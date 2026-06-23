import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Missing Authorization')

    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } }
    })

    const { data: { user } } = await supabaseClient.auth.getUser()
    if (!user) throw new Error('Unauthorized')

    const { tier } = await req.json()
    // Prices based on current dark_downloader subscription logic
    const amountStr = tier === 'pro_yearly' ? '15000' : '2000'

    // Use environment variables for API base to support staging/production
    const authBase = Deno.env.get('FIB_AUTH_BASE') ?? "https://fib-stage.fib.iq";
    const apiBase = Deno.env.get('FIB_API_BASE') ?? "https://fib.stage.fib.iq";

    // 1. Get Access Token
    const authRes = await fetch(`${authBase}/auth/realms/fib-online-shop/protocol/openid-connect/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: Deno.env.get('FIB_CLIENT_ID') ?? '',
        client_secret: Deno.env.get('FIB_CLIENT_SECRET') ?? '',
      }),
    })

    if (!authRes.ok) throw new Error(`FIB Auth Failed: ${await authRes.text()}`)
    const { access_token } = await authRes.json()

    // 2. Create Payment Request
    const paymentRes = await fetch(`${apiBase}/protected/v1/payments`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${access_token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        monetaryValue: { amount: amountStr, currency: 'IQD' },
        statusCallbackUrl: `${supabaseUrl}/functions/v1/fib-webhook`,
        description: `Premium Access - Dark Downloader`,
        redirectUri: "com.darkdownloader://payment-complete",
        expiresIn: 'PT1H',
        category: 'ECOMMERCE'
      }),
    })

    if (!paymentRes.ok) throw new Error(`FIB Payment Creation Failed: ${await paymentRes.text()}`)
    const paymentData = await paymentRes.json()

    // 3. Save pending transaction using Service Role Key
    const supabaseAdmin = createClient(supabaseUrl, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
    await supabaseAdmin.from('fib_pending_payments').insert({
      payment_id: paymentData.paymentId,
      user_id: user.id,
      tier: tier,
      amount_iqd: Number(amountStr),
    })

    return new Response(JSON.stringify({
      paymentId: paymentData.paymentId,
      qrCode: paymentData.qrCode,
      readableCode: paymentData.readableCode,
      personalAppLink: paymentData.personalAppLink,
      businessAppLink: paymentData.businessAppLink,
      validUntil: paymentData.validUntil
    }), {
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
