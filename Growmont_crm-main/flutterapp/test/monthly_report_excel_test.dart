// test/monthly_report_excel_test.dart
//
// The export must agree with the screen. Both read the same MonthlyReport,
// and these tests pin that down: the figures written into the workbook are
// compared against the report object the UI renders, and the bytes are
// decoded back to prove the file is a real multi-tab .xlsx.

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/excel/excel_io.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/reports/monthly_report_builder.dart';
import 'package:growmont_crm/core/reports/monthly_report_excel.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';

Sale _sale({
  String id = 's1',
  required String date,
  int paise = 500000,
  String rep = 'emp1',
  String product = 'MF',
  String company = 'HDFC',
}) {
  return Sale(
    id: id,
    date: date,
    clientName: 'Acme Industries',
    clientId: 'c1',
    salesRep: rep,
    salesRepId: rep,
    salesRepName: 'Asha Rao',
    product: product,
    company: company,
    scheme: 'Growth',
    amount: (paise / 100).toStringAsFixed(2),
    amountPaise: paise,
    frequency: 'M',
  );
}

MonthlyReport _report({
  ReportScope scope = ReportScope.company,
  List<Sale>? sales,
  List<Client> clients = const [],
}) {
  return MonthlyReportBuilder.build(
    period: const ReportMonth(2025, 6),
    scope: scope,
    scopeLabel: scope == ReportScope.company ? 'Whole company' : 'Asha Rao',
    sales: sales ??
        [
          _sale(id: 'a', date: '2025-06-02', paise: 500000),
          _sale(id: 'b', date: '2025-06-14', paise: 250000, product: 'HI'),
          _sale(id: 'c', date: '2025-05-10', paise: 300000),
        ],
    interactions: [
      Interaction(
        id: 'i1',
        date: '2025-06-03',
        clientName: 'Acme Industries',
        clientContact: '9999999999',
        employee: 'emp1',
        employeeId: 'emp1',
        followUpDate: '2025-06-20',
        followUpTime: '10:00:00',
        priority: 'HIGH',
      ),
    ],
    clients: clients,
    employeeNames: const {'emp1': 'Asha Rao'},
    now: DateTime(2025, 6, 15, 10),
  );
}

/// Finds the row in [sheet] whose first cell equals [label].
List<xls.Data?> _rowStartingWith(xls.Sheet sheet, String label) {
  for (final row in sheet.rows) {
    if (row.isEmpty) continue;
    if (row.first?.value?.toString() == label) return row;
  }
  fail('No row starting with "$label" in sheet "${sheet.sheetName}"');
}

num? _num(List<xls.Data?> row, int index) {
  final value = row.length > index ? row[index]?.value : null;
  if (value is xls.IntCellValue) return value.value;
  if (value is xls.DoubleCellValue) return value.value;
  return null;
}

void main() {
  group('workbook structure', () {
    test('tabs appear in reading order, with no stray default sheet', () {
      final sheets = MonthlyReportExcel.sheets(_report());
      expect(
        sheets.map((s) => s.name),
        [
          'Summary',
          'Revenue by Product',
          'Revenue by Company',
          'Revenue by Frequency',
          'Monthly Trend',
          'Top Deals',
          'Team Performance',
          'Notes',
        ],
      );
    });

    test('an individual report omits the team tab', () {
      final sheets = MonthlyReportExcel.sheets(
        _report(scope: ReportScope.individual),
      );
      expect(sheets.any((s) => s.name == 'Team Performance'), isFalse);
      // Everything else is still there.
      expect(sheets.first.name, 'Summary');
      expect(sheets.last.name, 'Notes');
    });

    test('encodes to a decodable .xlsx carrying every tab', () {
      final report = _report();
      final bytes = ExcelIO.buildMultiSheetBytes(
        MonthlyReportExcel.sheets(report),
      );

      final workbook = xls.Excel.decodeBytes(bytes);
      expect(
        workbook.tables.keys,
        containsAll(<String>['Summary', 'Monthly Trend', 'Notes']),
      );
      // createExcel() seeds a 'Sheet1'; it must have been renamed, not
      // left beside the real tabs.
      expect(workbook.tables.keys, isNot(contains('Sheet1')));
      expect(workbook.tables.length, 8);
    });

    test('an empty sheet list is rejected rather than writing a blank file', () {
      expect(
        () => ExcelIO.buildMultiSheetBytes(const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('filename carries the period', () {
      expect(
        MonthlyReportExcel.filename(_report()),
        'Growmont-Report-2025-06.xlsx',
      );
    });
  });

  group('figures match the report object', () {
    late MonthlyReport report;
    late xls.Excel workbook;

    setUp(() {
      report = _report();
      workbook = xls.Excel.decodeBytes(
        ExcelIO.buildMultiSheetBytes(MonthlyReportExcel.sheets(report)),
      );
    });

    test('summary revenue and deals equal the rendered values', () {
      final summary = workbook.tables['Summary']!;

      final revenue = _rowStartingWith(summary, 'Revenue');
      expect(_num(revenue, 1), report.revenue.current / 100);
      expect(_num(revenue, 2), report.revenue.previous / 100);
      expect(_num(revenue, 3), report.revenue.change / 100);

      final deals = _rowStartingWith(summary, 'Deals closed');
      expect(_num(deals, 1), report.deals.current);
      expect(_num(deals, 2), report.deals.previous);
    });

    test('summary average deal matches the report getter', () {
      final row = _rowStartingWith(workbook.tables['Summary']!, 'Average deal value');
      expect(_num(row, 1), report.avgDealPaise / 100);
    });

    test('percent change cell is blank when there is no baseline', () {
      final noBaseline = _report(
        sales: [_sale(id: 'only', date: '2025-06-05', paise: 100000)],
      );
      final sheet = xls.Excel.decodeBytes(
        ExcelIO.buildMultiSheetBytes(MonthlyReportExcel.sheets(noBaseline)),
      ).tables['Summary']!;

      expect(noBaseline.revenue.percentChange, isNull);
      final row = _rowStartingWith(sheet, 'Revenue');
      // A blank cell, not a misleading 0%.
      expect(_num(row, 4), isNull);
    });

    test('follow-up rows match the report', () {
      final summary = workbook.tables['Summary']!;
      expect(
        _num(_rowStartingWith(summary, 'Follow-ups scheduled'), 1),
        report.followUpsScheduled,
      );
      expect(
        _num(_rowStartingWith(summary, 'Follow-ups with a past date'), 1),
        report.followUpsPastDue,
      );
    });

    test('product breakdown totals reconcile to revenue', () {
      final sheet = workbook.tables['Revenue by Product']!;
      final total = _rowStartingWith(sheet, 'Total');

      expect(_num(total, 1), report.deals.current);
      expect(_num(total, 2), report.revenue.current / 100);
      // Share is written as a fraction so Excel's percent format renders
      // it; the whole table is therefore 1, not 100.
      expect(_num(total, 3), 1);
    });

    test('trend tab has one row per month plus a header', () {
      final sheet = workbook.tables['Monthly Trend']!;
      expect(sheet.rows.length, report.trailingRevenue.length + 1);

      // Last data row is the selected month.
      final last = sheet.rows.last;
      expect(last.first?.value?.toString(), 'Jun 2025');
      expect(_num(last, 2), report.revenue.current / 100);
    });

    test('team totals reconcile to company revenue', () {
      final sheet = workbook.tables['Team Performance']!;
      final total = _rowStartingWith(sheet, 'Total');
      expect(_num(total, 2), report.revenue.current / 100);
      expect(_num(total, 1), report.deals.current);
    });

    test('top deals are written largest first', () {
      final sheet = workbook.tables['Top Deals']!;
      // Row 0 is the header.
      expect(_num(sheet.rows[1], 5), 5000.0);
      expect(_num(sheet.rows[2], 5), 2500.0);
    });
  });

  group('notes tab', () {
    test('states the untracked metrics', () {
      final sheet = xls.Excel.decodeBytes(
        ExcelIO.buildMultiSheetBytes(MonthlyReportExcel.sheets(_report())),
      ).tables['Notes']!;

      final text = sheet.rows
          .expand((r) => r)
          .map((c) => c?.value?.toString() ?? '')
          .join('\n');

      expect(text, contains('Not tracked in this CRM'));
      expect(text, contains('Leads generated'));
      expect(text, contains('Deals won vs lost'));
      expect(kUntrackedMetrics, isNotEmpty);
    });

    test('reports the data-quality counts', () {
      final report = _report(
        sales: [
          _sale(id: 'a', date: '2025-06-02'),
          _sale(id: 'bad', date: ''),
        ],
        clients: const [
          Client(id: 'c9', name: 'No Date Ltd', contactNumber: '1'),
        ],
      );
      final sheet = xls.Excel.decodeBytes(
        ExcelIO.buildMultiSheetBytes(MonthlyReportExcel.sheets(report)),
      ).tables['Notes']!;

      expect(
        _num(_rowStartingWith(sheet, 'Sales with no usable date'), 1),
        report.quality.salesWithoutDate,
      );
      expect(
        _num(_rowStartingWith(sheet, 'Clients with no creation date'), 1),
        report.quality.clientsWithoutCreatedAt,
      );
      // And says what that means for the figure above.
      final row = _rowStartingWith(sheet, 'Clients with no creation date');
      expect(row[2]?.value?.toString(), contains('minimum, not a total'));
    });
  });

  group('existing single-sheet export is unchanged', () {
    test('buildBytes still produces a one-tab workbook', () {
      final bytes = ExcelIO.buildBytes(
        sheetName: 'Sales',
        headers: const ['Date', 'Amount'],
        rows: [
          [DateTime(2025, 6, 1), 1234.5],
        ],
      );
      final workbook = xls.Excel.decodeBytes(bytes);
      expect(workbook.tables.length, 1);
      expect(workbook.tables.keys.single, 'Sales');
    });
  });
}
