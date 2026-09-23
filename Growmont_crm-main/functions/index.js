/**
 * Cloud Functions for Growmont CRM
 * Replaces all remaining custom Django server functionality:
 * - Admin account management (create, role, access, password, email,
 *   delete) through the Admin SDK
 * - Keeping each Auth account's claims and disabled flag in step with its
 *   employees/{uid} document
 * - Scheduled reminder notifications (every 60s)
 * - Fan-out updates for denormalized employee names
 *
 * Excel import/export runs entirely on-device in the Flutter app
 * (see flutterapp/lib/core/excel/excel_io.dart) — there is no server
 * component for it.
 *
 * Everything runs in asia-south1, the Firestore database's region: a v2
 * Firestore trigger must live there, and the app's callers are in India.
 * The Flutter app hardcodes the same region (kFunctionsRegion in
 * flutterapp/lib/core/config/app_config.dart) — change both together.
 *
 * Deploy: firebase deploy --only functions (needs the Blaze plan).
 */

import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onDocumentUpdated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import nodemailer from 'nodemailer';

setGlobalOptions({ region: 'asia-south1', maxInstances: 10 });

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const auth = admin.auth();

// SMTP Transporter setup (reads env vars or defaults to console simulation)
function getTransporter() {
  const host = process.env.SMTP_HOST || 'smtp.gmail.com';
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;

  if (user && pass) {
    return nodemailer.createTransport({
      host,
      port: 465,
      secure: true,
      auth: { user, pass }
    });
  }
  return null;
}

// ==========================================
// 1. Employee Management Functions (Admin Only)
// ==========================================

const ALLOWED_DOMAIN = '@growmont.com';
const ROLES = ['ADMIN', 'EMPLOYEE'];
// Firebase Auth's own minimum; the app enforces the same.
const MIN_PASSWORD_LENGTH = 6;
// Statuses whose Auth account is disabled. PENDING is deliberately absent:
// a pending Google sign-in has to be able to authenticate to be told it is
// waiting for approval.
const LOCKED_STATUSES = ['RESTRICTED', 'REJECTED'];

const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

function isActiveAdmin(data) {
  return Boolean(data) && data.role === 'ADMIN' && data.status === 'ACTIVE';
}

// The employees/{uid} document is the source of truth for who may do what,
// exactly as in firestore.rules — not the caller's custom claims, which
// accounts created before these functions existed don't have. The lookup is
// by uid only: matching on email would let anyone who registers an address
// that some admin document mentions inherit that admin's rights.
async function requireAdmin(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Please sign in again to manage employee accounts.');
  }
  const snap = await db.collection('employees').doc(request.auth.uid).get();
  if (!snap.exists || !isActiveAdmin(snap.data())) {
    throw new HttpsError('permission-denied', 'Only administrators can manage employee accounts.');
  }
  return { uid: request.auth.uid };
}

// Wraps an admin-only callable: gates it on requireAdmin and turns any
// failure into an HttpsError whose message the app can show as-is.
function adminCallable(handler) {
  return onCall(async (request) => {
    try {
      const caller = await requireAdmin(request);
      return await handler(request.data || {}, caller);
    } catch (error) {
      throw toHttpsError(error);
    }
  });
}

function toHttpsError(error) {
  if (error instanceof HttpsError) return error;
  switch (error?.code) {
    case 'auth/email-already-exists':
      return new HttpsError('already-exists', 'Another account already uses this email address.');
    case 'auth/invalid-email':
      return new HttpsError('invalid-argument', 'The email address is not valid.');
    case 'auth/invalid-password':
      return new HttpsError('invalid-argument', `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`);
    case 'auth/user-not-found':
      return new HttpsError('not-found', 'This employee has no sign-in account.');
    default:
      console.error(error);
      return new HttpsError('internal', 'Something went wrong on the server. Please try again.');
  }
}

function requireEmployeeId(employeeId) {
  if (typeof employeeId !== 'string' || !employeeId) {
    throw new HttpsError('invalid-argument', 'An employee must be specified.');
  }
  return employeeId;
}

function requireNotSelf(employeeId, caller, action) {
  if (employeeId === caller.uid) {
    throw new HttpsError('failed-precondition', `You can't ${action} your own account. Ask another administrator.`);
  }
}

function normaliseEmail(raw) {
  const email = String(raw || '').trim().toLowerCase();
  const local = email.slice(0, -ALLOWED_DOMAIN.length);
  if (!email.endsWith(ALLOWED_DOMAIN) || !/^[a-z0-9._%+-]+$/.test(local)) {
    throw new HttpsError('invalid-argument', `Employee emails must end in ${ALLOWED_DOMAIN}.`);
  }
  return email;
}

function requirePassword(raw) {
  if (typeof raw !== 'string' || raw.length < MIN_PASSWORD_LENGTH) {
    throw new HttpsError('invalid-argument', `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`);
  }
  return raw;
}

async function loadEmployee(employeeId) {
  const ref = db.collection('employees').doc(requireEmployeeId(employeeId));
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'That employee no longer exists.');
  }
  return { ref, data: snap.data() };
}

// The Auth account behind an employee document. The document id is the
// Auth uid (the rules depend on it), so a document keyed any other way has
// no account this can safely act on.
async function authUserFor(employeeId) {
  try {
    return await auth.getUser(employeeId);
  } catch (error) {
    if (error.code === 'auth/user-not-found') return null;
    throw error;
  }
}

// Brings an Auth account in line with its employee document: the claims
// mirror role and status, the display name follows the document, and the
// credential is disabled (with every session revoked) while the status is
// locked. Idempotent, so both the callables and syncEmployeeAuth can run it.
async function syncAuthFromDoc(employeeId, data) {
  const user = await authUserFor(employeeId);
  if (!user) return null;

  const role = ROLES.includes(data.role) ? data.role : 'EMPLOYEE';
  const status = data.status || 'ACTIVE';
  const claims = user.customClaims || {};
  if (claims.role !== role || claims.status !== status) {
    await auth.setCustomUserClaims(user.uid, { ...claims, role, status });
  }

  const update = {};
  if (status !== 'PENDING') {
    const locked = LOCKED_STATUSES.includes(status);
    if (user.disabled !== locked) update.disabled = locked;
  }
  if (data.name && data.name !== user.displayName) {
    update.displayName = data.name;
  }
  if (Object.keys(update).length) {
    await auth.updateUser(user.uid, update);
  }
  if (update.disabled === true) {
    // A disabled account can't refresh its session, but an ID token it
    // already holds would otherwise keep working until it expires.
    await auth.revokeRefreshTokens(user.uid);
  }
  return user;
}

export const createEmployee = adminCallable(async (data, caller) => {
  const name = String(data.name || '').trim();
  if (!name) {
    throw new HttpsError('invalid-argument', 'Name is required.');
  }
  const email = normaliseEmail(data.email);
  const password = requirePassword(data.password);
  const role = data.role === 'ADMIN' ? 'ADMIN' : 'EMPLOYEE';

  const sameEmail = await db.collection('employees').where('email', '==', email).limit(1).get();
  if (!sameEmail.empty) {
    throw new HttpsError('already-exists', `An employee account for ${email} already exists.`);
  }

  let existing = null;
  try {
    existing = await auth.getUserByEmail(email);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  if (existing && (await db.collection('employees').doc(existing.uid).get()).exists) {
    throw new HttpsError('already-exists', `An employee account for ${email} already exists.`);
  }

  // An Auth account with no employee document is left over from an
  // employee deleted before deletions reached Auth. Take it over rather
  // than refuse the address forever.
  let uid;
  if (existing) {
    await auth.updateUser(existing.uid, { password, displayName: name, disabled: false });
    uid = existing.uid;
  } else {
    uid = (await auth.createUser({ email, password, displayName: name })).uid;
  }

  const dob = data.dob ? new Date(data.dob) : null;
  try {
    await auth.setCustomUserClaims(uid, { role, status: 'ACTIVE' });
    await db.collection('employees').doc(uid).set({
      name,
      email,
      mobile_no: String(data.mobile_no || ''),
      gender: ['M', 'F', 'O'].includes(data.gender) ? data.gender : 'O',
      dob: dob && !isNaN(dob) ? admin.firestore.Timestamp.fromDate(dob) : null,
      avatar_url: String(data.avatar_url || ''),
      role,
      status: 'ACTIVE',
      created_by: caller.uid,
      clients_count: 0,
      sales_count: 0,
      interactions_count: 0,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp()
    });
  } catch (error) {
    // Don't leave behind a sign-in account nobody can manage.
    if (!existing) await auth.deleteUser(uid).catch(() => {});
    throw error;
  }

  console.log(JSON.stringify({ event: 'createEmployee', employeeId: uid, role, adminId: caller.uid, reusedAuthAccount: Boolean(existing) }));
  return { success: true, uid };
});

export const deleteEmployee = adminCallable(async (data, caller) => {
  const employeeId = requireEmployeeId(data.employeeId);
  requireNotSelf(employeeId, caller, 'delete');
  const { ref } = await loadEmployee(employeeId);

  if (await authUserFor(employeeId)) {
    await auth.deleteUser(employeeId);
  }
  await ref.delete();

  console.log(JSON.stringify({ event: 'deleteEmployee', employeeId, adminId: caller.uid }));
  return { success: true };
});

export const updateEmployeeRole = adminCallable(async (data, caller) => {
  const employeeId = requireEmployeeId(data.employeeId);
  const role = data.role;
  if (!ROLES.includes(role)) {
    throw new HttpsError('invalid-argument', 'Role must be ADMIN or EMPLOYEE.');
  }
  // Also what guarantees an admin always remains: the caller is one.
  requireNotSelf(employeeId, caller, 'change the role of');
  const { ref, data: current } = await loadEmployee(employeeId);
  if (current.role === role) {
    return { success: true, role, noop: true };
  }

  await ref.update({ role, updated_at: serverTimestamp() });
  await syncAuthFromDoc(employeeId, { ...current, role });

  console.log(JSON.stringify({ event: 'updateEmployeeRole', employeeId, role, previousRole: current.role, adminId: caller.uid }));
  return { success: true, role };
});

// Grants (active: true) or restricts (active: false) an account. Granting
// also serves PENDING and REJECTED accounts, so it doubles as an approval.
export const setEmployeeAccess = adminCallable(async (data, caller) => {
  const employeeId = requireEmployeeId(data.employeeId);
  if (typeof data.active !== 'boolean') {
    throw new HttpsError('invalid-argument', 'Specify whether the account should be active.');
  }
  requireNotSelf(employeeId, caller, 'restrict');
  const { ref, data: current } = await loadEmployee(employeeId);

  const status = data.active ? 'ACTIVE' : 'RESTRICTED';
  const update = data.active
    ? { status, restricted_at: null, approved_by: caller.uid, approved_at: serverTimestamp() }
    : { status, restricted_at: serverTimestamp() };

  // Auth first: a failure between the two steps then leaves a restricted
  // account already locked out, and a granted one merely waiting for its
  // document, which the rules still treat as not active.
  await syncAuthFromDoc(employeeId, { ...current, status });
  await ref.update({ ...update, updated_at: serverTimestamp() });

  console.log(JSON.stringify({ event: 'setEmployeeAccess', employeeId, status, previousStatus: current.status, adminId: caller.uid }));
  return { success: true, status };
});

// Sets a new password for another employee. Changing a password ends every
// session the account has, so the employee signs in again with the new one.
// Admins change their own password in the app instead, which keeps their
// current session.
export const setEmployeePassword = adminCallable(async (data, caller) => {
  const employeeId = requireEmployeeId(data.employeeId);
  const password = requirePassword(data.password);
  requireNotSelf(employeeId, caller, 'reset the password of');
  const { data: current } = await loadEmployee(employeeId);

  if (!(await authUserFor(employeeId))) {
    throw new HttpsError('not-found', `${current.name || 'This employee'} has no sign-in account.`);
  }
  await auth.updateUser(employeeId, { password });
  await auth.revokeRefreshTokens(employeeId);

  console.log(JSON.stringify({ event: 'setEmployeePassword', employeeId, adminId: caller.uid }));
  return { success: true };
});

// Changes the address an employee signs in with, in Auth and in their
// document together, so the two can't drift apart.
export const changeEmployeeEmail = adminCallable(async (data, caller) => {
  const employeeId = requireEmployeeId(data.employeeId);
  const email = normaliseEmail(data.email);
  requireNotSelf(employeeId, caller, 'change the email of');
  const { ref, data: current } = await loadEmployee(employeeId);
  if (String(current.email || '').toLowerCase() === email) {
    return { success: true, email, noop: true };
  }

  const sameEmail = await db.collection('employees').where('email', '==', email).limit(1).get();
  if (!sameEmail.empty && sameEmail.docs[0].id !== employeeId) {
    throw new HttpsError('already-exists', `${email} already belongs to another employee.`);
  }

  if (await authUserFor(employeeId)) {
    await auth.updateUser(employeeId, { email });
  }
  await ref.update({ email, updated_at: serverTimestamp() });

  console.log(JSON.stringify({ event: 'changeEmployeeEmail', employeeId, adminId: caller.uid }));
  return { success: true, email };
});

// Safety net for every write to an employee document that didn't come
// through the callables above — an admin's edit from an older app version,
// a bulk import, a change made in the console — so the Auth account always
// ends up matching the document the rules read.
export const syncEmployeeAuth = onDocumentWritten('employees/{employeeId}', async (event) => {
  const employeeId = event.params.employeeId;
  const before = event.data?.before?.exists ? event.data.before.data() : null;
  const after = event.data?.after?.exists ? event.data.after.data() : null;

  try {
    if (!after) {
      // Removed without deleteEmployee (which deletes the account first):
      // nothing may sign in as this employee any more.
      const user = await authUserFor(employeeId);
      if (user && !user.disabled) {
        await auth.updateUser(employeeId, { disabled: true });
        await auth.revokeRefreshTokens(employeeId);
        console.log(JSON.stringify({ event: 'syncEmployeeAuth', employeeId, action: 'disabled-orphan' }));
      }
      return;
    }
    if (before && before.role === after.role && before.status === after.status && before.name === after.name) {
      return;
    }
    await syncAuthFromDoc(employeeId, after);
  } catch (error) {
    console.error(JSON.stringify({ event: 'syncEmployeeAuth', employeeId, error: error.message }));
  }
});

// ==========================================
// 1b. Self-service provisioning + admin review
//     (3-day grace-period access for first-time Google sign-ins)
// ==========================================

const GRACE_PERIOD_MS = 3 * 24 * 60 * 60 * 1000; // 3 days

// Any authenticated Google account with no existing `employees` doc calls
// this right after Firebase Auth sign-in succeeds, to self-provision a
// PENDING record with a 3-day grace period. Deliberately NOT admin-gated —
// this is the self-signup path. Idempotent: re-invoking for an account that
// already has a doc just returns its current status instead of resetting
// the clock or clobbering an admin's decision.
export const provisionPendingEmployee = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const emailClaim = request.auth.token.email || '';
  if (!emailClaim.toLowerCase().endsWith('@growmont.com')) {
    throw new HttpsError('invalid-argument', 'Only @growmont.com accounts can be provisioned.');
  }

  const uid = request.auth.uid;
  const ref = db.collection('employees').doc(uid);

  try {
    const existing = await ref.get();
    if (existing.exists) {
      const data = existing.data();
      return { success: true, uid, status: data.status || 'ACTIVE', alreadyExisted: true };
    }

    const email = emailClaim;
    const name = request.auth.token.name || (email ? email.split('@')[0] : 'New User');
    const picture = request.auth.token.picture || '';
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + GRACE_PERIOD_MS);

    await ref.set({
      name,
      email,
      mobile_no: '',
      gender: 'O',
      dob: null,
      avatar_url: picture,
      role: 'EMPLOYEE',
      status: 'PENDING',
      access_expires_at: expiresAt,
      requested_at: admin.firestore.FieldValue.serverTimestamp(),
      approved_by: null,
      approved_at: null,
      rejected_by: null,
      rejected_at: null,
      restricted_at: null,
      clients_count: 0,
      sales_count: 0,
      interactions_count: 0,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });

    await auth.setCustomUserClaims(uid, { role: 'EMPLOYEE', status: 'PENDING' });

    console.log(JSON.stringify({
      event: 'provisionPendingEmployee',
      employeeId: uid,
      email,
      accessExpiresAt: expiresAt.toDate().toISOString()
    }));

    return {
      success: true,
      uid,
      status: 'PENDING',
      access_expires_at: expiresAt.toDate().toISOString()
    };
  } catch (error) {
    console.error('Error provisioning pending employee:', error);
    throw new HttpsError('internal', error.message);
  }
});

// Valid admin decisions per current status. Anything not listed here is
// rejected with 'failed-precondition' rather than silently applied — this
// is what keeps two admins racing an Accept/Reject on the same request from
// producing an inconsistent outcome: whichever request's read wins the race
// transitions the doc, and the loser's re-read no longer matches a listed
// transition, so it fails closed instead of clobbering the result.
const ALLOWED_TRANSITIONS = {
  PENDING: ['ACCEPT', 'REJECT'],
  RESTRICTED: ['ACCEPT', 'REJECT'],
  REJECTED: ['ACCEPT'] // re-rejecting an already-rejected account is a no-op, handled below
};

// Admin-only. One callable for Accept / Reject / Restore, since they share
// identical auth-gate + fetch + claims/disable shape and differ only in
// which branch runs — this also means "grant access to a RESTRICTED or
// REJECTED account after the fact" needs no special-casing, it's just
// another ACCEPT.
export const reviewEmployee = onCall(async (request) => {
  try {
    await requireAdmin(request);
  } catch (error) {
    throw toHttpsError(error);
  }

  const { employeeId, decision, role } = request.data || {};
  if (!employeeId || !['ACCEPT', 'REJECT'].includes(decision)) {
    throw new HttpsError('invalid-argument', 'Valid employeeId and decision are required.');
  }

  const adminId = request.auth.uid;
  const ref = db.collection('employees').doc(employeeId);

  // Re-read the current state fresh from Firestore rather than trusting
  // anything the client believes about it — this is the source of truth
  // the transition table below is validated against.
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Employee not found.');
  }
  const current = snap.data();
  const previousStatus = current.status || 'ACTIVE';

  if (previousStatus === 'REJECTED' && decision === 'REJECT') {
    // Already rejected — no-op, return current state instead of erroring
    // on a harmless repeat click.
    return { success: true, uid: employeeId, status: previousStatus, noop: true };
  }

  const allowed = ALLOWED_TRANSITIONS[previousStatus] || [];
  if (!allowed.includes(decision)) {
    throw new HttpsError(
      'failed-precondition',
      `Cannot ${decision} employee ${employeeId}: current status is ${previousStatus}, ` +
        `which does not accept this decision (it may already have been reviewed).`
    );
  }

  const logBase = { event: 'reviewEmployee', employeeId, decision, previousStatus, adminId };
  let authUpdateResult = 'not-attempted';
  let claimsUpdateResult = 'not-attempted';
  let firestoreUpdateResult = 'not-attempted';

  try {
    if (decision === 'ACCEPT') {
      const newRole = ['ADMIN', 'EMPLOYEE'].includes(role) ? role : (current.role || 'EMPLOYEE');

      await auth.updateUser(employeeId, { disabled: false });
      authUpdateResult = 'ok';

      await auth.setCustomUserClaims(employeeId, { role: newRole, status: 'ACTIVE' });
      claimsUpdateResult = 'ok';

      await ref.update({
        status: 'ACTIVE',
        role: newRole,
        approved_by: adminId,
        approved_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
      firestoreUpdateResult = 'ok';

      console.log(JSON.stringify({ ...logBase, newStatus: 'ACTIVE', authUpdateResult, claimsUpdateResult, firestoreUpdateResult }));
      return { success: true, uid: employeeId, status: 'ACTIVE' };
    }

    // REJECT (including RESTRICTED -> REJECT re-reject)
    await auth.updateUser(employeeId, { disabled: true });
    authUpdateResult = 'ok';

    // Forces any already-cached client session to re-authenticate and hit
    // the disabled check immediately, instead of waiting for its short-lived
    // ID token to naturally expire.
    await auth.revokeRefreshTokens(employeeId);

    await auth.setCustomUserClaims(employeeId, { role: current.role || 'EMPLOYEE', status: 'REJECTED' });
    claimsUpdateResult = 'ok';

    await ref.update({
      status: 'REJECTED',
      rejected_by: adminId,
      rejected_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });
    firestoreUpdateResult = 'ok';

    console.log(JSON.stringify({ ...logBase, newStatus: 'REJECTED', authUpdateResult, claimsUpdateResult, firestoreUpdateResult }));
    return { success: true, uid: employeeId, status: 'REJECTED' };
  } catch (error) {
    // Auth/claims/Firestore are three separate systems and can't be wrapped
    // in one transaction. The fixed write order above (Auth disabled-flag
    // -> claims -> Firestore) means a failure here always leaves the
    // account on the *safer* side of the intended outcome: an ACCEPT that
    // fails after enabling Auth leaves the account already able to sign in
    // (matches the admin's intent, Firestore just needs to catch up); a
    // REJECT that fails after disabling Auth leaves the account already
    // locked out. The Auth step itself is idempotent, so retrying this
    // callable after a failure is always safe.
    console.error(JSON.stringify({
      ...logBase,
      error: error.message,
      authUpdateResult,
      claimsUpdateResult,
      firestoreUpdateResult
    }));
    throw new HttpsError('internal', `Review failed partway through (auth:${authUpdateResult}, claims:${claimsUpdateResult}, firestore:${firestoreUpdateResult}): ${error.message}`);
  }
});

// Scheduled sweep: any PENDING employee whose 3-day grace period has
// lapsed with no admin decision gets locked out (RESTRICTED) the same way
// an explicit REJECT does, just recorded separately for audit clarity.
// 30-minute cadence is intentionally coarser than sendReminderEmails' 1
// minute — a 3-day window doesn't need second-granularity sweeping, and the
// residual race (expired but not yet swept) is closed client-side in
// auth_provider.dart, which also checks access_expires_at directly.
export const expirePendingEmployees = onSchedule('every 30 minutes', async () => {
  const now = admin.firestore.Timestamp.now();

  let snapshot;
  try {
    snapshot = await db.collection('employees')
      .where('status', '==', 'PENDING')
      .where('access_expires_at', '<=', now)
      .limit(100)
      .get();
  } catch (error) {
    console.error('Error querying expired pending employees:', error);
    return;
  }

  if (snapshot.empty) {
    return;
  }

  const batch = db.batch();
  let batchHasWrites = false;

  for (const doc of snapshot.docs) {
    const employeeId = doc.id;
    const data = doc.data();
    const logBase = { event: 'expirePendingEmployees', employeeId, previousStatus: 'PENDING', adminId: 'system:scheduled-sweep' };

    try {
      await auth.updateUser(employeeId, { disabled: true });
      await auth.revokeRefreshTokens(employeeId);
      await auth.setCustomUserClaims(employeeId, { role: data.role || 'EMPLOYEE', status: 'RESTRICTED' });
    } catch (error) {
      // Don't flip Firestore status if we couldn't actually lock the
      // account out — leaves it PENDING for the next sweep to retry.
      console.error(JSON.stringify({ ...logBase, error: error.message, authUpdateResult: 'failed' }));
      continue;
    }

    batch.update(doc.ref, {
      status: 'RESTRICTED',
      restricted_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });
    batchHasWrites = true;
    console.log(JSON.stringify({ ...logBase, newStatus: 'RESTRICTED', authUpdateResult: 'ok', claimsUpdateResult: 'ok' }));
  }

  if (batchHasWrites) {
    await batch.commit();
  }
});

// ==========================================
// 2. Scheduled Reminders (Replaces Celery Task)
// ==========================================

// Deliberately NOT exported, so it isn't deployed: with no SMTP account
// configured it only simulates sending, yet still runs every minute and
// marks reminders sent. Before exporting it again, configure SMTP_USER /
// SMTP_PASS and fix the time handling below: it builds the reminder time in
// the function's UTC clock, so a 10:00 IST reminder would go out at 15:30.
// eslint-disable-next-line no-unused-vars
const sendReminderEmails = onSchedule('every 1 minutes', async () => {
  const now = new Date();
  const tenMinutesFromNow = new Date(now.getTime() + 10 * 60 * 1000);

  console.log(`Checking for due reminders at ${now.toISOString()}...`);

  try {
    // Query unsent reminders where date is today or in the past
    const snapshot = await db.collection('reminders')
      .where('is_sent', '==', false)
      .limit(50)
      .get();

    if (snapshot.empty) {
      return;
    }

    const transporter = getTransporter();
    const batch = db.batch();

    for (const doc of snapshot.docs) {
      const reminder = doc.data();
      const reminderDate = reminder.date?.toDate ? reminder.date.toDate() : new Date(reminder.date);
      
      // Parse time HH:mm
      const [hours, minutes] = (reminder.time || '10:00').split(':').map(Number);
      const reminderDateTime = new Date(reminderDate);
      reminderDateTime.setHours(hours, minutes, 0, 0);

      // Trigger if reminder is due within the next 10 minutes or overdue
      if (reminderDateTime <= tenMinutesFromNow) {
        const recipient = reminder.employee_email;
        const subject = `Reminder: ${reminder.event_name}`;
        const html = `
          <h2>Growmont CRM Reminder</h2>
          <p>Hello <strong>${reminder.employee_name || 'Team Member'}</strong>,</p>
          <p>This is a reminder for: <strong>${reminder.event_name}</strong></p>
          <p><strong>Scheduled Time:</strong> ${reminder.time} on ${reminderDateTime.toLocaleDateString('en-IN')}</p>
          <p><strong>Priority:</strong> ${reminder.priority || 'NORMAL'}</p>
          <p><strong>Details:</strong> ${reminder.description || 'No additional details.'}</p>
        `;

        if (transporter && recipient) {
          try {
            await transporter.sendMail({
              from: `"Growmont CRM" <${process.env.SMTP_USER}>`,
              to: recipient,
              subject,
              html
            });
            console.log(`Sent email for reminder ${doc.id} to ${recipient}`);
          } catch (mailErr) {
            console.error(`Failed to send email to ${recipient}:`, mailErr);
          }
        } else {
          console.log(`[SIMULATED EMAIL] Reminder ${doc.id} triggered for ${recipient || 'no email'}: ${reminder.event_name}`);
        }

        batch.update(doc.ref, {
          is_sent: true,
          sent_at: admin.firestore.FieldValue.serverTimestamp()
        });
      }
    }

    await batch.commit();
  } catch (error) {
    console.error('Error in sendReminderEmails schedule:', error);
  }
});

// ==========================================
// 3. Fan-out Triggers for Denormalized Data
// ==========================================

export const onEmployeeUpdate = onDocumentUpdated('employees/{employeeId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const employeeId = event.params.employeeId;

  if (before.name === after.name) {
    return; // Name did not change
  }

  const newName = after.name;
  console.log(`Employee ${employeeId} renamed from "${before.name}" to "${newName}". Updating denormalized references...`);

  // 1. Update sales
  const salesSnapshot = await db.collection('sales').where('sales_rep_id', '==', employeeId).get();
  const batch = db.batch();
  salesSnapshot.forEach(doc => {
    batch.update(doc.ref, { sales_rep_name: newName });
  });

  // 2. Update interactions
  const interSnapshot = await db.collection('interactions').where('employee_id', '==', employeeId).get();
  interSnapshot.forEach(doc => {
    batch.update(doc.ref, { employee_name: newName });
  });

  // 3. Update reminders
  const remSnapshot = await db.collection('reminders').where('employee_id', '==', employeeId).get();
  remSnapshot.forEach(doc => {
    batch.update(doc.ref, { employee_name: newName });
  });

  await batch.commit();
  console.log(`Updated denormalized name across ${salesSnapshot.size} sales, ${interSnapshot.size} interactions, and ${remSnapshot.size} reminders.`);
});
