const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');

const projectId = process.env.GCLOUD_PROJECT || 'scentify-b97e5';
const email = process.env.SCENTIFY_ADMIN_EMAIL?.trim();
const password = process.env.SCENTIFY_ADMIN_PASSWORD;
const displayName =
  process.env.SCENTIFY_ADMIN_DISPLAY_NAME?.trim() || 'Scentify Admin';
const isSuperadmin = process.env.SCENTIFY_SUPERADMIN === 'true';

if (!email || !password) {
  throw new Error(
    'Set SCENTIFY_ADMIN_EMAIL and SCENTIFY_ADMIN_PASSWORD before running this script.',
  );
}

if (password.length < 6) {
  throw new Error('SCENTIFY_ADMIN_PASSWORD must contain at least 6 characters.');
}

initializeApp({
  credential: applicationDefault(),
  projectId,
});

async function provisionAdmin() {
  const auth = getAuth();
  const firestore = getFirestore();
  let user;
  let existed = true;

  try {
    user = await auth.getUserByEmail(email);
    user = await auth.updateUser(user.uid, {
      email,
      password,
      displayName,
      disabled: false,
    });
  } catch (error) {
    if (error.code !== 'auth/user-not-found') {
      throw error;
    }
    existed = false;
    user = await auth.createUser({
      email,
      password,
      displayName,
    });
  }

  const customClaims = {
    ...(user.customClaims || {}),
    admin: true,
  };
  if (isSuperadmin) {
    customClaims.superadmin = true;
  } else {
    delete customClaims.superadmin;
  }
  await auth.setCustomUserClaims(user.uid, customClaims);

  const profileRef = firestore.collection('users').doc(user.uid);
  const profileSnapshot = await profileRef.get();
  const profile = {
    email,
    displayName,
    role: isSuperadmin ? 'superadmin' : 'admin',
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!profileSnapshot.exists) {
    profile.createdAt = FieldValue.serverTimestamp();
  }
  await profileRef.set(profile, { merge: true });

  console.log(
    `${existed ? 'Updated' : 'Created'} ${isSuperadmin ? 'superadmin' : 'admin'} account ${email} (${user.uid}).`,
  );
  console.log(
    `The same Scentify login page will route this account to ${isSuperadmin ? 'Superadmin' : 'Admin'}.`,
  );
}

provisionAdmin().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
