/**
 * Attendance tests. The callable handlers run against a tiny in-memory
 * Firestore fake (optimistic transactions with retry) and a controllable
 * clock, so no emulator is needed.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import * as L from '../attendance_logic.js';
import { createAttendanceHandlers } from '../attendance.js';

// ───────────────────────── in-memory Firestore fake ─────────────────────────

class FakeTs {
  constructor(ms) { this.ms = ms; }
  toDate() { return new Date(this.ms); }
  toMillis() { return this.ms; }
  static fromDate(d) { return new FakeTs(d.getTime()); }
}

const clone = (v) => {
  if (v === null || v === undefined || v instanceof FakeTs) return v;
  if (Array.isArray(v)) return v.map(clone);
  if (typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = clone(x);
    return o;
  }
  return v;
};

function createFakeDb() {
  const store = new Map(); // "col/id" -> {data, version}
  let auto = 0;
  const key = (c, id) => `${c}/${id}`;
  const snap = (c, id) => {
    const e = store.get(key(c, id));
    return { id, exists: Boolean(e), data: () => (e ? clone(e.data) : undefined) };
  };
  const version = (c, id) => (store.get(key(c, id)) || { version: 0 }).version;
  const write = (c, id, data) => {
    const e = store.get(key(c, id));
    store.set(key(c, id), { data: clone(data), version: (e ? e.version : 0) + 1 });
  };
  const deleted = new Map();
  const del = (c, id) => {
    const e = store.get(key(c, id));
    if (e) {
      deleted.set(key(c, id), e.version + 1);
      store.delete(key(c, id));
    }
  };
  const versionOf = (c, id) => (store.has(key(c, id)) ? store.get(key(c, id)).version : deleted.get(key(c, id)) || 0);

  const listDocs = (c, filters = []) => {
    const docs = [];
    for (const k of store.keys()) {
      if (!k.startsWith(`${c}/`)) continue;
      const id = k.slice(c.length + 1);
      const s = snap(c, id);
      if (filters.every(([f, v]) => s.data()[f] === v)) docs.push(s);
    }
    return docs;
  };
  const query = (c, filters) => ({
    where: (f, op, v) => {
      assert.equal(op, '==');
      return query(c, [...filters, [f, v]]);
    },
    get: async () => ({ docs: listDocs(c, filters), size: listDocs(c, filters).length }),
  });
  const db = {
    collection: (c) => ({
      ...query(c, []),
      doc: (id) => {
        const docId = id === undefined ? `auto${++auto}` : id;
        return { _c: c, id: docId, get: async () => snap(c, docId) };
      },
    }),
    async runTransaction(fn) {
      for (let attempt = 0; attempt < 8; attempt += 1) {
        const reads = [];
        const writes = [];
        const tx = {
          async get(ref) {
            await Promise.resolve(); // let concurrent callers interleave
            reads.push([ref._c, ref.id, versionOf(ref._c, ref.id)]);
            return snap(ref._c, ref.id);
          },
          set(ref, data) { assert.ok(reads.length >= 0); writes.push(['set', ref, data]); },
          delete(ref) { writes.push(['delete', ref]); },
        };
        const result = await fn(tx);
        if (reads.every(([c, id, v]) => versionOf(c, id) === v)) {
          for (const [op, ref, data] of writes) {
            if (op === 'set') write(ref._c, ref.id, data); else del(ref._c, ref.id);
          }
          return result;
        }
      }
      throw new Error('transaction retries exhausted');
    },
  };
  return {
    db,
    put: (c, id, data) => write(c, id, data),
    get: (c, id) => { const s = snap(c, id); return s.exists ? s.data() : null; },
    all: (c) => listDocs(c).map((s) => ({ id: s.id, ...s.data() })),
    remove: (c, id) => del(c, id),
  };
}

// ───────────────────────── harness ─────────────────────────

const OFFICE = { lat: 19.076, lng: 72.8777 };
// ~1 degree of latitude is 111,195 m with R = 6,371,000
const metersNorth = (m) => ({ lat: OFFICE.lat + m / 111194.93, lng: OFFICE.lng });

function makeEnv(startIso = '2026-11-18T10:00:00+05:30', { configured = true } = {}) {
  const fake = createFakeDb();
  let clock = new Date(startIso);
  const handlers = createAttendanceHandlers({ db: fake.db, Timestamp: FakeTs, now: () => new Date(clock) });
  const emp = (id, extra = {}) => fake.put('employees', id, {
    name: id, role: 'EMPLOYEE', status: 'ACTIVE', approved_at: new FakeTs(new Date('2026-01-01T00:00:00Z').getTime()), ...extra,
  });
  emp('alice'); emp('bob'); emp('carol');
  emp('admin1', { role: 'ADMIN' }); emp('admin2', { role: 'ADMIN' });
  emp('restricted', { status: 'RESTRICTED' });
  if (configured) {
    fake.put('attendance_settings', 'config', {
      office: OFFICE, radius_m: 100, max_accuracy_m: 25, arrival: '10:00', leave: '19:00', grace_minutes: 15,
      weekly_off_history: [{ from: '2026-01-01', days: [7] }], started_on: '2026-01-01',
    });
  }
  const env = {
    fake,
    set: (iso) => { clock = new Date(iso); },
    advance: (ms) => { clock = new Date(clock.getTime() + ms); },
    emp,
    call: (name, uid, data) => handlers[name]({ auth: uid ? { uid } : null, data }),
    markData: (o = {}) => ({
      action: 'in', ...OFFICE, accuracy_m: 10, is_mocked: false, position_age_ms: 1000,
      device_id: 'dev1', biometric_passed: true, ...o,
    }),
    markIn: (uid, o = {}) => env.call('attendanceMark', uid, env.markData({ action: 'in', device_id: `dev-${uid}`, ...o })),
    markOut: (uid, o = {}) => env.call('attendanceMark', uid, env.markData({ action: 'out', device_id: `dev-${uid}`, ...o })),
    rec: (uid, date) => fake.get('attendance', `${uid}_${date}`),
    putRecord: (uid, date, extra = {}) => fake.put('attendance', `${uid}_${date}`, baseRecord(uid, date, extra)),
  };
  return env;
}

function baseRecord(uid, date, extra = {}) {
  const inMs = L.istInstant(date, '10:00').getTime();
  return {
    employee_id: uid, employee_name: uid, date, month: date.slice(0, 7),
    shift: { arrival: '10:00', leave: '19:00', grace_minutes: 15 },
    check_in_at: new FakeTs(inMs), check_out_at: new FakeTs(inMs + 9 * 3600000),
    check_in_local: '10:00', check_out_local: '19:00',
    check_in_geo: null, check_out_geo: null, worked_minutes: 540, late_minutes: 0, early_minutes: 0,
    late: L.emptyReview(), early: L.emptyReview(), needs_review: false, source: 'self', admin_edited: false,
    ...extra,
  };
}

const codeOf = async (promise) => {
  try { await promise; } catch (e) { return e.details && e.details.code; }
  return 'NO_ERROR';
};
const expectCode = async (promise, code) => assert.equal(await codeOf(promise), code);

// ───────────────────────── pure logic ─────────────────────────

test('grace: check-in at exactly arrival+grace to the second is not late', () => {
  const shift = { arrival: '10:00', leave: '19:00', grace_minutes: 15 };
  const r = L.evaluateLate(new Date('2026-11-18T10:15:00+05:30'), '2026-11-18', shift);
  assert.deepEqual(r, { late: false, minutes: 0 });
});

test('grace: one second after grace is late and minutes are ceil of time after arrival', () => {
  const shift = { arrival: '10:00', leave: '19:00', grace_minutes: 15 };
  const r = L.evaluateLate(new Date('2026-11-18T10:15:01+05:30'), '2026-11-18', shift);
  assert.deepEqual(r, { late: true, minutes: 16 });
});

test('grace: one second before grace ends is not late; zero grace makes arrival+1s late', () => {
  const shift = { arrival: '10:00', leave: '19:00', grace_minutes: 15 };
  assert.equal(L.evaluateLate(new Date('2026-11-18T10:14:59+05:30'), '2026-11-18', shift).late, false);
  const zero = { ...shift, grace_minutes: 0 };
  assert.equal(L.evaluateLate(new Date('2026-11-18T10:00:00+05:30'), '2026-11-18', zero).late, false);
  assert.deepEqual(L.evaluateLate(new Date('2026-11-18T10:00:01+05:30'), '2026-11-18', zero), { late: true, minutes: 1 });
});

test('grace: arriving before the shift starts is never late', () => {
  const shift = { arrival: '10:00', leave: '19:00', grace_minutes: 15 };
  assert.equal(L.evaluateLate(new Date('2026-11-18T06:00:00+05:30'), '2026-11-18', shift).late, false);
});

test('early: leaving at exactly leave-grace is not early, one second sooner is, minutes ceil from leave', () => {
  const shift = { arrival: '10:00', leave: '19:00', grace_minutes: 15 };
  assert.equal(L.evaluateEarly(new Date('2026-11-18T18:45:00+05:30'), '2026-11-18', shift).early, false);
  assert.deepEqual(L.evaluateEarly(new Date('2026-11-18T18:44:59+05:30'), '2026-11-18', shift), { early: true, minutes: 16 });
});

test('IST day boundary: 18:29:59Z is still the same IST day, 18:30:00Z is the next', () => {
  const a = L.istParts(new Date('2026-11-17T18:29:59Z'));
  const b = L.istParts(new Date('2026-11-17T18:30:00Z'));
  assert.deepEqual([a.date, a.time], ['2026-11-17', '23:59']);
  assert.deepEqual([b.date, b.time], ['2026-11-18', '00:00']);
});

test('midnight: a UTC date that is still yesterday in UTC is today in IST', () => {
  assert.equal(L.istParts(new Date('2026-12-31T20:00:00Z')).date, '2027-01-01');
  assert.equal(L.istParts(new Date('2026-12-31T20:00:00Z')).month, '2027-01');
});

test('calendar: leap days, month and year rollovers', () => {
  assert.ok(L.isValidDate('2028-02-29'));
  assert.ok(!L.isValidDate('2026-02-29'));
  assert.ok(!L.isValidDate('2100-02-29'));
  assert.equal(L.addDays('2028-02-28', 1), '2028-02-29');
  assert.equal(L.addDays('2026-02-28', 1), '2026-03-01');
  assert.equal(L.addDays('2026-12-31', 1), '2027-01-01');
  assert.equal(L.daysInMonth('2028-02'), 29);
  assert.equal(L.daysInMonth('2026-02'), 28);
  assert.deepEqual(L.monthRange('2026-12'), { first: '2026-12-01', last: '2026-12-31' });
});

test('calendar: malformed dates, times and months are rejected', () => {
  for (const bad of ['2026-13-01', '2026-1-1', '2026-11-31', '', null, 20261118, '2026-11-18T00:00']) {
    assert.ok(!L.isValidDate(bad), String(bad));
  }
  for (const bad of ['24:00', '9:30', '10:60', '', null, 1000]) assert.ok(!L.isValidTime(bad), String(bad));
  for (const bad of ['2026-00', '2026-13', '202611', null]) assert.ok(!L.isValidMonth(bad), String(bad));
});

test('weekday: ISO numbering with Sunday as 7', () => {
  assert.equal(L.isoWeekday('2026-11-22'), 7);
  assert.equal(L.isoWeekday('2026-11-23'), 1);
  assert.equal(L.isoWeekday('2026-11-18'), 3);
});

test('radius: boundary is inside, just beyond is outside, haversine sanity', () => {
  assert.ok(L.isWithinRadius(100, 100));
  assert.ok(!L.isWithinRadius(100.0001, 100));
  assert.equal(L.haversineMeters(10, 10, 10, 10), 0);
  const d = L.haversineMeters(0, 0, 1, 0);
  assert.ok(Math.abs(d - 111195) < 5);
});

test('coordinates: NaN, strings, Infinity, null and out-of-range values are invalid', () => {
  assert.ok(!L.isValidCoordinate(NaN, 10));
  assert.ok(!L.isValidCoordinate('19.07', 72));
  assert.ok(!L.isValidCoordinate(Infinity, 0));
  assert.ok(!L.isValidCoordinate(null, null));
  assert.ok(!L.isValidCoordinate(91, 0));
  assert.ok(!L.isValidCoordinate(0, 180.0001));
  assert.ok(L.isValidCoordinate(90, 180));
  assert.ok(L.isValidCoordinate(-90, -180));
});

test('weekly-off history: each date uses the entry in force on that date', () => {
  const h = [{ from: '2026-01-01', days: [7] }, { from: '2026-06-01', days: [6, 7] }];
  assert.deepEqual(L.weeklyOffFor(h, '2026-05-31'), [7]);
  assert.deepEqual(L.weeklyOffFor(h, '2026-06-01'), [6, 7]);
  assert.deepEqual(L.weeklyOffFor(h, '2025-01-01'), [7]);
  assert.deepEqual(L.weeklyOffFor([], '2026-01-01'), [7]);
});

test('weekly-off change: appends today, replaces same-day entry, ignores identical set', () => {
  const h = [{ from: '2026-01-01', days: [7] }];
  const a = L.applyWeeklyOffChange(h, [6, 7], '2026-06-01');
  assert.equal(a.length, 2);
  const b = L.applyWeeklyOffChange(a, [5, 6, 7], '2026-06-01');
  assert.equal(b.length, 2);
  assert.deepEqual(b[1].days, [5, 6, 7]);
  assert.deepEqual(L.applyWeeklyOffChange(a, [6, 7], '2026-07-01'), a);
  assert.deepEqual(h, [{ from: '2026-01-01', days: [7] }], 'input is not mutated');
});

test('review: nextReview clears when fine, flags when newly late, keeps decided state when still late', () => {
  assert.equal(L.nextReview({ ...L.emptyReview(), status: 'pending', note: 'x' }, false).status, 'none');
  assert.equal(L.nextReview(null, true).status, 'needs_note');
  assert.equal(L.nextReview({ ...L.emptyReview(), status: 'approved' }, true).status, 'approved');
  assert.equal(L.needsReview({ status: 'pending' }, { status: 'none' }), true);
  assert.equal(L.needsReview({ status: 'approved' }, { status: 'needs_note' }), false);
});

test('ranking: ties share a rank and the next rank skips (1,1,3); excluded are unranked', () => {
  const r = L.rankEmployees([
    { id: 'a', eligible: true, present: 10, late: 0 },
    { id: 'b', eligible: true, present: 10, late: 0 },
    { id: 'c', eligible: true, present: 9, late: 0 },
    { id: 'x', eligible: false, present: 30, late: 0 },
  ]);
  assert.equal(r.get('a').rank, 1);
  assert.equal(r.get('b').rank, 1);
  assert.equal(r.get('c').rank, 3);
  assert.equal(r.get('c').ranked_of, 3);
  assert.deepEqual(r.get('x'), { rank: null, ranked_of: null });
});

test('ranking: fewer late+early breaks a tie on present', () => {
  const r = L.rankEmployees([
    { id: 'a', eligible: true, present: 10, late: 3 },
    { id: 'b', eligible: true, present: 10, late: 1 },
  ]);
  assert.equal(r.get('b').rank, 1);
  assert.equal(r.get('a').rank, 2);
});

const SETTINGS = () => L.normalizeSettings({
  office: OFFICE, radius_m: 100, arrival: '10:00', leave: '19:00', grace_minutes: 15,
  weekly_off_history: [{ from: '2026-01-01', days: [7] }], started_on: '2026-11-01',
});
const rec = (date, extra = {}) => baseRecord('alice', date, extra);

test('summary: zero working days gives null percent and stars and no division error', () => {
  const s = L.buildMonth({ month: '2026-11', now: new Date('2026-11-18T12:00:00+05:30'),
    settings: { ...SETTINGS(), started_on: '2026-11-19' }, holidays: {}, records: {}, joinDate: null }).summary;
  assert.equal(s.working_days, 0);
  assert.equal(s.percent, null);
  assert.equal(s.stars, null);
});

test('summary: a future month is all zeros', () => {
  const { summary, days } = L.buildMonth({ month: '2027-03', now: new Date('2026-11-18T12:00:00+05:30'),
    settings: SETTINGS(), holidays: {}, records: {}, joinDate: null });
  assert.equal(summary.working_days, 0);
  assert.equal(summary.absent, 0);
  assert.ok(days.filter((d) => d.type === 'working').every((d) => d.status === 'upcoming'));
});

test('summary: started_on mid-month excludes earlier days from absences', () => {
  const { summary } = L.buildMonth({ month: '2026-11', now: new Date('2026-11-18T20:00:00+05:30'),
    settings: { ...SETTINGS(), started_on: '2026-11-16' }, holidays: {}, records: {}, joinDate: null });
  // 16 (Mon), 17, 18 (after leave) are working
  assert.equal(summary.working_days, 3);
  assert.equal(summary.absent, 3);
});

test('summary: employee join date later than started_on limits the range', () => {
  const { summary } = L.buildMonth({ month: '2026-11', now: new Date('2026-11-18T20:00:00+05:30'),
    settings: SETTINGS(), holidays: {}, records: {}, joinDate: '2026-11-17' });
  assert.equal(summary.working_days, 2);
});

test('summary: today before leave time is not absent, after leave it is', () => {
  const args = { month: '2026-11', settings: { ...SETTINGS(), started_on: '2026-11-18' }, holidays: {}, records: {}, joinDate: null };
  const before = L.buildMonth({ ...args, now: new Date('2026-11-18T18:59:00+05:30') });
  assert.equal(before.summary.working_days, 0);
  assert.equal(before.summary.absent, 0);
  assert.equal(before.days.find((d) => d.date === '2026-11-18').status, 'upcoming');
  const after = L.buildMonth({ ...args, now: new Date('2026-11-18T19:00:00+05:30') });
  assert.equal(after.summary.absent, 1);
});

test('summary: today with a check-in counts as present even before leave time', () => {
  const s = L.buildMonth({ month: '2026-11', now: new Date('2026-11-18T11:00:00+05:30'),
    settings: { ...SETTINGS(), started_on: '2026-11-18' }, holidays: {},
    records: { '2026-11-18': rec('2026-11-18', { check_out_at: null }) }, joinDate: null }).summary;
  assert.equal(s.present, 1);
  assert.equal(s.percent, 100);
  assert.equal(s.missed_checkout, 0, 'today is not yet a missed check-out');
});

test('summary: extra days on off days never inflate the percentage', () => {
  const s = L.buildMonth({ month: '2026-11', now: new Date('2026-11-23T20:00:00+05:30'),
    settings: { ...SETTINGS(), started_on: '2026-11-22' }, holidays: {},
    records: { '2026-11-22': rec('2026-11-22') }, joinDate: null }).summary;
  assert.equal(s.extra_days, 1);
  assert.equal(s.working_days, 1); // only Monday 23
  assert.equal(s.present, 0);
  assert.equal(s.percent, 0);
});

test('summary: late/early unexcused vs pending vs excused, missed check-out, rounding', () => {
  const records = {
    '2026-11-16': rec('2026-11-16', { late: { ...L.emptyReview(), status: 'needs_note' } }),
    '2026-11-17': rec('2026-11-17', { late: { ...L.emptyReview(), status: 'rejected' }, check_out_at: null }),
    '2026-11-18': rec('2026-11-18', { early: { ...L.emptyReview(), status: 'pending' }, late: { ...L.emptyReview(), status: 'approved' } }),
  };
  const s = L.buildMonth({ month: '2026-11', now: new Date('2026-11-19T11:00:00+05:30'),
    settings: { ...SETTINGS(), started_on: '2026-11-16' }, holidays: {}, records, joinDate: null }).summary;
  assert.equal(s.late, 2);
  assert.equal(s.pending, 1);
  assert.equal(s.excused, 1);
  assert.equal(s.missed_checkout, 1);
  assert.equal(s.working_days, 3); // 19th has no record and it is before leave
  assert.equal(s.percent, 83); // 2 full + 1 half (missed check-out) over 3 days
  assert.equal(s.stars, 4.2);
  const two = L.buildMonth({ month: '2026-11', now: new Date('2026-11-19T20:00:00+05:30'),
    settings: { ...SETTINGS(), started_on: '2026-11-16' }, holidays: {}, records, joinDate: null }).summary;
  assert.equal(two.percent, 63); // 2.5 over 4 days once the 19th is absent
  assert.equal(two.stars, 3.1);
});

test('summary: a holiday is not a working day and removes its absence', () => {
  const base = { month: '2026-11', now: new Date('2026-11-19T20:00:00+05:30'),
    settings: { ...SETTINGS(), started_on: '2026-11-16' }, records: {}, joinDate: null };
  assert.equal(L.buildMonth({ ...base, holidays: {} }).summary.working_days, 4);
  const h = L.buildMonth({ ...base, holidays: { '2026-11-17': 'Diwali' } });
  assert.equal(h.summary.working_days, 3);
  assert.equal(h.days.find((d) => d.date === '2026-11-17').holiday_name, 'Diwali');
});

test('summary: weekly-off change leaves earlier months identical', () => {
  const before = SETTINGS();
  const after = { ...before, weekly_off_history: L.applyWeeklyOffChange(before.weekly_off_history, [6, 7], '2026-11-10') };
  const args = { month: '2026-10', now: new Date('2026-11-19T20:00:00+05:30'), holidays: {}, records: {}, joinDate: null };
  const a = L.buildMonth({ ...args, settings: { ...before, started_on: '2026-10-01' } }).summary;
  const b = L.buildMonth({ ...args, settings: { ...after, started_on: '2026-10-01' } }).summary;
  assert.deepEqual(a, b);
  const nov = L.buildMonth({ ...args, month: '2026-11', settings: { ...after, started_on: '2026-11-01' } });
  assert.equal(nov.days.find((d) => d.date === '2026-11-14').type, 'weekly_off', 'Saturday off from the change date');
  assert.equal(nov.days.find((d) => d.date === '2026-11-07').type, 'working', 'earlier Saturday still working');
});

test('settings validation (pure): every bound and shape', () => {
  const ok = { office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00', grace_minutes: 15, weekly_off: [7] };
  assert.doesNotThrow(() => L.validateSettingsInput(ok));
  const bad = (o) => assert.throws(() => L.validateSettingsInput({ ...ok, ...o }), (e) => e.code === 'invalid_input');
  bad({ radius_m: 9 }); bad({ radius_m: 501 }); bad({ radius_m: 50.5 }); bad({ radius_m: '50' });
  bad({ max_accuracy_m: 4 }); bad({ max_accuracy_m: 101 });
  bad({ grace_minutes: -1 }); bad({ grace_minutes: 61 });
  bad({ office: { lat: 0, lng: 0 } }); bad({ office: { lat: 91, lng: 10 } }); bad({ office: { lat: 10, lng: NaN } });
  bad({ office: { lat: '19', lng: '72' } }); bad({ office: undefined });
  bad({ arrival: '25:00' }); bad({ leave: '10:59' }); bad({ leave: '09:00' });
  bad({ weekly_off: [1, 2, 3, 4, 5, 6, 7] }); bad({ weekly_off: [8] }); bad({ weekly_off: 'sun' });
  assert.doesNotThrow(() => L.validateSettingsInput({ ...ok, leave: '11:00' }), 'exactly 60 minutes is fine');
  assert.doesNotThrow(() => L.validateSettingsInput({ ...ok, office: null }));
  assert.doesNotThrow(() => L.validateSettingsInput({ ...ok, weekly_off: [] }));
});

// ───────────────────────── mark in ─────────────────────────

test('mark in: success inside radius on time creates a clean record with server-computed fields', async () => {
  const env = makeEnv('2026-11-18T09:58:00+05:30');
  const { record, already } = await env.call('attendanceMark', 'alice', env.markData({ ...metersNorth(50) }));
  assert.equal(already, false);
  assert.equal(record.date, '2026-11-18');
  assert.equal(record.check_in_local, '09:58');
  assert.equal(record.late.status, 'none');
  assert.equal(record.late_minutes, 0);
  assert.equal(record.source, 'self');
  assert.ok(Math.abs(record.check_in_geo.distance_m - 50) < 1);
  assert.match(record.check_in_at, /^2026-11-18T04:28:00/);
});

test('mark in: late arrival is flagged needs_note and does not need review yet', async () => {
  const env = makeEnv('2026-11-18T10:15:01+05:30');
  const { record } = await env.markIn('alice');
  assert.equal(record.late.status, 'needs_note');
  assert.equal(record.late_minutes, 16);
  assert.equal(record.needs_review, false);
});

test('mark in: exactly at grace is on time', async () => {
  const env = makeEnv('2026-11-18T10:15:00+05:30');
  const { record } = await env.markIn('alice');
  assert.equal(record.late.status, 'none');
});

test('mark in: double tap returns the existing record unchanged with already:true', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  const first = await env.markIn('alice');
  env.advance(5000);
  const second = await env.markIn('alice');
  assert.equal(second.already, true);
  assert.deepEqual(second.record, first.record);
  assert.equal(env.fake.all('attendance').length, 1);
});

test('mark in: network retry long after the first call still returns the same record', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  const first = await env.markIn('alice');
  env.advance(3 * 3600 * 1000);
  const retry = await env.markIn('alice');
  assert.equal(retry.already, true);
  assert.equal(retry.record.check_in_at, first.record.check_in_at);
});

test('mark in: concurrent calls from one employee create exactly one record', async () => {
  const env = makeEnv();
  const results = await Promise.all([env.markIn('alice'), env.markIn('alice'), env.markIn('alice')]);
  assert.equal(results.filter((r) => !r.already).length, 1);
  assert.equal(env.fake.all('attendance').length, 1);
});

test('mark in: concurrent calls from two employees on one device let only one through', async () => {
  const env = makeEnv();
  const res = await Promise.allSettled([
    env.call('attendanceMark', 'alice', env.markData({ device_id: 'shared' })),
    env.call('attendanceMark', 'bob', env.markData({ device_id: 'shared' })),
  ]);
  assert.equal(res.filter((r) => r.status === 'fulfilled').length, 1);
  const rejected = res.find((r) => r.status === 'rejected');
  assert.equal(rejected.reason.details.code, 'device_in_use');
  assert.equal(env.fake.all('attendance').length, 1);
});

test('mark in: a device already used by another employee today is refused', async () => {
  const env = makeEnv();
  await env.call('attendanceMark', 'alice', env.markData({ device_id: 'shared' }));
  await expectCode(env.call('attendanceMark', 'bob', env.markData({ device_id: 'shared' })), 'device_in_use');
  assert.equal(env.rec('bob', '2026-11-18'), null);
});

test('mark in: the same device is fine for another employee the next day', async () => {
  const env = makeEnv();
  await env.call('attendanceMark', 'alice', env.markData({ device_id: 'shared' }));
  env.set('2026-11-19T10:00:00+05:30');
  const r = await env.call('attendanceMark', 'bob', env.markData({ device_id: 'shared' }));
  assert.equal(r.already, false);
});

test('mark in: outside the radius reports distance and radius', async () => {
  const env = makeEnv();
  const e = await env.markIn('alice', { ...metersNorth(150) }).catch((x) => x);
  assert.equal(e.details.code, 'outside_radius');
  assert.equal(e.details.radius_m, 100);
  assert.ok(Math.abs(e.details.distance_m - 150) < 1);
});

test('mark in: 99 m is inside and 101 m is outside a 100 m radius', async () => {
  const env = makeEnv();
  assert.equal((await env.markIn('alice', { ...metersNorth(99) })).already, false);
  await expectCode(env.markIn('bob', { ...metersNorth(101) }), 'outside_radius');
});

test('mark in: bad, NaN, string and out-of-range coordinates are invalid_input', async () => {
  const env = makeEnv();
  for (const bad of [{ lat: NaN }, { lat: '19.07' }, { lng: null }, { lat: 91 }, { lng: -181 }, { lat: Infinity }, { lat: undefined }]) {
    await expectCode(env.markIn('alice', bad), 'invalid_input');
  }
  assert.equal(env.fake.all('attendance').length, 0);
});

test('mark in: malformed input fields are invalid_input', async () => {
  const env = makeEnv();
  await expectCode(env.call('attendanceMark', 'alice', env.markData({ action: 'sideways' })), 'invalid_input');
  await expectCode(env.markIn('alice', { accuracy_m: 'ten' }), 'invalid_input');
  await expectCode(env.markIn('alice', { accuracy_m: -1 }), 'invalid_input');
  await expectCode(env.markIn('alice', { is_mocked: 'false' }), 'invalid_input');
  await expectCode(env.markIn('alice', { position_age_ms: NaN }), 'invalid_input');
  await expectCode(env.markIn('alice', { device_id: '' }), 'invalid_input');
  await expectCode(env.markIn('alice', { device_id: 'a/b' }), 'invalid_input');
  await expectCode(env.call('attendanceMark', 'alice', 'not an object'), 'invalid_input');
});

test('mark in: poor GPS accuracy refused above the limit, allowed at the limit', async () => {
  const env = makeEnv();
  const e = await env.markIn('alice', { accuracy_m: 25.01 }).catch((x) => x);
  assert.equal(e.details.code, 'poor_accuracy');
  assert.equal(e.details.accuracy_m, 25.01);
  assert.equal((await env.markIn('alice', { accuracy_m: 25 })).already, false);
});

test('mark in: a mocked location is refused', async () => {
  const env = makeEnv();
  await expectCode(env.markIn('alice', { is_mocked: true }), 'mock_location');
});

test('mark in: stale or impossible position age is refused, boundaries 0 and 120000 allowed', async () => {
  const env = makeEnv();
  await expectCode(env.markIn('alice', { position_age_ms: 120001 }), 'stale_location');
  await expectCode(env.markIn('alice', { position_age_ms: -1 }), 'stale_location');
  assert.equal((await env.markIn('alice', { position_age_ms: 120000 })).already, false);
  assert.equal((await env.markIn('bob', { position_age_ms: 0 })).already, false);
});

test('mark in: missing, false, or non-boolean biometric is refused', async () => {
  const env = makeEnv();
  await expectCode(env.markIn('alice', { biometric_passed: false }), 'biometric_required');
  await expectCode(env.markIn('alice', { biometric_passed: undefined }), 'biometric_required');
  await expectCode(env.markIn('alice', { biometric_passed: 'true' }), 'biometric_required');
  await expectCode(env.markIn('alice', { biometric_passed: 1 }), 'biometric_required');
  assert.equal(env.fake.all('attendance').length, 0);
});

test('mark in: refused when the office is not configured', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30', { configured: false });
  await expectCode(env.markIn('alice'), 'not_configured');
});

test('mark in: inactive, restricted, unknown and signed-out users are refused', async () => {
  const env = makeEnv();
  await expectCode(env.markIn('restricted'), 'inactive');
  await expectCode(env.markIn('ghost'), 'inactive');
  await expectCode(env.markIn(null), 'unauthenticated');
  env.emp('pending1', { status: 'PENDING' });
  await expectCode(env.markIn('pending1'), 'inactive');
});

test('mark in: after leave time on a working day is shift_over, at leave time too', async () => {
  const env = makeEnv('2026-11-18T18:59:59+05:30');
  assert.equal((await env.markIn('alice')).already, false);
  env.set('2026-11-18T19:00:00+05:30');
  await expectCode(env.markIn('bob'), 'shift_over');
});

test('mark in: an off day (Sunday) can be marked late in the evening with no lateness', async () => {
  const env = makeEnv('2026-11-22T21:30:00+05:30');
  const { record } = await env.markIn('alice');
  assert.equal(record.late.status, 'none');
  assert.equal(record.late_minutes, 0);
  env.advance(2 * 3600 * 1000);
  const out = await env.markOut('alice');
  assert.equal(out.record.early.status, 'none');
});

test('mark in: a declared holiday has no lateness and no shift_over', async () => {
  const env = makeEnv('2026-11-18T20:00:00+05:30');
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'Festival' });
  const { record } = await env.markIn('alice');
  assert.equal(record.late.status, 'none');
});

test('mark in: the record keeps a shift snapshot, later shift changes do not alter it', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  await env.call('attendanceSaveSettings', 'admin1', {
    office: OFFICE, radius_m: 100, max_accuracy_m: 25, arrival: '09:00', leave: '17:00', grace_minutes: 0, weekly_off: [7],
  });
  assert.deepEqual(env.rec('alice', '2026-11-18').shift, { arrival: '10:00', leave: '19:00', grace_minutes: 15, full_day_minutes: 360 });
  env.set('2026-11-18T18:00:00+05:30');
  const out = await env.markOut('alice');
  // 18:00 is early against the 19:00 snapshot; it would not be against the new 17:00 shift
  assert.equal(out.record.early.status, 'needs_note');
});

// ───────────────────────── mark out ─────────────────────────

test('mark out: without a check-in is not_checked_in', async () => {
  const env = makeEnv();
  await expectCode(env.markOut('alice'), 'not_checked_in');
});

test('mark out: inside 60 seconds is too_soon, exactly 60 seconds is fine', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  env.advance(59000);
  await expectCode(env.markOut('alice'), 'too_soon');
  env.advance(1000);
  assert.equal((await env.markOut('alice')).record.check_out_local, '10:01');
});

test('mark out: on time leaves no early flag and records worked minutes', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  env.set('2026-11-18T18:45:00+05:30');
  const { record } = await env.markOut('alice');
  assert.equal(record.early.status, 'none');
  assert.equal(record.worked_minutes, 525);
});

test('mark out: leaving early is flagged needs_note with ceil minutes', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  env.set('2026-11-18T18:44:59+05:30');
  const { record } = await env.markOut('alice');
  assert.equal(record.early.status, 'needs_note');
  assert.equal(record.early_minutes, 16);
});

test('mark out: repeating check-out is allowed and the last one wins', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  env.set('2026-11-18T12:00:00+05:30');
  await env.markOut('alice');
  env.set('2026-11-18T19:30:00+05:30');
  const { record } = await env.markOut('alice');
  assert.equal(record.check_out_local, '19:30');
  assert.equal(record.early.status, 'none', 'no longer early once the later check-out recomputes');
  assert.equal(record.early_minutes, 0);
});

test('mark out: repeat that is still early keeps a pending note; not early clears it', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  env.set('2026-11-18T12:00:00+05:30');
  await env.markOut('alice');
  await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'early', note: 'Doctor visit' });
  env.set('2026-11-18T13:00:00+05:30');
  const still = await env.markOut('alice');
  assert.equal(still.record.early.status, 'pending');
  assert.equal(still.record.early.note, 'Doctor visit');
  assert.equal(still.record.needs_review, true);
  env.set('2026-11-18T19:00:00+05:30');
  const cleared = await env.markOut('alice');
  assert.equal(cleared.record.early.status, 'none');
  assert.equal(cleared.record.early.note, null);
  assert.equal(cleared.record.needs_review, false);
});

test('mark out: refused with locked_by_admin after an admin edit', async () => {
  const env = makeEnv('2026-11-18T12:00:00+05:30');
  await env.markIn('alice');
  await env.call('attendanceAdminEdit', 'admin1', {
    employee_id: 'alice', date: '2026-11-18', check_in: '10:00', check_out: null, reason: 'Fixing time',
  });
  env.advance(2 * 3600 * 1000);
  await expectCode(env.markOut('alice'), 'locked_by_admin');
});

test('mark out: refused with already_decided once the early item is approved or rejected', async () => {
  for (const decision of ['approved', 'rejected']) {
    const env = makeEnv('2026-11-18T10:00:00+05:30');
    await env.markIn('alice');
    env.set('2026-11-18T12:00:00+05:30');
    await env.markOut('alice');
    await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'early', note: 'Family event' });
    await env.call('attendanceReview', 'admin1', { employee_id: 'alice', date: '2026-11-18', kind: 'early', decision });
    env.advance(3600 * 1000);
    await expectCode(env.markOut('alice'), 'already_decided');
  }
});

test('mark out: after midnight is a new day so not_checked_in, and the old day stays a missed check-out', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  env.set('2026-11-19T00:00:30+05:30');
  await expectCode(env.markOut('alice'), 'not_checked_in');
  assert.equal(env.rec('alice', '2026-11-18').check_out_at, null);
  const { summary } = await env.call('attendanceMonth', 'alice', { month: '2026-11' });
  assert.equal(summary.missed_checkout, 1);
  assert.equal(summary.present, 1);
});

test('mark out: applies the same location, biometric, mock and device checks', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  env.advance(120000);
  await expectCode(env.markOut('alice', { ...metersNorth(500) }), 'outside_radius');
  await expectCode(env.markOut('alice', { is_mocked: true }), 'mock_location');
  await expectCode(env.markOut('alice', { biometric_passed: false }), 'biometric_required');
  await env.markIn('bob', { device_id: 'bobs-phone' }).catch(() => {});
  await expectCode(env.markOut('alice', { device_id: 'bobs-phone' }), 'device_in_use');
});

// ───────────────────────── notes ─────────────────────────

const lateAlice = async (env) => {
  env.set('2026-11-18T10:30:00+05:30');
  await env.markIn('alice');
};

test('note: owner submits a note, status moves to pending and needs_review is set', async () => {
  const env = makeEnv();
  await lateAlice(env);
  const { record } = await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'late', note: '  Bus broke down  ' });
  assert.equal(record.late.status, 'pending');
  assert.equal(record.late.note, 'Bus broke down');
  assert.equal(record.needs_review, true);
});

test('note: editable while pending', async () => {
  const env = makeEnv();
  await lateAlice(env);
  await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'late', note: 'First reason' });
  const { record } = await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'late', note: 'Better reason' });
  assert.equal(record.late.note, 'Better reason');
  assert.equal(record.late.status, 'pending');
});

test('note: length and whitespace validation (2 chars, 3 chars, 500, 501, blanks, non-string)', async () => {
  const env = makeEnv();
  await lateAlice(env);
  const send = (note) => env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'late', note });
  await expectCode(send('ab'), 'invalid_input');
  await expectCode(send('   a   '), 'invalid_input');
  await expectCode(send('      '), 'invalid_input');
  await expectCode(send(''), 'invalid_input');
  await expectCode(send(12345), 'invalid_input');
  await expectCode(send(null), 'invalid_input');
  await expectCode(send('x'.repeat(501)), 'invalid_input');
  assert.equal((await send('x'.repeat(500))).record.late.note.length, 500);
});

test('note: bad date or kind is invalid_input', async () => {
  const env = makeEnv();
  await lateAlice(env);
  await expectCode(env.call('attendanceSubmitNote', 'alice', { date: '2026-02-30', kind: 'late', note: 'valid note' }), 'invalid_input');
  await expectCode(env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'both', note: 'valid note' }), 'invalid_input');
});

test('note: not allowed when the item needs no note (on time, or not early)', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  await expectCode(env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'late', note: 'no need' }), 'note_not_allowed');
  await expectCode(env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'early', note: 'no need' }), 'note_not_allowed');
});

test('note: another employee cannot add a note to someone else\'s record', async () => {
  const env = makeEnv();
  await lateAlice(env);
  await expectCode(env.call('attendanceSubmitNote', 'bob', { date: '2026-11-18', kind: 'late', note: 'not mine' }), 'note_not_allowed');
  assert.equal(env.rec('alice', '2026-11-18').late.status, 'needs_note');
  await expectCode(env.call('attendanceSubmitNote', 'bob', { employee_id: 'alice', date: '2026-11-18', kind: 'late', note: 'sneaky' }), 'note_not_allowed');
});

test('note: never after a decision', async () => {
  const env = makeEnv();
  await lateAlice(env);
  await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'late', note: 'Traffic jam' });
  await env.call('attendanceReview', 'admin1', { employee_id: 'alice', date: '2026-11-18', kind: 'late', decision: 'rejected' });
  await expectCode(env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'late', note: 'Please reconsider' }), 'note_not_allowed');
});

// ───────────────────────── review ─────────────────────────

const pendingLate = async (env, uid = 'alice') => {
  env.set('2026-11-18T10:30:00+05:30');
  await env.markIn(uid);
  await env.call('attendanceSubmitNote', uid, { date: '2026-11-18', kind: 'late', note: 'Traffic jam' });
};

test('review: admin approves, decision metadata recorded, needs_review cleared, audit written', async () => {
  const env = makeEnv();
  await pendingLate(env);
  const { record } = await env.call('attendanceReview', 'admin1', {
    employee_id: 'alice', date: '2026-11-18', kind: 'late', decision: 'approved', comment: ' ok ',
  });
  assert.equal(record.late.status, 'approved');
  assert.equal(record.late.decided_by, 'admin1');
  assert.equal(record.late.decided_by_name, 'admin1');
  assert.equal(record.late.comment, 'ok');
  assert.equal(record.needs_review, false);
  assert.equal(env.fake.all('attendance_audit').filter((a) => a.action === 'review_approved').length, 1);
});

test('review: a second decision, even from another admin, is not_pending', async () => {
  const env = makeEnv();
  await pendingLate(env);
  const args = { employee_id: 'alice', date: '2026-11-18', kind: 'late', decision: 'approved' };
  await env.call('attendanceReview', 'admin1', args);
  await expectCode(env.call('attendanceReview', 'admin2', { ...args, decision: 'rejected' }), 'not_pending');
  assert.equal(env.rec('alice', '2026-11-18').late.status, 'approved');
});

test('review: two admins deciding concurrently, exactly one wins', async () => {
  const env = makeEnv();
  await pendingLate(env);
  const args = { employee_id: 'alice', date: '2026-11-18', kind: 'late' };
  const res = await Promise.allSettled([
    env.call('attendanceReview', 'admin1', { ...args, decision: 'approved' }),
    env.call('attendanceReview', 'admin2', { ...args, decision: 'rejected' }),
  ]);
  assert.equal(res.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(res.find((r) => r.status === 'rejected').reason.details.code, 'not_pending');
});

test('review: items that are not pending (needs_note, none) cannot be decided', async () => {
  const env = makeEnv();
  env.set('2026-11-18T10:30:00+05:30');
  await env.markIn('alice');
  const args = { employee_id: 'alice', date: '2026-11-18', decision: 'approved' };
  await expectCode(env.call('attendanceReview', 'admin1', { ...args, kind: 'late' }), 'not_pending');
  await expectCode(env.call('attendanceReview', 'admin1', { ...args, kind: 'early' }), 'not_pending');
  await expectCode(env.call('attendanceReview', 'admin1', { ...args, employee_id: 'bob', kind: 'late' }), 'not_pending');
});

test('review: an admin cannot decide their own item while another active admin exists', async () => {
  const env = makeEnv();
  await pendingLate(env, 'admin1');
  await expectCode(env.call('attendanceReview', 'admin1', {
    employee_id: 'admin1', date: '2026-11-18', kind: 'late', decision: 'approved',
  }), 'self_review');
  // the other admin can
  const { record } = await env.call('attendanceReview', 'admin2', {
    employee_id: 'admin1', date: '2026-11-18', kind: 'late', decision: 'approved',
  });
  assert.equal(record.late.status, 'approved');
});

test('review: the only active admin may decide their own item', async () => {
  const env = makeEnv();
  env.emp('admin2', { role: 'ADMIN', status: 'RESTRICTED' });
  await pendingLate(env, 'admin1');
  const { record } = await env.call('attendanceReview', 'admin1', {
    employee_id: 'admin1', date: '2026-11-18', kind: 'late', decision: 'rejected',
  });
  assert.equal(record.late.status, 'rejected');
});

test('review: bad decision, bad comment, bad kind are invalid_input', async () => {
  const env = makeEnv();
  await pendingLate(env);
  const base = { employee_id: 'alice', date: '2026-11-18', kind: 'late', decision: 'approved' };
  await expectCode(env.call('attendanceReview', 'admin1', { ...base, decision: 'maybe' }), 'invalid_input');
  await expectCode(env.call('attendanceReview', 'admin1', { ...base, comment: 'x'.repeat(301) }), 'invalid_input');
  await expectCode(env.call('attendanceReview', 'admin1', { ...base, comment: 42 }), 'invalid_input');
  await expectCode(env.call('attendanceReview', 'admin1', { ...base, kind: 'x' }), 'invalid_input');
  await expectCode(env.call('attendanceReview', 'admin1', { ...base, employee_id: '' }), 'invalid_input');
  assert.equal((await env.call('attendanceReview', 'admin1', { ...base, comment: 'x'.repeat(300) })).record.late.status, 'approved');
});

// ───────────────────────── approvals list ─────────────────────────

test('approvals: lists pending items newest first and nothing that is merely needs_note', async () => {
  const env = makeEnv();
  env.set('2026-11-17T10:30:00+05:30');
  await env.markIn('alice');
  await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-17', kind: 'late', note: 'Older reason' });
  env.set('2026-11-18T10:40:00+05:30');
  await env.markIn('bob');
  await env.call('attendanceSubmitNote', 'bob', { date: '2026-11-18', kind: 'late', note: 'Newer reason' });
  env.set('2026-11-18T10:50:00+05:30');
  await env.markIn('carol'); // late, no note yet
  const { items } = await env.call('attendanceListApprovals', 'admin1', {});
  assert.deepEqual(items.map((i) => [i.employee_id, i.date]), [['bob', '2026-11-18'], ['alice', '2026-11-17']]);
  assert.deepEqual(items[0], {
    employee_id: 'bob', employee_name: 'bob', date: '2026-11-18', kind: 'late', minutes: 40,
    note: 'Newer reason', expected: '10:00', actual: '10:40',
  });
});

test('approvals: dates that are now holidays or weekly offs are excluded', async () => {
  const env = makeEnv();
  await pendingLate(env);
  assert.equal((await env.call('attendanceListApprovals', 'admin1', {})).items.length, 1);
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'Surprise holiday' });
  assert.equal((await env.call('attendanceListApprovals', 'admin1', {})).items.length, 0);
  await env.call('attendanceRemoveHoliday', 'admin1', { date: '2026-11-18' });
  assert.equal((await env.call('attendanceListApprovals', 'admin1', {})).items.length, 1);
});

test('approvals: a record with both late and early pending yields two items', async () => {
  const env = makeEnv();
  await pendingLate(env);
  env.set('2026-11-18T12:00:00+05:30');
  await env.markOut('alice');
  await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'early', note: 'Left for clinic' });
  const { items } = await env.call('attendanceListApprovals', 'admin1', {});
  assert.deepEqual(items.map((i) => i.kind).sort(), ['early', 'late']);
  const early = items.find((i) => i.kind === 'early');
  assert.equal(early.expected, '19:00');
  assert.equal(early.actual, '12:00');
  assert.equal(early.minutes, 420);
});

// ───────────────────────── admin edit ─────────────────────────

const edit = (env, o = {}, uid = 'admin1') => env.call('attendanceAdminEdit', uid, {
  employee_id: 'alice', date: '2026-11-17', check_in: '09:30', check_out: '19:00', reason: 'Forgot to mark', ...o,
});

test('admin edit: adds a missing record with admin source, snapshot, locals and audit', async () => {
  const env = makeEnv();
  const { record } = await edit(env);
  assert.equal(record.source, 'admin');
  assert.equal(record.admin_edited, true);
  assert.equal(record.check_in_local, '09:30');
  assert.equal(record.worked_minutes, 570);
  assert.equal(record.late.status, 'none');
  assert.deepEqual(record.shift, { arrival: '10:00', leave: '19:00', grace_minutes: 15, full_day_minutes: 360 });
  const audit = env.fake.all('attendance_audit');
  assert.equal(audit.length, 1);
  assert.equal(audit[0].before, null);
  assert.equal(audit[0].reason, 'Forgot to mark');
  assert.equal(audit[0].by, 'admin1');
});

test('admin edit: changing a self record makes it mixed and newly late becomes needs_note', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.markIn('alice');
  env.set('2026-11-18T12:00:00+05:30');
  const { record } = await edit(env, { date: '2026-11-18', check_in: '10:45', check_out: null });
  assert.equal(record.source, 'mixed');
  assert.equal(record.late.status, 'needs_note');
  assert.equal(record.late_minutes, 45);
});

test('admin edit: no longer late resets the status to none and drops the note', async () => {
  const env = makeEnv();
  await pendingLate(env);
  const { record } = await edit(env, { date: '2026-11-18', check_in: '10:05', check_out: null });
  assert.equal(record.late.status, 'none');
  assert.equal(record.late.note, null);
  assert.equal(record.needs_review, false);
});

test('admin edit: still late keeps the existing pending status and note', async () => {
  const env = makeEnv();
  await pendingLate(env);
  env.set('2026-11-18T12:00:00+05:30');
  const { record } = await edit(env, { date: '2026-11-18', check_in: '10:50', check_out: null });
  assert.equal(record.late.status, 'pending');
  assert.equal(record.late.note, 'Traffic jam');
  assert.equal(record.late_minutes, 50);
  assert.equal(record.needs_review, true);
});

test('admin edit: unchanged check-in time keeps the original second so grace stays exact', async () => {
  const env = makeEnv('2026-11-18T10:15:00+05:30');
  await env.markIn('alice');
  const before = env.rec('alice', '2026-11-18').check_in_at.toMillis();
  env.set('2026-11-18T19:30:00+05:30');
  await edit(env, { date: '2026-11-18', check_in: '10:15', check_out: '18:00' });
  assert.equal(env.rec('alice', '2026-11-18').check_in_at.toMillis(), before);
  assert.equal(env.rec('alice', '2026-11-18').late.status, 'none');
});

test('admin edit: adding an early check-out flags early, moving it later clears it', async () => {
  const env = makeEnv();
  const a = await edit(env, { check_in: '10:00', check_out: '15:00' });
  assert.equal(a.record.early.status, 'needs_note');
  assert.equal(a.record.early_minutes, 240);
  const b = await edit(env, { check_in: '10:00', check_out: '19:00' });
  assert.equal(b.record.early.status, 'none');
  assert.equal(b.record.early_minutes, 0);
});

test('admin edit: both times null removes the record and the audit keeps what it was', async () => {
  const env = makeEnv();
  await edit(env);
  const { record } = await edit(env, { check_in: null, check_out: null, reason: 'Entered by mistake' });
  assert.equal(record, null);
  assert.equal(env.rec('alice', '2026-11-17'), null);
  const audit = env.fake.all('attendance_audit').find((a) => a.action === 'admin_delete');
  assert.equal(audit.before.check_in_local, '09:30');
  assert.equal(audit.after, null);
});

test('admin edit: removing a record that does not exist is harmless', async () => {
  const env = makeEnv();
  const { record } = await edit(env, { check_in: null, check_out: null });
  assert.equal(record, null);
});

test('admin edit: check-out before or equal to check-in is rejected', async () => {
  const env = makeEnv();
  await expectCode(edit(env, { check_in: '12:00', check_out: '11:59' }), 'invalid_input');
  await expectCode(edit(env, { check_in: '12:00', check_out: '12:00' }), 'invalid_input');
  assert.equal(env.rec('alice', '2026-11-17'), null);
});

test('admin edit: check-out without a check-in is rejected', async () => {
  const env = makeEnv();
  await expectCode(edit(env, { check_in: null, check_out: '18:00' }), 'invalid_input');
  await expectCode(edit(env, { check_in: undefined, check_out: '18:00' }), 'invalid_input');
});

test('admin edit: future dates and future times today are rejected, past times today allowed', async () => {
  const env = makeEnv('2026-11-18T12:00:00+05:30');
  await expectCode(edit(env, { date: '2026-11-19' }), 'invalid_input');
  await expectCode(edit(env, { date: '2026-11-18', check_in: '12:01', check_out: null }), 'invalid_input');
  await expectCode(edit(env, { date: '2026-11-18', check_in: '09:00', check_out: '12:01' }), 'invalid_input');
  assert.ok((await edit(env, { date: '2026-11-18', check_in: '12:00', check_out: null })).record);
});

test('admin edit: reason is required and 3 to 300 characters', async () => {
  const env = makeEnv();
  await expectCode(edit(env, { reason: undefined }), 'invalid_input');
  await expectCode(edit(env, { reason: '  ab ' }), 'invalid_input');
  await expectCode(edit(env, { reason: 'x'.repeat(301) }), 'invalid_input');
  await expectCode(edit(env, { reason: 7 }), 'invalid_input');
  assert.ok((await edit(env, { reason: 'x'.repeat(300) })).record);
});

test('admin edit: malformed date or times are rejected', async () => {
  const env = makeEnv();
  await expectCode(edit(env, { date: '2026-11-31' }), 'invalid_input');
  await expectCode(edit(env, { check_in: '9:30' }), 'invalid_input');
  await expectCode(edit(env, { check_in: '24:00', check_out: null }), 'invalid_input');
  await expectCode(edit(env, { check_in: 930 }), 'invalid_input');
  await expectCode(edit(env, { employee_id: '' }), 'invalid_input');
  await expectCode(edit(env, { employee_id: 'a/b' }), 'invalid_input');
});

test('admin edit: unknown employee is rejected and nothing is written', async () => {
  const env = makeEnv();
  await expectCode(edit(env, { employee_id: 'nobody' }), 'employee_not_found');
  assert.equal(env.fake.all('attendance').length, 0);
  assert.equal(env.fake.all('attendance_audit').length, 0);
});

test('admin edit: on an off day records no lateness', async () => {
  const env = makeEnv();
  const { record } = await edit(env, { date: '2026-11-15', check_in: '14:00', check_out: '15:00' });
  assert.equal(record.late.status, 'none');
  assert.equal(record.early.status, 'none');
});

test('admin edit: an existing record keeps its original shift snapshot', async () => {
  const env = makeEnv();
  await edit(env);
  await env.call('attendanceSaveSettings', 'admin1', {
    office: OFFICE, radius_m: 100, max_accuracy_m: 25, arrival: '08:00', leave: '16:00', grace_minutes: 5, weekly_off: [7],
  });
  const { record } = await edit(env, { check_in: '09:00', check_out: '18:00' });
  assert.deepEqual(record.shift, { arrival: '10:00', leave: '19:00', grace_minutes: 15, full_day_minutes: 360 });
  assert.equal(record.late.status, 'none');
});

// ───────────────────────── holidays ─────────────────────────

test('holiday: declared after records exist keeps the record but the day becomes off with no lateness counted', async () => {
  const env = makeEnv();
  await pendingLate(env);
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'Declared later' });
  assert.ok(env.rec('alice', '2026-11-18'));
  const { summary, days } = await env.call('attendanceMonth', 'alice', { month: '2026-11' });
  const day = days.find((d) => d.date === '2026-11-18');
  assert.equal(day.type, 'holiday');
  assert.equal(day.status, 'present');
  assert.equal(summary.extra_days, 1);
  assert.equal(summary.pending, 0, 'a holiday late request is not counted');
  assert.equal(summary.late, 0);
});

test('holiday: removed again, the day is a working day and the late item counts as pending', async () => {
  const env = makeEnv();
  await pendingLate(env);
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'Declared later' });
  await env.call('attendanceRemoveHoliday', 'admin1', { date: '2026-11-18' });
  const { summary } = await env.call('attendanceMonth', 'alice', { month: '2026-11' });
  assert.equal(summary.pending, 1);
  assert.equal(summary.extra_days, 0);
});

test('holiday: past holidays are allowed, setting again renames, list is by year and sorted', async () => {
  const env = makeEnv();
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-03-04', name: 'Holi' });
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-01-26', name: 'Republic Day' });
  await env.call('attendanceSetHoliday', 'admin1', { date: '2027-01-26', name: 'Next year' });
  await env.call('attendanceSetHoliday', 'admin2', { date: '2026-03-04', name: 'Holi (renamed)' });
  const { holidays } = await env.call('attendanceListHolidays', 'alice', { year: 2026 });
  assert.deepEqual(holidays, [{ date: '2026-01-26', name: 'Republic Day' }, { date: '2026-03-04', name: 'Holi (renamed)' }]);
  assert.equal(env.fake.get('attendance_holidays', '2026-03-04').created_by, 'admin1', 'rename keeps the creator');
});

test('holiday: validation of date, name length and year', async () => {
  const env = makeEnv();
  await expectCode(env.call('attendanceSetHoliday', 'admin1', { date: '2026-02-30', name: 'Bad' }), 'invalid_input');
  await expectCode(env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'x' }), 'invalid_input');
  await expectCode(env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: ' y ' }), 'invalid_input');
  await expectCode(env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'n'.repeat(61) }), 'invalid_input');
  await expectCode(env.call('attendanceRemoveHoliday', 'admin1', { date: 'tomorrow' }), 'invalid_input');
  await expectCode(env.call('attendanceListHolidays', 'alice', { year: '2026' }), 'invalid_input');
  await expectCode(env.call('attendanceListHolidays', 'alice', { year: 1999 }), 'invalid_input');
  assert.equal(env.fake.all('attendance_holidays').length, 0);
});

test('holiday: every set and remove is audited, removing a missing one is a no-op', async () => {
  const env = makeEnv();
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'Fest' });
  await env.call('attendanceRemoveHoliday', 'admin1', { date: '2026-11-18' });
  assert.deepEqual((await env.call('attendanceRemoveHoliday', 'admin1', { date: '2026-11-18' })), { removed: false });
  assert.deepEqual(env.fake.all('attendance_audit').map((a) => a.action).sort(), ['holiday_remove', 'holiday_set']);
});

// ───────────────────────── settings ─────────────────────────

const settingsInput = (o = {}) => ({
  office: OFFICE, radius_m: 100, max_accuracy_m: 25, arrival: '10:00', leave: '19:00', grace_minutes: 15, weekly_off: [7], ...o,
});

test('settings: first save sets started_on to today and it never changes afterwards', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30', { configured: false });
  const first = (await env.call('attendanceSaveSettings', 'admin1', settingsInput())).settings;
  assert.equal(first.started_on, '2026-11-18');
  env.set('2026-12-05T10:00:00+05:30');
  const second = (await env.call('attendanceSaveSettings', 'admin1', settingsInput({ radius_m: 200 }))).settings;
  assert.equal(second.started_on, '2026-11-18');
  assert.equal(second.radius_m, 200);
});

test('settings: invalid values are rejected without touching the stored config', async () => {
  const env = makeEnv();
  const before = JSON.stringify(env.fake.get('attendance_settings', 'config'));
  for (const bad of [
    { radius_m: 5 }, { office: { lat: 0, lng: 0 } }, { leave: '10:30' }, { weekly_off: [1, 2, 3, 4, 5, 6, 7] },
    { grace_minutes: 90 }, { max_accuracy_m: 1 }, { office: { lat: NaN, lng: 1 } },
  ]) {
    await expectCode(env.call('attendanceSaveSettings', 'admin1', settingsInput(bad)), 'invalid_input');
  }
  assert.equal(JSON.stringify(env.fake.get('attendance_settings', 'config')), before);
  assert.equal(env.fake.all('attendance_audit').length, 0);
});

test('settings: weekly-off change appends today, same-day change replaces, unchanged adds nothing', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30');
  await env.call('attendanceSaveSettings', 'admin1', settingsInput({ weekly_off: [6, 7] }));
  let h = env.fake.get('attendance_settings', 'config').weekly_off_history;
  assert.deepEqual(h, [{ from: '2026-01-01', days: [7] }, { from: '2026-11-18', days: [6, 7] }]);
  await env.call('attendanceSaveSettings', 'admin1', settingsInput({ weekly_off: [5, 6, 7] }));
  h = env.fake.get('attendance_settings', 'config').weekly_off_history;
  assert.equal(h.length, 2);
  assert.deepEqual(h[1], { from: '2026-11-18', days: [5, 6, 7] });
  await env.call('attendanceSaveSettings', 'admin1', settingsInput({ weekly_off: [7, 6, 5] }));
  assert.equal(env.fake.get('attendance_settings', 'config').weekly_off_history.length, 2);
});

test('settings: changing weekly off today does not alter a month already closed', async () => {
  const env = makeEnv('2026-11-19T20:00:00+05:30');
  const before = (await env.call('attendanceMonth', 'alice', { month: '2026-10' })).summary;
  await env.call('attendanceSaveSettings', 'admin1', settingsInput({ weekly_off: [6, 7] }));
  const after = (await env.call('attendanceMonth', 'alice', { month: '2026-10' })).summary;
  assert.deepEqual(after, before);
  assert.equal(before.working_days, 27, 'October 2026 has 31 days and 4 Sundays');
});

test('settings: office change never touches existing records', async () => {
  const env = makeEnv();
  await env.markIn('alice');
  const before = JSON.stringify(env.rec('alice', '2026-11-18'));
  await env.call('attendanceSaveSettings', 'admin1', settingsInput({ office: { lat: 12.9, lng: 77.6 } }));
  assert.equal(JSON.stringify(env.rec('alice', '2026-11-18')), before);
});

test('settings: office can be cleared, after which marking is not_configured', async () => {
  const env = makeEnv();
  await env.call('attendanceSaveSettings', 'admin1', settingsInput({ office: null }));
  await expectCode(env.markIn('alice'), 'not_configured');
  const today = await env.call('attendanceGetToday', 'alice', {});
  assert.equal(today.configured, false);
});

test('settings: get returns defaults when never saved and ISO timestamps after saving', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30', { configured: false });
  const d = (await env.call('attendanceGetSettings', 'admin1', {})).settings;
  assert.equal(d.radius_m, 10);
  assert.equal(d.arrival, '10:00');
  assert.equal(d.office, null);
  assert.deepEqual(d.weekly_off, [7]);
  const s = (await env.call('attendanceSaveSettings', 'admin1', settingsInput())).settings;
  assert.match(s.updated_at, /^2026-11-18T/);
  assert.equal(s.updated_by, 'admin1');
});

// ───────────────────────── authorisation ─────────────────────────

test('authorisation: every admin callable refuses a normal employee and signed-out callers, with no side effects', async () => {
  const env = makeEnv();
  await pendingLate(env);
  const snapshot = JSON.stringify(env.fake.all('attendance'));
  const calls = {
    attendanceTeamDay: { date: '2026-11-18' },
    attendanceTeamMonth: { month: '2026-11' },
    attendanceListApprovals: {},
    attendanceReview: { employee_id: 'alice', date: '2026-11-18', kind: 'late', decision: 'approved' },
    attendanceAdminEdit: { employee_id: 'alice', date: '2026-11-17', check_in: '09:00', check_out: null, reason: 'trying' },
    attendanceGetSettings: {},
    attendanceSaveSettings: settingsInput(),
    attendanceSetHoliday: { date: '2026-11-20', name: 'Mine' },
    attendanceRemoveHoliday: { date: '2026-11-20' },
  };
  for (const [name, data] of Object.entries(calls)) {
    await expectCode(env.call(name, 'bob', data), 'admin_only');
    await expectCode(env.call(name, null, data), 'unauthenticated');
    await expectCode(env.call(name, 'restricted', data), 'inactive');
  }
  assert.equal(JSON.stringify(env.fake.all('attendance')), snapshot);
  assert.equal(env.fake.all('attendance_holidays').length, 0);
  assert.equal(env.fake.all('attendance_audit').length, 0);
});

test('authorisation: errors surface as HttpsError with a human message and a details.code', async () => {
  const env = makeEnv();
  const e = await env.markIn('alice', { is_mocked: true }).catch((x) => x);
  assert.equal(e.code, 'failed-precondition');
  assert.equal(e.details.code, 'mock_location');
  assert.ok(e.message.length > 10);
  const d = await env.call('attendanceTeamDay', 'bob', { date: '2026-11-18' }).catch((x) => x);
  assert.equal(d.code, 'permission-denied');
});

test('authorisation: restricted users cannot use the employee callables either', async () => {
  const env = makeEnv();
  for (const [name, data] of [
    ['attendanceGetToday', {}], ['attendanceMonth', { month: '2026-11' }],
    ['attendanceSubmitNote', { date: '2026-11-18', kind: 'late', note: 'abc' }], ['attendanceListHolidays', { year: 2026 }],
  ]) {
    await expectCode(env.call(name, 'restricted', data), 'inactive');
  }
});

test('month: a normal employee cannot read another employee\'s month, an admin can', async () => {
  const env = makeEnv();
  await env.markIn('bob');
  await expectCode(env.call('attendanceMonth', 'alice', { month: '2026-11', employee_id: 'bob' }), 'admin_only');
  const asAdmin = await env.call('attendanceMonth', 'admin1', { month: '2026-11', employee_id: 'bob' });
  assert.equal(asAdmin.days.find((d) => d.date === '2026-11-18').record.employee_id, 'bob');
  const self = await env.call('attendanceMonth', 'alice', { month: '2026-11', employee_id: 'alice' });
  assert.equal(self.days.find((d) => d.date === '2026-11-18').record, null);
  await expectCode(env.call('attendanceMonth', 'admin1', { month: '2026-11', employee_id: 'ghost' }), 'employee_not_found');
});

test('month: invalid month strings are rejected', async () => {
  const env = makeEnv();
  for (const month of ['2026-13', '2026-1', 'November', 202611, undefined]) {
    await expectCode(env.call('attendanceMonth', 'alice', { month }), 'invalid_input');
  }
});

test('month: an employee\'s response never contains other employees\' records or names', async () => {
  const env = makeEnv();
  await env.markIn('bob');
  await env.markIn('carol');
  const res = await env.call('attendanceMonth', 'alice', { month: '2026-11' });
  const text = JSON.stringify(res);
  assert.ok(!text.includes('bob'));
  assert.ok(!text.includes('carol'));
  assert.deepEqual(Object.keys(res).sort(), ['days', 'summary']);
});

test('month: timestamps in records are ISO strings, never raw Timestamp objects', async () => {
  const env = makeEnv();
  await env.markIn('alice');
  const day = (await env.call('attendanceMonth', 'alice', { month: '2026-11' })).days.find((d) => d.date === '2026-11-18');
  assert.equal(typeof day.record.check_in_at, 'string');
  assert.equal(typeof day.record.created_at, 'string');
  assert.equal(day.status, 'present');
});

test('month: employee join date and started_on keep earlier days out of absences', async () => {
  const env = makeEnv('2026-11-19T20:00:00+05:30');
  env.emp('newbie', { approved_at: new FakeTs(new Date('2026-11-17T08:00:00+05:30').getTime()) });
  const { summary } = await env.call('attendanceMonth', 'admin1', { month: '2026-11', employee_id: 'newbie' });
  assert.equal(summary.working_days, 3); // 17, 18, 19 (after leave)
  assert.equal(summary.absent, 3);
  const none = makeEnv('2026-11-19T20:00:00+05:30', { configured: false });
  const s = (await none.call('attendanceMonth', 'alice', { month: '2026-11' })).summary;
  assert.equal(s.working_days, 0, 'before the first settings save nothing is counted');
});

test('month: join date falls back to requested_at then created_at', async () => {
  const env = makeEnv('2026-11-19T20:00:00+05:30');
  env.emp('req', { approved_at: null, requested_at: new FakeTs(new Date('2026-11-18T09:00:00+05:30').getTime()) });
  env.emp('cre', { approved_at: null, created_at: new FakeTs(new Date('2026-11-19T09:00:00+05:30').getTime()) });
  assert.equal((await env.call('attendanceMonth', 'admin1', { month: '2026-11', employee_id: 'req' })).summary.working_days, 2);
  assert.equal((await env.call('attendanceMonth', 'admin1', { month: '2026-11', employee_id: 'cre' })).summary.working_days, 1);
});

test('month: today before leave time is upcoming, not absent, in the day list', async () => {
  const env = makeEnv('2026-11-18T09:00:00+05:30');
  const { summary, days } = await env.call('attendanceMonth', 'alice', { month: '2026-11' });
  assert.equal(days.find((d) => d.date === '2026-11-18').status, 'upcoming');
  assert.equal(days.find((d) => d.date === '2026-11-17').status, 'absent');
  assert.equal(days.find((d) => d.date === '2026-11-22').status, 'off');
  assert.equal(days.find((d) => d.date === '2026-11-25').status, 'upcoming');
  assert.equal(summary.absent, 14, 'Nov 1..17 minus the Sundays on 1, 8 and 15');
});

test('month: a future month is all zero with no rank', async () => {
  const env = makeEnv();
  const { summary } = await env.call('attendanceMonth', 'alice', { month: '2027-02' });
  assert.equal(summary.working_days, 0);
  assert.equal(summary.percent, null);
  assert.equal(summary.rank, null);
});

// ───────────────────────── team views ─────────────────────────

test('team day: lists only active non-excluded employees sorted by name with statuses', async () => {
  const env = makeEnv('2026-11-18T20:00:00+05:30');
  env.emp('zed', { name: 'Zed' }); env.emp('amy', { name: 'Amy' });
  env.emp('ghost', { name: 'Ghost', exclude_from_headcount: true });
  env.set('2026-11-18T10:00:00+05:30');
  await env.markIn('zed');
  env.set('2026-11-18T20:00:00+05:30');
  const { rows, day } = await env.call('attendanceTeamDay', 'admin1', { date: '2026-11-18' });
  const names = rows.map((r) => r.name);
  assert.deepEqual(names, [...names].sort((a, b) => a.localeCompare(b)));
  assert.ok(!names.includes('Ghost'));
  assert.ok(!names.includes('restricted'));
  assert.equal(day.type, 'working');
  assert.equal(rows.find((r) => r.name === 'Zed').status, 'present');
  assert.equal(rows.find((r) => r.name === 'Amy').status, 'absent');
  assert.equal(rows.find((r) => r.name === 'Zed').record.employee_id, 'zed');
});

test('team day: a Sunday shows everyone as off, a future date as upcoming', async () => {
  const env = makeEnv();
  const sun = await env.call('attendanceTeamDay', 'admin1', { date: '2026-11-22' });
  assert.equal(sun.day.type, 'weekly_off');
  assert.ok(sun.rows.every((r) => r.status === 'off'));
  const fut = await env.call('attendanceTeamDay', 'admin1', { date: '2026-11-25' });
  assert.ok(fut.rows.every((r) => r.status === 'upcoming'));
});

test('team month: ranked with ties, excluded and zero-working employees unranked, summaries only', async () => {
  const env = makeEnv('2026-11-19T20:00:00+05:30');
  env.emp('ghost', { name: 'Ghost', exclude_from_headcount: true });
  env.emp('late', { name: 'Late', approved_at: new FakeTs(new Date('2026-11-19T20:00:00+05:30').getTime()) });
  env.fake.put('attendance_settings', 'config', { ...env.fake.get('attendance_settings', 'config'), started_on: '2026-11-17' });
  for (const uid of ['alice', 'bob']) for (const d of ['2026-11-17', '2026-11-18']) env.putRecord(uid, d);
  env.putRecord('carol', '2026-11-17');
  env.putRecord('ghost', '2026-11-17'); env.putRecord('ghost', '2026-11-18');
  const { rows } = await env.call('attendanceTeamMonth', 'admin1', { month: '2026-11' });
  const by = Object.fromEntries(rows.map((r) => [r.employee_id, r.summary]));
  assert.equal(by.alice.rank, 1);
  assert.equal(by.bob.rank, 1);
  assert.equal(by.carol.rank, 3);
  assert.equal(by.alice.ranked_of, by.carol.ranked_of);
  assert.ok(!('ghost' in by));
  assert.ok(!('restricted' in by));
  assert.ok(rows.findIndex((r) => r.employee_id === 'carol') > rows.findIndex((r) => r.employee_id === 'bob'));
  assert.equal(by.alice.working_days, 3);
  assert.equal(by.alice.present, 2);
});

test('team month: an employee viewing their own month gets only their own rank, not the board', async () => {
  const env = makeEnv('2026-11-19T20:00:00+05:30');
  env.fake.put('attendance_settings', 'config', { ...env.fake.get('attendance_settings', 'config'), started_on: '2026-11-17' });
  env.putRecord('alice', '2026-11-17'); env.putRecord('bob', '2026-11-17'); env.putRecord('bob', '2026-11-18');
  const { summary } = await env.call('attendanceMonth', 'alice', { month: '2026-11' });
  assert.equal(summary.present, 1);
  assert.equal(summary.rank, 2);
  assert.ok(summary.ranked_of >= 2);
  assert.ok(!Object.keys(summary).some((k) => k.includes('bob')));
});

test('team month: an excluded employee viewing their own month has no rank', async () => {
  const env = makeEnv('2026-11-19T20:00:00+05:30');
  env.emp('ghost', { name: 'Ghost', exclude_from_headcount: true });
  const { summary } = await env.call('attendanceMonth', 'ghost', { month: '2026-11' });
  assert.equal(summary.rank, null);
  assert.equal(summary.ranked_of, null);
});

// ───────────────────────── today view ─────────────────────────

test('get today: reports server date, time, day type, settings and own record', async () => {
  const env = makeEnv('2026-11-22T10:00:00+05:30');
  const t = await env.call('attendanceGetToday', 'alice', {});
  assert.equal(t.date, '2026-11-22');
  assert.equal(t.time, '10:00');
  assert.equal(t.now_iso, '2026-11-22T04:30:00.000Z');
  assert.equal(t.configured, true);
  assert.equal(t.day.type, 'weekly_off');
  assert.equal(t.record, null);
  assert.deepEqual(Object.keys(t.settings).sort(), ['arrival', 'full_day_minutes', 'grace_minutes', 'leave', 'max_accuracy_m', 'office', 'radius_m']);
  await env.markIn('alice');
  assert.equal((await env.call('attendanceGetToday', 'alice', {})).record.employee_id, 'alice');
  assert.equal((await env.call('attendanceGetToday', 'bob', {})).record, null);
});

test('get today: holiday is reported with its name', async () => {
  const env = makeEnv();
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'Founders Day' });
  const t = await env.call('attendanceGetToday', 'alice', {});
  assert.deepEqual(t.day, { type: 'holiday', holiday_name: 'Founders Day' });
});

// ───────────────────────── request contract with the app ─────────────────────────

import fs from 'node:fs';

test('app contract: the exact JSON the Flutter app sends is accepted by the real handlers', async () => {
  const req = JSON.parse(fs.readFileSync(new URL('../../flutterapp/test/fixtures/attendance_requests.json', import.meta.url), 'utf8'));
  const env = makeEnv('2026-11-18T10:00:00+05:30', { configured: false });
  const office = { lat: req.attendanceMark.lat, lng: req.attendanceMark.lng };
  env.fake.put('attendance_settings', 'config', {
    office, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00', grace_minutes: 15,
    weekly_off_history: [{ from: '2026-01-01', days: [7] }], started_on: '2026-01-01',
  });
  const never = async (p) => assert.notEqual(await codeOf(p), 'invalid_input');
  await never(env.call('attendanceGetToday', 'alice', req.attendanceGetToday));
  const marked = await env.call('attendanceMark', 'alice', req.attendanceMark);
  assert.equal(marked.already, false);
  await env.call('attendanceMonth', 'alice', req.attendanceMonth);
  await env.call('attendanceMonth', 'admin1', { ...req.attendanceMonthOther, employee_id: 'bob' });
  await env.call('attendanceTeamDay', 'admin1', req.attendanceTeamDay);
  await env.call('attendanceTeamMonth', 'admin1', req.attendanceTeamMonth);
  await env.call('attendanceListApprovals', 'admin1', req.attendanceListApprovals);
  await env.call('attendanceGetSettings', 'admin1', req.attendanceGetSettings);
  await env.call('attendanceSaveSettings', 'admin1', req.attendanceSaveSettings);
  await env.call('attendanceListHolidays', 'alice', req.attendanceListHolidays);
  await env.call('attendanceSetHoliday', 'admin1', req.attendanceSetHoliday);
  await env.call('attendanceRemoveHoliday', 'admin1', req.attendanceRemoveHoliday);
  await never(env.call('attendanceAdminEdit', 'admin1', { ...req.attendanceAdminEdit, employee_id: 'bob' }));
  // Note and review need a late record: 10:30 arrival is late.
  env.set('2026-11-18T10:30:00+05:30');
  await env.call('attendanceMark', 'bob', { ...req.attendanceMark, device_id: 'bobs-phone-0123456789abcdef' });
  await env.call('attendanceSubmitNote', 'bob', req.attendanceSubmitNote);
  await env.call('attendanceReview', 'admin1', { ...req.attendanceReview, employee_id: 'bob' });
});

test('document ids: employee ids that Firestore cannot store are invalid_input, not internal errors', async () => {
  const env = makeEnv();
  for (const employee_id of ['.', '..', '__x__', 'a/b', 'x'.repeat(129), '', null, 7, {}]) {
    const base = { employee_id, date: '2026-11-18' };
    await expectCode(env.call('attendanceAdminEdit', 'admin1', { ...base, check_in: '09:00', check_out: null, reason: 'testing' }), 'invalid_input');
    await expectCode(env.call('attendanceReview', 'admin1', { ...base, kind: 'late', decision: 'approved' }), 'invalid_input');
  }
});

test('month strings: years outside 1970..2999 are rejected (they used to wrap to 19xx)', async () => {
  const env = makeEnv();
  for (const month of ['0001-01', '0099-02', '1969-12', '3000-01', '2026-00', '2026-13', '2026-1', '2026-01-01', ' 2026-01', 5, null, {}]) {
    await expectCode(env.call('attendanceMonth', 'alice', { month }), 'invalid_input');
  }
  assert.equal(L.isValidMonth('1970-01'), true);
  assert.equal(L.isValidMonth('2999-12'), true);
});

test('mark out: the late flag, note and decision from check-in survive a holiday declared after check-in', async () => {
  const env = makeEnv('2026-11-18T10:30:00+05:30');
  await env.markIn('alice');
  await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'late', note: 'Stuck in traffic' });
  assert.equal(env.rec('alice', '2026-11-18').late.status, 'pending');
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-18', name: 'Surprise holiday' });
  env.set('2026-11-18T17:00:00+05:30');
  const { record } = await env.markOut('alice');
  assert.equal(record.late.status, 'pending');
  assert.equal(record.late.note, 'Stuck in traffic');
  assert.equal(record.late_minutes, 30);
  assert.equal(record.early.status, 'none');
  assert.equal(record.needs_review, true);
});

test('fuzz: no input shape, for any callable and any field, ever produces an internal error', async () => {
  const env = makeEnv('2026-11-18T10:30:00+05:30');
  await env.markIn('alice');
  const weird = [
    null, undefined, '', ' ', 'x'.repeat(20000), [], {}, [1], { a: 1 }, -1, 0, 0.5, 1e308, -1e308, true, false,
    '2026-02-30', '2026-11-18/../x', '../x', '2026-11-18\n', 'a/b', '__proto__', 'constructor', '\u0000', '1e3', 'NaN',
  ];
  const good = {
    attendanceGetToday: {},
    attendanceMark: env.markData({ action: 'in', device_id: 'fuzz-device-1' }),
    attendanceSubmitNote: { date: '2026-11-18', kind: 'late', note: 'a fine note' },
    attendanceMonth: { month: '2026-11', employee_id: 'bob' },
    attendanceTeamDay: { date: '2026-11-18' },
    attendanceTeamMonth: { month: '2026-11' },
    attendanceListApprovals: {},
    attendanceReview: { employee_id: 'alice', date: '2026-11-18', kind: 'late', decision: 'approved', comment: 'ok' },
    attendanceAdminEdit: { employee_id: 'bob', date: '2026-11-18', check_in: '09:30', check_out: '10:00', reason: 'because' },
    attendanceGetSettings: {},
    attendanceSaveSettings: {
      office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00', grace_minutes: 15, weekly_off: [7],
    },
    attendanceListHolidays: { year: 2026 },
    attendanceSetHoliday: { date: '2026-12-25', name: 'Christmas' },
    attendanceRemoveHoliday: { date: '2026-12-25' },
  };
  const bad = [];
  for (const [name, payload] of Object.entries(good)) {
    const asUser = ['attendanceGetToday', 'attendanceMark', 'attendanceSubmitNote', 'attendanceMonth', 'attendanceListHolidays']
      .includes(name) ? 'alice' : 'admin1';
    const variants = [undefined, null, 'string', 7, [], [payload]].map((d) => d);
    for (const d of variants) {
      try { await env.call(name, asUser, d); } catch (e) { if (e.code === 'internal') bad.push(`${name} data=${JSON.stringify(d)}`); }
    }
    for (const key of Object.keys(payload)) {
      for (const w of weird) {
        const data = { ...payload, [key]: w };
        try { await env.call(name, asUser, data); } catch (e) {
          if (e.code === 'internal') bad.push(`${name}.${key}=${JSON.stringify(w)?.slice(0, 30)}`);
        }
      }
    }
  }
  assert.deepEqual(bad, []);
});

test('employee document with no status field counts as active, as in the rest of the backend', async () => {
  const env = makeEnv();
  env.emp('legacy', { status: undefined });
  assert.equal((await env.markIn('legacy')).already, false);
  const { summary } = await env.call('attendanceMonth', 'legacy', { month: '2026-11' });
  assert.notEqual(summary.rank, null);
});

test('re-activation does not move the join date: first_approved_at wins over approved_at', async () => {
  const env = makeEnv('2026-11-19T20:00:00+05:30');
  env.emp('back', {
    first_approved_at: new FakeTs(new Date('2026-01-01T09:00:00+05:30').getTime()),
    approved_at: new FakeTs(new Date('2026-11-19T09:00:00+05:30').getTime()),
  });
  env.emp('fresh', { approved_at: new FakeTs(new Date('2026-11-19T09:00:00+05:30').getTime()) });
  const month = async (id) => (await env.call('attendanceMonth', 'admin1', { month: '2026-11', employee_id: id })).summary;
  assert.equal((await month('fresh')).working_days, 1);
  assert.ok((await month('back')).working_days > 1);
});

// ───────────────────────── v2: full / half day, kinds, missed check-outs ─────────────────────────

const checkedOut = (date, minutes, extra = {}) => ({
  check_out_at: new FakeTs(L.istInstant(date, '10:00').getTime() + minutes * 60000),
  check_out_local: 'x',
  worked_minutes: minutes,
  ...extra,
});
const V2_SHIFT = { arrival: '10:00', leave: '19:00', grace_minutes: 15, full_day_minutes: 360 };
const OPEN = { check_out_at: null, check_out_local: null, worked_minutes: null };
const kindOf = (record, date = '2026-11-17') => L.classifyDay({
  date, today: '2026-11-18', nowMinutes: 720, settings: SETTINGS(), holidays: {}, record, rangeStart: '2026-11-01',
}).kind;

test('full day: exactly the threshold is full, one minute less is half', () => {
  const r = (m) => rec('2026-11-17', { shift: V2_SHIFT, ...checkedOut('2026-11-17', m) });
  assert.equal(kindOf(r(360)), 'full');
  assert.equal(kindOf(r(359)), 'half');
  assert.equal(kindOf(r(361)), 'full');
  const custom = (m) => rec('2026-11-17', { shift: { ...V2_SHIFT, full_day_minutes: 480 }, ...checkedOut('2026-11-17', m) });
  assert.equal(kindOf(custom(480)), 'full');
  assert.equal(kindOf(custom(479)), 'half');
});

test('full day: a short shift clamps the threshold to leave minus arrival', () => {
  const shift = { arrival: '10:00', leave: '13:00', grace_minutes: 15, full_day_minutes: 360 };
  assert.equal(L.fullDayThreshold({ shift }, SETTINGS()), 180);
  const r = (m) => rec('2026-11-17', { shift, ...checkedOut('2026-11-17', m) });
  assert.equal(kindOf(r(180)), 'full');
  assert.equal(kindOf(r(179)), 'half');
  assert.equal(L.fullDayThreshold({ shift: { ...shift, leave: '11:00', full_day_minutes: 1440 } }, SETTINGS()), 60);
});

test('full day: an old record without the snapshot uses 360 whatever the setting is now', () => {
  const shift = { arrival: '10:00', leave: '19:00', grace_minutes: 15 };
  const settings = { ...SETTINGS(), full_day_minutes: 480 };
  const kind = (m) => L.classifyDay({
    date: '2026-11-17', today: '2026-11-18', nowMinutes: 720, settings, holidays: {},
    record: rec('2026-11-17', { shift, ...checkedOut('2026-11-17', m) }), rangeStart: '2026-11-01',
  }).kind;
  assert.equal(kind(360), 'full');
  assert.equal(kind(359), 'half');
});

test('full day: approved early leave becomes full, rejected, pending and unreviewed stay half', () => {
  const early = (status) => rec('2026-11-17', {
    shift: V2_SHIFT, ...checkedOut('2026-11-17', 200), early: { ...L.emptyReview(), status },
  });
  assert.equal(kindOf(early('approved')), 'full');
  assert.equal(kindOf(early('rejected')), 'half');
  assert.equal(kindOf(early('pending')), 'half');
  assert.equal(kindOf(early('needs_note')), 'half');
});

test('kind: missed check-out on a past working day, in progress today', () => {
  assert.equal(kindOf(rec('2026-11-17', OPEN)), 'missed_checkout');
  assert.equal(kindOf(rec('2026-11-18', OPEN), '2026-11-18'), 'in_progress');
});

test('kinds: every value appears in a month and the summary counts them', async () => {
  const env = makeEnv('2026-11-18T12:00:00+05:30');
  env.fake.put('attendance_settings', 'config', {
    office: OFFICE, radius_m: 100, max_accuracy_m: 25, arrival: '10:00', leave: '19:00', grace_minutes: 15,
    weekly_off_history: [{ from: '2026-01-01', days: [7] }], started_on: '2026-11-05',
  });
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-09', name: 'Fest' });
  env.putRecord('alice', '2026-11-05', { shift: V2_SHIFT, ...checkedOut('2026-11-05', 540) }); // full
  env.putRecord('alice', '2026-11-06', { shift: V2_SHIFT, ...checkedOut('2026-11-06', 120) }); // half
  env.putRecord('alice', '2026-11-07', OPEN); // missed check-out
  env.putRecord('alice', '2026-11-08', {}); // Sunday: extra
  env.putRecord('alice', '2026-11-16', { shift: V2_SHIFT, ...checkedOut('2026-11-16', 400) }); // full
  env.putRecord('alice', '2026-11-18', OPEN); // in progress
  const m = await env.call('attendanceMonth', 'alice', { month: '2026-11' });
  const kind = Object.fromEntries(m.days.map((d) => [d.date, d.kind]));
  const at = (d) => kind[`2026-11-${d}`];
  assert.deepEqual(
    ['02', '05', '06', '07', '08', '09', '10', '15', '16', '18', '19', '22'].map(at),
    ['not_tracked', 'full', 'half', 'missed_checkout', 'extra', 'holiday', 'absent', 'weekly_off', 'full',
      'in_progress', 'upcoming', 'upcoming'],
  );
  assert.equal(m.days.find((d) => d.date === '2026-11-10').status, 'absent', 'status keeps its old meaning');
  const s = m.summary;
  assert.equal(s.working_days, 11);
  assert.equal(s.present, 5);
  assert.equal(s.absent, 6);
  assert.equal(s.missed_checkout, 1);
  assert.equal(s.full_days, 2);
  assert.equal(s.half_days, 2); // half + missed_checkout
  assert.equal(s.attended_value, 4); // 2 full + 1 in progress + 0.5 * 2
  assert.equal(s.percent, 36);
  assert.equal(s.stars, 1.8);
  const set = new Set(Object.values(kind));
  for (const k of ['not_tracked', 'upcoming', 'holiday', 'weekly_off', 'extra', 'absent', 'in_progress',
    'missed_checkout', 'full', 'half']) assert.ok(set.has(k), k);
});

test('kinds: team day rows carry kind for every employee', async () => {
  const env = makeEnv('2026-11-18T12:00:00+05:30');
  env.putRecord('alice', '2026-11-18', OPEN);
  const day = await env.call('attendanceTeamDay', 'admin1', { date: '2026-11-18' });
  const kinds = Object.fromEntries(day.rows.map((r) => [r.employee_id, r.kind]));
  assert.equal(kinds.alice, 'in_progress');
  assert.equal(kinds.bob, 'upcoming');
  env.set('2026-11-18T20:00:00+05:30');
  const late = await env.call('attendanceTeamDay', 'admin1', { date: '2026-11-18' });
  const lk = Object.fromEntries(late.rows.map((r) => [r.employee_id, r.kind]));
  assert.equal(lk.alice, 'in_progress', 'still in progress after leave time');
  assert.equal(lk.bob, 'absent');
  const past = await env.call('attendanceTeamDay', 'admin1', { date: '2026-11-15' });
  assert.ok(past.rows.every((r) => r.kind === 'weekly_off'));
  const future = await env.call('attendanceTeamDay', 'admin1', { date: '2026-11-25' });
  assert.ok(future.rows.every((r) => r.kind === 'upcoming'));
});

test('kinds: today stays in progress after leave time and turns missed_checkout at midnight', async () => {
  const env = makeEnv('2026-11-18T20:30:00+05:30');
  env.putRecord('alice', '2026-11-18', OPEN);
  const load = () => env.call('attendanceMonth', 'alice', { month: '2026-11' });
  let m = await load();
  assert.equal(m.days.find((d) => d.date === '2026-11-18').kind, 'in_progress');
  assert.equal(m.summary.missed_checkout, 0);
  assert.equal(m.summary.attended_value, 1);
  env.set('2026-11-19T00:00:00+05:30');
  m = await load();
  assert.equal(m.days.find((d) => d.date === '2026-11-18').kind, 'missed_checkout');
  assert.equal(m.summary.missed_checkout, 1);
  assert.equal(m.summary.half_days, 1);
  assert.equal(m.summary.attended_value, 0.5);
});

test('kinds: an admin adding the check-out turns missed_checkout into full or half at once', async () => {
  const env = makeEnv('2026-11-19T12:00:00+05:30');
  env.putRecord('alice', '2026-11-17', OPEN);
  env.putRecord('bob', '2026-11-17', OPEN);
  const kindFor = async (uid) => (await env.call('attendanceMonth', uid, { month: '2026-11' }))
    .days.find((d) => d.date === '2026-11-17').kind;
  assert.equal(await kindFor('alice'), 'missed_checkout');
  await env.call('attendanceAdminEdit', 'admin1', {
    employee_id: 'alice', date: '2026-11-17', check_in: '10:00', check_out: '19:00', reason: 'forgot to tap out',
  });
  assert.equal(await kindFor('alice'), 'full');
  await env.call('attendanceAdminEdit', 'admin1', {
    employee_id: 'bob', date: '2026-11-17', check_in: '10:00', check_out: '12:00', reason: 'left at noon',
  });
  assert.equal(await kindFor('bob'), 'half');
});

test('kinds: approving an early note makes the day full, rejecting keeps it half', async () => {
  const run = async (decision) => {
    const env = makeEnv('2026-11-18T10:00:00+05:30');
    await env.markIn('alice');
    env.set('2026-11-18T13:00:00+05:30');
    await env.markOut('alice');
    await env.call('attendanceSubmitNote', 'alice', { date: '2026-11-18', kind: 'early', note: 'doctor visit' });
    const kindFor = async () => (await env.call('attendanceMonth', 'alice', { month: '2026-11' }))
      .days.find((d) => d.date === '2026-11-18').kind;
    assert.equal(await kindFor(), 'half');
    await env.call('attendanceReview', 'admin1', {
      employee_id: 'alice', date: '2026-11-18', kind: 'early', decision,
    });
    return kindFor();
  };
  assert.equal(await run('approved'), 'full');
  assert.equal(await run('rejected'), 'half');
});

test('half days: percent, stars and rank use the attended value and ties still share a rank', async () => {
  const env = makeEnv('2026-11-17T20:00:00+05:30');
  env.fake.put('attendance_settings', 'config', {
    office: OFFICE, radius_m: 100, max_accuracy_m: 25, arrival: '10:00', leave: '19:00', grace_minutes: 15,
    weekly_off_history: [{ from: '2026-01-01', days: [7] }], started_on: '2026-11-16',
  });
  const full = (uid, d) => env.putRecord(uid, d, { shift: V2_SHIFT, ...checkedOut(d, 540) });
  const half = (uid, d) => env.putRecord(uid, d, { shift: V2_SHIFT, ...checkedOut(d, 100) });
  full('alice', '2026-11-16'); full('alice', '2026-11-17');
  full('bob', '2026-11-16'); half('bob', '2026-11-17');
  half('carol', '2026-11-16'); full('carol', '2026-11-17');
  half('admin2', '2026-11-16'); half('admin2', '2026-11-17');
  const team = await env.call('attendanceTeamMonth', 'admin1', { month: '2026-11' });
  const row = Object.fromEntries(team.rows.map((r) => [r.employee_id, r.summary]));
  assert.equal(row.alice.percent, 100);
  assert.equal(row.alice.stars, 5);
  assert.equal(row.bob.attended_value, 1.5);
  assert.equal(row.bob.percent, 75);
  assert.equal(row.bob.stars, 3.8);
  assert.equal(row.admin2.percent, 50);
  assert.equal(row.admin2.stars, 2.5);
  assert.equal(row.admin1.percent, 0);
  assert.deepEqual([row.alice.rank, row.bob.rank, row.carol.rank, row.admin2.rank, row.admin1.rank], [1, 2, 2, 4, 5]);
  assert.equal(row.alice.ranked_of, 5);
  assert.equal(row.admin2.present, 2, 'a half day still counts as present');
});

test('ranking: attended value decides first, then fewer late+early, ties share a rank', () => {
  const r = L.rankEmployees([
    { id: 'a', eligible: true, attended_value: 4.5, late: 0 },
    { id: 'b', eligible: true, attended_value: 4.5, late: 0 },
    { id: 'c', eligible: true, attended_value: 4.5, late: 2 },
    { id: 'd', eligible: true, attended_value: 4, late: 0 },
  ]);
  assert.deepEqual(['a', 'b', 'c', 'd'].map((i) => r.get(i).rank), [1, 1, 3, 4]);
});

test('settings v2: full_day_minutes bounds, optional, not null or a string', () => {
  const ok = { office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00', grace_minutes: 15, weekly_off: [7] };
  const bad = (v) => assert.throws(() => L.validateSettingsInput({ ...ok, full_day_minutes: v }), (e) => e.code === 'invalid_input');
  bad(59); bad(1441); bad(360.5); bad('360'); bad(null); bad(NaN); bad(-1);
  assert.equal(L.validateSettingsInput({ ...ok, full_day_minutes: 60 }).full_day_minutes, 60);
  assert.equal(L.validateSettingsInput({ ...ok, full_day_minutes: 1440 }).full_day_minutes, 1440);
  assert.equal(L.validateSettingsInput(ok).full_day_minutes, undefined);
  assert.equal(L.normalizeSettings(null).full_day_minutes, 360);
  assert.equal(L.normalizeSettings({ full_day_minutes: 12 }).full_day_minutes, 360);
});

test('settings v2: saved, returned by get / save / today, and absent keeps the stored value', async () => {
  const env = makeEnv('2026-11-18T10:00:00+05:30', { configured: false });
  const first = (await env.call('attendanceSaveSettings', 'admin1', settingsInput())).settings;
  assert.equal(first.full_day_minutes, 360, 'default when never set');
  const second = (await env.call('attendanceSaveSettings', 'admin1', settingsInput({ full_day_minutes: 480 }))).settings;
  assert.equal(second.full_day_minutes, 480);
  const third = (await env.call('attendanceSaveSettings', 'admin1', settingsInput({ radius_m: 200 }))).settings;
  assert.equal(third.full_day_minutes, 480, 'omitted keeps its value');
  assert.equal(third.radius_m, 200);
  assert.equal((await env.call('attendanceGetSettings', 'admin1', {})).settings.full_day_minutes, 480);
  assert.equal((await env.call('attendanceGetToday', 'alice', {})).settings.full_day_minutes, 480);
  await expectCode(env.call('attendanceSaveSettings', 'admin1', settingsInput({ full_day_minutes: 30 })), 'invalid_input');
  await expectCode(env.call('attendanceSaveSettings', 'admin1', settingsInput({ full_day_minutes: null })), 'invalid_input');
  assert.equal(env.fake.get('attendance_settings', 'config').full_day_minutes, 480, 'a rejected save changes nothing');
  await env.markIn('alice');
  assert.equal(env.rec('alice', '2026-11-18').shift.full_day_minutes, 480);
  await env.call('attendanceSaveSettings', 'admin1', settingsInput({ full_day_minutes: 300 }));
  assert.equal(env.rec('alice', '2026-11-18').shift.full_day_minutes, 480, 'snapshot is not rewritten');
});

test('missed check-outs: window, exclusions, order and shape', async () => {
  const env = makeEnv('2026-11-20T12:00:00+05:30');
  env.emp('nohead', { exclude_from_headcount: true });
  await env.call('attendanceSetHoliday', 'admin1', { date: '2026-11-12', name: 'Fest' });
  env.putRecord('alice', '2026-11-19', OPEN);
  env.putRecord('bob', '2026-11-19', OPEN);
  env.putRecord('carol', '2026-11-17', OPEN);
  env.putRecord('alice', '2026-10-20', OPEN); // first day inside the 31-day window
  env.putRecord('alice', '2026-10-19', OPEN); // one day outside it
  env.putRecord('alice', '2026-11-20', OPEN); // today is in progress, not missed
  env.putRecord('carol', '2026-11-18', {}); // has a check-out
  env.putRecord('restricted', '2026-11-18', OPEN); // inactive
  env.putRecord('nohead', '2026-11-18', OPEN); // excluded from headcount
  env.putRecord('alice', '2026-11-12', OPEN); // holiday: extra
  env.putRecord('alice', '2026-11-15', OPEN); // Sunday: extra
  const { items, missed_checkouts: missed } = await env.call('attendanceListApprovals', 'admin1', {});
  assert.deepEqual(items, []);
  assert.deepEqual(missed, [
    { employee_id: 'alice', employee_name: 'alice', date: '2026-11-19', check_in: '10:00' },
    { employee_id: 'bob', employee_name: 'bob', date: '2026-11-19', check_in: '10:00' },
    { employee_id: 'carol', employee_name: 'carol', date: '2026-11-17', check_in: '10:00' },
    { employee_id: 'alice', employee_name: 'alice', date: '2026-10-20', check_in: '10:00' },
  ]);
  await env.call('attendanceAdminEdit', 'admin1', {
    employee_id: 'alice', date: '2026-11-19', check_in: '10:00', check_out: '19:00', reason: 'added time',
  });
  const after = (await env.call('attendanceListApprovals', 'admin1', {})).missed_checkouts;
  assert.deepEqual(after.map((m) => `${m.employee_id}:${m.date}`), ['bob:2026-11-19', 'carol:2026-11-17', 'alice:2026-10-20']);
});

test('missed check-outs: non-admins are denied, empty list when none', async () => {
  const env = makeEnv('2026-11-20T12:00:00+05:30');
  await expectCode(env.call('attendanceListApprovals', 'alice', {}), 'admin_only');
  assert.deepEqual((await env.call('attendanceListApprovals', 'admin1', {})).missed_checkouts, []);
});
