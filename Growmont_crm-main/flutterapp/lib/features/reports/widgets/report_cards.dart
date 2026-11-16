// lib/features/reports/widgets/report_cards.dart
//
// The card shell and KPI tile the Monthly Report is built from. Both
// alias the shared design tokens only, so this screen can never drift
// from the rest of the app.

import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';

/// A titled white panel. Same border, radius and shadow as the dashboard's
/// chart cards and the Sales screen's metric boxes.
class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.sectionTitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(subtitle!, style: AppTypography.caption),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}

/// The "+12.4% vs May" chip under a KPI value.
class DeltaChip extends StatelessWidget {
  const DeltaChip({
    super.key,
    required this.delta,
    required this.previousLabel,
  });

  final MetricDelta delta;

  /// Name of the month being compared against, e.g. "May 2025".
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final percent = delta.percentChange;

    // No baseline: say so instead of implying an infinite rise. This is
    // the common case for a brand-new deployment's first month.
    if (percent == null) {
      final text = delta.current == 0
          ? 'No activity in $previousLabel'
          : 'New vs $previousLabel';
      return _chip(
        text: text,
        icon: null,
        ink: AppColors.textCaption,
        fill: AppColors.surfaceSunken,
      );
    }

    // Every metric the report shows is one where more is better, so a
    // rise is green and a fall is red. If a "lower is better" measure is
    // ever added here, it needs its own direction flag rather than
    // inheriting this one.
    final isFlat = delta.isFlat;
    final (Color ink, Color fill) = isFlat
        ? (AppColors.textSecondary, AppColors.surfaceSunken)
        : delta.isUp
            ? (AppColors.success, AppColors.successSoft)
            : (AppColors.danger, AppColors.dangerSoft);

    final magnitude = percent.abs();
    // A near-zero but non-zero move would read as "0.0%", which looks like
    // a bug next to an up arrow.
    final formatted = magnitude >= 100
        ? magnitude.toStringAsFixed(0)
        : magnitude < 0.1 && magnitude > 0
            ? '<0.1'
            : magnitude.toStringAsFixed(1);

    return _chip(
      text: isFlat
          ? 'Flat vs $previousLabel'
          : '${delta.isUp ? '+' : '−'}$formatted% vs $previousLabel',
      icon: isFlat
          ? Icons.remove
          : delta.isUp
              ? Icons.arrow_upward
              : Icons.arrow_downward,
      ink: ink,
      fill: fill,
    );
  }

  Widget _chip({
    required String text,
    required IconData? icon,
    required Color ink,
    required Color fill,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSizing.iconXs, color: ink),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// One headline metric: label, value, and its move against last month.
///
/// Mirrors the Sales screen's metric box so the two read as one family;
/// the delta chip and the optional [note] are what this one adds.
class ReportKpiCard extends StatelessWidget {
  const ReportKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.previousLabel = '',
    this.valueColor,
  });

  final String label;
  final String value;
  final MetricDelta? delta;
  final String previousLabel;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.metricLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.metricLarge.copyWith(color: valueColor),
              maxLines: 1,
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: DeltaChip(
                delta: delta!,
                previousLabel: previousLabel,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
