// lib/core/reports/period_summary_builder.dart
//
// A small, pure summary for any date range (a week, a month) and the range
// before it: company totals plus one row per employee. Feeds the phone
// Reports cards. Pure Dart, no clock reads, so test/period_summary_test.dart
// can assert every figure.
//
// The attribution rules are MonthlyReportBuilder's own, not a variant:
// a sale belongs to `repIdOf(sale)`, money is `salePaise` (amountPaise with
// the amount-string fallback), distinct clients use
// `distinctClientCount`, and an interaction belongs to
// `employeeId ?? employee`.

import '../../models/client.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../shared/widgets/monthly_revenue_chart.dart' show salePaise;
import '../theme/app_theme.dart' show frequencyChoices, productCategories;
import 'monthly_report.dart';
import 'monthly_report_builder.dart';
import 'report_period.dart';

/// One employee's figures for a period.
class EmployeePeriodRow {
  const EmployeePeriodRow({
    required this.employeeId,
    required this.name,
    required this.revenuePaise,
    required this.previousRevenuePaise,
    required this.dealCount,
    required this.interactionCount,
    required this.newClientCount,
    this.clientCount = 0,
    this.overdueCount = 0,
    required this.share,
  });

  final String employeeId;
  final String name;
  final int revenuePaise;
  final int previousRevenuePaise;
  final int dealCount;
  final int interactionCount;
  final int newClientCount;

  /// Distinct clients sold to in the period.
  final int clientCount;

  /// Follow-ups owned by this person dated before today (any period).
  final int overdueCount;

  /// This employee's fraction (0..1) of the team's revenue in the period.
  final double share;

  int get avgDealPaise => dealCount > 0 ? revenuePaise ~/ dealCount : 0;

  MetricDelta get revenueDelta =>
      MetricDelta(current: revenuePaise, previous: previousRevenuePaise);

  bool get isIdle =>
      revenuePaise == 0 &&
      dealCount == 0 &&
      interactionCount == 0 &&
      newClientCount == 0;
}

/// Company totals and per-employee rows for one period.
class PeriodSummary {
  const PeriodSummary({
    required this.range,
    required this.previousRange,
    required this.revenue,
    required this.deals,
    required this.clients,
    required this.interactions,
    required this.newClients,
    required this.daily,
    required this.employees,
    this.revenueByProduct = const [],
    this.revenueByFrequency = const [],
    this.revenueByCompany = const [],
    this.interactionsByPriority = const [],
    this.followUpsOverdue = 0,
    this.followUpsUpcoming = 0,
    this.topDeals = const [],
  });

  final DateRange range;
  final DateRange previousRange;

  /// Revenue in paise.
  final MetricDelta revenue;
  final MetricDelta deals;

  /// Distinct clients sold to.
  final MetricDelta clients;

  /// Interactions (follow-ups) dated in the period.
  final MetricDelta interactions;

  /// Clients whose created_at falls in the period.
  final MetricDelta newClients;

  /// One entry per day of [range], oldest first, zeros included.
  final List<DayTotal> daily;

  /// Highest revenue first.
  final List<EmployeePeriodRow> employees;

  /// Same labelling and order rules as MonthlyReport.
  final List<CategoryTotal> revenueByProduct;
  final List<CategoryTotal> revenueByFrequency;
  final List<CategoryTotal> revenueByCompany;
  final List<CategoryTotal> interactionsByPriority;

  /// Follow-ups (over all interactions in scope) dated before today.
  final int followUpsOverdue;

  /// Follow-ups dated today or later.
  final int followUpsUpcoming;

  /// Top [kTopDealCount] sales in the range by amount, descending.
  final List<Sale> topDeals;

  int get avgDealPaise =>
      deals.current > 0 ? revenue.current ~/ deals.current : 0;

  /// No sales, interactions or new clients in the period itself.
  bool get isEmpty =>
      revenue.current == 0 &&
      deals.current == 0 &&
      interactions.current == 0 &&
      newClients.current == 0;
}

class PeriodSummaryBuilder {
  const PeriodSummaryBuilder._();

  /// Summarises [range] against [previous] (default: the range of equal
  /// length immediately before it).
  ///
  /// The lists MUST already be scoped to what the signed-in user may see,
  /// exactly as for [MonthlyReportBuilder.build]. [employeeNames] maps id to
  /// display name; when given (admin) every listed employee gets a row even
  /// with no activity.
  static PeriodSummary build({
    required DateRange range,
    DateRange? previous,
    required List<Sale> sales,
    required List<Interaction> interactions,
    required List<Client> clients,
    Map<String, String> employeeNames = const {},
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final prev = previous ?? range.previousOfEqualLength;

    // ── Sales ──────────────────────────────────────────────────────────
    final currentSales = <Sale>[];
    final previousSales = <Sale>[];
    for (final sale in sales) {
      final day = parseEventDate(sale.date);
      if (day == null) continue;
      if (range.contains(day)) {
        currentSales.add(sale);
      } else if (prev.contains(day)) {
        previousSales.add(sale);
      }
    }

    // ── Interactions ───────────────────────────────────────────────────
    final currentInteractions = <Interaction>[];
    var previousInteractionCount = 0;
    for (final interaction in interactions) {
      final day = parseEventDate(interaction.date);
      if (range.contains(day)) {
        currentInteractions.add(interaction);
      } else if (prev.contains(day)) {
        previousInteractionCount++;
      }
    }

    // ── Clients acquired ───────────────────────────────────────────────
    final currentNewClients = <Client>[];
    var previousNewClientCount = 0;
    for (final client in clients) {
      final day = parseInstantDay(client.createdAt);
      if (range.contains(day)) {
        currentNewClients.add(client);
      } else if (prev.contains(day)) {
        previousNewClientCount++;
      }
    }

    var overdue = 0;
    var upcoming = 0;
    for (final interaction in interactions) {
      final followUp = parseEventDate(interaction.followUpDate);
      if (followUp == null) continue;
      if (followUp.isBefore(today)) {
        overdue++;
      } else {
        upcoming++;
      }
    }
    final topDeals = [...currentSales]
      ..sort((a, b) => salePaise(b).compareTo(salePaise(a)));

    int sum(List<Sale> list) =>
        list.fold<int>(0, (total, s) => total + salePaise(s));

    return PeriodSummary(
      range: range,
      previousRange: prev,
      revenue: MetricDelta(
        current: sum(currentSales),
        previous: sum(previousSales),
      ),
      deals: MetricDelta(
        current: currentSales.length,
        previous: previousSales.length,
      ),
      clients: MetricDelta(
        current: MonthlyReportBuilder.distinctClientCount(currentSales),
        previous: MonthlyReportBuilder.distinctClientCount(previousSales),
      ),
      interactions: MetricDelta(
        current: currentInteractions.length,
        previous: previousInteractionCount,
      ),
      newClients: MetricDelta(
        current: currentNewClients.length,
        previous: previousNewClientCount,
      ),
      daily: _daily(currentSales, range),
      revenueByProduct: MonthlyReportBuilder.categorize(
        currentSales,
        (s) => s.productDisplay?.isNotEmpty == true
            ? s.productDisplay!
            : MonthlyReportBuilder.labelFor(productCategories, s.product),
      ),
      revenueByFrequency: MonthlyReportBuilder.categorizeInScaleOrder(
        currentSales,
        frequencyChoices,
        (s) => s.frequency,
      ),
      revenueByCompany: MonthlyReportBuilder.categorize(
        currentSales,
        (s) => s.company,
      ),
      interactionsByPriority: MonthlyReportBuilder.interactionsByPriority(
        currentInteractions,
      ),
      followUpsOverdue: overdue,
      followUpsUpcoming: upcoming,
      topDeals: topDeals.take(kTopDealCount).toList(),
      employees: _employees(
        currentSales: currentSales,
        previousSales: previousSales,
        currentInteractions: currentInteractions,
        currentNewClients: currentNewClients,
        interactions: interactions,
        today: today,
        employeeNames: employeeNames,
      ),
    );
  }

  static List<DayTotal> _daily(List<Sale> currentSales, DateRange range) {
    final paise = <DateTime, int>{};
    final counts = <DateTime, int>{};
    for (final sale in currentSales) {
      final day = parseEventDate(sale.date)!;
      paise[day] = (paise[day] ?? 0) + salePaise(sale);
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return [
      for (var i = 0; i < range.dayCount; i++)
        () {
          final day = DateTime(
            range.start.year,
            range.start.month,
            range.start.day + i,
          );
          return DayTotal(
            day: day,
            paise: paise[day] ?? 0,
            count: counts[day] ?? 0,
          );
        }(),
    ];
  }

  static List<EmployeePeriodRow> _employees({
    required List<Sale> currentSales,
    required List<Sale> previousSales,
    required List<Interaction> currentInteractions,
    required List<Client> currentNewClients,
    required List<Interaction> interactions,
    required DateTime today,
    required Map<String, String> employeeNames,
  }) {
    final revenue = <String, int>{};
    final deals = <String, int>{};
    final previousRevenue = <String, int>{};
    final interactionCounts = <String, int>{};
    final newClientCounts = <String, int>{};
    final salesByRep = <String, List<Sale>>{};
    final overdueCounts = <String, int>{};
    final fallbackNames = <String, String>{};

    for (final sale in currentSales) {
      final id = MonthlyReportBuilder.repIdOf(sale);
      if (id.isEmpty) continue;
      revenue[id] = (revenue[id] ?? 0) + salePaise(sale);
      deals[id] = (deals[id] ?? 0) + 1;
      (salesByRep[id] ??= []).add(sale);
      final name = sale.salesRepName;
      if (name != null && name.isNotEmpty) fallbackNames[id] ??= name;
    }

    for (final sale in previousSales) {
      final id = MonthlyReportBuilder.repIdOf(sale);
      if (id.isEmpty) continue;
      previousRevenue[id] = (previousRevenue[id] ?? 0) + salePaise(sale);
      final name = sale.salesRepName;
      if (name != null && name.isNotEmpty) fallbackNames[id] ??= name;
    }

    for (final interaction in currentInteractions) {
      final id = (interaction.employeeId ?? interaction.employee).trim();
      if (id.isEmpty) continue;
      interactionCounts[id] = (interactionCounts[id] ?? 0) + 1;
      final name = interaction.employeeName;
      if (name != null && name.isNotEmpty) fallbackNames[id] ??= name;
    }

    for (final interaction in interactions) {
      final id = (interaction.employeeId ?? interaction.employee).trim();
      if (id.isEmpty) continue;
      final followUp = parseEventDate(interaction.followUpDate);
      if (followUp != null && followUp.isBefore(today)) {
        overdueCounts[id] = (overdueCounts[id] ?? 0) + 1;
      }
    }

    for (final client in currentNewClients) {
      final id = client.employeeId.trim();
      if (id.isEmpty) continue;
      newClientCounts[id] = (newClientCounts[id] ?? 0) + 1;
    }

    // Roster members appear even when idle; ids found only on records (a
    // departed employee) are kept so nothing drops out of the totals.
    final ids = <String>{
      ...employeeNames.keys,
      ...revenue.keys,
      ...previousRevenue.keys,
      ...interactionCounts.keys,
      ...newClientCounts.keys,
    };

    final teamRevenue = revenue.values.fold<int>(0, (a, b) => a + b);

    final rows = [
      for (final id in ids)
        EmployeePeriodRow(
          employeeId: id,
          name: employeeNames[id] ?? fallbackNames[id] ?? id,
          revenuePaise: revenue[id] ?? 0,
          previousRevenuePaise: previousRevenue[id] ?? 0,
          dealCount: deals[id] ?? 0,
          interactionCount: interactionCounts[id] ?? 0,
          newClientCount: newClientCounts[id] ?? 0,
          clientCount: MonthlyReportBuilder.distinctClientCount(
            salesByRep[id] ?? const [],
          ),
          overdueCount: overdueCounts[id] ?? 0,
          share: teamRevenue > 0 ? (revenue[id] ?? 0) / teamRevenue : 0,
        ),
    ];

    rows.sort((a, b) {
      final byRevenue = b.revenuePaise.compareTo(a.revenuePaise);
      if (byRevenue != 0) return byRevenue;
      final byDeals = b.dealCount.compareTo(a.dealCount);
      return byDeals != 0 ? byDeals : a.name.compareTo(b.name);
    });
    return rows;
  }
}
