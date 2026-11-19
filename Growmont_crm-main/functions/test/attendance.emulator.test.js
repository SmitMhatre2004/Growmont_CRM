/**
 * Attendance against the REAL Firestore emulator (admin SDK, real Timestamps,
 * real transactions, real rules). Skipped unless FIRESTORE_EMULATOR_HOST is
 * set, so a plain `node --test test/` stays green without Java.
 *
 *   cd <repo root>
 *   firebase emulators:exec --only firestore --project demo-growmont \
 *     "node --test functions/test/attendance.emulator.test.js"
 *
 * Set WRITE_CONTRACT_FIXTURE=1 to also (re)write the JSON that the Dart
 * contract test parses (flutterapp/test/fixtures/attendance_contract.json).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';
import { createAttendanceHandlers } from '../attendance.js';

const EMU = process.env.FIRESTORE_EMULATOR_HOST;
const skip = EMU ? false : 'FIRESTORE_EMULATOR_HOST not set';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = 'demo-growmont';

if (EMU && !admin.apps.length) admin.initializeApp({ projectId: PROJECT });
const db = EMU ? admin.firestore() : null;
const Timestamp = admin.firestore.Timestamp;

let nowMs = Date.parse('2026-11-18T04:30:00Z'); // Wed 10:00 IST
const setNow = (iso) => { nowMs = Date.parse(iso); };
const h = EMU ? createAttendanceHandlers({ db, Timestamp, now: () => new Date(nowMs) }) : {};

const OFFICE = { lat: 18.5204, lng: 73.8567 };
const as = (uid, data) => ({ auth: { uid }, data });
const mark = (action, over = {}) => ({
  action, lat: OFFICE.lat, lng: OFFICE.lng, accuracy_m: 8, is_mocked: false,
  position_age_ms: 500, device_id: 'dev-aaaaaaaaaaaaaaaaaaaa', biometric_passed: true, ...over,
});
const code = async (promise) => {
  try { await promise; } catch (e) { return e.details && e.details.code; }
  return 'NO_ERROR';
};
const json = (v) => JSON.parse(JSON.stringify(v));
const fixture = {};

async function wipe() {
  for (const c of ['attendance', 'attendance_settings', 'attendance_holidays', 'attendance_devices',
    'attendance_audit', 'employees']) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed() {
  await wipe();
  const e = (id, name, role, extra = {}) => db.collection('employees').doc(id).set({
    name, role, status: 'ACTIVE', approved_at: Timestamp.fromDate(new Date('2026-01-01T00:00:00Z')),
    avatar_url: '', ...extra,
  });
  await e('admin1', 'Asha Admin', 'ADMIN');
  await e('emp1', 'Bela Employee', 'EMPLOYEE');
  await e('emp2', 'Chitra Employee', 'EMPLOYEE');
  await e('gone', 'Dev Inactive', 'EMPLOYEE', { status: 'INACTIVE' });
  await e('nohead', 'Esha Excluded', 'EMPLOYEE', { exclude_from_headcount: true });
}

test('emulator: whole attendance journey on real Firestore', { skip }, async () => {
  await seed();
  const cap = (name, v) => { fixture[name] = json(v); return v; };

  // Not configured yet.
  cap('today_unconfigured', await h.attendanceGetToday(as('emp1', {})));
  assert.equal(await code(h.attendanceMark(as('emp1', mark('in')))), 'not_configured');

  // Settings.
  assert.equal(await code(h.attendanceGetSettings(as('emp1', {}))), 'admin_only');
  const saved = cap('save_settings', await h.attendanceSaveSettings(as('admin1', {
    office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00',
    grace_minutes: 15, weekly_off: [7],
  })));
  assert.deepEqual(saved.settings.office, OFFICE);
  assert.equal(saved.settings.full_day_minutes, 360);
  assert.equal(cap('save_settings_full_day', await h.attendanceSaveSettings(as('admin1', {
    office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00',
    grace_minutes: 15, weekly_off: [7], full_day_minutes: 360,
  }))).settings.full_day_minutes, 360);
  cap('get_settings', await h.attendanceGetSettings(as('admin1', {})));
  const cfg = (await db.collection('attendance_settings').doc('config').get()).data();
  assert.ok(cfg.updated_at instanceof Timestamp);
  assert.equal(typeof saved.settings.updated_at, 'string');

  // Mark in on time: real Timestamps stored, ISO strings returned.
  const t = cap('today_configured', await h.attendanceGetToday(as('emp1', {})));
  assert.equal(t.configured, true);
  const inRes = cap('mark_in', await h.attendanceMark(as('emp1', mark('in'))));
  assert.equal(inRes.already, false);
  assert.equal(typeof inRes.record.check_in_at, 'string');
  assert.equal(inRes.record.check_in_local, '10:00');
  const stored = (await db.collection('attendance').doc('emp1_2026-11-18').get()).data();
  assert.ok(stored.check_in_at instanceof Timestamp);

  // Retry: idempotent.
  const again = await h.attendanceMark(as('emp1', mark('in')));
  assert.equal(again.already, true);
  assert.deepEqual(again.record, inRes.record);

  // Another employee on the same device: refused.
  assert.equal(await code(h.attendanceMark(as('emp2', mark('in')))), 'device_in_use');

  // Late arrival for emp2 on another device -> needs_note; note -> pending -> approvals.
  setNow('2026-11-18T05:30:00Z'); // 11:00 IST
  const late = cap('mark_in_late', await h.attendanceMark(as('emp2', mark('in', { device_id: 'dev-bbbbbbbbbbbbbbbbbbbb' }))));
  assert.equal(late.record.late.status, 'needs_note');
  assert.equal(late.record.late_minutes, 60);
  const noted = cap('submit_note', await h.attendanceSubmitNote(as('emp2', {
    date: '2026-11-18', kind: 'late', note: 'Bus broke down',
  })));
  assert.equal(noted.record.late.status, 'pending');
  assert.equal(noted.record.needs_review, true);
  const approvals = cap('approvals', await h.attendanceListApprovals(as('admin1', {})));
  assert.equal(approvals.items.length, 1);
  assert.equal(approvals.items[0].employee_id, 'emp2');
  const reviewed = cap('review', await h.attendanceReview(as('admin1', {
    employee_id: 'emp2', date: '2026-11-18', kind: 'late', decision: 'approved', comment: 'ok',
  })));
  assert.equal(reviewed.record.late.status, 'approved');
  assert.equal(await code(h.attendanceReview(as('admin1', {
    employee_id: 'emp2', date: '2026-11-18', kind: 'late', decision: 'rejected',
  }))), 'not_pending');
  assert.ok((await db.collection('attendance_audit').get()).size >= 2);

  // Mark out (early) and again.
  setNow('2026-11-18T05:32:00Z');
  const out = cap('mark_out_early', await h.attendanceMark(as('emp1', mark('out'))));
  assert.equal(out.record.early.status, 'needs_note');
  setNow('2026-11-18T13:35:00Z'); // 19:05 IST
  const out2 = await h.attendanceMark(as('emp1', mark('out')));
  assert.equal(out2.record.early.status, 'none');

  // Holidays.
  cap('set_holiday', await h.attendanceSetHoliday(as('admin1', { date: '2026-11-20', name: 'Diwali' })));
  cap('list_holidays', await h.attendanceListHolidays(as('emp1', { year: 2026 })));
  cap('remove_holiday', await h.attendanceRemoveHoliday(as('admin1', { date: '2026-11-20' })));
  cap('remove_holiday_missing', await h.attendanceRemoveHoliday(as('admin1', { date: '2026-11-21' })));
  await h.attendanceSetHoliday(as('admin1', { date: '2026-11-20', name: 'Diwali' }));

  // Admin edit create, edit, delete.
  const edit = cap('admin_edit', await h.attendanceAdminEdit(as('admin1', {
    employee_id: 'emp1', date: '2026-11-17', check_in: '09:30', check_out: '18:00', reason: 'Forgot to mark',
  })));
  assert.equal(edit.record.source, 'admin');
  const del = cap('admin_delete', await h.attendanceAdminEdit(as('admin1', {
    employee_id: 'emp1', date: '2026-11-17', check_in: null, check_out: null, reason: 'Entered by mistake',
  })));
  assert.equal(del.record, null);
  await h.attendanceAdminEdit(as('admin1', {
    employee_id: 'emp1', date: '2026-11-16', check_in: '10:40', check_out: null, reason: 'Phone broke',
  }));

  // Missed check-out: emp1 checked in on the 16th and never out. Listed for admins only.
  const missedList = cap('approvals_missed', await h.attendanceListApprovals(as('admin1', {})));
  assert.deepEqual(missedList.missed_checkouts, [
    { employee_id: 'emp1', employee_name: 'Bela Employee', date: '2026-11-16', check_in: '10:40' },
  ]);
  assert.equal(await code(h.attendanceListApprovals(as('emp1', {}))), 'admin_only');

  // Month and team views (these use the where() queries: no composite index may be needed).
  const monthSelf = cap('month_self', await h.attendanceMonth(as('emp1', { month: '2026-11' })));
  const kindOn = (d) => monthSelf.days.find((x) => x.date === d).kind;
  assert.equal(kindOn('2026-11-16'), 'missed_checkout');
  assert.equal(kindOn('2026-11-18'), 'full'); // 10:00 to 19:05 on the last check-out
  // started_on is the 18th, so the 16th is not counted in the summary.
  assert.equal(monthSelf.summary.full_days, 1);
  assert.equal(monthSelf.summary.half_days, 0);
  assert.equal(monthSelf.summary.attended_value, 1);
  cap('month_other_as_admin', await h.attendanceMonth(as('admin1', { month: '2026-11', employee_id: 'emp2' })));
  cap('team_day', await h.attendanceTeamDay(as('admin1', { date: '2026-11-18' })));
  cap('team_month', await h.attendanceTeamMonth(as('admin1', { month: '2026-11' })));
  assert.equal(await code(h.attendanceMonth(as('emp1', { month: '2026-11', employee_id: 'emp2' }))), 'admin_only');

  // Error shape that the app parses.
  try { await h.attendanceMark(as('emp1', mark('in', { lat: 19.0 }))); assert.fail('should refuse'); } catch (e) {
    cap('error_outside_radius', e.toJSON());
    assert.equal(e.details.code, 'outside_radius');
    assert.equal(typeof e.details.distance_m, 'number');
  }

  if (process.env.WRITE_CONTRACT_FIXTURE) {
    const dest = path.resolve(HERE, '../../flutterapp/test/fixtures/attendance_contract.json');
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, `${JSON.stringify(fixture, null, 2)}\n`);
  }
});

test('emulator: concurrent mark-in by one employee makes one record, all callers agree', { skip }, async () => {
  await seed();
  setNow('2026-11-18T04:30:00Z');
  await h.attendanceSaveSettings(as('admin1', {
    office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00',
    grace_minutes: 15, weekly_off: [7],
  }));
  const results = await Promise.all(Array.from({ length: 8 }, () => h.attendanceMark(as('emp1', mark('in')))));
  assert.equal(results.filter((r) => !r.already).length, 1);
  assert.equal((await db.collection('attendance').get()).size, 1);
});

test('emulator: two employees racing for one device, exactly one wins', { skip }, async () => {
  await seed();
  setNow('2026-11-18T04:30:00Z');
  await h.attendanceSaveSettings(as('admin1', {
    office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00',
    grace_minutes: 15, weekly_off: [7],
  }));
  const settled = await Promise.allSettled([
    h.attendanceMark(as('emp1', mark('in'))),
    h.attendanceMark(as('emp2', mark('in'))),
  ]);
  assert.equal(settled.filter((s) => s.status === 'fulfilled').length, 1);
  assert.equal((await db.collection('attendance').get()).size, 1);
});

test('emulator: odd device ids and employee ids never become internal errors', { skip }, async () => {
  await seed();
  setNow('2026-11-18T04:30:00Z');
  await h.attendanceSaveSettings(as('admin1', {
    office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00',
    grace_minutes: 15, weekly_off: [7],
  }));
  for (const device_id of ['..', '.', '__x__', 'a b', 'ünï-€', 'x'.repeat(129), '../emp2', 'a\\b']) {
    const c = await code(h.attendanceMark(as('emp1', mark('in', { device_id }))));
    assert.notEqual(c, 'internal', `device_id ${JSON.stringify(device_id)}`);
  }
  for (const employee_id of ['.', '..', '__x__', 'a/b', 'x'.repeat(2000), 'ghost']) {
    const base = { employee_id, date: '2026-11-18', reason: 'testing' };
    for (const call of [
      () => h.attendanceAdminEdit(as('admin1', { ...base, check_in: '09:00', check_out: null })),
      () => h.attendanceReview(as('admin1', { ...base, kind: 'late', decision: 'approved' })),
      () => h.attendanceMonth(as('admin1', { month: '2026-11', employee_id })),
    ]) {
      const c = await code(call());
      assert.notEqual(c, 'internal', `employee_id ${JSON.stringify(employee_id).slice(0, 20)}`);
      assert.notEqual(c, 'NO_ERROR');
    }
  }
});

test('emulator: rules deny every client read and write of the attendance collections', { skip }, async () => {
  await seed();
  const base = `http://${EMU.replace('127.0.0.1', '127.0.0.1')}/v1/projects/${PROJECT}/databases/(default)/documents`;
  for (const c of ['attendance', 'attendance_settings', 'attendance_holidays', 'attendance_devices', 'attendance_audit']) {
    const read = await fetch(`${base}/${c}/x`);
    assert.equal(read.status, 403, `read ${c}`);
    const list = await fetch(`${base}/${c}`);
    assert.equal(list.status, 403, `list ${c}`);
    const write = await fetch(`${base}/${c}?documentId=x`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: { a: { stringValue: 'b' } } }),
    });
    assert.equal(write.status, 403, `write ${c}`);
    // A signed-in-looking token does not help: rules say false for everyone.
    const fake = Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url')
      + '.' + Buffer.from(JSON.stringify({ user_id: 'emp1', sub: 'emp1' })).toString('base64url') + '.';
    const authed = await fetch(`${base}/${c}/x`, { headers: { Authorization: `Bearer ${fake}` } });
    assert.equal(authed.status, 403, `authed read ${c}`);
  }
});

test('emulator: editing a self-marked record, changing settings twice, clearing the office', { skip }, async () => {
  await seed();
  setNow('2026-11-18T05:30:00Z'); // 11:00 IST, late
  const cfg = {
    office: OFFICE, radius_m: 50, max_accuracy_m: 25, arrival: '10:00', leave: '19:00',
    grace_minutes: 15, weekly_off: [7],
  };
  await h.attendanceSaveSettings(as('admin1', cfg));
  await h.attendanceMark(as('emp1', mark('in')));
  setNow('2026-11-18T05:45:00Z');
  await h.attendanceMark(as('emp1', mark('out')));
  setNow('2026-11-18T06:15:00Z');
  // Admin changes only the check-out: check-in keeps its instant and GPS.
  const r = (await h.attendanceAdminEdit(as('admin1', {
    employee_id: 'emp1', date: '2026-11-18', check_in: '11:00', check_out: '11:40', reason: 'Fix out time',
  }))).record;
  assert.equal(r.source, 'mixed');
  assert.equal(r.admin_edited, true);
  assert.ok(r.check_in_geo, 'check-in GPS kept');
  assert.equal(r.late.status, 'needs_note');
  assert.equal(await code(h.attendanceMark(as('emp1', mark('out')))), 'locked_by_admin');
  // Settings: weekly-off change twice in a day replaces, then clear the office.
  await h.attendanceSaveSettings(as('admin1', { ...cfg, weekly_off: [6, 7] }));
  const s2 = (await h.attendanceSaveSettings(as('admin1', { ...cfg, weekly_off: [5], office: null }))).settings;
  assert.equal(s2.office, null);
  assert.deepEqual(s2.weekly_off, [5]);
  assert.equal(s2.weekly_off_history.length, 1);
  assert.equal((await h.attendanceGetToday(as('emp1', {}))).configured, false);
  const audit = await db.collection('attendance_audit').get();
  assert.ok(audit.docs.every((d) => d.data().at instanceof Timestamp));
});
