import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.46.1';
import { eventId, json } from '../_shared/http.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const callbackToken = Deno.env.get('XENDIT_WEBHOOK_TOKEN');

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);
  if (!callbackToken || request.headers.get('x-callback-token') !== callbackToken) return json({ error: 'Unauthorized.' }, 401);
  const raw = await request.text();
  try {
    const body = JSON.parse(raw);
    const session = body?.data;
    const sessionId = session?.payment_session_id;
    const orderId = session?.reference_id;
    if (typeof sessionId !== 'string' || typeof orderId !== 'string') return json({ error: 'Invalid webhook.' }, 400);
    const id = `${await eventId(raw)}:${body.created ?? ''}`;
    if (body.event === 'payment_session.completed' && session.status === 'COMPLETED') {
      const { error } = await admin.rpc('settle_xendit_payment', {
        p_event_id: id,
        p_session_id: sessionId,
        p_amount_centavos: Math.round(Number(session.amount) * 100),
        p_currency: session.currency,
        p_status: session.status,
        p_payment_id: session.payment_id ?? null,
      });
      if (error) throw error;
    } else if (body.event === 'payment_session.expired') {
      const { error } = await admin.rpc('release_xendit_payment', {
        p_event_id: id, p_session_id: sessionId, p_status: session.status,
      });
      if (error) throw error;
    }
    return json({ received: true });
  } catch (error) {
    console.error('xendit-webhook failed', error);
    return json({ error: 'Webhook processing failed.' }, 500);
  }
});
