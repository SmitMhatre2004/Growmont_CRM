import '../../core/excel/excel_io.dart';
import '../../core/io/record_import.dart';
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

/// JSON field names, in the same column order as [interactionsExcelHeaders],
/// so a JSON record and a spreadsheet row feed the same payload builder.
const interactionsJsonKeys = [
  'date',
  'client_name',
  'client_contact',
  'employee_name',
  'follow_up_date',
  'follow_up_time',
  'priority',
  'discussion_notes',
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

/// Fields that identify an interaction on import. Discussion notes are left
/// out: everything else matching means it is the same interaction, so a
/// re-import with expanded notes should update that record, not duplicate it.
const interactionsSignatureFields = [
  'date',
  'client_name',
  'client_contact',
  'employee_name',
  'follow_up_date',
  'follow_up_time',
  'priority',
];

/// The signature of an interaction already in the list, mirroring the
/// fallbacks [interactionImportPayload] applies so both sides line up.
String interactionSignatureOf(Interaction i) {
  final priority = (i.priorityDisplay ?? i.priority).toUpperCase();
  return recordSignature({
    'date': i.date,
    'client_name': i.clientName.isEmpty ? 'Unknown Client' : i.clientName,
    'client_contact': i.clientContact,
    'employee_name': i.employeeName ?? i.employee,
    'follow_up_date': i.followUpDate,
    'follow_up_time': i.followUpTime,
    'priority': ['HIGH', 'MEDIUM', 'LOW'].contains(priority)
        ? priority
        : 'MEDIUM',
  }, interactionsSignatureFields);
}

String _isoOrToday(List<Object?> row, int index) {
  final iso = ExcelIO.isoDate(row, index);
  return iso.isNotEmpty ? iso : DateTime.now().toIso8601String().split('T').first;
}
