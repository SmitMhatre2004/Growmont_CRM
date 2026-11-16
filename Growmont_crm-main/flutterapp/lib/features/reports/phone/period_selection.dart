// lib/features/reports/phone/period_selection.dart
//
// What the phone Reports screens are looking at: a calendar month (the
// default) or an optional custom range of days. Immutable; a change makes a
// new value.

import 'package:intl/intl.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/reports/report_period.dart';
import '../widgets/month_picker_bar.dart' show formatReportMonth;

class ReportPeriodSelection {
  /// A whole calendar month. [latestMonth] is where forward travel stops.
  const ReportPeriodSelection.month(
    ReportMonth this.monthValue, {
    required this.latestMonth,
  }) : firstDay = null,
       lastDay = null;

  /// Inclusive first and last day of a custom range, already at midnight.
  /// Use [ReportPeriodSelection.customCapped] for picked dates.
  const ReportPeriodSelection.custom(
    DateTime this.firstDay,
    DateTime this.lastDay, {
    required this.latestMonth,
  }) : monthValue = null;

  /// A custom range from picked [start] and [end] days, normalised to
  /// midnight, ordered, and with the end no later than [today].
  factory ReportPeriodSelection.customCapped(
    DateTime start,
    DateTime end, {
    required ReportMonth latestMonth,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final cap = DateTime(now.year, now.month, now.day);
    var s = DateTime(start.year, start.month, start.day);
    var e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) (s, e) = (e, s);
    if (e.isAfter(cap)) e = cap;
    if (s.isAfter(e)) s = e;
    return ReportPeriodSelection.custom(s, e, latestMonth: latestMonth);
  }

  /// The current month: where every screen opens.
  factory ReportPeriodSelection.currentMonth([DateTime? now]) {
    final m = ReportMonth.current(now);
    return ReportPeriodSelection.month(m, latestMonth: m);
  }

  final ReportMonth? monthValue;
  final DateTime? firstDay;
  final DateTime? lastDay;

  /// Forward travel stops here.
  final ReportMonth latestMonth;

  bool get isMonth => monthValue != null;
  bool get isCustom => !isMonth;

  /// The selected month. Only meaningful in month mode; custom mode answers
  /// with the month the range ends in.
  ReportMonth get month => monthValue ?? ReportMonth.of(lastDay!);

  DateRange get range => isMonth
      ? monthValue!.range
      : DateRange(
          firstDay!,
          DateTime(lastDay!.year, lastDay!.month, lastDay!.day + 1),
        );

  DateRange get previousRange =>
      isMonth ? monthValue!.previous.range : range.previousOfEqualLength;

  /// "November 2026", "1 Oct – 15 Nov 2026", "1 – 15 Nov 2026", "5 Nov 2026".
  String get label {
    if (isMonth) return formatReportMonth(monthValue!);
    final s = firstDay!;
    final e = lastDay!;
    if (s == e) return DateFormat('d MMM yyyy').format(e);
    if (s.year != e.year) {
      final f = DateFormat('d MMM yyyy');
      return '${f.format(s)} – ${f.format(e)}';
    }
    if (s.month != e.month) {
      return '${DateFormat('d MMM').format(s)} – '
          '${DateFormat('d MMM yyyy').format(e)}';
    }
    return '${s.day} – ${DateFormat('d MMM yyyy').format(e)}';
  }

  /// The tail of "vs ...": the previous month's short name, or
  /// "previous period".
  String get previousLabel => isMonth
      ? DateFormat('MMM').format(monthValue!.previous.start)
      : 'previous period';

  /// "vs Oct" / "vs previous period".
  String get deltaLabel => 'vs $previousLabel';

  String get emptyText =>
      isMonth ? 'No activity this month' : 'No activity in this period';

  bool get canGoNext => isMonth && monthValue!.compareTo(latestMonth) < 0;

  ReportPeriodSelection previous() => isMonth
      ? ReportPeriodSelection.month(
          monthValue!.previous,
          latestMonth: latestMonth,
        )
      : this;

  ReportPeriodSelection next() => !canGoNext
      ? this
      : ReportPeriodSelection.month(monthValue!.next, latestMonth: latestMonth);

  ReportPeriodSelection withMonth(ReportMonth m) =>
      ReportPeriodSelection.month(m, latestMonth: latestMonth);

  /// Back to the current month.
  ReportPeriodSelection toCurrentMonth() =>
      ReportPeriodSelection.month(latestMonth, latestMonth: latestMonth);

  @override
  bool operator ==(Object other) =>
      other is ReportPeriodSelection &&
      other.monthValue == monthValue &&
      other.firstDay == firstDay &&
      other.lastDay == lastDay &&
      other.latestMonth == latestMonth;

  @override
  int get hashCode => Object.hash(monthValue, firstDay, lastDay, latestMonth);
}
