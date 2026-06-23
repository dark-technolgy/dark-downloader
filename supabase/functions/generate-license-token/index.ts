import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const { data: { user } } = await supabaseClient.auth.getUser()
    if (!user) throw new Error('Unauthorized')

    // 1. Check subscription status
    const { data: profile } = await supabaseClient
      .from('profiles')
      .select('subscription_tier, subscription_expires_at')
      .eq('id', user.id)
      .single()

    const isPro = profile?.subscription_tier === 'pro';
    const expires = profile?.subscription_expires_at;

    if (!isPro) throw new Error('Subscription required')

    // 2. Generate a secure, time-bound token for Rust
    // Format: user_id:expiry:secret_hash
    const expiry = expires ? new Date(expires).getTime() : Date.now() + 86400000;
    const secret = Deno.env.get('RUST_SECURITY_SECRET') ?? 'fallback_secret';

    const dataToSign = `${user.id}:${expiry}:${secret}`;
    const hashBuffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(dataToSign));
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    const token = `${user.id}:${expiry}:${hashHex}`;

    return new Response(JSON.stringify({ token }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
