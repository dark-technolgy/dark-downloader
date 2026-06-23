import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { paymentId } = await req.json()
    if (!paymentId) return new Response('No payment ID', { status: 400 })

    console.log(`WEBHOOK: Received payment confirmation for ID: ${paymentId}`);

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAdmin = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const authBase = Deno.env.get('FIB_AUTH_BASE') ?? "https://fib-stage.fib.iq";
    const apiBase = Deno.env.get('FIB_API_BASE') ?? "https://fib.stage.fib.iq";

    // 1. Get Auth Token from FIB to verify status
    const authRes = await fetch(`${authBase}/auth/realms/fib-online-shop/protocol/openid-connect/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: Deno.env.get('FIB_CLIENT_ID') ?? '',
        client_secret: Deno.env.get('FIB_CLIENT_SECRET') ?? '',
      }),
    })

    const authData = await authRes.json()
    const access_token = authData.access_token
    if (!access_token) throw new Error('Failed to authenticate with FIB')

    // 2. Mandatory Verification with FIB Server
    const statusRes = await fetch(`${apiBase}/protected/v1/payments/${paymentId}/status`, {
      headers: { 'Authorization': `Bearer ${access_token}` }
    })

    const realStatusData = await statusRes.json()
    const realStatus = realStatusData.status // PAID, DECLINED, etc.

    console.log(`WEBHOOK: FIB Server status for ${paymentId} is ${realStatus}`);

    if (realStatus === 'PAID') {
      const { data: pending } = await supabaseAdmin
        .from('fib_pending_payments')
        .select('user_id, tier')
        .eq('payment_id', paymentId)
        .maybeSingle()

      if (pending) {
        const subscription_tier = pending.tier.includes('pro') ? 'pro' : 'premium';

        // CRITICAL FIX: Use upsert instead of update in case profiles row is missing
        const { error: profileErr } = await supabaseAdmin
          .from('profiles')
          .upsert({
            id: pending.user_id,
            subscription_tier: subscription_tier,
            subscription_status: 'active',
            subscription_expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
            updated_at: new Date().toISOString()
          })

        if (profileErr) console.error(`WEBHOOK_ERROR: Profile update failed: ${profileErr.message}`);

        await supabaseAdmin
          .from('fib_pending_payments')
          .update({ status: 'PAID' })
          .eq('payment_id', paymentId)

        await supabaseAdmin.from('audit_logs').insert({
          user_id: pending.user_id,
          action: 'FIB_PAYMENT_SUCCESS',
          metadata: { paymentId, tier: pending.tier }
        })

        console.log(`WEBHOOK: Successfully activated ${subscription_tier} for user ${pending.user_id}`);
      } else {
        console.error(`WEBHOOK_ERROR: No pending payment record found for ${paymentId}`);
      }
    }

    return new Response(JSON.stringify({ received: true }), { status: 200 })
  } catch (error) {
    console.error('WEBHOOK_ERROR:', error.message)
    return new Response('Webhook Error', { status: 400 })
  }
})
