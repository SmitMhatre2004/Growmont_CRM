// lib/features/reports/phone/employee_sections.dart
//
// Blocks specific to one person's report: the identity row, the comparison
// with the team average, the daily revenue / follow-up chart, the activity
// timeline and the upcoming follow-ups.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reports/employee_report.dart';
import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/interaction.dart';
import '../../../shared/charts/charts.dart';
import '../../../shared/widgets/monogram.dart';
import 'phone_style.dart';

// ── Identity ────────────────────────────────────────────────────────────

class EmployeeIdentity extends StatelessWidget {
  const EmployeeIdentity({super.key, required this.report});

  final EmployeeReport report;

  @override
  Widget build(BuildContext context) {
    final showTeam =
        report.teamSize >= 2 && report.rank > 0 && report.revenue.current > 0;
    return Row(
      children: [
        Monogram(name: report.name, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhoneText.number(18),
              ),
              if (showTeam) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip('Rank #${report.rank} of ${report.teamSize}'),
                    _Chip('${(report.share * 100).round()}% of team'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surfaceSelected,
      borderRadius: BorderRadius.circular(AppRadius.full),
    ),
    child: Text(
      text,
      style: PhoneText.number(
        12,
        weight: FontWeight.w700,
        color: AppColors.primaryBlue,
      ),
    ),
  );
}

// ── Vs team average ─────────────────────────────────────────────────────

class VsTeamAverage extends StatelessWidget {
  const VsTeamAverage({super.key, required this.report});

  final EmployeeReport report;

  @override
  Widget build(BuildContext context) {
    final avgRevenue = report.teamAvgRevenuePaise;
    final avgDeals = report.teamAvgDeals;
    final avgInteractions = report.teamAvgInteractions;
    if (avgRevenue == null || avgDeals == null || avgInteractions == null) {
      return const SizedBox.shrink();
    }

    final rows = [
      _CompareRow(
        label: 'Revenue',
        value: report.revenue.current.toDouble(),
        average: avgRevenue.toDouble(),
        text:
            '${compactMoney(report.revenue.current)} vs '
            '${compactMoney(avgRevenue)} avg',
      ),
      _CompareRow(
        label: 'Deals',
        value: report.deals.current.toDouble(),
        average: avgDeals.toDouble(),
        text: '${report.deals.current} vs ${avgDeals.toStringAsFixed(1)} avg',
      ),
      _CompareRow(
        label: 'Follow-ups',
        value: report.interactions.current.toDouble(),
        average: avgInteractions.toDouble(),
        text:
            '${report.interactions.current} vs '
            '${avgInteractions.toStringAsFixed(1)} avg',
      ),
    ];

    return PhoneSection(
      title: 'Vs team average',
      child: PhoneCard(
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.value,
    required this.average,
    required this.text,
  });

  final String label;
  final double value;
  final double average;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scale = (value > average ? value : average) * 1.25;
    double fraction(double v) => scale <= 0 ? 0 : (v / scale).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: PhoneText.label),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhoneText.number(14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GrowTrack(fraction: fraction(value), marker: fraction(average)),
      ],
    );
  }
}

// ── Daily activity ──────────────────────────────────────────────────────

/// Daily revenue bars (bucketed weekly / monthly for long ranges); the
/// tooltip carries the bucket's follow-up count.
class DailyActivityChart extends StatelessWidget {
  const DailyActivityChart({
    super.key,
    required this.revenue,
    required this.followUps,
    required this.weekly,
  });

  final List<DayTotal> revenue;
  final List<DayTotal> followUps;

  /// A one-week range: label bars by weekday instead of date.
  final bool weekly;

  @override
  Widget build(BuildContext context) {
    if (revenue.isEmpty) return const SizedBox.shrink();

    final unit = bucketUnitFor(revenue.length);
    final revenuePoints = bucketDaily(revenue, unit: unit);
    final followUpCounts = {
      for (final p in bucketDaily(followUps, unit: unit)) p.x: p.count,
    };
    final daily = unit == BucketUnit.day;

    final bars = [
      for (final p in revenuePoints)
        () {
          final day = p.x!;
          final count = followUpCounts[p.x] ?? 0;
          return ChartBar(
            label: !daily
                ? p.label!
                : weekly
                ? DateFormat('E').format(day)
                : '${day.day}',
            tooltipLabel: daily
                ? DateFormat('EEE, d MMM').format(day)
                : p.label,
            value: p.y,
            detail: count > 0
                ? '$count ${count == 1 ? 'follow-up' : 'follow-ups'}'
                : null,
          );
        }(),
    ];

    return PhoneCard(child: GrowBarChart(height: 150, bars: bars));
  }
}

// ── Activity timeline ───────────────────────────────────────────────────

Color priorityInk(String label) => switch (label.trim().toLowerCase()) {
  'high' => AppColors.danger,
  'medium' => AppColors.yellowText,
  _ => AppColors.textSecondary,
};

Color priorityFill(String label) => switch (label.trim().toLowerCase()) {
  'high' => AppColors.dangerSoft,
  'medium' => AppColors.yellowSoft,
  _ => AppColors.surfaceSunken,
};

class PriorityTag extends StatelessWidget {
  const PriorityTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: priorityFill(label),
      borderRadius: BorderRadius.circular(AppRadius.full),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: PhoneText.number(
        11,
        weight: FontWeight.w700,
        color: priorityInk(label),
      ),
    ),
  );
}

String dayHeader(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final diff = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE, d MMM').format(d);
}

class ActivityTimeline extends StatefulWidget {
  const ActivityTimeline({
    super.key,
    required this.entries,
    this.initialLimit = 15,
    this.now,
  });

  final List<ActivityEntry> entries;
  final int initialLimit;
  final DateTime? now;

  @override
  State<ActivityTimeline> createState() => _ActivityTimelineState();
}

class _ActivityTimelineState extends State<ActivityTimeline> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final all = widget.entries;
    final shown = _expanded ? all : all.take(widget.initialLimit).toList();

    final children = <Widget>[];
    DateTime? currentDay;
    for (final entry in shown) {
      final day = DateTime(entry.at.year, entry.at.month, entry.at.day);
      if (currentDay != day) {
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: currentDay == null ? 0 : 16,
              bottom: 8,
            ),
            child: Text(dayHeader(day, now), style: PhoneText.label),
          ),
        );
        currentDay = day;
      } else {
        children.add(const SizedBox(height: 14));
      }
      children.add(_ActivityRow(entry: entry));
    }

    return PhoneCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...children,
          if (!_expanded && all.length > widget.initialLimit) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = true),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Show all (${all.length})'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color ink, Color fill) = switch (entry.kind) {
      ActivityKind.sale => (
        Icons.currency_rupee,
        AppColors.success,
        AppColors.successSoft,
      ),
      ActivityKind.followUp => (
        Icons.chat_bubble_outline,
        AppColors.info,
        AppColors.infoSoft,
      ),
      ActivityKind.newClient => (
        Icons.person_add_alt,
        AppColors.chatText,
        AppColors.chatSoft,
      ),
    };
    final detail =
        entry.detail ??
        (entry.kind == ActivityKind.newClient ? 'New client' : null);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.clientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhoneText.rowTitle,
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PhoneText.muted,
                ),
              ],
              if (entry.priority != null && entry.priority!.isNotEmpty) ...[
                const SizedBox(height: 6),
                PriorityTag(entry.priority!),
              ],
            ],
          ),
        ),
        if (entry.amountPaise != null) ...[
          const SizedBox(width: 12),
          Text(fullMoney(entry.amountPaise!), style: PhoneText.number(15)),
        ],
      ],
    );
  }
}

// ── Upcoming follow-ups ─────────────────────────────────────────────────

class UpcomingFollowUps extends StatelessWidget {
  const UpcomingFollowUps({super.key, required this.items});

  final List<Interaction> items;

  static String _when(Interaction i) {
    final day = DateTime.tryParse(i.followUpDate);
    final date = day == null
        ? i.followUpDate
        : DateFormat('EEE, d MMM').format(day);
    final time = i.followUpTime.length >= 5
        ? i.followUpTime.substring(0, 5)
        : '';
    final parsed = time.isEmpty ? null : DateFormat('HH:mm').tryParse(time);
    final clock = parsed == null ? '' : DateFormat('h:mm a').format(parsed);
    return clock.isEmpty ? date : '$date · $clock';
  }

  @override
  Widget build(BuildContext context) {
    return PhoneCard(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhoneText.rowTitle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _when(items[i]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhoneText.muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                PriorityTag(
                  items[i].priorityDisplay?.isNotEmpty == true
                      ? items[i].priorityDisplay!
                      : items[i].priority,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
