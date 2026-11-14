// lib/core/reports/monthly_report_excel.dart
//
// Turns a [MonthlyReport] into workbook tabs.
//
// Every figure here is read off the same [MonthlyReport] instance the
// screen renders — nothing is recomputed — which is what guarantees the
// export and the dashboard can never disagree. If you need a new figure
// in the export, add it to MonthlyReport first.
//
// Amounts are written as rupee doubles rather than formatted strings so
// the reader can sum a column in Excel. The paise ints stay internal.

import 'package:intl/intl.dart';

import '../excel/excel_io.dart';
import 'monthly_report.dart';

/// Human-readable labels for the metrics that this CRM cannot produce, so
/// a reader of the export is told the same thing the screen tells them.
const List<String> kUntrackedMetrics = [
  'Leads generated — this CRM has no lead record; a client is created directly.',
  'Lead conversion rate — no lead-to-client transition is stored.',
  'Deals won vs lost — a sale has no outcome field; only closed sales are recorded.',
  'Sales pipeline by stage — there are no pipeline stages.',
  'Tasks completed vs pending — reminders carry no completion flag.',
  'Follow-ups completed — an interaction has no completion flag; only the scheduled date is stored.',
];

class MonthlyReportExcel {
  const MonthlyReportExcel._();

  /// Suggested filename, e.g. `Growmont-Report-2025-06.xlsx`.
  static String filename(MonthlyReport report) =>
      'Growmont-Report-${report.period}.xlsx';

  /// The workbook tabs, in reading order.
  static List<ExcelSheet> sheets(MonthlyReport report) {
    final periodName = DateFormat('MMMM yyyy').format(report.period.start);
    final previousName = DateFormat('MMMM yyyy').format(
      report.period.previous.start,
    );

    return [
      _summarySheet(report, periodName, previousName),
      _breakdownSheet('Revenue by Product', report.revenueByProduct),
      _breakdownSheet('Revenue by Company', report.revenueByCompany),
      _breakdownSheet('Revenue by Frequency', report.revenueByFrequency),
      _trendSheet(report),
      _topDealsSheet(report),
      if (report.team.isNotEmpty) _teamSheet(report, previousName),
      _notesSheet(report, periodName),
    ];
  }

  // ── Summary ────────────────────────────────────────────────────────────

  static ExcelSheet _summarySheet(
    MonthlyReport report,
    String periodName,
    String previousName,
  ) {
    final generated = DateFormat('dd MMM yyyy, h:mm a').format(
      report.generatedAt,
    );

    // Metrics are declared, not hand-laid-out, so the number formats and
    // the row contents cannot drift apart: a summary table whose rows are
    // alternately money and counts cannot be described column-wise, so
    // each row contributes its own per-cell formats as it is built.
    final metrics = <({String label, MetricDelta delta, bool money, String basis})>[
      (label: 'Revenue', delta: report.revenue, money: true, basis: 'Sale date'),
      (label: 'Deals closed', delta: report.deals, money: false, basis: 'Sale date'),
      (label: 'Average deal value', delta: report.avgDeal, money: true, basis: 'Sale date'),
      (label: 'Active clients', delta: report.activeClients, money: false, basis: 'Sale date (distinct clients)'),
      (label: 'New clients added', delta: report.newClients, money: false, basis: 'Client creation date'),
      (label: 'Interactions logged', delta: report.interactions, money: false, basis: 'Interaction date'),
    ];

    final rows = <List<Object?>>[
      ['Growmont CRM — Monthly Report'],
      ['$periodName  ·  ${report.scope == ReportScope.company ? 'Whole company' : report.scopeLabel}'],
      [],
      ['Reporting period', periodName],
      ['Compared against', previousName],
      [
        'Scope',
        report.scope == ReportScope.company ? 'Whole company' : report.scopeLabel,
      ],
      ['Generated', generated],
      // The timezone is part of the result, not trivia: it decides which
      // month a sale dated near a month boundary belongs to.
      ['Period computed in', report.generatedAt.timeZoneName],
      [],
      ['Performance'],
    ];

    final headerRow = rows.length;
    rows.add([
      'Metric',
      periodName,
      previousName,
      'Change',
      'Change %',
      'Based on',
    ]);

    final cellFormats = <(int, int), ExcelNumberFormat>{};

    for (final metric in metrics) {
      final index = rows.length;
      rows.add(_metricRow(metric.label, metric.delta,
          asRupees: metric.money, basis: metric.basis));
      final format =
          metric.money ? ExcelNumberFormat.rupees : ExcelNumberFormat.count;
      for (final column in [1, 2, 3]) {
        cellFormats[(index, column)] = format;
      }
      cellFormats[(index, 4)] = ExcelNumberFormat.signedPercent;
    }

    for (final followUp in [
      ('Follow-ups scheduled', report.followUpsScheduled, 'Follow-up date'),
      (
        'Follow-ups with a past date',
        report.followUpsPastDue,
        'Follow-up date vs report date',
      ),
    ]) {
      cellFormats[(rows.length, 1)] = ExcelNumberFormat.count;
      rows.add([followUp.$1, followUp.$2, null, null, null, followUp.$3]);
    }

    return ExcelSheet(
      name: 'Summary',
      titleRows: const {0},
      sectionRows: const {9},
      headerRows: {headerRow},
      boldFirstColumn: true,
      cellFormats: cellFormats,
      columnWidths: const {0: 30, 1: 18, 2: 18, 3: 16, 4: 12, 5: 32},
      rows: rows,
    );
  }

  static List<Object?> _metricRow(
    String label,
    MetricDelta delta, {
    bool asRupees = false,
    required String basis,
  }) {
    num toCell(num paiseOrCount) =>
        asRupees ? paiseOrCount / 100 : paiseOrCount;

    final percent = delta.percentChange;
    return [
      label,
      toCell(delta.current),
      toCell(delta.previous),
      toCell(delta.change),
      // Written as a FRACTION so Excel's own percent format renders it
      // (0.2953 -> +29.5%), which keeps the cell a real number a reader
      // can chart or compare.
      //
      // Null, not 0, when there is no baseline - a blank cell is honest
      // where "0%" would read as "no change".
      percent == null ? null : double.parse((percent / 100).toStringAsFixed(4)),
      basis,
    ];
  }

  // ── Breakdowns ─────────────────────────────────────────────────────────

  static ExcelSheet _breakdownSheet(String name, List<CategoryTotal> rows) {
    final total = rows.fold<int>(0, (sum, r) => sum + r.paise);

    return ExcelSheet(
      name: name,
      headers: const ['Category', 'Deals', 'Amount', 'Share'],
      columnFormats: const {
        1: ExcelNumberFormat.count,
        2: ExcelNumberFormat.rupees,
        3: ExcelNumberFormat.signedPercent,
      },
      columnWidths: const {0: 26, 1: 10, 2: 16, 3: 10},
      // The last line is the total.
      boldRows: {rows.isEmpty ? -1 : rows.length},
      rows: [
        for (final row in rows)
          [
            row.label,
            row.count,
            row.rupees,
            total == 0 ? 0 : double.parse((row.paise / total).toStringAsFixed(4)),
          ],
        if (rows.isNotEmpty)
          ['Total', rows.fold<int>(0, (s, r) => s + r.count), total / 100, 1],
      ],
    );
  }

  // ── Trend ──────────────────────────────────────────────────────────────

  static ExcelSheet _trendSheet(MonthlyReport report) {
    return ExcelSheet(
      name: 'Monthly Trend',
      headers: const ['Month', 'Deals', 'Revenue'],
      columnFormats: const {
        1: ExcelNumberFormat.count,
        2: ExcelNumberFormat.rupees,
      },
      columnWidths: const {0: 14, 1: 10, 2: 16},
      rows: [
        for (final month in report.trailingRevenue)
          [
            DateFormat('MMM yyyy').format(month.month.start),
            month.count,
            month.rupees,
          ],
      ],
    );
  }

  // ── Top deals ──────────────────────────────────────────────────────────

  static ExcelSheet _topDealsSheet(MonthlyReport report) {
    return ExcelSheet(
      name: 'Top Deals',
      headers: const [
        'Date',
        'Client',
        'Product',
        'Company',
        'Sales rep',
        'Amount',
      ],
      columnFormats: const {5: ExcelNumberFormat.rupees},
      columnWidths: const {0: 12, 1: 26, 2: 20, 3: 16, 4: 20, 5: 16},
      rows: [
        for (final sale in report.topDeals)
          [
            parseEventDate(sale.date),
            sale.clientName,
            sale.productDisplay?.isNotEmpty == true
                ? sale.productDisplay!
                : sale.product,
            sale.company,
            sale.salesRepName ?? sale.salesRep,
            sale.amountPaise != 0
                ? sale.amountPaise / 100
                : double.tryParse(sale.amount) ?? 0,
          ],
      ],
    );
  }

  // ── Team ───────────────────────────────────────────────────────────────

  static ExcelSheet _teamSheet(MonthlyReport report, String previousName) {
    return ExcelSheet(
      name: 'Team Performance',
      headers: [
        'Employee',
        'Deals',
        'Revenue',
        'Average deal',
        'Interactions',
        '$previousName revenue',
        'Change',
      ],
      columnFormats: const {
        1: ExcelNumberFormat.count,
        2: ExcelNumberFormat.rupees,
        3: ExcelNumberFormat.rupees,
        4: ExcelNumberFormat.count,
        5: ExcelNumberFormat.rupees,
        6: ExcelNumberFormat.signedPercent,
      },
      columnWidths: const {0: 24, 1: 10, 2: 16, 3: 16, 4: 14, 5: 20, 6: 12},
      boldRows: {report.team.length},
      rows: [
        for (final row in report.team)
          [
            row.name,
            row.dealCount,
            row.revenueRupees,
            row.avgDealPaise / 100,
            row.interactionCount,
            row.previousRevenuePaise / 100,
            row.revenueDelta.percentChange == null
                ? null
                : double.parse(
                    (row.revenueDelta.percentChange! / 100).toStringAsFixed(4),
                  ),
          ],
        if (report.team.isNotEmpty)
          [
            'Total',
            report.team.fold<int>(0, (s, r) => s + r.dealCount),
            report.team.fold<int>(0, (s, r) => s + r.revenuePaise) / 100,
            null,
            report.team.fold<int>(0, (s, r) => s + r.interactionCount),
            report.team.fold<int>(0, (s, r) => s + r.previousRevenuePaise) /
                100,
            null,
          ],
      ],
    );
  }

  // ── Notes ──────────────────────────────────────────────────────────────

  /// The caveats that make the rest of the workbook trustworthy. Shipped
  /// as a tab rather than a footnote so they survive being emailed on.
  static ExcelSheet _notesSheet(MonthlyReport report, String periodName) {
    final quality = report.quality;

    return ExcelSheet(
      name: 'Notes',
      titleRows: const {0},
      // Row 7 is the data-quality heading, row 12 the untracked list.
      sectionRows: const {7, 12},
      boldFirstColumn: true,
      columnWidths: const {0: 30, 1: 12, 2: 70},
      rows: [
        ['How to read this report'],
        [],
        [
          'Period',
          'A month runs from the 1st to the last day inclusive. A record '
              'belongs to the month shown on its date in the app.',
        ],
        [
          'Revenue',
          'The sum of sales dated in the period. Every sale in this CRM is '
              'a completed sale.',
        ],
        [
          'Historical figures',
          'This report is recalculated from current records each time it is '
              'opened. Editing or deleting an old sale changes that month\'s '
              'figures. No month-end snapshot is stored.',
        ],
        [
          'Attribution',
          'Each sale keeps the employee who recorded it, so a past month\'s '
              'split stays correct even after clients are transferred.',
        ],
        [],
        ['Data quality for $periodName'],
        [
          'Sales with no usable date',
          quality.salesWithoutDate,
          quality.salesWithoutDate > 0
              ? 'Excluded from every month. Fix the date on these records.'
              : 'None.',
        ],
        [
          'Interactions with no usable date',
          quality.interactionsWithoutDate,
          quality.interactionsWithoutDate > 0
              ? 'Excluded from every month.'
              : 'None.',
        ],
        [
          'Clients with no creation date',
          quality.clientsWithoutCreatedAt,
          quality.clientsWithoutCreatedAt > 0
              ? 'Cannot be counted as newly added in any month, so '
                  '"New clients added" is a minimum, not a total.'
              : 'None.',
        ],
        [],
        ['Not tracked in this CRM'],
        for (final item in kUntrackedMetrics) [item],
      ],
    );
  }
}
