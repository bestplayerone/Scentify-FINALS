const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const email = process.env.SCENTIFY_ADMIN_EMAIL?.trim();
const password = process.env.SCENTIFY_ADMIN_PASSWORD;
const displayName =
  process.env.SCENTIFY_ADMIN_DISPLAY_NAME?.trim() || 'Scentify Admin';
const projectId = process.env.GCLOUD_PROJECT || 'scentify-b97e5';
const localId =
  process.env.SCENTIFY_ADMIN_LOCAL_ID?.trim() ||
  crypto.randomBytes(16).toString('hex');
const isSuperadmin = process.env.SCENTIFY_SUPERADMIN === 'true';

if (!email || !password) {
  throw new Error(
    'Set SCENTIFY_ADMIN_EMAIL and SCENTIFY_ADMIN_PASSWORD before importing.',
  );
}

if (password.length < 6) {
  throw new Error('SCENTIFY_ADMIN_PASSWORD must contain at least 6 characters.');
}

const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'scentify-admin-'));
const importFile = path.join(tempDirectory, 'admin.json');
const passwordHash = crypto.createHash('sha256').update(password).digest('base64');
const importData = {
  users: [
    {
      localId,
      email,
      displayName,
      passwordHash,
      customAttributes: JSON.stringify({
        admin: true,
        ...(isSuperadmin ? { superadmin: true } : {}),
      }),
    },
  ],
};

try {
  fs.writeFileSync(importFile, JSON.stringify(importData));
  const result = spawnSync(
    'firebase',
    [
      'auth:import',
      importFile,
      '--project',
      projectId,
      '--hash-algo',
      'SHA256',
      '--rounds',
      '1',
    ],
    { stdio: 'inherit' },
  );
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.exitCode = result.status || 1;
  }
} finally {
  fs.rmSync(tempDirectory, { recursive: true, force: true });
}
