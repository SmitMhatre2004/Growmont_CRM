import '../../core/excel/excel_io.dart';
import '../../models/interaction.dart';

/// Shared row (export) / payload (import) builders for the Interactions
/// Excel sheet, reused by the Interactions screen and the Info Portal's
/// Interactions tab so both stay in lockstep with a single column layout.
const interactionsExcelHeaders = [
  'Date',
  'Client Name',
  'Client Contact',
  'Employee',
  'Follow-up Date',
  'Follow-up Time',
  'Priority',
  'Discussion Notes',
];

List<Object?> interactionExportRow(Interaction i) {
  return [
    DateTime.tryParse(i.date),
    i.clientName,
    i.clientContact,
    i.employeeName ?? i.employee,
    DateTime.tryParse(i.followUpDate),
    i.followUpTime,
    i.priorityDisplay ?? i.priority,
    i.discussionNotes,
  ];
}

/// Builds the payload for [FirestoreService.createInteraction] from one
/// imported row, or returns null if the row is blank. The interaction is
/// always attributed to the importing user.
Map<String, dynamic>? interactionImportPayload(
  List<Object?> row, {
  required String currentUserName,
}) {
  if (ExcelIO.isBlankRow(row)) return null;

  final clientName = ExcelIO.text(row, 1);
  final priority = ExcelIO.text(row, 6).toUpperCase();

  return {
    'date': _isoOrToday(row, 0),
    'client_name': clientName.isEmpty ? 'Unknown Client' : clientName,
    'client_contact': ExcelIO.text(row, 2),
    'employee_name': currentUserName,
    'follow_up_date': ExcelIO.isoDate(row, 4),
    'follow_up_time': ExcelIO.text(row, 5),
    'priority': ['HIGH', 'MEDIUM', 'LOW'].contains(priority)
        ? priority
        : 'MEDIUM',
    'discussion_notes': ExcelIO.text(row, 7),
  };
}

String _isoOrToday(List<Object?> row, int index) {
  final iso = ExcelIO.isoDate(row, index);
  return iso.isNotEmpty ? iso : DateTime.now().toIso8601String().split('T').first;
}
