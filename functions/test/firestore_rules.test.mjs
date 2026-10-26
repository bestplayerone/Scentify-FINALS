import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, Timestamp, updateDoc } from 'firebase/firestore';

const projectId = 'demo-scentify-rules';
let testEnv;

const address = (createdAt, updatedAt = createdAt) => ({
  fullName: 'Juan Dela Cruz',
  phoneNumber: '+639171234567',
  addressLine1: '123 Mabini Street',
  barangay: 'Barangay 1',
  city: 'Quezon City',
  province: 'Metro Manila',
  postalCode: '1100',
  label: 'Home',
  isDefault: true,
  latitude: 14.676,
  longitude: 121.0437,
  placeId: 'place-1',
  addressSource: 'autocomplete',
  notes: '',
  createdAt,
  updatedAt,
});

const reviewedOrder = (orderId, userId, overrides = {}) => {
  const createdAt = Timestamp.fromDate(new Date('2026-05-01T00:00:00.000Z'));
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000));
  const items = [{
    productId: 'product-1',
    variantId: 'variant-1',
    productName: 'Test Scent',
    variantLabel: '50ml',
    unitPriceCentavos: 42000,
    quantity: 1,
  }];
  const shippingAddress = {
    fullName: 'Juan Dela Cruz',
    phoneNumber: '+639171234567',
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
    items,
    shippingAddress,
    deliveryOption,
    subtotalCentavos: 42000,
    deliveryFeeCentavos: 8000,
    totalCentavos: 50000,
    status: 'pending_payment',
    paymentReference: `sandbox-${orderId}`,
    paymentMethod: 'gcash',
    createdAt,
    updatedAt: createdAt,
    events: [],
    ...overrides,
  };
  const review = {
    orderId,
    userId,
    status: 'ready',
    paymentMethod: 'gcash',
    orderItems: items,
    shippingAddress,
    deliveryOption,
    subtotalCentavos: 42000,
    deliveryFeeCentavos: 8000,
    totalCentavos: 50000,
    amountCentavos: 50000,
    expiresAt,
  };
  return { order, review };
};

async function seedOrderReview(orderId, review) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `orderReviews/${orderId}`), review);
  });
}

async function seedPayMongoOrder(orderId, userId, {
  orderOverrides = {},
  reviewOverrides = {},
  intentOverrides = {},
} = {}) {
  const paymentReference = `session-${orderId}`;
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000));
  const { order, review: baseReview } = reviewedOrder(orderId, userId, {
    paymentProvider: 'paymongo',
    paymentReference,
    ...orderOverrides,
  });
  const review = { ...baseReview, ...reviewOverrides };
  await seedOrderReview(orderId, review);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `checkoutIntents/${orderId}`), {
      orderId,
      userId,
      amountCentavos: 50000,
      paymentReference,
      status: 'pending',
      expiresAt,
      ...intentOverrides,
    });
  });
  return order;
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, 'perfumes/product-1'), { isPublished: true });
    await setDoc(doc(firestore, 'perfumes/product-1/ratings/review-1'), {
      userId: 'customer-1',
      orderId: 'order-1',
      productId: 'product-1',
      variantId: 'variant-1',
      rating: 5,
      verifiedPurchase: true,
      createdAt: Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z')),
    });
    await setDoc(doc(firestore, 'addressSuggestions/place-1'), {
      searchKey: '123 mabini street quezon city',
      primaryText: '123 Mabini Street',
      secondaryText: 'Quezon City, Metro Manila',
      addressLine1: '123 Mabini Street',
      barangay: 'Barangay 1',
      city: 'Quezon City',
      province: 'Metro Manila',
      postalCode: '1100',
      latitude: 14.676,
      longitude: 121.0437,
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

test('saved addresses are private to their owner and schema-validated', async () => {
  const owner = testEnv.authenticatedContext('customer-1').firestore();
  const otherUser = testEnv.authenticatedContext('customer-2').firestore();
  const anonymous = testEnv.unauthenticatedContext().firestore();
  const ownerAddress = doc(owner, 'users/customer-1/addresses/primary');
  const otherAddress = doc(otherUser, 'users/customer-1/addresses/primary');
  const anonymousAddress = doc(anonymous, 'users/customer-1/addresses/primary');
  const createdAt = Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z'));
  const updatedAt = Timestamp.fromDate(new Date('2026-01-02T00:00:00.000Z'));

  await assertSucceeds(setDoc(ownerAddress, address(createdAt, updatedAt)));
  await assertSucceeds(getDoc(ownerAddress));
  await assertSucceeds(setDoc(ownerAddress, {
    ...address(createdAt, updatedAt),
    province: 'National Capital Region',
    city: 'Caloocan City',
    barangay: 'Barangay 123',
    postalCode: '1400',
  }));
  await assertFails(getDoc(otherAddress));
  const wrongOwnerError = await setDoc(
    otherAddress,
    address(createdAt, updatedAt),
  ).then(() => null, (error) => error);
  assert.equal(wrongOwnerError?.code, 'permission-denied');
  const anonymousError = await setDoc(
    anonymousAddress,
    address(createdAt, updatedAt),
  ).then(() => null, (error) => error);
  assert.equal(anonymousError?.code, 'permission-denied');
  await assertFails(
    setDoc(ownerAddress, { ...address(createdAt, updatedAt), postalCode: '11000' }),
  );
});

test('saved address writes are restricted to the primary document ID', async () => {
  const userId = 'customer-primary-address-only';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const secondary = doc(firestore, `users/${userId}/addresses/secondary`);
  const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));
  const updatedAt = Timestamp.fromDate(new Date('2026-02-02T00:00:00.000Z'));

  await assertFails(setDoc(secondary, address(createdAt)));
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), `users/${userId}/addresses/secondary`),
      address(createdAt),
    );
  });
  await assertFails(updateDoc(secondary, { updatedAt }));
  await assertFails(deleteDoc(secondary));
});

test('address updates preserve createdAt and allow only valid address data', async () => {
  const firestore = testEnv.authenticatedContext('customer-3').firestore();
  const reference = doc(firestore, 'users/customer-3/addresses/primary');
  const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));
  const updatedAt = Timestamp.fromDate(new Date('2026-02-02T00:00:00.000Z'));

  await assertSucceeds(setDoc(reference, address(createdAt)));
  await assertSucceeds(updateDoc(reference, { updatedAt }));
  await assertFails(
    updateDoc(reference, {
      ...address(createdAt, updatedAt),
      createdAt: Timestamp.fromDate(new Date('2026-02-03T00:00:00.000Z')),
    }),
  );
});

const blankAddressTextCases = [
  ['whitespace-only', ' \t\n'],
  ['format-only', '\u200B'],
];

for (const field of [
  'fullName', 'phoneNumber', 'addressLine1', 'barangay',
  'city', 'province', 'postalCode', 'label',
]) {
  for (const [caseName, value] of blankAddressTextCases) {
    test(`saved addresses reject ${caseName} ${field}`, async () => {
      const userId = `customer-${field}-${caseName}`;
      const firestore = testEnv.authenticatedContext(userId).firestore();
      const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));

      await assertFails(setDoc(
        doc(firestore, `users/${userId}/addresses/primary`),
        { ...address(createdAt), [field]: value },
      ));
    });
  }
}

test('saved addresses allow visible names containing format characters', async () => {
  const userId = 'customer-visible-format-name';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));

  await assertSucceeds(setDoc(
    doc(firestore, `users/${userId}/addresses/primary`),
    { ...address(createdAt), fullName: 'Juan\u200B Dela Cruz' },
  ));
});

test('saved address rules retain notes and reject the deferred deliveryInstructions field', async () => {
  const userId = 'customer-address-notes-schema';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const reference = doc(firestore, `users/${userId}/addresses/primary`);
  const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));
  const savedAddress = address(createdAt);

  await assertSucceeds(setDoc(reference, savedAddress));
  await assertFails(setDoc(reference, {
    ...savedAddress,
    deliveryInstructions: 'Leave at the front desk.',
  }));
});

test('saved addresses reject unsafe place IDs', async () => {
  const userId = 'customer-unsafe-place-id';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));

  await assertFails(setDoc(
    doc(firestore, `users/${userId}/addresses/primary`),
    { ...address(createdAt), placeId: 'place-1/unsafe' },
  ));
});

test('saved addresses reject partial coordinate pairs', async () => {
  const userId = 'customer-partial-address-coordinates';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));

  const partialAddress = address(createdAt);
  delete partialAddress.longitude;

  await assertFails(setDoc(
    doc(firestore, `users/${userId}/addresses/primary`),
    partialAddress,
  ));
});

test('saved addresses reject out-of-range coordinates', async () => {
  const userId = 'customer-invalid-address-coordinates';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));
  for (const invalidCoordinate of [
    { latitude: 90.1 },
    { latitude: -90.1 },
    { longitude: 180.1 },
    { longitude: -180.1 },
  ]) {
    await assertFails(setDoc(
      doc(firestore, `users/${userId}/addresses/primary`),
      { ...address(createdAt), ...invalidCoordinate },
    ));
  }
});

test('saved addresses allow null place IDs and null coordinate pairs', async () => {
  const userId = 'customer-null-address-coordinates';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));

  await assertSucceeds(setDoc(
    doc(firestore, `users/${userId}/addresses/primary`),
    { ...address(createdAt), placeId: null, latitude: null, longitude: null },
  ));
});

test('clients cannot forge server-owned cart confirmation markers', async () => {
  const userId = 'customer-cart-markers';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const reference = doc(firestore, `carts/${userId}`);
  const updatedAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));
  const cart = { userId, items: [], updatedAt };
  await assertSucceeds(setDoc(reference, cart));

  for (const [field, value] of [
    ['serverConfirmed', true],
    ['lastOperationId', 'forged-operation'],
    ['serverConfirmedAt', updatedAt],
  ]) {
    await assertFails(setDoc(reference, { ...cart, [field]: value }));
  }
});

test('cart and wishlist rules retain bounded document shapes', async () => {
  const userId = 'customer-nested-validation';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const updatedAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));
  const validItem = {
    productId: 'product-1',
    variantId: 'variant-1',
    productName: 'Test Scent',
    variantLabel: '50ml',
    unitPriceCentavos: 42000,
    quantity: 1,
  };

  await assertSucceeds(setDoc(doc(firestore, `carts/${userId}`), {
    userId,
    items: [validItem],
    updatedAt,
  }));
  await assertFails(setDoc(doc(firestore, `carts/${userId}`), {
    userId,
    items: {},
    updatedAt,
  }));

  await assertSucceeds(setDoc(doc(firestore, `wishlists/${userId}`), {
    productIds: ['product-1'],
  }));
  await assertFails(setDoc(doc(firestore, `wishlists/${userId}`), {
    productIds: {},
  }));
});

test('published reviews are readable but only trusted Functions can write them', async () => {
  const firestore = testEnv.authenticatedContext('customer-2').firestore();
  const reference = doc(firestore, 'perfumes/product-1/ratings/review-1');

  await assertSucceeds(getDoc(reference));
  await assertFails(
    setDoc(doc(firestore, 'perfumes/product-1/ratings/client-review'), {
      userId: 'customer-2',
      rating: 5,
    }),
  );
});

test('clients cannot adjust product variants or write inventory audit records', async () => {
  const admin = testEnv.authenticatedContext('stock-admin', { admin: true }).firestore();
  await assertFails(updateDoc(doc(admin, 'perfumes/product-1'), {
    variants: [{ id: 'variant-1', stock: 99 }],
  }));
  await assertFails(setDoc(doc(admin, 'inventoryAdjustments/client-write'), {
    productId: 'product-1', variantId: 'variant-1', delta: 10,
  }));
  await assertFails(getDoc(doc(admin, 'inventoryReservations/order-1')));
});

test('address suggestion records are inaccessible to client SDKs', async () => {
  const firestore = testEnv.authenticatedContext('customer-1').firestore();
  const reference = doc(firestore, 'addressSuggestions/place-1');

  await assertFails(getDoc(reference));
  await assertFails(setDoc(doc(firestore, 'addressSuggestions/client-place'), {}));
});

test('clients cannot create an order without a trusted checkout review', async () => {
  const firestore = testEnv.authenticatedContext('customer-1').firestore();
  const createdAt = Timestamp.fromDate(new Date('2026-03-01T00:00:00.000Z'));
  const order = {
    id: 'order-1',
    userId: 'customer-1',
    items: [{ productId: 'product-1', variantId: 'variant-1', quantity: 1 }],
    shippingAddress: { city: 'Quezon City' },
    deliveryOption: { id: 'standard' },
    subtotalCentavos: 42000,
    deliveryFeeCentavos: 8000,
    totalCentavos: 50000,
    status: 'pending_payment',
    paymentReference: 'sandbox-order-1',
    createdAt,
    updatedAt: createdAt,
    events: [],
    paymentMethod: 'gcash',
    paymentStatus: 'pending',
    paymentProvider: 'paymongo',
  };

  await assertFails(setDoc(doc(firestore, 'orders/order-1'), order));
});

test('valid server-reviewed sandbox and PayMongo orders can be created', async () => {
  const firestore = testEnv.authenticatedContext('customer-4').firestore();
  const createdAt = Timestamp.fromDate(new Date('2026-04-01T00:00:00.000Z'));
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000));
  const items = [
    {
      productId: 'product-1',
      variantId: 'variant-1',
      productName: 'Test Scent',
      variantLabel: '50ml',
      unitPriceCentavos: 42000,
      quantity: 1,
    },
  ];
  const shippingAddress = {
    fullName: 'Juan Dela Cruz',
    phoneNumber: '+639171234567',
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

  for (const checkout of [
    { orderId: 'sandbox-order', paymentReference: 'sandbox-test-order' },
    { orderId: 'paymongo-order', paymentReference: 'paymongo-session-1' },
  ]) {
    const totalCentavos = 50000;
    const order = {
      id: checkout.orderId,
      userId: 'customer-4',
      items,
      shippingAddress,
      deliveryOption,
      subtotalCentavos: 42000,
      deliveryFeeCentavos: 8000,
      totalCentavos,
      status: 'pending_payment',
      paymentReference: checkout.paymentReference,
      createdAt,
      updatedAt: createdAt,
      events: [],
      ...(checkout.orderId === 'sandbox-order' ? {} : { paymentMethod: 'gcash' }),
      paymentStatus: 'pending',
    };
    const review = {
      orderId: checkout.orderId,
      userId: 'customer-4',
      status: 'ready',
      paymentMethod: 'gcash',
      orderItems: items,
      shippingAddress,
      deliveryOption,
      subtotalCentavos: 42000,
      deliveryFeeCentavos: 8000,
      totalCentavos,
      amountCentavos: totalCentavos,
      expiresAt,
    };

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      await setDoc(doc(admin, `orderReviews/${checkout.orderId}`), review);
      if (checkout.orderId === 'paymongo-order') {
        await setDoc(doc(admin, `checkoutIntents/${checkout.orderId}`), {
          orderId: checkout.orderId,
          userId: 'customer-4',
          amountCentavos: totalCentavos,
          paymentReference: checkout.paymentReference,
          status: 'pending',
          expiresAt,
        });
      }
    });

    await assertSucceeds(setDoc(doc(firestore, `orders/${checkout.orderId}`), order));
  }
});

test('clients cannot create COD orders directly', async () => {
  const userId = 'customer-client-cod-denied';
  const orderId = 'client-cod-denied';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const { order, review } = reviewedOrder(orderId, userId, {
    status: 'confirmed',
    paymentReference: `cod-${orderId}`,
    paymentMethod: 'cod',
    paymentStatus: 'pending_collection',
  });
  await seedOrderReview(orderId, { ...review, paymentMethod: 'cod' });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('customers can submit owner-only COD requests awaiting admin confirmation', async () => {
  const userId = 'cod-request-customer';
  const orderId = 'cod-request-1';
  const owner = testEnv.authenticatedContext(userId).firestore();
  const other = testEnv.authenticatedContext('another-customer').firestore();
  const request = reviewedOrder(orderId, userId).order;
  Object.assign(request, {
    status: 'pending_confirmation',
    paymentReference: null,
    paymentMethod: 'cod',
    paymentStatus: 'unpaid',
  });
  const ownerOrder = doc(owner, `orders/${orderId}`);
  const otherOrder = doc(other, `orders/${orderId}`);

  await assertSucceeds(setDoc(ownerOrder, request));
  await assertSucceeds(getDoc(ownerOrder));
  await assertFails(getDoc(otherOrder));
  await assertFails(updateDoc(ownerOrder, { paymentStatus: 'paid' }));
  await assertFails(setDoc(doc(owner, 'orders/cod-request-forged'), {
    ...request,
    id: 'cod-request-forged',
    status: 'confirmed',
  }));
  await assertFails(setDoc(doc(owner, 'orders/cod-request-paid'), {
    ...request,
    id: 'cod-request-paid',
    paymentStatus: 'paid',
  }));
});

test('order creation rejects an expired review', async () => {
  const userId = 'customer-expired-review';
  const orderId = 'expired-review-order';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const expiredAt = Timestamp.fromDate(new Date(Date.now() - 60 * 1000));
  const order = await seedPayMongoOrder(orderId, userId, {
    reviewOverrides: { expiresAt: expiredAt },
  });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('order creation rejects an expired checkout intent', async () => {
  const userId = 'customer-expired-intent';
  const orderId = 'expired-checkout-intent';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const expiredAt = Timestamp.fromDate(new Date(Date.now() - 60 * 1000));
  const order = await seedPayMongoOrder(orderId, userId, {
    intentOverrides: { expiresAt: expiredAt },
  });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('order creation rejects a checkout intent with a mismatched order ID', async () => {
  const userId = 'customer-intent-order-id';
  const orderId = 'wrong-intent-order-id';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const order = await seedPayMongoOrder(orderId, userId, {
    intentOverrides: { orderId: 'different-order-id' },
  });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('order creation rejects a checkout intent owned by another user', async () => {
  const userId = 'customer-intent-owner';
  const orderId = 'wrong-intent-owner';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const order = await seedPayMongoOrder(orderId, userId, {
    intentOverrides: { userId: 'another-customer' },
  });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('order creation rejects a checkout intent with the wrong amount', async () => {
  const userId = 'customer-intent-amount';
  const orderId = 'wrong-intent-amount';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const order = await seedPayMongoOrder(orderId, userId, {
    intentOverrides: { amountCentavos: 49999 },
  });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('order creation rejects a checkout intent with the wrong payment reference', async () => {
  const userId = 'customer-intent-reference';
  const orderId = 'wrong-intent-reference';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const order = await seedPayMongoOrder(orderId, userId, {
    intentOverrides: { paymentReference: 'different-session' },
  });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('order creation rejects extra client-provided order keys', async () => {
  const userId = 'customer-extra-order-key';
  const orderId = 'extra-order-key';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const order = await seedPayMongoOrder(orderId, userId, {
    orderOverrides: { forgedField: 'not in the order contract' },
  });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('sandbox order payment method must match its reviewed quote', async () => {
  const firestore = testEnv.authenticatedContext('customer-method').firestore();
  const orderId = 'sandbox-method-mismatch';
  const { order, review } = reviewedOrder(orderId, 'customer-method', { paymentMethod: 'maya' });
  await seedOrderReview(orderId, review);

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('PayMongo order payment method must match its reviewed quote', async () => {
  const firestore = testEnv.authenticatedContext('customer-paymongo-method').firestore();
  const orderId = 'paymongo-method-mismatch';
  const paymentReference = 'cs_paymongo-method-mismatch';
  const { order, review } = reviewedOrder(orderId, 'customer-paymongo-method', {
    paymentMethod: 'maya',
    paymentProvider: 'paymongo',
    paymentReference,
  });
  await seedOrderReview(orderId, review);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `checkoutIntents/${orderId}`), {
      orderId,
      userId: 'customer-paymongo-method',
      amountCentavos: 50000,
      paymentReference,
      status: 'pending',
      expiresAt: review.expiresAt,
    });
  });

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('sandbox orders cannot claim the PayMongo provider without an intent', async () => {
  const userId = 'customer-sandbox-provider-claim';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const orderId = 'sandbox-provider-claim';
  const { order, review } = reviewedOrder(orderId, userId, {
    paymentProvider: 'paymongo',
  });
  await seedOrderReview(orderId, review);

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('PayMongo orders without a checkout intent are denied', async () => {
  const userId = 'customer-no-paymongo-intent';
  const firestore = testEnv.authenticatedContext(userId).firestore();
  const orderId = 'paymongo-without-intent';
  const { order, review } = reviewedOrder(orderId, userId, {
    paymentProvider: 'paymongo',
    paymentReference: `cs_${orderId}`,
  });
  await seedOrderReview(orderId, review);

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});

test('client-created orders must begin with an empty event list', async () => {
  const firestore = testEnv.authenticatedContext('customer-events').firestore();
  const orderId = 'sandbox-forged-events';
  const { order, review } = reviewedOrder(orderId, 'customer-events', {
    events: [{ from: null, to: 'confirmed' }],
  });
  await seedOrderReview(orderId, review);

  await assertFails(setDoc(doc(firestore, `orders/${orderId}`), order));
});
