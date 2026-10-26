const fs = require('node:fs');

const exportPath = process.env.FIRESTORE_EXPORT || '/tmp/scentify-firestore-export.json';
const exportData = JSON.parse(fs.readFileSync(exportPath, 'utf8'));

function loadEnv(path) {
  return Object.fromEntries(fs.readFileSync(path, 'utf8').split(/\r?\n/)
    .filter((line) => line && !line.startsWith('#') && line.includes('='))
    .map((line) => {
      const index = line.indexOf('=');
      return [line.slice(0, index), line.slice(index + 1)];
    }));
}

const env = loadEnv('functions/.env');
const baseUrl = env.SUPABASE_URL;
const serviceRole = env.SUPABASE_SERVICE_ROLE_KEY;
if (!baseUrl || !serviceRole) throw new Error('Supabase service configuration is missing.');

async function upsert(table, rows, onConflict) {
  if (!rows.length) return;
  const response = await fetch(`${baseUrl}/rest/v1/${table}?on_conflict=${onConflict}`, {
    method: 'POST',
    headers: {
      apikey: serviceRole,
      Authorization: `Bearer ${serviceRole}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify(rows),
  });
  if (!response.ok) throw new Error(`${table}: ${response.status} ${(await response.text()).slice(0, 500)}`);
}

const rows = (name) => exportData.collections[name] || [];
const products = rows('perfumes');
const users = rows('users');
const orders = rows('orders');

(async () => {
  const brands = [...new Map(products.map(({ data }) => [data.brandId, {
    id: data.brandId,
    name: data.brandName || data.brandId,
  }])).values()];
  await upsert('brands', brands, 'id');

  await upsert('customers', users.map(({ id, data }) => ({
    id,
    email: data.email || '',
    display_name: data.displayName || '',
    role: ['customer', 'admin', 'superadmin'].includes(data.role) ? data.role : 'customer',
    created_at: data.createdAt || new Date().toISOString(),
  })), 'id');

  await upsert('products', products.map(({ id, data }) => ({
    id,
    brand_id: data.brandId,
    name: data.name || '',
    description: data.description || '',
    gender: data.gender || 'unisex',
    family: data.family || 'other',
    concentration: data.concentration || 'edp',
    occasions: data.occasions || [],
    vibes: data.vibes || [],
    top_notes: data.topNotes || [],
    heart_notes: data.heartNotes || [],
    base_notes: data.baseNotes || [],
    image_urls: data.imageUrls || [],
    tags: data.tags || [],
    authenticity_note: data.authenticityNote || '',
    is_published: data.isPublished !== false,
    average_rating: Number(data.averageRating || 0),
    review_count: Number(data.reviewCount || 0),
  })), 'id');

  await upsert('product_variants', products.flatMap(({ id: productId, data }) =>
    (data.variants || []).map((variant) => ({
      id: variant.id,
      product_id: productId,
      label: variant.label,
      volume_ml: Number(variant.volumeMl),
      price_centavos: Number(variant.priceCentavos),
      on_hand: Number(variant.stock || 0),
      reserved: 0,
    }))), 'id');

  await upsert('carts', rows('carts').map(({ id, data }) => ({
    user_id: data.userId || id,
    updated_at: data.updatedAt || new Date().toISOString(),
  })), 'user_id');
  await upsert('cart_items', rows('carts').flatMap(({ id, data }) =>
    (data.items || []).map((item) => ({
      user_id: data.userId || id,
      variant_id: item.variantId,
      quantity: Number(item.quantity),
    }))), 'user_id,variant_id');

  await upsert('wishlists', rows('wishlists').flatMap(({ id, data }) =>
    (data.productIds || []).map((productId) => ({ user_id: id, product_id: productId }))), 'user_id,product_id');

  await upsert('orders', orders.map(({ id, data }) => ({
    id,
    user_id: data.userId,
    idempotency_key: `migrated:${id}`,
    shipping_address: data.shippingAddress || {},
    delivery_option: data.deliveryOption || {},
    subtotal_centavos: Number(data.subtotalCentavos || 0),
    delivery_fee_centavos: Number(data.deliveryFeeCentavos || 0),
    total_centavos: Number(data.totalCentavos || 0),
    status: data.status || 'pending_confirmation',
    payment_method: ['cod', 'gcash', 'maya', 'card'].includes(data.paymentMethod) ? data.paymentMethod : 'cod',
    payment_provider: data.paymentReference ? 'firebase-migration' : null,
    payment_reference: data.paymentReference || null,
    payment_status: data.paymentStatus || null,
    created_at: data.createdAt || new Date().toISOString(),
  })), 'id');
  await upsert('order_items', orders.flatMap(({ id: orderId, data }) =>
    (data.items || []).map((item) => ({
      order_id: orderId,
      product_id: item.productId,
      variant_id: item.variantId,
      product_name: item.productName || '',
      variant_label: item.variantLabel || '',
      unit_price_centavos: Number(item.unitPriceCentavos || 0),
      quantity: Number(item.quantity || 0),
    }))), 'order_id,variant_id');

  await upsert('reviews', rows('reviews').map(({ id, productId, data }) => ({
    id,
    order_id: data.orderId,
    user_id: data.userId,
    product_id: productId || data.productId,
    variant_id: data.variantId,
    rating: Number(data.rating),
    title: data.title || '',
    comment: data.comment || '',
    created_at: data.createdAt || new Date().toISOString(),
  })), 'id');

  console.log(JSON.stringify({
    imported: {
      brands: brands.length,
      products: products.length,
      variants: products.reduce((count, row) => count + (row.data.variants || []).length, 0),
      customers: users.length,
      carts: rows('carts').length,
      wishlists: rows('wishlists').reduce((count, row) => count + (row.data.productIds || []).length, 0),
      orders: orders.length,
      orderItems: orders.reduce((count, row) => count + (row.data.items || []).length, 0),
      reviews: rows('reviews').length,
    },
  }));
})().catch((error) => { console.error(error.message); process.exitCode = 1; });
