import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/excel/excel_io.dart';

void main() {
  group('ExcelIO.buildBytes', () {
    test('produces a valid, readable .xlsx with correct dates', () {
      final bytes = ExcelIO.buildBytes(
        sheetName: 'Sales',
        headers: const ['Date', 'Client Name', 'Amount'],
        rows: [
          [DateTime(2026, 9, 13), 'Acme Corp', 1234.5], // day > 12
          [null, 'No Date Client', 500],
        ],
      );

      expect(bytes.length, greaterThan(100));
      expect(bytes[0], 0x50); // 'P' — zip/xlsx magic header
      expect(bytes[1], 0x4B); // 'K'

      final workbook = xls.Excel.decodeBytes(bytes);
      final sheet = workbook.tables[workbook.tables.keys.first]!;
      final rows = sheet.rows;
      expect(rows.length, 3); // header + 2 data rows

      final dateCell = rows[1][0]!.value;
      expect(dateCell, isA<xls.DateCellValue>());
      expect((dateCell as xls.DateCellValue).day, 13);
      expect(dateCell.month, 9);
      expect(dateCell.year, 2026);

      expect((rows[1][1]!.value as xls.TextCellValue).toString(), 'Acme Corp');
      expect(rows[2][0]?.value, isNull); // blank date cell round-trips as null
    });

    test('sizes each column to its own longest cell, header included', () {
      final longNote =
          'This is a much longer discussion note than any of the other cells in this sheet.';

      final bytes = ExcelIO.buildBytes(
        sheetName: 'Interactions',
        headers: const ['Pri', 'Client Name', 'Notes'],
        rows: [
          ['HIGH', 'A', longNote],
          ['LOW', 'A somewhat longer client name here', 'short'],
        ],
      );

      final workbook = xls.Excel.decodeBytes(bytes);
      final sheet = workbook.tables[workbook.tables.keys.first]!;

      final priWidth = sheet.getColumnWidth(0);
      final clientWidth = sheet.getColumnWidth(1);
      final notesWidth = sheet.getColumnWidth(2);

      // 'Pri' / 'HIGH' / 'LOW' are all short — narrowest column.
      expect(priWidth, lessThan(clientWidth));
      expect(priWidth, lessThan(notesWidth));
      // The long note is the longest string in the sheet — widest column.
      expect(notesWidth, greaterThan(clientWidth));

      // Sanity: widths are actually distinct, not just all defaulted to
      // the same generic Excel width (the bug being fixed here).
      expect({priWidth, clientWidth, notesWidth}.length, 3);
    });

    test('a column with only a short header and short data stays narrow', () {
      final bytes = ExcelIO.buildBytes(
        sheetName: 'S',
        headers: const ['ID'],
        rows: [
          ['1'],
          ['2'],
        ],
      );
      final workbook = xls.Excel.decodeBytes(bytes);
      final sheet = workbook.tables[workbook.tables.keys.first]!;
      // Excel's own autofit formula for 2-char content: (2*7+9)/7 ≈ 3.29
      expect(sheet.getColumnWidth(0), lessThan(6));
    });
  });
}
