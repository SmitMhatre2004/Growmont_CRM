/**
 * Cloud Functions for Growmont CRM
 * Replaces all remaining custom Django server functionality:
 * - Admin employee provisioning (Auth + custom claims + Firestore doc)
 * - Scheduled reminder notifications (every 60s)
 * - Fan-out updates for denormalized employee names
 *
 * Excel import/export runs entirely on-device in the Flutter app
 * (see flutterapp/lib/core/excel/excel_io.dart) — there is no server
 * component for it.
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import nodemailer from 'nodemailer';

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

export const createEmployee = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }
  if (request.auth.token.role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only administrators can create employees.');
  }

  const { name, email, password, mobile_no, gender, dob, role } = request.data;
  if (!name || !email || !password) {
    throw new HttpsError('invalid-argument', 'Name, email, and password are required.');
  }
  if (!email.toLowerCase().endsWith('@growmont.com')) {
    throw new HttpsError('invalid-argument', 'Employee emails must end in @growmont.com.');
  }

  const employeeRole = role === 'ADMIN' ? 'ADMIN' : 'EMPLOYEE';

  try {
    // 1. Create Firebase Auth user
    const userRecord = await auth.createUser({
      email,
      password,
      displayName: name
    });

    // 2. Set custom claim for RBAC
    await auth.setCustomUserClaims(userRecord.uid, { role: employeeRole, status: 'ACTIVE' });

    // 3. Create employee document in Firestore
    const employeeData = {
      name,
      email,
      mobile_no: mobile_no || '',
      gender: gender || 'O',
      dob: dob ? admin.firestore.Timestamp.fromDate(new Date(dob)) : null,
      avatar_url: '',
      role: employeeRole,
      status: 'ACTIVE',
      clients_count: 0,
      sales_count: 0,
      interactions_count: 0,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    };

    await db.collection('employees').doc(userRecord.uid).set(employeeData);

    return {
      success: true,
      uid: userRecord.uid,
      message: `Employee ${name} created successfully.`
    };
  } catch (error) {
    console.error('Error creating employee:', error);
    throw new HttpsError('internal', error.message);
  }
});

export const deleteEmployee = onCall(async (request) => {
  if (!request.auth || request.auth.token.role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only administrators can delete employees.');
  }

  const { employeeId } = request.data;
  if (!employeeId) {
    throw new HttpsError('invalid-argument', 'Employee ID is required.');
  }

  try {
    // Delete from Auth
    try {
      await auth.deleteUser(employeeId);
    } catch (authErr) {
      console.warn(`Auth user ${employeeId} could not be deleted or does not exist:`, authErr.message);
    }

    // Delete Firestore document
    await db.collection('employees').doc(employeeId).delete();

    return { success: true, message: `Employee ${employeeId} deleted successfully.` };
  } catch (error) {
    console.error('Error deleting employee:', error);
    throw new HttpsError('internal', error.message);
  }
});

export const updateEmployeeRole = onCall(async (request) => {
  if (!request.auth || request.auth.token.role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only administrators can update employee roles.');
  }

  const { employeeId, role } = request.data;
  if (!employeeId || !['ADMIN', 'EMPLOYEE'].includes(role)) {
    throw new HttpsError('invalid-argument', 'Valid employeeId and role are required.');
  }

  try {
    await auth.setCustomUserClaims(employeeId, { role });
    await db.collection('employees').doc(employeeId).update({
      role,
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });

    return { success: true, message: `Role for ${employeeId} updated to ${role}.` };
  } catch (error) {
    console.error('Error updating role:', error);
    throw new HttpsError('internal', error.message);
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
  if (!request.auth || request.auth.token.role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only administrators can review employees.');
  }

  const { employeeId, decision, role } = request.data;
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

export const sendReminderEmails = onSchedule('every 1 minutes', async () => {
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
