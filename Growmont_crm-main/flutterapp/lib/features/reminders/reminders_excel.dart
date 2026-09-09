import '../../core/excel/excel_io.dart';
import '../../models/reminder.dart';

/// Shared row (export) / payload (import) builders for the Reminders
/// Excel sheet, used by the Reminders tab on the Profile screen.
const remindersExcelHeaders = [
  'Event Name',
  'Type',
  'Priority',
  'Date',
  'Time',
  'End Time',
  'Employee',
  'Description',
];

List<Object?> reminderExportRow(Reminder r) {
  return [
    r.eventName,
    r.type,
    r.priority,
    DateTime.tryParse(r.date),
    r.time.length >= 5 ? r.time.substring(0, 5) : r.time,
    (r.endTime != null && r.endTime!.length >= 5)
        ? r.endTime!.substring(0, 5)
        : (r.endTime ?? ''),
    r.employeeName ?? r.employee,
    r.description,
  ];
}

/// Builds the payload for [FirestoreService.createReminder] from one
/// imported row, or returns null if the row is blank or has no event
/// name. The reminder is always attributed to the importing user.
Map<String, dynamic>? reminderImportPayload(
  List<Object?> row, {
  required String currentUserName,
}) {
  if (ExcelIO.isBlankRow(row)) return null;

  final eventName = ExcelIO.text(row, 0);
  if (eventName.isEmpty) return null;

  final type = ExcelIO.text(row, 1).toUpperCase();
  final priority = ExcelIO.text(row, 2).toUpperCase();
  final time = ExcelIO.text(row, 4);
  final endTime = ExcelIO.text(row, 5);

  return {
    'event_name': eventName,
    'type': ['CORPORATE', 'PERSONAL'].contains(type) ? type : 'CORPORATE',
    'priority': ['HIGH', 'MEDIUM', 'LOW'].contains(priority)
        ? priority
        : 'MEDIUM',
    'date': _isoOrToday(row, 3),
    'time': _normalizeTime(time.isEmpty ? '10:00' : time),
    if (endTime.isNotEmpty) 'end_time': _normalizeTime(endTime),
    'employee_name': currentUserName,
    'description': ExcelIO.text(row, 7),
  };
}

String _isoOrToday(List<Object?> row, int index) {
  final iso = ExcelIO.isoDate(row, index);
  return iso.isNotEmpty
      ? iso
      : DateTime.now().toIso8601String().split('T').first;
}

String _normalizeTime(String time) {
  return time.length == 5 ? '$time:00' : time;
}
