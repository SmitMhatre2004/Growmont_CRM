// scripts/seed-emulator.js
//
// Creates a development login and a few months of sample CRM data inside
// the local Firebase Emulator Suite, so the app can be exercised without
// touching the live `growmontcrm` project.
//
// ── Safety ───────────────────────────────────────────────────────────────
//
//   The Firebase Admin SDK connects to the LIVE project whenever the
//   emulator host variables are absent — which, for a deployed CRM, would
//   mean writing fabricated sales into production. So this script does not
//   merely hope they are set: it sets them itself, and then refuses to run
//   if they point anywhere other than the local machine.
//
//   That makes reaching production impossible rather than unlikely, and is
//   the whole reason this is a separate file from bootstrap-admin.js (which
//   is designed to talk to the real project).
//
//   Run it with:
//     npm --prefix scripts run seed:emulator
//
// Everything it writes is thrown away the moment the emulators stop,
// unless they were started with --import/--export-on-exit.

import admin from 'firebase-admin';

// ─── Guard ───────────────────────────────────────────────────────────────

// Ports match the `emulators` block in ../firebase.json.
//
// 127.0.0.1 rather than 'localhost' deliberately: the Firestore and Auth
// emulators bind IPv4 only, while Node on Windows resolves 'localhost' to
// ::1 first and fails with ECONNREFUSED before ever trying IPv4.
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;

/// Only a loopback address is acceptable. An override pointing somewhere
/// else would defeat the whole point of the guard.
const isLocal = (hostPort) =>
  /^(localhost|127\.0\.0\.1|\[::1\]):\d+$/.test(hostPort ?? '');

if (!isLocal(firestoreHost) || !isLocal(authHost)) {
  console.error('');
  console.error('REFUSING TO RUN: emulator hosts are not local.');
  console.error('');
  console.error('  FIRESTORE_EMULATOR_HOST     =', firestoreHost);
  console.error('  FIREBASE_AUTH_EMULATOR_HOST =', authHost);
  console.error('');
  console.error('This script only ever writes to a local emulator. Unset');
  console.error('those variables to use the defaults, or point them at');
  console.error('localhost.');
  console.error('');
  process.exit(1);
}

// Refuse to pick up real credentials even if they happen to be configured.
if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.warn(
    'NOTE: GOOGLE_APPLICATION_CREDENTIALS is set but will be ignored - ' +
      'the emulator host variables above take precedence.',
  );
}

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'growmontcrm' });

const auth = admin.auth();
const db = admin.firestore();

// ─── Accounts ────────────────────────────────────────────────────────────

const PASSWORD = process.env.DEV_PASSWORD || 'devpass123';

const PEOPLE = [
  { email: 'dev@growmont.com', name: 'Dev Admin', role: 'ADMIN', gender: 'M' },
  { email: 'asha@growmont.com', name: 'Asha Rao', role: 'EMPLOYEE', gender: 'F' },
  { email: 'bilal@growmont.com', name: 'Bilal Khan', role: 'EMPLOYEE', gender: 'M' },
];

// ─── Sample data shape ───────────────────────────────────────────────────

const PRODUCTS = ['MF', 'HI', 'LI', 'GI', 'BOND', 'PMS', 'CFD'];
const COMPANIES = ['HDFC', 'ICICI', 'SBI', 'Axis', 'Kotak', 'Bajaj'];
const FREQUENCIES = ['M', 'Q', 'H', 'Y', 'O'];
const PRIORITIES = ['HIGH', 'MEDIUM', 'LOW'];

const CLIENT_NAMES = [
  'Acme Industries', 'Bluewave Textiles', 'Crestline Motors',
  'Deccan Agro', 'Eastpoint Logistics', 'Fairfield Foods',
  'Greenfield Estates', 'Harbour Chemicals', 'Indus Pharma',
  'Jupiter Steel', 'Kinetic Tools', 'Lotus Hospitality',
];

/// Deterministic pseudo-random so repeated seeds give comparable numbers.
let seed = 42;
function rand() {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
}
function pick(list) {
  return list[Math.floor(rand() * list.length)];
}
function intBetween(min, max) {
  return Math.floor(rand() * (max - min + 1)) + min;
}

const ts = (date) => admin.firestore.Timestamp.fromDate(date);

/// A date inside the month `monthsAgo` months before today.
function dateInMonth(monthsAgo) {
  const now = new Date();
  const base = new Date(now.getFullYear(), now.getMonth() - monthsAgo, 1);
  const daysInMonth = new Date(
    base.getFullYear(),
    base.getMonth() + 1,
    0,
  ).getDate();
  // Never past today in the current month, so "this month" looks realistic.
  const maxDay = monthsAgo === 0 ? now.getDate() : daysInMonth;
  return new Date(base.getFullYear(), base.getMonth(), intBetween(1, maxDay));
}

// ─── Seed ────────────────────────────────────────────────────────────────

async function wipe(collection) {
  const snapshot = await db.collection(collection).get();
  if (snapshot.empty) return 0;
  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  return snapshot.size;
}

async function main() {
  console.log(`Seeding emulators at firestore=${firestoreHost} auth=${authHost}`);
  console.log('');

  // Start clean so repeated runs do not pile up duplicates.
  for (const collection of [
    'employees', 'clients', 'sales', 'interactions', 'reminders',
    'client_transfers', 'transfer_reasons',
  ]) {
    const removed = await wipe(collection);
    if (removed) console.log(`  cleared ${removed} old ${collection}`);
  }

  // ── Accounts ──
  const employees = [];
  for (const person of PEOPLE) {
    let user;
    try {
      user = await auth.getUserByEmail(person.email);
    } catch {
      user = await auth.createUser({
        email: person.email,
        password: PASSWORD,
        displayName: person.name,
        emailVerified: true,
      });
    }

    await db.collection('employees').doc(user.uid).set({
      name: person.name,
      email: person.email,
      mobile_no: `9${intBetween(100000000, 999999999)}`,
      gender: person.gender,
      dob: ts(new Date(1990, intBetween(0, 11), intBetween(1, 28))),
      role: person.role,
      status: 'ACTIVE',
      created_at: ts(new Date(new Date().getFullYear() - 1, 0, 15)),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    employees.push({ uid: user.uid, ...person });
    console.log(`  employee ${person.role.padEnd(8)} ${person.email}`);
  }

  const reps = employees.filter((e) => e.role === 'EMPLOYEE');

  // ── Clients, spread across the last 6 months by created_at ──
  const clients = [];
  for (let i = 0; i < CLIENT_NAMES.length; i++) {
    const owner = reps[i % reps.length];
    const createdAt = dateInMonth(intBetween(0, 5));
    const ref = db.collection('clients').doc();

    await ref.set({
      name: CLIENT_NAMES[i],
      contact_number: `9${intBetween(100000000, 999999999)}`,
      employee_id: owner.uid,
      employee_name: owner.name,
      created_at: ts(createdAt),
      updated_at: ts(createdAt),
    });
    clients.push({ id: ref.id, name: CLIENT_NAMES[i], owner });
  }
  console.log(`  ${clients.length} clients`);

  // One client with NO created_at, so the report's data-quality warning
  // and its "this is a minimum" wording can actually be seen.
  const undatedRef = db.collection('clients').doc();
  await undatedRef.set({
    name: 'Legacy Imports (no date)',
    contact_number: '9000000000',
    employee_id: reps[0].uid,
    employee_name: reps[0].name,
  });
  clients.push({ id: undatedRef.id, name: 'Legacy Imports (no date)', owner: reps[0] });
  console.log('  1 client deliberately missing created_at');

  // ── Sales across the last 6 months ──
  let saleCount = 0;
  for (let monthsAgo = 0; monthsAgo <= 5; monthsAgo++) {
    for (let n = 0; n < intBetween(6, 14); n++) {
      const client = pick(clients);
      const date = dateInMonth(monthsAgo);
      await db.collection('sales').add({
        date: ts(date),
        client_name: client.name,
        client_id: client.id,
        sales_rep_id: client.owner.uid,
        sales_rep_name: client.owner.name,
        product: pick(PRODUCTS),
        company: pick(COMPANIES),
        scheme: 'Growth Plan',
        amount_paise: intBetween(25, 1200) * 100 * 100,
        frequency: pick(FREQUENCIES),
        remarks: '',
        created_at: ts(date),
        updated_at: ts(date),
      });
      saleCount++;
    }
  }
  console.log(`  ${saleCount} sales across 6 months`);

  // ── Interactions, some with follow-ups in the current month ──
  let interactionCount = 0;
  for (let monthsAgo = 0; monthsAgo <= 2; monthsAgo++) {
    for (let n = 0; n < intBetween(5, 10); n++) {
      const client = pick(clients);
      const date = dateInMonth(monthsAgo);
      const hasFollowUp = rand() > 0.35;
      const followUp = new Date(date);
      followUp.setDate(followUp.getDate() + intBetween(3, 25));

      await db.collection('interactions').add({
        date: ts(date),
        client_name: client.name,
        client_id: client.id,
        client_contact: `9${intBetween(100000000, 999999999)}`,
        employee_id: client.owner.uid,
        employee_name: client.owner.name,
        follow_up_date: hasFollowUp ? ts(followUp) : null,
        follow_up_time: hasFollowUp ? '11:00:00' : '',
        priority: pick(PRIORITIES),
        discussion_notes: 'Seeded sample interaction.',
        created_at: ts(date),
        updated_at: ts(date),
      });
      interactionCount++;
    }
  }
  console.log(`  ${interactionCount} interactions`);

  console.log('');
  console.log('Done. Sign in to the app with:');
  for (const person of PEOPLE) {
    console.log(`  ${person.email.padEnd(22)} ${PASSWORD}   (${person.role})`);
  }
  console.log('');
  console.log('Emulator UI: http://localhost:4000');
}

main().catch((error) => {
  console.error('Seeding failed:', error);
  process.exit(1);
});
