import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.46.1';
import { bearer, json } from '../_shared/http.ts';
import { createXenditSession, XenditRequestError } from '../_shared/xendit.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;

function checkoutError(code: string | undefined) {
  return code === '23514'
    ? 'Some items are no longer available in the requested quantity.'
    : code === '22023'
      ? 'Review the delivery details and try again.'
      : code === '42501'
        ? 'Your session expired. Sign in again before placing the order.'
        : 'We could not create the payment order.';
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);
  let orderId: string | null = null;
  let userClient: ReturnType<typeof createClient> | null = null;
  try {
    const token = bearer(request);
    userClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: auth, error: authError } = await userClient.auth.getUser(token);
    if (authError || !auth.user) return json({ error: 'Sign in before starting payment.' }, 401);
    const data = await request.json();
    if (data?.paymentMethod !== 'gcash' || typeof data?.idempotencyKey !== 'string') {
      return json({ error: 'GCash payment details are invalid.' }, 400);
    }
    const { data: order, error: orderError } = await userClient.rpc('create_online_payment_order', {
      p_idempotency_key: data.idempotencyKey,
      p_shipping_address: data.shippingAddress,
      p_delivery_option: data.deliveryOption,
      p_payment_method: 'gcash',
    });
    if (orderError) {
      console.error('create_online_payment_order failed', orderError.code, orderError.message);
      return json({ error: checkoutError(orderError.code), code: orderError.code }, 400);
    }
    orderId = order.order_id as string;
    const payload = await createXenditSession({
      orderId,
      amountCentavos: order.total_centavos as number,
      paymentMethod: 'gcash',
      successUrl: `${Deno.env.get('XENDIT_SUCCESS_URL') ?? 'https://scentify.app/payment/success'}?orderId=${encodeURIComponent(orderId)}`,
      cancelUrl: `${Deno.env.get('XENDIT_CANCEL_URL') ?? 'https://scentify.app/payment/cancel'}?orderId=${encodeURIComponent(orderId)}`,
    });
    const { error: recordError } = await userClient.rpc('record_xendit_session', {
      p_order_id: orderId,
      p_session_id: payload.payment_session_id,
      p_checkout_url: payload.payment_link_url,
      p_expires_at: payload.expires_at,
      p_amount_centavos: order.total_centavos,
    });
    if (recordError) throw new Error('Payment session could not be recorded.');
    return json({ provider: 'xendit', reference: payload.payment_session_id, checkoutUrl: payload.payment_link_url });
  } catch (error) {
    if (orderId) {
      await userClient?.rpc('release_checkout_reservation', { p_order_id: orderId });
    }
    console.error('create-xendit-session failed', error);
    if (error instanceof XenditRequestError) {
      return json({ error: error.message, code: error.code }, error.status >= 400 && error.status < 500 ? error.status : 502);
    }
    return json({ error: error instanceof Error ? error.message : 'Payment is temporarily unavailable.' }, 500);
  }
});
