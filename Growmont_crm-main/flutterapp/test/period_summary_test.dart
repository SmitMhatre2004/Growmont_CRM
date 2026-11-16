// test/period_summary_test.dart
//
// ReportWeek boundaries and PeriodSummaryBuilder's figures.

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/reports/period_summary_builder.dart';
import 'package:growmont_crm/core/reports/report_period.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';

Sale _sale(
  String id,
  String date,
  int paise, {
  String rep = 'emp1',
  String clientId = 'c1',
  String? repName,
}) => Sale(
  id: id,
  date: date,
  clientName: 'Client $clientId',
  clientId: clientId,
  salesRep: rep,
  salesRepId: rep,
  salesRepName: repName,
  product: 'MF',
  company: 'HDFC',
  scheme: 'Growth',
  amount: (paise / 100).toStringAsFixed(2),
  amountPaise: paise,
  frequency: 'M',
);

Interaction _interaction(String id, String date, {String employee = 'emp1'}) =>
    Interaction(
      id: id,
      date: date,
      clientName: 'Acme',
      clientContact: '1',
      employee: employee,
      employeeId: employee,
      followUpDate: '',
      followUpTime: '',
      priority: 'HIGH',
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
  group('ReportWeek', () {
    test('starts on Monday and ends on Sunday', () {
      // 16 Nov 2026 is a Monday, 22 Nov a Sunday.
      final fromMonday = ReportWeek.of(DateTime(2026, 11, 16));
      final fromSunday = ReportWeek.of(DateTime(2026, 11, 22, 23, 59));

      expect(fromMonday.start, DateTime(2026, 11, 16));
      expect(fromSunday, fromMonday);
      expect(fromMonday.lastDay, DateTime(2026, 11, 22));
      expect(fromMonday.endExclusive, DateTime(2026, 11, 23));
    });

    test('is half-open: Sunday is in, next Monday is out', () {
      final week = ReportWeek.of(DateTime(2026, 11, 18));
      expect(week.contains(DateTime(2026, 11, 15)), isFalse);
      expect(week.contains(DateTime(2026, 11, 16)), isTrue);
      expect(week.contains(DateTime(2026, 11, 22)), isTrue);
      expect(week.contains(DateTime(2026, 11, 23)), isFalse);
      expect(week.contains(null), isFalse);
    });

    test('previous and next step by seven days across months and years', () {
      final week = ReportWeek.of(DateTime(2027, 1, 1)); // Fri; Mon is 28 Dec
      expect(week.start, DateTime(2026, 12, 28));
      expect(week.previous.start, DateTime(2026, 12, 21));
      expect(week.next.start, DateTime(2027, 1, 4));
      expect(week.next.previous, week);
    });

    test('labels within a month, across months and across years', () {
      expect(ReportWeek.of(DateTime(2026, 11, 10)).label, '9–15 Nov 2026');
      expect(ReportWeek.of(DateTime(2026, 11, 16)).label, '16–22 Nov 2026');
      expect(
        ReportWeek.of(DateTime(2026, 9, 30)).label,
        '28 Sep – 4 Oct 2026',
      );
      expect(
        ReportWeek.of(DateTime(2026, 12, 30)).label,
        '28 Dec 2026 – 3 Jan 2027',
      );
    });
  });

  group('PeriodSummaryBuilder', () {
    final week = ReportWeek.of(DateTime(2026, 11, 18)); // 16-22 Nov

    test('counts Monday and Sunday in, neighbouring days out', () {
      final summary = PeriodSummaryBuilder.build(
        range: week.range,
        sales: [
          _sale('before', '2026-11-15', 100000), // previous week's Sunday
          _sale('mon', '2026-11-16', 200000),
          _sale('sun', '2026-11-22', 300000),
          _sale('after', '2026-11-23', 900000), // next week
        ],
        interactions: const [],
        clients: const [],
      );

      expect(summary.revenue.current, 500000);
      expect(summary.deals.current, 2);
      // Sunday 15 Nov falls in the previous week.
      expect(summary.revenue.previous, 100000);
      expect(summary.deals.previous, 1);
      expect(summary.daily, hasLength(7));
      expect(summary.daily.first.day, DateTime(2026, 11, 16));
      expect(summary.daily.first.paise, 200000);
      expect(summary.daily.last.paise, 300000);
    });

    test('previous-week delta reflects the equal-length week before', () {
      final summary = PeriodSummaryBuilder.build(
        range: week.range,
        sales: [
          _sale('now', '2026-11-18', 600000, clientId: 'a'),
          _sale('now2', '2026-11-19', 400000, clientId: 'a'),
          _sale('prev', '2026-11-10', 500000, clientId: 'b'),
        ],
        interactions: [
          _interaction('i1', '2026-11-17'),
          _interaction('i2', '2026-11-18'),
          _interaction('i0', '2026-11-11'),
        ],
        clients: [
          _client('n1', '2026-11-17T10:00:00'),
          _client('p1', '2026-11-12T10:00:00'),
          _client('p2', '2026-11-13T10:00:00'),
        ],
      );

      expect(summary.revenue.current, 1000000);
      expect(summary.revenue.previous, 500000);
      expect(summary.revenue.percentChange, closeTo(100, 0.001));
      expect(summary.clients.current, 1); // both sales to client "a"
      expect(summary.clients.previous, 1);
      expect(summary.interactions.current, 2);
      expect(summary.interactions.previous, 1);
      expect(summary.newClients.current, 1);
      expect(summary.newClients.previous, 2);
      expect(summary.avgDealPaise, 500000);
    });

    test('falls back to the amount string when amountPaise is zero', () {
      final legacy = Sale(
        id: 'old',
        date: '2026-11-17',
        clientName: 'Old Ltd',
        salesRep: 'emp1',
        product: 'MF',
        company: 'HDFC',
        scheme: 'Growth',
        amount: '1234.50',
        frequency: 'M',
      );
      final summary = PeriodSummaryBuilder.build(
        range: week.range,
        sales: [legacy],
        interactions: const [],
        clients: const [],
      );
      expect(summary.revenue.current, 123450);
      expect(summary.employees.single.employeeId, 'emp1');
    });

    test('per-employee rows: sorted, shares, and a zero-activity employee', () {
      final summary = PeriodSummaryBuilder.build(
        range: week.range,
        employeeNames: const {
          'emp1': 'Asha Rao',
          'emp2': 'Bilal Khan',
          'emp3': 'Quiet Person',
        },
        sales: [
          _sale('a', '2026-11-17', 300000, rep: 'emp1'),
          _sale('b', '2026-11-18', 900000, rep: 'emp2'),
          _sale('c', '2026-11-19', 300000, rep: 'emp2'),
          _sale('p', '2026-11-10', 400000, rep: 'emp1'),
        ],
        interactions: [
          _interaction('i1', '2026-11-17', employee: 'emp1'),
          _interaction('i2', '2026-11-18', employee: 'emp1'),
        ],
        clients: [_client('n1', '2026-11-18T09:00:00', employeeId: 'emp2')],
      );

      final names = summary.employees.map((e) => e.name).toList();
      expect(names, ['Bilal Khan', 'Asha Rao', 'Quiet Person']);

      final bilal = summary.employees[0];
      expect(bilal.revenuePaise, 1200000);
      expect(bilal.dealCount, 2);
      expect(bilal.avgDealPaise, 600000);
      expect(bilal.newClientCount, 1);
      expect(bilal.share, closeTo(0.8, 1e-9));

      final asha = summary.employees[1];
      expect(asha.revenuePaise, 300000);
      expect(asha.previousRevenuePaise, 400000);
      expect(asha.revenueDelta.isDown, isTrue);
      expect(asha.interactionCount, 2);
      expect(asha.share, closeTo(0.2, 1e-9));

      final quiet = summary.employees[2];
      expect(quiet.isIdle, isTrue);
      expect(quiet.avgDealPaise, 0);
      expect(quiet.share, 0);
    });

    test('a departed employee keeps the name stored on the sale', () {
      final summary = PeriodSummaryBuilder.build(
        range: week.range,
        sales: [_sale('a', '2026-11-17', 100, rep: 'gone', repName: 'Old Hand')],
        interactions: const [],
        clients: const [],
      );
      expect(summary.employees.single.name, 'Old Hand');
    });

    test('works for a month range with an explicit previous month', () {
      const month = ReportMonth(2026, 11);
      final summary = PeriodSummaryBuilder.build(
        range: month.range,
        previous: month.previous.range,
        sales: [
          _sale('nov', '2026-11-30', 700000),
          _sale('oct', '2026-10-31', 200000),
          _sale('sep', '2026-09-30', 999999),
        ],
        interactions: const [],
        clients: const [],
      );
      expect(summary.revenue.current, 700000);
      expect(summary.revenue.previous, 200000);
      expect(summary.daily, hasLength(30));
    });

    test('breakdowns, top deals and follow-up split', () {
      final now = DateTime(2026, 11, 18, 9);
      Interaction fu(String id, String followUp) => Interaction(
        id: id,
        date: '2026-11-17',
        clientName: 'Acme',
        clientContact: '1',
        employee: 'emp1',
        employeeId: 'emp1',
        followUpDate: followUp,
        followUpTime: '',
        priority: 'HIGH',
      );
      final summary = PeriodSummaryBuilder.build(
        range: week.range,
        now: now,
        sales: [
          for (var i = 0; i < 7; i++)
            _sale('s$i', '2026-11-17', (i + 1) * 100000),
          _sale('prev', '2026-11-10', 999999999),
        ],
        interactions: [
          fu('a', '2026-11-17'), // overdue
          fu('b', '2026-11-18'), // today -> upcoming
          fu('c', '2026-12-01'), // upcoming
          fu('d', ''), // none
          fu('e', '2026-10-01'), // overdue, outside the range
        ],
        clients: const [],
      );

      expect(summary.followUpsOverdue, 2);
      expect(summary.followUpsUpcoming, 2);
      expect(summary.topDeals, hasLength(5));
      expect(summary.topDeals.first.id, 's6');
      expect(summary.topDeals.last.id, 's2');
      expect(summary.revenueByProduct.single.paise, 2800000);
      expect(summary.revenueByFrequency.first.paise, 2800000);
      expect(summary.interactionsByPriority.first.count, 5);
    });

    test('an empty period reports isEmpty', () {
      final summary = PeriodSummaryBuilder.build(
        range: week.range,
        sales: const [],
        interactions: const [],
        clients: const [],
      );
      expect(summary.isEmpty, isTrue);
      expect(summary.employees, isEmpty);
    });
  });
}
