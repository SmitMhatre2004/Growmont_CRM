/**
 * Cloud Functions for Growmont CRM
 * Replaces all remaining custom Django server functionality:
 * - Admin employee provisioning (Auth + custom claims + Firestore doc)
 * - Scheduled reminder notifications (every 60s)
 * - Excel import & export for Sales and Interactions
 * - Fan-out updates for denormalized employee names
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import admin from 'firebase-admin';
import ExcelJS from 'exceljs';
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

  const employeeRole = role === 'ADMIN' ? 'ADMIN' : 'EMPLOYEE';

  try {
    // 1. Create Firebase Auth user
    const userRecord = await auth.createUser({
      email,
      password,
      displayName: name
    });

    // 2. Set custom claim for RBAC
    await auth.setCustomUserClaims(userRecord.uid, { role: employeeRole });

    // 3. Create employee document in Firestore
    const employeeData = {
      name,
      email,
      mobile_no: mobile_no || '',
      gender: gender || 'O',
      dob: dob ? admin.firestore.Timestamp.fromDate(new Date(dob)) : null,
      avatar_url: '',
      role: employeeRole,
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
// 3. Excel Export Functions
// ==========================================

export const exportSalesExcel = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const isAdmin = request.auth.token.role === 'ADMIN';
  const filterEmployeeId = request.data?.sales_rep_id;

  let query = db.collection('sales').orderBy('date', 'desc');

  if (!isAdmin) {
    // Employees can only export their own sales
    query = query.where('sales_rep_id', '==', request.auth.uid);
  } else if (filterEmployeeId) {
    query = query.where('sales_rep_id', '==', filterEmployeeId);
  }

  const snapshot = await query.get();

  const workbook = new ExcelJS.Workbook();
  const worksheet = workbook.addWorksheet('Sales');

  worksheet.columns = [
    { header: 'Date', key: 'date', width: 15 },
    { header: 'Client Name', key: 'client_name', width: 25 },
    { header: 'Sales Representative', key: 'sales_rep_name', width: 25 },
    { header: 'Product', key: 'product', width: 15 },
    { header: 'Company', key: 'company', width: 20 },
    { header: 'Scheme', key: 'scheme', width: 20 },
    { header: 'Amount (₹)', key: 'amount', width: 15 },
    { header: 'Frequency', key: 'frequency', width: 15 },
    { header: 'Remarks', key: 'remarks', width: 30 }
  ];

  snapshot.forEach(doc => {
    const s = doc.data();
    const dateStr = s.date?.toDate ? s.date.toDate().toLocaleDateString('en-IN') : '';
    worksheet.addRow({
      date: dateStr,
      client_name: s.client_name || '',
      sales_rep_name: s.sales_rep_name || '',
      product: s.product || '',
      company: s.company || '',
      scheme: s.scheme || '',
      amount: ((s.amount_paise || 0) / 100).toFixed(2),
      frequency: s.frequency || '',
      remarks: s.remarks || ''
    });
  });

  const buffer = await workbook.xlsx.writeBuffer();
  return {
    base64: Buffer.from(buffer).toString('base64'),
    filename: `sales_export_${Date.now()}.xlsx`
  };
});

export const exportInteractionsExcel = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const isAdmin = request.auth.token.role === 'ADMIN';
  const filterEmployeeId = request.data?.employee_id;

  let query = db.collection('interactions').orderBy('date', 'desc');

  if (!isAdmin) {
    query = query.where('employee_id', '==', request.auth.uid);
  } else if (filterEmployeeId) {
    query = query.where('employee_id', '==', filterEmployeeId);
  }

  const snapshot = await query.get();

  const workbook = new ExcelJS.Workbook();
  const worksheet = workbook.addWorksheet('Interactions');

  worksheet.columns = [
    { header: 'Date', key: 'date', width: 15 },
    { header: 'Client Name', key: 'client_name', width: 25 },
    { header: 'Client Contact', key: 'client_contact', width: 18 },
    { header: 'Employee', key: 'employee_name', width: 25 },
    { header: 'Follow-up Date', key: 'follow_up_date', width: 15 },
    { header: 'Follow-up Time', key: 'follow_up_time', width: 15 },
    { header: 'Priority', key: 'priority', width: 12 },
    { header: 'Discussion Notes', key: 'discussion_notes', width: 35 }
  ];

  snapshot.forEach(doc => {
    const i = doc.data();
    const dateStr = i.date?.toDate ? i.date.toDate().toLocaleDateString('en-IN') : '';
    const followUpStr = i.follow_up_date?.toDate ? i.follow_up_date.toDate().toLocaleDateString('en-IN') : '';
    worksheet.addRow({
      date: dateStr,
      client_name: i.client_name || '',
      client_contact: i.client_contact || '',
      employee_name: i.employee_name || '',
      follow_up_date: followUpStr,
      follow_up_time: i.follow_up_time || '',
      priority: i.priority || '',
      discussion_notes: i.discussion_notes || ''
    });
  });

  const buffer = await workbook.xlsx.writeBuffer();
  return {
    base64: Buffer.from(buffer).toString('base64'),
    filename: `interactions_export_${Date.now()}.xlsx`
  };
});

// ==========================================
// 4. Excel Import Functions
// ==========================================

export const importSalesExcel = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { base64 } = request.data;
  if (!base64) {
    throw new HttpsError('invalid-argument', 'Excel file base64 data is required.');
  }

  const buffer = Buffer.from(base64, 'base64');
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(buffer);

  const worksheet = workbook.worksheets[0];
  if (!worksheet) {
    throw new HttpsError('invalid-argument', 'No worksheet found in Excel file.');
  }

  // Fetch current user details
  const empDoc = await db.collection('employees').doc(request.auth.uid).get();
  const currentEmpName = empDoc.exists ? empDoc.data().name : 'Team Member';
  const isAdmin = request.auth.token.role === 'ADMIN';

  let batch = db.batch();
  let count = 0;

  worksheet.eachRow((row, rowNumber) => {
    if (rowNumber === 1) return; // Skip header

    const dateVal = row.getCell(1).value;
    const clientName = row.getCell(2).value?.toString() || 'Unknown Client';
    const repName = row.getCell(3).value?.toString() || currentEmpName;
    const product = row.getCell(4).value?.toString() || 'MF';
    const company = row.getCell(5).value?.toString() || '';
    const scheme = row.getCell(6).value?.toString() || '';
    const amountVal = parseFloat(row.getCell(7).value || 0);
    const frequency = row.getCell(8).value?.toString() || 'O';
    const remarks = row.getCell(9).value?.toString() || '';

    const amountPaise = Math.round(amountVal * 100);
    if (isNaN(amountPaise) || amountPaise <= 0) return;

    const saleRef = db.collection('sales').doc();
    batch.set(saleRef, {
      date: dateVal ? admin.firestore.Timestamp.fromDate(new Date(dateVal)) : admin.firestore.FieldValue.serverTimestamp(),
      client_name: clientName,
      sales_rep_id: request.auth.uid,
      sales_rep_name: isAdmin ? repName : currentEmpName,
      product,
      company,
      scheme,
      amount_paise: amountPaise,
      frequency,
      remarks,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });
    count++;
  });

  await batch.commit();
  return { success: true, count, message: `Successfully imported ${count} sales.` };
});

export const importInteractionsExcel = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { base64 } = request.data;
  if (!base64) {
    throw new HttpsError('invalid-argument', 'Excel file base64 data is required.');
  }

  const buffer = Buffer.from(base64, 'base64');
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(buffer);

  const worksheet = workbook.worksheets[0];
  if (!worksheet) {
    throw new HttpsError('invalid-argument', 'No worksheet found in Excel file.');
  }

  const empDoc = await db.collection('employees').doc(request.auth.uid).get();
  const currentEmpName = empDoc.exists ? empDoc.data().name : 'Team Member';

  let batch = db.batch();
  let count = 0;

  worksheet.eachRow((row, rowNumber) => {
    if (rowNumber === 1) return;

    const dateVal = row.getCell(1).value;
    const clientName = row.getCell(2).value?.toString() || 'Unknown Client';
    const clientContact = row.getCell(3).value?.toString() || '';
    const followUpDate = row.getCell(5).value;
    const followUpTime = row.getCell(6).value?.toString() || '';
    const priority = row.getCell(7).value?.toString() || 'MEDIUM';
    const discussionNotes = row.getCell(8).value?.toString() || '';

    const interRef = db.collection('interactions').doc();
    batch.set(interRef, {
      date: dateVal ? admin.firestore.Timestamp.fromDate(new Date(dateVal)) : admin.firestore.FieldValue.serverTimestamp(),
      client_name: clientName,
      client_contact: clientContact,
      employee_id: request.auth.uid,
      employee_name: currentEmpName,
      follow_up_date: followUpDate ? admin.firestore.Timestamp.fromDate(new Date(followUpDate)) : null,
      follow_up_time: followUpTime,
      priority,
      discussion_notes: discussionNotes,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });
    count++;
  });

  await batch.commit();
  return { success: true, count, message: `Successfully imported ${count} interactions.` };
});

// ==========================================
// 5. Fan-out Triggers for Denormalized Data
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
