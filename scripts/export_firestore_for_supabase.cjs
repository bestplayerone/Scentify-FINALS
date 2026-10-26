const fs = require('node:fs/promises');

const projectId = process.env.FIREBASE_PROJECT_ID || 'scentify-b97e5';
const token = process.env.FIREBASE_ACCESS_TOKEN;
const output = process.env.OUTPUT || '/tmp/scentify-firestore-export.json';
const collections = ['perfumes', 'users', 'carts', 'wishlists', 'orders'];

if (!token) throw new Error('FIREBASE_ACCESS_TOKEN is required.');

function decode(value) {
  if (value == null) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('referenceValue' in value) return value.referenceValue;
  if ('nullValue' in value) return null;
  if ('bytesValue' in value) return value.bytesValue;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decode);
  if ('mapValue' in value) return decodeFields(value.mapValue.fields || {});
  return value;
}

function decodeFields(fields) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, decode(value)]));
}

async function getCollection(collection) {
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}?pageSize=300`;
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`${collection}: Firestore returned ${response.status}`);
  const payload = await response.json();
  return (payload.documents || []).map((document) => ({
    id: document.name.split('/').pop(),
    data: decodeFields(document.fields || {}),
  }));
}

(async () => {
  const exportData = { projectId, exportedAt: new Date().toISOString(), collections: {} };
  for (const collection of collections) {
    exportData.collections[collection] = await getCollection(collection);
  }

  exportData.collections.reviews = [];
  for (const perfume of exportData.collections.perfumes) {
    const rows = await getCollection(`perfumes/${encodeURIComponent(perfume.id)}/ratings`);
    exportData.collections.reviews.push(
      ...rows.map((review) => ({ productId: perfume.id, ...review })),
    );
  }

  await fs.writeFile(output, JSON.stringify(exportData, null, 2), { mode: 0o600 });
  console.log(JSON.stringify({
    output,
    counts: Object.fromEntries(
      Object.entries(exportData.collections).map(([name, rows]) => [name, rows.length]),
    ),
  }));
})().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
