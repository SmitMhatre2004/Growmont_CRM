import '../../core/excel/excel_io.dart';
import '../../core/io/record_import.dart';
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

/// Fields that identify a reminder on import. The description is left out:
/// everything else matching means it is the same event, so a re-import with a
/// reworded description should update it rather than duplicate it.
const remindersSignatureFields = [
  'event_name',
  'type',
  'priority',
  'date',
  'time',
  'end_time',
  'employee_name',
];

/// The signature of a reminder already in the list, applying the same
/// normalization [reminderImportPayload] does - including the trip through
/// 'HH:mm' the export performs, so a round-tripped row matches.
String reminderSignatureOf(Reminder r) {
  final type = r.type.toUpperCase();
  final priority = r.priority.toUpperCase();
  final endTime = r.endTime ?? '';
  return recordSignature({
    'event_name': r.eventName,
    'type': ['CORPORATE', 'PERSONAL'].contains(type) ? type : 'CORPORATE',
    'priority': ['HIGH', 'MEDIUM', 'LOW'].contains(priority)
        ? priority
        : 'MEDIUM',
    'date': r.date,
    'time': _normalizeTime(_hhmm(r.time.isEmpty ? '10:00' : r.time)),
    'end_time': endTime.isEmpty ? '' : _normalizeTime(_hhmm(endTime)),
    'employee_name': r.employeeName ?? r.employee,
  }, remindersSignatureFields);
}

String _hhmm(String time) => time.length >= 5 ? time.substring(0, 5) : time;

String _isoOrToday(List<Object?> row, int index) {
  final iso = ExcelIO.isoDate(row, index);
  return iso.isNotEmpty
      ? iso
      : DateTime.now().toIso8601String().split('T').first;
}

String _normalizeTime(String time) {
  return time.length == 5 ? '$time:00' : time;
}
