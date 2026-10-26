const API = 'https://api.xendit.co/sessions';

export class XenditRequestError extends Error {
  constructor(public readonly status: number, public readonly code: string | undefined, message: string) {
    super(message);
  }
}

export async function createXenditSession(input: {
  orderId: string;
  amountCentavos: number;
  paymentMethod: string;
  successUrl: string;
  cancelUrl: string;
}) {
  const secret = Deno.env.get('XENDIT_SECRET_KEY');
  if (!secret) throw new Error('Xendit is not configured.');
  const response = await fetch(API, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      authorization: `Basic ${btoa(`${secret}:`)}`,
      'content-type': 'application/json',
      'idempotency-key': `scentify-${input.orderId}`,
    },
    body: JSON.stringify({
      reference_id: input.orderId,
      session_type: 'PAY',
      mode: 'PAYMENT_LINK',
      amount: input.amountCentavos / 100,
      currency: 'PHP',
      country: 'PH',
      locale: 'en',
      allow_save_payment_method: 'DISABLED',
      allowed_payment_channels: [input.paymentMethod === 'gcash' ? 'GCASH' : input.paymentMethod.toUpperCase()],
      description: `Scentify order ${input.orderId}`,
      success_return_url: input.successUrl,
      cancel_return_url: input.cancelUrl,
      metadata: { scentifyOrderId: input.orderId },
    }),
  });
  const payload = await response.json();
  if (!response.ok || typeof payload.payment_session_id !== 'string' || typeof payload.payment_link_url !== 'string') {
    console.error('Xendit session creation failed', response.status, payload?.error_code, payload?.message);
    throw new XenditRequestError(
      response.status,
      typeof payload?.error_code === 'string' ? payload.error_code : undefined,
      typeof payload?.message === 'string' ? payload.message : 'Xendit could not start checkout.',
    );
  }
  return payload;
}
