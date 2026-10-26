import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.46.1';

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
  if (request.method !== 'POST') return Response.json({ error: 'Method not allowed.' }, { status: 405 });
  let orderId: string | null = null;
  let client: ReturnType<typeof createClient> | null = null;
  try {
    const authorization = request.headers.get('authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return Response.json({ error: 'Sign in before starting payment.' }, { status: 401 });
    const token = authorization.slice(7).trim();
    client = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: auth, error: authError } = await client.auth.getUser(token);
    if (authError || !auth.user) return Response.json({ error: 'Sign in before starting payment.' }, { status: 401 });
    const data = await request.json();
    if (data?.paymentMethod !== 'gcash' || typeof data?.idempotencyKey !== 'string') return Response.json({ error: 'GCash payment details are invalid.' }, { status: 400 });
    const { data: order, error: orderError } = await client.rpc('create_online_payment_order', {
      p_idempotency_key: data.idempotencyKey,
      p_shipping_address: data.shippingAddress,
      p_delivery_option: data.deliveryOption,
      p_payment_method: 'gcash',
    });
    if (orderError) {
      console.error('create_online_payment_order failed', orderError.code, orderError.message);
      return Response.json({ error: checkoutError(orderError.code), code: orderError.code }, { status: 400 });
    }
    orderId = order.order_id;
    const secret = Deno.env.get('XENDIT_SECRET_KEY');
    if (!secret) throw new Error('Xendit is not configured.');
    const response = await fetch('https://api.xendit.co/sessions', {
      method: 'POST',
      headers: { accept: 'application/json', authorization: `Basic ${btoa(`${secret}:`)}`, 'content-type': 'application/json', 'idempotency-key': `scentify-${orderId}` },
      body: JSON.stringify({
        reference_id: orderId, session_type: 'PAY', mode: 'PAYMENT_LINK', amount: order.total_centavos / 100,
        currency: 'PHP', country: 'PH', locale: 'en', allow_save_payment_method: 'DISABLED',
        allowed_payment_channels: ['GCASH'], description: `Scentify order ${orderId}`,
        success_return_url: `${Deno.env.get('XENDIT_SUCCESS_URL') ?? 'https://scentify.app/payment/success'}?orderId=${encodeURIComponent(orderId)}`,
        cancel_return_url: `${Deno.env.get('XENDIT_CANCEL_URL') ?? `${url}/functions/v1/xendit-cancel`}?orderId=${encodeURIComponent(orderId)}`,
        metadata: { scentifyOrderId: orderId },
      }),
    });
    const payload = await response.json();
    if (!response.ok || typeof payload.payment_session_id !== 'string' || typeof payload.payment_link_url !== 'string') {
      console.error('Xendit session creation failed', response.status, payload?.error_code, payload?.message);
      const error = new Error(typeof payload?.message === 'string' ? payload.message : 'Xendit could not start checkout.');
      (error as Error & { status?: number; code?: string }).status = response.status;
      (error as Error & { status?: number; code?: string }).code = payload?.error_code;
      throw error;
    }
    const { error: recordError } = await client.rpc('record_xendit_session', {
      p_order_id: orderId, p_session_id: payload.payment_session_id, p_checkout_url: payload.payment_link_url,
      p_expires_at: payload.expires_at, p_amount_centavos: order.total_centavos,
    });
    if (recordError) throw new Error('Payment session could not be recorded.');
    return Response.json({ provider: 'xendit', reference: payload.payment_session_id, checkoutUrl: payload.payment_link_url });
  } catch (error) {
    if (orderId) {
      await client?.rpc('release_checkout_reservation', { p_order_id: orderId }).catch(() => undefined);
    }
    console.error('create-xendit-session failed', error);
    const details = error as Error & { status?: number; code?: string };
    const status = details.status && details.status >= 400 && details.status < 500 ? details.status : 500;
    return Response.json({ error: error instanceof Error ? error.message : 'Payment is temporarily unavailable.', code: details.code }, { status });
  }
});
