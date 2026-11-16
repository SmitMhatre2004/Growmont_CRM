// test/monthly_report_test.dart
//
// Unit tests for the Monthly Report aggregation. Every figure the screen
// and the Excel export show comes out of MonthlyReportBuilder.build, so
// these tests are what stands between a reporting bug and a business
// decision made on a wrong number.
//
// `now` is injected everywhere so nothing here depends on the day the
// suite happens to run.

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/reports/monthly_report_builder.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';

// ── Fixtures ────────────────────────────────────────────────────────────

Sale sale({
  String id = 's1',
  required String date,
  int paise = 100000,
  String clientName = 'Acme',
  String? clientId,
  String rep = 'emp1',
  String? repName,
  String product = 'MF',
  String company = 'HDFC',
  String frequency = 'M',
}) {
  return Sale(
    id: id,
    date: date,
    clientName: clientName,
    clientId: clientId,
    salesRep: rep,
    salesRepId: rep,
    salesRepName: repName,
    product: product,
    company: company,
    scheme: 'Scheme',
    amount: (paise / 100).toStringAsFixed(2),
    amountPaise: paise,
    frequency: frequency,
  );
}

Interaction interaction({
  String id = 'i1',
  required String date,
  String followUpDate = '',
  String priority = 'MEDIUM',
  String employee = 'emp1',
  String? employeeName,
}) {
  return Interaction(
    id: id,
    date: date,
    clientName: 'Acme',
    clientContact: '9999999999',
    employee: employee,
    employeeId: employee,
    employeeName: employeeName,
    followUpDate: followUpDate,
    followUpTime: '10:00:00',
    priority: priority,
  );
}

Client client({String id = 'c1', String? createdAt}) =>
    Client(id: id, name: 'Acme', contactNumber: '9999999999', createdAt: createdAt);

MonthlyReport buildReport({
  ReportMonth period = const ReportMonth(2025, 6),
  List<Sale> sales = const [],
  List<Interaction> interactions = const [],
  List<Client> clients = const [],
  Map<String, String> employeeNames = const {},
  ReportScope scope = ReportScope.company,
  DateTime? now,
}) {
  return MonthlyReportBuilder.build(
    period: period,
    scope: scope,
    scopeLabel: 'Growmont',
    sales: sales,
    interactions: interactions,
    clients: clients,
    employeeNames: employeeNames,
    now: now ?? DateTime(2025, 6, 15, 12),
  );
}

void main() {
  // ── Period arithmetic ────────────────────────────────────────────────
  group('ReportMonth', () {
    test('start and endExclusive form a half-open month', () {
      const june = ReportMonth(2025, 6);
      expect(june.start, DateTime(2025, 6, 1));
      expect(june.endExclusive, DateTime(2025, 7, 1));
      expect(june.lastDay, DateTime(2025, 6, 30));
    });

    test('rolls over December to January and back', () {
      expect(const ReportMonth(2025, 12).next, const ReportMonth(2026, 1));
      expect(const ReportMonth(2025, 1).previous, const ReportMonth(2024, 12));
      expect(const ReportMonth(2025, 12).endExclusive, DateTime(2026, 1, 1));
    });

    test('February has 29 days in a leap year and 28 otherwise', () {
      expect(const ReportMonth(2024, 2).dayCount, 29);
      expect(const ReportMonth(2025, 2).dayCount, 28);
      expect(const ReportMonth(2024, 2).lastDay, DateTime(2024, 2, 29));
      expect(const ReportMonth(2100, 2).dayCount, 28); // not a leap year
    });

    test('contains includes both boundary days and excludes neighbours', () {
      const june = ReportMonth(2025, 6);
      expect(june.contains(DateTime(2025, 6, 1)), isTrue);
      expect(june.contains(DateTime(2025, 6, 30)), isTrue);
      expect(june.contains(DateTime(2025, 5, 31)), isFalse);
      expect(june.contains(DateTime(2025, 7, 1)), isFalse);
      expect(june.contains(null), isFalse);
    });

    test('equality and ordering work across years', () {
      expect(const ReportMonth(2025, 6), const ReportMonth(2025, 6));
      expect(
        const ReportMonth(2024, 12).compareTo(const ReportMonth(2025, 1)),
        isNegative,
      );
    });
  });

  // ── Date parsing ─────────────────────────────────────────────────────
  group('date parsing', () {
    test('parseEventDate accepts both stored shapes', () {
      // Date-only, as written by the direct-Firestore read path.
      expect(parseEventDate('2025-06-10'), DateTime(2025, 6, 10));
      // Full ISO without a zone, as written into the SQLite payload.
      expect(
        parseEventDate('2025-06-10T00:00:00.000'),
        DateTime(2025, 6, 10),
      );
    });

    test('parseEventDate keeps the displayed calendar day, not the instant', () {
      // A Z-suffixed value must NOT shift month even when the local zone
      // would move it, because the list screens render its own fields.
      expect(parseEventDate('2025-06-01T00:00:00.000Z'), DateTime(2025, 6, 1));
      expect(parseEventDate('2025-07-01T00:00:00.000Z'), DateTime(2025, 7, 1));
    });

    test('parseEventDate returns null for junk and blanks', () {
      expect(parseEventDate(null), isNull);
      expect(parseEventDate(''), isNull);
      expect(parseEventDate('not a date'), isNull);
      expect(parseEventDate('31/06/2025'), isNull);
    });

    test('parseInstantDay converts UTC to the local calendar day', () {
      final utc = DateTime.utc(2025, 6, 10, 18, 30);
      final expected = utc.toLocal();
      expect(
        parseInstantDay(utc.toIso8601String()),
        DateTime(expected.year, expected.month, expected.day),
      );
    });

    test('parseInstantDay returns null for junk and blanks', () {
      expect(parseInstantDay(null), isNull);
      expect(parseInstantDay(''), isNull);
      expect(parseInstantDay('whenever'), isNull);
    });
  });

  // ── Money and counts ─────────────────────────────────────────────────
  group('revenue and deals', () {
    test('sums only sales dated inside the month', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-01', paise: 150000),
          sale(id: 'b', date: '2025-06-30', paise: 250000),
          sale(id: 'c', date: '2025-05-31', paise: 999900), // previous month
          sale(id: 'd', date: '2025-07-01', paise: 888800), // next month
        ],
      );

      expect(report.revenue.current, 400000);
      expect(report.deals.current, 2);
      expect(report.revenue.previous, 999900);
      expect(report.deals.previous, 1);
    });

    test('sums in paise so repeated addition cannot drift', () {
      // 0.01 rupee x 3 is the classic float-drift case.
      final report = buildReport(
        sales: [
          for (var i = 0; i < 3; i++)
            sale(id: 's$i', date: '2025-06-0${i + 1}', paise: 1),
        ],
      );
      expect(report.revenue.current, 3);
      expect(report.revenueRupees, closeTo(0.03, 1e-12));
    });

    test('average deal value is zero when there are no deals', () {
      final report = buildReport();
      expect(report.avgDealPaise, 0);
      expect(report.deals.current, 0);
    });

    test('average deal value divides revenue by deal count', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-02', paise: 100000),
          sale(id: 'b', date: '2025-06-03', paise: 200000),
        ],
      );
      expect(report.avgDealPaise, 150000);
    });

    test('falls back to the rupee string when amount_paise is absent', () {
      const legacy = Sale(
        id: 'legacy',
        date: '2025-06-05',
        clientName: 'Acme',
        salesRep: 'emp1',
        product: 'MF',
        company: 'HDFC',
        scheme: '',
        amount: '1250.50',
        frequency: 'M',
      );
      final report = buildReport(sales: [legacy]);
      expect(report.revenue.current, 125050);
    });
  });

  group('month-over-month deltas', () {
    test('percentChange is null when the previous month is empty', () {
      final report = buildReport(
        sales: [sale(date: '2025-06-10', paise: 500000)],
      );
      expect(report.revenue.previous, 0);
      expect(report.revenue.percentChange, isNull);
      expect(report.revenue.isUp, isTrue);
    });

    test('percentChange computes a rise and a fall', () {
      final up = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-10', paise: 150000),
          sale(id: 'b', date: '2025-05-10', paise: 100000),
        ],
      );
      expect(up.revenue.percentChange, closeTo(50, 1e-9));

      final down = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-10', paise: 50000),
          sale(id: 'b', date: '2025-05-10', paise: 100000),
        ],
      );
      expect(down.revenue.percentChange, closeTo(-50, 1e-9));
      expect(down.revenue.isDown, isTrue);
    });

    test('a month equal to the previous one is flat, not up or down', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-10', paise: 100000),
          sale(id: 'b', date: '2025-05-10', paise: 100000),
        ],
      );
      expect(report.revenue.isFlat, isTrue);
      expect(report.revenue.percentChange, 0);
    });
  });

  // ── Clients ──────────────────────────────────────────────────────────
  group('active and new clients', () {
    test('active clients counts distinct ids, not sales', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-01', clientId: 'c1'),
          sale(id: 'b', date: '2025-06-02', clientId: 'c1'),
          sale(id: 'c', date: '2025-06-03', clientId: 'c2'),
        ],
      );
      expect(report.deals.current, 3);
      expect(report.activeClients.current, 2);
    });

    test('active clients falls back to the name when no id is stored', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-01', clientName: 'Acme Corp'),
          sale(id: 'b', date: '2025-06-02', clientName: '  acme corp '),
          sale(id: 'c', date: '2025-06-03', clientName: 'Other Ltd'),
        ],
      );
      expect(report.activeClients.current, 2);
    });

    test('new clients are bucketed by created_at, and missing ones counted', () {
      final report = buildReport(
        clients: [
          client(id: 'c1', createdAt: DateTime.utc(2025, 6, 10, 6).toIso8601String()),
          client(id: 'c2', createdAt: DateTime.utc(2025, 5, 10, 6).toIso8601String()),
          client(id: 'c3'), // no created_at at all
          client(id: 'c4', createdAt: 'garbage'),
        ],
      );

      expect(report.newClients.current, 1);
      expect(report.newClients.previous, 1);
      expect(report.quality.clientsWithoutCreatedAt, 2);
      expect(report.quality.hasIssues, isTrue);
    });
  });

  // ── Interactions and follow-ups ──────────────────────────────────────
  group('interactions and follow-ups', () {
    test('counts interactions by their own date', () {
      final report = buildReport(
        interactions: [
          interaction(id: 'a', date: '2025-06-05'),
          interaction(id: 'b', date: '2025-06-06'),
          interaction(id: 'c', date: '2025-05-06'),
        ],
      );
      expect(report.interactions.current, 2);
      expect(report.interactions.previous, 1);
    });

    test('priority rows keep a fixed order and include zero rows', () {
      final report = buildReport(
        interactions: [
          interaction(id: 'a', date: '2025-06-05', priority: 'HIGH'),
          interaction(id: 'b', date: '2025-06-06', priority: 'HIGH'),
          interaction(id: 'c', date: '2025-06-07', priority: 'LOW'),
        ],
      );

      expect(
        report.interactionsByPriority.map((r) => r.label),
        ['High', 'Medium', 'Low'],
      );
      expect(report.interactionsByPriority[0].count, 2);
      expect(report.interactionsByPriority[1].count, 0);
      expect(report.interactionsByPriority[2].count, 1);
    });

    test('an unknown priority still gets a row rather than vanishing', () {
      final report = buildReport(
        interactions: [
          interaction(id: 'a', date: '2025-06-05', priority: 'URGENT'),
        ],
      );
      final total = report.interactionsByPriority.fold<int>(
        0,
        (sum, row) => sum + row.count,
      );
      expect(total, 1);
      expect(
        report.interactionsByPriority.any((r) => r.label == 'URGENT'),
        isTrue,
      );
    });

    test('follow-ups are counted on the follow-up date, not the log date', () {
      // Logged in May, due in June: belongs to June's follow-up load.
      final report = buildReport(
        interactions: [
          interaction(id: 'a', date: '2025-05-20', followUpDate: '2025-06-10'),
        ],
      );
      expect(report.interactions.current, 0);
      expect(report.followUpsScheduled, 1);
    });

    test('past-due counts only follow-ups on or before today', () {
      final report = buildReport(
        now: DateTime(2025, 6, 15, 9),
        interactions: [
          interaction(id: 'a', date: '2025-06-01', followUpDate: '2025-06-10'),
          interaction(id: 'b', date: '2025-06-02', followUpDate: '2025-06-15'),
          interaction(id: 'c', date: '2025-06-03', followUpDate: '2025-06-20'),
        ],
      );
      expect(report.followUpsScheduled, 3);
      expect(report.followUpsPastDue, 2); // the 10th and today, not the 20th
    });

    test('a blank follow-up date is not counted', () {
      final report = buildReport(
        interactions: [interaction(id: 'a', date: '2025-06-05')],
      );
      expect(report.followUpsScheduled, 0);
      expect(report.followUpsPastDue, 0);
    });
  });

  // ── Breakdowns ───────────────────────────────────────────────────────
  group('breakdowns', () {
    test('product revenue uses display labels and sorts by value', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-01', product: 'MF', paise: 100000),
          sale(id: 'b', date: '2025-06-02', product: 'HI', paise: 300000),
          sale(id: 'c', date: '2025-06-03', product: 'MF', paise: 100000),
        ],
      );

      expect(report.revenueByProduct.first.label, 'Health Insurance');
      expect(report.revenueByProduct.first.paise, 300000);
      expect(report.revenueByProduct[1].label, 'Mutual Funds');
      expect(report.revenueByProduct[1].paise, 200000);
      expect(report.revenueByProduct[1].count, 2);
    });

    test('a blank grouping field becomes Unspecified, never dropped', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-01', company: '', paise: 100000),
          sale(id: 'b', date: '2025-06-02', product: '', paise: 200000),
        ],
      );

      expect(
        report.revenueByCompany.any((r) => r.label == kUnspecifiedLabel),
        isTrue,
      );
      expect(
        report.revenueByProduct.any((r) => r.label == kUnspecifiedLabel),
        isTrue,
      );
      // Every rupee still shows up in the breakdown total.
      final byCompany = report.revenueByCompany.fold<int>(
        0,
        (sum, r) => sum + r.paise,
      );
      expect(byCompany, report.revenue.current);
    });

    test('frequency comes back in scale order, not largest first', () {
      // Payment frequency is an ordered scale, so it keeps the order
      // frequencyChoices declares and holds a zero row for every step
      // that saw no business. The segmented bar that draws it reads left
      // to right along that scale; re-sorting by size would turn an
      // ordered split into a ranked list wearing an ordinal ramp.
      final report = buildReport(
        sales: [
          // Deliberately largest last: Yearly out-sells Quarterly.
          sale(id: 'q', date: '2025-06-01', frequency: 'Q', paise: 100000),
          sale(id: 'y', date: '2025-06-02', frequency: 'Y', paise: 900000),
        ],
      );

      expect(
        report.revenueByFrequency.map((r) => r.label),
        ['Monthly', 'Quarterly', 'Half Yearly', 'Yearly', 'One Time'],
      );

      final quarterly = report.revenueByFrequency
          .firstWhere((r) => r.label == 'Quarterly');
      expect(quarterly.paise, 100000);
      expect(quarterly.count, 1);

      // Steps with no sales are present at zero, so the order never
      // shifts between months.
      expect(
        report.revenueByFrequency.firstWhere((r) => r.label == 'Monthly').paise,
        0,
      );
    });

    test('a frequency outside the scale is still counted, after it', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-01', frequency: 'M', paise: 100000),
          sale(id: 'b', date: '2025-06-02', frequency: 'WEIRD', paise: 50000),
        ],
      );

      final labels = report.revenueByFrequency.map((r) => r.label).toList();
      expect(labels.take(5), [
        'Monthly',
        'Quarterly',
        'Half Yearly',
        'Yearly',
        'One Time',
      ]);
      expect(labels.last, 'WEIRD');
      // Nothing is dropped: the breakdown still reconciles to revenue.
      expect(
        report.revenueByFrequency.fold<int>(0, (s, r) => s + r.paise),
        report.revenue.current,
      );
    });

    test('top deals are the largest, biggest first, capped', () {
      final report = buildReport(
        sales: [
          for (var i = 1; i <= 8; i++)
            sale(id: 's$i', date: '2025-06-0${i % 9}', paise: i * 10000),
        ],
      );
      expect(report.topDeals.length, kTopDealCount);
      expect(report.topDeals.first.amountPaise, 80000);
      expect(report.topDeals.last.amountPaise, 40000);
    });
  });

  group('daily revenue series', () {
    test('runs one entry per day, oldest first, ending on the last day', () {
      final report = buildReport();
      expect(report.dailyRevenue.length, kTrendDays);
      expect(report.dailyRevenue.last.day, DateTime(2025, 6, 30));
      expect(
        report.dailyRevenue.first.day,
        DateTime(2025, 6, 30 - (kTrendDays - 1)),
      );
    });

    test('days are consecutive with no gaps or repeats', () {
      final days = buildReport().dailyRevenue.map((d) => d.day).toList();
      expect(days.toSet().length, days.length, reason: 'no repeated dates');
      for (var i = 1; i < days.length; i++) {
        expect(
          days[i].difference(days[i - 1]).inDays,
          1,
          reason: 'gap before ${days[i]}',
        );
      }
    });

    test('a sale lands on its own day', () {
      final report = buildReport(
        sales: [sale(date: '2025-06-10', paise: 450000)],
      );
      final tenth = report.dailyRevenue
          .firstWhere((d) => d.day == DateTime(2025, 6, 10));
      expect(tenth.paise, 450000);
      expect(tenth.count, 1);
    });

    test('several sales on one day are summed', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-10', paise: 100000),
          sale(id: 'b', date: '2025-06-10', paise: 250000),
        ],
      );
      final tenth = report.dailyRevenue
          .firstWhere((d) => d.day == DateTime(2025, 6, 10));
      expect(tenth.paise, 350000);
      expect(tenth.count, 2);
    });

    test('a quiet day is a zero, not a missing entry', () {
      final report = buildReport(
        sales: [sale(date: '2025-06-10', paise: 450000)],
      );
      final eleventh = report.dailyRevenue
          .firstWhere((d) => d.day == DateTime(2025, 6, 11));
      expect(eleventh.paise, 0);
      expect(eleventh.count, 0);
    });

    test('sales after the reported month are not included', () {
      final report = buildReport(
        sales: [sale(date: '2025-07-05', paise: 900000)],
      );
      expect(report.dailyRevenue.every((d) => d.paise == 0), isTrue);
    });

    test('sales older than the window are not included', () {
      final report = buildReport(
        sales: [sale(date: '2020-01-10', paise: 900000)],
      );
      expect(report.dailyRevenue.every((d) => d.paise == 0), isTrue);
    });

    test('the window spans a year boundary correctly', () {
      final report = buildReport(
        period: const ReportMonth(2025, 1),
        now: DateTime(2025, 1, 20),
        sales: [sale(date: '2024-12-15', paise: 700000)],
      );
      final december = report.dailyRevenue
          .firstWhere((d) => d.day == DateTime(2024, 12, 15));
      expect(december.paise, 700000);
    });
  });

  group('trailing revenue trend', () {
    test('returns one bucket per month, oldest first, ending on the period', () {
      final report = buildReport();
      expect(report.trailingRevenue.length, kTrendMonths);
      expect(report.trailingRevenue.last.month, const ReportMonth(2025, 6));
      expect(report.trailingRevenue.first.month, const ReportMonth(2024, 7));
    });

    test('empty months are present as zero rows', () {
      final report = buildReport(
        sales: [sale(date: '2025-06-10', paise: 500000)],
      );
      expect(report.trailingRevenue.last.paise, 500000);
      expect(
        report.trailingRevenue.take(kTrendMonths - 1).every((m) => m.paise == 0),
        isTrue,
      );
    });

    test('the window crosses a year boundary correctly', () {
      final report = buildReport(
        period: const ReportMonth(2025, 1),
        now: DateTime(2025, 1, 20),
        sales: [sale(date: '2024-12-15', paise: 700000)],
      );
      final december = report.trailingRevenue.firstWhere(
        (m) => m.month == const ReportMonth(2024, 12),
      );
      expect(december.paise, 700000);
      expect(report.trailingRevenue.first.month, const ReportMonth(2024, 2));
    });

    test('sales outside the window do not leak into any bucket', () {
      final report = buildReport(
        sales: [sale(date: '2020-01-10', paise: 999900)],
      );
      expect(
        report.trailingRevenue.every((m) => m.paise == 0),
        isTrue,
      );
    });
  });

  // ── Team ─────────────────────────────────────────────────────────────
  group('team performance', () {
    test('groups by the sale own rep id and sorts by revenue', () {
      final report = buildReport(
        employeeNames: const {'emp1': 'Asha', 'emp2': 'Bilal'},
        sales: [
          sale(id: 'a', date: '2025-06-01', rep: 'emp1', paise: 100000),
          sale(id: 'b', date: '2025-06-02', rep: 'emp2', paise: 400000),
          sale(id: 'c', date: '2025-05-02', rep: 'emp2', paise: 200000),
        ],
        interactions: [
          interaction(id: 'i1', date: '2025-06-03', employee: 'emp1'),
        ],
      );

      expect(report.team.length, 2);
      expect(report.team.first.name, 'Bilal');
      expect(report.team.first.revenuePaise, 400000);
      expect(report.team.first.previousRevenuePaise, 200000);
      expect(report.team.first.revenueDelta.percentChange, closeTo(100, 1e-9));

      final asha = report.team[1];
      expect(asha.name, 'Asha');
      expect(asha.dealCount, 1);
      expect(asha.interactionCount, 1);
    });

    test('per-employee revenue sums to the company total', () {
      final report = buildReport(
        employeeNames: const {'emp1': 'Asha', 'emp2': 'Bilal'},
        sales: [
          sale(id: 'a', date: '2025-06-01', rep: 'emp1', paise: 123400),
          sale(id: 'b', date: '2025-06-02', rep: 'emp2', paise: 567800),
        ],
      );
      final teamTotal = report.team.fold<int>(
        0,
        (sum, row) => sum + row.revenuePaise,
      );
      expect(teamTotal, report.revenue.current);
    });

    test('falls back to the name stored on the record for a missing employee', () {
      final report = buildReport(
        employeeNames: const {},
        sales: [
          sale(id: 'a', date: '2025-06-01', rep: 'ghost', repName: 'Ex Employee'),
        ],
      );
      expect(report.team.single.name, 'Ex Employee');
    });

    test('an individual report computes no team rows at all', () {
      final report = buildReport(
        scope: ReportScope.individual,
        employeeNames: const {'emp1': 'Asha'},
        sales: [sale(date: '2025-06-01', rep: 'emp1', paise: 100000)],
      );
      expect(report.team, isEmpty);
      // The person's own totals are still there.
      expect(report.revenue.current, 100000);
    });
  });

  // ── Edge cases ───────────────────────────────────────────────────────
  group('edge cases', () {
    test('an empty dataset yields an empty report, not a crash', () {
      final report = buildReport();
      expect(report.isEmpty, isTrue);
      expect(report.revenue.current, 0);
      expect(report.topDeals, isEmpty);
      expect(report.team, isEmpty);
      expect(report.revenueByProduct, isEmpty);
      expect(report.trailingRevenue.length, kTrendMonths);
      expect(report.quality.hasIssues, isFalse);
    });

    test('undated records are counted as a data-quality issue, not dropped', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: ''),
          sale(id: 'b', date: 'not-a-date'),
          sale(id: 'c', date: '2025-06-01', paise: 100000),
        ],
        interactions: [
          interaction(id: 'i1', date: ''),
          interaction(id: 'i2', date: '2025-06-01'),
        ],
      );

      expect(report.quality.salesWithoutDate, 2);
      expect(report.quality.interactionsWithoutDate, 1);
      expect(report.revenue.current, 100000);
      expect(report.interactions.current, 1);
    });

    test('a report with activity is not reported as empty', () {
      final report = buildReport(
        interactions: [interaction(date: '2025-06-05')],
      );
      expect(report.revenue.current, 0);
      expect(report.isEmpty, isFalse);
    });

    test('February boundaries hold in a leap year', () {
      final report = buildReport(
        period: const ReportMonth(2024, 2),
        now: DateTime(2024, 3, 1),
        sales: [
          sale(id: 'a', date: '2024-02-29', paise: 100000),
          sale(id: 'b', date: '2024-03-01', paise: 900000),
          sale(id: 'c', date: '2024-01-31', paise: 500000),
        ],
      );
      expect(report.revenue.current, 100000);
      expect(report.revenue.previous, 500000);
    });

    test('duplicate records are both counted — the books are not deduped', () {
      final report = buildReport(
        sales: [
          sale(id: 'a', date: '2025-06-01', paise: 100000, clientId: 'c1'),
          sale(id: 'b', date: '2025-06-01', paise: 100000, clientId: 'c1'),
        ],
      );
      expect(report.deals.current, 2);
      expect(report.revenue.current, 200000);
      expect(report.activeClients.current, 1);
    });

    test('scales to a large dataset without changing the arithmetic', () {
      final many = [
        for (var i = 0; i < 20000; i++)
          sale(
            id: 's$i',
            date: '2025-06-${(i % 30) + 1}'.replaceAllMapped(
              RegExp(r'-(\d)$'),
              (m) => '-0${m[1]}',
            ),
            paise: 100,
          ),
      ];
      final report = buildReport(sales: many);

      expect(report.deals.current, 20000);
      expect(report.revenue.current, 2000000);
      expect(report.activeClients.current, 1);
      expect(report.trailingRevenue.last.count, 20000);
      // Deliberately no wall-clock assertion. An earlier version of this
      // test bounded the elapsed time, which passed in isolation and
      // failed under the parallel load of the full suite — a flake, not a
      // finding. Completing at all is the real guard: the aggregation is
      // one pass per collection, so an accidental O(n^2) here would run
      // for minutes and trip the harness timeout instead.
    });
  });
}
