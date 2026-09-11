import admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';

// Credential-resolution block (from scripts/migrate.js)
if (!admin.apps.length) {
  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.resolve('./serviceAccountKey.json');
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('Initialized Firebase Admin with service account.');
  } else if (process.env.FIRESTORE_EMULATOR_HOST) {
    admin.initializeApp({ projectId: 'growmontcrm' });
    console.log('Initialized Firebase Admin for Emulator.');
  } else {
    console.warn('WARNING: No serviceAccountKey.json found and FIRESTORE_EMULATOR_HOST not set.');
    console.warn('Defaulting to projectId: growmontcrm (Ensure local emulator or ADC is active).');
    admin.initializeApp({ projectId: 'growmontcrm' });
  }
}

const auth = admin.auth();
const db = admin.firestore();

// Credentials come from the environment so this file carries no secret and is
// safe to commit. Set them for the one command:
//   ADMIN_PASSWORD='...' npm run bootstrap-admin
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'samir@growmont.com';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;
const ADMIN_NAME = process.env.ADMIN_NAME || 'Samir Joshi';

if (!ADMIN_PASSWORD) {
  console.error('ERROR: ADMIN_PASSWORD is not set.');
  console.error('');
  console.error('Run it with the password supplied for that command only, e.g.');
  console.error("  ADMIN_PASSWORD='your-password' npm run bootstrap-admin");
  console.error('');
  console.error('Optional overrides: ADMIN_EMAIL, ADMIN_NAME.');
  process.exit(1);
}

async function bootstrapAdmin() {
  console.log(`\nBootstrapping admin account: ${ADMIN_EMAIL}...`);

  let uid;
  try {
    const existing = await auth.getUserByEmail(ADMIN_EMAIL);
    uid = existing.uid;
    await auth.updateUser(uid, {
      password: ADMIN_PASSWORD,
      displayName: ADMIN_NAME,
      disabled: false,
    });
    console.log(`Updated existing Firebase Auth user: ${uid}`);
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      const newUser = await auth.createUser({
        email: ADMIN_EMAIL,
        password: ADMIN_PASSWORD,
        displayName: ADMIN_NAME,
        disabled: false,
      });
      uid = newUser.uid;
      console.log(`Created new Firebase Auth user: ${uid}`);
    } else {
      throw err;
    }
  }

  // Set custom claims for RBAC and ACTIVE status
  await auth.setCustomUserClaims(uid, {
    role: 'ADMIN',
    status: 'ACTIVE',
  });
  console.log(`Set custom claims { role: 'ADMIN', status: 'ACTIVE' } for UID: ${uid}`);

  // Set employee document matching createEmployee schema exactly.
  // created_at is only stamped on first write so re-running this script
  // refreshes the password/claims without rewriting the account's history.
  const docRef = db.collection('employees').doc(uid);
  const existingDoc = await docRef.get();
  const employeeData = {
    name: ADMIN_NAME,
    email: ADMIN_EMAIL,
    mobile_no: '',
    gender: 'O',
    dob: null,
    avatar_url: '',
    role: 'ADMIN',
    status: 'ACTIVE',
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Counters and created_at are seeded on first write only — a re-run is for
  // resetting the password/claims and must not zero a live account's totals.
  if (!existingDoc.exists) {
    employeeData.clients_count = 0;
    employeeData.sales_count = 0;
    employeeData.interactions_count = 0;
    employeeData.created_at = admin.firestore.FieldValue.serverTimestamp();
  }

  await docRef.set(employeeData, { merge: true });
  console.log(`Employee document written in Firestore under employees/${uid}`);

  console.log('\n=============================================================');
  console.log(`SUCCESS: Admin account ready!`);
  console.log(`UID: ${uid}`);
  console.log(`Email: ${ADMIN_EMAIL}`);
  console.log('Password: (as supplied via ADMIN_PASSWORD)');
  console.log('\nNOTE: If already signed in, the admin must sign out and back in');
  console.log('once for the fresh claims to land in their ID token.');
  console.log('=============================================================\n');
}

bootstrapAdmin().catch((err) => {
  console.error('Error bootstrapping admin account:', err);
  process.exit(1);
});
