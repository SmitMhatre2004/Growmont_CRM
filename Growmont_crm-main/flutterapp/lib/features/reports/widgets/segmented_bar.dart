// lib/features/reports/widgets/segmented_bar.dart
//
// One whole, split into parts: a thin segmented bar above a list that
// names each part and gives its figures.
//
// ── Why this is not another ranked bar chart ──────────────────────────────
//
// Ranked bars answer "compare these categories with each other". Payment
// frequency asks something else: how does ONE month's revenue divide up?
// The parts are also an ordered scale — Monthly, Quarterly, Half Yearly,
// Yearly, One Time — not an identity set, so they take an ordinal ramp
// (one hue, light to dark, in scale order) rather than a flat accent.
//
// The thin variant is the right one here rather than the tall one,
// because the figures are listed underneath: the spec's rule is that a
// bar sitting above a list which already carries each part's name and
// amount prints no text of its own, and a swatch on each list row
// replaces the legend. Printing shares on the bar as well would be a
// number on every mark.
//
// ── The ramp was validated ────────────────────────────────────────────────
//
//   #86A7DA,#4F7DC3,#2458A8,#00337C,#001C4A  --ordinal  → all PASS
//     (monotone lightness, adjacent ΔL ≥ 0.06, light end clears the
//      surface at 2.39:1, single hue)
//
// Two earlier attempts failed and are recorded so they are not retried:
// starting at navy200 #B8CCEB failed the light-end contrast floor
// (1.59:1), and a navy600/navy700 pair failed the adjacent-step gap
// (ΔL 0.06 exactly at the boundary).

import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import 'report_chart_theme.dart';
import 'report_tables.dart' show rupeesFromPaise;

/// The validated ordinal ramp, light to dark, in scale order.
const List<Color> kOrdinalRamp = [
  AppPalette.navy300,
  AppPalette.navy400,
  AppPalette.navy500,
  AppPalette.navy700,
  AppPalette.navy900,
];

class SegmentedBarList extends StatelessWidget {
  const SegmentedBarList({
    super.key,
    required this.rows,
    this.emptyMessage = 'Nothing to break down for this month',
    this.animate = true,
  });

  /// Parts in their natural scale order — NOT re-sorted by size. The
  /// order is the point: an ordered scale read out of order is just a
  /// ranked list with a confusing palette.
  final List<CategoryTotal> rows;

  final String emptyMessage;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final present = rows.where((r) => r.paise > 0).toList();

    if (present.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          emptyMessage,
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    final total = present.fold<int>(0, (sum, r) => sum + r.paise);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Bar(parts: present, total: total, animate: animate),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < present.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _ListRow(
            row: present[i],
            colour: kOrdinalRamp[i % kOrdinalRamp.length],
            share: total == 0 ? 0 : present[i].paise / total,
          ),
        ],
      ],
    );
  }
}

/// The bar itself: 8px, fully rounded ends, no baseline and so no square
/// end, widths proportional, a 2px surface gap between parts. No text —
/// the list below carries every figure.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.parts,
    required this.total,
    required this.animate,
  });

  final List<CategoryTotal> parts;
  final int total;
  final bool animate;

  static const double _height = 10;

  @override
  Widget build(BuildContext context) {
    Widget build(double t) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_height / 2),
        child: SizedBox(
          height: _height,
          child: Row(
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0)
                  const SizedBox(width: ReportChart.surfaceGap),
                Expanded(
                  // A part at zero is filtered out before this point, so
                  // every flex here is a real, non-zero share.
                  flex: (parts[i].paise * 1000 ~/ (total == 0 ? 1 : total))
                      .clamp(1, 1000),
                  child: Container(
                    color: kOrdinalRamp[i % kOrdinalRamp.length],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!animate) return build(1);

    // The bar wipes in from the left rather than each part growing on its
    // own, so the proportions are never briefly wrong on the way in.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.slow,
      curve: AppMotion.curve,
      builder: (context, t, child) => Align(
        alignment: Alignment.centerLeft,
        widthFactor: t.clamp(0.01, 1.0),
        child: child,
      ),
      child: build(1),
    );
  }
}

/// One list row: swatch, name, amount, share. The swatch is what ties the
/// row to its block, which is why this list needs no separate legend.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.row,
    required this.colour,
    required this.share,
  });

  final CategoryTotal row;
  final Color colour;
  final double share;

  @override
  Widget build(BuildContext context) {
    final sharePercent = share >= 0.1 || share == 0
        ? '${(share * 100).round()}%'
        : '${(share * 100).toStringAsFixed(1)}%';

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            row.label,
            style: AppTypography.tableCell,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          rupeesFromPaise(row.paise),
          style: AppTypography.tableCellNumeric.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 38,
          child: Text(
            sharePercent,
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// A small row of counts — label over value — for a handful of headline
/// numbers that are not worth a chart.
///
/// Interaction priority is three counts on an ordered scale. A chart of
/// three bars is the "one-bar bar chart" failure with two extra bars: the
/// numbers ARE the content, so they are set as figures and the ordinal
/// ramp carries the ordering through a rule under each one.
class MiniStatRow extends StatelessWidget {
  const MiniStatRow({
    super.key,
    required this.rows,
    this.emptyMessage = 'Nothing logged this month',
  });

  final List<CategoryTotal> rows;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          emptyMessage,
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rows[i].label.toUpperCase(),
                  style: AppTypography.metricLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${rows[i].count}',
                  style: AppTypography.metricMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                // A 3px rule in the step for this position: it carries the
                // High -> Low ordering without colouring the number itself.
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: rows[i].count == 0
                        ? AppColors.border
                        : kOrdinalRamp[i % kOrdinalRamp.length],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
