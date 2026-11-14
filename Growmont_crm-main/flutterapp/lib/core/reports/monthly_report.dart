// lib/core/reports/monthly_report.dart
//
// Value types for the Monthly Report screen. Everything here is plain
// Dart over already-loaded models — no Firestore, no SQLite, no widgets —
// so every number the screen and the export show can be unit-tested in
// isolation (see test/monthly_report_test.dart). The aggregation itself
// lives in monthly_report_builder.dart.
//
// ─── Why the numbers are what they are ──────────────────────────────────
//
// 1. DATE BASIS. Each metric is computed on exactly one basis, and the UI
//    labels which one:
//      * event date    — sales.date, interactions.date, follow_up_date.
//                        The business date the user picked.
//      * creation date — clients.created_at. When the row entered the CRM.
//      * current state — the employee roster and client ownership. These
//                        are NOT historical; see §3.
//
// 2. MONTH BOUNDARY. A month is the half-open interval
//    [first of month, first of next month). A record belongs to the month
//    its *displayed* calendar date falls in: parseEventDate reads the
//    stored timestamp's own y/m/d fields without shifting time zones,
//    which is exactly what AppFormatters.formatDate does when the list
//    screens render that same date. So the report can never disagree with
//    the Sales screen about which month a sale is in — even though the
//    underlying Firestore Timestamp is an absolute instant and would
//    bucket differently if it were converted to another zone.
//    parseInstantDay is the opposite case: created_at is a real instant,
//    not a picked date, so it IS converted to local time first.
//
// 3. NO HISTORICAL SNAPSHOTS. This CRM keeps no event log, so a closed
//    month is recomputed from the records as they exist *today*. Delete or
//    edit a sale and last month's revenue changes with it. Sales and
//    interactions do carry their own employee id, which transferClient
//    never rewrites, so per-employee revenue for a past month is stable;
//    client *ownership* is current-state only.
//
// 4. MONEY. Summed as int paise and divided only at render, so repeated
//    float addition can never drift.

import '../../models/sale.dart';

// ─── Date parsing ───────────────────────────────────────────────────────

/// Parses a user-picked business date (`sales.date`, `interactions.date`,
/// `follow_up_date`) to the calendar day it displays as, with the time
/// component dropped.
///
/// Deliberately does NOT convert time zones — see the header, §2. Returns
/// null for an empty or unparseable value, which callers must count rather
/// than silently drop.
DateTime? parseEventDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Parses a machine-written instant (`created_at`) to the local calendar
/// day it happened on. Unlike [parseEventDate] this one does convert to
/// local time, because the value is a moment rather than a chosen date.
DateTime? parseInstantDay(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  return DateTime(local.year, local.month, local.day);
}

// ─── Period ─────────────────────────────────────────────────────────────

/// One calendar month, as a half-open `[start, endExclusive)` range.
///
/// All arithmetic goes through DateTime's own constructor, which
/// normalizes an out-of-range month (0 -> December of the previous year,
/// 13 -> January of the next). That is what makes the December/January
/// rollover and February's length — leap year or not — fall out for free
/// instead of needing special cases.
class ReportMonth implements Comparable<ReportMonth> {
  const ReportMonth(this.year, this.month);

  factory ReportMonth.of(DateTime date) => ReportMonth(date.year, date.month);

  /// The month [now] (default: the real clock) falls in.
  factory ReportMonth.current([DateTime? now]) =>
      ReportMonth.of(now ?? DateTime.now());

  final int year;
  final int month;

  DateTime get start => DateTime(year, month, 1);
  DateTime get endExclusive => DateTime(year, month + 1, 1);

  /// Last calendar day of the month — 28/29 Feb included correctly.
  DateTime get lastDay => endExclusive.subtract(const Duration(days: 1));

  int get dayCount => lastDay.day;

  ReportMonth get previous => ReportMonth.of(DateTime(year, month - 1, 1));
  ReportMonth get next => ReportMonth.of(DateTime(year, month + 1, 1));

  /// True if [day] falls inside this month. Null (an unparseable or
  /// missing date) is never inside any month.
  bool contains(DateTime? day) =>
      day != null && !day.isBefore(start) && day.isBefore(endExclusive);

  @override
  int compareTo(ReportMonth other) {
    final byYear = year.compareTo(other.year);
    return byYear != 0 ? byYear : month.compareTo(other.month);
  }

  @override
  bool operator ==(Object other) =>
      other is ReportMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}

// ─── Value types ────────────────────────────────────────────────────────

/// A metric alongside the same metric for the previous month, so the UI
/// can draw a delta without recomputing anything.
class MetricDelta {
  const MetricDelta({required this.current, required this.previous});

  const MetricDelta.zero() : current = 0, previous = 0;

  final num current;
  final num previous;

  num get change => current - previous;

  /// Percentage change, or null when there is no baseline to compare
  /// against. Null means "no previous data", which the UI must render as
  /// an em dash rather than as 0% or as a 100% rise.
  double? get percentChange {
    if (previous == 0) return null;
    return (current - previous) / previous.abs() * 100;
  }

  bool get isUp => change > 0;
  bool get isDown => change < 0;
  bool get isFlat => change == 0;
}

/// One row of a breakdown table (product, company, frequency, priority).
class CategoryTotal {
  const CategoryTotal({
    required this.label,
    required this.paise,
    required this.count,
  });

  final String label;
  final int paise;
  final int count;

  double get rupees => paise / 100;
}

/// Revenue for one month in a trailing series.
class MonthTotal {
  const MonthTotal({
    required this.month,
    required this.paise,
    required this.count,
  });

  final ReportMonth month;
  final int paise;
  final int count;

  double get rupees => paise / 100;
}

/// One employee's contribution for the period. Admin-only.
class EmployeePerformance {
  const EmployeePerformance({
    required this.employeeId,
    required this.name,
    required this.revenuePaise,
    required this.previousRevenuePaise,
    required this.dealCount,
    required this.interactionCount,
  });

  final String employeeId;
  final String name;
  final int revenuePaise;
  final int previousRevenuePaise;
  final int dealCount;
  final int interactionCount;

  double get revenueRupees => revenuePaise / 100;

  int get avgDealPaise => dealCount > 0 ? revenuePaise ~/ dealCount : 0;

  MetricDelta get revenueDelta =>
      MetricDelta(current: revenuePaise, previous: previousRevenuePaise);
}

/// Counts of records that could not be placed in time. Surfaced in the UI
/// as a data-quality note instead of being discarded quietly — a report
/// that drops rows without saying so is worse than one that admits it.
class DataQuality {
  const DataQuality({
    this.salesWithoutDate = 0,
    this.interactionsWithoutDate = 0,
    this.clientsWithoutCreatedAt = 0,
  });

  final int salesWithoutDate;
  final int interactionsWithoutDate;

  /// Clients carrying no parseable `created_at`. Such a row can never be
  /// counted as acquired in any month, so the acquisition figure is a
  /// floor, not a total, whenever this is above zero.
  final int clientsWithoutCreatedAt;

  bool get hasIssues =>
      salesWithoutDate > 0 ||
      interactionsWithoutDate > 0 ||
      clientsWithoutCreatedAt > 0;
}

/// Whether the report covers the whole company or a single user. Drives
/// both the heading and whether the team section is computed at all.
enum ReportScope { company, individual }

// ─── The report ─────────────────────────────────────────────────────────

/// Every figure the Monthly Report screen and its Excel export display.
/// Both render from this one object, so the two can never disagree.
class MonthlyReport {
  const MonthlyReport({
    required this.period,
    required this.scope,
    required this.scopeLabel,
    required this.generatedAt,
    required this.revenue,
    required this.deals,
    required this.activeClients,
    required this.newClients,
    required this.interactions,
    required this.interactionsByPriority,
    required this.followUpsScheduled,
    required this.followUpsPastDue,
    required this.revenueByProduct,
    required this.revenueByCompany,
    required this.revenueByFrequency,
    required this.trailingRevenue,
    required this.topDeals,
    required this.team,
    required this.quality,
  });

  final ReportMonth period;
  final ReportScope scope;

  /// Who the report is about: the company, or one person's name.
  final String scopeLabel;

  /// When the figures were computed. Stamped into the export.
  final DateTime generatedAt;

  /// Revenue in paise, with the previous month as baseline.
  final MetricDelta revenue;

  /// Count of sales dated in the month ("deals closed"). Every sale in
  /// this CRM is a closed deal — there is no won/lost state to split on.
  final MetricDelta deals;

  /// Distinct clients with at least one sale in the month.
  final MetricDelta activeClients;

  /// Clients whose created_at falls in the month. Depends on a field that
  /// older rows may not carry — see [DataQuality.clientsWithoutCreatedAt].
  final MetricDelta newClients;

  final MetricDelta interactions;

  /// HIGH/MEDIUM/LOW counts for interactions dated in the month.
  final List<CategoryTotal> interactionsByPriority;

  /// Follow-ups whose follow_up_date falls in the month. This counts what
  /// was *scheduled*, not what was done: the data model has no completion
  /// flag on an interaction, so completion cannot be reported.
  final int followUpsScheduled;

  /// Of those, how many fall on or before [generatedAt]'s day — i.e. their
  /// date has passed. Again: passed, not necessarily outstanding.
  final int followUpsPastDue;

  final List<CategoryTotal> revenueByProduct;
  final List<CategoryTotal> revenueByCompany;
  final List<CategoryTotal> revenueByFrequency;

  /// Trailing 12 months ending with [period], oldest first.
  final List<MonthTotal> trailingRevenue;

  /// Largest sales of the month, biggest first.
  final List<Sale> topDeals;

  /// Per-employee rows, highest revenue first. Empty for an individual
  /// report — an employee's local database holds nobody else's sales, so
  /// there is nothing to aggregate even if the UI asked.
  final List<EmployeePerformance> team;

  final DataQuality quality;

  double get revenueRupees => revenue.current / 100;

  int get avgDealPaise =>
      deals.current > 0 ? (revenue.current ~/ deals.current) : 0;

  int get previousAvgDealPaise =>
      deals.previous > 0 ? (revenue.previous ~/ deals.previous) : 0;

  MetricDelta get avgDeal =>
      MetricDelta(current: avgDealPaise, previous: previousAvgDealPaise);

  /// True when the month has no activity at all, so the UI can show one
  /// honest empty state instead of a grid of zeroes.
  bool get isEmpty =>
      revenue.current == 0 &&
      deals.current == 0 &&
      interactions.current == 0 &&
      newClients.current == 0 &&
      followUpsScheduled == 0;
}
