// scripts/dump-fixture.js
//
// Writes the emulator's current contents, plus independently computed
// expected figures, to a JSON fixture that the Dart test suite reads back.
//
// ── Why ──────────────────────────────────────────────────────────────────
//
// Every other test of the reporting layer feeds it hand-written objects.
// That proves the arithmetic but not the pipeline: a field named wrongly,
// a date stored in a shape the parser does not expect, or a sale attached
// to an id the report never looks at would all pass those tests and still
// produce a wrong report on real records.
//
// This fixture closes that gap. The data is whatever the emulator really
// holds; the expectations are recomputed here in JavaScript, from the raw
// documents, with no reference to the Dart code. If the two agree, two
// independent implementations read the same real records the same way.
//
// Regenerate after reseeding:
//   npm --prefix scripts run dump:fixture
//
// Safety: loopback emulator only, same guard as the other scripts.

import admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
const host = process.env.FIRESTORE_EMULATOR_HOST;

if (!/^(localhost|127\.0\.0\.1|\[::1\]):\d+$/.test(host)) {
  console.error(`REFUSING TO RUN: FIRESTORE_EMULATOR_HOST=${host} is not local.`);
  process.exit(1);
}

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'growmontcrm' });
const db = admin.firestore();

// ─── Date handling ───────────────────────────────────────────────────────

/// Mirrors what the app's local store writes: a Firestore Timestamp comes
/// out of SQLite as an ISO string in LOCAL time with no trailing Z,
/// because toJsonSafe calls Timestamp.toDate().toIso8601String(). Emitting
/// UTC here would hand the Dart parser a different shape than it sees in
/// the running app, and the fixture would stop being representative.
function localIso(value) {
  if (!value || typeof value.toDate !== 'function') return null;
  const d = value.toDate();
  const p = (n, w = 2) => String(n).padStart(w, '0');
  return (
    `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}` +
    `T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}` +
    `.${p(d.getMilliseconds(), 3)}`
  );
}

const calendarDay = (value) => {
  if (!value || typeof value.toDate !== 'function') return null;
  const d = value.toDate();
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
};

// ─── Period ──────────────────────────────────────────────────────────────

const arg = process.argv[2];
const now = new Date();
let year = now.getFullYear();
let month = now.getMonth() + 1;
if (arg) {
  const m = /^(\d{4})-(\d{1,2})$/.exec(arg);
  if (!m) {
    console.error(`Bad month "${arg}". Use YYYY-MM.`);
    process.exit(1);
  }
  year = Number(m[1]);
  month = Number(m[2]);
}

const range = (y, mo) => ({
  start: new Date(y, mo - 1, 1),
  end: new Date(y, mo, 1),
});
const period = range(year, month);
const prev = new Date(year, month - 2, 1);
const previous = range(prev.getFullYear(), prev.getMonth() + 1);
const inRange = (d, r) => d !== null && d >= r.start && d < r.end;

const PRODUCT_LABELS = {
  MF: 'Mutual Funds', HI: 'Health Insurance', GI: 'General Insurance',
  LI: 'Life Insurance', NCD: 'NCDs', MLD: 'MLDs', BOND: 'Bonds',
  CFD: 'Corporate FDs', AIF: 'AIFs', PMS: 'PMS', ADV: 'Advisory',
  SB: 'Shares Broking', US: 'Unlisted Shares', RE: 'Real Estate',
  LOAN: 'Loans', WILL: 'Will Making',
};

async function main() {
  const [salesSnap, interactionsSnap, clientsSnap, employeesSnap] =
    await Promise.all([
      db.collection('sales').get(),
      db.collection('interactions').get(),
      db.collection('clients').get(),
      db.collection('employees').get(),
    ]);

  // ── Raw records, in the shape the local store hands the models ──
  const sales = salesSnap.docs.map((d) => {
    const v = d.data();
    return {
      id: d.id,
      date: localIso(v.date),
      client_name: v.client_name ?? '',
      client_id: v.client_id ?? null,
      sales_rep_id: v.sales_rep_id ?? '',
      sales_rep_name: v.sales_rep_name ?? null,
      product: v.product ?? '',
      company: v.company ?? '',
      scheme: v.scheme ?? '',
      amount_paise: v.amount_paise ?? 0,
      frequency: v.frequency ?? 'M',
      remarks: v.remarks ?? '',
      created_at: localIso(v.created_at),
    };
  });

  const interactions = interactionsSnap.docs.map((d) => {
    const v = d.data();
    return {
      id: d.id,
      date: localIso(v.date),
      client_name: v.client_name ?? '',
      client_id: v.client_id ?? null,
      client_contact: v.client_contact ?? '',
      employee_id: v.employee_id ?? '',
      employee_name: v.employee_name ?? null,
      follow_up_date: localIso(v.follow_up_date),
      follow_up_time: v.follow_up_time ?? '',
      priority: v.priority ?? 'MEDIUM',
      discussion_notes: v.discussion_notes ?? '',
    };
  });

  const clients = clientsSnap.docs.map((d) => {
    const v = d.data();
    return {
      id: d.id,
      name: v.name ?? '',
      contact_number: v.contact_number ?? '',
      employee_id: v.employee_id ?? '',
      employee_name: v.employee_name ?? null,
      created_at: localIso(v.created_at),
    };
  });

  const employeeNames = {};
  employeesSnap.forEach((d) => {
    employeeNames[d.id] = d.data().name ?? d.id;
  });

  // ── Expectations, recomputed here from the raw documents ──
  function expectationsFor(repId) {
    const mine = (s) => repId === null || s.sales_rep_id === repId;
    const mineI = (i) => repId === null || i.employee_id === repId;
    const mineC = (c) => repId === null || c.employee_id === repId;

    let revenue = 0, deals = 0, prevRevenue = 0, prevDeals = 0, undated = 0;
    const active = new Set();
    const prevActive = new Set();
    const byProduct = new Map();
    const byCompany = new Map();

    for (const s of salesSnap.docs.map((d) => ({ id: d.id, ...d.data() }))) {
      if (repId !== null && (s.sales_rep_id ?? '') !== repId) continue;
      const day = calendarDay(s.date);
      if (day === null) { undated++; continue; }
      const paise = s.amount_paise ?? 0;
      const key = s.client_id ? `id:${s.client_id}`
        : s.client_name ? `name:${String(s.client_name).trim().toLowerCase()}` : null;

      if (inRange(day, period)) {
        revenue += paise; deals++;
        if (key) active.add(key);
        const product = PRODUCT_LABELS[s.product] || s.product || 'Unspecified';
        byProduct.set(product, (byProduct.get(product) || 0) + paise);
        const company = (s.company || '').trim() || 'Unspecified';
        byCompany.set(company, (byCompany.get(company) || 0) + paise);
      } else if (inRange(day, previous)) {
        prevRevenue += paise; prevDeals++;
        if (key) prevActive.add(key);
      }
    }

    let interactionCount = 0, prevInteractions = 0, undatedI = 0;
    let scheduled = 0, passed = 0;
    const byPriority = { HIGH: 0, MEDIUM: 0, LOW: 0 };
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    for (const i of interactionsSnap.docs.map((d) => d.data())) {
      if (repId !== null && (i.employee_id ?? '') !== repId) continue;
      const day = calendarDay(i.date);
      if (day === null) undatedI++;
      else if (inRange(day, period)) {
        interactionCount++;
        const p = i.priority || 'MEDIUM';
        byPriority[p] = (byPriority[p] || 0) + 1;
      } else if (inRange(day, previous)) prevInteractions++;

      const fu = calendarDay(i.follow_up_date);
      if (inRange(fu, period)) {
        scheduled++;
        if (fu <= today) passed++;
      }
    }

    let newClients = 0, prevNewClients = 0, missingCreated = 0;
    for (const c of clientsSnap.docs.map((d) => d.data())) {
      if (repId !== null && (c.employee_id ?? '') !== repId) continue;
      const day = calendarDay(c.created_at);
      if (day === null) missingCreated++;
      else if (inRange(day, period)) newClients++;
      else if (inRange(day, previous)) prevNewClients++;
    }

    const sortRows = (m) =>
      [...m.entries()]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .map(([label, paise]) => ({ label, paise }));

    return {
      revenue, previousRevenue: prevRevenue,
      deals, previousDeals: prevDeals,
      avgDeal: deals > 0 ? Math.trunc(revenue / deals) : 0,
      activeClients: active.size, previousActiveClients: prevActive.size,
      newClients, previousNewClients: prevNewClients,
      interactions: interactionCount, previousInteractions: prevInteractions,
      followUpsScheduled: scheduled, followUpsPastDue: passed,
      priorityHigh: byPriority.HIGH || 0,
      priorityMedium: byPriority.MEDIUM || 0,
      priorityLow: byPriority.LOW || 0,
      salesWithoutDate: undated,
      interactionsWithoutDate: undatedI,
      clientsWithoutCreatedAt: missingCreated,
      revenueByProduct: sortRows(byProduct),
      revenueByCompany: sortRows(byCompany),
    };
  }

  const perEmployee = {};
  for (const id of Object.keys(employeeNames)) {
    perEmployee[id] = expectationsFor(id);
  }

  const fixture = {
    generatedAt: new Date().toISOString(),
    period: { year, month },
    // The day the expectations were computed on: the past-due follow-up
    // count depends on it, so the Dart side must use the same one.
    today: {
      year: now.getFullYear(),
      month: now.getMonth() + 1,
      day: now.getDate(),
    },
    sales,
    interactions,
    clients,
    employeeNames,
    company: expectationsFor(null),
    perEmployee,
  };

  const out = path.resolve('../flutterapp/test/fixtures/emulator_report.json');
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, `${JSON.stringify(fixture, null, 2)}\n`);

  console.log(`Wrote ${out}`);
  console.log(
    `  ${sales.length} sales, ${interactions.length} interactions, ` +
      `${clients.length} clients, ${Object.keys(employeeNames).length} employees`,
  );
  console.log(
    `  company ${new Date(year, month - 1).toLocaleString('en-US', { month: 'long', year: 'numeric' })}: ` +
      `revenue ${fixture.company.revenue} paise, ${fixture.company.deals} deals`,
  );
}

main().catch((e) => {
  console.error('Dump failed:', e);
  process.exit(1);
});
