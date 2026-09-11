import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/io/file_saver.dart';
import 'package:growmont_crm/core/io/record_import.dart';
import 'package:growmont_crm/core/io/record_json.dart';
import 'package:growmont_crm/features/interactions/interactions_excel.dart';
import 'package:growmont_crm/features/sales/sales_excel.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';
import 'package:path/path.dart' as p;

Sale _sale({
  String id = 's1',
  String date = '2026-03-04',
  String client = 'Acme Corp',
  String rep = 'Priya Nair',
  String product = 'Mutual Fund',
  String amount = '15000.00',
  String remarks = 'first call',
}) {
  return Sale.fromJson({
    'id': id,
    'date': date,
    'client_name': client,
    'sales_rep_name': rep,
    'product': product,
    'company': 'HDFC',
    'scheme': 'Balanced Advantage',
    'amount': amount,
    'frequency': 'M',
    'remarks': remarks,
  });
}

Interaction _interaction({
  String id = 'i1',
  String notes = 'discussed portfolio',
}) {
  return Interaction.fromJson({
    'id': id,
    'date': '2026-03-04',
    'client_name': 'Acme Corp',
    'client_contact': '9876543210',
    'employee_name': 'Priya Nair',
    'follow_up_date': '2026-03-11',
    'follow_up_time': '11:30',
    'priority': 'HIGH',
    'discussion_notes': notes,
  });
}

void main() {
  group('FileSaver.uniquePath', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('growmont_export'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('leaves a free name alone', () {
      final path = p.join(dir.path, 'sales_export.xlsx');
      expect(FileSaver.uniquePath(path), path);
    });

    test('steps aside rather than overwriting an existing file', () {
      final path = p.join(dir.path, 'sales_export.xlsx');
      File(path).writeAsStringSync('original');

      final unique = FileSaver.uniquePath(path);
      expect(unique, p.join(dir.path, 'sales_export (1).xlsx'));
      expect(File(path).readAsStringSync(), 'original');
    });

    test('counts up past a run of collisions', () {
      File(p.join(dir.path, 'report.json')).writeAsStringSync('a');
      File(p.join(dir.path, 'report (1).json')).writeAsStringSync('b');
      File(p.join(dir.path, 'report (2).json')).writeAsStringSync('c');

      expect(
        FileSaver.uniquePath(p.join(dir.path, 'report.json')),
        p.join(dir.path, 'report (3).json'),
      );
    });

    test('keeps the extension when a name contains dots', () {
      final path = p.join(dir.path, 'sales.2026.03.xlsx');
      File(path).writeAsStringSync('x');
      expect(
        FileSaver.uniquePath(path),
        p.join(dir.path, 'sales.2026.03 (1).xlsx'),
      );
    });
  });

  group('recordSignature', () {
    test('compares numbers numerically, not as text', () {
      const fields = ['amount'];
      expect(
        recordSignature({'amount': '1000'}, fields),
        recordSignature({'amount': 1000.0}, fields),
      );
      expect(
        recordSignature({'amount': '1000.00'}, fields),
        recordSignature({'amount': 1000}, fields),
      );
    });

    test('ignores case and surrounding whitespace', () {
      const fields = ['client'];
      expect(
        recordSignature({'client': '  Acme Corp '}, fields),
        recordSignature({'client': 'acme corp'}, fields),
      );
    });

    test('treats null and empty as the same absent value', () {
      const fields = ['note'];
      expect(
        recordSignature({'note': null}, fields),
        recordSignature({'note': ''}, fields),
      );
    });

    test('separates fields so a shift cannot collide', () {
      const fields = ['a', 'b'];
      expect(
        recordSignature({'a': 'xy', 'b': 'z'}, fields),
        isNot(recordSignature({'a': 'x', 'b': 'yz'}, fields)),
      );
    });
  });

  group('runRecordImport', () {
    test('creates rows that are not already present', () async {
      final created = <Map<String, dynamic>>[];

      final result = await runRecordImport(
        payloads: [
          {'k': 'a'},
          {'k': 'b'},
        ],
        existingIdBySignature: const {},
        signatureFields: const ['k'],
        create: (p) async => created.add(p),
        update: (_, _) async => fail('should not update'),
      );

      expect(result.created, 2);
      expect(result.updated, 0);
      expect(created.map((e) => e['k']), ['a', 'b']);
    });

    test('updates a row that already exists instead of duplicating it',
        () async {
      final updates = <String, Map<String, dynamic>>{};

      final result = await runRecordImport(
        payloads: [
          {'k': 'a', 'note': 'revised'},
        ],
        existingIdBySignature: {recordSignature({'k': 'a'}, ['k']): 'id-1'},
        signatureFields: const ['k'],
        create: (_) async => fail('should not create a duplicate'),
        update: (id, p) async => updates[id] = p,
      );

      expect(result.created, 0);
      expect(result.updated, 1);
      expect(updates['id-1']!['note'], 'revised');
    });

    test('writes a row repeated inside one file only once', () async {
      var creates = 0;

      final result = await runRecordImport(
        payloads: [
          {'k': 'a'},
          {'k': 'a'},
          {'k': 'a'},
        ],
        existingIdBySignature: const {},
        signatureFields: const ['k'],
        create: (_) async => creates++,
        update: (_, _) async => fail('should not update'),
      );

      expect(creates, 1);
      expect(result.created, 1);
      expect(result.repeated, 2);
    });

    test('counts a failing write without abandoning the rest', () async {
      final result = await runRecordImport(
        payloads: [
          {'k': 'bad'},
          {'k': 'good'},
        ],
        existingIdBySignature: const {},
        signatureFields: const ['k'],
        create: (p) async {
          if (p['k'] == 'bad') throw StateError('nope');
        },
        update: (_, _) async {},
      );

      expect(result.failed, 1);
      expect(result.created, 1);
    });

    test('describe reports what happened', () async {
      final result = ImportResult()
        ..created = 2
        ..updated = 1
        ..repeated = 3;
      expect(
        result.describe('sale'),
        '2 sales imported, 1 updated, 3 duplicates skipped',
      );
      expect(ImportResult().describe('sale'), 'Nothing to import');
    });
  });

  // The whole point of the dedup work: a file produced by Export, fed back
  // into Import, must recognise every row as one it already has.
  group('re-importing an export matches the records it came from', () {
    test('sales', () {
      final sale = _sale();
      final payload = saleImportPayload(
        saleExportRow(sale),
        currentUserName: sale.salesRepName!,
      )!;

      expect(
        recordSignature(payload, salesSignatureFields),
        saleSignatureOf(sale),
      );
    });

    test('sales - remarks are excluded, so an edited note still matches', () {
      final original = _sale(remarks: 'first call');
      final edited = _sale(remarks: 'rewrote this note entirely');

      expect(saleSignatureOf(original), saleSignatureOf(edited));
    });

    test('sales - a different amount is a different record', () {
      expect(
        saleSignatureOf(_sale(amount: '15000.00')),
        isNot(saleSignatureOf(_sale(amount: '15001.00'))),
      );
    });

    test('interactions', () {
      final interaction = _interaction();
      final payload = interactionImportPayload(
        interactionExportRow(interaction),
        currentUserName: interaction.employeeName!,
      )!;

      expect(
        recordSignature(payload, interactionsSignatureFields),
        interactionSignatureOf(interaction),
      );
    });

    test('interactions - notes are excluded from the match', () {
      expect(
        interactionSignatureOf(_interaction(notes: 'short')),
        interactionSignatureOf(_interaction(notes: 'a much longer note')),
      );
    });
  });

  group('RecordJson', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('growmont_json'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips rows through a file', () async {
      final rows = [_sale()].map(saleExportRow).toList();
      final path = p.join(dir.path, 'sales.json');
      File(path).writeAsBytesSync(
        RecordJson.encode(type: 'sales', keys: salesJsonKeys, rows: rows),
      );

      final back = await RecordJson.readRows(path, salesJsonKeys);
      expect(back, hasLength(1));

      // A round-tripped row rebuilds the same payload as the sheet path.
      final payload =
          saleImportPayload(back.single, currentUserName: 'Priya Nair')!;
      expect(
        recordSignature(payload, salesSignatureFields),
        saleSignatureOf(_sale()),
      );
    });

    test('writes dates as plain yyyy-MM-dd, not a Dart timestamp', () async {
      final bytes = RecordJson.encode(
        type: 'sales',
        keys: salesJsonKeys,
        rows: [_sale()].map(saleExportRow).toList(),
      );
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      expect(decoded['type'], 'sales');
      expect(decoded['count'], 1);
      expect((decoded['records'] as List).first['date'], '2026-03-04');
    });

    test('accepts a bare top-level array too', () async {
      final path = p.join(dir.path, 'bare.json');
      File(path).writeAsStringSync(
        jsonEncode([
          {'date': '2026-03-04', 'client_name': 'Acme Corp'},
        ]),
      );

      final rows = await RecordJson.readRows(path, salesJsonKeys);
      expect(rows.single[0], '2026-03-04');
      expect(rows.single[1], 'Acme Corp');
    });

    test('rejects a file that is not a record export', () async {
      final path = p.join(dir.path, 'junk.json');
      File(path).writeAsStringSync('{"hello":"world"}');

      expect(
        () => RecordJson.readRows(path, salesJsonKeys),
        throwsA(isA<FormatException>()),
      );
    });

    test('isJsonPath distinguishes the two formats', () {
      expect(RecordJson.isJsonPath('a/b/sales_export.JSON'), isTrue);
      expect(RecordJson.isJsonPath('a/b/sales_export.xlsx'), isFalse);
    });
  });
}
