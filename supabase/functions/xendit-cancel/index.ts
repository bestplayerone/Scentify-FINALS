import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.46.1';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json' },
});

const url = Deno.env.get('SUPABASE_URL')!;
const secret = Deno.env.get('XENDIT_SECRET_KEY');
const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

Deno.serve(async (request) => {
  if (request.method !== 'GET') return json({ error: 'Method not allowed.' }, 405);
  const orderId = new URL(request.url).searchParams.get('orderId');
  if (!secret || !orderId || orderId.length < 8 || orderId.length > 128) {
    return json({ error: 'Invalid payment cancellation request.' }, 400);
  }
  try {
    const { data: payment, error: lookupError } = await admin
      .from('payment_sessions')
      .select('provider_session_id')
      .eq('order_id', orderId)
      .maybeSingle();
    if (lookupError || !payment) return json({ error: 'Payment session not found.' }, 404);

    const response = await fetch(`https://api.xendit.co/sessions/${encodeURIComponent(payment.provider_session_id)}`, {
      headers: { accept: 'application/json', authorization: `Basic ${btoa(`${secret}:`)}` },
    });
    const session = await response.json();
    if (!response.ok || session.reference_id !== orderId) return json({ error: 'Payment cancellation could not be verified.' }, 409);
    if (session.status !== 'CANCELED' && session.status !== 'EXPIRED') return json({ received: true });

    const { error: releaseError } = await admin.rpc('release_xendit_payment', {
      p_event_id: `cancel-return:${payment.provider_session_id}:${session.status}`,
      p_session_id: payment.provider_session_id,
      p_status: session.status,
    });
    if (releaseError) throw releaseError;
    return json({ released: true });
  } catch (error) {
    console.error('xendit-cancel failed', error instanceof Error ? error.message : error);
    return json({ error: 'Payment cancellation could not be processed.' }, 500);
  }
});
