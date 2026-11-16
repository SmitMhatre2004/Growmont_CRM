// test/performance_report_pdf_test.dart
//
// The performance PDF must build for company and employee scope, across the
// daily / weekly / monthly bucketing thresholds, with real fonts and an
// injected logo.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/employee_report.dart';
import 'package:growmont_crm/core/reports/monthly_report_pdf.dart';
import 'package:growmont_crm/core/reports/performance_report_pdf.dart';
import 'package:growmont_crm/core/reports/period_summary_builder.dart';
import 'package:growmont_crm/core/reports/report_period.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';
import 'package:pdf/widgets.dart' as pw;

const _names = {'e1': 'Samir Joshi', 'e2': 'Asha Rao', 'e3': 'Idle Person'};

Sale _sale(
  String id,
  String date,
  int paise,
  String rep,
  String client, {
  String product = 'MF',
  String freq = 'M',
}) {
  return Sale(
    id: id,
    date: date,
    clientName: client,
    clientId: client,
    salesRep: rep,
    salesRepId: rep,
    salesRepName: _names[rep],
    product: product,
    company: 'HDFC',
    scheme: 'Growth',
    amount: (paise / 100).toStringAsFixed(2),
    amountPaise: paise,
    frequency: freq,
  );
}

Interaction _interaction(String id, String date, String rep, String follow) =>
    Interaction(
      id: id,
      date: date,
      clientName: 'Acme Industries',
      clientContact: '9999999999',
      employee: rep,
      employeeId: rep,
      followUpDate: follow,
      followUpTime: '10:00:00',
      priority: 'HIGH',
      discussionNotes: 'Discussed renewal and top-up\nsecond line',
    );

final _sales = [
  for (var i = 0; i < 12; i++)
    _sale(
      'a$i',
      '2026-11-${(i + 1).toString().padLeft(2, '0')}',
      60434900 ~/ 12,
      i.isEven ? 'e1' : 'e2',
      'Client $i',
      product: i % 3 == 0 ? 'HI' : 'MF',
      freq: i % 2 == 0 ? 'M' : 'Y',
    ),
  _sale('p1', '2026-10-05', 1500000, 'e1', 'Old Client'),
];

final _interactions = [
  _interaction('i1', '2026-11-03', 'e1', '2026-11-20'),
  _interaction('i2', '2026-11-04', 'e1', '2026-11-01'),
  _interaction('i3', '2026-11-05', 'e2', ''),
];

const _clients = [
  Client(
    id: 'c1',
    name: 'Client 1',
    contactNumber: '1',
    employeeId: 'e1',
    createdAt: '2026-11-02T10:00:00',
  ),
];

ReportPdfFonts _fonts() {
  pw.Font f(String n) => pw.Font.ttf(
    ByteData.sublistView(
      Uint8List.fromList(File('assets/fonts/$n').readAsBytesSync()),
    ),
  );
  return ReportPdfFonts(
    regular: f('Inter-400.ttf'),
    medium: f('Inter-600.ttf'),
    bold: f('Inter-700.ttf'),
    unicodeSafe: true,
  );
}

Uint8List _logo() => File('assets/images/growmont_logo.png').readAsBytesSync();

({PeriodSummary summary, List<EmployeeReport> employees}) _data(
  DateRange range,
) {
  final now = DateTime(2026, 11, 16);
  final summary = PeriodSummaryBuilder.build(
    range: range,
    sales: _sales,
    interactions: _interactions,
    clients: _clients,
    employeeNames: _names,
    now: now,
  );
  final employees = [
    for (final id in _names.keys)
      EmployeeReportBuilder.build(
        range: range,
        employeeId: id,
        sales: _sales,
        interactions: _interactions,
        clients: _clients,
        employeeNames: _names,
        now: now,
      ),
  ];
  return (summary: summary, employees: employees);
}

final _november = DateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1));

void _expectPdf(Uint8List bytes) {
  expect(bytes, isNotEmpty);
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
}

Future<Uint8List> _build(
  DateRange range, {
  required bool company,
  int? only,
  String label = 'November 2026',
  bool injectFonts = true,
}) {
  final d = _data(range);
  return PerformanceReportPdf.build(
    periodLabel: label,
    summary: d.summary,
    employees: only == null ? d.employees : [d.employees[only]],
    companyScope: company,
    generatedAt: DateTime(2026, 11, 16),
    generatedBy: 'Admin',
    fonts: injectFonts ? _fonts() : null,
    logoOverride: injectFonts ? _logo() : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fileName follows the export convention', () {
    expect(
      PerformanceReportPdf.fileName(periodLabel: 'November 2026'),
      'Growmont_Performance_Nov_2026.pdf',
    );
    expect(
      PerformanceReportPdf.fileName(
        periodLabel: '1 Oct – 15 Nov 2026',
        employeeName: 'Samir Joshi',
      ),
      'Growmont_Samir_Joshi_1-Oct_15-Nov_2026.pdf',
    );
    expect(
      PerformanceReportPdf.fileName(
        periodLabel: 'November 2026',
        employeeName: 'Samir Joshi',
      ),
      'Growmont_Samir_Joshi_Nov_2026.pdf',
    );
  });

  test('company scope builds (incl. an idle employee)', () async {
    _expectPdf(await _build(_november, company: true));
  });

  test('employee scope builds', () async {
    _expectPdf(await _build(_november, company: false, only: 0));
  });

  test('empty period (company) and idle employee scope build', () async {
    final range = DateRange(DateTime(2025, 1, 1), DateTime(2025, 2, 1));
    expect(_data(range).summary.isEmpty, isTrue);
    _expectPdf(await _build(range, company: true, label: 'January 2025'));
    _expectPdf(
      await _build(range, company: false, only: 2, label: 'January 2025'),
    );
  });

  test('120-day (weekly) and 400-day (monthly) ranges build', () async {
    for (final days in [120, 400]) {
      final range = DateRange(
        DateTime(2026, 11, 16 - days + 1),
        DateTime(2026, 11, 17),
      );
      _expectPdf(await _build(range, company: true, label: 'Range'));
    }
  });

  test('default asset loading (real logo, Inter, Jakarta) builds', () async {
    _expectPdf(await _build(_november, company: true, injectFonts: false));
  });

  test('14 active employees (bars grouped into Others) build', () async {
    final names = {for (var i = 0; i < 14; i++) 'x$i': 'Employee $i'};
    final sales = [
      for (var i = 0; i < 14; i++)
        for (final p in ['MF', 'HI', 'LI', 'SIP'])
          _sale(
            's$i$p',
            '2026-11-${(i + 1).toString().padLeft(2, '0')}',
            (i + 1) * 100000,
            'x$i',
            'C$i',
            product: p,
          ),
    ];
    final range = _november;
    final now = DateTime(2026, 11, 16);
    final summary = PeriodSummaryBuilder.build(
      range: range,
      sales: sales,
      interactions: _interactions,
      clients: _clients,
      employeeNames: names,
      now: now,
    );
    final employees = [
      for (final id in names.keys)
        EmployeeReportBuilder.build(
          range: range,
          employeeId: id,
          sales: sales,
          interactions: _interactions,
          clients: _clients,
          employeeNames: names,
          now: now,
        ),
    ];
    _expectPdf(
      await PerformanceReportPdf.build(
        periodLabel: 'November 2026',
        summary: summary,
        employees: employees,
        companyScope: true,
        generatedAt: now,
        fonts: _fonts(),
        logoOverride: _logo(),
      ),
    );
  });

  test('writes a sample PDF when SAMPLE_PDF_PATH is set', () async {
    final out = Platform.environment['SAMPLE_PDF_PATH'];
    if (out == null) return;
    File(out).writeAsBytesSync(await _build(_november, company: true));
  });
}
