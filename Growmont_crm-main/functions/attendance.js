/**
 * Attendance callables. The server decides time, day, distance and lateness;
 * Firestore rules deny all direct client access to the attendance collections.
 *
 * createAttendanceHandlers({ db, Timestamp, now }) returns one plain
 * `async (request) => result` function per callable. index.js wraps each in
 * onCall; tests inject an in-memory db and a fixed clock instead.
 */

import { HttpsError } from 'firebase-functions/v2/https';
import * as L from './attendance_logic.js';

const CODE_MAP = {
  unauthenticated: 'unauthenticated',
  inactive: 'permission-denied',
  admin_only: 'permission-denied',
  invalid_input: 'invalid-argument',
  employee_not_found: 'not-found',
};

function toHttpsError(error) {
  if (error instanceof HttpsError) return error;
  if (error instanceof L.AttendanceError) {
    return new HttpsError(CODE_MAP[error.code] || 'failed-precondition', error.message,
      { ...error.details, code: error.code });
  }
  console.error(error);
  return new HttpsError('internal', 'Something went wrong on the server. Please try again.', { code: 'internal' });
}

const err = (code, message, details) => new L.AttendanceError(code, message, details);

/** Recursively turns Timestamps / Dates into ISO strings. */
export function serialize(v) {
  if (v === null || v === undefined) return v ?? null;
  if (v instanceof Date) return v.toISOString();
  if (typeof v.toDate === 'function') return v.toDate().toISOString();
  if (Array.isArray(v)) return v.map(serialize);
  if (typeof v === 'object') {
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = serialize(val);
    return out;
  }
  return v;
}

export function createAttendanceHandlers({ db, Timestamp, now = () => new Date() }) {
  const ts = (d) => (d ? Timestamp.fromDate(d) : null);
  const col = (name) => db.collection(name);
  const configRef = () => col('attendance_settings').doc('config');
  const recordId = (uid, date) => `${uid}_${date}`;
  // Older employee documents have no status field; the rest of the backend treats those as active.
  const isActiveEmployee = (e) => (e.status || 'ACTIVE') === 'ACTIVE';
  const isEligibleEmployee = (e) => isActiveEmployee(e) && !e.exclude_from_headcount;

  async function requireCaller(request, { admin }) {
    const uid = request && request.auth && request.auth.uid;
    if (!uid) throw err('unauthenticated', 'Please sign in again.');
    const snap = await col('employees').doc(uid).get();
    const data = snap.exists ? snap.data() : null;
    if (!data || !isActiveEmployee(data)) {
      throw err('inactive', 'Your account is not active, so attendance is unavailable.');
    }
    if (admin && data.role !== 'ADMIN') throw err('admin_only', 'Only administrators can do this.');
    return { uid, name: data.name || '', data };
  }

  function wrap(fn, { admin = false } = {}) {
    return async (request) => {
      try {
        const caller = await requireCaller(request, { admin });
        const data = request.data && typeof request.data === 'object' && !Array.isArray(request.data)
          ? request.data : {};
        return await fn(data, caller);
      } catch (e) {
        throw toHttpsError(e);
      }
    };
  }

  const loadSettings = async () => {
    const snap = await configRef().get();
    return L.normalizeSettings(snap.exists ? snap.data() : null);
  };

  const loadHolidays = async () => {
    const snap = await col('attendance_holidays').get();
    const map = {};
    snap.docs.forEach((d) => {
      const data = d.data();
      map[data.date || d.id] = data.name;
    });
    return map;
  };

  const settingsOut = (s) => {
    const today = L.istParts(now()).date;
    return serialize({ ...s, weekly_off: L.weeklyOffFor(s.weekly_off_history, today) });
  };

  const joinDateOf = (emp) => {
    // approved_at moves on every re-activation; first_approved_at does not.
    const d = L.toDateObj(emp.first_approved_at) || L.toDateObj(emp.approved_at)
      || L.toDateObj(emp.requested_at) || L.toDateObj(emp.created_at);
    return d ? L.istParts(d).date : null;
  };

  const shiftOf = (s) => ({
    arrival: s.arrival, leave: s.leave, grace_minutes: s.grace_minutes, full_day_minutes: s.full_day_minutes,
  });

  async function loadEmployees() {
    const snap = await col('employees').get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  }

  /** date -> record for each employee id, for one month. */
  async function loadMonthRecords(month) {
    const snap = await col('attendance').where('month', '==', month).get();
    const byEmp = {};
    snap.docs.forEach((d) => {
      const r = d.data();
      (byEmp[r.employee_id] ||= {})[r.date] = r;
    });
    return byEmp;
  }

  function summarize(month, emp, ctx, recordsByEmp) {
    return L.buildMonth({
      month, now: ctx.nowD, settings: ctx.settings, holidays: ctx.holidays,
      records: recordsByEmp[emp.id] || {}, joinDate: joinDateOf(emp),
    });
  }

  /** Summaries for every employee plus ranking among eligible ones. */
  async function monthForAll(month) {
    const nowD = now();
    const [settings, holidays, employees, recordsByEmp] = await Promise.all([
      loadSettings(), loadHolidays(), loadEmployees(), loadMonthRecords(month),
    ]);
    const ctx = { nowD, settings, holidays };
    const built = new Map();
    for (const emp of employees) built.set(emp.id, summarize(month, emp, ctx, recordsByEmp));
    const ranks = L.rankEmployees(employees.map((emp) => {
      const s = built.get(emp.id).summary;
      return {
        id: emp.id, eligible: isEligibleEmployee(emp) && s.working_days > 0,
        attended_value: s.attended_value, late: s.late + s.early,
      };
    }));
    for (const emp of employees) {
      Object.assign(built.get(emp.id).summary, ranks.get(emp.id));
    }
    return { employees, built, ctx };
  }

  // ───────────── today ─────────────

  const getToday = wrap(async (_data, caller) => {
    const nowD = now();
    const { date, time } = L.istParts(nowD);
    const [settings, holidays, recSnap] = await Promise.all([
      loadSettings(), loadHolidays(), col('attendance').doc(recordId(caller.uid, date)).get(),
    ]);
    const dt = L.dayType(date, holidays, settings.weekly_off_history);
    return {
      now_iso: nowD.toISOString(),
      date,
      time,
      configured: Boolean(settings.office),
      settings: {
        arrival: settings.arrival, leave: settings.leave, grace_minutes: settings.grace_minutes,
        full_day_minutes: settings.full_day_minutes, radius_m: settings.radius_m, max_accuracy_m: settings.max_accuracy_m, office: settings.office,
      },
      day: { type: dt.type, holiday_name: dt.holiday_name },
      record: recSnap.exists ? serialize(recSnap.data()) : null,
    };
  });

  // ───────────── mark in / out ─────────────

  const mark = wrap(async (data, caller) => {
    const input = L.validateMarkInput(data);
    const nowD = now();
    const { date, month } = L.istParts(nowD);
    const settings = await loadSettings();
    const distance = L.checkMarkPolicy(input, settings);
    const holidaySnap = await col('attendance_holidays').doc(date).get();
    const holidays = holidaySnap.exists ? { [date]: holidaySnap.data().name } : {};
    const working = L.dayType(date, holidays, settings.weekly_off_history).type === 'working';
    const geo = {
      lat: input.lat, lng: input.lng, accuracy_m: input.accuracy_m,
      distance_m: Math.round(distance * 10) / 10,
    };
    const recRef = col('attendance').doc(recordId(caller.uid, date));
    const devRef = col('attendance_devices').doc(`${input.device_id}_${date}`);

    const result = await db.runTransaction(async (tx) => {
      const recSnap = await tx.get(recRef);
      const devSnap = await tx.get(devRef);
      if (devSnap.exists && devSnap.data().employee_id !== caller.uid) {
        throw err('device_in_use', 'This device has already been used by another employee today.');
      }
      const existing = recSnap.exists ? recSnap.data() : null;

      if (input.action === 'in') {
        if (existing && existing.check_in_at) return { record: existing, already: true };
        if (working && nowD >= L.istInstant(date, settings.leave)) {
          throw err('shift_over', 'The shift is over for today, so you can no longer check in.');
        }
        const shift = shiftOf(settings);
        const derived = L.computeRecordTimes({
          date, shift, checkInAt: nowD, checkOutAt: null, working, prevLate: null, prevEarly: null,
        });
        const record = {
          employee_id: caller.uid,
          employee_name: caller.name,
          date,
          month,
          shift,
          check_in_at: ts(nowD),
          check_out_at: null,
          check_in_local: derived.check_in_local,
          check_out_local: null,
          check_in_geo: geo,
          check_out_geo: null,
          worked_minutes: null,
          late_minutes: derived.late_minutes,
          early_minutes: 0,
          late: derived.late,
          early: derived.early,
          needs_review: derived.needs_review,
          source: 'self',
          admin_edited: false,
          created_at: ts(nowD),
          updated_at: ts(nowD),
        };
        tx.set(recRef, record);
        tx.set(devRef, { employee_id: caller.uid, date });
        return { record, already: false };
      }

      // action === 'out'
      if (!existing || !existing.check_in_at) {
        throw err('not_checked_in', 'You have not checked in today.');
      }
      if (existing.admin_edited) {
        throw err('locked_by_admin', 'An administrator has edited today\'s attendance, so it can no longer be changed here.');
      }
      if (existing.early && (existing.early.status === 'approved' || existing.early.status === 'rejected')) {
        throw err('already_decided', 'Your early leave has already been reviewed.');
      }
      const inAt = L.toDateObj(existing.check_in_at);
      if (nowD.getTime() - inAt.getTime() < L.MIN_CHECKOUT_GAP_MS) {
        throw err('too_soon', 'You checked in less than a minute ago. Wait a moment before checking out.');
      }
      const derived = L.computeRecordTimes({
        date, shift: existing.shift, checkInAt: inAt, checkOutAt: nowD, working,
        prevLate: existing.late, prevEarly: existing.early,
      });
      // Only the check-out changed, so the check-in side (late, its note and
      // decision) stays exactly as it was, even if the day has since become a
      // holiday or stopped being one.
      const record = {
        ...existing,
        check_out_at: ts(nowD),
        check_out_local: derived.check_out_local,
        check_out_geo: geo,
        worked_minutes: derived.worked_minutes,
        early_minutes: derived.early_minutes,
        early: derived.early,
        needs_review: L.needsReview(existing.late, derived.early),
        updated_at: ts(nowD),
      };
      tx.set(recRef, record);
      if (!devSnap.exists) tx.set(devRef, { employee_id: caller.uid, date });
      return { record, already: false };
    });
    return { record: serialize(result.record), already: result.already };
  });

  // ───────────── notes and review ─────────────

  const submitNote = wrap(async (data, caller) => {
    const date = L.requireDate(data.date);
    const kind = L.requireKind(data.kind);
    const note = L.requireText(data.note, 3, 500, 'Note');
    const nowD = now();
    const ref = col('attendance').doc(recordId(caller.uid, date));
    const record = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const rec = snap.exists ? snap.data() : null;
      const review = rec && rec[kind];
      if (!review || (review.status !== 'needs_note' && review.status !== 'pending')) {
        throw err('note_not_allowed', 'A note cannot be added to this record.');
      }
      const next = { ...rec, [kind]: { ...review, status: 'pending', note }, updated_at: ts(nowD) };
      next.needs_review = L.needsReview(next.late, next.early);
      tx.set(ref, next);
      return next;
    });
    return { record: serialize(record) };
  });

  const review = wrap(async (data, caller) => {
    const employeeId = L.requireEmployeeId(data.employee_id);
    const date = L.requireDate(data.date);
    const kind = L.requireKind(data.kind);
    if (data.decision !== 'approved' && data.decision !== 'rejected') {
      throw err('invalid_input', "Decision must be 'approved' or 'rejected'.");
    }
    let comment = null;
    if (data.comment !== undefined && data.comment !== null) {
      if (typeof data.comment !== 'string' || data.comment.trim().length > 300) {
        throw err('invalid_input', 'Comment must be at most 300 characters.');
      }
      comment = data.comment.trim() || null;
    }
    if (employeeId === caller.uid) {
      const employees = await loadEmployees();
      const otherAdmin = employees.some((e) => e.id !== caller.uid && e.role === 'ADMIN' && isActiveEmployee(e));
      if (otherAdmin) throw err('self_review', 'You cannot decide your own request. Ask another administrator.');
    }
    const nowD = now();
    const ref = col('attendance').doc(recordId(employeeId, date));
    const record = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const rec = snap.exists ? snap.data() : null;
      const item = rec && rec[kind];
      if (!item || item.status !== 'pending') {
        throw err('not_pending', 'This request is no longer waiting for a decision.');
      }
      const next = {
        ...rec,
        [kind]: {
          ...item, status: data.decision, decided_by: caller.uid, decided_by_name: caller.name,
          decided_at: ts(nowD), comment,
        },
        updated_at: ts(nowD),
      };
      next.needs_review = L.needsReview(next.late, next.early);
      tx.set(ref, next);
      tx.set(col('attendance_audit').doc(), {
        action: `review_${data.decision}`, employee_id: employeeId, date, kind,
        before: item, after: next[kind], reason: comment, by: caller.uid, by_name: caller.name, at: ts(nowD),
      });
      return next;
    });
    return { record: serialize(record) };
  }, { admin: true });

  const listApprovals = wrap(async () => {
    const nowD = now();
    const { date: today, minutes: nowMinutes } = L.istParts(nowD);
    const windowStart = L.addDays(today, -31);
    const months = [...new Set([windowStart.slice(0, 7), L.addDays(today, -1).slice(0, 7)])];
    const [settings, holidays, snap, employees, ...monthSnaps] = await Promise.all([
      loadSettings(), loadHolidays(), col('attendance').where('needs_review', '==', true).get(),
      loadEmployees(), ...months.map((m) => col('attendance').where('month', '==', m).get()),
    ]);
    const items = [];
    for (const d of snap.docs) {
      const rec = d.data();
      if (!rec.needs_review) continue;
      if (L.dayType(rec.date, holidays, settings.weekly_off_history).type !== 'working') continue;
      for (const kind of ['late', 'early']) {
        if (!rec[kind] || rec[kind].status !== 'pending') continue;
        items.push({
          employee_id: rec.employee_id,
          employee_name: rec.employee_name,
          date: rec.date,
          kind,
          minutes: kind === 'late' ? rec.late_minutes : rec.early_minutes,
          note: rec[kind].note,
          expected: kind === 'late' ? rec.shift.arrival : rec.shift.leave,
          actual: kind === 'late' ? rec.check_in_local : rec.check_out_local,
        });
      }
    }
    items.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1
      : String(a.employee_name).localeCompare(String(b.employee_name))));
    const empById = new Map(employees.map((e) => [e.id, e]));
    const missed = [];
    for (const ms of monthSnaps) {
      for (const d of ms.docs) {
        const rec = d.data();
        if (rec.date < windowStart || rec.date >= today) continue;
        const emp = empById.get(rec.employee_id);
        if (!emp || !isEligibleEmployee(emp)) continue;
        const c = L.classifyDay({
          date: rec.date, today, nowMinutes, settings, holidays, record: rec,
          rangeStart: L.rangeStartFor(settings, joinDateOf(emp)),
        });
        if (c.kind !== 'missed_checkout') continue;
        missed.push({
          employee_id: rec.employee_id, employee_name: rec.employee_name || emp.name || '',
          date: rec.date, check_in: rec.check_in_local,
        });
      }
    }
    missed.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1
      : String(a.employee_name).localeCompare(String(b.employee_name))));
    return { items, missed_checkouts: missed };
  }, { admin: true });

  // ───────────── admin edit ─────────────

  const adminEdit = wrap(async (data, caller) => {
    const employeeId = L.requireEmployeeId(data.employee_id);
    const date = L.requireDate(data.date);
    const reason = L.requireText(data.reason, 3, 300, 'Reason');
    const norm = (v, label) => {
      if (v === null || v === undefined) return null;
      if (!L.isValidTime(v)) throw err('invalid_input', `${label} must look like 09:30, or be empty.`);
      return v;
    };
    const inStr = norm(data.check_in, 'Check-in time');
    const outStr = norm(data.check_out, 'Check-out time');
    const nowD = now();
    const { date: today } = L.istParts(nowD);
    if (date > today) throw err('invalid_input', 'You cannot edit attendance for a future date.');
    if (outStr && !inStr) throw err('invalid_input', 'A check-out needs a check-in.');
    if (inStr && outStr && L.minutesOf(outStr) <= L.minutesOf(inStr)) {
      throw err('invalid_input', 'Check-out must be after check-in.');
    }
    const inInstant = inStr ? L.istInstant(date, inStr) : null;
    const outInstant = outStr ? L.istInstant(date, outStr) : null;
    if (date === today && ((inInstant && inInstant > nowD) || (outInstant && outInstant > nowD))) {
      throw err('invalid_input', 'Times today cannot be in the future.');
    }
    const empSnap = await col('employees').doc(employeeId).get();
    if (!empSnap.exists) throw err('employee_not_found', 'That employee does not exist.');
    const emp = empSnap.data();
    const [settings, holidays] = await Promise.all([loadSettings(), loadHolidays()]);
    const working = L.dayType(date, holidays, settings.weekly_off_history).type === 'working';
    const ref = col('attendance').doc(recordId(employeeId, date));

    const record = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const existing = snap.exists ? snap.data() : null;
      const auditBase = {
        action: 'admin_edit', employee_id: employeeId, date, before: existing, reason,
        by: caller.uid, by_name: caller.name, at: ts(nowD),
      };
      if (!inStr) {
        if (existing) tx.delete(ref);
        tx.set(col('attendance_audit').doc(), { ...auditBase, action: 'admin_delete', after: null });
        return null;
      }
      const shift = existing && existing.shift ? existing.shift : shiftOf(settings);
      // Unchanged times keep their original instant (and GPS) so seconds are not lost.
      const keepIn = existing && existing.check_in_at && existing.check_in_local === inStr;
      const keepOut = existing && existing.check_out_at && existing.check_out_local === outStr;
      const inAt = keepIn ? L.toDateObj(existing.check_in_at) : inInstant;
      const outAt = outStr ? (keepOut ? L.toDateObj(existing.check_out_at) : outInstant) : null;
      const derived = L.computeRecordTimes({
        date, shift, checkInAt: inAt, checkOutAt: outAt, working,
        prevLate: existing && existing.late, prevEarly: existing && existing.early,
      });
      const next = {
        employee_id: employeeId,
        employee_name: emp.name || (existing && existing.employee_name) || '',
        date,
        month: date.slice(0, 7),
        shift,
        check_in_at: ts(inAt),
        check_out_at: ts(outAt),
        check_in_local: derived.check_in_local,
        check_out_local: derived.check_out_local,
        check_in_geo: keepIn ? existing.check_in_geo : null,
        check_out_geo: keepOut ? existing.check_out_geo : null,
        worked_minutes: derived.worked_minutes,
        late_minutes: derived.late_minutes,
        early_minutes: derived.early_minutes,
        late: derived.late,
        early: derived.early,
        needs_review: derived.needs_review,
        source: !existing || existing.source === 'admin' ? 'admin' : 'mixed',
        admin_edited: true,
        created_at: (existing && existing.created_at) || ts(nowD),
        updated_at: ts(nowD),
      };
      tx.set(ref, next);
      tx.set(col('attendance_audit').doc(), { ...auditBase, after: next });
      return next;
    });
    return { record: serialize(record) };
  }, { admin: true });

  // ───────────── settings ─────────────

  const getSettings = wrap(async () => ({ settings: settingsOut(await loadSettings()) }), { admin: true });

  const saveSettings = wrap(async (data, caller) => {
    const v = L.validateSettingsInput(data);
    const nowD = now();
    const { date: today } = L.istParts(nowD);
    const ref = configRef();
    const saved = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const existing = snap.exists ? snap.data() : null;
      const before = L.normalizeSettings(existing);
      const history = existing
        ? L.applyWeeklyOffChange(before.weekly_off_history, v.weekly_off, today)
        : [{ from: today, days: v.weekly_off }];
      const doc = {
        office: v.office,
        radius_m: v.radius_m,
        max_accuracy_m: v.max_accuracy_m,
        arrival: v.arrival,
        leave: v.leave,
        grace_minutes: v.grace_minutes,
        full_day_minutes: v.full_day_minutes ?? before.full_day_minutes,
        weekly_off_history: history,
        started_on: before.started_on || today,
        updated_by: caller.uid,
        updated_at: ts(nowD),
      };
      tx.set(ref, doc);
      tx.set(col('attendance_audit').doc(), {
        action: 'settings_save', employee_id: null, date: today, before: existing, after: doc,
        reason: null, by: caller.uid, by_name: caller.name, at: ts(nowD),
      });
      return doc;
    });
    return { settings: settingsOut(L.normalizeSettings(saved)) };
  }, { admin: true });

  // ───────────── holidays ─────────────

  const listHolidays = wrap(async (data) => {
    const year = data.year;
    if (!Number.isInteger(year) || year < 2000 || year > 2100) {
      throw err('invalid_input', 'Year must be a whole number such as 2026.');
    }
    const holidays = await loadHolidays();
    const prefix = `${year}-`;
    const list = Object.entries(holidays)
      .filter(([d]) => d.startsWith(prefix))
      .map(([date, name]) => ({ date, name }))
      .sort((a, b) => (a.date < b.date ? -1 : 1));
    return { holidays: list };
  });

  const setHoliday = wrap(async (data, caller) => {
    const date = L.requireDate(data.date);
    const name = L.requireText(data.name, 2, 60, 'Holiday name');
    const nowD = now();
    const ref = col('attendance_holidays').doc(date);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const existing = snap.exists ? snap.data() : null;
      const doc = {
        date, name,
        created_by: existing ? existing.created_by : caller.uid,
        created_at: existing ? existing.created_at : ts(nowD),
      };
      tx.set(ref, doc);
      tx.set(col('attendance_audit').doc(), {
        action: existing ? 'holiday_rename' : 'holiday_set', employee_id: null, date,
        before: existing, after: doc, reason: null, by: caller.uid, by_name: caller.name, at: ts(nowD),
      });
    });
    return { holiday: { date, name } };
  }, { admin: true });

  const removeHoliday = wrap(async (data, caller) => {
    const date = L.requireDate(data.date);
    const nowD = now();
    const ref = col('attendance_holidays').doc(date);
    const removed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      tx.delete(ref);
      tx.set(col('attendance_audit').doc(), {
        action: 'holiday_remove', employee_id: null, date, before: snap.data(), after: null,
        reason: null, by: caller.uid, by_name: caller.name, at: ts(nowD),
      });
      return true;
    });
    return { removed };
  }, { admin: true });

  // ───────────── month and team views ─────────────

  const month = wrap(async (data, caller) => {
    if (!L.isValidMonth(data.month)) throw err('invalid_input', 'Month must look like 2026-03.');
    let targetId = caller.uid;
    if (data.employee_id !== undefined && data.employee_id !== null && data.employee_id !== caller.uid) {
      if (typeof data.employee_id !== 'string' || !data.employee_id) {
        throw err('invalid_input', 'Employee is not valid.');
      }
      if (caller.data.role !== 'ADMIN') throw err('admin_only', 'You can only view your own attendance.');
      targetId = data.employee_id;
    }
    const { employees, built } = await monthForAll(data.month);
    const emp = employees.find((e) => e.id === targetId);
    if (!emp) throw err('employee_not_found', 'That employee does not exist.');
    const { summary, days } = built.get(targetId);
    return {
      summary,
      days: days.map((d) => ({ ...d, record: serialize(d.record) })),
    };
  });

  const teamDay = wrap(async (data) => {
    const date = L.requireDate(data.date);
    const nowD = now();
    const { date: today, minutes: nowMinutes } = L.istParts(nowD);
    const [settings, holidays, employees, snap] = await Promise.all([
      loadSettings(), loadHolidays(), loadEmployees(), col('attendance').where('date', '==', date).get(),
    ]);
    const byEmp = {};
    snap.docs.forEach((d) => { byEmp[d.data().employee_id] = d.data(); });
    const dt = L.dayType(date, holidays, settings.weekly_off_history);
    const rows = employees
      .filter(isEligibleEmployee)
      .sort((a, b) => String(a.name).localeCompare(String(b.name)))
      .map((emp) => {
        const record = byEmp[emp.id] || null;
        const c = L.classifyDay({
          date, today, nowMinutes, settings, holidays, record,
          rangeStart: L.rangeStartFor(settings, joinDateOf(emp)),
        });
        return {
          employee_id: emp.id, name: emp.name || '', avatar_url: emp.avatar_url || '',
          status: c.status, kind: c.kind, record: serialize(record),
        };
      });
    return { date, day: { type: dt.type, holiday_name: dt.holiday_name }, rows };
  }, { admin: true });

  const teamMonth = wrap(async (data) => {
    if (!L.isValidMonth(data.month)) throw err('invalid_input', 'Month must look like 2026-03.');
    const { employees, built } = await monthForAll(data.month);
    const rows = employees.filter(isEligibleEmployee).map((emp) => ({
      employee_id: emp.id, name: emp.name || '', summary: built.get(emp.id).summary,
    }));
    rows.sort((a, b) => {
      const ra = a.summary.rank;
      const rb = b.summary.rank;
      if (ra === null && rb === null) return String(a.name).localeCompare(String(b.name));
      if (ra === null) return 1;
      if (rb === null) return -1;
      return (ra - rb) || String(a.name).localeCompare(String(b.name));
    });
    return { rows };
  }, { admin: true });

  return {
    attendanceGetToday: getToday,
    attendanceMark: mark,
    attendanceSubmitNote: submitNote,
    attendanceMonth: month,
    attendanceTeamDay: teamDay,
    attendanceTeamMonth: teamMonth,
    attendanceListApprovals: listApprovals,
    attendanceReview: review,
    attendanceAdminEdit: adminEdit,
    attendanceGetSettings: getSettings,
    attendanceSaveSettings: saveSettings,
    attendanceListHolidays: listHolidays,
    attendanceSetHoliday: setHoliday,
    attendanceRemoveHoliday: removeHoliday,
  };
}
