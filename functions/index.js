const crypto = require('node:crypto');

const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { defineSecret } = require('firebase-functions/params');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { HttpsError, onCall, onRequest } = require('firebase-functions/v2/https');

initializeApp();

const db = getFirestore();
const REGION = 'asia-southeast1';
const PAYMONGO_API = 'https://api.paymongo.com/v2/checkout_sessions';
const XENDIT_API = 'https://api.xendit.co/sessions';
const XENDIT_SECRET_KEY = defineSecret('XENDIT_SECRET_KEY');
const XENDIT_WEBHOOK_TOKEN = defineSecret('XENDIT_WEBHOOK_TOKEN');
const CHECKOUT_INTENT_TTL_MS = 30 * 60 * 1000;
const CHECKOUT_CLAIM_TTL_MS = 60 * 1000;
const PAYMONGO_SIGNATURE_MAX_AGE_SECONDS = 10 * 60;
const MAX_ORDER_ITEMS = 100;
const MAX_CART_ITEMS = 100;
const MAX_RATING_COMMENT_LENGTH = 1000;
const SESSION_COOKIE_NAME = 'scentify_session';
const SESSION_COOKIE_MAX_AGE_SECONDS = 5 * 24 * 60 * 60;
const NCR_PROVINCE_NAMES = new Set(['metro manila', 'national capital region', 'ncr']);
const NCR_LGU_NAMES = new Set([
  'caloocan', 'las pinas', 'makati', 'malabon', 'mandaluyong', 'manila', 'marikina',
  'muntinlupa', 'navotas', 'paranaque', 'pasay', 'pasig', 'pateros', 'quezon',
  'san juan', 'taguig', 'valenzuela',
]);

const paymentMethodMap = Object.freeze({
  gcash: 'gcash',
  maya: 'paymaya',
  card: 'card',
});

exports.createPayMongoCheckoutSession = onCall(
  { region: REGION, timeoutSeconds: 30, enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Sign in before starting payment.');
    }
    await enforceRateLimit(`payment:${userId}`, {
      limit: 5,
      windowMs: 60 * 1000,
      message: 'Too many payment attempts. Try again in a minute.',
    });

    const data = asMap(request.data);
    assertAllowedKeys(data, [
      'orderId', 'amountCentavos', 'currency', 'paymentMethod', 'supportedMethods',
    ]);
    const orderId = readId(data.orderId, 'orderId');
    const amountCentavos = readInteger(data.amountCentavos, 'amountCentavos');
    const currency = readEnum(data.currency ?? 'PHP', ['PHP'], 'currency');
    const paymentMethod = readOnlinePaymentMethod(data.paymentMethod ?? 'gcash');
    const supportedMethods = readSupportedPaymentMethods(data.supportedMethods);
    const secretKey = process.env.PAYMONGO_SECRET_KEY;

    if (!secretKey) {
      throw new HttpsError(
        'failed-precondition',
        'PayMongo test mode is not configured on the backend yet.',
      );
    }
    if (amountCentavos < 100 || amountCentavos > 100_000_000) {
      throw new HttpsError('invalid-argument', 'Payment amount or order is invalid.');
    }
    if (!supportedMethods.includes(paymentMethod)) {
      throw new HttpsError(
        'invalid-argument',
        'The selected payment method must be in supportedMethods.',
      );
    }

    const reviewRef = db.collection('orderReviews').doc(orderId);
    const reviewSnapshot = await reviewRef.get();
    const review = reviewSnapshot.data() || {};
    const reviewExpiresAt = asDate(review.expiresAt);
    if (!reviewSnapshot.exists || review.orderId !== orderId || review.userId !== userId ||
        review.status !== 'ready' || !reviewExpiresAt || reviewExpiresAt.getTime() <= Date.now() ||
        review.totalCentavos !== amountCentavos || review.paymentMethod !== paymentMethod ||
        review.currency !== currency) {
      throw new HttpsError(
        'failed-precondition',
        'Refresh the order review before starting payment.',
      );
    }

    const orderRef = db.collection('orders').doc(orderId);
    const existingOrder = await orderRef.get();
    if (existingOrder.exists) {
      const order = existingOrder.data() || {};
      if (order.userId !== userId) {
        throw new HttpsError('permission-denied', 'That order does not belong to you.');
      }
      if (
        order.id !== orderId || order.status !== 'pending_payment' ||
        order.totalCentavos !== amountCentavos ||
        order.subtotalCentavos !== review.subtotalCentavos ||
        order.deliveryFeeCentavos !== review.deliveryFeeCentavos ||
        JSON.stringify(order.items) !== JSON.stringify(review.orderItems) ||
        JSON.stringify(order.shippingAddress) !== JSON.stringify(review.shippingAddress) ||
        JSON.stringify(order.deliveryOption) !== JSON.stringify(review.deliveryOption) ||
        (order.paymentMethod != null && order.paymentMethod !== paymentMethod)
      ) {
        throw new HttpsError('failed-precondition', 'The order does not match its reviewed quote.');
      }
    }

    const intentRef = db.collection('checkoutIntents').doc(orderId);
    const quoteFingerprint = checkoutQuoteFingerprint(review, amountCentavos, currency, paymentMethod);
    const claim = await claimCheckoutIntent(intentRef, {
      orderId,
      userId,
      amountCentavos,
      currency,
      paymentMethod,
      reviewId: orderId,
      quoteFingerprint,
    });
    if (claim.existing) return { ...claim.existing, paymentMethod, orderCreatedOnServer: true };

    const paymentMethodType = paymentMethodMap[paymentMethod];
    let session;
    try {
      const response = await fetch(PAYMONGO_API, {
        method: 'POST',
        headers: {
          accept: 'application/json',
          authorization: `Basic ${Buffer.from(`${secretKey}:`).toString('base64')}`,
          'content-type': 'application/json',
          'idempotency-key': `scentify-${orderId}-${quoteFingerprint}`,
        },
        body: JSON.stringify({
          data: {
            attributes: {
              line_items: [
                {
                  name: `Scentify order ${orderId}`,
                  amount: amountCentavos,
                  currency,
                  quantity: 1,
                },
              ],
              payment_method_types: [paymentMethodType],
              reference_number: orderId,
              metadata: {
                scentifyOrderId: orderId,
                scentifyUserId: userId,
                scentifyPaymentMethod: paymentMethod,
              },
              description: 'Scentify perfume order',
              success_url: `${process.env.PAYMONGO_SUCCESS_URL || 'https://scentify.app/payment/success'}?orderId=${encodeURIComponent(orderId)}`,
              cancel_url: `${process.env.PAYMONGO_CANCEL_URL || 'https://scentify.app/payment/cancel'}?orderId=${encodeURIComponent(orderId)}`,
            },
          },
        }),
      });

      const payload = await response.json();
      if (!response.ok) {
        console.error('PayMongo checkout creation failed', response.status, payload);
        throw new HttpsError('failed-precondition', 'PayMongo could not start checkout.');
      }
      session = payload?.data;
      if (typeof session?.id !== 'string' || !isHttpsUrl(session?.attributes?.checkout_url)) {
        throw new HttpsError('internal', 'PayMongo returned an incomplete checkout session.');
      }

      const expiresAt = new Date(Date.now() + CHECKOUT_INTENT_TTL_MS);
      await placeXenditOrder({
        orderId,
        userId,
        intentRef,
        claimToken: claim.claimToken,
        session: {
          providerReference: session.id,
          paymentReference: session.id,
          checkoutUrl: session.attributes.checkout_url,
          expiresAt,
        },
        provider: 'paymongo',
      });
    } catch (error) {
      await releaseCheckoutClaim(intentRef, claim.claimToken);
      if (error instanceof HttpsError) throw error;
      console.error('PayMongo checkout creation failed', error);
      throw new HttpsError('unavailable', 'PayMongo could not start checkout.');
    }

    return {
      provider: 'paymongo',
      reference: session.id,
      checkoutUrl: session.attributes.checkout_url,
      paymentMethod,
      orderCreatedOnServer: true,
    };
  },
);

function checkoutQuoteFingerprint(review, amountCentavos, currency, paymentMethod) {
  return crypto.createHash('sha256').update(JSON.stringify({
    amountCentavos,
    currency,
    paymentMethod,
    orderItems: review.orderItems,
    shippingAddress: review.shippingAddress,
    deliveryOption: review.deliveryOption,
  })).digest('hex').slice(0, 32);
}

async function claimCheckoutIntent(intentRef, quote, provider = 'paymongo') {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(intentRef);
    const now = Date.now();
    if (snapshot.exists) {
      const intent = snapshot.data() || {};
      if (intent.userId !== quote.userId || intent.orderId !== quote.orderId) {
        throw new HttpsError('permission-denied', 'That checkout intent is not yours.');
      }
      if (
        intent.amountCentavos !== quote.amountCentavos || intent.currency !== quote.currency ||
        intent.paymentMethod !== quote.paymentMethod || intent.provider !== provider ||
        intent.reviewId !== quote.reviewId ||
        (intent.quoteFingerprint != null && intent.quoteFingerprint !== quote.quoteFingerprint)
      ) {
        throw new HttpsError('failed-precondition', 'The checkout intent does not match its reviewed quote.');
      }
      if (
        intent.status === 'pending' &&
        typeof intent.providerReference === 'string' &&
        intent.paymentReference === intent.providerReference &&
        isHttpsUrl(intent.checkoutUrl) &&
        asDate(intent.expiresAt)?.getTime() > now
      ) {
        return {
          existing: {
            provider,
            reference: intent.providerReference,
            checkoutUrl: intent.checkoutUrl,
          },
        };
      }
      if (intent.status === 'paid') {
        throw new HttpsError('already-exists', 'This checkout has already been paid.');
      }
      if (intent.status === 'manual_review') {
        throw new HttpsError('failed-precondition', 'This checkout requires manual review.');
      }
      if (intent.status === 'creating' && asDate(intent.claimExpiresAt)?.getTime() > now) {
        throw new HttpsError('aborted', 'Payment session is already being created. Try again shortly.');
      }
    }

    const claimToken = crypto.randomBytes(18).toString('hex');
    transaction.set(intentRef, {
      ...quote,
      provider,
      status: 'creating',
      claimToken,
      claimExpiresAt: new Date(now + CHECKOUT_CLAIM_TTL_MS),
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { claimToken };
  });
}

exports.createXenditCheckoutSession = onCall(
  { region: REGION, timeoutSeconds: 30, enforceAppCheck: true, secrets: [XENDIT_SECRET_KEY] },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new HttpsError('unauthenticated', 'Sign in before starting payment.');
    await enforceRateLimit(`payment:${userId}`, {
      limit: 5,
      windowMs: 60 * 1000,
      message: 'Too many payment attempts. Try again in a minute.',
    });
    const data = asMap(request.data);
    assertAllowedKeys(data, ['orderId', 'amountCentavos', 'currency', 'paymentMethod', 'supportedMethods']);
    const orderId = readId(data.orderId, 'orderId');
    const amountCentavos = readInteger(data.amountCentavos, 'amountCentavos');
    const currency = readEnum(data.currency ?? 'PHP', ['PHP'], 'currency');
    const paymentMethod = readOnlinePaymentMethod(data.paymentMethod ?? 'gcash');
    const supportedMethods = readSupportedPaymentMethods(data.supportedMethods);
    const secretKey = XENDIT_SECRET_KEY.value() || process.env.XENDIT_SECRET_KEY;
    if (!secretKey) throw new HttpsError('failed-precondition', 'Xendit test mode is not configured on the backend yet.');
    if (amountCentavos < 100 || amountCentavos > 100_000_000 || !supportedMethods.includes(paymentMethod)) {
      throw new HttpsError('invalid-argument', 'Payment amount or order is invalid.');
    }
    const reviewSnapshot = await db.collection('orderReviews').doc(orderId).get();
    const review = reviewSnapshot.data() || {};
    const reviewExpiresAt = asDate(review.expiresAt);
    if (!reviewSnapshot.exists || review.orderId !== orderId || review.userId !== userId ||
        review.status !== 'ready' || !reviewExpiresAt || reviewExpiresAt.getTime() <= Date.now() ||
        review.totalCentavos !== amountCentavos || review.paymentMethod !== paymentMethod || review.currency !== currency) {
      throw new HttpsError('failed-precondition', 'Refresh the order review before starting payment.');
    }
    const orderSnapshot = await db.collection('orders').doc(orderId).get();
    if (orderSnapshot.exists) {
      const order = orderSnapshot.data() || {};
      if (order.userId !== userId) throw new HttpsError('permission-denied', 'That order does not belong to you.');
      if (order.id !== orderId || order.status !== 'pending_payment' || order.totalCentavos !== amountCentavos ||
          order.subtotalCentavos !== review.subtotalCentavos || order.deliveryFeeCentavos !== review.deliveryFeeCentavos ||
          JSON.stringify(order.items) !== JSON.stringify(review.orderItems) ||
          JSON.stringify(order.shippingAddress) !== JSON.stringify(review.shippingAddress) ||
          JSON.stringify(order.deliveryOption) !== JSON.stringify(review.deliveryOption) ||
          (order.paymentMethod != null && order.paymentMethod !== paymentMethod)) {
        throw new HttpsError('failed-precondition', 'The order does not match its reviewed quote.');
      }
    }
    const intentRef = db.collection('checkoutIntents').doc(orderId);
    const quoteFingerprint = checkoutQuoteFingerprint(review, amountCentavos, currency, paymentMethod);
    const claim = await claimCheckoutIntent(intentRef, {
      orderId, userId, amountCentavos, currency, paymentMethod, reviewId: orderId, quoteFingerprint,
    }, 'xendit');
    if (claim.existing) return { ...claim.existing, paymentMethod, orderCreatedOnServer: true };
    try {
      await validateXenditInventory(review.orderItems);
      const response = await fetch(XENDIT_API, {
        method: 'POST',
        headers: {
          accept: 'application/json',
          authorization: `Basic ${Buffer.from(`${secretKey}:`).toString('base64')}`,
          'content-type': 'application/json',
          'idempotency-key': `scentify-${orderId}-${quoteFingerprint}`,
        },
        body: JSON.stringify({
          reference_id: orderId,
          session_type: 'PAY',
          mode: 'PAYMENT_LINK',
          amount: amountCentavos / 100,
          currency,
          country: 'PH',
          locale: 'en',
          allow_save_payment_method: 'DISABLED',
          allowed_payment_channels: supportedMethods.map((method) => ({ gcash: 'GCASH', maya: 'PAYMAYA', card: 'CARDS' })[method]),
          description: 'Scentify perfume order',
          metadata: { scentifyOrderId: orderId, scentifyUserId: userId, scentifyPaymentMethod: paymentMethod },
          success_return_url: `${process.env.XENDIT_SUCCESS_URL || 'https://scentify.app/payment/success'}?orderId=${encodeURIComponent(orderId)}`,
          cancel_return_url: `${process.env.XENDIT_CANCEL_URL || 'https://scentify.app/payment/cancel'}?orderId=${encodeURIComponent(orderId)}`,
        }),
      });
      const payload = await response.json();
      if (!response.ok || typeof payload?.payment_session_id !== 'string' || !isHttpsUrl(payload?.payment_link_url)) {
        console.error('Xendit checkout creation failed', response.status, payload);
        throw new HttpsError('failed-precondition', 'Xendit could not start checkout.');
      }
      const expiresAt = asDate(payload.expires_at) || new Date(Date.now() + CHECKOUT_INTENT_TTL_MS);
      const session = {
        providerReference: payload.payment_session_id,
        paymentReference: payload.payment_session_id,
        checkoutUrl: payload.payment_link_url,
        expiresAt,
      };
      await placeXenditOrder({
        orderId,
        userId,
        intentRef,
        claimToken: claim.claimToken,
        session,
      });
      return {
        provider: 'xendit',
        reference: payload.payment_session_id,
        checkoutUrl: payload.payment_link_url,
        paymentMethod,
        orderCreatedOnServer: true,
      };
    } catch (error) {
      await releaseCheckoutClaim(intentRef, claim.claimToken);
      if (error instanceof HttpsError) throw error;
      console.error('Xendit checkout creation failed', error);
      throw new HttpsError('unavailable', 'Xendit could not start checkout.');
    }
  },
);

async function validateXenditInventory(items) {
  const productIds = [...new Set(items.map((item) => item.productId))];
  const snapshots = await Promise.all(productIds.map((id) => db.collection('perfumes').doc(id).get()));
  const products = new Map(snapshots.map((snapshot, index) => [productIds[index], snapshot.data() || {}]));
  for (const item of items) {
    const product = products.get(item.productId);
    const variant = product?.variants?.find((candidate) => candidate?.id === item.variantId);
    if (product?.isPublished !== true || !variant || !Number.isInteger(variant.stock) ||
        variant.stock < item.quantity || variant.priceCentavos !== item.unitPriceCentavos) {
      throw new HttpsError('failed-precondition', 'A selected item is no longer available in the reviewed quantity and price.');
    }
  }
}

async function placeXenditOrder({ orderId, userId, intentRef, claimToken, session, provider = 'xendit' }) {
  const reviewRef = db.collection('orderReviews').doc(orderId);
  const orderRef = db.collection('orders').doc(orderId);
  const cartRef = db.collection('carts').doc(userId);
  const reservationRef = db.collection('inventoryReservations').doc(orderId);
  return db.runTransaction(async (transaction) => {
    const [intentSnapshot, reviewSnapshot, cartSnapshot, orderSnapshot, reservationSnapshot] =
      await Promise.all([
        transaction.get(intentRef),
        transaction.get(reviewRef),
        transaction.get(cartRef),
        transaction.get(orderRef),
        transaction.get(reservationRef),
      ]);
    const intent = intentSnapshot.data() || {};
    const review = reviewSnapshot.data() || {};
    if (!intentSnapshot.exists || intent.status !== 'creating' || intent.claimToken !== claimToken ||
        intent.orderId !== orderId || intent.userId !== userId || !reviewSnapshot.exists ||
        review.status !== 'ready' || review.userId !== userId || review.orderId !== orderId ||
        review.paymentMethod !== intent.paymentMethod || review.currency !== intent.currency ||
        review.totalCentavos !== intent.amountCentavos || !asDate(review.expiresAt) ||
        asDate(review.expiresAt).getTime() <= Date.now()) {
      throw new HttpsError('failed-precondition', 'The checkout review is no longer valid.');
    }
    if (!Array.isArray(review.orderItems) || review.orderItems.length < 1 ||
        review.orderItems.length > MAX_ORDER_ITEMS ||
        !review.orderItems.every(isReviewOrderItem) || hasDuplicateCartVariants(review.orderItems)) {
      throw new HttpsError('failed-precondition', 'The reviewed order contains invalid items.');
    }
    if (reservationSnapshot.exists) {
      const reservation = reservationSnapshot.data() || {};
      if (!['reserved', 'committed'].includes(reservation.status)) {
        throw new HttpsError('failed-precondition', 'This inventory reservation is no longer active.');
      }
      if (!orderSnapshot.exists) {
        throw new HttpsError('failed-precondition', 'The reserved order could not be loaded.');
      }
      transaction.update(intentRef, {
        status: 'pending', ...session, claimToken: null, claimExpiresAt: null,
      });
      return;
    }

    const cart = cartSnapshot.data() || {};
    if (!cartSnapshot.exists || cart.userId !== userId || !Array.isArray(cart.items) ||
        !cart.items.every(isCartItem) || hasDuplicateCartVariants(cart.items)) {
      throw new HttpsError('failed-precondition', 'Your cart changed. Review it again.');
    }
    for (const item of review.orderItems) {
      const cartItem = cart.items.find((candidate) =>
        candidate.productId === item.productId && candidate.variantId === item.variantId,
      );
      if (!cartItem || cartItem.quantity < item.quantity) {
        throw new HttpsError('failed-precondition', 'Your cart changed. Review it again.');
      }
    }

    const productIds = [...new Set(review.orderItems.map((item) => item.productId))];
    const productRefs = productIds.map((productId) => db.collection('perfumes').doc(productId));
    const productSnapshots = await Promise.all(productRefs.map((reference) => transaction.get(reference)));
    const products = new Map(productSnapshots.map((snapshot, index) => [
      productIds[index], { ref: productRefs[index], data: snapshot.data() || {} },
    ]));
    const updatedVariants = new Map();
    for (const item of review.orderItems) {
      const product = products.get(item.productId);
      if (!product || product.data.isPublished !== true || !Array.isArray(product.data.variants)) {
        throw new HttpsError('failed-precondition', 'A selected product is no longer available.');
      }
      const variants = updatedVariants.get(item.productId) || [...product.data.variants];
      const variantIndex = variants.findIndex((variant) => variant?.id === item.variantId);
      const variant = variants[variantIndex];
      if (!variant || !Number.isInteger(variant.priceCentavos) ||
          !Number.isInteger(variant.stock) || variant.stock < item.quantity ||
          variant.priceCentavos !== item.unitPriceCentavos) {
        throw new HttpsError('failed-precondition', 'A selected item is no longer available in the reviewed quantity and price.');
      }
      variants[variantIndex] = { ...variant, stock: variant.stock - item.quantity };
      updatedVariants.set(item.productId, variants);
    }

    if (orderSnapshot.exists) {
      const order = orderSnapshot.data() || {};
      if (order.userId !== userId || order.status !== 'pending_payment' ||
          order.totalCentavos !== review.totalCentavos ||
          JSON.stringify(order.items) !== JSON.stringify(review.orderItems)) {
        throw new HttpsError('failed-precondition', 'The existing order does not match its reviewed quote.');
      }
    }
    for (const [productId, variants] of updatedVariants) {
      transaction.update(products.get(productId).ref, { variants });
    }
    const adjustments = review.orderItems.map((item) => ({
      ref: db.collection('inventoryAdjustments').doc(),
      item,
    }));
    for (const { ref, item } of adjustments) {
      transaction.create(ref, {
        productId: item.productId,
        variantId: item.variantId,
        orderId,
        actorId: `checkout:${userId}`,
        delta: -item.quantity,
        reason: `${provider} order reservation`,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.create(reservationRef, {
      orderId,
      userId,
      provider,
      status: 'reserved',
      items: review.orderItems.map(({ productId, variantId, quantity }) => ({
        productId, variantId, quantity,
      })),
      expiresAt: session.expiresAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (!orderSnapshot.exists) {
      transaction.create(orderRef, {
        id: orderId,
        userId,
        items: review.orderItems,
        shippingAddress: review.shippingAddress,
        deliveryOption: review.deliveryOption,
        subtotalCentavos: review.subtotalCentavos,
        deliveryFeeCentavos: review.deliveryFeeCentavos,
        totalCentavos: review.totalCentavos,
        status: 'pending_payment',
        paymentReference: session.paymentReference,
        paymentMethod: intent.paymentMethod,
        paymentStatus: 'pending',
        paymentProvider: provider,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        events: [],
      });
    }
    const selected = new Map(review.orderItems.map((item) => [
      `${item.productId}|${item.variantId}`, item,
    ]));
    const remainingItems = cart.items.flatMap((item) => {
      const selectedItem = selected.get(`${item.productId}|${item.variantId}`);
      if (!selectedItem) return [item];
      const remaining = item.quantity - selectedItem.quantity;
      return remaining > 0 ? [{ ...item, quantity: remaining }] : [];
    });
    if (remainingItems.length) {
      transaction.set(cartRef, {
        userId, items: remainingItems, updatedAt: FieldValue.serverTimestamp(),
        serverConfirmed: true, lastOperationId: `${provider}-${orderId}`,
        serverConfirmedAt: FieldValue.serverTimestamp(),
      });
    } else {
      transaction.delete(cartRef);
    }
    transaction.update(intentRef, {
      status: 'pending', ...session, claimToken: null, claimExpiresAt: null,
    });
  });
}

async function releaseCheckoutClaim(intentRef, claimToken) {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(intentRef);
    const intent = snapshot.data() || {};
    if (!snapshot.exists || intent.status !== 'creating' || intent.claimToken !== claimToken) return;
    transaction.update(intentRef, {
      status: 'failed',
      claimToken: null,
      claimExpiresAt: null,
      failedAt: FieldValue.serverTimestamp(),
    });
  });
}

// Optional web-session bridge. Mobile clients continue to use Firebase Auth;
// browser clients can exchange a short-lived ID token for a hardened cookie
// without ever receiving an Admin credential.
exports.sessionCookie = onRequest(
  { region: REGION, timeoutSeconds: 15 },
  async (request, response) => {
    if (request.method === 'DELETE') {
      response.setHeader('Set-Cookie', serializeCookie('', 0));
      response.status(204).send();
      return;
    }
    if (request.method !== 'POST') {
      response.sendStatus(405);
      return;
    }

    const authorization = request.get('Authorization') || '';
    const match = authorization.match(/^Bearer\s+(.+)$/i);
    const token = match?.[1]?.trim();
    if (!token || token.length > 8192) {
      response.status(401).json({ error: 'unauthenticated' });
      return;
    }
    try {
      const decoded = await getAuth().verifyIdToken(token, true);
      await enforceRateLimit(`session:${decoded.uid}:${requestIp(request)}`, {
        limit: 10,
        windowMs: 60 * 1000,
        message: 'Too many session requests.',
      });
      const expiresIn = SESSION_COOKIE_MAX_AGE_SECONDS * 1000;
      const cookie = await getAuth().createSessionCookie(token, { expiresIn });
      response.setHeader(
        'Set-Cookie',
        serializeCookie(cookie, SESSION_COOKIE_MAX_AGE_SECONDS),
      );
      response.status(200).json({
        ok: true,
        userId: decoded.uid,
        expiresAt: new Date(Date.now() + expiresIn).toISOString(),
      });
    } catch (error) {
      console.error('Session cookie creation failed', error?.code || error?.message || error);
      if (error?.code === 'resource-exhausted') {
        const retryAfter = Number(error.details?.retryAfterSeconds || 60);
        response.setHeader('Retry-After', String(retryAfter));
        response.status(429).json({ error: 'resource-exhausted' });
        return;
      }
      response.status(401).json({ error: 'unauthenticated' });
    }
  },
);

exports.listMyPurchases = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Sign in to view purchases.');
    }
    await enforceRateLimit(`purchases:${userId}`, {
      limit: 30,
      windowMs: 60 * 1000,
      message: 'Too many purchase refreshes. Try again shortly.',
    });
    const data = asMap(request.data || {});
    assertAllowedKeys(data, ['limit', 'cursor']);
    const limit = data.limit == null ? 50 : readInteger(data.limit, 'limit');
    if (limit < 1 || limit > 100) {
      throw new HttpsError('invalid-argument', 'limit must be between 1 and 100.');
    }
    const cursor = readPurchaseCursor(data.cursor);

    let query = db.collection('orders')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc');
    if (cursor) query = query.startAfter(cursor.createdAt);
    const snapshot = await query.limit(limit + 1).get();
    const documents = snapshot.docs.slice(0, limit);
    const purchases = documents.map((document) => mapPurchase(document.id, document.data()));
    const hasMore = snapshot.docs.length > limit;
    return {
      purchases,
      nextCursor: hasMore
        ? encodePurchaseCursor(documents.at(-1)?.data()?.createdAt)
        : null,
    };
  },
);

exports.submitProductRating = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Sign in before rating a product.');
    }
    await enforceRateLimit(`rating:${userId}`, {
      limit: 10,
      windowMs: 60 * 60 * 1000,
      message: 'Too many rating submissions. Try again later.',
    });
    const data = asMap(request.data);
    assertAllowedKeys(data, [
      'orderId', 'productId', 'variantId', 'rating', 'title', 'comment',
    ]);
    const orderId = readId(data.orderId, 'orderId');
    const productId = readId(data.productId, 'productId');
    const variantId = readId(data.variantId, 'variantId');
    const rating = readInteger(data.rating, 'rating');
    if (rating < 1 || rating > 5) {
      throw new HttpsError('invalid-argument', 'rating must be an integer from 1 to 5.');
    }
    const title = readString(data.title, 'title', {
      maxLength: 120,
      required: false,
    }) || '';
    const comment = readString(data.comment, 'comment', {
      maxLength: MAX_RATING_COMMENT_LENGTH,
      required: false,
    }) || '';

    const reviewId = makeReviewId(orderId, productId, variantId);
    const orderRef = db.collection('orders').doc(orderId);
    const productRef = db.collection('perfumes').doc(productId);
    const reviewRef = productRef.collection('ratings').doc(reviewId);
    const nowIso = new Date().toISOString();

    await db.runTransaction(async (transaction) => {
      const orderSnapshot = await transaction.get(orderRef);
      const reviewSnapshot = await transaction.get(reviewRef);
      const productSnapshot = await transaction.get(productRef);
      if (!orderSnapshot.exists) {
        throw new HttpsError('not-found', 'The purchase does not exist.');
      }
      if (reviewSnapshot.exists) {
        throw new HttpsError('already-exists', 'This purchase item was already rated.');
      }
      const order = orderSnapshot.data() || {};
      if (order.userId !== userId || order.status !== 'delivered') {
        throw new HttpsError(
          'failed-precondition',
          'Only delivered purchases can be rated by their owner.',
        );
      }
      const matchingItem = Array.isArray(order.items)
        ? order.items.find((item) => item?.productId === productId && item?.variantId === variantId)
        : null;
      if (!matchingItem) {
        throw new HttpsError(
          'failed-precondition',
          'The rated variant was not part of this purchase.',
        );
      }
      if (!productSnapshot.exists) {
        throw new HttpsError('not-found', 'The rated product no longer exists.');
      }

      const product = productSnapshot.data() || {};
      const currentSum = Number.isInteger(product.ratingSum) ? product.ratingSum : 0;
      const currentCount = Number.isInteger(product.reviewCount) ? product.reviewCount : 0;
      const distribution = ratingDistribution(product.ratingDistribution);
      distribution[String(rating)] += 1;
      const nextCount = currentCount + 1;
      const nextSum = currentSum + rating;
      transaction.create(reviewRef, {
        userId,
        orderId,
        productId,
        variantId,
        rating,
        title,
        comment,
        verifiedPurchase: true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(productRef, {
        reviewCount: nextCount,
        ratingSum: nextSum,
        ratingAverage: Number((nextSum / nextCount).toFixed(2)),
        ratingDistribution: distribution,
      });
    });

    return {
      reviewId,
      productId,
      variantId,
      rating,
      title,
      comment,
      verifiedPurchase: true,
      createdAt: nowIso,
    };
  },
);

exports.addressAutocomplete = onCall(
  { region: REGION, timeoutSeconds: 10, enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Sign in before searching addresses.');
    }
    const data = asMap(request.data);
    assertAllowedKeys(data, ['query', 'sessionToken']);
    const query = readString(data.query, 'query', { maxLength: 80 });
    const sessionToken = readString(data.sessionToken, 'sessionToken', { maxLength: 128 });
    if (query.length < 2) {
      return [];
    }
    await enforceRateLimit(`address-autocomplete:${userId}`, {
      limit: 20,
      windowMs: 60 * 1000,
      message: 'Too many address suggestions. Try again shortly.',
    });

    const prefix = query.toLowerCase();
    const snapshot = await db.collection('addressSuggestions')
      .where('searchKey', '>=', prefix)
      .where('searchKey', '<=', `${prefix}\uf8ff`)
      .limit(8)
      .get();
    return snapshot.docs.map((document) => {
      const suggestion = document.data() || {};
      return {
        placeId: document.id,
        primaryText: clipString(suggestion.primaryText, 160),
        secondaryText: clipString(suggestion.secondaryText, 240),
      };
    });
  },
);

exports.addressPlaceDetails = onCall(
  { region: REGION, timeoutSeconds: 10, enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Sign in before selecting an address.');
    }
    const data = asMap(request.data);
    assertAllowedKeys(data, ['placeId', 'sessionToken']);
    const placeId = readId(data.placeId, 'placeId');
    const sessionToken = readString(data.sessionToken, 'sessionToken', { maxLength: 128 });
    await enforceRateLimit(`address-details:${userId}`, {
      limit: 20,
      windowMs: 60 * 1000,
      message: 'Too many address detail requests. Try again shortly.',
    });

    const document = await db.collection('addressSuggestions').doc(placeId).get();
    if (!document.exists) {
      throw new HttpsError('not-found', 'The address suggestion is no longer available.');
    }
    const suggestion = document.data() || {};
    const details = {
      placeId: document.id,
      addressLine1: readStoredString(suggestion.addressLine1),
      barangay: readStoredString(suggestion.barangay),
      city: readStoredString(suggestion.city),
      province: readStoredString(suggestion.province),
      postalCode: readStoredString(suggestion.postalCode),
      latitude: readStoredNumber(suggestion.latitude),
      longitude: readStoredNumber(suggestion.longitude),
      addressSource: 'autocomplete',
    };
    if (!details.addressLine1 || !details.barangay || !details.city ||
        !details.province || !/^\d{4}$/.test(details.postalCode) ||
        details.latitude == null || details.latitude < -90 || details.latitude > 90 ||
        details.longitude == null || details.longitude < -180 || details.longitude > 180) {
      throw new HttpsError('failed-precondition', 'The address suggestion is incomplete.');
    }
    return details;
  },
);

exports.addToCart = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Sign in before adding to cart.');
    }
    await enforceRateLimit(`cart:${userId}`, {
      limit: 30,
      windowMs: 60 * 1000,
      message: 'Too many cart changes. Try again shortly.',
    });
    const data = asMap(request.data);
    assertAllowedKeys(data, ['productId', 'variantId', 'quantity', 'operationId']);
    const productId = readId(data.productId, 'productId');
    const variantId = readId(data.variantId, 'variantId');
    const quantity = data.quantity == null ? 1 : readInteger(data.quantity, 'quantity');
    if (quantity < 1 || quantity > MAX_CART_ITEMS) {
      throw new HttpsError('invalid-argument', 'quantity must be between 1 and 100.');
    }
    const operationId = data.operationId == null
      ? `add-${Date.now()}-${crypto.randomBytes(6).toString('hex')}`
      : readId(data.operationId, 'operationId');

    const productRef = db.collection('perfumes').doc(productId);
    const cartRef = db.collection('carts').doc(userId);
    const nowIso = new Date().toISOString();
    let responsePayload;
    await db.runTransaction(async (transaction) => {
      const productSnapshot = await transaction.get(productRef);
      const cartSnapshot = await transaction.get(cartRef);
      if (!productSnapshot.exists) {
        throw new HttpsError('not-found', 'The perfume is not available.');
      }
      const product = productSnapshot.data() || {};
      if (product.isPublished !== true || !Array.isArray(product.variants)) {
        throw new HttpsError('not-found', 'The perfume is not available.');
      }
      const variant = product.variants.find((candidate) => candidate?.id === variantId);
      if (!variant || !Number.isInteger(variant.stock) || !Number.isInteger(variant.priceCentavos)) {
        throw new HttpsError('not-found', 'The perfume variant does not exist.');
      }
      if (variant.stock < 1) {
        throw new HttpsError('failed-precondition', 'This variant is out of stock.');
      }

      const currentCart = cartSnapshot.data() || {};
      const currentItems = cartSnapshot.exists ? currentCart.items : [];
      if (!Array.isArray(currentItems) || currentItems.length > MAX_CART_ITEMS ||
          !currentItems.every(isCartItem) || hasDuplicateCartVariants(currentItems)) {
        throw new HttpsError('failed-precondition', 'The cart contains invalid items.');
      }
      if (currentCart.lastOperationId === operationId && currentCart.serverConfirmed === true) {
        const existingItem = currentItems.find(
          (item) => item.productId === productId && item.variantId === variantId,
        );
        responsePayload = cartResponse(existingItem, currentItems, operationId, nowIso);
        return;
      }
      const existing = currentItems.find(
        (item) => item.productId === productId && item.variantId === variantId,
      );
      const nextQuantity = (existing?.quantity || 0) + quantity;
      if (nextQuantity > MAX_CART_ITEMS) {
        throw new HttpsError('failed-precondition', 'A cart line cannot exceed 100 units.');
      }
      if (nextQuantity > variant.stock) {
        throw new HttpsError(
          'failed-precondition',
          `Only ${variant.stock} unit(s) of ${variant.label || 'this variant'} are available.`,
        );
      }
      const nextItem = {
        productId,
        variantId,
        productName: clipString(product.name, 256),
        variantLabel: clipString(variant.label, 128),
        unitPriceCentavos: variant.priceCentavos,
        quantity: nextQuantity,
      };
      const nextItems = [
        ...currentItems.filter(
          (item) => item.productId !== productId || item.variantId !== variantId,
        ),
        nextItem,
      ];
      if (nextItems.length > MAX_CART_ITEMS) {
        throw new HttpsError('failed-precondition', 'Your cart has reached its item limit.');
      }
      transaction.set(cartRef, {
        userId,
        items: nextItems,
        updatedAt: FieldValue.serverTimestamp(),
        serverConfirmed: true,
        lastOperationId: operationId,
        serverConfirmedAt: FieldValue.serverTimestamp(),
      });
      responsePayload = cartResponse(nextItem, nextItems, operationId, nowIso);
    });
    return responsePayload;
  },
);

exports.getOrderReview = onCall(
  { region: REGION, timeoutSeconds: 20, enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Sign in before reviewing an order.');
    }
    await enforceRateLimit(`order-review:${userId}`, {
      limit: 30,
      windowMs: 60 * 1000,
      message: 'Too many order review refreshes. Try again shortly.',
    });
    const data = asMap(request.data);
    assertAllowedKeys(data, [
      'orderId', 'selectedItems', 'addressId', 'shippingAddress',
      'deliveryOptionId', 'paymentMethod', 'currency',
    ]);
    const orderId = data.orderId == null
      ? `order-${Date.now()}-${crypto.randomBytes(6).toString('hex')}`
      : readId(data.orderId, 'orderId');
    const paymentMethod = readCheckoutPaymentMethod(data.paymentMethod ?? 'gcash');
    const currency = readEnum(data.currency ?? 'PHP', ['PHP'], 'currency');
    const delivery = deliveryOptionById(data.deliveryOptionId ?? 'standard');
    const cartSnapshot = await db.collection('carts').doc(userId).get();
    const cart = cartSnapshot.data() || {};
    if (!cartSnapshot.exists) {
      throw new HttpsError('failed-precondition', 'Cannot review an empty cart.');
    }
    if (!Array.isArray(cart.items)) {
      throw new HttpsError('failed-precondition', 'The cart contains invalid items.');
    }
    const cartItems = cart.items;
    if (cartItems.length === 0) {
      throw new HttpsError('failed-precondition', 'Cannot review an empty cart.');
    }
    if (cartItems.length > MAX_CART_ITEMS || !cartItems.every(isCartItem) ||
        hasDuplicateCartVariants(cartItems)) {
      throw new HttpsError('failed-precondition', 'The cart contains invalid items.');
    }

    const selectedItems = selectedCartItems(data.selectedItems, cartItems);
    const productIds = [...new Set(selectedItems.map((item) => item.productId))];
    const productSnapshots = await Promise.all(
      productIds.map((productId) => db.collection('perfumes').doc(productId).get()),
    );
    const productMap = new Map(
      productSnapshots.map((snapshot, index) => [productIds[index], snapshot.data() || {}]),
    );
    const reviewItems = selectedItems.map((item) => {
      const product = productMap.get(item.productId);
      if (!product || product.isPublished !== true || !Array.isArray(product.variants)) {
        throw new HttpsError('failed-precondition', 'A selected product is no longer available.');
      }
      const variant = product.variants.find((candidate) => candidate?.id === item.variantId);
      if (!variant || !Number.isInteger(variant.priceCentavos) || !Number.isInteger(variant.stock)) {
        throw new HttpsError('failed-precondition', 'A selected variant is no longer available.');
      }
      if (item.quantity > variant.stock) {
        throw new HttpsError('failed-precondition', `Only ${variant.stock} unit(s) are available.`);
      }
      const unitPriceCentavos = variant.priceCentavos;
      return {
        productId: item.productId,
        variantId: item.variantId,
        productName: clipString(product.name, 256),
        variantLabel: clipString(variant.label, 128),
        unitPriceCentavos,
        quantity: item.quantity,
        lineTotalCentavos: unitPriceCentavos * item.quantity,
        imageUrl: Array.isArray(product.imageUrls) && typeof product.imageUrls[0] === 'string'
          ? product.imageUrls[0]
          : null,
      };
    });
    const subtotalCentavos = reviewItems.reduce(
      (total, item) => total + item.lineTotalCentavos,
      0,
    );
    const shippingAddress = await resolveReviewAddress(userId, data);
    assertDeliveryAddress(delivery.id, shippingAddress);
    const nowIso = new Date().toISOString();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
    const orderItems = reviewItems.map((item) => ({
      productId: item.productId,
      variantId: item.variantId,
      productName: item.productName,
      variantLabel: item.variantLabel,
      unitPriceCentavos: item.unitPriceCentavos,
      quantity: item.quantity,
    }));
    const shippingAddressForOrder = {
      fullName: shippingAddress.fullName,
      phoneNumber: shippingAddress.phoneNumber,
      addressLine1: shippingAddress.addressLine1,
      barangay: shippingAddress.barangay,
      city: shippingAddress.city,
      province: shippingAddress.province,
      postalCode: shippingAddress.postalCode,
      notes: shippingAddress.notes,
    };
    const deliveryOptionForOrder = {
      id: delivery.id,
      name: delivery.name,
      feeCentavos: delivery.feeCentavos,
      estimatedDays: delivery.estimatedDays,
    };
    const reviewRef = db.collection('orderReviews').doc(orderId);
    const review = {
      orderId,
      userId,
      status: 'ready',
      currency,
      paymentMethod,
      orderItems,
      shippingAddress: shippingAddressForOrder,
      deliveryOption: deliveryOptionForOrder,
      subtotalCentavos,
      deliveryFeeCentavos: delivery.feeCentavos,
      totalCentavos: subtotalCentavos + delivery.feeCentavos,
      amountCentavos: subtotalCentavos + delivery.feeCentavos,
      createdAt: new Date(nowIso),
      expiresAt,
    };
    await db.runTransaction(async (transaction) => {
      const orderRef = db.collection('orders').doc(orderId);
      const intentRef = db.collection('checkoutIntents').doc(orderId);
      const [orderSnapshot, intentSnapshot, existingReviewSnapshot] = await Promise.all([
        transaction.get(orderRef),
        transaction.get(intentRef),
        transaction.get(reviewRef),
      ]);
      if (orderSnapshot.exists) {
        const existingOrder = orderSnapshot.data() || {};
        throw new HttpsError(
          existingOrder.userId === userId ? 'failed-precondition' : 'permission-denied',
          'This order ID is already in use.',
        );
      }
      if (intentSnapshot.exists) {
        const existingIntent = intentSnapshot.data() || {};
        if (existingIntent.userId !== userId) {
          throw new HttpsError('permission-denied', 'This checkout ID is already in use.');
        }
        const now = Date.now();
        const stale = existingIntent.status === 'failed' ||
          (existingIntent.status === 'creating' &&
            asDate(existingIntent.claimExpiresAt)?.getTime() <= now) ||
          (existingIntent.status === 'pending' &&
            asDate(existingIntent.expiresAt)?.getTime() <= now);
        if (stale) {
          transaction.delete(intentRef);
        } else {
          throw new HttpsError('failed-precondition', 'This checkout ID is already in use.');
        }
      }
      if (existingReviewSnapshot.exists && existingReviewSnapshot.data()?.userId !== userId) {
        throw new HttpsError('permission-denied', 'That order review belongs to another user.');
      }
      transaction.set(reviewRef, review);
    });
    return {
      orderId,
      userId,
      status: 'ready_for_place_order',
      serverCalculated: true,
      currency,
      shippingAddressSnapshot: shippingAddress,
      deliveryOptionSnapshot: {
        id: delivery.id,
        name: delivery.name,
        estimatedDays: delivery.estimatedDays,
        feeCentavos: delivery.feeCentavos,
      },
      payment: {
        method: paymentMethod,
        label: paymentMethodLabel(paymentMethod),
        status: paymentMethod === 'cod' ? 'pending_collection' : 'pending',
      },
      items: reviewItems,
      pricing: {
        subtotalCentavos,
        deliveryFeeCentavos: delivery.feeCentavos,
        discountCentavos: 0,
        totalCentavos: subtotalCentavos + delivery.feeCentavos,
        currency,
      },
      createdAt: nowIso,
      expiresAt: expiresAt.toISOString(),
      acknowledgement: 'By placing this order, you agree to Scentify delivery and payment terms.',
    };
  },
);

exports.createCashOnDeliveryOrder = onCall(
  { region: REGION, timeoutSeconds: 30, enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Sign in before placing an order.');
    }
    await enforceRateLimit(`cod-order:${userId}`, {
      limit: 5,
      windowMs: 60 * 1000,
      message: 'Too many order attempts. Try again in a minute.',
    });

    const data = asMap(request.data);
    assertAllowedKeys(data, ['orderId']);
    const orderId = readId(data.orderId, 'orderId');
    const orderRef = db.collection('orders').doc(orderId);
    const reviewRef = db.collection('orderReviews').doc(orderId);
    const cartRef = db.collection('carts').doc(userId);

    const result = await db.runTransaction(async (transaction) => {
      const existingOrderSnapshot = await transaction.get(orderRef);
      if (existingOrderSnapshot.exists) {
        const existing = existingOrderSnapshot.data() || {};
        if (existing.userId !== userId) {
          throw new HttpsError('permission-denied', 'That order does not belong to you.');
        }
        if (existing.id !== orderId || existing.paymentMethod !== 'cod') {
          throw new HttpsError('already-exists', 'This order ID is already in use.');
        }
        return {
          orderId,
          userId,
          status: existing.status,
          paymentMethod: existing.paymentMethod,
          paymentStatus: existing.paymentStatus,
        };
      }

      const [reviewSnapshot, cartSnapshot] = await Promise.all([
        transaction.get(reviewRef),
        transaction.get(cartRef),
      ]);
      const review = reviewSnapshot.data() || {};
      if (!reviewSnapshot.exists || review.orderId !== orderId || review.userId !== userId ||
          review.status !== 'ready' || review.paymentMethod !== 'cod' ||
          review.currency !== 'PHP' || !asDate(review.expiresAt) ||
          asDate(review.expiresAt).getTime() <= Date.now()) {
        throw new HttpsError('failed-precondition', 'Refresh the order review before placing this order.');
      }
      if (!cartSnapshot.exists) {
        throw new HttpsError('failed-precondition', 'Your cart changed. Review it again.');
      }
      const cart = cartSnapshot.data() || {};
      if (cart.userId !== userId || !Array.isArray(cart.items) ||
          !cart.items.every(isCartItem) || hasDuplicateCartVariants(cart.items)) {
        throw new HttpsError('failed-precondition', 'Your cart contains invalid items.');
      }
      if (!Array.isArray(review.orderItems) || review.orderItems.length < 1 ||
          review.orderItems.length > MAX_ORDER_ITEMS ||
          !review.orderItems.every((item) => isReviewOrderItem(item)) ||
          hasDuplicateCartVariants(review.orderItems)) {
        throw new HttpsError('failed-precondition', 'The reviewed order contains invalid items.');
      }

      const address = normalizeReviewAddress(review.shippingAddress, null);
      assertDeliveryAddress(review.deliveryOption?.id, address);
      const delivery = deliveryOptionById(review.deliveryOption?.id);
      if (review.deliveryOption?.feeCentavos !== delivery.feeCentavos) {
        throw new HttpsError('failed-precondition', 'The delivery price changed. Review your order again.');
      }

      const subtotalCentavos = review.orderItems.reduce(
        (total, item) => total + item.unitPriceCentavos * item.quantity,
        0,
      );
      const totalCentavos = subtotalCentavos + delivery.feeCentavos;
      if (!Number.isSafeInteger(subtotalCentavos) ||
          review.subtotalCentavos !== subtotalCentavos ||
          review.deliveryFeeCentavos !== delivery.feeCentavos ||
          review.totalCentavos !== totalCentavos || review.amountCentavos !== totalCentavos) {
        throw new HttpsError('failed-precondition', 'The order total changed. Review it again.');
      }

      const selected = new Map(review.orderItems.map((item) => [
        `${item.productId}|${item.variantId}`,
        item,
      ]));
      for (const item of review.orderItems) {
        const cartItem = cart.items.find((candidate) =>
          candidate.productId === item.productId && candidate.variantId === item.variantId,
        );
        if (!cartItem || cartItem.quantity < item.quantity) {
          throw new HttpsError('failed-precondition', 'Your cart changed. Review it again.');
        }
      }

      const productIds = [...new Set(review.orderItems.map((item) => item.productId))];
      const productRefs = productIds.map((productId) => db.collection('perfumes').doc(productId));
      const productSnapshots = await Promise.all(productRefs.map((reference) => transaction.get(reference)));
      const products = new Map(productSnapshots.map((snapshot, index) => [
        productIds[index], { reference: productRefs[index], data: snapshot.data() || {} },
      ]));
      const updatedVariants = new Map();
      for (const item of review.orderItems) {
        const product = products.get(item.productId);
        if (!product || !product.data.isPublished || !Array.isArray(product.data.variants)) {
          throw new HttpsError('failed-precondition', 'A selected product is no longer available.');
        }
        const variants = updatedVariants.get(item.productId) || [...product.data.variants];
        const variantIndex = variants.findIndex((candidate) => candidate?.id === item.variantId);
        const variant = variants[variantIndex];
        if (!variant || !Number.isInteger(variant.priceCentavos) ||
            !Number.isInteger(variant.stock) || variant.stock < 0 ||
            variant.priceCentavos !== item.unitPriceCentavos || variant.stock < item.quantity) {
          throw new HttpsError('failed-precondition', 'A selected item is no longer available in the reviewed quantity and price.');
        }
        variants[variantIndex] = { ...variant, stock: variant.stock - item.quantity };
        updatedVariants.set(item.productId, variants);
      }

      const now = new Date();
      const order = {
        id: orderId,
        userId,
        items: review.orderItems,
        shippingAddress: review.shippingAddress,
        deliveryOption: delivery,
        subtotalCentavos,
        deliveryFeeCentavos: delivery.feeCentavos,
        totalCentavos,
        status: 'confirmed',
        paymentMethod: 'cod',
        paymentStatus: 'pending_collection',
        createdAt: now,
        updatedAt: now,
        events: [{
          from: null,
          to: 'confirmed',
          changedAt: now,
          actorId: 'checkout:cash-on-delivery',
        }],
      };
      const remainingItems = cart.items.flatMap((item) => {
        const selectedItem = selected.get(`${item.productId}|${item.variantId}`);
        if (!selectedItem) return [item];
        const remaining = item.quantity - selectedItem.quantity;
        return remaining > 0 ? [{ ...item, quantity: remaining }] : [];
      });

      transaction.create(orderRef, order);
      if (remainingItems.length === 0) {
        transaction.delete(cartRef);
      } else {
        transaction.set(cartRef, {
          userId,
          items: remainingItems,
          updatedAt: FieldValue.serverTimestamp(),
          serverConfirmed: true,
          lastOperationId: `cod-${orderId}`,
          serverConfirmedAt: FieldValue.serverTimestamp(),
        });
      }
      for (const [productId, variants] of updatedVariants) {
        transaction.update(products.get(productId).reference, { variants });
      }
      for (const item of review.orderItems) {
        transaction.create(db.collection('inventoryAdjustments').doc(), {
          productId: item.productId,
          variantId: item.variantId,
          orderId,
          actorId: `checkout:${userId}`,
          delta: -item.quantity,
          reason: 'Cash on delivery order',
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      transaction.update(reviewRef, {
        status: 'cod_placed',
        placedAt: FieldValue.serverTimestamp(),
      });
      return {
        orderId,
        userId,
        status: order.status,
        paymentMethod: order.paymentMethod,
        paymentStatus: order.paymentStatus,
      };
    });

    return result;
  },
);

exports.adjustInventory = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const adminId = request.auth?.uid;
    if (!adminId || (request.auth.token?.admin !== true && request.auth.token?.superadmin !== true)) {
      throw new HttpsError('permission-denied', 'Only an authorized admin can adjust inventory.');
    }
    const data = asMap(request.data);
    assertAllowedKeys(data, ['productId', 'variantId', 'delta', 'reason']);
    const productId = readId(data.productId, 'productId');
    const variantId = readId(data.variantId, 'variantId');
    const delta = readInteger(data.delta, 'delta');
    const reason = readString(data.reason, 'reason', { maxLength: 240 });
    if (delta === 0 || Math.abs(delta) > 100_000 || reason.length < 3) {
      throw new HttpsError('invalid-argument', 'The inventory adjustment is invalid.');
    }
    const productRef = db.collection('perfumes').doc(productId);
    const adjustmentRef = db.collection('inventoryAdjustments').doc();
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(productRef);
      const product = snapshot.data() || {};
      if (!snapshot.exists || !Array.isArray(product.variants)) {
        throw new HttpsError('not-found', 'The inventory product does not exist.');
      }
      const variants = [...product.variants];
      const index = variants.findIndex((variant) => variant?.id === variantId);
      const variant = variants[index];
      const stock = Number.isInteger(variant?.stock) ? variant.stock : -1;
      if (index < 0 || stock < 0) {
        throw new HttpsError('not-found', 'The inventory variant does not exist.');
      }
      const nextStock = stock + delta;
      if (nextStock < 0 || nextStock > 1_000_000) {
        throw new HttpsError('failed-precondition', 'The adjustment would make stock invalid.');
      }
      variants[index] = { ...variant, stock: nextStock };
      transaction.update(productRef, { variants });
      transaction.create(adjustmentRef, {
        productId,
        variantId,
        actorId: adminId,
        delta,
        reason,
        createdAt: FieldValue.serverTimestamp(),
      });
      return { productId, variantId, stock: nextStock };
    });
  },
);

exports.paymongoWebhook = onRequest(
  { region: REGION },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.sendStatus(405);
      return;
    }

    const rawBody = request.rawBody || Buffer.from(JSON.stringify(request.body || {}));
    if (rawBody.length > 1_000_000) {
      response.sendStatus(413);
      return;
    }
    const signature = request.get('Paymongo-Signature') || request.get('X-Paymongo-Signature');
    const secret = process.env.PAYMONGO_WEBHOOK_SECRET;
    if (!secret || !verifyPayMongoSignature(rawBody, signature, secret)) {
      response.sendStatus(401);
      return;
    }

    let event;
    try {
      event = request.body || JSON.parse(rawBody.toString('utf8'));
    } catch (_) {
      response.sendStatus(400);
      return;
    }
    const eventEnvelope = isPlainObject(event?.data) ? event.data : event;
    if (!isPlainObject(eventEnvelope)) {
      response.sendStatus(400);
      return;
    }
    const eventType = eventEnvelope.type || eventEnvelope.attributes?.type;
    if (eventType !== 'checkout_session.payment.paid') {
      response.sendStatus(200);
      return;
    }

    const resource = eventEnvelope.data || eventEnvelope.attributes?.data;
    if (!resource || typeof resource !== 'object') {
      response.sendStatus(400);
      return;
    }
    const eventId = typeof eventEnvelope.id === 'string'
      ? eventEnvelope.id
      : typeof resource.id === 'string' ? resource.id : '';
    if (!eventId) {
      response.sendStatus(200);
      return;
    }

    try {
      await confirmPaidOrder(resource, eventId, requestIp(request));
      response.sendStatus(200);
    } catch (error) {
      console.error('PayMongo webhook processing failed', error);
      // A non-2xx response asks PayMongo to retry if the order was not ready
      // yet or a transient Firestore failure occurred.
      if (error?.code === 'resource-exhausted') {
        response.setHeader('Retry-After', String(error.details?.retryAfterSeconds || 60));
        response.sendStatus(429);
        return;
      }
      response.sendStatus(500);
    }
  },
);

exports.reconcileLatePayment = onCall(
  { region: REGION, timeoutSeconds: 20, enforceAppCheck: true },
  async (request) => {
    const adminId = request.auth?.uid;
    if (!adminId || (request.auth?.token?.admin !== true && request.auth?.token?.superadmin !== true)) {
      throw new HttpsError('permission-denied', 'Only an authorized admin can reconcile payments.');
    }
    const data = asMap(request.data);
    assertAllowedKeys(data, ['orderId']);
    const orderId = readId(data.orderId, 'orderId');
    const orderRef = db.collection('orders').doc(orderId);
    const intentRef = db.collection('checkoutIntents').doc(orderId);
    const reviewRef = db.collection('orderReviews').doc(orderId);

    await db.runTransaction(async (transaction) => {
      const [orderSnapshot, intentSnapshot, reviewSnapshot] = await Promise.all([
        transaction.get(orderRef),
        transaction.get(intentRef),
        transaction.get(reviewRef),
      ]);
      if (!orderSnapshot.exists || !intentSnapshot.exists || !reviewSnapshot.exists) {
        throw new HttpsError('not-found', 'The payment reconciliation records are incomplete.');
      }
      const order = orderSnapshot.data() || {};
      const intent = intentSnapshot.data() || {};
      const review = reviewSnapshot.data() || {};
      if (order.status !== 'pending_payment' || order.paymentStatus !== 'manual_review' ||
          intent.status !== 'manual_review' || review.status !== 'manual_review' ||
          intent.userId !== order.userId || intent.orderId !== orderId ||
          typeof intent.paymentReference !== 'string' ||
          intent.paymentReference !== intent.providerReference) {
        throw new HttpsError('failed-precondition', 'This payment is not awaiting reconciliation.');
      }
      await settlePaidOrder(transaction, {
        orderRef,
        intentRef,
        reviewRef,
        order,
        intent,
        review,
        paymentReference: intent.paymentReference,
        actorId: `admin:${adminId}`,
      });
    });
    return { orderId, status: 'confirmed' };
  },
);

exports.notifyOrderCreated = onDocumentCreated(
  { region: REGION, document: 'orders/{orderId}' },
  async (event) => {
    const snapshot = event.data;
    const order = snapshot?.data();
    if (!order?.userId) return;
    await ensureOrderPayment(snapshot);
    await ensureStatusTimeline(snapshot);
    await notifyUser(
      order.userId,
      'Order placed',
      `Order ${event.params.orderId} is waiting for payment confirmation.`,
      event.params.orderId,
    );
  },
);

exports.notifyOrderStatusChanged = onDocumentUpdated(
  { region: REGION, document: 'orders/{orderId}' },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status === after.status || !after.userId) {
      return;
    }
    await ensureStatusTimeline(event.data.after);
    const label = statusLabel(after.status);
    await notifyUser(
      after.userId,
      'Order update',
      `Order ${event.params.orderId} is now ${label}.`,
      event.params.orderId,
    );
  },
);

function verifyPayMongoSignature(rawBody, header, secret) {
  if (!header) return false;
  const parts = Object.fromEntries(
    header.split(',').map((part) => {
      const [key, ...value] = part.trim().split('=');
      return [key, value.join('=')];
    }),
  );
  const timestamp = parts.t;
  const provided = parts.te || parts.li;
  if (!timestamp || !provided) return false;
  const timestampSeconds = Number(timestamp);
  if (!Number.isInteger(timestampSeconds) ||
      Math.abs(Math.floor(Date.now() / 1000) - timestampSeconds) > PAYMONGO_SIGNATURE_MAX_AGE_SECONDS) {
    return false;
  }

  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${timestamp}.${rawBody.toString('utf8')}`)
    .digest('hex');
  return timingSafeEqual(expected, provided);
}

function timingSafeEqual(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length &&
    crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function payMongoPaymentDate(attributes) {
  const value = attributes?.paid_at ?? attributes?.created_at;
  if (typeof value === 'number' && Number.isFinite(value)) {
    const date = new Date(value * 1000);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return asDate(value);
}

async function settlePaidOrder(transaction, {
  orderRef,
  intentRef,
  reviewRef,
  order,
  intent,
  review,
  paymentReference,
  paymentRequestId,
  actorId,
}) {
  if (review.status !== 'ready' && review.status !== 'manual_review') {
    throw new Error('The payment review is not eligible for settlement.');
  }
  validateOrderForPayment(order);

  const reservationRef = db.collection('inventoryReservations').doc(order.id);
  const reservationSnapshot = await transaction.get(reservationRef);
  if (!reservationSnapshot.exists || reservationSnapshot.data()?.status !== 'reserved') {
    throw new Error(`The ${intent.provider} order has no active inventory reservation.`);
  }

  const events = Array.isArray(order.events) ? order.events : [];
  transaction.update(orderRef, {
    status: 'confirmed',
    paymentReference,
    paymentMethod: intent.paymentMethod,
    paymentStatus: 'paid',
    paymentProvider: intent.provider || 'paymongo',
    ...(typeof paymentRequestId === 'string' ? { paymentRequestId } : {}),
    updatedAt: FieldValue.serverTimestamp(),
    events: [
      ...events,
      {
        from: 'pending_payment',
        to: 'confirmed',
        changedAt: new Date(),
        actorId,
      },
    ],
  });
  transaction.update(intentRef, {
    status: 'paid',
    paidAt: FieldValue.serverTimestamp(),
    paymentReference,
    ...(typeof paymentRequestId === 'string' ? { paymentRequestId } : {}),
  });
  if (reservationSnapshot) {
    transaction.update(reservationRef, {
      status: 'committed',
      paymentReference,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  transaction.update(reviewRef, {
    status: 'paid',
    paidAt: FieldValue.serverTimestamp(),
  });
}

async function confirmPaidOrder(resource, eventId, ip, provider = 'paymongo') {
  const attributes = resource?.attributes || {};
  const metadata = attributes.metadata || {};
  const orderId = readOptionalId(attributes.reference_number || metadata.scentifyOrderId);
  if (!orderId) {
    throw new Error('PayMongo payment has no Scentify order reference.');
  }
  if (typeof resource.id !== 'string' || resource.id.length > 128) {
    throw new Error('PayMongo payment has no valid provider reference.');
  }

  const orderRef = db.collection('orders').doc(orderId);
  const intentRef = db.collection('checkoutIntents').doc(orderId);
  const reviewRef = db.collection('orderReviews').doc(orderId);
  const eventDocumentId = crypto.createHash('sha256').update(eventId).digest('hex');
  const eventRef = db.collection(`${provider}WebhookEvents`).doc(eventDocumentId);
  const rateLimitId = crypto.createHash('sha256').update(`webhook:${ip}`).digest('hex');
  const rateLimitRef = db.collection('rateLimits').doc(rateLimitId);
  const result = await db.runTransaction(async (transaction) => {
    const eventSnapshot = await transaction.get(eventRef);
    if (eventSnapshot.exists) return { duplicate: true };

    const rateLimitSnapshot = await transaction.get(rateLimitRef);
    const now = Date.now();
    const currentLimit = rateLimitSnapshot.exists ? rateLimitSnapshot.data() || {} : {};
    const windowStart = asDate(currentLimit.windowStart)?.getTime() || 0;
    const count = Number.isInteger(currentLimit.count) ? currentLimit.count : 0;
    let rateLimitWrite;
    if (!windowStart || now - windowStart >= 60 * 1000) {
      rateLimitWrite = {
        type: 'set',
        value: {
          scopeHash: rateLimitId,
          windowStart: new Date(now),
          count: 1,
          expiresAt: new Date(now + 60 * 1000 + 60 * 1000),
        },
      };
    } else if (count >= 120) {
      return {
        rateLimited: true,
        retryAfterSeconds: Math.max(1, Math.ceil((60 * 1000 - (now - windowStart)) / 1000)),
      };
    } else {
      rateLimitWrite = {
        type: 'update',
        value: {
          count: FieldValue.increment(1),
          expiresAt: new Date(windowStart + 60 * 1000 + 60 * 1000),
        },
      };
    }

    const [orderSnapshot, intentSnapshot, reviewSnapshot] = await Promise.all([
      transaction.get(orderRef),
      transaction.get(intentRef),
      transaction.get(reviewRef),
    ]);
    if (!orderSnapshot.exists) {
      throw new Error(`Order ${orderId} is not available yet.`);
    }
    if (!intentSnapshot.exists) {
      throw new Error(`Checkout intent ${orderId} is not available.`);
    }
    if (!reviewSnapshot.exists) {
      throw new Error(`Order review ${orderId} is not available.`);
    }
    const order = orderSnapshot.data();
    const intent = intentSnapshot.data() || {};
    const review = reviewSnapshot.data() || {};
    if (intent.orderId !== orderId || intent.userId !== order.userId ||
        intent.providerReference !== resource.id ||
        intent.amountCentavos !== order.totalCentavos) {
      throw new Error(`Payment intent ${orderId} does not match the order.`);
    }
    if (provider === 'xendit' &&
        (!Number.isFinite(attributes.amount) ||
          Math.round(attributes.amount * 100) !== order.totalCentavos ||
          attributes.currency !== intent.currency)) {
      throw new Error(`Xendit payment amount does not match order ${orderId}.`);
    }

    const recordEvent = () => {
      transaction.create(eventRef, {
        eventId,
        receivedAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(now + 24 * 60 * 60 * 1000),
      });
      if (rateLimitWrite.type === 'set') {
        transaction.set(rateLimitRef, rateLimitWrite.value);
      } else {
        transaction.update(rateLimitRef, rateLimitWrite.value);
      }
    };
    if (order.status !== 'pending_payment') {
      recordEvent();
      return { duplicate: false };
    }
    if ((review.status !== 'ready' && review.status !== 'manual_review') ||
        review.userId !== order.userId ||
        review.totalCentavos !== order.totalCentavos ||
        review.paymentMethod !== intent.paymentMethod ||
        review.currency !== intent.currency ||
        JSON.stringify(review.orderItems) !== JSON.stringify(order.items) ||
        JSON.stringify(review.shippingAddress) !== JSON.stringify(order.shippingAddress) ||
        JSON.stringify(review.deliveryOption) !== JSON.stringify(order.deliveryOption)) {
      throw new Error(`Payment intent ${orderId} does not match the order review.`);
    }

    const intentExpiresAt = asDate(intent.expiresAt);
    const providerPaidAt = provider === 'paymongo' ? payMongoPaymentDate(attributes) : null;
    const late = intent.status !== 'pending' || !intentExpiresAt ||
      intentExpiresAt.getTime() <= Date.now() ||
      (providerPaidAt && providerPaidAt.getTime() > intentExpiresAt.getTime());
    if (late) {
      const events = Array.isArray(order.events) ? order.events : [];
      transaction.update(orderRef, {
        status: 'pending_payment',
        paymentReference: resource.id,
        paymentMethod: intent.paymentMethod,
        paymentStatus: 'manual_review',
        paymentProvider: provider,
        updatedAt: FieldValue.serverTimestamp(),
        events: [
          ...events,
          {
            from: 'pending_payment',
            to: 'pending_payment',
            changedAt: new Date(),
            actorId: `${provider}-webhook:manual-review`,
          },
        ],
      });
      transaction.update(intentRef, {
        status: 'manual_review',
        paymentReference: resource.id,
        manualReviewAt: FieldValue.serverTimestamp(),
        ...(providerPaidAt ? { providerPaidAt } : {}),
      });
      transaction.update(reviewRef, {
        status: 'manual_review',
        manualReviewAt: FieldValue.serverTimestamp(),
      });
      recordEvent();
      return { duplicate: false, manualReview: true };
    }

    await settlePaidOrder(transaction, {
      orderRef,
      intentRef,
      reviewRef,
      order,
      intent,
      review,
      paymentReference: resource.id,
      paymentRequestId: typeof attributes.payment_request_id === 'string'
        ? attributes.payment_request_id : undefined,
      actorId: `${provider}-webhook`,
    });
    recordEvent();
    return { duplicate: false };
  });
  if (result.rateLimited) {
    const error = new Error('Webhook rate limit exceeded.');
    error.code = 'resource-exhausted';
    error.details = { retryAfterSeconds: result.retryAfterSeconds };
    throw error;
  }
}

exports.xenditWebhook = onRequest(
  { region: REGION, secrets: [XENDIT_WEBHOOK_TOKEN] },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.sendStatus(405);
      return;
    }
    const token = XENDIT_WEBHOOK_TOKEN.value() || process.env.XENDIT_WEBHOOK_TOKEN;
    if (!token || request.get('x-callback-token') !== token) {
      response.sendStatus(401);
      return;
    }
    const event = request.body || {};
    if (!isPlainObject(event.data)) {
      response.sendStatus(200);
      return;
    }
    const session = event.data;
    const paymentReference = typeof session.payment_session_id === 'string'
      ? session.payment_session_id : '';
    const orderId = readOptionalId(session.reference_id);
    if (!orderId || !paymentReference) {
      response.sendStatus(400);
      return;
    }
    try {
      if (event.event === 'payment_session.expired') {
        await releaseExpiredXenditOrder(orderId, paymentReference);
        response.sendStatus(200);
        return;
      }
      if (event.event !== 'payment_session.completed') {
        response.sendStatus(200);
        return;
      }
      if (session.status !== 'COMPLETED' ||
          !(typeof session.payment_id === 'string' || typeof session.payment_request_id === 'string')) {
        response.sendStatus(400);
        return;
      }
      await confirmPaidOrder({
        id: paymentReference,
        attributes: {
          reference_number: orderId,
          amount: session.amount,
          currency: session.currency,
          payment_request_id: session.payment_request_id,
          metadata: { scentifyOrderId: orderId },
        },
      }, `${paymentReference}:${event.created || ''}`, requestIp(request), 'xendit');
      response.sendStatus(200);
    } catch (error) {
      console.error('Xendit webhook processing failed', error);
      if (error?.code === 'resource-exhausted') {
        response.setHeader('Retry-After', String(error.details?.retryAfterSeconds || 60));
        response.sendStatus(429);
        return;
      }
      response.sendStatus(500);
    }
  },
);

async function releaseExpiredXenditOrder(orderId, paymentReference) {
  const orderRef = db.collection('orders').doc(orderId);
  const intentRef = db.collection('checkoutIntents').doc(orderId);
  const reservationRef = db.collection('inventoryReservations').doc(orderId);
  await db.runTransaction(async (transaction) => {
    const [orderSnapshot, intentSnapshot, reservationSnapshot] = await Promise.all([
      transaction.get(orderRef), transaction.get(intentRef), transaction.get(reservationRef),
    ]);
    if (!orderSnapshot.exists || !intentSnapshot.exists || !reservationSnapshot.exists) return;
    const order = orderSnapshot.data() || {};
    const intent = intentSnapshot.data() || {};
    const reservation = reservationSnapshot.data() || {};
    if (intent.provider !== 'xendit' || intent.providerReference !== paymentReference ||
        order.paymentReference !== paymentReference || order.status !== 'pending_payment' ||
        reservation.status !== 'reserved' || !Array.isArray(reservation.items)) return;
    const productIds = [...new Set(reservation.items.map((item) => item.productId))];
    const productRefs = productIds.map((id) => db.collection('perfumes').doc(id));
    const productSnapshots = await Promise.all(productRefs.map((ref) => transaction.get(ref)));
    const products = new Map(productSnapshots.map((snapshot, index) => [
      productIds[index], { ref: productRefs[index], data: snapshot.data() || {} },
    ]));
    const updated = new Map();
    for (const item of reservation.items) {
      const product = products.get(item.productId);
      const variants = updated.get(item.productId) || [...(product?.data.variants || [])];
      const index = variants.findIndex((variant) => variant?.id === item.variantId);
      if (index < 0 || !Number.isInteger(item.quantity) || item.quantity < 1) {
        throw new Error('The Xendit reservation inventory is invalid.');
      }
      variants[index] = { ...variants[index], stock: variants[index].stock + item.quantity };
      updated.set(item.productId, variants);
    }
    for (const [productId, variants] of updated) {
      transaction.update(products.get(productId).ref, { variants });
    }
    for (const item of reservation.items) {
      transaction.create(db.collection('inventoryAdjustments').doc(), {
        ...item, orderId, actorId: 'xendit-webhook', delta: item.quantity,
        reason: 'Xendit payment session expired', createdAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.update(reservationRef, { status: 'released', updatedAt: FieldValue.serverTimestamp() });
    transaction.update(orderRef, {
      status: 'cancelled', paymentStatus: 'expired', updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(intentRef, { status: 'expired', expiredAt: FieldValue.serverTimestamp() });
  });
}

function validateOrderForPayment(order) {
  if (!isPlainObject(order) || typeof order.userId !== 'string' ||
      !order.userId || order.status !== 'pending_payment') {
    throw new Error('The order payload is invalid.');
  }
  if (!Array.isArray(order.items) || order.items.length < 1 ||
      order.items.length > MAX_ORDER_ITEMS) {
    throw new Error('The order has an invalid item list.');
  }
  const subtotal = readNonNegativeIntegerOrThrow(order.subtotalCentavos, 'subtotalCentavos');
  const deliveryFee = readNonNegativeIntegerOrThrow(order.deliveryFeeCentavos, 'deliveryFeeCentavos');
  const total = readNonNegativeIntegerOrThrow(order.totalCentavos, 'totalCentavos');
  if (subtotal + deliveryFee !== total) {
    throw new Error('The order total is inconsistent.');
  }
  if (typeof order.paymentReference !== 'string' || order.paymentReference.length > 128) {
    throw new Error('The order payment reference is invalid.');
  }

  let calculatedSubtotal = 0;
  for (const item of order.items) {
    if (!isPlainObject(item) || typeof item.productId !== 'string' ||
        typeof item.variantId !== 'string' || typeof item.productName !== 'string' ||
        typeof item.variantLabel !== 'string') {
      throw new Error('The order contains an invalid item.');
    }
    const unitPrice = readNonNegativeIntegerOrThrow(item.unitPriceCentavos, 'item.unitPriceCentavos');
    const quantity = readIntegerOrThrow(item.quantity, 'item.quantity');
    if (!item.productId || item.productId.length > 128 || !item.variantId ||
        item.variantId.length > 128 || item.productName.length > 256 ||
        item.variantLabel.length > 128 || quantity < 1 || quantity > 100) {
      throw new Error('The order contains an invalid item value.');
    }
    calculatedSubtotal += unitPrice * quantity;
    if (calculatedSubtotal > total) {
      throw new Error('The order subtotal exceeds the total.');
    }
  }
  if (calculatedSubtotal !== subtotal) {
    throw new Error('The order subtotal is inconsistent.');
  }

  const address = order.shippingAddress;
  if (!isPlainObject(address) ||
      !['fullName', 'phoneNumber', 'addressLine1', 'barangay', 'city', 'province', 'postalCode']
        .every((field) => typeof address[field] === 'string' && address[field].trim())) {
    throw new Error('The order shipping address is incomplete.');
  }
  if (!/^\d{4}$/.test(address.postalCode.trim())) {
    throw new Error('The order postal code is invalid.');
  }
  const delivery = order.deliveryOption;
  if (!isPlainObject(delivery) || typeof delivery.id !== 'string' ||
      typeof delivery.name !== 'string' || typeof delivery.estimatedDays !== 'string' ||
      readNonNegativeIntegerOrThrow(delivery.feeCentavos, 'deliveryOption.feeCentavos') < 0) {
    throw new Error('The order delivery option is invalid.');
  }
}

function asMap(value) {
  if (!isPlainObject(value)) {
    throw new HttpsError('invalid-argument', 'Request data must be an object.');
  }
  return value;
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function readString(value, field, { maxLength = 256, required = true } = {}) {
  if (typeof value !== 'string') {
    if (!required && value == null) return null;
    throw new HttpsError('invalid-argument', `${field} must be a string.`);
  }
  const normalized = value.trim();
  if ((required && !normalized) || normalized.length > maxLength) {
    throw new HttpsError('invalid-argument', `${field} is invalid.`);
  }
  return normalized;
}

function readId(value, field) {
  const normalized = readString(value, field, { maxLength: 128 });
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(normalized)) {
    throw new HttpsError('invalid-argument', `${field} contains invalid characters.`);
  }
  return normalized;
}

function readOptionalId(value) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(normalized) ? normalized : null;
}

function readInteger(value, field) {
  if (!Number.isInteger(value)) {
    throw new HttpsError('invalid-argument', `${field} must be an integer.`);
  }
  return value;
}

function readEnum(value, allowed, field) {
  if (typeof value !== 'string' || value.length > 32 || !allowed.includes(value)) {
    throw new HttpsError('invalid-argument', `${field} is not supported.`);
  }
  return value;
}

function readPaymentMethod(value) {
  if (typeof value !== 'string' || value.length > 24 ||
      !Object.prototype.hasOwnProperty.call(paymentMethodMap, value)) {
    throw new HttpsError('invalid-argument', 'The selected payment method is not supported.');
  }
  return value;
}

function readOnlinePaymentMethod(value) {
  return readPaymentMethod(value);
}

function readCheckoutPaymentMethod(value) {
  if (value === 'cod') return value;
  return readOnlinePaymentMethod(value);
}

function readSupportedPaymentMethods(value) {
  if (value == null) return Object.keys(paymentMethodMap);
  if (!Array.isArray(value) || value.length < 1 || value.length > 3) {
    throw new HttpsError('invalid-argument', 'supportedMethods must contain one to three methods.');
  }
  const methods = value.map((method) => readPaymentMethod(method));
  if (new Set(methods).size !== methods.length) {
    throw new HttpsError('invalid-argument', 'supportedMethods cannot contain duplicates.');
  }
  return methods;
}

function assertAllowedKeys(data, allowed) {
  const allowedSet = new Set(allowed);
  for (const key of Object.keys(data)) {
    if (!allowedSet.has(key)) {
      throw new HttpsError('invalid-argument', `Unknown field: ${key}.`);
    }
  }
}

function makeReviewId(orderId, productId, variantId) {
  return `${orderId}_${productId}_${variantId}`.slice(0, 512);
}

function ratingDistribution(value) {
  const distribution = { '1': 0, '2': 0, '3': 0, '4': 0, '5': 0 };
  if (!isPlainObject(value)) return distribution;
  for (const key of Object.keys(distribution)) {
    distribution[key] = Number.isInteger(value[key]) && value[key] >= 0
      ? value[key]
      : 0;
  }
  return distribution;
}

function readIntegerOrThrow(value, field) {
  if (!Number.isInteger(value)) throw new Error(`${field} must be an integer.`);
  return value;
}

function readNonNegativeIntegerOrThrow(value, field) {
  const integer = readIntegerOrThrow(value, field);
  if (integer < 0) throw new Error(`${field} must not be negative.`);
  return integer;
}

function isHttpsUrl(value) {
  if (typeof value !== 'string' || value.length > 2048) return false;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && Boolean(url.hostname);
  } catch (_) {
    return false;
  }
}

function asDate(value) {
  if (value instanceof Date) return value;
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (value && typeof value.toDate === 'function') {
    const date = value.toDate();
    return date instanceof Date ? date : null;
  }
  return null;
}

function toIso(value) {
  return (asDate(value) || new Date(0)).toISOString();
}

function normalizeStatusTimeline(events, status, createdAt) {
  const timeline = Array.isArray(events)
    ? events.filter(isPlainObject).map((event) => ({
      from: typeof event.from === 'string' ? event.from : null,
      to: typeof event.to === 'string' ? event.to : String(status || 'pending_payment'),
      changedAt: toIso(event.changedAt),
      actorId: typeof event.actorId === 'string' ? event.actorId : 'system',
    }))
    : [];
  if (timeline.length > 0) return timeline;
  return [{
    from: null,
    to: String(status || 'pending_payment'),
    changedAt: toIso(createdAt),
    actorId: 'system',
  }];
}

function encodePurchaseCursor(createdAt) {
  const date = asDate(createdAt);
  if (!date) return null;
  return Buffer.from(JSON.stringify({ createdAt: date.toISOString() })).toString('base64url');
}

function readPurchaseCursor(value) {
  if (value == null) return null;
  const encoded = readString(value, 'cursor', { maxLength: 512 });
  try {
    const decoded = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
    const createdAt = asDate(decoded?.createdAt);
    if (!isPlainObject(decoded) || !createdAt) throw new Error('invalid cursor');
    return { createdAt };
  } catch (_) {
    throw new HttpsError('invalid-argument', 'cursor is invalid.');
  }
}

function mapPurchase(id, order) {
  const status = typeof order.status === 'string' ? order.status : 'pending_payment';
  const items = Array.isArray(order.items)
    ? order.items.filter(isPlainObject).map((item) => ({
      productId: typeof item.productId === 'string' ? item.productId : '',
      variantId: typeof item.variantId === 'string' ? item.variantId : '',
      productName: typeof item.productName === 'string' ? item.productName : '',
      variantLabel: typeof item.variantLabel === 'string' ? item.variantLabel : '',
      unitPriceCentavos: Number.isInteger(item.unitPriceCentavos)
        ? item.unitPriceCentavos : 0,
      quantity: Number.isInteger(item.quantity) ? item.quantity : 0,
    }))
    : [];
  const address = isPlainObject(order.shippingAddress) ? order.shippingAddress : {};
  const delivery = isPlainObject(order.deliveryOption) ? order.deliveryOption : {};
  return {
    id,
    userId: typeof order.userId === 'string' ? order.userId : '',
    status,
    statusLabel: statusLabel(status),
    statusTimeline: normalizeStatusTimeline(
      order.statusTimeline || order.events,
      status,
      order.createdAt,
    ),
    items,
    shippingAddress: {
      fullName: clipString(address.fullName),
      phoneNumber: clipString(address.phoneNumber),
      addressLine1: clipString(address.addressLine1),
      barangay: clipString(address.barangay),
      city: clipString(address.city),
      province: clipString(address.province),
      postalCode: clipString(address.postalCode),
      notes: clipString(address.notes),
    },
    deliveryOption: {
      id: clipString(delivery.id),
      name: clipString(delivery.name),
      feeCentavos: Number.isInteger(delivery.feeCentavos) ? delivery.feeCentavos : 0,
      estimatedDays: clipString(delivery.estimatedDays),
    },
    subtotalCentavos: Number.isInteger(order.subtotalCentavos) ? order.subtotalCentavos : 0,
    deliveryFeeCentavos: Number.isInteger(order.deliveryFeeCentavos)
      ? order.deliveryFeeCentavos : 0,
    totalCentavos: Number.isInteger(order.totalCentavos) ? order.totalCentavos : 0,
    paymentMethod: typeof order.paymentMethod === 'string' ? order.paymentMethod : null,
    paymentStatus: typeof order.paymentStatus === 'string' ? order.paymentStatus : 'unknown',
    paymentReference: typeof order.paymentReference === 'string' ? order.paymentReference : null,
    createdAt: toIso(order.createdAt),
    updatedAt: toIso(order.updatedAt),
  };
}

function isCartItem(item) {
  const fields = [
    'productId', 'variantId', 'productName', 'variantLabel', 'unitPriceCentavos', 'quantity',
  ];
  return isPlainObject(item) && Object.keys(item).length === fields.length &&
    fields.every((field) => Object.hasOwn(item, field)) &&
    typeof item.productId === 'string' && typeof item.variantId === 'string' &&
    readOptionalId(item.productId) === item.productId &&
    readOptionalId(item.variantId) === item.variantId &&
    typeof item.productName === 'string' && typeof item.variantLabel === 'string' &&
    Number.isInteger(item.unitPriceCentavos) && item.unitPriceCentavos >= 0 &&
    Number.isInteger(item.quantity) && item.quantity > 0 && item.quantity <= MAX_CART_ITEMS;
}

function hasDuplicateCartVariants(items) {
  return new Set(items.map((item) => `${item.productId}|${item.variantId}`)).size !== items.length;
}

function cartResponse(item, items, operationId, updatedAt) {
  return {
    serverConfirmed: true,
    noRedirect: true,
    operationId,
    updatedAt,
    cartItemCount: Array.isArray(items) ? items.length : 0,
    cartQuantity: isCartItem(item) ? item.quantity : 0,
    item: isCartItem(item) ? item : null,
  };
}

function selectedCartItems(value, cartItems) {
  if (value == null) {
    const seen = new Set();
    return cartItems.map((item) => {
      if (item.quantity > MAX_CART_ITEMS) {
        throw new HttpsError('failed-precondition', 'A cart line cannot exceed 100 units.');
      }
      const key = `${item.productId}|${item.variantId}`;
      if (seen.has(key)) {
        throw new HttpsError('failed-precondition', 'The cart contains duplicate variants.');
      }
      seen.add(key);
      return {
        productId: item.productId,
        variantId: item.variantId,
        quantity: item.quantity,
      };
    });
  }
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_CART_ITEMS) {
    throw new HttpsError('invalid-argument', 'selectedItems must contain one to 100 items.');
  }
  const seen = new Set();
  return value.map((rawItem) => {
    if (!isPlainObject(rawItem)) {
      throw new HttpsError('invalid-argument', 'Every selected cart item must be an object.');
    }
    assertAllowedKeys(rawItem, ['productId', 'variantId', 'quantity']);
    const productId = readId(rawItem.productId, 'selectedItems.productId');
    const variantId = readId(rawItem.variantId, 'selectedItems.variantId');
    const quantity = readInteger(rawItem.quantity, 'selectedItems.quantity');
    if (quantity < 1 || quantity > MAX_CART_ITEMS) {
      throw new HttpsError('invalid-argument', 'Selected quantity is out of range.');
    }
    const key = `${productId}|${variantId}`;
    if (seen.has(key)) {
      throw new HttpsError('invalid-argument', 'selectedItems cannot contain duplicates.');
    }
    seen.add(key);
    const cartItem = cartItems.find(
      (item) => item.productId === productId && item.variantId === variantId,
    );
    if (!cartItem || quantity > cartItem.quantity) {
      throw new HttpsError('failed-precondition', 'A selected cart quantity is no longer available.');
    }
    return { productId, variantId, quantity };
  });
}

function deliveryOptionById(value) {
  const id = readEnum(value, ['standard', 'express', 'same-day'], 'deliveryOptionId');
  const options = {
    standard: {
      id: 'standard',
      name: 'Standard Delivery',
      feeCentavos: 8000,
      estimatedDays: '3-5 business days',
    },
    express: {
      id: 'express',
      name: 'Express Delivery',
      feeCentavos: 15000,
      estimatedDays: '1-2 business days',
    },
    'same-day': {
      id: 'same-day',
      name: 'Same day delivery',
      feeCentavos: 25000,
      estimatedDays: 'Metro Manila only',
    },
  };
  if (!options[id]) {
    throw new HttpsError('invalid-argument', 'The selected delivery option is not supported.');
  }
  return options[id];
}

function paymentMethodLabel(method) {
  return {
    gcash: 'GCash',
    maya: 'Maya',
    card: 'Credit / Debit Card',
    cod: 'Cash on Delivery',
  }[method] || method;
}

function isReviewOrderItem(item) {
  const fields = [
    'productId', 'variantId', 'productName', 'variantLabel',
    'unitPriceCentavos', 'quantity',
  ];
  return isPlainObject(item) && Object.keys(item).length === fields.length &&
    fields.every((field) => Object.hasOwn(item, field)) &&
    readOptionalId(item.productId) === item.productId &&
    readOptionalId(item.variantId) === item.variantId &&
    typeof item.productName === 'string' && item.productName.length > 0 &&
    item.productName.length <= 256 && typeof item.variantLabel === 'string' &&
    item.variantLabel.length > 0 && item.variantLabel.length <= 128 &&
    Number.isSafeInteger(item.unitPriceCentavos) && item.unitPriceCentavos >= 0 &&
    Number.isInteger(item.quantity) && item.quantity > 0 && item.quantity <= MAX_CART_ITEMS;
}

async function resolveReviewAddress(userId, data) {
  const hasAddressId = data.addressId != null;
  const hasAddressMap = data.shippingAddress != null;
  if (hasAddressId === hasAddressMap) {
    throw new HttpsError(
      'invalid-argument',
      'Provide exactly one of addressId or shippingAddress.',
    );
  }
  if (hasAddressId) {
    const addressId = readId(data.addressId, 'addressId');
    const snapshot = await db.collection('users').doc(userId)
      .collection('addresses').doc(addressId).get();
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'The selected saved address does not exist.');
    }
    return normalizeReviewAddress(snapshot.data() || {}, addressId);
  }
  return normalizeReviewAddress(data.shippingAddress, null);
}

function normalizeReviewAddress(value, addressId) {
  if (!isPlainObject(value)) {
    throw new HttpsError('invalid-argument', 'shippingAddress must be an object.');
  }
  assertAllowedKeys(value, [
    'fullName', 'phoneNumber', 'addressLine1', 'barangay', 'city', 'province',
    'postalCode', 'notes', 'label', 'isDefault',
    'latitude', 'longitude', 'placeId', 'addressSource',
  ]);
  const city = readString(value.city, 'shippingAddress.city', { maxLength: 120 });
  const province = readString(value.province, 'shippingAddress.province', { maxLength: 120 });
  const address = {
    addressId,
    fullName: readString(value.fullName, 'shippingAddress.fullName', { maxLength: 120 }),
    phoneNumber: normalizePhilippineMobile(value.phoneNumber, 'shippingAddress.phoneNumber'),
    addressLine1: readString(value.addressLine1, 'shippingAddress.addressLine1', { maxLength: 240 }),
    barangay: readString(value.barangay, 'shippingAddress.barangay', { maxLength: 120 }),
    city,
    province: normalizePhilippineProvince(province, city),
    postalCode: readString(value.postalCode, 'shippingAddress.postalCode', { maxLength: 4 }),
    notes: readString(
      value.notes,
      'shippingAddress.notes',
      { maxLength: 500, required: false },
    ) || '',
  };
  if (!/^\d{4}$/.test(address.postalCode)) {
    throw new HttpsError('invalid-argument', 'shippingAddress.postalCode must contain four digits.');
  }
  if (value.label != null) address.label = readString(value.label, 'shippingAddress.label', { maxLength: 16 });
  if (value.isDefault != null) {
    if (typeof value.isDefault !== 'boolean') {
      throw new HttpsError('invalid-argument', 'shippingAddress.isDefault is invalid.');
    }
    address.isDefault = value.isDefault;
  }
  if (value.latitude != null) {
    if (typeof value.latitude !== 'number' || !Number.isFinite(value.latitude) ||
        value.latitude < -90 || value.latitude > 90) {
      throw new HttpsError('invalid-argument', 'shippingAddress.latitude is invalid.');
    }
    address.latitude = value.latitude;
  }
  if (value.longitude != null) {
    if (typeof value.longitude !== 'number' || !Number.isFinite(value.longitude) ||
        value.longitude < -180 || value.longitude > 180) {
      throw new HttpsError('invalid-argument', 'shippingAddress.longitude is invalid.');
    }
    address.longitude = value.longitude;
  }
  if (value.placeId != null) address.placeId = readId(value.placeId, 'shippingAddress.placeId');
  if (value.addressSource != null) {
    address.addressSource = readEnum(
      value.addressSource,
      ['manual', 'autocomplete'],
      'shippingAddress.addressSource',
    );
  }
  return address;
}

function normalizePhilippineMobile(value, field) {
  const phoneNumber = readString(value, field, { maxLength: 32 });
  if (/^09\d{9}$/.test(phoneNumber)) return `+63${phoneNumber.slice(1)}`;
  if (/^\+639\d{9}$/.test(phoneNumber)) return phoneNumber;
  throw new HttpsError('invalid-argument', `${field} must be a Philippine mobile number.`);
}

function normalizeAreaName(value) {
  return value.normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\b(city|municipality)\s+of\b/g, '')
    .replace(/\b(city|municipality)\b/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function normalizePhilippineProvince(province, city) {
  if (normalizeAreaName(province) === 'manila' &&
      NCR_LGU_NAMES.has(normalizeAreaName(city))) {
    return 'National Capital Region';
  }
  return province;
}

function assertDeliveryAddress(deliveryId, address) {
  if (deliveryId !== 'same-day') return;
  if (!NCR_PROVINCE_NAMES.has(normalizeAreaName(address.province)) ||
      !NCR_LGU_NAMES.has(normalizeAreaName(address.city))) {
    throw new HttpsError(
      'failed-precondition',
      'Same-day delivery is available only within Metro Manila.',
    );
  }
}

function clipString(value, maxLength = 512) {
  return typeof value === 'string' ? value.slice(0, maxLength) : '';
}

function readStoredString(value) {
  return typeof value === 'string' ? value.trim().slice(0, 256) : '';
}

function readStoredNumber(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

async function ensureStatusTimeline(snapshot) {
  const order = snapshot?.data();
  if (!order || !snapshot.ref) return;
  const timeline = normalizeStatusTimeline(order.events, order.status, order.createdAt);
  const existing = Array.isArray(order.statusTimeline) ? order.statusTimeline : [];
  if (JSON.stringify(existing) === JSON.stringify(timeline)) return;
  await snapshot.ref.set({ statusTimeline: timeline }, { merge: true });
}

async function ensureOrderPayment(snapshot) {
  const order = snapshot?.data();
  if (!order || order.paymentMethod || !order.id) return;
  const intentSnapshot = await db.collection('checkoutIntents').doc(order.id).get();
  const intent = intentSnapshot.data() || {};
  if (!intentSnapshot.exists || !Object.prototype.hasOwnProperty.call(paymentMethodMap, intent.paymentMethod)) {
    return;
  }
  await snapshot.ref.set({
    paymentMethod: intent.paymentMethod,
    paymentStatus: 'pending',
    paymentProvider: 'paymongo',
  }, { merge: true });
}

async function enforceRateLimit(scope, {
  limit,
  windowMs,
  message = 'Too many requests.',
}) {
  if (!Number.isInteger(limit) || limit < 1 || !Number.isInteger(windowMs) || windowMs < 1000) {
    throw new Error('Invalid rate-limit configuration.');
  }
  const documentId = crypto.createHash('sha256').update(scope).digest('hex');
  const reference = db.collection('rateLimits').doc(documentId);
  let retryAfterSeconds = 0;
  await db.runTransaction(async (transaction) => {
    retryAfterSeconds = 0;
    const snapshot = await transaction.get(reference);
    const now = Date.now();
    const current = snapshot.exists ? snapshot.data() || {} : {};
    const windowStart = asDate(current.windowStart)?.getTime() || 0;
    const count = Number.isInteger(current.count) ? current.count : 0;
    if (!windowStart || now - windowStart >= windowMs) {
      transaction.set(reference, {
        scopeHash: documentId,
        windowStart: new Date(now),
        count: 1,
        expiresAt: new Date(now + windowMs + 60 * 1000),
      });
      return;
    }
    if (count >= limit) {
      retryAfterSeconds = Math.max(1, Math.ceil((windowMs - (now - windowStart)) / 1000));
      return;
    }
    transaction.update(reference, {
      count: FieldValue.increment(1),
      expiresAt: new Date(windowStart + windowMs + 60 * 1000),
    });
  });
  if (retryAfterSeconds > 0) {
    throw new HttpsError('resource-exhausted', message, { retryAfterSeconds });
  }
}

function requestIp(request) {
  const forwarded = request.get('X-Forwarded-For');
  const candidate = typeof forwarded === 'string' ? forwarded.split(',')[0].trim() : '';
  return (candidate || request.ip || 'unknown').slice(0, 128);
}

function serializeCookie(value, maxAgeSeconds) {
  const encoded = value ? encodeURIComponent(value) : '';
  const maxAge = Number.isInteger(maxAgeSeconds) ? `Max-Age=${maxAgeSeconds}; ` : '';
  return `${SESSION_COOKIE_NAME}=${encoded}; ${maxAge}Path=/; HttpOnly; Secure; SameSite=Lax`;
}

async function notifyUser(userId, title, body, orderId) {
  const snapshot = await db.collection('users').doc(userId).collection('notificationTokens').get();
  const tokenDocuments = snapshot.docs
    .map((document) => ({ id: document.id, ref: document.ref, token: document.data().token }))
    .filter((entry) => typeof entry.token === 'string' && entry.token);
  if (!tokenDocuments.length) return;

  const result = await getMessaging().sendEachForMulticast({
    tokens: tokenDocuments.map((entry) => entry.token),
    notification: { title, body },
    data: { orderId, type: 'order_update' },
    android: {
      notification: {
        channelId: 'scentify_orders',
      },
    },
  });

  const deletes = [];
  result.responses.forEach((response, index) => {
    const code = response.error?.code || '';
    if (code.includes('registration-token-not-registered') || code.includes('invalid-registration-token')) {
      deletes.push(tokenDocuments[index].ref.delete());
    }
  });
  await Promise.all(deletes);
}

function statusLabel(status) {
  return String(status || 'updated').replaceAll('_', ' ');
}
