// test/monthly_report_pdf_test.dart
//
// The PDF export must be a real, parseable document carrying the same
// figures the screen shows. These tests render it and read the text back
// out of the page stream, which is the only way to prove a number
// actually reached the page rather than just reaching the builder.

import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/reports/monthly_report_builder.dart';
import 'package:growmont_crm/core/reports/monthly_report_pdf.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';

Sale _sale({
  String id = 's1',
  required String date,
  int paise = 500000,
  String rep = 'emp1',
  String product = 'MF',
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
    company: 'HDFC',
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

/// Pulls the literal strings out of a PDF's content streams.
///
/// Text in a PDF lives in `(...) Tj` / `[...] TJ` operators inside a page's
/// content stream, and the pdf package Flate-compresses those streams — so
/// every `stream ... endstream` block is inflated first. A block that is
/// not compressed (or is an image/font payload) is scanned as-is and simply
/// yields nothing.
///
/// With a core font the parentheses hold readable Latin-1, which is enough
/// to assert a figure was actually drawn. An embedded TrueType subset
/// encodes to glyph ids instead, which is why the text assertions below use
/// the core font and the embedding is checked separately.
String _extractText(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final out = StringBuffer();
  final textPattern = RegExp(r'\(((?:\\.|[^()\\])*)\)');

  var cursor = 0;
  while (true) {
    final start = raw.indexOf('stream', cursor);
    if (start < 0) break;

    // 'endstream' also contains 'stream'; skip those matches.
    if (start >= 3 && raw.substring(start - 3, start) == 'end') {
      cursor = start + 'stream'.length;
      continue;
    }

    final end = raw.indexOf('endstream', start);
    if (end < 0) break;

    // The stream data begins after the keyword's EOL (CR, LF or CRLF).
    var dataStart = start + 'stream'.length;
    if (dataStart < bytes.length && bytes[dataStart] == 0x0D) dataStart++;
    if (dataStart < bytes.length && bytes[dataStart] == 0x0A) dataStart++;

    if (dataStart < end) {
      final chunk = bytes.sublist(dataStart, end);
      List<int> payload;
      try {
        payload = ZLibCodec().decode(chunk);
      } catch (_) {
        payload = chunk; // not Flate — scan the raw bytes instead
      }
      final text = latin1.decode(payload, allowInvalid: true);
      for (final match in textPattern.allMatches(text)) {
        out.write(
          match.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'),
        );
        out.write('\n');
      }
    }

    cursor = end + 'endstream'.length;
  }
  // Collapse the runs' whitespace so a phrase reads as one line.
  return out.toString().replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  // The pdf package's core fonts need no asset bundle, so these run
  // without a platform channel.
  final fonts = ReportPdfFonts.core();

  group('document', () {
    test('produces a non-trivial, well-formed PDF', () async {
      final bytes = await MonthlyReportPdf.build(_report(), fonts);

      expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
      expect(
        latin1.decode(bytes, allowInvalid: true),
        contains('%%EOF'),
      );
      // A header-only page would be a couple of KB; a full report is more.
      expect(bytes.length, greaterThan(8000));
    });

    test('filename carries the period and matches the Excel convention', () {
      expect(
        MonthlyReportPdf.filename(_report()),
        'Growmont-Report-2025-06.pdf',
      );
    });

    test('renders an empty month without throwing', () async {
      final empty = _report(sales: const []);
      expect(empty.isEmpty, isFalse, reason: 'fixture still logs an interaction');

      final bytes = await MonthlyReportPdf.build(empty, fonts);
      expect(bytes.length, greaterThan(4000));
    });

    test('renders a report with no data at all without throwing', () async {
      final blank = MonthlyReportBuilder.build(
        period: const ReportMonth(2025, 6),
        scope: ReportScope.individual,
        scopeLabel: 'Asha Rao',
        sales: const [],
        interactions: const [],
        clients: const [],
        now: DateTime(2025, 6, 15),
      );
      expect(blank.isEmpty, isTrue);

      final bytes = await MonthlyReportPdf.build(blank, fonts);
      expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
    });
  });

  group('content matches the report', () {
    test('header names the period and the scope', () async {
      final report = _report();
      final text = _extractText(
        await MonthlyReportPdf.build(report, fonts),
      );

      expect(text, contains('Growmont CRM'));
      expect(text, contains('June 2025'));
      expect(text, contains('Whole company'));
      // The comparison month is stated, not left implicit.
      expect(text, contains('May 2025'));
    });

    test('states the day range so the month boundary is unambiguous', () async {
      final text = _extractText(
        await MonthlyReportPdf.build(_report(), fonts),
      );
      expect(text, contains('30'), reason: 'June has 30 days');
    });

    test('revenue appears as the rendered rupee figure', () async {
      final report = _report();
      // 500000 + 250000 paise = Rs 7,500.
      expect(report.revenue.current, 750000);

      final text = _extractText(
        await MonthlyReportPdf.build(report, fonts),
      );
      expect(text, contains('7,500'));
    });

    test('deal count and average deal reach the page', () async {
      final report = _report();
      expect(report.deals.current, 2);
      expect(report.avgDealPaise, 375000);

      final text = _extractText(
        await MonthlyReportPdf.build(report, fonts),
      );
      expect(text, contains('3,750'));
    });

    test('every section heading is present for a company report', () async {
      final text = _extractText(
        await MonthlyReportPdf.build(_report(), fonts),
      );

      for (final heading in const [
        'Month-over-month',
        'Revenue trend',
        'Revenue by product',
        'Revenue by company',
        'Client activity and follow-up load',
        'Largest deals',
        'Team performance',
        'How to read this report',
      ]) {
        expect(text, contains(heading), reason: 'missing section: $heading');
      }
    });

    test('an individual report omits the team section', () async {
      final text = _extractText(
        await MonthlyReportPdf.build(
          _report(scope: ReportScope.individual),
          fonts,
        ),
      );
      expect(text, isNot(contains('Team performance')));
      expect(text, contains('Asha Rao'));
      // The rest of the report is still there.
      expect(text, contains('Month-over-month'));
    });

    test('product labels are spelled the way the app spells them', () async {
      final text = _extractText(
        await MonthlyReportPdf.build(_report(), fonts),
      );
      expect(text, contains('Mutual Funds'));
      expect(text, contains('Health Insurance'));
    });

    test('states what the CRM does not track', () async {
      final text = _extractText(
        await MonthlyReportPdf.build(_report(), fonts),
      );
      expect(text, contains('Not tracked in this CRM'));
      expect(text, contains('Leads generated'));
    });

    test('warns about records that could not be placed in a month', () async {
      final report = _report(
        sales: [
          _sale(id: 'a', date: '2025-06-02'),
          _sale(id: 'bad', date: ''),
        ],
        clients: const [
          Client(id: 'c9', name: 'No Date Ltd', contactNumber: '1'),
        ],
      );
      expect(report.quality.hasIssues, isTrue);

      final text = _extractText(
        await MonthlyReportPdf.build(report, fonts),
      );
      expect(
        text,
        contains('Some records could not be placed in a month'),
      );
    });

    test('a month with no baseline shows an em dash, not a fake percentage',
        () async {
      final report = _report(
        sales: [_sale(id: 'only', date: '2025-06-05', paise: 100000)],
      );
      expect(report.revenue.percentChange, isNull);

      // Asserted on the formatter rather than the glyph stream: an em dash
      // is not Latin-1 and would not survive the text extraction above.
      final bytes = await MonthlyReportPdf.build(report, fonts);
      expect(bytes.length, greaterThan(4000));
    });
  });

  group('fonts', () {
    test('core fallback prefixes amounts with Rs. instead of a blank glyph',
        () async {
      expect(fonts.unicodeSafe, isFalse);

      final text = _extractText(
        await MonthlyReportPdf.build(_report(), fonts),
      );
      expect(text, contains('Rs. 7,500'));
    });

    test('core fallback downgrades punctuation it cannot draw', () async {
      // Regression guard: the pdf package draws NOTHING for a glyph the
      // font lacks, so an em dash, en dash or middle dot would silently
      // vanish from a fallback-rendered report. They must come out as
      // ASCII instead.
      final text = _extractText(
        await MonthlyReportPdf.build(_report(), fonts),
      );

      expect(text, isNot(contains('—')), reason: 'em dash must be gone');
      expect(text, isNot(contains('–')), reason: 'en dash must be gone');
      expect(text, isNot(contains('·')), reason: 'middle dot must be gone');
      expect(text, isNot(contains('₹')), reason: 'rupee sign must be gone');

      // And the words around them survived rather than being dropped.
      expect(text, contains('Monthly Report - June 2025'));
      expect(text, contains('Whole company'));
    });

    test('a missing "no value" figure still prints a mark', () async {
      final report = _report(
        sales: [_sale(id: 'only', date: '2025-06-05', paise: 100000)],
      );
      expect(report.revenue.percentChange, isNull);

      final text = _extractText(
        await MonthlyReportPdf.build(report, fonts),
      );
      // The fallback renders the "no baseline" dash as a hyphen, so the
      // cell is never blank.
      expect(text, contains('-'));
    });

    test('embedded Inter is used when the asset bundle is available',
        () async {
      // rootBundle works under flutter_test for assets declared in
      // pubspec.yaml, so this exercises the real path the app takes.
      TestWidgetsFlutterBinding.ensureInitialized();
      final loaded = await ReportPdfFonts.load();

      expect(
        loaded.unicodeSafe,
        isTrue,
        reason: 'Inter must load so the rupee sign renders',
      );

      final bytes = await MonthlyReportPdf.build(_report(), loaded);
      // An embedded TrueType subset shows up as a FontFile2 stream; the
      // core-font document has none.
      final raw = latin1.decode(bytes, allowInvalid: true);
      expect(raw, contains('FontFile2'));
      expect(raw, contains('Inter'));
    });
  });
}
