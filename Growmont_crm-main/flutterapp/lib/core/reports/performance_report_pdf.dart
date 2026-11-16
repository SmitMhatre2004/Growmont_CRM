// lib/core/reports/performance_report_pdf.dart
//
// The admin-facing Performance Report: an A4 portrait PDF with a company
// overview (KPIs, revenue chart, team table, breakdowns, largest deals) and
// one section per employee. Titles, labels, numbers and tables only - no
// prose.
//
// Every figure is read off the PeriodSummary / EmployeeReport instances the
// phone Reports screen already renders; nothing is recomputed here except
// layout-only things (bucketing the daily series, percentages of a list's
// own total).
//
// Fonts: Inter (via ReportPdfFonts) for text, Plus Jakarta Sans for numbers
// and headings. If Jakarta cannot be read the Inter faces stand in.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../shared/widgets/monthly_revenue_chart.dart' show salePaise;
import '../theme/app_theme.dart' show productCategories;
import 'employee_report.dart';
import 'monthly_report.dart';
import 'monthly_report_builder.dart';
import 'monthly_report_pdf.dart' show ReportPdfFonts;
import 'period_summary_builder.dart';

/// Brand colours mirroring AppPalette (kept as PdfColor so this file stays
/// free of dart:ui).
class _C {
  _C._();
  static const navy = PdfColor.fromInt(0xFF00337C);
  static const green = PdfColor.fromInt(0xFF2D8A4E);
  static const greenDark = PdfColor.fromInt(0xFF246E3F);
  static const danger = PdfColor.fromInt(0xFFDC2626);
  static const text = PdfColor.fromInt(0xFF0F172A);
  static const label = PdfColor.fromInt(0xFF64748B);
  static const muted = PdfColor.fromInt(0xFF94A3B8);
  static const rule = PdfColor.fromInt(0xFFE2E8F0);
  static const amber = PdfColor.fromInt(0xFFF59E0B);
  static const white = PdfColor.fromInt(0xFFFFFFFF);
  static const zebra = PdfColor.fromInt(0xFFF8FAFC);
}

const double _kMargin = 36;
const double _kContentWidth = 595.28 - _kMargin * 2;

enum _Al { left, right }

class _Row {
  const _Row(this.cells, {this.muted = false, this.total = false});
  final List<String> cells;
  final bool muted;
  final bool total;
}

class PerformanceReportPdf {
  const PerformanceReportPdf._();

  /// e.g. "Growmont_Performance_Nov_2026.pdf" or
  /// "Growmont_Samir_Joshi_1-Oct_15-Nov_2026.pdf".
  static String fileName({required String periodLabel, String? employeeName}) {
    final period = _periodSlug(periodLabel);
    final name = employeeName == null ? '' : _nameSlug(employeeName);
    final parts = [
      'Growmont',
      if (name.isNotEmpty) name else 'Performance',
      if (period.isNotEmpty) period,
    ];
    return '${parts.join('_')}.pdf';
  }

  static String _periodSlug(String label) {
    final segments = label
        .split(RegExp(r'\s*[–—]\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final out = <String>[];
    for (final seg in segments) {
      final tokens = seg.split(RegExp(r'\s+'));
      final words = <String>[];
      String? year;
      for (final t in tokens) {
        if (RegExp(r'^\d{4}$').hasMatch(t)) {
          year = t;
        } else {
          final alpha = RegExp(r'^[A-Za-z]{4,}$').hasMatch(t);
          words.add(alpha ? t.substring(0, 3) : t);
        }
      }
      final head = words.join('-');
      out.add([head, ?year].where((s) => s.isNotEmpty).join('_'));
    }
    return out
        .join('_')
        .replaceAll(RegExp(r'[^\p{L}\p{N}_-]', unicode: true), '');
  }

  static String _nameSlug(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .join('_')
      .replaceAll(RegExp(r'[^\p{L}\p{N}_-]', unicode: true), '');

  static Future<Uint8List> build({
    required String periodLabel,
    required PeriodSummary summary,
    required List<EmployeeReport> employees,
    required bool companyScope,
    required DateTime generatedAt,
    String? generatedBy,
    ReportPdfFonts? fonts,
    Uint8List? logoOverride,
  }) async {
    final inter = fonts ?? await ReportPdfFonts.load();
    final jakarta = await _loadJakarta(inter);
    final logo = await _loadLogo(logoOverride);
    final k = _Kit(inter, jakarta);

    final doc = pw.Document(
      title: 'Growmont Performance Report - $periodLabel',
      author: 'Growmont CRM',
    );

    final body = <pw.Widget>[];
    if (companyScope) {
      body.addAll(_companyPages(k, periodLabel, summary, employees));
    } else {
      for (final e in employees.take(1)) {
        body.addAll(_employeeSection(k, e, periodLabel, standalone: true));
      }
    }

    final generated =
        'Generated ${DateFormat('d MMM yyyy').format(generatedAt)}'
        '${generatedBy != null && generatedBy.trim().isNotEmpty ? ' · by ${generatedBy.trim()}' : ''}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_kMargin),
        theme: pw.ThemeData.withFont(base: inter.regular, bold: inter.bold),
        header: (ctx) => _header(k, logo, periodLabel),
        footer: (ctx) => _footer(k, ctx, generated),
        build: (ctx) => body,
      ),
    );
    return doc.save();
  }

  // ── Assets ────────────────────────────────────────────────────────────

  static Future<_Jakarta> _loadJakarta(ReportPdfFonts inter) async {
    try {
      return _Jakarta(
        semi: pw.Font.ttf(
          await rootBundle.load('assets/fonts/PlusJakartaSans-600.ttf'),
        ),
        bold: pw.Font.ttf(
          await rootBundle.load('assets/fonts/PlusJakartaSans-700.ttf'),
        ),
      );
    } catch (_) {
      return _Jakarta(semi: inter.medium, bold: inter.bold);
    }
  }

  /// The logo as an image provider, or null (header falls back to a word
  /// mark). The full wordmark assets/images/growmont_logo.png is the
  /// default; assets/logo.svg wraps a base64 PNG in an SVG pattern, which
  /// the pdf package's SVG renderer cannot draw reliably, so the embedded
  /// PNG is extracted and drawn directly; app_icon.png is the fallback.
  static Future<pw.ImageProvider?> _loadLogo(Uint8List? override) async {
    if (override != null) return _tryImage(override);
    try {
      final data = await rootBundle.load('assets/images/growmont_logo.png');
      final img = _tryImage(data.buffer.asUint8List());
      if (img != null) return img;
    } catch (_) {}
    try {
      final svg = await rootBundle.loadString('assets/logo.svg');
      final m = RegExp(r'base64,([A-Za-z0-9+/=\s]+)"').firstMatch(svg);
      if (m != null) {
        final bytes = base64Decode(m.group(1)!.replaceAll(RegExp(r'\s+'), ''));
        final img = _tryImage(Uint8List.fromList(bytes));
        if (img != null) return img;
      }
    } catch (_) {}
    try {
      final data = await rootBundle.load('assets/icon/app_icon.png');
      return _tryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static pw.ImageProvider? _tryImage(Uint8List bytes) {
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // ── Page chrome ───────────────────────────────────────────────────────

  static pw.Widget _header(_Kit k, pw.ImageProvider? logo, String period) {
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            logo != null
                ? pw.Image(logo, height: 31)
                : k.head('Growmont', 13, color: _C.navy),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                k.head('Performance Report', 9.5, color: _C.navy),
                pw.SizedBox(height: 1.5),
                k.text(period, 8, color: _C.label),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Container(height: 0.6, color: _C.rule),
        pw.SizedBox(height: 14),
      ],
    );
  }

  static pw.Widget _footer(_Kit k, pw.Context ctx, String generated) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        children: [
          k.text(generated, 8, color: _C.muted),
          pw.Spacer(),
          k.text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            8,
            color: _C.muted,
          ),
        ],
      ),
    );
  }

  // ── Company pages ─────────────────────────────────────────────────────

  static bool _idle(EmployeeReport e) =>
      e.activity.isEmpty &&
      e.revenue.current == 0 &&
      e.deals.current == 0 &&
      e.interactions.current == 0 &&
      e.newClients.current == 0;

  static List<pw.Widget> _companyPages(
    _Kit k,
    String period,
    PeriodSummary s,
    List<EmployeeReport> employees,
  ) {
    final out = <pw.Widget>[
      _titleBlock(k, 'Company overview', period),
      pw.SizedBox(height: 14),
      _kpiStrip(k, [
        _Kpi(
          'Revenue',
          k.rupees(s.revenue.current.toInt()),
          s.revenue,
          percent: true,
        ),
        _Kpi('Deals', '${s.deals.current}', s.deals),
        _Kpi('Clients', '${s.clients.current}', s.clients),
        _Kpi('New clients', '${s.newClients.current}', s.newClients),
        _Kpi('Follow-ups', '${s.interactions.current}', s.interactions),
        _Kpi(
          'Overdue',
          '${s.followUpsOverdue}',
          null,
          alert: s.followUpsOverdue > 0,
        ),
      ]),
    ];

    if (s.isEmpty) {
      out.addAll([
        pw.SizedBox(height: 18),
        k.text('No activity in this period', 10, color: _C.muted),
      ]);
      return out;
    }

    // Revenue chart.
    final chart = _dailyChart(k, s.daily);
    if (chart != null) out.addAll([pw.SizedBox(height: 15), chart]);

    // Team table.
    // Same order the builders use for rank: revenue desc, deals desc, name.
    final active =
        [
          for (final e in employees)
            if (!_idle(e)) e,
        ]..sort((a, b) {
          final byRevenue = b.revenue.current.compareTo(a.revenue.current);
          if (byRevenue != 0) return byRevenue;
          final byDeals = b.deals.current.compareTo(a.deals.current);
          return byDeals != 0 ? byDeals : a.name.compareTo(b.name);
        });
    final idle = [
      for (final e in employees)
        if (_idle(e)) e,
    ]..sort((a, b) => a.name.compareTo(b.name));
    if (employees.isNotEmpty) {
      final rows = <_Row>[
        for (var i = 0; i < active.length; i++) _teamRow(k, active[i], i + 1),
        for (final e in idle) _teamRow(k, e, 0, muted: true),
        _Row([
          '',
          'Total',
          k.rupees(s.revenue.current.toInt()),
          s.revenue.current > 0 ? '100%' : '',
          '${s.deals.current}',
          '${s.clients.current}',
          '${s.interactions.current}',
          '${s.newClients.current}',
          '${s.followUpsOverdue}',
        ], total: true),
      ];
      if (active.length >= 2) {
        out.addAll([pw.SizedBox(height: 15), _employeeBars(k, active)]);
      }
      out.addAll([
        pw.SizedBox(height: 15),
        _sectionTitle(k, 'Team performance'),
        _table(
          k,
          headers: const [
            '#',
            'Employee',
            'Revenue',
            'Share',
            'Deals',
            'Clients',
            'Follow-ups',
            'New clients',
            'Overdue',
          ],
          aligns: const [
            _Al.left,
            _Al.left,
            _Al.right,
            _Al.right,
            _Al.right,
            _Al.right,
            _Al.right,
            _Al.right,
            _Al.right,
          ],
          widths: const {
            0: pw.FixedColumnWidth(20),
            1: pw.FlexColumnWidth(2.4),
            2: pw.FlexColumnWidth(1.7),
            3: pw.FixedColumnWidth(42),
            4: pw.FixedColumnWidth(38),
            5: pw.FixedColumnWidth(50),
            6: pw.FixedColumnWidth(62),
            7: pw.FixedColumnWidth(50),
            8: pw.FixedColumnWidth(50),
          },
          rows: rows,
        ),
      ]);
    }

    // Products + payment frequency side by side.
    if (s.revenueByProduct.isNotEmpty || s.revenueByFrequency.isNotEmpty) {
      out.addAll([
        pw.SizedBox(height: 15),
        _unit(
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _breakdown(
                  k,
                  'Products',
                  s.revenueByProduct,
                  donut: true,
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: _breakdown(
                  k,
                  'Payment frequency',
                  s.revenueByFrequency,
                  donut: true,
                ),
              ),
            ],
          ),
        ),
      ]);
    }

    // Follow-ups mini table.
    out.addAll([
      pw.SizedBox(height: 15),
      _unit(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [_sectionTitle(k, 'Follow-ups'), _followUps(k, s)],
        ),
      ),
    ]);

    // Largest deals.
    if (s.topDeals.isNotEmpty) {
      out.addAll([
        pw.SizedBox(height: 15),
        _sectionTitle(k, 'Largest deals'),
        _table(
          k,
          headers: const ['Date', 'Client', 'Product', 'Employee', 'Amount'],
          aligns: const [_Al.left, _Al.left, _Al.left, _Al.left, _Al.right],
          widths: const {
            0: pw.FixedColumnWidth(62),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FixedColumnWidth(74),
          },
          rows: [
            for (final d in s.topDeals)
              _Row([
                _fmtDay(d.date),
                d.clientName,
                _productOf(d),
                d.salesRepName?.isNotEmpty == true
                    ? d.salesRepName!
                    : d.salesRep,
                k.rupees(salePaise(d)),
              ]),
          ],
        ),
      ]);
    }

    // Employee sections.
    for (final e in active) {
      out.add(pw.NewPage());
      out.addAll(_employeeSection(k, e, period, standalone: false));
    }

    if (idle.isNotEmpty) {
      if (active.isNotEmpty) out.add(pw.SizedBox(height: 24));
      out.addAll([
        _sectionTitle(k, 'No activity'),
        k.text(idle.map((e) => e.name).join(', '), 9, color: _C.label),
      ]);
    }
    return out;
  }

  static _Row _teamRow(
    _Kit k,
    EmployeeReport e,
    int index, {
    bool muted = false,
  }) {
    final share = e.share;
    final shareText = share <= 0
        ? '–'
        : share < 0.01
        ? '<1%'
        : '${(share * 100).round()}%';
    return _Row([
      muted ? '–' : '${e.rank > 0 ? e.rank : index}',
      e.name,
      k.rupees(e.revenue.current.toInt()),
      shareText,
      '${e.deals.current}',
      '${e.clients.current}',
      '${e.interactions.current}',
      '${e.newClients.current}',
      '${e.followUpsOverdue}',
    ], muted: muted);
  }

  // ── Employee section ──────────────────────────────────────────────────

  static List<pw.Widget> _employeeSection(
    _Kit k,
    EmployeeReport e,
    String period, {
    required bool standalone,
  }) {
    final rankLine = e.teamSize >= 2 && e.rank > 0
        ? 'Rank ${e.rank} of ${e.teamSize} · '
              '${e.share <= 0 ? '0' : (e.share < 0.01 ? '<1' : (e.share * 100).round().toString())}% of team'
        : null;

    final out = <pw.Widget>[
      _titleBlock(
        k,
        e.name,
        standalone ? period : null,
        eyebrow: standalone ? 'Employee report' : null,
        sub: rankLine,
      ),
      pw.SizedBox(height: 14),
      _kpiStrip(k, [
        _Kpi(
          'Revenue',
          k.rupees(e.revenue.current.toInt()),
          e.revenue,
          percent: true,
        ),
        _Kpi('Deals', '${e.deals.current}', e.deals),
        _Kpi('Clients', '${e.clients.current}', e.clients),
        _Kpi('Follow-ups', '${e.interactions.current}', e.interactions),
        _Kpi(
          'Overdue',
          '${e.followUpsOverdue}',
          null,
          alert: e.followUpsOverdue > 0,
        ),
      ]),
    ];

    if (_idle(e)) {
      out.addAll([
        pw.SizedBox(height: 18),
        k.text('No activity in this period', 10, color: _C.muted),
      ]);
      return out;
    }

    final daily = _dailyChart(k, e.dailyRevenue);
    if (daily != null) out.addAll([pw.SizedBox(height: 15), daily]);

    if (e.teamAvgRevenuePaise != null) {
      out.addAll([pw.SizedBox(height: 15), _vsTeam(k, e)]);
    }

    if (e.revenueByProduct.isNotEmpty) {
      out.addAll([
        pw.SizedBox(height: 15),
        _breakdown(k, 'Products', e.revenueByProduct),
      ]);
    }

    if (e.activity.isNotEmpty) {
      out.addAll([
        pw.SizedBox(height: 15),
        _sectionTitle(k, 'Activity'),
        _table(
          k,
          headers: const ['Date', 'Type', 'Client', 'Detail', 'Amount'],
          aligns: const [_Al.left, _Al.left, _Al.left, _Al.left, _Al.right],
          widths: const {
            0: pw.FixedColumnWidth(58),
            1: pw.FixedColumnWidth(54),
            2: pw.FlexColumnWidth(1.5),
            3: pw.FlexColumnWidth(2.4),
            4: pw.FixedColumnWidth(72),
          },
          rows: [
            for (final a in e.activity)
              _Row([
                DateFormat('d MMM yyyy').format(a.at),
                switch (a.kind) {
                  ActivityKind.sale => 'Sale',
                  ActivityKind.followUp => 'Follow-up',
                  ActivityKind.newClient => 'New client',
                },
                a.clientName,
                _activityDetail(a),
                a.amountPaise != null ? k.rupees(a.amountPaise!) : '',
              ]),
          ],
        ),
      ]);
    }

    if (e.upcomingFollowUps.isNotEmpty) {
      out.addAll([
        pw.SizedBox(height: 15),
        _sectionTitle(k, 'Upcoming follow-ups'),
        _table(
          k,
          headers: const ['Date', 'Client', 'Priority'],
          aligns: const [_Al.left, _Al.left, _Al.left],
          widths: const {
            0: pw.FixedColumnWidth(80),
            1: pw.FlexColumnWidth(2.5),
            2: pw.FlexColumnWidth(1),
          },
          rows: [
            for (final Interaction i in e.upcomingFollowUps)
              _Row([
                _fmtDay(i.followUpDate),
                i.clientName,
                i.priorityDisplay?.isNotEmpty == true
                    ? i.priorityDisplay!
                    : i.priority,
              ]),
          ],
        ),
      ]);
    }
    return out;
  }

  static String _activityDetail(ActivityEntry a) {
    final detail = a.detail ?? '';
    final pr = a.priority ?? '';
    if (a.kind == ActivityKind.followUp && pr.isNotEmpty) {
      return detail.isEmpty ? pr : '$pr · $detail';
    }
    return detail;
  }

  static String _avg(double? v) {
    if (v == null) return '–';
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
  }

  static String _fmtDay(String raw) {
    final d = parseEventDate(raw);
    return d == null
        ? (raw.isEmpty ? '–' : raw)
        : DateFormat('d MMM yyyy').format(d);
  }

  static String _productOf(Sale s) => s.productDisplay?.isNotEmpty == true
      ? s.productDisplay!
      : MonthlyReportBuilder.labelFor(productCategories, s.product);

  // ── Blocks ────────────────────────────────────────────────────────────

  static pw.Widget _titleBlock(
    _Kit k,
    String title,
    String? period, {
    String? eyebrow,
    String? sub,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          k.text(eyebrow.toUpperCase(), 7.5, color: _C.green, spacing: 1.2),
          pw.SizedBox(height: 3),
        ],
        k.head(title, 20, color: _C.navy),
        pw.SizedBox(height: 4),
        pw.Container(width: 28, height: 2.5, color: _C.green),
        if (period != null) ...[
          pw.SizedBox(height: 6),
          k.text(period, 10, color: _C.label),
        ],
        if (sub != null) ...[
          pw.SizedBox(height: 3),
          k.text(sub, 9.5, color: _C.label),
        ],
      ],
    );
  }

  static pw.Widget _sectionTitle(_Kit k, String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: k.head(title, 11, color: _C.navy),
    );
  }

  static pw.Widget _kpiStrip(_Kit k, List<_Kpi> items) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) pw.SizedBox(width: 6),
          pw.Expanded(flex: i == 0 ? 15 : 10, child: _kpiBox(k, items[i])),
        ],
      ],
    );
  }

  static pw.Widget _kpiBox(_Kit k, _Kpi kpi) {
    final size = kpi.value.length > 10
        ? 10.0
        : (kpi.value.length > 8 ? 12.0 : 14.0);
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 8, 6, 8),
      decoration: pw.BoxDecoration(
        color: _C.zebra,
        border: pw.Border.all(color: _C.rule, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          k.text(kpi.label.toUpperCase(), 6.5, color: _C.label, spacing: 0.6),
          pw.SizedBox(height: 5),
          k.figure(kpi.value, size, color: kpi.alert ? _C.danger : _C.navy),
          pw.SizedBox(height: 4),
          _delta(k, kpi),
        ],
      ),
    );
  }

  static pw.Widget _delta(_Kit k, _Kpi kpi) {
    final d = kpi.delta;
    if (d == null || d.previous == 0) return pw.SizedBox(height: 8);
    final change = d.change;
    if (change == 0) {
      return k.text('No change', 7, color: _C.muted);
    }
    final up = change > 0;
    final color = up ? _C.greenDark : _C.danger;
    final pct = kpi.percent ? d.percentChange!.abs() : 0.0;
    final label = kpi.percent
        ? (pct > 999 ? '999%+' : '${pct.toStringAsFixed(pct < 10 ? 1 : 0)}%')
        : '${up ? '+' : '-'}${change.abs().toInt()}';
    return pw.Row(
      children: [
        _triangle(up, color),
        pw.SizedBox(width: 3),
        k.text(label, 7.5, color: color, bold: true),
      ],
    );
  }

  static pw.Widget _triangle(bool up, PdfColor color) {
    return pw.SizedBox(
      width: 6,
      height: 6,
      child: pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.CustomPaint(
              size: const PdfPoint(6, 6),
              painter: (canvas, size) {
                canvas
                  ..setFillColor(color)
                  ..moveTo(0, up ? 0 : size.y)
                  ..lineTo(size.x, up ? 0 : size.y)
                  ..lineTo(size.x / 2, up ? size.y : 0)
                  ..closePath()
                  ..fillPath();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Breakdown + follow-up tables ──────────────────────────────────────

  static pw.Widget _breakdown(
    _Kit k,
    String title,
    List<CategoryTotal> items, {
    bool donut = false,
  }) {
    final total = items.fold<int>(0, (t, c) => t + c.paise);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(k, title),
        if (items.isEmpty)
          k.text('–', 9, color: _C.muted)
        else ...[
          if (donut && total > 0) ...[
            _donutWithLegend(k, items, total),
            pw.SizedBox(height: 10),
          ],
          _table(
            k,
            headers: const ['', 'Revenue', '%', 'Deals'],
            aligns: const [_Al.left, _Al.right, _Al.right, _Al.right],
            widths: const {
              0: pw.FlexColumnWidth(1.6),
              1: pw.FlexColumnWidth(1.5),
              2: pw.FixedColumnWidth(34),
              3: pw.FixedColumnWidth(40),
            },
            rows: [
              for (final c in items)
                _Row([
                  c.label,
                  k.rupees(c.paise),
                  total > 0 ? '${(c.paise * 100 / total).round()}%' : '–',
                  '${c.count}',
                ]),
            ],
          ),
        ],
      ],
    );
  }

  static pw.Widget _followUps(_Kit k, PeriodSummary s) {
    final pri = s.interactionsByPriority;
    final headers = [
      'Logged',
      'Overdue',
      'Upcoming',
      for (final p in pri) p.label,
    ];
    final cells = [
      '${s.interactions.current}',
      '${s.followUpsOverdue}',
      '${s.followUpsUpcoming}',
      for (final p in pri) '${p.count}',
    ];
    final table = _table(
      k,
      headers: headers,
      aligns: [for (final _ in headers) _Al.right],
      widths: {
        for (var i = 0; i < headers.length; i++) i: const pw.FlexColumnWidth(1),
      },
      rows: [_Row(cells)],
    );
    final bar = _priorityBar(k, pri);
    if (bar == null) return table;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [table, pw.SizedBox(height: 10), bar],
    );
  }

  static PdfColor _priorityColor(String label) {
    final u = label.toUpperCase();
    if (u.contains('HIGH')) return _C.danger;
    if (u.contains('MED')) return _C.amber;
    if (u.contains('LOW')) return _C.muted;
    return _C.rule;
  }

  /// One stacked horizontal bar: High red / Medium amber / Low slate.
  static pw.Widget? _priorityBar(_Kit k, List<CategoryTotal> pri) {
    final items = [
      for (final p in pri)
        if (p.count > 0) p,
    ];
    if (items.isEmpty) return null;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          height: 9,
          child: pw.Row(
            children: [
              for (final p in items)
                pw.Expanded(
                  flex: p.count,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      color: _priorityColor(p.label),
                      border: const pw.Border(
                        right: pw.BorderSide(color: _C.white, width: 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            for (final p in items) ...[
              _dot(_priorityColor(p.label)),
              pw.SizedBox(width: 4),
              k.text('${p.label}  ${p.count}', 7.5, color: _C.label),
              pw.SizedBox(width: 14),
            ],
          ],
        ),
      ],
    );
  }

  static pw.Widget _dot(PdfColor color) => pw.Container(
    width: 6,
    height: 6,
    decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
  );

  // ── Horizontal bars, donut, vs-team ───────────────────────────────────

  /// Revenue by employee: rank order, at most 12 bars, the rest "Others".
  static pw.Widget _employeeBars(_Kit k, List<EmployeeReport> active) {
    const maxBars = 12;
    final shown = active.take(maxBars).toList();
    final rest = active.skip(maxBars).toList();
    final bars = <(String, int, bool)>[
      for (final e in shown) (e.name, e.revenue.current.toInt(), false),
      if (rest.isNotEmpty)
        (
          'Others (${rest.length})',
          rest.fold<int>(0, (t, e) => t + e.revenue.current.toInt()),
          true,
        ),
    ];
    final maxPaise = bars.fold<int>(0, (m, b) => math.max(m, b.$2));
    if (maxPaise <= 0) return pw.SizedBox();
    const nameW = 112.0;
    const valueW = 54.0;
    const barMax = _kContentWidth - nameW - valueW - 6;
    return _unit(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle(k, 'Revenue by employee'),
          for (final b in bars)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(
                    width: nameW,
                    child: pw.Text(
                      k.safe(b.$1),
                      maxLines: 1,
                      style: k.styleFor(8.5, color: b.$3 ? _C.label : _C.text),
                    ),
                  ),
                  pw.SizedBox(
                    width: barMax + 6,
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Container(
                        width: math.max(1.0, barMax * b.$2 / maxPaise),
                        height: 9,
                        decoration: pw.BoxDecoration(
                          color: b.$3 ? _C.muted : _C.navy,
                          borderRadius: const pw.BorderRadius.horizontal(
                            right: pw.Radius.circular(1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: valueW,
                    child: pw.Text(
                      k.safe(_compact(b.$2 / 100, k)),
                      textAlign: pw.TextAlign.right,
                      style: k.styleFor(8, color: _C.label, bold: true),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const _slicePalette = [
    PdfColor.fromInt(0xFF00337C),
    PdfColor.fromInt(0xFF2D8A4E),
    PdfColor.fromInt(0xFF4F7CC4),
    PdfColor.fromInt(0xFF86C79D),
    PdfColor.fromInt(0xFF64748B),
    PdfColor.fromInt(0xFFB7C6E0),
    PdfColor.fromInt(0xFF94A3B8),
    PdfColor.fromInt(0xFFCBD5E1),
  ];

  static pw.Widget _donutWithLegend(
    _Kit k,
    List<CategoryTotal> items,
    int total,
  ) {
    // At most 8 slices; the tail is merged into "Others".
    final shown = items.length > 8 ? items.take(7).toList() : items;
    final rest = items.length > 8 ? items.skip(7).toList() : <CategoryTotal>[];
    final slices = <(String, int, PdfColor)>[
      for (var i = 0; i < shown.length; i++)
        (shown[i].label, shown[i].paise, _slicePalette[i]),
      if (rest.isNotEmpty)
        ('Others', rest.fold<int>(0, (t, c) => t + c.paise), _slicePalette[7]),
    ];
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        _donut([for (final s in slices) (s.$2.toDouble(), s.$3)], 76),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            children: [
              for (final s in slices)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
                  child: pw.Row(
                    children: [
                      _dot(s.$3),
                      pw.SizedBox(width: 5),
                      pw.Expanded(
                        child: pw.Text(
                          k.safe(s.$1),
                          maxLines: 1,
                          style: k.styleFor(7.5),
                        ),
                      ),
                      pw.SizedBox(
                        width: 26,
                        child: pw.Text(
                          '${(s.$2 * 100 / total).round()}%',
                          textAlign: pw.TextAlign.right,
                          style: k.styleFor(7.5, color: _C.label),
                        ),
                      ),
                      pw.SizedBox(
                        width: 48,
                        child: pw.Text(
                          k.safe(k.rupees(s.$2)),
                          textAlign: pw.TextAlign.right,
                          style: k.styleFor(7.5, color: _C.label),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// A ring chart drawn as filled polygon sectors, clockwise from 12 o'clock.
  static pw.Widget _donut(List<(double, PdfColor)> slices, double size) {
    final total = slices.fold<double>(0, (t, s) => t + s.$1);
    return pw.SizedBox(
      width: size,
      height: size,
      child: pw.CustomPaint(
        size: PdfPoint(size, size),
        painter: (canvas, sz) {
          if (total <= 0) return;
          final cx = sz.x / 2, cy = sz.y / 2;
          final ro = sz.x / 2, ri = ro * 0.58;
          var a0 = math.pi / 2;
          for (final s in slices) {
            if (s.$1 <= 0) continue;
            final sweep = s.$1 / total * 2 * math.pi;
            final n = math.max(2, (sweep / (2 * math.pi) * 90).ceil());
            canvas
              ..setFillColor(s.$2)
              ..setStrokeColor(_C.white)
              ..setLineWidth(0.8);
            for (var i = 0; i <= n; i++) {
              final a = a0 - sweep * i / n;
              final x = cx + ro * math.cos(a), y = cy + ro * math.sin(a);
              if (i == 0) {
                canvas.moveTo(x, y);
              } else {
                canvas.lineTo(x, y);
              }
            }
            for (var i = n; i >= 0; i--) {
              final a = a0 - sweep * i / n;
              canvas.lineTo(cx + ri * math.cos(a), cy + ri * math.sin(a));
            }
            canvas
              ..closePath()
              ..fillAndStrokePath();
            a0 -= sweep;
          }
        },
      ),
    );
  }

  /// Employee vs team average: a pair of bars per metric, numbers beside.
  static pw.Widget _vsTeam(_Kit k, EmployeeReport e) {
    final metrics = <(String, double, double, String, String)>[
      (
        'Revenue',
        e.revenue.current.toDouble(),
        (e.teamAvgRevenuePaise ?? 0).toDouble(),
        k.rupees(e.revenue.current.toInt()),
        k.rupees(e.teamAvgRevenuePaise ?? 0),
      ),
      (
        'Deals',
        e.deals.current.toDouble(),
        e.teamAvgDeals ?? 0,
        '${e.deals.current}',
        _avg(e.teamAvgDeals),
      ),
      (
        'Follow-ups',
        e.interactions.current.toDouble(),
        e.teamAvgInteractions ?? 0,
        '${e.interactions.current}',
        _avg(e.teamAvgInteractions),
      ),
    ];
    const labelW = 62.0;
    const valueW = 74.0;
    const barMax = _kContentWidth - labelW - valueW - 6;

    pw.Widget barRow(
      double v,
      double max,
      PdfColor color,
      String text, {
      bool strong = true,
    }) {
      final w = max <= 0 ? 0.0 : math.max(v > 0 ? 1.0 : 0.0, barMax * v / max);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          children: [
            pw.SizedBox(
              width: barMax + 6,
              child: pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Container(
                  width: w,
                  height: 7,
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: const pw.BorderRadius.horizontal(
                      right: pw.Radius.circular(1.5),
                    ),
                  ),
                ),
              ),
            ),
            pw.SizedBox(
              width: valueW,
              child: pw.Text(
                k.safe(text),
                textAlign: pw.TextAlign.right,
                style: k.styleFor(
                  8,
                  color: strong ? _C.text : _C.label,
                  bold: strong,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _unit(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              _sectionTitle(k, 'Vs team average'),
              pw.Spacer(),
              _dot(_C.navy),
              pw.SizedBox(width: 4),
              k.text('Employee', 7.5, color: _C.label),
              pw.SizedBox(width: 12),
              _dot(_C.muted),
              pw.SizedBox(width: 4),
              k.text('Team average', 7.5, color: _C.label),
            ],
          ),
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0)
              pw.Container(
                height: 0.4,
                color: _C.rule,
                margin: const pw.EdgeInsets.symmetric(vertical: 4),
              ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(width: labelW, child: k.text(metrics[i].$1, 8.5)),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      barRow(
                        metrics[i].$2,
                        math.max(metrics[i].$2, metrics[i].$3),
                        _C.navy,
                        metrics[i].$4,
                      ),
                      barRow(
                        metrics[i].$3,
                        math.max(metrics[i].$2, metrics[i].$3),
                        _C.muted,
                        metrics[i].$5,
                        strong: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Generic table ─────────────────────────────────────────────────────

  static pw.Widget _table(
    _Kit k, {
    required List<String> headers,
    required List<_Al> aligns,
    required Map<int, pw.TableColumnWidth> widths,
    required List<_Row> rows,
  }) {
    pw.Widget cell(String text, int col, _Row? row) {
      final header = row == null;
      final color = header
          ? _C.label
          : row.muted
          ? _C.muted
          : _C.text;
      final style = header
          ? k.styleFor(6.8, color: color, bold: true, spacing: 0.2)
          : k.styleFor(8.5, color: color, bold: row.total);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
        child: pw.Align(
          alignment: aligns[col] == _Al.right
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
          child: pw.Text(
            header ? k.safe(text).toUpperCase() : k.safe(text),
            style: style,
            textAlign: aligns[col] == _Al.right
                ? pw.TextAlign.right
                : pw.TextAlign.left,
          ),
        ),
      );
    }

    final children = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _C.navy, width: 0.8)),
        ),
        children: [
          for (var c = 0; c < headers.length; c++) cell(headers[c], c, null),
        ],
      ),
      for (var r = 0; r < rows.length; r++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: rows[r].total ? null : (r.isOdd ? _C.zebra : null),
            border: rows[r].total
                ? const pw.Border(
                    top: pw.BorderSide(color: _C.navy, width: 0.8),
                  )
                : const pw.Border(
                    bottom: pw.BorderSide(color: _C.rule, width: 0.4),
                  ),
          ),
          children: [
            for (var c = 0; c < headers.length; c++)
              cell(
                c < rows[r].cells.length ? rows[r].cells[c] : '',
                c,
                rows[r],
              ),
          ],
        ),
    ];

    return pw.Table(
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: children,
    );
  }

  // ── Revenue chart ─────────────────────────────────────────────────────

  /// Keeps a block (title + chart) together: a Container is not a spanning
  /// widget, so MultiPage moves it to the next page whole instead of
  /// splitting it.
  static pw.Widget _unit(pw.Widget child) => pw.Container(child: child);

  static pw.Widget? _dailyChart(_Kit k, List<DayTotal> daily) {
    if (daily.isEmpty || daily.every((d) => d.paise == 0)) return null;

    final n = daily.length;
    final buckets = _bucket(daily, n);
    final unit = n <= 62 ? 'Daily' : (n <= 366 ? 'Weekly' : 'Monthly');
    final labelFmt = n > 366 ? DateFormat('MMM yy') : DateFormat('d MMM');

    final maxPaise = buckets.fold<int>(0, (m, b) => math.max(m, b.paise));
    final step = _niceStep(maxPaise / 100 / 4);
    final top = step * 4;

    const axisW = 44.0;
    const chartH = 100.0;
    const plotW = _kContentWidth - axisW;
    final slot = plotW / buckets.length;
    final barW = math.max(1.0, slot * 0.68);
    final labelEvery = math.max(1, (buckets.length / 8).ceil());

    final grid = <pw.Widget>[
      for (var g = 0; g <= 4; g++)
        pw.Positioned(
          left: 0,
          right: 0,
          bottom: chartH * g / 4,
          child: pw.Container(
            height: g == 0 ? 0.8 : 0.4,
            color: g == 0 ? _C.muted : _C.rule,
          ),
        ),
    ];

    final bars = <pw.Widget>[
      for (var i = 0; i < buckets.length; i++)
        if (buckets[i].paise > 0)
          pw.Positioned(
            left: slot * i + (slot - barW) / 2,
            bottom: 0.8,
            child: pw.Container(
              width: barW,
              height: math.max(1.0, chartH * (buckets[i].paise / 100) / top),
              decoration: const pw.BoxDecoration(
                color: _C.navy,
                borderRadius: pw.BorderRadius.vertical(
                  top: pw.Radius.circular(1.5),
                ),
              ),
            ),
          ),
    ];

    final xLabels = <pw.Widget>[
      for (var i = 0; i < buckets.length; i += labelEvery)
        pw.Positioned(
          left: slot * i + slot / 2 - 24,
          top: 4,
          child: pw.SizedBox(
            width: 48,
            child: pw.Text(
              labelFmt.format(buckets[i].start),
              textAlign: pw.TextAlign.center,
              style: k.styleFor(7, color: _C.label),
            ),
          ),
        ),
    ];

    return _unit(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle(k, '$unit revenue'),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: axisW,
                height: chartH + 16,
                child: pw.Stack(
                  children: [
                    for (var g = 0; g <= 4; g++)
                      pw.Positioned(
                        right: 6,
                        bottom: chartH * g / 4 + 4,
                        child: k.text(
                          _compact(step * g, k),
                          7,
                          color: _C.label,
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(
                width: plotW,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Column(
                    children: [
                      pw.SizedBox(
                        height: chartH,
                        child: pw.Stack(
                          overflow: pw.Overflow.visible,
                          children: [...grid, ...bars],
                        ),
                      ),
                      pw.SizedBox(
                        height: 16,
                        child: pw.Stack(
                          overflow: pw.Overflow.visible,
                          children: xLabels,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Daily up to 62 days, weekly (7-day chunks from the range start) up to
  /// 366, calendar months beyond.
  static List<_Bucket> _bucket(List<DayTotal> daily, int n) {
    if (n <= 62) {
      return [for (final d in daily) _Bucket(d.day, d.paise)];
    }
    final out = <_Bucket>[];
    if (n <= 366) {
      for (var i = 0; i < n; i += 7) {
        var sum = 0;
        for (var j = i; j < math.min(i + 7, n); j++) {
          sum += daily[j].paise;
        }
        out.add(_Bucket(daily[i].day, sum));
      }
      return out;
    }
    int? key;
    for (final d in daily) {
      final k = d.day.year * 12 + d.day.month;
      if (k != key) {
        out.add(_Bucket(DateTime(d.day.year, d.day.month), 0));
        key = k;
      }
      final last = out.removeLast();
      out.add(_Bucket(last.start, last.paise + d.paise));
    }
    return out;
  }

  /// 1, 2, 2.5, 5 x 10^k at or above [raw] rupees.
  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (m * mag >= raw) return m * mag;
    }
    return 10 * mag;
  }

  static String _compact(double rupees, _Kit k) {
    final p = k.unicodeSafe ? '₹' : 'Rs.';
    String t(double v) {
      final s = v.toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    if (rupees >= 10000000) return '$p${t(rupees / 10000000)}Cr';
    if (rupees >= 100000) return '$p${t(rupees / 100000)}L';
    if (rupees >= 1000) return '$p${t(rupees / 1000)}K';
    return '$p${rupees.toStringAsFixed(0)}';
  }
}

class _Bucket {
  const _Bucket(this.start, this.paise);
  final DateTime start;
  final int paise;
}

class _Kpi {
  const _Kpi(
    this.label,
    this.value,
    this.delta, {
    this.percent = false,
    this.alert = false,
  });
  final String label;
  final String value;
  final MetricDelta? delta;
  final bool percent;
  final bool alert;
}

class _Jakarta {
  const _Jakarta({required this.semi, required this.bold});
  final pw.Font semi;
  final pw.Font bold;
}

/// Text helpers bound to the loaded fonts.
class _Kit {
  _Kit(this.inter, this.jakarta);
  final ReportPdfFonts inter;
  final _Jakarta jakarta;

  bool get unicodeSafe => inter.unicodeSafe;

  /// With a core-font fallback, replace glyphs Helvetica cannot draw.
  String safe(String s) {
    if (unicodeSafe) return s;
    return s
        .replaceAll('₹', 'Rs. ')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('·', '|');
  }

  pw.TextStyle styleFor(
    double size, {
    PdfColor color = _C.text,
    bool bold = false,
    double spacing = 0,
  }) => pw.TextStyle(
    font: bold ? inter.medium : inter.regular,
    fontBold: inter.bold,
    fontSize: size,
    color: color,
    letterSpacing: spacing,
  );

  pw.Widget text(
    String s,
    double size, {
    PdfColor color = _C.text,
    bool bold = false,
    double spacing = 0,
  }) => pw.Text(
    safe(s),
    style: styleFor(size, color: color, bold: bold, spacing: spacing),
  );

  /// Headings.
  pw.Widget head(String s, double size, {PdfColor color = _C.navy}) => pw.Text(
    safe(s),
    style: pw.TextStyle(font: jakarta.bold, fontSize: size, color: color),
  );

  /// Figures.
  pw.Widget figure(String s, double size, {PdfColor color = _C.navy}) =>
      pw.Text(
        safe(s),
        style: pw.TextStyle(font: jakarta.bold, fontSize: size, color: color),
      );

  /// Whole rupees from paise with Indian grouping: "₹6,04,349".
  String rupees(int paise) {
    final negative = paise < 0;
    // Round to the nearest rupee, half away from zero.
    final whole = (paise.abs() + 50) ~/ 100;
    final digits = whole.toString();
    String grouped;
    if (digits.length <= 3) {
      grouped = digits;
    } else {
      final head = digits.substring(0, digits.length - 3);
      final tail = digits.substring(digits.length - 3);
      final parts = <String>[];
      var i = head.length;
      while (i > 0) {
        parts.insert(0, head.substring(math.max(0, i - 2), i));
        i -= 2;
      }
      grouped = '${parts.join(',')},$tail';
    }
    return '${negative ? '-' : ''}${unicodeSafe ? '₹' : 'Rs. '}$grouped';
  }
}
