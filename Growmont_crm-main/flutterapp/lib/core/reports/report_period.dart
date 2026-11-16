// lib/core/reports/report_period.dart
//
// Period types for the phone Reports layout: a half-open [DateRange] and
// [ReportWeek], a Monday-start calendar week. Pure Dart, like
// monthly_report.dart, so the boundaries can be unit-tested directly.

import 'package:intl/intl.dart';

import 'monthly_report.dart';

/// A half-open `[start, endExclusive)` range of calendar days.
class DateRange {
  const DateRange(this.start, this.endExclusive);

  final DateTime start;
  final DateTime endExclusive;

  /// Whole calendar days covered (DST-safe: counted from y/m/d fields).
  int get dayCount {
    final s = DateTime.utc(start.year, start.month, start.day);
    final e = DateTime.utc(endExclusive.year, endExclusive.month, endExclusive.day);
    return e.difference(s).inDays;
  }

  /// The range of equal length ending where this one starts.
  DateRange get previousOfEqualLength {
    final days = dayCount;
    return DateRange(
      DateTime(start.year, start.month, start.day - days),
      start,
    );
  }

  /// True if [day] is inside the range. Null is never inside.
  bool contains(DateTime? day) =>
      day != null && !day.isBefore(start) && day.isBefore(endExclusive);

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      other.start == start &&
      other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(start, endExclusive);
}

extension ReportMonthRange on ReportMonth {
  /// This month as a [DateRange].
  DateRange get range => DateRange(start, endExclusive);
}

/// One calendar week, Monday through Sunday.
class ReportWeek implements Comparable<ReportWeek> {
  const ReportWeek._(this.start);

  /// The week [date] falls in. Time of day is dropped.
  factory ReportWeek.of(DateTime date) {
    // DateTime.weekday: Monday = 1 ... Sunday = 7.
    return ReportWeek._(
      DateTime(date.year, date.month, date.day - (date.weekday - 1)),
    );
  }

  /// The week [now] (default: the real clock) falls in.
  factory ReportWeek.current([DateTime? now]) =>
      ReportWeek.of(now ?? DateTime.now());

  /// The Monday that opens the week, at local midnight.
  final DateTime start;

  DateTime get endExclusive => DateTime(start.year, start.month, start.day + 7);

  /// The Sunday that closes the week.
  DateTime get lastDay => DateTime(start.year, start.month, start.day + 6);

  DateRange get range => DateRange(start, endExclusive);

  ReportWeek get previous =>
      ReportWeek._(DateTime(start.year, start.month, start.day - 7));
  ReportWeek get next =>
      ReportWeek._(DateTime(start.year, start.month, start.day + 7));

  bool contains(DateTime? day) => range.contains(day);

  /// "10–16 Nov 2026", "28 Sep – 4 Oct 2026", "28 Dec 2026 – 3 Jan 2027".
  String get label {
    final end = lastDay;
    if (start.year != end.year) {
      final f = DateFormat('d MMM yyyy');
      return '${f.format(start)} – ${f.format(end)}';
    }
    if (start.month != end.month) {
      return '${DateFormat('d MMM').format(start)} – '
          '${DateFormat('d MMM yyyy').format(end)}';
    }
    return '${start.day}–${DateFormat('d MMM yyyy').format(end)}';
  }

  /// Short form used in "vs ..." chips, e.g. "3–9 Nov".
  String get shortLabel {
    final end = lastDay;
    if (start.month != end.month) {
      return '${DateFormat('d MMM').format(start)} – '
          '${DateFormat('d MMM').format(end)}';
    }
    return '${start.day}–${DateFormat('d MMM').format(end)}';
  }

  @override
  int compareTo(ReportWeek other) => start.compareTo(other.start);

  @override
  bool operator ==(Object other) => other is ReportWeek && other.start == start;

  @override
  int get hashCode => start.hashCode;

  @override
  String toString() => 'ReportWeek(${start.toIso8601String()})';
}
