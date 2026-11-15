// lib/core/reports/monthly_report_builder.dart
//
// Turns the model lists the screen already loads into one [MonthlyReport].
// Pure: no I/O, no clock reads except the injectable [now], no widgets —
// so test/monthly_report_test.dart can assert every figure directly.
//
// Read monthly_report.dart's header first; it states the date-basis and
// month-boundary rules this file implements.

import '../../models/client.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../shared/widgets/monthly_revenue_chart.dart' show salePaise;
import '../theme/app_theme.dart'
    show frequencyChoices, priorityChoices, productCategories;
import 'monthly_report.dart';

/// How many months the monthly trend series covers, ending with the
/// selected one. Still used by the Excel and PDF exports' trend table.
const int kTrendMonths = 12;

/// How many days the daily trend series covers. A year, so the chart's
/// period selector can slice 3, 6 or 12 months out of one computation.
const int kTrendDays = 365;

/// How many of the month's largest sales the report lists.
const int kTopDealCount = 5;

/// Shown wherever a record leaves a grouping field blank, so a blank never
/// silently merges into another bucket or disappears from a total.
const String kUnspecifiedLabel = 'Unspecified';

class MonthlyReportBuilder {
  const MonthlyReportBuilder._();

  /// Builds the report for [period] from the caller's already-scoped data.
  ///
  /// The lists MUST already be scoped to what the signed-in user may see.
  /// This function applies no access filtering of its own — it has no
  /// notion of who is asking beyond [scope] — so the caller is responsible
  /// for passing an owner filter to `getSales()` and friends for a
  /// non-admin. See the header of monthly_report_screen.dart for why the
  /// local database cannot be assumed to be pre-scoped.
  ///
  /// [employeeNames] maps employee id to display name for the team table.
  /// Only names are needed, so the caller can pass the cheap
  /// `getEmployeesDropdown()` result rather than full [Employee] objects —
  /// `getEmployees()` loads four collections to compute its counts, which
  /// would mean reading sales twice for one report.
  ///
  /// [now] defaults to the real clock and is only used to decide which
  /// follow-ups have a date in the past, and to stamp the report.
  static MonthlyReport build({
    required ReportMonth period,
    required ReportScope scope,
    required String scopeLabel,
    required List<Sale> sales,
    required List<Interaction> interactions,
    required List<Client> clients,
    Map<String, String> employeeNames = const {},
    DateTime? now,
  }) {
    final generatedAt = now ?? DateTime.now();
    final today = DateTime(generatedAt.year, generatedAt.month, generatedAt.day);
    final previous = period.previous;

    // ── Sales: split into the two months once, then reuse ──────────────
    final currentSales = <Sale>[];
    final previousSales = <Sale>[];
    var salesWithoutDate = 0;

    for (final sale in sales) {
      final day = parseEventDate(sale.date);
      if (day == null) {
        salesWithoutDate++;
        continue;
      }
      if (period.contains(day)) {
        currentSales.add(sale);
      } else if (previous.contains(day)) {
        previousSales.add(sale);
      }
    }

    final revenue = MetricDelta(
      current: _sumPaise(currentSales),
      previous: _sumPaise(previousSales),
    );
    final deals = MetricDelta(
      current: currentSales.length,
      previous: previousSales.length,
    );
    final activeClients = MetricDelta(
      current: _distinctClients(currentSales),
      previous: _distinctClients(previousSales),
    );

    // ── Interactions ───────────────────────────────────────────────────
    final currentInteractions = <Interaction>[];
    var previousInteractionCount = 0;
    var interactionsWithoutDate = 0;
    var followUpsScheduled = 0;
    var followUpsPastDue = 0;

    for (final interaction in interactions) {
      final day = parseEventDate(interaction.date);
      if (day == null) {
        interactionsWithoutDate++;
      } else if (period.contains(day)) {
        currentInteractions.add(interaction);
      } else if (previous.contains(day)) {
        previousInteractionCount++;
      }

      // Follow-up load is counted on its own date, independently of when
      // the interaction itself happened: a call logged in March can
      // schedule an April follow-up, and April's report should show it.
      final followUp = parseEventDate(interaction.followUpDate);
      if (period.contains(followUp)) {
        followUpsScheduled++;
        if (!followUp!.isAfter(today)) followUpsPastDue++;
      }
    }

    // ── Clients acquired, by creation date ─────────────────────────────
    var newClientCount = 0;
    var previousNewClientCount = 0;
    var clientsWithoutCreatedAt = 0;

    for (final client in clients) {
      final day = parseInstantDay(client.createdAt);
      if (day == null) {
        clientsWithoutCreatedAt++;
        continue;
      }
      if (period.contains(day)) {
        newClientCount++;
      } else if (previous.contains(day)) {
        previousNewClientCount++;
      }
    }

    // ── Breakdowns ─────────────────────────────────────────────────────
    final topDeals = [...currentSales]
      ..sort((a, b) => salePaise(b).compareTo(salePaise(a)));

    return MonthlyReport(
      period: period,
      scope: scope,
      scopeLabel: scopeLabel,
      generatedAt: generatedAt,
      revenue: revenue,
      deals: deals,
      activeClients: activeClients,
      newClients: MetricDelta(
        current: newClientCount,
        previous: previousNewClientCount,
      ),
      interactions: MetricDelta(
        current: currentInteractions.length,
        previous: previousInteractionCount,
      ),
      interactionsByPriority: _interactionsByPriority(currentInteractions),
      followUpsScheduled: followUpsScheduled,
      followUpsPastDue: followUpsPastDue,
      revenueByProduct: _categorize(
        currentSales,
        (s) => s.productDisplay?.isNotEmpty == true
            ? s.productDisplay!
            : _labelFor(productCategories, s.product),
      ),
      revenueByCompany: _categorize(currentSales, (s) => s.company),
      // Scale order (Monthly -> One Time), NOT largest-first: payment
      // frequency is an ordered scale, and the segmented bar that draws it
      // reads left to right along that scale. Re-sorting by size would
      // turn an ordered split into a ranked list wearing an ordinal ramp.
      revenueByFrequency: _categorizeInScaleOrder(
        currentSales,
        frequencyChoices,
        (s) => s.frequency,
      ),
      trailingRevenue: _trailingRevenue(sales, period),
      dailyRevenue: _dailyRevenue(sales, period),
      topDeals: topDeals.take(kTopDealCount).toList(),
      team: scope == ReportScope.company
          ? _teamPerformance(
              currentSales: currentSales,
              previousSales: previousSales,
              currentInteractions: currentInteractions,
              employeeNames: employeeNames,
            )
          : const [],
      quality: DataQuality(
        salesWithoutDate: salesWithoutDate,
        interactionsWithoutDate: interactionsWithoutDate,
        clientsWithoutCreatedAt: clientsWithoutCreatedAt,
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static int _sumPaise(List<Sale> sales) =>
      sales.fold<int>(0, (total, s) => total + salePaise(s));

  /// Distinct clients behind a set of sales. Prefers `client_id`; falls
  /// back to the normalized client name for older rows written before the
  /// id was stored, which is the same fallback the Sales screen's "ACTIVE
  /// CLIENTS" box uses. Sales with neither are not counted — there is
  /// nothing to tell them apart by.
  static int _distinctClients(List<Sale> sales) {
    final keys = <String>{};
    for (final sale in sales) {
      final id = sale.clientId;
      if (id != null && id.isNotEmpty) {
        keys.add('id:$id');
        continue;
      }
      final name = sale.clientName.trim().toLowerCase();
      if (name.isNotEmpty) keys.add('name:$name');
    }
    return keys.length;
  }

  /// Resolves a stored code to its display label using one of the
  /// `(code, label)` lists in app_theme.dart, so the report always names
  /// a product or frequency the way the rest of the app does.
  static String _labelFor(
    List<(String, String)> choices,
    String code,
  ) {
    if (code.isEmpty) return kUnspecifiedLabel;
    for (final (value, label) in choices) {
      if (value == code) return label;
    }
    return code;
  }

  /// Groups sales by a label, summing paise and counting rows. Sorted by
  /// value descending so the biggest contributor reads first; ties break
  /// on count, then alphabetically, so the order is stable across rebuilds.
  static List<CategoryTotal> _categorize(
    List<Sale> sales,
    String Function(Sale) labelOf,
  ) {
    final paise = <String, int>{};
    final counts = <String, int>{};

    for (final sale in sales) {
      var label = labelOf(sale).trim();
      if (label.isEmpty) label = kUnspecifiedLabel;
      paise[label] = (paise[label] ?? 0) + salePaise(sale);
      counts[label] = (counts[label] ?? 0) + 1;
    }

    final rows = [
      for (final entry in paise.entries)
        CategoryTotal(
          label: entry.key,
          paise: entry.value,
          count: counts[entry.key] ?? 0,
        ),
    ];

    rows.sort((a, b) {
      final byPaise = b.paise.compareTo(a.paise);
      if (byPaise != 0) return byPaise;
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.label.compareTo(b.label);
    });
    return rows;
  }

  /// Groups sales into the order a `(code, label)` scale declares, rather
  /// than by size. Codes outside the scale are appended after it so a
  /// stray value is still counted; an empty scale slot is kept at zero so
  /// the ordering never shifts between months.
  static List<CategoryTotal> _categorizeInScaleOrder(
    List<Sale> sales,
    List<(String, String)> scale,
    String Function(Sale) codeOf,
  ) {
    final paise = <String, int>{};
    final counts = <String, int>{};

    for (final sale in sales) {
      final code = codeOf(sale);
      paise[code] = (paise[code] ?? 0) + salePaise(sale);
      counts[code] = (counts[code] ?? 0) + 1;
    }

    final rows = <CategoryTotal>[
      for (final (code, label) in scale)
        CategoryTotal(
          label: label,
          paise: paise.remove(code) ?? 0,
          count: counts.remove(code) ?? 0,
        ),
    ];
    for (final leftover in paise.entries) {
      rows.add(
        CategoryTotal(
          label: leftover.key.isEmpty ? kUnspecifiedLabel : leftover.key,
          paise: leftover.value,
          count: counts[leftover.key] ?? 0,
        ),
      );
    }
    return rows;
  }

  /// HIGH/MEDIUM/LOW counts in the fixed order [priorityChoices] declares,
  /// including a zero row, so the bar order never shuffles between months.
  /// `paise` is 0 on these rows: an interaction carries no money.
  static List<CategoryTotal> _interactionsByPriority(
    List<Interaction> interactions,
  ) {
    final counts = <String, int>{};
    for (final interaction in interactions) {
      final key = interaction.priority.isEmpty ? 'MEDIUM' : interaction.priority;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final rows = <CategoryTotal>[
      for (final (code, label) in priorityChoices)
        CategoryTotal(label: label, paise: 0, count: counts.remove(code) ?? 0),
    ];
    // Anything with a priority outside the known set still gets a row,
    // rather than vanishing from a total the user can cross-check.
    for (final leftover in counts.entries) {
      rows.add(
        CategoryTotal(label: leftover.key, paise: 0, count: leftover.value),
      );
    }
    return rows;
  }

  /// One entry per day for [kTrendDays] ending on [period]'s last day,
  /// oldest first.
  ///
  /// Days with no sales are present as zeros. A line that simply skipped
  /// them would space its points by "days that happened to have a sale",
  /// which compresses quiet stretches and makes a busy week look the same
  /// width as a dead month.
  static List<DayTotal> _dailyRevenue(List<Sale> sales, ReportMonth period) {
    final end = period.lastDay;
    final paise = <DateTime, int>{};
    final counts = <DateTime, int>{};

    for (final sale in sales) {
      final day = parseEventDate(sale.date);
      if (day == null) continue;
      if (day.isAfter(end)) continue;
      if (end.difference(day).inDays >= kTrendDays) continue;
      paise[day] = (paise[day] ?? 0) + salePaise(sale);
      counts[day] = (counts[day] ?? 0) + 1;
    }

    return [
      for (var back = kTrendDays - 1; back >= 0; back--)
        () {
          // Built from y/m/d rather than by subtracting Durations, so a
          // daylight-saving boundary cannot shift a day by an hour and
          // land two entries on the same date.
          final day = DateTime(end.year, end.month, end.day - back);
          return DayTotal(
            day: day,
            paise: paise[day] ?? 0,
            count: counts[day] ?? 0,
          );
        }(),
    ];
  }

  /// Revenue for the [kTrendMonths] months ending with [period], oldest
  /// first. Months with no sales are present as zero rows so the chart
  /// keeps an even x-axis instead of collapsing gaps.
  static List<MonthTotal> _trailingRevenue(
    List<Sale> sales,
    ReportMonth period,
  ) {
    final paise = <ReportMonth, int>{};
    final counts = <ReportMonth, int>{};
    final window = <ReportMonth>[];

    for (var back = kTrendMonths - 1; back >= 0; back--) {
      final month = ReportMonth.of(
        DateTime(period.year, period.month - back, 1),
      );
      window.add(month);
      paise[month] = 0;
      counts[month] = 0;
    }

    for (final sale in sales) {
      final day = parseEventDate(sale.date);
      if (day == null) continue;
      final month = ReportMonth.of(day);
      if (!paise.containsKey(month)) continue;
      paise[month] = paise[month]! + salePaise(sale);
      counts[month] = counts[month]! + 1;
    }

    return [
      for (final month in window)
        MonthTotal(
          month: month,
          paise: paise[month] ?? 0,
          count: counts[month] ?? 0,
        ),
    ];
  }

  /// Per-employee rows for the period, highest revenue first.
  ///
  /// Attribution uses each sale's own `sales_rep_id`, which a client
  /// transfer never rewrites, so a past month's split stays correct even
  /// after clients change hands. Only employees with activity in the
  /// current or previous month appear — a roster of zeroes would bury the
  /// people who actually sold something.
  static List<EmployeePerformance> _teamPerformance({
    required List<Sale> currentSales,
    required List<Sale> previousSales,
    required List<Interaction> currentInteractions,
    required Map<String, String> employeeNames,
  }) {
    final revenue = <String, int>{};
    final deals = <String, int>{};
    final previousRevenue = <String, int>{};
    final interactionCounts = <String, int>{};
    final fallbackNames = <String, String>{};

    for (final sale in currentSales) {
      final id = _repId(sale);
      if (id.isEmpty) continue;
      revenue[id] = (revenue[id] ?? 0) + salePaise(sale);
      deals[id] = (deals[id] ?? 0) + 1;
      final name = sale.salesRepName;
      if (name != null && name.isNotEmpty) fallbackNames[id] ??= name;
    }

    for (final sale in previousSales) {
      final id = _repId(sale);
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

    // Everyone on the roster appears, not only the people who sold
    // something. An admin reading a team table needs to see who had a
    // quiet month as much as who led it, and a name that vanishes in a
    // slow month looks like a bug. Ids found only on records — a
    // departed employee's sales — are included too, so nothing is
    // dropped from the totals.
    final ids = <String>{
      ...employeeNames.keys,
      ...revenue.keys,
      ...previousRevenue.keys,
      ...interactionCounts.keys,
    };

    final rows = [
      for (final id in ids)
        EmployeePerformance(
          employeeId: id,
          // A deleted employee's sales still belong in the total, so fall
          // back to the name denormalized onto the record, then the raw id.
          name: employeeNames[id] ?? fallbackNames[id] ?? id,
          revenuePaise: revenue[id] ?? 0,
          previousRevenuePaise: previousRevenue[id] ?? 0,
          dealCount: deals[id] ?? 0,
          interactionCount: interactionCounts[id] ?? 0,
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

  static String _repId(Sale sale) =>
      (sale.salesRepId?.isNotEmpty == true ? sale.salesRepId! : sale.salesRep)
          .trim();
}
