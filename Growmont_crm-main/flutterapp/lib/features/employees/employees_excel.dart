import 'dart:math';

import '../../core/excel/excel_io.dart';
import '../../core/io/record_import.dart';
import '../../models/employee.dart';

/// Shared row (export) / payload (import) builders for the Employees Excel
/// sheet. Import creates a real Firebase Auth account per row (via
/// [FirestoreService.createEmployee]), so — unlike Sales/Interactions —
/// the import sheet carries an extra Password column that export doesn't
/// need to fill in.
const employeesExportHeaders = [
  'Name',
  'Email',
  'Mobile No',
  'Gender',
  'DOB',
  'Role',
  'Clients',
  'Sales',
  'Interactions',
];

const employeesImportHeaders = [
  'Name',
  'Email',
  'Mobile No',
  'Gender',
  'DOB',
  'Role',
  'Password (leave blank to auto-generate)',
];

List<Object?> employeeExportRow(Employee e) {
  return [
    e.name,
    e.email,
    e.mobileNo,
    e.genderDisplay,
    DateTime.tryParse(e.dob),
    e.role,
    e.clientsCount,
    e.salesCount,
    e.interactionsCount,
  ];
}

/// Builds the payload for [FirestoreService.createEmployee] from one
/// imported row, or returns null if the row is blank or missing the name
/// / email a new account requires.
Map<String, dynamic>? employeeImportPayload(List<Object?> row) {
  if (ExcelIO.isBlankRow(row)) return null;

  final name = ExcelIO.text(row, 0);
  final email = ExcelIO.text(row, 1);
  if (name.isEmpty || email.isEmpty) return null;
  if (!email.toLowerCase().endsWith('@growmont.com')) return null;

  final genderRaw = ExcelIO.text(row, 3).toUpperCase();
  final gender = ['M', 'F', 'O'].contains(genderRaw)
      ? genderRaw
      : (genderRaw.isNotEmpty ? genderRaw[0] : 'O');
  final roleRaw = ExcelIO.text(row, 5).toUpperCase();
  final password = ExcelIO.text(row, 6);

  return {
    'name': name,
    'email': email,
    'mobile_no': ExcelIO.text(row, 2),
    'gender': gender,
    'dob': ExcelIO.isoDate(row, 4),
    'role': roleRaw == 'ADMIN' ? 'ADMIN' : 'EMPLOYEE',
    'password': password.isEmpty ? _randomPassword() : password,
  };
}

/// Employees are matched on email alone, unlike every other import. It is the
/// account's natural key: a row whose address already exists is that same
/// person even if their mobile or role changed. Matching on every field would
/// instead try to create a second Firebase Auth account for the address, which
/// just fails.
const employeesSignatureFields = ['email'];

String employeeSignatureOf(Employee e) =>
    recordSignature({'email': e.email}, employeesSignatureFields);

/// The part of [employeeImportPayload] that may be written over an employee
/// who already exists - deliberately without `password`, so re-importing a
/// sheet never resets somebody's sign-in, and without `email`, which is the
/// key being matched on.
Map<String, dynamic> employeeUpdatePayload(Map<String, dynamic> payload) {
  const updatable = ['name', 'mobile_no', 'gender', 'dob', 'role'];
  return {
    for (final key in updatable)
      if (payload.containsKey(key)) key: payload[key],
  };
}

String _randomPassword() {
  const chars =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#%';
  final rand = Random.secure();
  return List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
}
