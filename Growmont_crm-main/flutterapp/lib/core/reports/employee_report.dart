// lib/core/reports/employee_report.dart
//
// One employee's report for a period: their figures, rank among the team,
// daily series and an activity feed. Pure Dart. Team stats come from
// PeriodSummaryBuilder so the numbers match the team table exactly.

import '../../models/client.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../shared/widgets/monthly_revenue_chart.dart' show salePaise;
import '../theme/app_theme.dart' show frequencyChoices, productCategories;
import 'monthly_report.dart';
import 'monthly_report_builder.dart';
import 'period_summary_builder.dart';
import 'report_period.dart';

enum ActivityKind { sale, followUp, newClient }

class ActivityEntry {
  const ActivityEntry({
    required this.at,
    required this.kind,
    required this.clientName,
    this.detail,
    this.amountPaise,
    this.priority,
  });

  /// Event day (time if known).
  final DateTime at;
  final ActivityKind kind;
  final String clientName;

  /// sale: "Product · Frequency"; followUp: first line of the notes
  /// (trimmed, at most 120 chars); newClient: null.
  final String? detail;

  /// Sales only.
  final int? amountPaise;

  /// Follow-ups only (display label).
  final String? priority;
}

class EmployeeReport {
  const EmployeeReport({
    required this.employeeId,
    required this.name,
    required this.range,
    required this.previousRange,
    required this.rank,
    required this.teamSize,
    required this.share,
    required this.revenue,
    required this.deals,
    required this.clients,
    required this.newClients,
    required this.interactions,
    required this.avgDealPaise,
    required this.followUpsOverdue,
    required this.teamAvgRevenuePaise,
    required this.teamAvgDeals,
    required this.teamAvgInteractions,
    required this.dailyRevenue,
    required this.dailyInteractions,
    required this.revenueByProduct,
    required this.activity,
    required this.upcomingFollowUps,
  });

  final String employeeId;
  final String name;
  final DateRange range;
  final DateRange previousRange;

  /// 1-based by revenue among team rows; 0 if no team.
  final int rank;
  final int teamSize;

  /// Of team revenue, 0..1.
  final double share;
  final MetricDelta revenue, deals, clients, newClients, interactions;
  final int avgDealPaise;
  final int followUpsOverdue;
  final int? teamAvgRevenuePaise;

  /// Per team member, real division (0.3 follow-ups each is meaningful).
  final double? teamAvgDeals, teamAvgInteractions;
  final List<DayTotal> dailyRevenue;
  final List<DayTotal> dailyInteractions;
  final List<CategoryTotal> revenueByProduct;

  /// Newest first, every entry in range.
  final List<ActivityEntry> activity;

  /// followUpDate today or later, ascending, max 10.
  final List<Interaction> upcomingFollowUps;
}

class EmployeeReportBuilder {
  const EmployeeReportBuilder._();

  static String _interactionRepId(Interaction i) =>
      (i.employeeId ?? i.employee).trim();

  static EmployeeReport build({
    required DateRange range,
    DateRange? previous,
    required String employeeId,
    required List<Sale> sales,
    required List<Interaction> interactions,
    required List<Client> clients,
    Map<String, String> employeeNames = const {},
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final prev = previous ?? range.previousOfEqualLength;
    final id = employeeId.trim();

    final team = PeriodSummaryBuilder.build(
      range: range,
      previous: prev,
      sales: sales,
      interactions: interactions,
      clients: clients,
      employeeNames: employeeNames,
      now: clock,
    );
    final rows = team.employees;
    final rowIndex = rows.indexWhere((r) => r.employeeId == id);
    final row = rowIndex >= 0 ? rows[rowIndex] : null;
    final teamSize = rows.length;

    // This employee's records.
    final mySales = <Sale>[];
    final myPrevSales = <Sale>[];
    String? saleRepName;
    for (final sale in sales) {
      if (MonthlyReportBuilder.repIdOf(sale) != id) continue;
      final name = sale.salesRepName;
      if (saleRepName == null && name != null && name.isNotEmpty) {
        saleRepName = name;
      }
      final day = parseEventDate(sale.date);
      if (range.contains(day)) {
        mySales.add(sale);
      } else if (prev.contains(day)) {
        myPrevSales.add(sale);
      }
    }

    final myInteractions = <Interaction>[];
    var myPrevInteractions = 0;
    var overdue = 0;
    final upcoming = <(DateTime, Interaction)>[];
    for (final interaction in interactions) {
      if (_interactionRepId(interaction) != id) continue;
      final day = parseEventDate(interaction.date);
      if (range.contains(day)) {
        myInteractions.add(interaction);
      } else if (prev.contains(day)) {
        myPrevInteractions++;
      }
      final followUp = parseEventDate(interaction.followUpDate);
      if (followUp != null) {
        if (followUp.isBefore(today)) {
          overdue++;
        } else {
          upcoming.add((followUp, interaction));
        }
      }
    }
    upcoming.sort((a, b) {
      final byDay = a.$1.compareTo(b.$1);
      return byDay != 0
          ? byDay
          : a.$2.followUpTime.compareTo(b.$2.followUpTime);
    });

    final myNewClients = <Client>[];
    var myPrevNewClients = 0;
    for (final client in clients) {
      if (client.employeeId.trim() != id) continue;
      final day = parseInstantDay(client.createdAt);
      if (range.contains(day)) {
        myNewClients.add(client);
      } else if (prev.contains(day)) {
        myPrevNewClients++;
      }
    }

    int sum(List<Sale> l) => l.fold<int>(0, (t, s) => t + salePaise(s));
    final revenuePaise = sum(mySales);

    // Daily series.
    final revPaise = <DateTime, int>{};
    final revCount = <DateTime, int>{};
    for (final s in mySales) {
      final d = parseEventDate(s.date)!;
      revPaise[d] = (revPaise[d] ?? 0) + salePaise(s);
      revCount[d] = (revCount[d] ?? 0) + 1;
    }
    final intCount = <DateTime, int>{};
    for (final i in myInteractions) {
      final d = parseEventDate(i.date)!;
      intCount[d] = (intCount[d] ?? 0) + 1;
    }
    final days = [
      for (var i = 0; i < range.dayCount; i++)
        DateTime(range.start.year, range.start.month, range.start.day + i),
    ];

    // Activity feed.
    final activity = <ActivityEntry>[
      for (final s in mySales)
        ActivityEntry(
          at: parseEventDate(s.date)!,
          kind: ActivityKind.sale,
          clientName: s.clientName,
          detail: '${_productLabel(s)} · ${_frequencyLabel(s)}',
          amountPaise: salePaise(s),
        ),
      for (final i in myInteractions)
        ActivityEntry(
          at: parseEventDate(i.date)!,
          kind: ActivityKind.followUp,
          clientName: i.clientName,
          detail: _firstLine(i.discussionNotes),
          priority: i.priorityDisplay?.isNotEmpty == true
              ? i.priorityDisplay!
              : i.priority,
        ),
      for (final c in myNewClients)
        ActivityEntry(
          at: parseInstantDay(c.createdAt)!,
          kind: ActivityKind.newClient,
          clientName: c.name,
        ),
    ];
    // Newest first; tie-break on kind then client so order is deterministic.
    activity.sort((a, b) {
      final byAt = b.at.compareTo(a.at);
      if (byAt != 0) return byAt;
      final byKind = a.kind.index.compareTo(b.kind.index);
      return byKind != 0 ? byKind : a.clientName.compareTo(b.clientName);
    });

    final multi = teamSize >= 2;
    double avgOf(int Function(EmployeePeriodRow) f) =>
        rows.fold<int>(0, (t, r) => t + f(r)) / teamSize;

    return EmployeeReport(
      employeeId: id,
      name: employeeNames[id] ?? row?.name ?? saleRepName ?? id,
      range: range,
      previousRange: prev,
      rank: rowIndex >= 0 ? rowIndex + 1 : 0,
      teamSize: teamSize,
      share: row?.share ?? 0,
      revenue: MetricDelta(current: revenuePaise, previous: sum(myPrevSales)),
      deals: MetricDelta(
        current: mySales.length,
        previous: myPrevSales.length,
      ),
      clients: MetricDelta(
        current: MonthlyReportBuilder.distinctClientCount(mySales),
        previous: MonthlyReportBuilder.distinctClientCount(myPrevSales),
      ),
      newClients: MetricDelta(
        current: myNewClients.length,
        previous: myPrevNewClients,
      ),
      interactions: MetricDelta(
        current: myInteractions.length,
        previous: myPrevInteractions,
      ),
      avgDealPaise: mySales.isEmpty ? 0 : revenuePaise ~/ mySales.length,
      followUpsOverdue: overdue,
      teamAvgRevenuePaise: multi
          ? rows.fold<int>(0, (t, r) => t + r.revenuePaise) ~/ teamSize
          : null,
      teamAvgDeals: multi ? avgOf((r) => r.dealCount) : null,
      teamAvgInteractions: multi ? avgOf((r) => r.interactionCount) : null,
      dailyRevenue: [
        for (final d in days)
          DayTotal(day: d, paise: revPaise[d] ?? 0, count: revCount[d] ?? 0),
      ],
      dailyInteractions: [
        for (final d in days)
          DayTotal(day: d, paise: 0, count: intCount[d] ?? 0),
      ],
      revenueByProduct: MonthlyReportBuilder.categorize(mySales, _productLabel),
      activity: activity,
      upcomingFollowUps: [for (final u in upcoming.take(10)) u.$2],
    );
  }

  static String _productLabel(Sale s) => s.productDisplay?.isNotEmpty == true
      ? s.productDisplay!
      : MonthlyReportBuilder.labelFor(productCategories, s.product);

  static String _frequencyLabel(Sale s) =>
      s.frequencyDisplay?.isNotEmpty == true
          ? s.frequencyDisplay!
          : MonthlyReportBuilder.labelFor(frequencyChoices, s.frequency);

  static String? _firstLine(String notes) {
    final trimmed = notes.trim();
    if (trimmed.isEmpty) return null;
    var line = trimmed.split(RegExp(r'[\r\n]')).first.trim();
    if (line.length > 120) line = line.substring(0, 120);
    return line;
  }
}
