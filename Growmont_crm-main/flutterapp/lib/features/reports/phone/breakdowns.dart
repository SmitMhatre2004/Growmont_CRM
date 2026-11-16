// lib/features/reports/phone/breakdowns.dart
//
// Revenue breakdown blocks for the phone Reports: ranked bars (products),
// the payment-frequency split, and the follow-up counts, all drawn with the
// shared chart kit. Labels, amounts and shares only; no captions.

import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/charts/charts.dart';
import '../widgets/report_chart_theme.dart';

import 'phone_style.dart';

String _share(double fraction) {
  final p = fraction * 100;
  return p > 0 && p < 1 ? '<1%' : '${p.round()}%';
}

/// Top [limit] rows by revenue, the remainder folded into "Others".
List<CategoryTotal> topWithOthers(List<CategoryTotal> rows, int limit) {
  final present = rows.where((r) => r.paise > 0).toList();
  if (present.length <= limit) return present;
  final head = present.take(limit).toList();
  final tail = present.skip(limit);
  return [
    ...head,
    CategoryTotal(
      label: 'Others',
      paise: tail.fold<int>(0, (s, r) => s + r.paise),
      count: tail.fold<int>(0, (s, r) => s + r.count),
    ),
  ];
}

/// Horizontal bars on one baseline: label left, amount and share right.
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.rows, this.limit = 6});

  final List<CategoryTotal> rows;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final all = rows.where((r) => r.paise > 0).toList();
    final total = all.fold<int>(0, (s, r) => s + r.paise);
    final visible = topWithOthers(rows, limit);

    return PhoneCard(
      child: GrowRankedBars(
        items: [
          for (var i = 0; i < visible.length; i++)
            RankedItem(
              label: visible[i].label,
              value: visible[i].paise.toDouble(),
              valueText: compactMoney(visible[i].paise),
              shareText: _share(total == 0 ? 0 : visible[i].paise / total),
              color: visible[i].label == 'Others' && i == limit
                  ? ReportChart.context
                  : null,
            ),
        ],
      ),
    );
  }
}

/// Payment frequency: the segmented bar, then one legend row per part.
class FrequencyBreakdown extends StatelessWidget {
  const FrequencyBreakdown({super.key, required this.rows});

  final List<CategoryTotal> rows;

  @override
  Widget build(BuildContext context) {
    final present = rows.where((r) => r.paise > 0).toList();
    final segments = [
      for (var i = 0; i < present.length; i++)
        ChartSegment(
          label: present[i].label,
          value: present[i].paise.toDouble(),
          color: kOrdinalRamp[i % kOrdinalRamp.length],
          valueText: compactMoney(present[i].paise),
        ),
    ];

    return PhoneCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GrowSegmentBar(segments: segments),
          const SizedBox(height: 14),
          GrowSegmentLegend(segments: segments),
        ],
      ),
    );
  }
}

/// Follow-ups: Logged / Overdue / Upcoming counts, then the priority split.
class FollowUpsCard extends StatelessWidget {
  const FollowUpsCard({
    super.key,
    required this.logged,
    required this.overdue,
    required this.upcoming,
    required this.byPriority,
  });

  final int logged;
  final int overdue;
  final int upcoming;

  /// Counts per priority, in High, Medium, Low order.
  final List<CategoryTotal> byPriority;

  static const _priorityColours = [
    AppColors.danger,
    AppColors.yellow,
    AppPalette.slate400,
  ];

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: PhoneText.muted),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: PhoneText.number(22, color: color ?? AppColors.textPrimary),
          ),
        ],
      ),
    );

    final present = <(CategoryTotal, Color)>[
      for (var i = 0; i < byPriority.length; i++)
        if (byPriority[i].count > 0)
          (byPriority[i], _priorityColours[i % _priorityColours.length]),
    ];

    return PhoneCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stat('Logged', logged),
              stat(
                'Overdue',
                overdue,
                color: overdue > 0 ? AppColors.danger : null,
              ),
              stat('Upcoming', upcoming),
            ],
          ),
          if (present.isNotEmpty) ...[
            const SizedBox(height: 16),
            GrowSegmentBar(
              height: 8,
              segments: [
                for (final p in present)
                  ChartSegment(
                    label: p.$1.label,
                    value: p.$1.count.toDouble(),
                    color: p.$2,
                    valueText: '${p.$1.count}',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final p in present)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: p.$2,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(p.$1.label, style: PhoneText.muted),
                      const SizedBox(width: 4),
                      Text(
                        '${p.$1.count}',
                        style: PhoneText.number(
                          13,
                          weight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
