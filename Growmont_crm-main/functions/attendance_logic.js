/**
 * Attendance: pure logic. No Firebase imports, no clock reads: `now` is always
 * passed in. Office time is the constant Asia/Kolkata (UTC+05:30, no DST), so
 * all date maths is done with a fixed offset rather than Intl, which keeps it
 * deterministic and dependency free.
 */

export const OFFICE_TZ = 'Asia/Kolkata';
const IST_OFFSET_MS = 330 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

export const MAX_POSITION_AGE_MS = 120000;
export const MIN_CHECKOUT_GAP_MS = 60000;

export const DEFAULT_SETTINGS = Object.freeze({
  office: null,
  radius_m: 10,
  max_accuracy_m: 25,
  arrival: '10:00',
  leave: '19:00',
  grace_minutes: 15,
  full_day_minutes: 360,
  weekly_off_history: [{ from: '1970-01-01', days: [7] }],
  started_on: null,
});

export class AttendanceError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = 'AttendanceError';
    this.code = code;
    this.details = details;
  }
}

const fail = (code, message, details) => {
  throw new AttendanceError(code, message, details);
};
const invalid = (message) => fail('invalid_input', message);

// ───────────────────────── date and time ─────────────────────────

const pad = (n, w = 2) => String(n).padStart(w, '0');
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;
const MONTH_RE = /^(\d{4})-(0[1-9]|1[0-2])$/;

export function isValidDate(s) {
  if (typeof s !== 'string') return false;
  const m = DATE_RE.exec(s);
  if (!m) return false;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  if (y < 1970 || y > 2999) return false;
  const t = new Date(Date.UTC(y, mo - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === mo - 1 && t.getUTCDate() === d;
}

export function isValidTime(s) {
  return typeof s === 'string' && TIME_RE.test(s);
}

export function isValidMonth(s) {
  if (typeof s !== 'string') return false;
  const m = MONTH_RE.exec(s);
  if (!m) return false;
  const y = Number(m[1]);
  return y >= 1970 && y <= 2999;
}

export function minutesOf(hhmm) {
  const m = TIME_RE.exec(hhmm);
  return Number(m[1]) * 60 + Number(m[2]);
}

/** Office-local {date, time, month, minutes, seconds} for an instant. */
export function istParts(instant) {
  const t = new Date(instant.getTime() + IST_OFFSET_MS);
  const date = `${pad(t.getUTCFullYear(), 4)}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
  const h = t.getUTCHours();
  const mi = t.getUTCMinutes();
  return {
    date,
    month: date.slice(0, 7),
    time: `${pad(h)}:${pad(mi)}`,
    minutes: h * 60 + mi,
    seconds: t.getUTCSeconds(),
  };
}

/** The instant at which office-local `HH:mm` on `date` happens. */
export function istInstant(date, hhmm) {
  const [y, mo, d] = date.split('-').map(Number);
  const [h, mi] = hhmm.split(':').map(Number);
  return new Date(Date.UTC(y, mo - 1, d, h, mi) - IST_OFFSET_MS);
}

export function addDays(date, n) {
  const [y, mo, d] = date.split('-').map(Number);
  const t = new Date(Date.UTC(y, mo - 1, d + n));
  return `${pad(t.getUTCFullYear(), 4)}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

/** ISO weekday of a date string: 1 = Monday ... 7 = Sunday. */
export function isoWeekday(date) {
  const [y, mo, d] = date.split('-').map(Number);
  const w = new Date(Date.UTC(y, mo - 1, d)).getUTCDay();
  return w === 0 ? 7 : w;
}

export function daysInMonth(month) {
  const [y, mo] = month.split('-').map(Number);
  return new Date(Date.UTC(y, mo, 0)).getUTCDate();
}

export function monthRange(month) {
  return { first: `${month}-01`, last: `${month}-${pad(daysInMonth(month))}` };
}

export function monthDates(month) {
  const n = daysInMonth(month);
  const out = [];
  for (let i = 1; i <= n; i += 1) out.push(`${month}-${pad(i)}`);
  return out;
}

/** Converts Date | Firestore Timestamp | {seconds} to a Date, else null. */
export function toDateObj(v) {
  if (v == null) return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v;
  if (typeof v.toDate === 'function') return toDateObj(v.toDate());
  const secs = v._seconds ?? v.seconds;
  if (typeof secs === 'number') return new Date(secs * 1000);
  return null;
}

// ───────────────────────── location ─────────────────────────

export function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const rad = (x) => (x * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Inside the fence when distance <= radius (the boundary is inside). */
export function isWithinRadius(distanceM, radiusM) {
  return distanceM <= radiusM;
}

export function isValidCoordinate(lat, lng) {
  return (
    typeof lat === 'number' && typeof lng === 'number' &&
    Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
  );
}

// ───────────────────────── settings ─────────────────────────

function cleanDays(days) {
  if (!Array.isArray(days)) return [7];
  const set = [...new Set(days.filter((d) => Number.isInteger(d) && d >= 1 && d <= 7))];
  return set.sort((a, b) => a - b);
}

/** Stored settings document (or null) merged over the defaults. */
export function normalizeSettings(raw) {
  const s = raw || {};
  let history = Array.isArray(s.weekly_off_history)
    ? s.weekly_off_history
        .filter((e) => e && isValidDate(e.from))
        .map((e) => ({ from: e.from, days: cleanDays(e.days) }))
    : [];
  if (history.length === 0) history = DEFAULT_SETTINGS.weekly_off_history.map((e) => ({ ...e }));
  history.sort((a, b) => (a.from < b.from ? -1 : a.from > b.from ? 1 : 0));
  return {
    office: s.office && isValidCoordinate(s.office.lat, s.office.lng)
      ? { lat: s.office.lat, lng: s.office.lng } : null,
    radius_m: Number.isInteger(s.radius_m) ? s.radius_m : DEFAULT_SETTINGS.radius_m,
    max_accuracy_m: Number.isInteger(s.max_accuracy_m) ? s.max_accuracy_m : DEFAULT_SETTINGS.max_accuracy_m,
    arrival: isValidTime(s.arrival) ? s.arrival : DEFAULT_SETTINGS.arrival,
    leave: isValidTime(s.leave) ? s.leave : DEFAULT_SETTINGS.leave,
    grace_minutes: Number.isInteger(s.grace_minutes) ? s.grace_minutes : DEFAULT_SETTINGS.grace_minutes,
    full_day_minutes: Number.isInteger(s.full_day_minutes) && s.full_day_minutes >= 60 && s.full_day_minutes <= 1440
      ? s.full_day_minutes : DEFAULT_SETTINGS.full_day_minutes,
    weekly_off_history: history,
    started_on: isValidDate(s.started_on) ? s.started_on : null,
    updated_by: s.updated_by ?? null,
    updated_at: s.updated_at ?? null,
  };
}

const intIn = (v, lo, hi, label) => {
  if (!Number.isInteger(v) || v < lo || v > hi) invalid(`${label} must be a whole number from ${lo} to ${hi}.`);
  return v;
};

/** Validates attendanceSaveSettings input; returns the normalized values. */
export function validateSettingsInput(input) {
  const d = input && typeof input === 'object' ? input : {};
  let office;
  if (d.office === null) {
    office = null;
  } else if (d.office && typeof d.office === 'object' && !Array.isArray(d.office)) {
    const { lat, lng } = d.office;
    if (!isValidCoordinate(lat, lng)) {
      invalid('Office location must be a latitude from -90 to 90 and a longitude from -180 to 180.');
    }
    if (lat === 0 && lng === 0) invalid('Office location cannot be 0, 0. Pick the real office position.');
    office = { lat, lng };
  } else {
    invalid('Office location must be set, or explicitly cleared.');
  }
  const radius_m = intIn(d.radius_m, 10, 500, 'Radius');
  const max_accuracy_m = intIn(d.max_accuracy_m, 5, 100, 'Maximum GPS accuracy');
  const grace_minutes = intIn(d.grace_minutes, 0, 60, 'Grace period');
  // Optional: absent (undefined) keeps the stored value; anything else must be valid.
  const full_day_minutes = d.full_day_minutes === undefined
    ? undefined : intIn(d.full_day_minutes, 60, 1440, 'Full-day hours');
  if (!isValidTime(d.arrival)) invalid('Arrival time must look like 10:00.');
  if (!isValidTime(d.leave)) invalid('Leave time must look like 19:00.');
  if (minutesOf(d.leave) - minutesOf(d.arrival) < 60) {
    invalid('Leave time must be at least 60 minutes after arrival time.');
  }
  if (!Array.isArray(d.weekly_off) || d.weekly_off.some((x) => !Number.isInteger(x) || x < 1 || x > 7)) {
    invalid('Weekly off days must be numbers from 1 (Monday) to 7 (Sunday).');
  }
  const weekly_off = cleanDays(d.weekly_off);
  if (weekly_off.length >= 7) invalid('At least one day of the week must be a working day.');
  return {
    office, radius_m, max_accuracy_m, arrival: d.arrival, leave: d.leave, grace_minutes, full_day_minutes, weekly_off,
  };
}

/** Weekly-off days in force on `date` according to the history. */
export function weeklyOffFor(history, date) {
  if (!Array.isArray(history) || history.length === 0) return [7];
  const sorted = [...history].sort((a, b) => (a.from < b.from ? -1 : a.from > b.from ? 1 : 0));
  let chosen = sorted[0];
  for (const e of sorted) {
    if (e.from <= date) chosen = e;
  }
  return chosen.days;
}

/** New history after saving `days` today. Past entries are never touched. */
export function applyWeeklyOffChange(history, days, today) {
  const next = (history || []).map((e) => ({ from: e.from, days: [...e.days] }));
  const sameSet = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
  if (next.length === 0) return [{ from: today, days }];
  const current = weeklyOffFor(next, today);
  if (sameSet(current, days)) return next;
  const last = next[next.length - 1];
  if (last.from === today) {
    last.days = days;
    return next;
  }
  next.push({ from: today, days });
  return next;
}

/** {type:'working'|'holiday'|'weekly_off', holiday_name}. Holidays win. */
export function dayType(date, holidays, history) {
  const name = holidays && Object.prototype.hasOwnProperty.call(holidays, date) ? holidays[date] : undefined;
  if (name !== undefined) return { type: 'holiday', holiday_name: name };
  if (weeklyOffFor(history, date).includes(isoWeekday(date))) return { type: 'weekly_off', holiday_name: null };
  return { type: 'working', holiday_name: null };
}

// ───────────────────────── marking ─────────────────────────

/** Shape and type validation of attendanceMark input. */
export function validateMarkInput(data) {
  const d = data && typeof data === 'object' ? data : {};
  if (d.action !== 'in' && d.action !== 'out') invalid("Action must be 'in' or 'out'.");
  if (!isValidCoordinate(d.lat, d.lng)) invalid('Your location could not be read. Try again.');
  if (typeof d.accuracy_m !== 'number' || !Number.isFinite(d.accuracy_m) || d.accuracy_m < 0) {
    invalid('GPS accuracy is missing or invalid.');
  }
  if (typeof d.is_mocked !== 'boolean') invalid('Location source information is missing.');
  if (typeof d.position_age_ms !== 'number' || !Number.isFinite(d.position_age_ms)) {
    invalid('Location age is missing or invalid.');
  }
  const device = typeof d.device_id === 'string' ? d.device_id.trim() : '';
  if (!device || device.length > 128 || device.includes('/')) invalid('This device could not be identified.');
  return {
    action: d.action,
    lat: d.lat,
    lng: d.lng,
    accuracy_m: d.accuracy_m,
    is_mocked: d.is_mocked,
    position_age_ms: d.position_age_ms,
    device_id: device,
    biometric_passed: d.biometric_passed,
  };
}

/** Policy checks shared by mark in and out. Returns the distance in metres. */
export function checkMarkPolicy(input, settings) {
  if (!settings.office) {
    fail('not_configured', 'Attendance has not been set up yet. Ask an administrator to set the office location.');
  }
  if (input.is_mocked) fail('mock_location', 'A mock location was detected. Turn it off and try again.');
  if (input.biometric_passed !== true) {
    fail('biometric_required', 'Fingerprint or face verification is required to mark attendance.');
  }
  if (input.position_age_ms < 0 || input.position_age_ms > MAX_POSITION_AGE_MS) {
    fail('stale_location', 'Your location is out of date. Wait for a fresh GPS fix and try again.');
  }
  if (input.accuracy_m > settings.max_accuracy_m) {
    fail('poor_accuracy', `GPS accuracy is too low (${Math.round(input.accuracy_m)} m). Move to an open area and try again.`,
      { accuracy_m: input.accuracy_m, max_accuracy_m: settings.max_accuracy_m });
  }
  const distance = haversineMeters(input.lat, input.lng, settings.office.lat, settings.office.lng);
  if (!isWithinRadius(distance, settings.radius_m)) {
    fail('outside_radius', `You are ${Math.round(distance)} m from the office. You must be within ${settings.radius_m} m.`,
      { distance_m: Math.round(distance * 10) / 10, radius_m: settings.radius_m });
  }
  return distance;
}

// ───────────────────────── lateness ─────────────────────────

export const emptyReview = () => ({
  status: 'none', note: null, decided_by: null, decided_by_name: null, decided_at: null, comment: null,
});

/** Late iff strictly after arrival + grace; minutes are ceil'd from arrival. */
export function evaluateLate(checkInAt, date, shift) {
  const arrival = istInstant(date, shift.arrival).getTime();
  const threshold = arrival + shift.grace_minutes * MINUTE_MS;
  const t = checkInAt.getTime();
  if (t <= threshold) return { late: false, minutes: 0 };
  return { late: true, minutes: Math.ceil((t - arrival) / MINUTE_MS) };
}

/** Early iff strictly before leave - grace; minutes are ceil'd from leave. */
export function evaluateEarly(checkOutAt, date, shift) {
  const leave = istInstant(date, shift.leave).getTime();
  const threshold = leave - shift.grace_minutes * MINUTE_MS;
  const t = checkOutAt.getTime();
  if (t >= threshold) return { early: false, minutes: 0 };
  return { early: true, minutes: Math.ceil((leave - t) / MINUTE_MS) };
}

/** Review state after a recompute: cleared if fine, needs_note if newly flagged, else kept. */
export function nextReview(prev, flagged) {
  if (!flagged) return emptyReview();
  if (!prev || prev.status === 'none') return { ...emptyReview(), status: 'needs_note' };
  return { ...emptyReview(), ...prev };
}

export const needsReview = (late, early) =>
  Boolean((late && late.status === 'pending') || (early && early.status === 'pending'));

/**
 * Everything derived from the two instants. Off days never produce lateness.
 * prevLate / prevEarly are the existing review objects (or null).
 */
export function computeRecordTimes({ date, shift, checkInAt, checkOutAt, working, prevLate, prevEarly }) {
  const lateEval = working && checkInAt ? evaluateLate(checkInAt, date, shift) : { late: false, minutes: 0 };
  const earlyEval = working && checkOutAt ? evaluateEarly(checkOutAt, date, shift) : { early: false, minutes: 0 };
  const late = nextReview(prevLate, lateEval.late);
  const early = nextReview(prevEarly, earlyEval.early);
  return {
    check_in_local: checkInAt ? istParts(checkInAt).time : null,
    check_out_local: checkOutAt ? istParts(checkOutAt).time : null,
    worked_minutes: checkInAt && checkOutAt
      ? Math.floor((checkOutAt.getTime() - checkInAt.getTime()) / MINUTE_MS) : null,
    late_minutes: lateEval.minutes,
    early_minutes: earlyEval.minutes,
    late,
    early,
    needs_review: needsReview(late, early),
  };
}

// ───────────────────────── day classification and summaries ─────────────────────────

/** Latest of started_on and join date; null means nothing is counted yet. */
export function rangeStartFor(settings, joinDate) {
  if (!settings.started_on) return null;
  return joinDate && joinDate > settings.started_on ? joinDate : settings.started_on;
}

export const DEFAULT_FULL_DAY_MINUTES = 360;

/** Worked minutes of a record: the stored value, else derived from the instants, else null. */
export function workedMinutesOf(record) {
  if (!record) return null;
  if (typeof record.worked_minutes === 'number') return record.worked_minutes;
  const a = toDateObj(record.check_in_at);
  const b = toDateObj(record.check_out_at);
  return a && b ? Math.floor((b.getTime() - a.getTime()) / MINUTE_MS) : null;
}

/**
 * Minutes needed for a full day: min(full_day_minutes, shift leave - arrival).
 * Records written before the setting existed have no snapshot and use 360.
 */
export function fullDayThreshold(record, settings) {
  const shift = (record && record.shift) || {};
  const arrival = isValidTime(shift.arrival) ? shift.arrival : settings.arrival;
  const leave = isValidTime(shift.leave) ? shift.leave : settings.leave;
  const full = Number.isInteger(shift.full_day_minutes) ? shift.full_day_minutes : DEFAULT_FULL_DAY_MINUTES;
  return Math.min(full, minutesOf(leave) - minutesOf(arrival));
}

/** 'full' | 'half' for a record that has a check-out. */
export function creditOf(record, settings) {
  if (record.early && record.early.status === 'approved') return 'full';
  const worked = workedMinutesOf(record);
  return worked !== null && worked >= fullDayThreshold(record, settings) ? 'full' : 'half';
}

/**
 * Classifies one date for one employee.
 * `rangeStart` is the first counted date (null = nothing counted).
 * `kind` is evaluated at read time, so admin edits and decisions show at once.
 */
export function classifyDay({ date, today, nowMinutes, settings, holidays, record, rangeStart }) {
  const dt = dayType(date, holidays, settings.weekly_off_history);
  const hasIn = Boolean(record && record.check_in_at);
  const inRange = rangeStart != null && date >= rangeStart && date <= today;
  let counted = false;
  if (inRange && dt.type === 'working') {
    if (date < today) counted = true;
    else counted = Boolean(record) || nowMinutes >= minutesOf((record && record.shift && record.shift.leave) || settings.leave);
  }
  let status;
  if (hasIn) status = 'present';
  else if (dt.type !== 'working') status = 'off';
  else if (date > today) status = 'upcoming';
  else if (!inRange) status = 'off';
  else if (date === today && !counted) status = 'upcoming';
  else status = 'absent';

  let kind;
  if (hasIn) {
    if (dt.type !== 'working') kind = 'extra';
    else if (!record.check_out_at) kind = date < today ? 'missed_checkout' : 'in_progress';
    else kind = creditOf(record, settings);
  } else if (date > today) {
    kind = 'upcoming';
  } else if (!inRange) {
    kind = 'not_tracked';
  } else if (dt.type !== 'working') {
    kind = dt.type;
  } else {
    kind = status === 'absent' ? 'absent' : 'upcoming';
  }
  return { type: dt.type, holiday_name: dt.holiday_name, inRange, counted, hasIn, status, kind };
}

const UNEXCUSED = new Set(['needs_note', 'rejected']);

export function emptySummary(month) {
  return {
    month, working_days: 0, off_days: 0, present: 0, absent: 0, extra_days: 0,
    late: 0, early: 0, pending: 0, excused: 0, missed_checkout: 0,
    full_days: 0, half_days: 0, attended_value: 0,
    percent: null, stars: null, rank: null, ranked_of: null,
  };
}

/**
 * Month summary and per-day list for one employee.
 * `records` maps date -> record; `now` is a Date.
 */
export function buildMonth({ month, now, settings, holidays, records, joinDate }) {
  const { date: today, minutes: nowMinutes } = istParts(now);
  const { first } = monthRange(month);
  let rangeStart = rangeStartFor(settings, joinDate);
  if (rangeStart != null && rangeStart < first) rangeStart = first;
  const summary = emptySummary(month);
  const days = [];
  for (const date of monthDates(month)) {
    const record = records[date] || null;
    const c = classifyDay({ date, today, nowMinutes, settings, holidays, record, rangeStart });
    days.push({ date, type: c.type, holiday_name: c.holiday_name, status: c.status, kind: c.kind, record });
    if (!c.inRange) continue;
    if (c.type !== 'working') {
      summary.off_days += 1;
      if (c.hasIn) summary.extra_days += 1;
      continue;
    }
    if (!c.counted) continue;
    summary.working_days += 1;
    if (c.hasIn) summary.present += 1;
    else summary.absent += 1;
    if (c.kind === 'full') summary.full_days += 1;
    else if (c.kind === 'half' || c.kind === 'missed_checkout') summary.half_days += 1;
    else if (c.kind === 'in_progress') summary.attended_value += 1;
    if (record) {
      for (const kind of ['late', 'early']) {
        const st = record[kind] && record[kind].status;
        if (UNEXCUSED.has(st)) summary[kind] += 1;
        else if (st === 'pending') summary.pending += 1;
        else if (st === 'approved') summary.excused += 1;
      }
      if (c.hasIn && !record.check_out_at && date < today) summary.missed_checkout += 1;
    }
  }
  summary.attended_value += summary.full_days + 0.5 * summary.half_days;
  if (summary.working_days > 0) {
    summary.percent = Math.round((100 * summary.attended_value) / summary.working_days);
    summary.stars = Math.round((5 * summary.attended_value / summary.working_days) * 10) / 10;
  }
  return { summary, days };
}

/**
 * Standard competition ranking (1,1,3). items: {id, eligible, attended_value, late}
 * where `late` is unexcused late + early (`present` is accepted in place of
 * attended_value). Returns Map id -> {rank, ranked_of}.
 */
export function rankEmployees(items) {
  const val = (i) => (i.attended_value ?? i.present);
  const eligible = items.filter((i) => i.eligible);
  eligible.sort((a, b) => (val(b) - val(a)) || (a.late - b.late));
  const out = new Map();
  let rank = 0;
  eligible.forEach((item, idx) => {
    const prev = eligible[idx - 1];
    if (!prev || val(prev) !== val(item) || prev.late !== item.late) rank = idx + 1;
    out.set(item.id, { rank, ranked_of: eligible.length });
  });
  for (const i of items) {
    if (!out.has(i.id)) out.set(i.id, { rank: null, ranked_of: null });
  }
  return out;
}

// ───────────────────────── small input validators ─────────────────────────

export function requireDate(v, label = 'Date') {
  if (!isValidDate(v)) invalid(`${label} must be a valid date like 2026-03-15.`);
  return v;
}

export function requireText(v, min, max, label) {
  if (typeof v !== 'string') invalid(`${label} is required.`);
  const t = v.trim();
  if (t.length < min || t.length > max) invalid(`${label} must be ${min} to ${max} characters.`);
  return t;
}

/**
 * An employee id that is safe to use as a Firestore document id. Anything
 * else would make Firestore throw (a '/', '.', '..', '__x__', or a huge id)
 * and surface as an internal error instead of invalid_input.
 */
export function requireEmployeeId(v) {
  if (typeof v !== 'string' || !v || v.length > 128 || v.includes('/') || v === '.' || v === '..'
    || /^__.*__$/.test(v)) {
    invalid('An employee must be specified.');
  }
  return v;
}

export function requireKind(v) {
  if (v !== 'late' && v !== 'early') invalid("Kind must be 'late' or 'early'.");
  return v;
}
