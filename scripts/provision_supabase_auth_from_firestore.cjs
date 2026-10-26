const fs = require('node:fs');
const crypto = require('node:crypto');

const exportData = JSON.parse(fs.readFileSync(
  process.env.FIRESTORE_EXPORT || '/tmp/scentify-firestore-export.json',
  'utf8',
));
const env = Object.fromEntries(fs.readFileSync('functions/.env', 'utf8')
  .split(/\r?\n/).filter((line) => line && !line.startsWith('#') && line.includes('='))
  .map((line) => { const i = line.indexOf('='); return [line.slice(0, i), line.slice(i + 1)]; }));
const baseUrl = env.SUPABASE_URL;
const serviceRole = env.SUPABASE_SERVICE_ROLE_KEY;
if (!baseUrl || !serviceRole) throw new Error('Supabase service configuration is missing.');

const headers = {
  apikey: serviceRole,
  Authorization: `Bearer ${serviceRole}`,
  'Content-Type': 'application/json',
};

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, { ...options, headers: { ...headers, ...options.headers } });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${path}: ${response.status} ${body.msg || body.message || 'request failed'}`);
  return body;
}

(async () => {
  const existing = await request('/auth/v1/admin/users?per_page=100');
  const byEmail = new Map((existing.users || []).map((user) => [user.email?.toLowerCase(), user]));
  const result = [];

  for (const { id: firebaseUid, data } of exportData.collections.users || []) {
    const email = String(data.email || '').trim().toLowerCase();
    if (!email) continue;
    let user = byEmail.get(email);
    if (!user) {
      user = await request('/auth/v1/admin/users', {
        method: 'POST',
        body: JSON.stringify({
          email,
          password: crypto.randomBytes(32).toString('base64url'),
          email_confirm: true,
          user_metadata: {
            display_name: data.displayName || '',
            firebase_uid: firebaseUid,
            migrated_from: 'firebase',
          },
          app_metadata: { role: data.role || 'customer', migrated_from: 'firebase' },
        }),
      });
      byEmail.set(email, user);
    }

    let recovery = null;
    try {
      recovery = (await request('/auth/v1/admin/generate_link', {
        method: 'POST',
        body: JSON.stringify({
          type: 'recovery',
          email,
          redirect_to: 'https://scentify.app/reset-password',
        }),
      })).action_link || null;
    } catch (_) {
      // The account is still provisioned; the app's forgot-password flow can issue a reset.
    }
    result.push({ email, firebaseUid, supabaseUserId: user.id, recovery });
  }

  fs.writeFileSync('/tmp/scentify-supabase-auth-migration.json', JSON.stringify({
    generatedAt: new Date().toISOString(),
    users: result,
  }, null, 2), { mode: 0o600 });
  console.log(JSON.stringify({ provisioned: result.length, recoveryLinks: result.filter((row) => row.recovery).length }));
})().catch((error) => { console.error(error.message); process.exitCode = 1; });
