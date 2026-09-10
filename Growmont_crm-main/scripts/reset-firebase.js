import admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';

// Credential-resolution block (from scripts/migrate.js)
if (!admin.apps.length) {
  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.resolve('./serviceAccountKey.json');
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || 'growmontcrm'
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

const TARGET_PROJECT = 'growmontcrm';
const COLLECTIONS_TO_CLEAR = [
  'employees',
  'clients',
  'sales',
  'interactions',
  'reminders'
];

const args = process.argv.slice(2);
const hasConfirm = args.includes('--confirm');
const projectArg = args.find(a => a.startsWith('--project='));
const projectVal = projectArg ? projectArg.split('=')[1] : null;
const includeStorage = args.includes('--include-storage');

const isDryRun = !hasConfirm || projectVal !== TARGET_PROJECT;

async function runReset() {
  const appProjectId = admin.app().options.projectId;

  console.log('\n=============================================================');
  console.log('              Growmont CRM Fresh-Start Reset Script          ');
  console.log('=============================================================');
  console.log(`Active Project: ${appProjectId}`);
  console.log(`Execution Mode: ${isDryRun ? 'DRY-RUN (Safe, no changes will be made)' : 'DESTRUCTIVE LIVE EXECUTION'}`);
  console.log(`Include Storage: ${includeStorage ? 'Yes (avatars/ prefix)' : 'No'}\n`);

  if (isDryRun) {
    if (hasConfirm && projectVal !== TARGET_PROJECT) {
      console.error(`ERROR: --project argument must match '${TARGET_PROJECT}', got '${projectVal}'.`);
    } else {
      console.log('Safety guard: Neither --confirm nor --project=growmontcrm was fully specified.');
    }
  }

  // 1. Scan / Delete Auth Users
  console.log('--- 1. Scanning Firebase Auth users ---');
  let totalAuthUsers = 0;
  let pageToken = undefined;
  const allUids = [];

  do {
    const listResult = await auth.listUsers(1000, pageToken);
    pageToken = listResult.pageToken;
    for (const u of listResult.users) {
      allUids.push(u.uid);
    }
    totalAuthUsers += listResult.users.length;
  } while (pageToken);

  console.log(`Found ${totalAuthUsers} Auth user(s).`);

  if (!isDryRun && allUids.length > 0) {
    console.log(`Deleting ${allUids.length} Auth user(s)...`);
    // Delete in chunks of 1000
    for (let i = 0; i < allUids.length; i += 1000) {
      const chunk = allUids.slice(i, i + 1000);
      const deleteResult = await auth.deleteUsers(chunk);
      console.log(`Deleted batch of ${chunk.length} users (Errors: ${deleteResult.failureCount}).`);
    }
  }

  // 2. Scan / Delete Firestore Documents
  console.log('\n--- 2. Scanning Firestore Collections ---');
  for (const colName of COLLECTIONS_TO_CLEAR) {
    const colRef = db.collection(colName);
    const snap = await colRef.get();
    console.log(`Collection '${colName}': found ${snap.docs.length} document(s).`);

    if (!isDryRun && snap.docs.length > 0) {
      console.log(`Deleting documents in '${colName}'...`);
      // Delete in batches of 400
      const docs = snap.docs;
      for (let i = 0; i < docs.length; i += 400) {
        const batch = db.batch();
        const slice = docs.slice(i, i + 400);
        for (const doc of slice) {
          batch.delete(doc.ref);
        }
        await batch.commit();
        console.log(`  Committed batch delete of ${slice.length} document(s) in '${colName}'.`);
      }
    }
  }

  // 3. Optional Storage Deletion
  if (includeStorage) {
    console.log('\n--- 3. Firebase Storage (avatars/) ---');
    try {
      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({ prefix: 'avatars/' });
      console.log(`Found ${files.length} file(s) under 'avatars/'.`);
      if (!isDryRun && files.length > 0) {
        await bucket.deleteFiles({ prefix: 'avatars/' });
        console.log(`Deleted all files under 'avatars/'.`);
      }
    } catch (storageErr) {
      console.warn(`Storage note: ${storageErr.message}`);
    }
  }

  console.log('\n=============================================================');
  if (isDryRun) {
    console.log('DRY RUN COMPLETE — No data was modified.');
    console.log('To perform the actual reset, execute:');
    console.log(`npm run reset -- --confirm --project=${TARGET_PROJECT}${includeStorage ? ' --include-storage' : ''}`);
  } else {
    console.log('RESET COMPLETE — All requested data has been cleared.');
    console.log('Next step: run bootstrap-admin to create the initial admin account:');
    console.log('npm run bootstrap-admin');
  }
  console.log('=============================================================\n');
}

runReset().catch(err => {
  console.error('Fatal error during reset:', err);
  process.exit(1);
});
