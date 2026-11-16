// lib/features/reports/phone/team_tab.dart
//
// The admin's Team tab: sort chips, an "Active n of m" strip and one card of
// employee rows. Tapping a row opens that person's report.

import 'package:flutter/material.dart';

import '../../../core/reports/period_summary_builder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/monogram.dart';
import 'overview_sections.dart' show dealsText;
import 'phone_style.dart';

enum TeamSort {
  revenue('Revenue'),
  deals('Deals'),
  followUps('Follow-ups'),
  newClients('New clients');

  const TeamSort(this.label);
  final String label;

  int metric(EmployeePeriodRow r) => switch (this) {
    TeamSort.revenue => r.revenuePaise,
    TeamSort.deals => r.dealCount,
    TeamSort.followUps => r.interactionCount,
    TeamSort.newClients => r.newClientCount,
  };
}

/// Active people first by [sort] (revenue, then name, as tie-breaks), idle
/// people after them in their incoming order.
List<EmployeePeriodRow> sortTeam(List<EmployeePeriodRow> rows, TeamSort sort) {
  final active = rows.where((r) => !r.isIdle).toList()
    ..sort((a, b) {
      final byMetric = sort.metric(b).compareTo(sort.metric(a));
      if (byMetric != 0) return byMetric;
      final byRevenue = b.revenuePaise.compareTo(a.revenuePaise);
      return byRevenue != 0 ? byRevenue : a.name.compareTo(b.name);
    });
  return [...active, ...rows.where((r) => r.isIdle)];
}

class TeamTab extends StatelessWidget {
  const TeamTab({
    super.key,
    required this.rows,
    required this.sort,
    required this.onSortChanged,
    required this.onEmployeeTap,
  });

  final List<EmployeePeriodRow> rows;
  final TeamSort sort;
  final ValueChanged<TeamSort> onSortChanged;
  final ValueChanged<EmployeePeriodRow> onEmployeeTap;

  @override
  Widget build(BuildContext context) {
    final sorted = sortTeam(rows, sort);
    final activeCount = rows.where((r) => !r.isIdle).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in TeamSort.values) ...[
                if (s != TeamSort.values.first) const SizedBox(width: 8),
                _SortChip(
                  label: s.label,
                  selected: s == sort,
                  onTap: () => onSortChanged(s),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Active $activeCount of ${rows.length}', style: PhoneText.label),
        const SizedBox(height: 12),
        PhoneCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.divider),
                _TeamRow(
                  row: sorted[i],
                  position: i + 1,
                  onTap: () => onEmployeeTap(sorted[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBlue : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: PhoneText.label.copyWith(
              color: selected ? AppColors.textOnDark : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.row,
    required this.position,
    required this.onTap,
  });

  final EmployeePeriodRow row;
  final int position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idle = row.isIdle;
    final delta = row.revenueDelta;
    final percent = delta.percentChange;
    final Color deltaColor = percent == null || delta.isFlat
        ? AppColors.textMuted
        : delta.isUp
        ? AppColors.success
        : AppColors.danger;
    // No baseline: no change line at all.
    final deltaText = percent == null
        ? null
        : delta.isFlat
        ? '0%'
        : '${delta.isUp ? '+' : '−'}${percentText(percent)}%';
    final parts = [
      if (row.dealCount > 0) dealsText(row.dealCount),
      if (row.newClientCount > 0)
        row.newClientCount == 1
            ? '1 new client'
            : '${row.newClientCount} new clients',
      if (row.interactionCount > 0)
        row.interactionCount == 1
            ? '1 follow-up'
            : '${row.interactionCount} follow-ups',
    ];

    return Opacity(
      opacity: idle ? 0.55 : 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  idle ? '–' : '$position',
                  style: PhoneText.number(
                    14,
                    weight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Monogram(name: row.name, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhoneText.rowTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parts.isEmpty ? 'No activity' : parts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PhoneText.muted,
                    ),
                  ],
                ),
              ),
              if (!idle) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      compactMoney(row.revenuePaise),
                      style: PhoneText.number(15),
                    ),
                    if (deltaText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        deltaText,
                        style: PhoneText.number(
                          12,
                          weight: FontWeight.w600,
                          color: deltaColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
