/// Shared create-or-update logic for every Import button.
///
/// Re-importing a file used to insert a second copy of every row. Records are
/// matched on a signature built from their business fields, so a row that is
/// already present updates that record instead of creating a duplicate.
library;

/// Canonical form of one field for comparison. Numbers are compared
/// numerically so `1000` and `1000.0` - which is the difference between a
/// typed cell and one round-tripped through an export - are one value, and
/// text is compared case- and whitespace-insensitively.
String normalizeField(Object? value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty) return '';
  final number = num.tryParse(text);
  if (number != null) return number.toDouble().toStringAsFixed(4);
  return text.toLowerCase();
}

/// Joins [fields] of [record] into one comparison key. The separator is a
/// control character so it cannot occur inside a field value.
String recordSignature(Map<String, dynamic> record, List<String> fields) {
  return fields.map((f) => normalizeField(record[f])).join('');
}

/// What one import run did.
class ImportResult {
  int created = 0;
  int updated = 0;
  int repeated = 0;
  int failed = 0;

  int get total => created + updated + repeated + failed;

  /// One line suitable for a snackbar.
  String describe(String noun, {String? pluralNoun}) {
    final plural = pluralNoun ?? '${noun}s';
    if (total == 0) return 'Nothing to import';

    final parts = <String>[
      if (created > 0) '$created ${created == 1 ? noun : plural} imported',
      if (updated > 0) '$updated updated',
      if (repeated > 0) '$repeated duplicate${repeated == 1 ? '' : 's'} skipped',
      if (failed > 0) '$failed failed',
    ];
    if (parts.isEmpty) return 'Nothing to import';
    return parts.join(', ');
  }
}

/// Runs [payloads] against the records already present.
///
/// [existingIdBySignature] maps a signature to the id of the record holding
/// it. A payload whose signature is already there updates that record; one
/// that is new is created. A signature repeated inside a single file is
/// counted once - the rows are identical by definition, so re-writing the
/// record it just created would be a no-op.
Future<ImportResult> runRecordImport({
  required Iterable<Map<String, dynamic>> payloads,
  required Map<String, String> existingIdBySignature,
  required List<String> signatureFields,
  required Future<void> Function(Map<String, dynamic> payload) create,
  required Future<void> Function(String id, Map<String, dynamic> payload)
      update,
}) async {
  final result = ImportResult();
  final createdThisRun = <String>{};

  for (final payload in payloads) {
    final signature = recordSignature(payload, signatureFields);

    if (createdThisRun.contains(signature)) {
      result.repeated++;
      continue;
    }

    try {
      final existingId = existingIdBySignature[signature];
      if (existingId != null) {
        await update(existingId, payload);
        result.updated++;
      } else {
        await create(payload);
        createdThisRun.add(signature);
        result.created++;
      }
    } catch (_) {
      result.failed++;
    }
  }

  return result;
}
