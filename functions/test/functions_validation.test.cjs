const assert = require('node:assert/strict');
const { createHash, createHmac, randomUUID } = require('node:crypto');
const { after, before, test } = require('node:test');
const { getFirestore } = require('firebase-admin/firestore');

process.env.GCLOUD_PROJECT = 'demo-scentify-rules';
process.env.GOOGLE_CLOUD_PROJECT = 'demo-scentify-rules';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.PAYMONGO_SECRET_KEY = 'test-secret';
process.env.PAYMONGO_WEBHOOK_SECRET = 'webhook-test-secret';
process.env.XENDIT_SECRET_KEY = 'xendit-test-secret';
process.env.XENDIT_WEBHOOK_TOKEN = 'xendit-test-token';

const functions = require('../index.js');
const db = getFirestore();
const { createFakeFirestore } = require('./fake_firestore.cjs');
createFakeFirestore(db);

before(async () => {
  await db.collection('_functionTests').doc('ready').set({ ready: true });
});

after(async () => {
  await db.collection('_functionTests').doc('ready').delete();
});

function fixture(overrides = {}) {
  const suffix = randomUUID();
  const userId = `user-${suffix}`;
  const orderId = `order-${suffix}`;
  const productId = `product-${suffix}`;
  const variantId = '50ml';
  const item = {
    productId,
    variantId,
    productName: 'Test Scent',
    variantLabel: '50ml',
    unitPriceCentavos: 42000,
    quantity: 1,
  };
  const address = {
    fullName: 'Juan Dela Cruz',
    phoneNumber: '09171234567',
    addressLine1: '123 Mabini Street',
    barangay: 'Barangay 1',
    city: 'Quezon City',
    province: 'Metro Manila',
    postalCode: '1100',
    notes: '',
  };
  const deliveryOption = {
    id: 'standard',
    name: 'Standard Delivery',
    feeCentavos: 8000,
    estimatedDays: '3-5 business days',
  };
  const order = {
    id: orderId,
    userId,
    items: [item],
    shippingAddress: address,
    deliveryOption,
    subtotalCentavos: 42000,
    deliveryFeeCentavos: 8000,
    totalCentavos: 50000,
    status: 'pending_payment',
    paymentReference: `cs_${suffix}`,
    paymentMethod: 'gcash',
  };
  const review = {
    orderId,
    userId,
    status: 'ready',
    currency: 'PHP',
    paymentMethod: 'gcash',
    orderItems: [item],
    shippingAddress: address,
    deliveryOption,
    subtotalCentavos: 42000,
    deliveryFeeCentavos: 8000,
    totalCentavos: 50000,
    amountCentavos: 50000,
    expiresAt: new Date(Date.now() + 5 * 60 * 1000),
  };
  const intent = {
    orderId,
    userId,
    amountCentavos: 50000,
    currency: 'PHP',
    paymentMethod: 'gcash',
    provider: 'paymongo',
    providerReference: order.paymentReference,
    paymentReference: order.paymentReference,
    reviewId: orderId,
    checkoutUrl: 'https://paymongo.com/checkout/test',
    status: 'pending',
    expiresAt: new Date(Date.now() + 20 * 60 * 1000),
  };
  return { ...{ userId, orderId, productId, variantId, item, address, deliveryOption, order, review, intent }, ...overrides };
}

async function seedCatalogAndCart(data, { stock = 20, quantity = 1 } = {}) {
  await db.collection('perfumes').doc(data.productId).set({
    isPublished: true,
    name: 'Test Scent',
    variants: [{ id: data.variantId, label: '50ml', priceCentavos: 42000, stock }],
  });
  await db.collection('carts').doc(data.userId).set({
    userId: data.userId,
    items: [{
      productId: data.productId,
      variantId: data.variantId,
      productName: 'Test Scent',
      variantLabel: '50ml',
      unitPriceCentavos: 42000,
      quantity,
    }],
  });
}

async function seedExistingCheckout(data) {
  await db.collection('orders').doc(data.orderId).set(data.order);
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await db.collection('checkoutIntents').doc(data.orderId).set(data.intent);
  await seedCatalogAndCart(data, { stock: 19 });
  await db.collection('inventoryReservations').doc(data.orderId).set({
    orderId: data.orderId,
    userId: data.userId,
    provider: 'paymongo',
    status: 'reserved',
    items: [{ productId: data.productId, variantId: data.variantId, quantity: 1 }],
  });
}

function reviewRequest(data, userId = data.userId, address = data.address) {
  return {
    auth: { uid: userId },
    data: {
      orderId: data.orderId,
      selectedItems: [{
        productId: data.productId,
        variantId: data.variantId,
        quantity: 1,
      }],
      shippingAddress: address,
      deliveryOptionId: 'standard',
      paymentMethod: 'gcash',
      currency: 'PHP',
    },
  };
}

function freshReviewRequest(data, overrides = {}) {
  return {
    auth: { uid: data.userId },
    data: {
      orderId: data.orderId,
      selectedItems: [{ productId: data.productId, variantId: data.variantId, quantity: 1 }],
      shippingAddress: data.address,
      deliveryOptionId: 'standard',
      paymentMethod: 'gcash',
      currency: 'PHP',
      ...overrides,
    },
  };
}

async function deliverPaidEvent(data, eventId, {
  timestamp = String(Math.floor(Date.now() / 1000)),
  signatureHeader,
  signatureHeaderName = 'Paymongo-Signature',
  signatureField = 'te',
  resourceAttributes = {},
} = {}) {
  const resource = {
    id: data.intent.providerReference,
    attributes: {
      ...resourceAttributes,
      reference_number: data.orderId,
      metadata: { scentifyOrderId: data.orderId },
    },
  };
  const body = {
    data: {
      id: eventId,
      attributes: { type: 'checkout_session.payment.paid', data: resource },
    },
  };
  const rawBody = Buffer.from(JSON.stringify(body));
  const digest = createHmac('sha256', process.env.PAYMONGO_WEBHOOK_SECRET)
    .update(`${timestamp}.${rawBody.toString('utf8')}`)
    .digest('hex');
  const webhookIp = data.webhookIp || '127.0.0.1';
  const headers = {
    [signatureHeaderName]: signatureHeader ?? `t=${timestamp},${signatureField}=${digest}`,
    'X-Forwarded-For': webhookIp,
  };
  const request = {
    method: 'POST',
    rawBody,
    body,
    ip: webhookIp,
    get: (name) => headers[name] || null,
  };
  const response = {
    statusCode: null,
    headers: {},
    setHeader(name, value) { this.headers[name] = value; },
    sendStatus(status) { this.statusCode = status; return this; },
    status(status) { this.statusCode = status; return this; },
    json(value) { this.body = value; return this; },
  };
  await functions.paymongoWebhook(request, response);
  return response;
}

test('getOrderReview rejects an order ID owned by another user without replacing its review', async () => {
  const data = fixture();
  const attackerId = `attacker-${randomUUID()}`;
  await seedExistingCheckout(data);
  await db.collection('carts').doc(attackerId).set({
    userId: attackerId,
    items: [{
      productId: data.productId,
      variantId: data.variantId,
      productName: 'Test Scent',
      variantLabel: '50ml',
      unitPriceCentavos: 42000,
      quantity: 1,
    }],
  });
  const originalReview = await db.collection('orderReviews').doc(data.orderId).get();

  await assert.rejects(functions.getOrderReview.run(reviewRequest(data, attackerId)));

  const currentReview = await db.collection('orderReviews').doc(data.orderId).get();
  assert.deepEqual(currentReview.data(), originalReview.data());
});

test('getOrderReview rejects an order ID used by another user review', async () => {
  const owner = fixture();
  const attacker = fixture({ orderId: owner.orderId });
  await db.collection('orderReviews').doc(owner.orderId).set(owner.review);
  await seedCatalogAndCart(attacker);
  const originalReview = await db.collection('orderReviews').doc(owner.orderId).get();

  await assert.rejects(functions.getOrderReview.run(reviewRequest(attacker)));

  const currentReview = await db.collection('orderReviews').doc(owner.orderId).get();
  assert.deepEqual(currentReview.data(), originalReview.data());
});

test('getOrderReview allows same-user quote refresh before an order or intent binds the ID', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await seedCatalogAndCart(data);
  const changedAddress = { ...data.address, addressLine1: '456 Changed Street' };

  await functions.getOrderReview.run(reviewRequest(data, data.userId, changedAddress));

  const currentReview = (await db.collection('orderReviews').doc(data.orderId).get()).data();
  assert.equal(currentReview.shippingAddress.addressLine1, '456 Changed Street');
});

test('getOrderReview rejects same-user snapshot changes for an existing order', async () => {
  const data = fixture();
  await seedExistingCheckout(data);
  const changedAddress = { ...data.address, addressLine1: '456 Changed Street' };

  await assert.rejects(functions.getOrderReview.run(reviewRequest(data, data.userId, changedAddress)));

  const currentReview = (await db.collection('orderReviews').doc(data.orderId).get()).data();
  assert.equal(currentReview.shippingAddress.addressLine1, data.address.addressLine1);
});

test('getOrderReview rejects same-user snapshot mutation after a pending intent binds the ID', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await db.collection('checkoutIntents').doc(data.orderId).set(data.intent);
  await seedCatalogAndCart(data);
  const changedAddress = { ...data.address, addressLine1: '456 Changed Street' };

  await assert.rejects(functions.getOrderReview.run(reviewRequest(data, data.userId, changedAddress)));

  const currentReview = (await db.collection('orderReviews').doc(data.orderId).get()).data();
  assert.equal(currentReview.shippingAddress.addressLine1, data.address.addressLine1);
});

test('createPayMongoCheckoutSession rejects reuse when the existing order snapshot differs', async () => {
  const data = fixture();
  await seedExistingCheckout(data);
  await db.collection('orders').doc(data.orderId).update({
    shippingAddress: { ...data.address, addressLine1: '456 Changed Street' },
  });

  await assert.rejects(functions.createPayMongoCheckoutSession.run({
    auth: { uid: data.userId },
    data: {
      orderId: data.orderId,
      amountCentavos: 50000,
      currency: 'PHP',
      paymentMethod: 'gcash',
      supportedMethods: ['gcash'],
    },
  }));
});

test('createPayMongoCheckoutSession rejects a review with a mismatched order ID', async () => {
  const data = fixture();
  await seedExistingCheckout(data);
  await db.collection('orderReviews').doc(data.orderId).update({ orderId: 'different-order' });

  await assert.rejects(functions.createPayMongoCheckoutSession.run({
    auth: { uid: data.userId },
    data: {
      orderId: data.orderId,
      amountCentavos: 50000,
      currency: 'PHP',
      paymentMethod: 'gcash',
      supportedMethods: ['gcash'],
    },
  }));
});

test('createPayMongoCheckoutSession creates a checkout and persists its intent', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await seedCatalogAndCart(data, { stock: 12 });
  await db.collection('perfumes').doc(data.productId).update({
    variants: [
      { id: data.variantId, label: '50ml', priceCentavos: 42000, stock: 12 },
      { id: '100ml', label: '100ml', priceCentavos: 62000, stock: 7 },
    ],
  });
  const sessionId = `cs_${randomUUID()}`;
  const checkoutUrl = `https://paymongo.com/checkout/${sessionId}`;
  const originalFetch = global.fetch;
  let requestOptions;
  global.fetch = async (_url, options) => {
    requestOptions = options;
    return {
      ok: true,
      async json() {
        return { data: { id: sessionId, attributes: { checkout_url: checkoutUrl } } };
      },
    };
  };

  try {
    const result = await functions.createPayMongoCheckoutSession.run({
      auth: { uid: data.userId },
      data: {
        orderId: data.orderId,
        amountCentavos: 50000,
        currency: 'PHP',
        paymentMethod: 'gcash',
        supportedMethods: ['gcash'],
      },
    });

    assert.deepEqual(result, {
      provider: 'paymongo',
      reference: sessionId,
      checkoutUrl,
      paymentMethod: 'gcash',
      orderCreatedOnServer: true,
    });
    assert.equal(requestOptions.method, 'POST');
    const intent = (await db.collection('checkoutIntents').doc(data.orderId).get()).data();
    assert.equal(intent.orderId, data.orderId);
    assert.equal(intent.userId, data.userId);
    assert.equal(intent.amountCentavos, 50000);
    assert.equal(intent.currency, 'PHP');
    assert.equal(intent.paymentMethod, 'gcash');
    assert.equal(intent.provider, 'paymongo');
    assert.equal(intent.reviewId, data.orderId);
    assert.equal(intent.paymentReference, sessionId);
    assert.equal(intent.providerReference, sessionId);
    assert.equal(intent.checkoutUrl, checkoutUrl);
    assert.equal(intent.status, 'pending');
    const order = (await db.collection('orders').doc(data.orderId).get()).data();
    assert.equal(order.status, 'pending_payment');
    assert.equal(order.paymentReference, sessionId);
    assert.equal(order.paymentProvider, 'paymongo');
    assert.deepEqual(
      (await db.collection('perfumes').doc(data.productId).get()).data().variants.map((variant) => variant.stock),
      [11, 7],
    );
    assert.equal((await db.collection('inventoryReservations').doc(data.orderId).get()).data().status, 'reserved');
    assert.equal((await db.collection('carts').doc(data.userId).get()).exists, false);
  } finally {
    global.fetch = originalFetch;
  }
});

test('createPayMongoCheckoutSession claims one provider session under concurrent requests', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await seedCatalogAndCart(data, { stock: 12 });
  const originalFetch = global.fetch;
  let fetchCalls = 0;
  const sessionId = `cs_${randomUUID()}`;
  const checkoutUrl = `https://paymongo.com/checkout/${sessionId}`;
  global.fetch = async () => {
    fetchCalls += 1;
    await new Promise((resolve) => setTimeout(resolve, 10));
    return {
      ok: true,
      async json() {
        return { data: { id: sessionId, attributes: { checkout_url: checkoutUrl } } };
      },
    };
  };
  const request = {
    auth: { uid: data.userId },
    data: {
      orderId: data.orderId,
      amountCentavos: 50000,
      currency: 'PHP',
      paymentMethod: 'gcash',
      supportedMethods: ['gcash'],
    },
  };

  try {
    const results = await Promise.allSettled([
      functions.createPayMongoCheckoutSession.run(request),
      functions.createPayMongoCheckoutSession.run(request),
    ]);

    assert.equal(fetchCalls, 1);
    assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
    const rejected = results.find((result) => result.status === 'rejected');
    assert.equal(rejected.reason.code, 'aborted');

    const retry = await functions.createPayMongoCheckoutSession.run(request);
    assert.deepEqual(retry, {
      provider: 'paymongo',
      reference: sessionId,
      checkoutUrl,
      paymentMethod: 'gcash',
      orderCreatedOnServer: true,
    });
    assert.equal(fetchCalls, 1);
  } finally {
    global.fetch = originalFetch;
  }
});

test('createXenditCheckoutSession creates a hosted payment session', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await seedCatalogAndCart(data, { stock: 12 });
  await db.collection('perfumes').doc(data.productId).update({
    variants: [
      { id: data.variantId, label: '50ml', priceCentavos: 42000, stock: 12 },
      { id: '100ml', label: '100ml', priceCentavos: 62000, stock: 7 },
    ],
  });
  const originalFetch = global.fetch;
  let requestOptions;
  global.fetch = async (_url, options) => {
    requestOptions = options;
    return {
      ok: true,
      async json() {
        return {
          payment_session_id: 'ps-1234567890123456789012345',
          payment_link_url: 'https://checkout-staging.xendit.co/sessions/test',
          expires_at: new Date(Date.now() + 60000).toISOString(),
        };
      },
    };
  };
  try {
    const result = await functions.createXenditCheckoutSession.run({
      auth: { uid: data.userId },
      data: {
        orderId: data.orderId,
        amountCentavos: 50000,
        currency: 'PHP',
        paymentMethod: 'gcash',
        supportedMethods: ['gcash'],
      },
    });
    assert.equal(result.provider, 'xendit');
    assert.match(result.checkoutUrl, /^https:\/\/checkout-staging\.xendit\.co\//);
    const xenditPayload = JSON.parse(requestOptions.body);
    assert.equal(xenditPayload.allowed_payment_channels[0], 'GCASH');
    assert.equal(xenditPayload.allow_save_payment_method, 'DISABLED');
    assert.equal(xenditPayload.amount, 500);
    const intent = (await db.collection('checkoutIntents').doc(data.orderId).get()).data();
    assert.equal(intent.provider, 'xendit');
    assert.equal(intent.paymentReference, result.reference);
    assert.equal(result.orderCreatedOnServer, true);
    const order = (await db.collection('orders').doc(data.orderId).get()).data();
    assert.equal(order.status, 'pending_payment');
    assert.equal(order.paymentReference, result.reference);
    const product = (await db.collection('perfumes').doc(data.productId).get()).data();
    assert.deepEqual(product.variants.map((variant) => variant.stock), [11, 7]);
    assert.equal((await db.collection('carts').doc(data.userId).get()).exists, false);
    assert.equal((await db.collection('inventoryReservations').doc(data.orderId).get()).data().status, 'reserved');
  } finally {
    global.fetch = originalFetch;
  }
});

test('createXenditCheckoutSession rejects insufficient variant stock before returning checkout', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await seedCatalogAndCart(data, { stock: 0 });
  const originalFetch = global.fetch;
  let fetchCalls = 0;
  global.fetch = async () => { fetchCalls += 1; throw new Error('should not create a session'); };

  try {
    await assert.rejects(functions.createXenditCheckoutSession.run({
      auth: { uid: data.userId },
      data: {
        orderId: data.orderId,
        amountCentavos: 50000,
        currency: 'PHP',
        paymentMethod: 'gcash',
        supportedMethods: ['gcash'],
      },
    }));
    assert.equal(fetchCalls, 0);
    assert.equal((await db.collection('orders').doc(data.orderId).get()).exists, false);
    assert.equal((await db.collection('carts').doc(data.userId).get()).exists, true);
  } finally {
    global.fetch = originalFetch;
  }
});

test('Xendit payment-session expiry releases its reserved variant stock once', async () => {
  const data = fixture();
  await db.collection('orders').doc(data.orderId).set(data.order);
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await db.collection('checkoutIntents').doc(data.orderId).set(data.intent);
  await db.collection('checkoutIntents').doc(data.orderId).update({ provider: 'xendit' });
  await db.collection('inventoryReservations').doc(data.orderId).set({
    orderId: data.orderId,
    status: 'reserved',
    items: [{ productId: data.productId, variantId: data.variantId, quantity: 1 }],
  });
  await db.collection('perfumes').doc(data.productId).set({
    isPublished: true,
    name: 'Test Scent',
    variants: [{ id: data.variantId, label: '50ml', priceCentavos: 42000, stock: 11 }],
  });
  const body = {
    event: 'payment_session.expired',
    created: new Date().toISOString(),
    data: {
      payment_session_id: data.intent.providerReference,
      reference_id: data.orderId,
      status: 'EXPIRED',
    },
  };
  const response = { sendStatus(status) { this.statusCode = status; return this; } };
  const request = {
    method: 'POST',
    body,
    get: (name) => name === 'x-callback-token' ? 'xendit-test-token' : null,
  };

  await functions.xenditWebhook(request, response);
  await functions.xenditWebhook(request, response);

  assert.equal(response.statusCode, 200);
  assert.equal((await db.collection('perfumes').doc(data.productId).get()).data().variants[0].stock, 12);
  assert.equal((await db.collection('inventoryReservations').doc(data.orderId).get()).data().status, 'released');
  assert.equal((await db.collection('orders').doc(data.orderId).get()).data().status, 'cancelled');
});

test('Xendit completed-session webhook verifies the amount and commits the existing stock reservation', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await seedCatalogAndCart(data, { stock: 12 });
  const originalFetch = global.fetch;
  const sessionId = 'ps-661f87c614802d6c402cd82d';
  global.fetch = async () => ({
    ok: true,
    async json() {
      return {
        payment_session_id: sessionId,
        payment_link_url: 'https://checkout-staging.xendit.co/sessions/test',
        expires_at: new Date(Date.now() + 60000).toISOString(),
      };
    },
  });

  try {
    await functions.createXenditCheckoutSession.run({
      auth: { uid: data.userId },
      data: {
        orderId: data.orderId,
        amountCentavos: 50000,
        currency: 'PHP',
        paymentMethod: 'gcash',
        supportedMethods: ['gcash'],
      },
    });
  } finally {
    global.fetch = originalFetch;
  }

  const response = {
    sendStatus(status) { this.statusCode = status; return this; },
  };
  await functions.xenditWebhook({
    method: 'POST',
    body: {
      event: 'payment_session.completed',
      data: {
        payment_session_id: sessionId,
        reference_id: data.orderId,
        status: 'COMPLETED',
        amount: 500,
        currency: 'PHP',
        payment_id: 'py-661f87c614802d6c402cd82d',
      },
    },
    get: (name) => name === 'x-callback-token' ? 'xendit-test-token' : null,
  }, response);

  assert.equal(response.statusCode, 200);
  assert.equal((await db.collection('orders').doc(data.orderId).get()).data().paymentStatus, 'paid');
  assert.equal((await db.collection('perfumes').doc(data.productId).get()).data().variants[0].stock, 11);
});

test('adjustInventory is admin-only and audits the variant adjustment', async () => {
  const data = fixture();
  await seedCatalogAndCart(data, { stock: 12 });

  await assert.rejects(functions.adjustInventory.run({
    auth: { uid: data.userId },
    data: { productId: data.productId, variantId: data.variantId, delta: 3, reason: 'Restock' },
  }), (error) => error.code === 'permission-denied');

  const result = await functions.adjustInventory.run({
    auth: { uid: 'admin-user', token: { admin: true } },
    data: { productId: data.productId, variantId: data.variantId, delta: 3, reason: 'Restock' },
  });
  assert.deepEqual(result, { productId: data.productId, variantId: data.variantId, stock: 15 });
  await assert.rejects(functions.adjustInventory.run({
    auth: { uid: 'admin-user', token: { admin: true } },
    data: { productId: data.productId, variantId: data.variantId, delta: -16, reason: 'Correction' },
  }), (error) => error.code === 'failed-precondition');
  const decrement = await functions.adjustInventory.run({
    auth: { uid: 'admin-user', token: { admin: true } },
    data: { productId: data.productId, variantId: data.variantId, delta: -2, reason: 'Correction' },
  });
  assert.equal(decrement.stock, 13);
  const adjustments = await db.collection('inventoryAdjustments').get();
  assert.equal(adjustments.docs.some((doc) => doc.data().actorId === 'admin-user' && doc.data().delta === 3), true);
});

test('listMyPurchases returns an opaque cursor for the next page', async () => {
  const data = fixture();
  const createdAt = [
    new Date('2026-03-03T00:00:00.000Z'),
    new Date('2026-03-02T00:00:00.000Z'),
    new Date('2026-03-01T00:00:00.000Z'),
  ];
  for (let index = 0; index < createdAt.length; index++) {
    const orderId = `${data.orderId}-${index}`;
    await db.collection('orders').doc(orderId).set({
      ...data.order,
      id: orderId,
      createdAt: createdAt[index],
      updatedAt: createdAt[index],
    });
  }

  const firstPage = await functions.listMyPurchases.run({
    auth: { uid: data.userId },
    data: { limit: 2 },
  });
  assert.deepEqual(firstPage.purchases.map((purchase) => purchase.id), [
    `${data.orderId}-0`,
    `${data.orderId}-1`,
  ]);
  assert.equal(typeof firstPage.nextCursor, 'string');

  const secondPage = await functions.listMyPurchases.run({
    auth: { uid: data.userId },
    data: { limit: 2, cursor: firstPage.nextCursor },
  });
  assert.deepEqual(secondPage.purchases.map((purchase) => purchase.id), [
    `${data.orderId}-2`,
  ]);
  assert.equal(secondPage.nextCursor, null);
});

test('submitProductRating saves one verified review and updates product ratings', async () => {
  const data = fixture();
  await db.collection('orders').doc(data.orderId).set({
    ...data.order,
    status: 'delivered',
  });
  await db.collection('perfumes').doc(data.productId).set({
    isPublished: true,
    ratingSum: 0,
    reviewCount: 0,
  });
  const request = {
    auth: { uid: data.userId },
    data: {
      orderId: data.orderId,
      productId: data.productId,
      variantId: data.variantId,
      rating: 5,
      comment: 'Lasts all day.',
    },
  };

  const result = await functions.submitProductRating.run(request);
  const saved = (await db.collection('perfumes').doc(data.productId)
    .collection('ratings').doc(result.reviewId).get()).data();
  const product = (await db.collection('perfumes').doc(data.productId).get()).data();
  assert.equal(saved.userId, data.userId);
  assert.equal(saved.verifiedPurchase, true);
  assert.equal(saved.comment, 'Lasts all day.');
  assert.equal(product.reviewCount, 1);
  assert.equal(product.ratingSum, 5);
  assert.equal(product.ratingAverage, 5);
  await assert.rejects(
    functions.submitProductRating.run(request),
    (error) => error.code === 'already-exists',
  );
});

test('listMyPurchases does not infer paid status for older orders', async () => {
  const data = fixture();
  await db.collection('orders').doc(data.orderId).set({
    ...data.order,
    status: 'delivered',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  const result = await functions.listMyPurchases.run({
    auth: { uid: data.userId },
    data: {},
  });
  assert.equal(result.purchases[0].paymentMethod, 'gcash');
  assert.equal(result.purchases[0].paymentStatus, 'unknown');
});

test('getOrderReview normalizes valid Philippine mobile numbers', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);
  const result = await functions.getOrderReview.run(freshReviewRequest(data));

  assert.equal(result.shippingAddressSnapshot.phoneNumber, '+639171234567');
  assert.equal(
    (await db.collection('orderReviews').doc(data.orderId).get()).data()
      .shippingAddress.phoneNumber,
    '+639171234567',
  );
});

test('getOrderReview normalizes Manila to NCR for a Caloocan address', async () => {
  const data = fixture();
  data.address = {
    ...data.address,
    province: 'Manila',
    city: 'Caloocan City',
    barangay: 'Barangay 123',
    postalCode: '1400',
  };
  await seedCatalogAndCart(data);

  const result = await functions.getOrderReview.run(freshReviewRequest(data, {
    deliveryOptionId: 'same-day',
  }));
  const review = (await db.collection('orderReviews').doc(data.orderId).get()).data();

  assert.equal(result.shippingAddressSnapshot.province, 'National Capital Region');
  assert.equal(result.shippingAddressSnapshot.city, 'Caloocan City');
  assert.equal(result.shippingAddressSnapshot.barangay, 'Barangay 123');
  assert.equal(result.shippingAddressSnapshot.postalCode, '1400');
  assert.equal(review.shippingAddress.city, 'Caloocan City');
  assert.equal(review.shippingAddress.province, 'National Capital Region');
  assert.equal(review.shippingAddress.postalCode, '1400');
});

test('COD order creation confirms fulfillment without collecting payment and consumes stock once', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);
  const address = {
    ...data.address,
      barangay: 'Barangay 132',
      city: 'Caloocan City',
      province: 'National Capital Region',
      postalCode: '1400',
  };
  await functions.getOrderReview.run(freshReviewRequest(data, {
    paymentMethod: 'cod',
    deliveryOptionId: 'same-day',
    shippingAddress: address,
  }));

  const request = { auth: { uid: data.userId }, data: { orderId: data.orderId } };
  const first = await functions.createCashOnDeliveryOrder.run(request);
  const retry = await functions.createCashOnDeliveryOrder.run(request);
  const order = (await db.collection('orders').doc(data.orderId).get()).data();
  const cart = (await db.collection('carts').doc(data.userId).get()).data();
  const product = (await db.collection('perfumes').doc(data.productId).get()).data();

  assert.equal(first.orderId, data.orderId);
  assert.equal(retry.orderId, data.orderId);
  assert.equal(order.userId, data.userId);
  assert.equal(order.status, 'confirmed');
  assert.equal(order.paymentMethod, 'cod');
  assert.equal(order.paymentStatus, 'pending_collection');
  assert.equal(order.shippingAddress.barangay, 'Barangay 132');
  assert.equal(order.shippingAddress.postalCode, '1400');
  assert.equal(order.totalCentavos, 67000);
  assert.equal(cart, undefined);
  assert.equal(product.variants[0].stock, 19);
});

test('COD order creation rejects insufficient stock without clearing the cart', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set({
    ...data.review,
    paymentMethod: 'cod',
  });
  await seedCatalogAndCart(data, { stock: 0 });

  await assert.rejects(
    functions.createCashOnDeliveryOrder.run({
      auth: { uid: data.userId },
      data: { orderId: data.orderId },
    }),
  );

  assert.equal((await db.collection('orders').doc(data.orderId).get()).exists, false);
  assert.equal((await db.collection('carts').doc(data.userId).get()).data().items.length, 1);
  assert.equal(
    (await db.collection('perfumes').doc(data.productId).get()).data().variants[0].stock,
    0,
  );
});

test('COD creation removes only quoted cart lines', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);
  const otherProductId = `other-${randomUUID()}`;
  await db.collection('perfumes').doc(otherProductId).set({
    isPublished: true,
    name: 'Other Scent',
    variants: [{ id: '30ml', label: '30ml', priceCentavos: 17000, stock: 4 }],
  });
  const cartRef = db.collection('carts').doc(data.userId);
  await cartRef.update({
    items: [
      ...(await cartRef.get()).data().items,
      {
        productId: otherProductId,
        variantId: '30ml',
        productName: 'Other Scent',
        variantLabel: '30ml',
        unitPriceCentavos: 17000,
        quantity: 2,
      },
    ],
  });
  await functions.getOrderReview.run(freshReviewRequest(data, {
    paymentMethod: 'cod',
    selectedItems: [{ productId: data.productId, variantId: data.variantId, quantity: 1 }],
  }));

  await functions.createCashOnDeliveryOrder.run({
    auth: { uid: data.userId },
    data: { orderId: data.orderId },
  });

  const cart = (await cartRef.get()).data();
  assert.equal(cart.items.length, 1);
  assert.equal(cart.items[0].productId, otherProductId);
  assert.equal(cart.items[0].quantity, 2);
});

test('COD order creation rejects online payment reviews and requests from another user', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set(data.review);
  await seedCatalogAndCart(data);

  await assert.rejects(
    functions.createCashOnDeliveryOrder.run({
      auth: { uid: data.userId },
      data: { orderId: data.orderId },
    }),
  );
  await assert.rejects(
    functions.createCashOnDeliveryOrder.run({
      auth: { uid: `other-${randomUUID()}` },
      data: { orderId: data.orderId },
    }),
  );
  assert.equal((await db.collection('orders').doc(data.orderId).get()).exists, false);
});

test('PayMongo session creation rejects COD instead of treating it as online payment', async () => {
  const data = fixture();
  await db.collection('orderReviews').doc(data.orderId).set({
    ...data.review,
    paymentMethod: 'cod',
  });

  await assert.rejects(functions.createPayMongoCheckoutSession.run({
    auth: { uid: data.userId },
    data: {
      orderId: data.orderId,
      amountCentavos: data.review.totalCentavos,
      currency: 'PHP',
      paymentMethod: 'cod',
      supportedMethods: ['cod'],
    },
  }));
});

test('getOrderReview rejects ZIP codes that are not four digits', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);

  await assert.rejects(
    functions.getOrderReview.run(freshReviewRequest(data, {
      shippingAddress: { ...data.address, postalCode: '11000' },
    })),
    (error) => error.code === 'invalid-argument',
  );
  assert.equal((await db.collection('orderReviews').doc(data.orderId).get()).exists, false);
});

test('getOrderReview rejects non-Philippine mobile phone formats', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);

  await assert.rejects(
    functions.getOrderReview.run(freshReviewRequest(data, {
      shippingAddress: { ...data.address, phoneNumber: '0917123456' },
    })),
    (error) => error.code === 'invalid-argument',
  );
});

test('getOrderReview rejects same-day delivery outside the NCR service area', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);

  await assert.rejects(
    functions.getOrderReview.run(freshReviewRequest(data, {
      deliveryOptionId: 'same-day',
      shippingAddress: {
        ...data.address,
        city: 'Cebu City',
        province: 'Cebu',
      },
    })),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal((await db.collection('orderReviews').doc(data.orderId).get()).exists, false);
});

for (const [caseName, invalidItem] of [
  ['null product ID', { productId: null }],
  ['null variant ID', { variantId: null }],
  ['non-string product ID', { productId: 42 }],
  ['non-string variant ID', { variantId: 42 }],
  ['unsafe product ID', { productId: 'unsafe/id' }],
  ['unsafe variant ID', { variantId: 'unsafe/id' }],
  ['extra item key', { unexpected: true }],
  ['zero quantity', { quantity: 0 }],
  ['non-integer quantity', { quantity: 1.5 }],
  ['non-number quantity', { quantity: '1' }],
  ['out-of-range quantity', { quantity: 101 }],
]) {
  test(`addToCart preserves a cart with ${caseName} by rejecting the write`, async () => {
    const data = fixture();
    await seedCatalogAndCart(data);
    const cartRef = db.collection('carts').doc(data.userId);
    const originalItems = [{ ...data.item, ...invalidItem }];
    await cartRef.update({ items: originalItems });
    const originalCart = (await cartRef.get()).data();

    await assert.rejects(
      functions.addToCart.run({
        auth: { uid: data.userId },
        data: {
          productId: data.productId,
          variantId: data.variantId,
          quantity: 1,
          operationId: `add-${randomUUID()}`,
        },
      }),
      (error) => error.code === 'failed-precondition',
    );

    assert.deepEqual((await cartRef.get()).data(), originalCart);
  });
}

test('addToCart preserves duplicate variant lines by rejecting the write', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);
  const cartRef = db.collection('carts').doc(data.userId);
  const originalItems = [data.item, data.item];
  await cartRef.update({ items: originalItems });
  const originalCart = (await cartRef.get()).data();

  await assert.rejects(
    functions.addToCart.run({
      auth: { uid: data.userId },
      data: {
        productId: data.productId,
        variantId: data.variantId,
        quantity: 1,
        operationId: `add-${randomUUID()}`,
      },
    }),
    (error) => error.code === 'failed-precondition',
  );

  assert.deepEqual((await cartRef.get()).data(), originalCart);
});

test('addToCart validates malformed cart state before idempotent replay', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);
  const cartRef = db.collection('carts').doc(data.userId);
  await cartRef.update({
    items: [{ ...data.item, quantity: 0 }],
    lastOperationId: 'same-operation',
    serverConfirmed: true,
  });
  const originalCart = (await cartRef.get()).data();

  await assert.rejects(
    functions.addToCart.run({
      auth: { uid: data.userId },
      data: {
        productId: data.productId,
        variantId: data.variantId,
        quantity: 1,
        operationId: 'same-operation',
      },
    }),
    (error) => error.code === 'failed-precondition',
  );

  assert.deepEqual((await cartRef.get()).data(), originalCart);
});

test('addToCart replays one increment using the catalog price and same item response', async () => {
  const data = fixture();
  await seedCatalogAndCart(data, { quantity: 1 });
  const cartRef = db.collection('carts').doc(data.userId);
  await cartRef.update({
    items: [{ ...data.item, unitPriceCentavos: 1 }],
  });
  const operationId = `add-${randomUUID()}`;
  const request = {
    auth: { uid: data.userId },
    data: {
      productId: data.productId,
      variantId: data.variantId,
      quantity: 2,
      operationId,
    },
  };

  const first = await functions.addToCart.run(request);
  const afterFirst = (await cartRef.get()).data();
  const replay = await functions.addToCart.run(request);
  const afterReplay = (await cartRef.get()).data();

  assert.equal(first.operationId, operationId);
  assert.equal(replay.operationId, operationId);
  assert.equal(first.cartQuantity, 3);
  assert.equal(replay.cartQuantity, 3);
  assert.deepEqual(replay.item, first.item);
  assert.equal(first.item.unitPriceCentavos, 42000);
  assert.equal(afterReplay.items[0].quantity, 3);
  assert.equal(afterReplay.items[0].unitPriceCentavos, 42000);
  assert.deepEqual(afterReplay.items, afterFirst.items);
});

test('addToCart rejects an accumulated line quantity above 100', async () => {
  const data = fixture();
  await seedCatalogAndCart(data, { stock: 200, quantity: 1 });

  await assert.rejects(functions.addToCart.run({
    auth: { uid: data.userId },
    data: {
      productId: data.productId,
      variantId: data.variantId,
      quantity: 100,
      operationId: `add-${randomUUID()}`,
    },
  }));

  const cart = (await db.collection('carts').doc(data.userId).get()).data();
  assert.equal(cart.items[0].quantity, 1);
});

test('getOrderReview rejects malformed stored cart entries instead of filtering them', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);
  const validItem = data.item;
  await db.collection('carts').doc(data.userId).update({
    items: [
      validItem,
      { ...validItem, variantId: 'other-variant', quantity: 101 },
      { ...validItem, variantId: 'extra-key-variant', unexpected: true },
    ],
  });

  await assert.rejects(
    functions.getOrderReview.run(reviewRequest(data)),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal((await db.collection('orderReviews').doc(data.orderId).get()).exists, false);
});

test('getOrderReview rejects duplicate variants in a stored cart', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);
  await db.collection('carts').doc(data.userId).update({
    items: [data.item, data.item],
  });

  await assert.rejects(
    functions.getOrderReview.run(reviewRequest(data)),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal((await db.collection('orderReviews').doc(data.orderId).get()).exists, false);
});

test('getOrderReview rejects an over-limit cart quantity when selectedItems is omitted', async () => {
  const data = fixture();
  await seedCatalogAndCart(data, { stock: 200, quantity: 101 });

  await assert.rejects(functions.getOrderReview.run({
    auth: { uid: data.userId },
    data: {
      orderId: data.orderId,
      shippingAddress: data.address,
      deliveryOptionId: 'standard',
      paymentMethod: 'gcash',
      currency: 'PHP',
    },
  }));
  assert.equal((await db.collection('orderReviews').doc(data.orderId).get()).exists, false);
});

test('getOrderReview rejects an explicit quantity above 100', async () => {
  const data = fixture();
  await seedCatalogAndCart(data, { stock: 200, quantity: 100 });

  await assert.rejects(functions.getOrderReview.run({
    auth: { uid: data.userId },
    data: {
      orderId: data.orderId,
      selectedItems: [{ productId: data.productId, variantId: data.variantId, quantity: 101 }],
      shippingAddress: data.address,
      deliveryOptionId: 'standard',
      paymentMethod: 'gcash',
      currency: 'PHP',
    },
  }));
  assert.equal((await db.collection('orderReviews').doc(data.orderId).get()).exists, false);
});

test('paymongoWebhook rejects requests without a signature', async () => {
  const data = fixture();
  await seedExistingCheckout(data);

  const response = await deliverPaidEvent(data, `evt_${randomUUID()}`, {
    signatureHeader: '',
  });

  assert.equal(response.statusCode, 401);
});

test('paymongoWebhook rejects an invalid signature', async () => {
  const data = fixture();
  await seedExistingCheckout(data);
  const timestamp = String(Math.floor(Date.now() / 1000));

  const response = await deliverPaidEvent(data, `evt_${randomUUID()}`, {
    signatureHeader: `t=${timestamp},te=${'0'.repeat(64)}`,
  });

  assert.equal(response.statusCode, 401);
});

test('paymongoWebhook rejects a malformed signature timestamp', async () => {
  const data = fixture();
  await seedExistingCheckout(data);

  const response = await deliverPaidEvent(data, `evt_${randomUUID()}`, {
    timestamp: 'not-a-timestamp',
  });

  assert.equal(response.statusCode, 401);
});

test('paymongoWebhook rejects a stale signature timestamp', async () => {
  const data = fixture();
  await seedExistingCheckout(data);

  const response = await deliverPaidEvent(data, `evt_${randomUUID()}`, {
    timestamp: String(Math.floor(Date.now() / 1000) - 601),
  });

  assert.equal(response.statusCode, 401);
});

test('paymongoWebhook accepts the alternate signature header and live signature field', async () => {
  const data = fixture();
  await seedExistingCheckout(data);

  const response = await deliverPaidEvent(data, `evt_${randomUUID()}`, {
    signatureHeaderName: 'X-Paymongo-Signature',
    signatureField: 'li',
  });

  assert.equal(response.statusCode, 200);
});

test('paymongoWebhook deduplicates a sequential replay before limiter writes and stock changes in fake Firestore', async () => {
  const data = fixture({ webhookIp: '127.0.0.2' });
  await seedExistingCheckout(data);
  await db.collection('perfumes').doc(data.productId).update({
    variants: [{ id: data.variantId, label: '50ml', priceCentavos: 42000, stock: 2 }],
  });
  const eventId = `evt_${randomUUID()}`;

  const responses = [
    await deliverPaidEvent(data, eventId),
    await deliverPaidEvent(data, eventId),
  ];

  assert.deepEqual(responses.map((response) => response.statusCode), [200, 200]);
  const product = (await db.collection('perfumes').doc(data.productId).get()).data();
  assert.equal(product.variants[0].stock, 2);
  const limiterId = createHash('sha256').update('webhook:127.0.0.2').digest('hex');
  assert.equal((await db.collection('rateLimits').doc(limiterId).get()).data().count, 1);
});

test('paymongoWebhook routes an expired checkout payment to manual review without changing stock', async () => {
  const data = fixture({ webhookIp: '127.0.0.3' });
  await seedExistingCheckout(data);
  await db.collection('checkoutIntents').doc(data.orderId).update({
    expiresAt: new Date(Date.now() - 60 * 1000),
  });
  await db.collection('perfumes').doc(data.productId).update({
    variants: [{ id: data.variantId, label: '50ml', priceCentavos: 42000, stock: 2 }],
  });

  const response = await deliverPaidEvent(data, `evt_${randomUUID()}`);

  assert.equal(response.statusCode, 200);
  const order = (await db.collection('orders').doc(data.orderId).get()).data();
  const intent = (await db.collection('checkoutIntents').doc(data.orderId).get()).data();
  const review = (await db.collection('orderReviews').doc(data.orderId).get()).data();
  const product = (await db.collection('perfumes').doc(data.productId).get()).data();
  assert.equal(order.status, 'pending_payment');
  assert.equal(order.paymentStatus, 'manual_review');
  assert.equal(intent.status, 'manual_review');
  assert.equal(review.status, 'manual_review');
  assert.equal(product.variants[0].stock, 2);
});

test('reconcileLatePayment confirms reviewed payment without deducting its existing reservation', async () => {
  const data = fixture();
  await seedExistingCheckout(data);
  await db.collection('checkoutIntents').doc(data.orderId).update({
    status: 'manual_review',
  });
  await db.collection('orders').doc(data.orderId).update({
    paymentStatus: 'manual_review',
  });
  await db.collection('orderReviews').doc(data.orderId).update({
    status: 'manual_review',
  });
  await db.collection('perfumes').doc(data.productId).update({
    variants: [{ id: data.variantId, label: '50ml', priceCentavos: 42000, stock: 2 }],
  });

  await assert.rejects(
    functions.reconcileLatePayment.run({
      auth: { uid: data.userId },
      data: { orderId: data.orderId },
    }),
    (error) => error.code === 'permission-denied',
  );

  const result = await functions.reconcileLatePayment.run({
    auth: { uid: 'admin-user', token: { admin: true } },
    data: { orderId: data.orderId },
  });

  assert.deepEqual(result, { orderId: data.orderId, status: 'confirmed' });
  const order = (await db.collection('orders').doc(data.orderId).get()).data();
  const intent = (await db.collection('checkoutIntents').doc(data.orderId).get()).data();
  const review = (await db.collection('orderReviews').doc(data.orderId).get()).data();
  const product = (await db.collection('perfumes').doc(data.productId).get()).data();
  assert.equal(order.status, 'confirmed');
  assert.equal(order.paymentStatus, 'paid');
  assert.equal(intent.status, 'paid');
  assert.equal(review.status, 'paid');
  assert.equal(product.variants[0].stock, 2);
});

test('addressAutocomplete applies the UID limit even when session tokens rotate', async () => {
  const userId = `autocomplete-${randomUUID()}`;
  for (let index = 0; index < 20; index++) {
    await functions.addressAutocomplete.run({
      auth: { uid: userId },
      data: { query: 'ma', sessionToken: `session-${index}` },
    });
  }

  await assert.rejects(functions.addressAutocomplete.run({
    auth: { uid: userId },
    data: { query: 'ma', sessionToken: `session-${randomUUID()}` },
  }), (error) => error.code === 'resource-exhausted');
});

test('addressPlaceDetails applies the UID limit even when session tokens rotate', async () => {
  const data = fixture();
  const placeId = `place-${randomUUID()}`;
  await db.collection('addressSuggestions').doc(placeId).set({
    addressLine1: '123 Mabini Street',
    barangay: 'Barangay 1',
    city: 'Quezon City',
    province: 'Metro Manila',
    postalCode: '1100',
    latitude: 14.676,
    longitude: 121.0437,
  });
  for (let index = 0; index < 20; index++) {
    await functions.addressPlaceDetails.run({
      auth: { uid: data.userId },
      data: { placeId, sessionToken: `session-${index}` },
    });
  }

  await assert.rejects(functions.addressPlaceDetails.run({
    auth: { uid: data.userId },
    data: { placeId, sessionToken: `session-${randomUUID()}` },
  }), (error) => error.code === 'resource-exhausted');
});

test('getOrderReview rejects the deferred deliveryInstructions address field', async () => {
  const data = fixture();
  await seedCatalogAndCart(data);
  const address = { ...data.address, deliveryInstructions: 'Leave at the front desk.' };

  await assert.rejects(
    functions.getOrderReview.run(reviewRequest(data, data.userId, address)),
    (error) => error.code === 'invalid-argument',
  );
});

for (const [label, overrides] of [
  ['payment method casing', { paymentMethod: 'GCASH' }],
  ['currency casing', { currency: 'php' }],
  ['address source whitespace', {
    shippingAddress: { ...fixture().address, addressSource: ' MANUAL ' },
  }],
  ['delivery ID whitespace', { deliveryOptionId: ' standard ' }],
]) {
  test(`getOrderReview rejects noncanonical ${label}`, async () => {
    const data = fixture();
    await seedCatalogAndCart(data);
    const requestOverrides = overrides.shippingAddress
      ? { ...overrides, shippingAddress: { ...data.address, addressSource: ' MANUAL ' } }
      : overrides;

    await assert.rejects(functions.getOrderReview.run(freshReviewRequest(data, requestOverrides)));
    assert.equal((await db.collection('orderReviews').doc(data.orderId).get()).exists, false);
  });
}
