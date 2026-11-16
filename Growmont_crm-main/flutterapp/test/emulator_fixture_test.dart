// test/emulator_fixture_test.dart
//
// End-to-end cross-check of the reporting layer against REAL records.
//
// Every other test here feeds the builder hand-written objects. That
// proves the arithmetic but not the pipeline: a field named wrongly, a
// date stored in a shape the parser does not expect, or a sale attached
// to an id the report never reads would pass all of them and still put a
// wrong number on the screen.
//
// This test loads `test/fixtures/emulator_report.json`, which holds the
// Firebase emulator's actual contents together with expected figures
// recomputed in JavaScript straight from those documents
// (scripts/dump-fixture.js). Two independent implementations reading the
// same real records have to agree.
//
// Regenerate the fixture after reseeding the emulator:
//   npm --prefix scripts run dump:fixture
//
// The fixture is committed, so this test runs in CI with no emulator.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/reports/monthly_report_builder.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';

void main() {
  final file = File('test/fixtures/emulator_report.json');
  if (!file.existsSync()) {
    test('emulator fixture is present', () {
      fail(
        'test/fixtures/emulator_report.json is missing. Start the emulator, '
        'seed it, then run: npm --prefix scripts run dump:fixture',
      );
    });
    return;
  }

  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  final period = ReportMonth(
    fixture['period']['year'] as int,
    fixture['period']['month'] as int,
  );

  // The past-due follow-up count depends on what "today" was when the
  // expectations were computed, so the builder is given the same day.
  final today = fixture['today'] as Map<String, dynamic>;
  final now = DateTime(
    today['year'] as int,
    today['month'] as int,
    today['day'] as int,
    12,
  );

  List<Sale> salesFrom(Iterable<dynamic> raw) => [
    for (final row in raw)
      Sale.fromJson(Map<String, dynamic>.from(row as Map)),
  ];
  List<Interaction> interactionsFrom(Iterable<dynamic> raw) => [
    for (final row in raw)
      Interaction.fromJson(Map<String, dynamic>.from(row as Map)),
  ];
  List<Client> clientsFrom(Iterable<dynamic> raw) => [
    for (final row in raw)
      Client.fromJson(Map<String, dynamic>.from(row as Map)),
  ];

  final allSales = salesFrom(fixture['sales'] as List);
  final allInteractions = interactionsFrom(fixture['interactions'] as List);
  final allClients = clientsFrom(fixture['clients'] as List);
  final employeeNames = Map<String, String>.from(
    fixture['employeeNames'] as Map,
  );

  MonthlyReport buildFor(String? employeeId) {
    return MonthlyReportBuilder.build(
      period: period,
      scope: employeeId == null
          ? ReportScope.company
          : ReportScope.individual,
      scopeLabel: employeeId == null
          ? 'Whole company'
          : (employeeNames[employeeId] ?? employeeId),
      // Filtered exactly the way the screen filters when an admin opens
      // one person's row.
      sales: employeeId == null
          ? allSales
          : allSales
                .where((s) => (s.salesRepId ?? s.salesRep) == employeeId)
                .toList(),
      interactions: employeeId == null
          ? allInteractions
          : allInteractions
                .where((i) => (i.employeeId ?? i.employee) == employeeId)
                .toList(),
      clients: employeeId == null
          ? allClients
          : allClients.where((c) => c.employeeId == employeeId).toList(),
      employeeNames: employeeNames,
      now: now,
    );
  }

  /// Asserts every headline figure against the JavaScript expectations.
  void checkAgainst(
    MonthlyReport report,
    Map<String, dynamic> want,
    String who,
  ) {
    void eq(String name, num actual, String key) {
      expect(actual, want[key], reason: '$who · $name');
    }

    eq('revenue', report.revenue.current, 'revenue');
    eq('previous revenue', report.revenue.previous, 'previousRevenue');
    eq('deals', report.deals.current, 'deals');
    eq('previous deals', report.deals.previous, 'previousDeals');
    eq('average deal', report.avgDealPaise, 'avgDeal');
    eq('active clients', report.activeClients.current, 'activeClients');
    eq(
      'previous active clients',
      report.activeClients.previous,
      'previousActiveClients',
    );
    eq('new clients', report.newClients.current, 'newClients');
    eq(
      'previous new clients',
      report.newClients.previous,
      'previousNewClients',
    );
    eq('interactions', report.interactions.current, 'interactions');
    eq(
      'previous interactions',
      report.interactions.previous,
      'previousInteractions',
    );
    eq('follow-ups scheduled', report.followUpsScheduled, 'followUpsScheduled');
    eq('follow-ups past due', report.followUpsPastDue, 'followUpsPastDue');
    eq(
      'sales with no date',
      report.quality.salesWithoutDate,
      'salesWithoutDate',
    );
    eq(
      'interactions with no date',
      report.quality.interactionsWithoutDate,
      'interactionsWithoutDate',
    );
    eq(
      'clients with no created_at',
      report.quality.clientsWithoutCreatedAt,
      'clientsWithoutCreatedAt',
    );

    int priority(String label) => report.interactionsByPriority
        .firstWhere((r) => r.label == label)
        .count;
    expect(priority('High'), want['priorityHigh'], reason: '$who · high');
    expect(priority('Medium'), want['priorityMedium'], reason: '$who · medium');
    expect(priority('Low'), want['priorityLow'], reason: '$who · low');
  }

  void checkBreakdown(
    List<CategoryTotal> actual,
    List<dynamic> want,
    String who,
  ) {
    expect(actual.length, want.length, reason: '$who · row count');
    for (var i = 0; i < want.length; i++) {
      final row = Map<String, dynamic>.from(want[i] as Map);
      expect(actual[i].label, row['label'], reason: '$who · row $i label');
      expect(actual[i].paise, row['paise'], reason: '$who · row $i amount');
    }
  }

  group('company report against real emulator records', () {
    final want = Map<String, dynamic>.from(fixture['company'] as Map);
    late MonthlyReport report;

    setUp(() => report = buildFor(null));

    test('every headline figure matches the independent calculation', () {
      checkAgainst(report, want, 'company');
    });

    test('revenue by product matches, row for row and in order', () {
      checkBreakdown(
        report.revenueByProduct,
        want['revenueByProduct'] as List,
        'company product',
      );
    });

    test('revenue by company matches, row for row and in order', () {
      checkBreakdown(
        report.revenueByCompany,
        want['revenueByCompany'] as List,
        'company company',
      );
    });

    test('the breakdowns reconcile to total revenue', () {
      final byProduct = report.revenueByProduct.fold<int>(
        0,
        (s, r) => s + r.paise,
      );
      final byCompany = report.revenueByCompany.fold<int>(
        0,
        (s, r) => s + r.paise,
      );
      final byFrequency = report.revenueByFrequency.fold<int>(
        0,
        (s, r) => s + r.paise,
      );
      expect(byProduct, report.revenue.current);
      expect(byCompany, report.revenue.current);
      expect(byFrequency, report.revenue.current);
    });

    test('team rows sum to the company total', () {
      final teamRevenue = report.team.fold<int>(0, (s, r) => s + r.revenuePaise);
      final teamDeals = report.team.fold<int>(0, (s, r) => s + r.dealCount);
      expect(teamRevenue, report.revenue.current);
      expect(teamDeals, report.deals.current);
    });

    test('every employee on the roster has a row', () {
      for (final id in employeeNames.keys) {
        expect(
          report.team.any((r) => r.employeeId == id),
          isTrue,
          reason: 'missing team row for $id',
        );
      }
    });
  });

  group('per-employee reports against real emulator records', () {
    final perEmployee = Map<String, dynamic>.from(
      fixture['perEmployee'] as Map,
    );

    for (final entry in perEmployee.entries) {
      final id = entry.key;
      final want = Map<String, dynamic>.from(entry.value as Map);
      final name = employeeNames[id] ?? id;

      test('$name — every headline figure matches', () {
        checkAgainst(buildFor(id), want, name);
      });

      test('$name — sees only their own records', () {
        final report = buildFor(id);
        // An individual report computes no team rows, and its revenue can
        // never exceed the company's.
        expect(report.team, isEmpty);
        expect(
          report.revenue.current,
          lessThanOrEqualTo(fixture['company']['revenue'] as int),
        );
      });
    }

    test('the employees\' revenue adds up to the company total', () {
      final sum = perEmployee.values.fold<int>(
        0,
        (total, want) => total + ((want as Map)['revenue'] as int),
      );
      expect(sum, fixture['company']['revenue']);
    });
  });

  group('derived series on real records', () {
    late MonthlyReport report;
    setUp(() => report = buildFor(null));

    test('the daily series covers a full year with no gaps', () {
      expect(report.dailyRevenue.length, kTrendDays);
      for (var i = 1; i < report.dailyRevenue.length; i++) {
        expect(
          report.dailyRevenue[i].day
              .difference(report.dailyRevenue[i - 1].day)
              .inDays,
          1,
        );
      }
      expect(report.dailyRevenue.last.day, period.lastDay);
    });

    test('the selected month of the daily series sums to its revenue', () {
      final thisMonth = report.dailyRevenue
          .where((d) => period.contains(d.day))
          .fold<int>(0, (s, d) => s + d.paise);
      expect(thisMonth, report.revenue.current);
    });

    test('the monthly series agrees with the daily one', () {
      final selected = report.trailingRevenue.firstWhere(
        (m) => m.month == period,
      );
      expect(selected.paise, report.revenue.current);
      expect(selected.count, report.deals.current);
    });
  });
}
