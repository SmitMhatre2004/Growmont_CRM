// test/employee_report_test.dart
//
// EmployeeReportBuilder: activity feed, rank/share/averages, follow-up split.

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/employee_report.dart';
import 'package:growmont_crm/core/reports/report_period.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';

Sale _sale(String id, String date, int paise, {String rep = 'emp1'}) => Sale(
  id: id,
  date: date,
  clientName: 'Client $id',
  clientId: id,
  salesRep: rep,
  salesRepId: rep,
  product: 'MF',
  company: 'HDFC',
  scheme: 'Growth',
  amount: (paise / 100).toStringAsFixed(2),
  amountPaise: paise,
  frequency: 'M',
);

Interaction _interaction(
  String id,
  String date, {
  String employee = 'emp1',
  String followUpDate = '',
  String notes = '',
}) => Interaction(
  id: id,
  date: date,
  clientName: 'Acme $id',
  clientContact: '1',
  employee: employee,
  employeeId: employee,
  followUpDate: followUpDate,
  followUpTime: '',
  priority: 'HIGH',
  discussionNotes: notes,
);

Client _client(String id, String createdAt, {String employeeId = 'emp1'}) =>
    Client(
      id: id,
      name: 'Client $id',
      contactNumber: '1',
      createdAt: createdAt,
      employeeId: employeeId,
    );

void main() {
  final week = ReportWeek.of(DateTime(2026, 11, 18)); // 16-22 Nov
  final now = DateTime(2026, 11, 18, 10);
  const names = {'emp1': 'Asha', 'emp2': 'Bilal', 'emp3': 'Chitra'};

  test('activity: kinds, newest first, only own records in range', () {
    final report = EmployeeReportBuilder.build(
      range: week.range,
      employeeId: 'emp1',
      employeeNames: names,
      now: now,
      sales: [
        _sale('s1', '2026-11-17', 100000),
        _sale('s2', '2026-11-20', 200000),
        _sale('x', '2026-11-20', 900000, rep: 'emp2'),
        _sale('old', '2026-11-10', 50000),
      ],
      interactions: [
        _interaction('i1', '2026-11-18', notes: '  Asked about SIP\nsecond'),
        _interaction('i2', '2026-11-19', employee: 'emp2'),
      ],
      clients: [_client('n1', '2026-11-16T09:00:00')],
    );

    expect(report.activity.map((a) => a.kind).toList(), [
      ActivityKind.sale, // 20 Nov
      ActivityKind.followUp, // 18 Nov
      ActivityKind.sale, // 17 Nov
      ActivityKind.newClient, // 16 Nov
    ]);
    expect(report.activity.first.amountPaise, 200000);
    expect(report.activity.first.detail, contains('·'));
    final followUp = report.activity[1];
    expect(followUp.detail, 'Asked about SIP');
    expect(followUp.priority, isNotEmpty);
    expect(report.activity.last.detail, isNull);
    expect(report.name, 'Asha');
    expect(report.revenue.current, 300000);
    expect(report.revenue.previous, 50000);
  });

  test('rank, share and team averages with three employees', () {
    final report = EmployeeReportBuilder.build(
      range: week.range,
      employeeId: 'emp1',
      employeeNames: names,
      now: now,
      sales: [
        _sale('a', '2026-11-17', 300000, rep: 'emp1'),
        _sale('b', '2026-11-18', 900000, rep: 'emp2'),
        _sale('c', '2026-11-19', 300000, rep: 'emp2'),
      ],
      interactions: [
        _interaction('i1', '2026-11-17'),
        _interaction('i2', '2026-11-18'),
        _interaction('i3', '2026-11-18', employee: 'emp2'),
      ],
      clients: const [],
    );

    expect(report.teamSize, 3);
    expect(report.rank, 2);
    expect(report.share, closeTo(0.2, 1e-9));
    expect(report.teamAvgRevenuePaise, 500000); // 1,500,000 / 3
    expect(report.teamAvgDeals, 1.0); // 3 / 3
    expect(report.teamAvgInteractions, 1.0); // 3 / 3
    expect(report.avgDealPaise, 300000);
  });

  test('team averages use real division, not integer division', () {
    final report = EmployeeReportBuilder.build(
      range: week.range,
      employeeId: 'emp1',
      employeeNames: names,
      now: now,
      sales: [
        _sale('a', '2026-11-17', 300000),
        _sale('b', '2026-11-18', 300000),
      ],
      interactions: [_interaction('i1', '2026-11-17')],
      clients: const [],
    );
    expect(report.teamAvgDeals, closeTo(2 / 3, 1e-9));
    expect(report.teamAvgInteractions, closeTo(1 / 3, 1e-9));
  });

  test('team averages are null for a single employee', () {
    final report = EmployeeReportBuilder.build(
      range: week.range,
      employeeId: 'emp1',
      now: now,
      sales: [_sale('a', '2026-11-17', 300000)],
      interactions: const [],
      clients: const [],
    );
    expect(report.teamSize, 1);
    expect(report.rank, 1);
    expect(report.teamAvgRevenuePaise, isNull);
    expect(report.teamAvgDeals, isNull);
    expect(report.teamAvgInteractions, isNull);
  });

  test('overdue vs upcoming follow-ups split around now', () {
    final report = EmployeeReportBuilder.build(
      range: week.range,
      employeeId: 'emp1',
      now: now, // 18 Nov
      sales: const [],
      clients: const [],
      interactions: [
        _interaction('late', '2026-11-01', followUpDate: '2026-11-17'),
        _interaction('today', '2026-11-02', followUpDate: '2026-11-18'),
        _interaction('soon', '2026-11-03', followUpDate: '2026-11-25'),
        _interaction('sooner', '2026-11-03', followUpDate: '2026-11-20'),
        _interaction('none', '2026-11-03'),
        _interaction(
          'other',
          '2026-11-03',
          employee: 'emp2',
          followUpDate: '2026-11-01',
        ),
      ],
    );
    expect(report.followUpsOverdue, 1);
    expect(report.upcomingFollowUps.map((i) => i.id).toList(), [
      'today',
      'sooner',
      'soon',
    ]);
  });

  test('daily lists cover every day of the week', () {
    final report = EmployeeReportBuilder.build(
      range: week.range,
      employeeId: 'emp1',
      now: now,
      sales: [_sale('a', '2026-11-22', 700000)],
      interactions: [_interaction('i', '2026-11-16')],
      clients: const [],
    );
    expect(report.dailyRevenue, hasLength(7));
    expect(report.dailyInteractions, hasLength(7));
    expect(report.dailyRevenue.first.day, DateTime(2026, 11, 16));
    expect(report.dailyRevenue.last.paise, 700000);
    expect(report.dailyInteractions.first.count, 1);
    expect(report.dailyInteractions.first.paise, 0);
    expect(report.dailyInteractions.last.count, 0);
  });
}
