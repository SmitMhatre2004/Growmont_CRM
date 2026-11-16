// lib/shared/charts/bucket.dart
//
// Turns a daily series of any length into something a chart can draw:
// daily up to 62 days, weekly up to 366, monthly beyond. Years of mostly
// zero days otherwise draw as a comb of single-day spikes.

import 'package:intl/intl.dart';

import '../../core/reports/monthly_report.dart';
import 'chart_models.dart';

enum BucketUnit { day, week, month }

const int kMaxDailyDays = 62;
const int kMaxWeeklyDays = 366;

/// The granularity [days] days of data should be drawn at.
BucketUnit bucketUnitFor(int days) {
  if (days <= kMaxDailyDays) return BucketUnit.day;
  if (days <= kMaxWeeklyDays) return BucketUnit.week;
  return BucketUnit.month;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _bucketStart(DateTime day, BucketUnit unit) => switch (unit) {
  BucketUnit.day => day,
  // Weeks start on Monday.
  BucketUnit.week => DateTime(day.year, day.month, day.day - (day.weekday - 1)),
  BucketUnit.month => DateTime(day.year, day.month),
};

String _bucketLabel(DateTime start, BucketUnit unit) => switch (unit) {
  BucketUnit.day => DateFormat('d MMM').format(start),
  BucketUnit.week => 'Wk of ${DateFormat('d MMM').format(start)}',
  BucketUnit.month => DateFormat('MMM yy').format(start),
};

/// Sums [days] (any order, gaps allowed) into buckets, oldest first. [unit]
/// overrides the automatic choice. A point's [ChartPoint.x] is the first day
/// present in its bucket and its [ChartPoint.detail] reads "3 sales".
List<ChartPoint> bucketDaily(List<DayTotal> days, {BucketUnit? unit}) {
  if (days.isEmpty) return const [];
  final sorted = [...days]..sort((a, b) => a.day.compareTo(b.day));
  final first = _dateOnly(sorted.first.day);
  final last = _dateOnly(sorted.last.day);
  final span = last.difference(first).inDays + 1;
  final u = unit ?? bucketUnitFor(span);

  final order = <DateTime>[];
  final rupees = <DateTime, double>{};
  final counts = <DateTime, int>{};
  final firstDay = <DateTime, DateTime>{};
  for (final d in sorted) {
    final day = _dateOnly(d.day);
    final key = _bucketStart(day, u);
    if (!rupees.containsKey(key)) {
      order.add(key);
      rupees[key] = 0;
      counts[key] = 0;
      firstDay[key] = day;
    }
    rupees[key] = rupees[key]! + d.rupees;
    counts[key] = counts[key]! + d.count;
  }

  return [
    for (final key in order)
      ChartPoint(
        x: firstDay[key],
        label: _bucketLabel(
          // "Wk of" names the first day we actually have, not a Monday
          // before the series began; months name the month.
          u == BucketUnit.week ? firstDay[key]! : key,
          u,
        ),
        y: rupees[key]!,
        count: counts[key]!,
        detail: counts[key]! > 0
            ? '${counts[key]} ${counts[key] == 1 ? 'sale' : 'sales'}'
            : null,
      ),
  ];
}
