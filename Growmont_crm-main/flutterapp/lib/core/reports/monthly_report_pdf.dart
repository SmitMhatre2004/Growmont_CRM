// lib/core/reports/monthly_report_pdf.dart
//
// Renders a [MonthlyReport] as a printable A4 PDF.
//
// Like the Excel export, every figure is read off the same MonthlyReport
// instance the screen renders — nothing is recomputed here — so the three
// outputs cannot drift apart. See monthly_report_excel.dart's header.
//
// Fonts: the PDF embeds the app's bundled Inter faces. This is not a
// branding nicety — the pdf package's built-in Helvetica has no glyph for
// the rupee sign (U+20B9), so a report rendered with it would print blank
// where every amount's symbol should be. [ReportPdfFonts.load] falls back
// to Helvetica with an "Rs." prefix if the asset cannot be read, which is
// ugly but legible, rather than failing the export outright.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'monthly_report.dart';
import 'monthly_report_excel.dart' show kUntrackedMetrics;

/// Brand colours, mirroring AppColors. Duplicated as [PdfColor] rather
/// than converted at runtime because this file must stay free of
/// `dart:ui` — it has to run under `flutter test` without a window.
class _Ink {
  _Ink._();
  static const navy = PdfColor.fromInt(0xFF00337C);
  static const navyDeep = PdfColor.fromInt(0xFF001C4A);
  static const green = PdfColor.fromInt(0xFF246E3F);
  static const danger = PdfColor.fromInt(0xFFDC2626);
  static const warning = PdfColor.fromInt(0xFFB45309);
  static const text = PdfColor.fromInt(0xFF0F172A);
  static const muted = PdfColor.fromInt(0xFF64748B);
  static const faint = PdfColor.fromInt(0xFF94A3B8);
  static const border = PdfColor.fromInt(0xFFE2E8F0);
  static const sunken = PdfColor.fromInt(0xFFF8FAFC);
  static const white = PdfColor.fromInt(0xFFFFFFFF);
}

/// The typefaces a report is drawn with, plus whether they can render the
/// rupee sign.
class ReportPdfFonts {
  const ReportPdfFonts({
    required this.regular,
    required this.medium,
    required this.bold,
    required this.unicodeSafe,
  });

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;

  /// False when we fell back to a core font, in which case amounts are
  /// prefixed "Rs." instead of the symbol.
  final bool unicodeSafe;

  /// Loads Inter from the app bundle. Never throws: a missing or
  /// unreadable font asset degrades to Helvetica rather than blocking the
  /// export.
  static Future<ReportPdfFonts> load() async {
    try {
      final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter-400.ttf'),
      );
      final medium = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter-600.ttf'),
      );
      final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter-700.ttf'),
      );
      return ReportPdfFonts(
        regular: regular,
        medium: medium,
        bold: bold,
        unicodeSafe: true,
      );
    } catch (_) {
      return ReportPdfFonts(
        regular: pw.Font.helvetica(),
        medium: pw.Font.helveticaBold(),
        bold: pw.Font.helveticaBold(),
        unicodeSafe: false,
      );
    }
  }

  /// Core fonts only — for tests and for any caller that must not touch
  /// the asset bundle.
  factory ReportPdfFonts.core() => ReportPdfFonts(
    regular: pw.Font.helvetica(),
    medium: pw.Font.helveticaBold(),
    bold: pw.Font.helveticaBold(),
    unicodeSafe: false,
  );
}

class MonthlyReportPdf {
  const MonthlyReportPdf._();

  /// Suggested filename, matching the Excel export's convention.
  static String filename(MonthlyReport report) =>
      'Growmont-Report-${report.period}.pdf';

  /// Builds the document bytes. Synchronous apart from the pdf package's
  /// own save step, so the whole report can be rendered from a single
  /// already-loaded [MonthlyReport].
  static Future<Uint8List> build(
    MonthlyReport report,
    ReportPdfFonts fonts,
  ) async {
    final f = _Fmt(fonts);
    final doc = pw.Document(
      title: 'Growmont CRM — Monthly Report ${report.period}',
      author: 'Growmont CRM',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 36),
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
        ),
        header: (context) =>
            context.pageNumber == 1 ? pw.SizedBox() : _runningHeader(report, f),
        footer: (context) => _footer(context, report, f),
        build: (context) => [
          _titleBlock(report, f),
          pw.SizedBox(height: 16),
          _kpiGrid(report, f),
          pw.SizedBox(height: 16),
          _comparisonTable(report, f),
          pw.SizedBox(height: 16),
          _trendBlock(report, f),
          pw.SizedBox(height: 16),
          if (report.revenueByProduct.isNotEmpty) ...[
            _breakdownBlock('Revenue by product', report.revenueByProduct, f),
            pw.SizedBox(height: 16),
          ],
          if (report.revenueByCompany.isNotEmpty) ...[
            _breakdownBlock('Revenue by company', report.revenueByCompany, f),
            pw.SizedBox(height: 16),
          ],
          if (report.revenueByFrequency.isNotEmpty) ...[
            _breakdownBlock(
              'Revenue by payment frequency',
              report.revenueByFrequency,
              f,
            ),
            pw.SizedBox(height: 16),
          ],
          _activityBlock(report, f),
          pw.SizedBox(height: 16),
          if (report.topDeals.isNotEmpty) ...[
            _topDealsBlock(report, f),
            pw.SizedBox(height: 16),
          ],
          if (report.team.isNotEmpty) ...[
            _teamBlock(report, f),
            pw.SizedBox(height: 16),
          ],
          if (report.quality.hasIssues) ...[
            _qualityBlock(report, f),
            pw.SizedBox(height: 16),
          ],
          _notesBlock(f),
        ],
      ),
    );

    return doc.save();
  }

  // ── Chrome ────────────────────────────────────────────────────────────

  static pw.Widget _titleBlock(MonthlyReport report, _Fmt f) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: const pw.BoxDecoration(
        color: _Ink.navy,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          f.text(
            'Growmont CRM',
            style: f.style(9, color: _Ink.white, weight: _W.medium, spacing: 1.4),
          ),
          pw.SizedBox(height: 4),
          f.text(
            'Monthly Report — ${f.monthName(report.period)}',
            style: f.style(20, color: _Ink.white, weight: _W.bold),
          ),
          pw.SizedBox(height: 8),
          f.text(
            '${report.scopeLabel}  ·  '
            '${f.dayRange(report.period)}  ·  '
            'compared against ${f.monthName(report.period.previous)}',
            style: f.style(9, color: PdfColor.fromInt(0xFFB8CCEB)),
          ),
          pw.SizedBox(height: 2),
          f.text(
            'Generated ${f.dateTime(report.generatedAt)} '
            '(${report.generatedAt.timeZoneName}) from synced data',
            style: f.style(8, color: PdfColor.fromInt(0xFF86A7DA)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _runningHeader(MonthlyReport report, _Fmt f) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _Ink.border)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          f.text(
            'Growmont CRM — Monthly Report',
            style: f.style(8, color: _Ink.muted, weight: _W.medium),
          ),
          f.text(
            '${f.monthName(report.period)}  ·  ${report.scopeLabel}',
            style: f.style(8, color: _Ink.muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context, MonthlyReport report, _Fmt f) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          f.text(
            'Figures are recalculated from current records — no month-end '
            'snapshot is stored.',
            style: f.style(7, color: _Ink.faint),
          ),
          f.text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: f.style(7, color: _Ink.faint),
          ),
        ],
      ),
    );
  }

  static pw.Widget _section(String title, pw.Widget child, _Fmt f,
      {String? subtitle}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        f.text(title, style: f.style(12, weight: _W.bold, color: _Ink.navyDeep)),
        if (subtitle != null) ...[
          pw.SizedBox(height: 2),
          f.text(subtitle, style: f.style(8, color: _Ink.muted)),
        ],
        pw.SizedBox(height: 8),
        child,
      ],
    );
  }

  // ── KPIs ──────────────────────────────────────────────────────────────

  static pw.Widget _kpiGrid(MonthlyReport report, _Fmt f) {
    final previous = f.monthName(report.period.previous, short: true);

    final tiles = <pw.Widget>[
      _kpiTile('Revenue', f.paise(report.revenue.current), report.revenue,
          previous, f, valueColor: _Ink.green, note: 'By sale date'),
      _kpiTile('Deals closed', '${report.deals.current}', report.deals,
          previous, f, note: 'Every recorded sale is closed'),
      _kpiTile('Average deal', f.paise(report.avgDealPaise), report.avgDeal,
          previous, f, note: 'Revenue / deals'),
      _kpiTile('Active clients', '${report.activeClients.current}',
          report.activeClients, previous, f, note: 'Distinct clients who bought'),
      _kpiTile('New clients', '${report.newClients.current}',
          report.newClients, previous, f,
          note: report.quality.clientsWithoutCreatedAt > 0
              ? 'By date added — a minimum, see notes'
              : 'By date added'),
      _kpiTile('Interactions', '${report.interactions.current}',
          report.interactions, previous, f, note: 'Conversations logged'),
    ];

    // Two rows of three. A pdf Table keeps the columns equal without
    // needing to measure anything.
    return pw.Table(
      children: [
        for (var row = 0; row < 2; row++)
          pw.TableRow(
            children: [
              for (var col = 0; col < 3; col++)
                pw.Padding(
                  padding: pw.EdgeInsets.only(
                    right: col < 2 ? 8 : 0,
                    bottom: row == 0 ? 8 : 0,
                  ),
                  child: tiles[row * 3 + col],
                ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _kpiTile(
    String label,
    String value,
    MetricDelta delta,
    String previousLabel,
    _Fmt f, {
    PdfColor valueColor = _Ink.text,
    String? note,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: const pw.BoxDecoration(
        color: _Ink.sunken,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.fromBorderSide(pw.BorderSide(color: _Ink.border)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          f.text(
            label.toUpperCase(),
            style: f.style(7, color: _Ink.muted, weight: _W.medium, spacing: 0.8),
          ),
          pw.SizedBox(height: 5),
          f.text(value, style: f.style(15, weight: _W.bold, color: valueColor)),
          pw.SizedBox(height: 4),
          f.text(
            f.deltaText(delta, previousLabel),
            style: f.style(7.5, color: f.deltaColor(delta), weight: _W.medium),
          ),
          if (note != null) ...[
            pw.SizedBox(height: 2),
            f.text(note, style: f.style(6.5, color: _Ink.faint)),
          ],
        ],
      ),
    );
  }

  // ── Tables ────────────────────────────────────────────────────────────

  static pw.Widget _comparisonTable(MonthlyReport report, _Fmt f) {
    final current = f.monthName(report.period, short: true);
    final previous = f.monthName(report.period.previous, short: true);

    final rows = <({String label, MetricDelta delta, bool money})>[
      (label: 'Revenue', delta: report.revenue, money: true),
      (label: 'Deals closed', delta: report.deals, money: false),
      (label: 'Average deal value', delta: report.avgDeal, money: true),
      (label: 'Active clients', delta: report.activeClients, money: false),
      (label: 'New clients', delta: report.newClients, money: false),
      (label: 'Interactions', delta: report.interactions, money: false),
    ];

    return _section(
      'Month-over-month',
      _table(
        f,
        headers: ['Metric', current, previous, 'Change', 'Change %'],
        flex: const [4, 3, 3, 3, 2],
        align: const [
          pw.TextAlign.left,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
        ],
        rows: [
          for (final row in rows)
            [
              _Cell(row.label),
              _Cell(
                row.money
                    ? f.paise(row.delta.current)
                    : '${row.delta.current.round()}',
              ),
              _Cell(
                row.money
                    ? f.paise(row.delta.previous)
                    : '${row.delta.previous.round()}',
                color: _Ink.muted,
              ),
              _Cell(
                row.money
                    ? f.signedPaise(row.delta.change)
                    : f.signedCount(row.delta.change),
                color: f.deltaColor(row.delta),
              ),
              _Cell(
                f.percentText(row.delta),
                color: f.deltaColor(row.delta),
              ),
            ],
        ],
      ),
      f,
      subtitle: 'Each metric against the same metric one month earlier',
    );
  }

  static pw.Widget _breakdownBlock(
    String title,
    List<CategoryTotal> rows,
    _Fmt f,
  ) {
    final shown = rows.take(10).toList();
    final total = rows.fold<int>(0, (sum, r) => sum + r.paise);
    final peak = shown.fold<int>(0, (best, r) => r.paise > best ? r.paise : best);

    return _section(
      title,
      pw.Column(
        children: [
          _table(
            f,
            headers: const ['Category', 'Deals', 'Amount', 'Share', ''],
            flex: const [5, 2, 3, 2, 4],
            align: const [
              pw.TextAlign.left,
              pw.TextAlign.right,
              pw.TextAlign.right,
              pw.TextAlign.right,
              pw.TextAlign.left,
            ],
            rows: [
              for (final row in shown)
                [
                  _Cell(row.label),
                  _Cell('${row.count}'),
                  _Cell(f.paise(row.paise), color: _Ink.green),
                  _Cell(
                    total == 0 ? f.dash : '${(row.paise / total * 100).round()}%',
                    color: _Ink.muted,
                  ),
                  _Cell.bar(peak == 0 ? 0 : row.paise / peak),
                ],
            ],
            footer: rows.length > shown.length
                ? [
                    _Cell(
                      '+ ${rows.length - shown.length} more categories',
                      color: _Ink.muted,
                    ),
                    _Cell(
                      '${rows.skip(shown.length).fold<int>(0, (s, r) => s + r.count)}',
                      color: _Ink.muted,
                    ),
                    _Cell(
                      f.paise(
                        rows.skip(shown.length).fold<int>(
                              0,
                              (s, r) => s + r.paise,
                            ),
                      ),
                      color: _Ink.muted,
                    ),
                    const _Cell(''),
                    const _Cell(''),
                  ]
                : null,
          ),
        ],
      ),
      f,
    );
  }

  static pw.Widget _trendBlock(MonthlyReport report, _Fmt f) {
    final peak = report.trailingRevenue.fold<int>(
      0,
      (best, m) => m.paise > best ? m.paise : best,
    );

    return _section(
      'Revenue trend',
      _table(
        f,
        headers: const ['Month', 'Deals', 'Revenue', ''],
        flex: const [3, 2, 3, 8],
        align: const [
          pw.TextAlign.left,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.left,
        ],
        rows: [
          for (final month in report.trailingRevenue)
            [
              _Cell(
                f.monthName(month.month, short: true),
                // The month being reported on is called out in the run.
                weight: month.month == report.period ? _W.bold : _W.regular,
                color: month.month == report.period ? _Ink.navy : _Ink.text,
              ),
              _Cell('${month.count}'),
              _Cell(
                month.paise == 0 ? f.dash : f.paise(month.paise),
                color: month.paise == 0 ? _Ink.faint : _Ink.green,
              ),
              _Cell.bar(
                peak == 0 ? 0 : month.paise / peak,
                color: month.month == report.period ? _Ink.navy : _Ink.border,
              ),
            ],
        ],
      ),
      f,
      subtitle:
          'Last ${report.trailingRevenue.length} months by sale date; '
          '${f.monthName(report.period, short: true)} highlighted',
    );
  }

  static pw.Widget _activityBlock(MonthlyReport report, _Fmt f) {
    return _section(
      'Client activity and follow-up load',
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _table(
            f,
            headers: const ['Interaction priority', 'Logs', ''],
            flex: const [5, 2, 9],
            align: const [
              pw.TextAlign.left,
              pw.TextAlign.right,
              pw.TextAlign.left,
            ],
            rows: [
              for (final row in report.interactionsByPriority)
                [
                  _Cell(row.label),
                  _Cell('${row.count}'),
                  const _Cell(''),
                ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              _miniStat(
                'Follow-ups scheduled',
                '${report.followUpsScheduled}',
                f,
              ),
              pw.SizedBox(width: 24),
              _miniStat(
                'Date already passed',
                '${report.followUpsPastDue}',
                f,
                color: report.followUpsPastDue > 0 ? _Ink.warning : _Ink.text,
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          _note(
            'An interaction has no "done" field in this CRM, so these count '
            'follow-ups whose date falls in the month — not whether anyone '
            'acted on them.',
            f,
          ),
        ],
      ),
      f,
    );
  }

  static pw.Widget _miniStat(
    String label,
    String value,
    _Fmt f, {
    PdfColor color = _Ink.text,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        f.text(
          label.toUpperCase(),
          style: f.style(7, color: _Ink.muted, weight: _W.medium, spacing: 0.8),
        ),
        pw.SizedBox(height: 3),
        f.text(value, style: f.style(13, weight: _W.bold, color: color)),
      ],
    );
  }

  static pw.Widget _topDealsBlock(MonthlyReport report, _Fmt f) {
    return _section(
      'Largest deals',
      _table(
        f,
        headers: const ['Date', 'Client', 'Product', 'Sales rep', 'Amount'],
        flex: const [2, 5, 3, 4, 3],
        align: const [
          pw.TextAlign.left,
          pw.TextAlign.left,
          pw.TextAlign.left,
          pw.TextAlign.left,
          pw.TextAlign.right,
        ],
        rows: [
          for (final sale in report.topDeals)
            [
              _Cell(f.shortDate(sale.date)),
              _Cell(sale.clientName.isEmpty ? f.dash : sale.clientName),
              _Cell(
                sale.productDisplay?.isNotEmpty == true
                    ? sale.productDisplay!
                    : sale.product,
              ),
              _Cell(sale.salesRepName ?? sale.salesRep),
              _Cell(
                f.paise(
                  sale.amountPaise != 0
                      ? sale.amountPaise
                      : ((double.tryParse(sale.amount) ?? 0) * 100).round(),
                ),
                color: _Ink.green,
                weight: _W.medium,
              ),
            ],
        ],
      ),
      f,
    );
  }

  static pw.Widget _teamBlock(MonthlyReport report, _Fmt f) {
    final previous = f.monthName(report.period.previous, short: true);

    return _section(
      'Team performance',
      _table(
        f,
        headers: ['Employee', 'Deals', 'Revenue', 'Avg deal', 'Logs', previous,
            'Change'],
        flex: const [5, 2, 3, 3, 2, 3, 2],
        align: const [
          pw.TextAlign.left,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
          pw.TextAlign.right,
        ],
        rows: [
          for (final row in report.team)
            [
              _Cell(row.name, weight: _W.medium),
              _Cell('${row.dealCount}'),
              _Cell(f.paise(row.revenuePaise), color: _Ink.green),
              _Cell(f.paise(row.avgDealPaise)),
              _Cell('${row.interactionCount}'),
              _Cell(f.paise(row.previousRevenuePaise), color: _Ink.muted),
              _Cell(
                f.percentText(row.revenueDelta),
                color: f.deltaColor(row.revenueDelta),
              ),
            ],
        ],
        footer: [
          const _Cell('Total', weight: _W.bold),
          _Cell(
            '${report.team.fold<int>(0, (s, r) => s + r.dealCount)}',
            weight: _W.bold,
          ),
          _Cell(
            f.paise(report.team.fold<int>(0, (s, r) => s + r.revenuePaise)),
            weight: _W.bold,
            color: _Ink.green,
          ),
          const _Cell(''),
          _Cell(
            '${report.team.fold<int>(0, (s, r) => s + r.interactionCount)}',
            weight: _W.bold,
          ),
          _Cell(
            f.paise(
              report.team.fold<int>(0, (s, r) => s + r.previousRevenuePaise),
            ),
            weight: _W.bold,
            color: _Ink.muted,
          ),
          const _Cell(''),
        ],
      ),
      f,
      subtitle:
          'By the employee recorded on each sale, so transfers do not move '
          'past credit',
    );
  }

  static pw.Widget _qualityBlock(MonthlyReport report, _Fmt f) {
    final quality = report.quality;
    final parts = <String>[
      if (quality.salesWithoutDate > 0)
        '${quality.salesWithoutDate} sale(s) have no usable date',
      if (quality.interactionsWithoutDate > 0)
        '${quality.interactionsWithoutDate} interaction(s) have no usable date',
      if (quality.clientsWithoutCreatedAt > 0)
        '${quality.clientsWithoutCreatedAt} client(s) have no date added',
    ];

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFFFF7ED),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.fromBorderSide(pw.BorderSide(color: _Ink.warning)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          f.text(
            'Some records could not be placed in a month',
            style: f.style(9, weight: _W.bold, color: _Ink.warning),
          ),
          pw.SizedBox(height: 3),
          f.text(
            '${parts.join('; ')}. These are left out of every month rather '
            'than guessed at, so the totals above are a minimum. Fixing the '
            'dates on those records will correct the figures.',
            style: f.style(8, color: _Ink.warning),
          ),
        ],
      ),
    );
  }

  static pw.Widget _notesBlock(_Fmt f) {
    return _section(
      'How to read this report',
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _note(
            'A month runs from the 1st to the last day inclusive. A record '
            'belongs to the month shown on its date in the app. Figures are '
            'recalculated from current records every time the report is '
            'opened, so editing or deleting an old sale changes that '
            'month\'s numbers — no month-end snapshot is stored.',
            f,
          ),
          pw.SizedBox(height: 10),
          f.text(
            'Not tracked in this CRM',
            style: f.style(9, weight: _W.bold, color: _Ink.navyDeep),
          ),
          pw.SizedBox(height: 4),
          for (final item in kUntrackedMetrics)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  f.text('·  ', style: f.style(8, color: _Ink.faint)),
                  pw.Expanded(
                    child: f.text(item, style: f.style(8, color: _Ink.muted)),
                  ),
                ],
              ),
            ),
        ],
      ),
      f,
    );
  }

  static pw.Widget _note(String text, _Fmt f) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: const pw.BoxDecoration(
        color: _Ink.sunken,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.fromBorderSide(pw.BorderSide(color: _Ink.border)),
      ),
      child: f.text(text, style: f.style(8, color: _Ink.muted)),
    );
  }

  // ── Generic table ─────────────────────────────────────────────────────

  /// A header row plus body rows, laid out with [flex] column weights.
  ///
  /// Built on pw.Table with explicit FlexColumnWidth rather than a
  /// TableHelper so a cell can carry a share-of-total bar as well as text.
  static pw.Widget _table(
    _Fmt f, {
    required List<String> headers,
    required List<int> flex,
    required List<pw.TextAlign> align,
    required List<List<_Cell>> rows,
    List<_Cell>? footer,
  }) {
    pw.Widget cell(_Cell c, pw.TextAlign a, {bool isHeader = false}) {
      if (c.barFraction != null) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: ((c.barFraction! * 100).round()).clamp(1, 100),
                child: pw.Container(height: 5, color: c.color ?? _Ink.navy),
              ),
              pw.Expanded(
                flex: (100 - (c.barFraction! * 100).round()).clamp(1, 100),
                child: pw.SizedBox(height: 5),
              ),
            ],
          ),
        );
      }
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: f.text(
          c.text,
          textAlign: a,
          maxLines: 2,
          style: isHeader
              ? f.style(7.5, color: _Ink.muted, weight: _W.medium, spacing: 0.4)
              : f.style(8.5, color: c.color ?? _Ink.text, weight: c.weight),
        ),
      );
    }

    return pw.Table(
      columnWidths: {
        for (var i = 0; i < flex.length; i++)
          i: pw.FlexColumnWidth(flex[i].toDouble()),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _Ink.border)),
          ),
          children: [
            for (var i = 0; i < headers.length; i++)
              cell(_Cell(headers[i].toUpperCase()), align[i], isHeader: true),
          ],
        ),
        for (final row in rows)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFF1F5F9)),
              ),
            ),
            children: [
              for (var i = 0; i < row.length; i++) cell(row[i], align[i]),
            ],
          ),
        if (footer != null)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _Ink.border)),
            ),
            children: [
              for (var i = 0; i < footer.length; i++) cell(footer[i], align[i]),
            ],
          ),
      ],
    );
  }
}

enum _W { regular, medium, bold }

/// One table cell: either text, or a proportional bar.
class _Cell {
  const _Cell(this.text, {this.color, this.weight = _W.regular})
      : barFraction = null;

  const _Cell.bar(double fraction, {this.color})
      : text = '',
        weight = _W.regular,
        barFraction = fraction;

  final String text;
  final PdfColor? color;
  final _W weight;
  final double? barFraction;
}

/// Formatting shared across the document, bound to the loaded fonts.
class _Fmt {
  _Fmt(this.fonts);

  final ReportPdfFonts fonts;

  late final NumberFormat _rupees = NumberFormat.decimalPattern('en_IN');

  /// Every piece of drawn text goes through here.
  ///
  /// The core fallback font has no glyph for the typographic punctuation
  /// used throughout the report (em dash, en dash, middle dot, rupee
  /// sign). The pdf package draws nothing at all for a missing glyph and
  /// logs a warning per occurrence, so a fallback-rendered report would
  /// quietly lose characters. Downgrading them to ASCII keeps that report
  /// plain but complete; when Inter is embedded the text passes through
  /// untouched.
  String safe(String value) {
    if (fonts.unicodeSafe) return value;
    return value
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('·', '-')
        .replaceAll('₹', 'Rs.');
  }

  /// [pw.Text] with [safe] applied. Used in place of pw.Text everywhere in
  /// this file so no call site can forget the sanitization.
  pw.Widget text(
    String value, {
    required pw.TextStyle style,
    pw.TextAlign? textAlign,
    int? maxLines,
  }) {
    return pw.Text(
      safe(value),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
    );
  }

  /// Em dash, or a hyphen on the fallback font. Means "no value".
  String get dash => fonts.unicodeSafe ? '—' : '-';

  /// En dash for numeric ranges, or a hyphen on the fallback font.
  String get enDash => fonts.unicodeSafe ? '–' : '-';

  pw.TextStyle style(
    double size, {
    PdfColor color = _Ink.text,
    _W weight = _W.regular,
    double? spacing,
  }) {
    return pw.TextStyle(
      font: switch (weight) {
        _W.regular => fonts.regular,
        _W.medium => fonts.medium,
        _W.bold => fonts.bold,
      },
      fontSize: size,
      color: color,
      letterSpacing: spacing,
    );
  }

  /// Rupee amount from paise, Indian-grouped and with no decimals — the
  /// same shape AppFormatters.formatAmount produces on screen.
  ///
  /// Falls back to an "Rs." prefix when the embedded font has no rupee
  /// glyph, since the symbol would otherwise print as a blank box.
  String paise(num paiseValue) {
    final rupees = (paiseValue / 100).round();
    final grouped = _rupees.format(rupees);
    return fonts.unicodeSafe ? '₹$grouped' : 'Rs. $grouped';
  }

  String signedPaise(num change) {
    if (change == 0) return dash;
    return '${change > 0 ? '+' : '-'}${paise(change.abs())}';
  }

  String signedCount(num change) {
    if (change == 0) return dash;
    return '${change > 0 ? '+' : '-'}${change.abs().round()}';
  }

  String percentText(MetricDelta delta) {
    final percent = delta.percentChange;
    if (percent == null) return dash;
    if (delta.isFlat) return 'flat';
    final magnitude = percent.abs();
    final formatted = magnitude >= 100
        ? magnitude.toStringAsFixed(0)
        : magnitude.toStringAsFixed(1);
    return '${percent > 0 ? '+' : '-'}$formatted%';
  }

  String deltaText(MetricDelta delta, String previousLabel) {
    final percent = delta.percentChange;
    if (percent == null) {
      return delta.current == 0
          ? 'no activity in $previousLabel'
          : 'new vs $previousLabel';
    }
    if (delta.isFlat) return 'flat vs $previousLabel';
    return '${percentText(delta)} vs $previousLabel';
  }

  PdfColor deltaColor(MetricDelta delta) {
    if (delta.percentChange == null || delta.isFlat) return _Ink.muted;
    return delta.isUp ? _Ink.green : _Ink.danger;
  }

  String monthName(ReportMonth month, {bool short = false}) =>
      DateFormat(short ? 'MMM yyyy' : 'MMMM yyyy').format(month.start);

  String dayRange(ReportMonth month) =>
      '1$enDash${month.dayCount} ${DateFormat('MMM yyyy').format(month.start)}';

  String dateTime(DateTime value) =>
      DateFormat('d MMM yyyy, h:mm a').format(value);

  String shortDate(String raw) {
    final parsed = parseEventDate(raw);
    return parsed == null ? dash : DateFormat('dd MMM').format(parsed);
  }
}
