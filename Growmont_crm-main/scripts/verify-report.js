// scripts/verify-report.js
//
// Independent ground truth for the Monthly Report screen.
//
// Reads the emulator's Firestore directly and recomputes every figure the
// report shows — in JavaScript, from the raw documents, with no reference
// to the Dart aggregation code. That independence is the point: if this
// script and the app agree, two separate implementations of the same spec
// read the same data the same way. If they disagree, one of them has a
// bug, and the numbers below say exactly where to look.
//
// Usage (emulators must be running):
//   npm --prefix scripts run verify            # current month
//   node scripts/verify-report.js 2025-10      # a specific month
//
// Safety: same guard as seed-emulator.js. Loopback emulator only; never
// the live project.

import admin from 'firebase-admin';

// ─── Guard ───────────────────────────────────────────────────────────────

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const isLocal = /^(localhost|127\.0\.0\.1|\[::1\]):\d+$/.test(firestoreHost);

if (!isLocal) {
  console.error(`REFUSING TO RUN: FIRESTORE_EMULATOR_HOST=${firestoreHost} is not local.`);
  process.exit(1);
}

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'growmontcrm' });
const db = admin.firestore();

// ─── Period ──────────────────────────────────────────────────────────────

const arg = process.argv[2];
const now = new Date();
let year = now.getFullYear();
let month = now.getMonth() + 1; // 1-based

if (arg) {
  const match = /^(\d{4})-(\d{1,2})$/.exec(arg);
  if (!match) {
    console.error(`Bad month "${arg}". Use YYYY-MM, e.g. 2025-10.`);
    process.exit(1);
  }
  year = Number(match[1]);
  month = Number(match[2]);
}

/// Half-open [start, end) in local time, matching the app's rule: a record
/// belongs to the month shown on its date, with no timezone shifting.
const range = (y, m) => ({
  start: new Date(y, m - 1, 1),
  end: new Date(y, m, 1),
});

const period = range(year, month);
const prevMonthDate = new Date(year, month - 2, 1);
const previous = range(prevMonthDate.getFullYear(), prevMonthDate.getMonth() + 1);

const monthName = (y, m) =>
  new Date(y, m - 1, 1).toLocaleString('en-US', { month: 'long', year: 'numeric' });

/// A stored Timestamp as the local calendar day it displays as. Returns
/// null for a missing or unusable value, which is counted, never dropped
/// silently.
function calendarDay(value) {
  if (!value) return null;
  let date;
  if (typeof value.toDate === 'function') date = value.toDate();
  else if (value instanceof Date) date = value;
  else if (typeof value === 'string') {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return null;
    date = parsed;
  } else return null;
  if (Number.isNaN(date.getTime())) return null;
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

const inRange = (day, r) => day !== null && day >= r.start && day < r.end;

// ─── Formatting ──────────────────────────────────────────────────────────

const rupees = (paise) =>
  '₹' + Math.round(paise / 100).toLocaleString('en-IN');

function percent(current, prev) {
  if (prev === 0) return current === 0 ? 'no activity last month' : 'new vs last month';
  const change = ((current - prev) / Math.abs(prev)) * 100;
  const sign = change > 0 ? '+' : change < 0 ? '-' : '';
  if (change === 0) return 'flat';
  const magnitude = Math.abs(change);
  return `${sign}${magnitude >= 100 ? magnitude.toFixed(0) : magnitude.toFixed(1)}%`;
}

function row(label, value, extra = '') {
  console.log(`  ${String(label).padEnd(30)} ${String(value).padStart(16)}  ${extra}`);
}

// ─── Verify ──────────────────────────────────────────────────────────────

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

  const names = new Map();
  employeesSnap.forEach((d) => names.set(d.id, d.data().name || d.id));

  // ── Sales ──
  let revenue = 0, deals = 0, prevRevenue = 0, prevDeals = 0, undatedSales = 0;
  const activeClients = new Set();
  const prevActiveClients = new Set();
  const byProduct = new Map();
  const byCompany = new Map();
  const perEmployee = new Map();

  const clientKey = (sale) =>
    sale.client_id ? `id:${sale.client_id}`
      : sale.client_name ? `name:${String(sale.client_name).trim().toLowerCase()}`
        : null;

  salesSnap.forEach((doc) => {
    const sale = doc.data();
    const day = calendarDay(sale.date);
    if (day === null) { undatedSales++; return; }

    const paise = Number.isFinite(sale.amount_paise)
      ? sale.amount_paise
      : Math.round(Number(sale.amount || 0) * 100);
    const rep = sale.sales_rep_id || sale.sales_rep || '';

    if (inRange(day, period)) {
      revenue += paise;
      deals++;
      const key = clientKey(sale);
      if (key) activeClients.add(key);

      const product = PRODUCT_LABELS[sale.product] || sale.product || 'Unspecified';
      byProduct.set(product, (byProduct.get(product) || 0) + paise);
      const company = (sale.company || '').trim() || 'Unspecified';
      byCompany.set(company, (byCompany.get(company) || 0) + paise);

      const entry = perEmployee.get(rep) || { revenue: 0, deals: 0, prev: 0, logs: 0 };
      entry.revenue += paise;
      entry.deals++;
      perEmployee.set(rep, entry);
    } else if (inRange(day, previous)) {
      prevRevenue += paise;
      prevDeals++;
      const key = clientKey(sale);
      if (key) prevActiveClients.add(key);
      const entry = perEmployee.get(rep) || { revenue: 0, deals: 0, prev: 0, logs: 0 };
      entry.prev += paise;
      perEmployee.set(rep, entry);
    }
  });

  // ── Interactions ──
  let interactions = 0, prevInteractions = 0, undatedInteractions = 0;
  let followUpsScheduled = 0, followUpsPastDue = 0;
  const byPriority = new Map([['HIGH', 0], ['MEDIUM', 0], ['LOW', 0]]);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  interactionsSnap.forEach((doc) => {
    const it = doc.data();
    const day = calendarDay(it.date);
    if (day === null) undatedInteractions++;
    else if (inRange(day, period)) {
      interactions++;
      const p = it.priority || 'MEDIUM';
      byPriority.set(p, (byPriority.get(p) || 0) + 1);
      const rep = it.employee_id || it.employee || '';
      const entry = perEmployee.get(rep) || { revenue: 0, deals: 0, prev: 0, logs: 0 };
      entry.logs++;
      perEmployee.set(rep, entry);
    } else if (inRange(day, previous)) prevInteractions++;

    const followUp = calendarDay(it.follow_up_date);
    if (inRange(followUp, period)) {
      followUpsScheduled++;
      if (followUp <= today) followUpsPastDue++;
    }
  });

  // ── Clients ──
  let newClients = 0, prevNewClients = 0, missingCreatedAt = 0;
  clientsSnap.forEach((doc) => {
    const day = calendarDay(doc.data().created_at);
    if (day === null) missingCreatedAt++;
    else if (inRange(day, period)) newClients++;
    else if (inRange(day, previous)) prevNewClients++;
  });

  // ── Report ──
  const avg = deals > 0 ? Math.trunc(revenue / deals) : 0;
  const prevAvg = prevDeals > 0 ? Math.trunc(prevRevenue / prevDeals) : 0;

  console.log('');
  console.log('='.repeat(72));
  console.log(`  EXPECTED FIGURES - ${monthName(year, month)} (whole company)`);
  console.log(`  compared against ${monthName(previous.start.getFullYear(), previous.start.getMonth() + 1)}`);
  console.log('='.repeat(72));
  console.log('');
  console.log('  KPI cards');
  row('REVENUE', rupees(revenue), percent(revenue, prevRevenue));
  row('DEALS CLOSED', deals, percent(deals, prevDeals));
  row('AVG DEAL VALUE', rupees(avg), percent(avg, prevAvg));
  row('ACTIVE CLIENTS', activeClients.size, percent(activeClients.size, prevActiveClients.size));
  row('NEW CLIENTS', newClients, percent(newClients, prevNewClients));
  row('INTERACTIONS', interactions, percent(interactions, prevInteractions));
  console.log('');
  console.log('  Follow-up load');
  row('Follow-ups scheduled', followUpsScheduled);
  row('Date already passed', followUpsPastDue);
  console.log('');
  console.log('  Interactions by priority');
  for (const [code, label] of [['HIGH', 'High'], ['MEDIUM', 'Medium'], ['LOW', 'Low']]) {
    row(label, byPriority.get(code) || 0);
  }
  console.log('');
  console.log('  Revenue by product (largest first)');
  [...byProduct.entries()].sort((a, b) => b[1] - a[1]).forEach(([label, paise]) => {
    row(label, rupees(paise), revenue ? `${Math.round((paise / revenue) * 100)}%` : '');
  });
  console.log('');
  console.log('  Revenue by company (largest first)');
  [...byCompany.entries()].sort((a, b) => b[1] - a[1]).forEach(([label, paise]) => {
    row(label, rupees(paise), revenue ? `${Math.round((paise / revenue) * 100)}%` : '');
  });
  console.log('');
  console.log('  Team performance (admin report only)');
  [...perEmployee.entries()]
    .sort((a, b) => b[1].revenue - a[1].revenue)
    .forEach(([id, e]) => {
      row(
        names.get(id) || id,
        rupees(e.revenue),
        `${e.deals} deals, ${e.logs} logs, ${percent(e.revenue, e.prev)} vs prev`,
      );
    });
  console.log('');
  console.log('  Data quality (the warning banner)');
  row('Sales with no usable date', undatedSales);
  row('Interactions with no date', undatedInteractions);
  row('Clients with no created_at', missingCreatedAt);
  console.log('');

  // ── Reconciliation the app must also satisfy ──
  const productTotal = [...byProduct.values()].reduce((a, b) => a + b, 0);
  const companyTotal = [...byCompany.values()].reduce((a, b) => a + b, 0);
  const teamTotal = [...perEmployee.values()].reduce((a, e) => a + e.revenue, 0);
  const priorityTotal = [...byPriority.values()].reduce((a, b) => a + b, 0);

  const checks = [
    ['product breakdown sums to revenue', productTotal === revenue],
    ['company breakdown sums to revenue', companyTotal === revenue],
    ['team revenue sums to company revenue', teamTotal === revenue],
    ['priority counts sum to interactions', priorityTotal === interactions],
    ['active clients <= deals', activeClients.size <= deals],
  ];

  console.log('  Internal consistency');
  let allOk = true;
  for (const [label, ok] of checks) {
    console.log(`  ${ok ? '[PASS]' : '[FAIL]'} ${label}`);
    if (!ok) allOk = false;
  }
  console.log('');
  console.log(allOk
    ? '  Ground truth is self-consistent. Compare the figures above with the app.'
    : '  GROUND TRUTH IS INCONSISTENT - fix this script before trusting it.');
  console.log('');
}

main().catch((error) => {
  console.error('Verification failed:', error);
  process.exit(1);
});
