// lib/features/reports/widgets/report_tables.dart
//
// The month-by-month history table, and the rupee formatter it shares with
// the rest of the Reports screens.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';

/// Rupee text for a paise amount, in full Indian-grouped form.
String rupeesFromPaise(int paise) =>
    AppFormatters.formatAmount((paise / 100).toStringAsFixed(2));

/// Wraps a row so it highlights under the pointer and opens on a tap.
/// Kept separate so the row builders stay layout-only.
class _Tappable extends StatefulWidget {
  const _Tappable({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// One person's month-by-month history: a row per month, newest first.
///
/// Shown on an individual report — an employee's own, or the one an admin
/// opens from the team table. The company view leaves it out: the daily
/// trend already carries the shape there, and a second time series would
/// be the kind of duplication the page was trimmed of.
///
/// Newest first because the question being asked is "how have I been
/// doing lately", which is answered at the top of the list rather than
/// after scrolling a year.
///
/// The bar is a magnitude cue against the best month in the window, not a
/// share of anything — months are not parts of a whole.
class MonthlyHistoryTable extends StatelessWidget {
  const MonthlyHistoryTable({
    super.key,
    required this.months,
    required this.selected,
    this.onMonthTap,
  });

  /// Trailing months, oldest first as the report produces them.
  final List<MonthTotal> months;

  /// The month the report is currently about.
  final ReportMonth selected;

  final ValueChanged<ReportMonth>? onMonthTap;

  @override
  Widget build(BuildContext context) {
    final rows = months.reversed.toList();
    final peak = rows.fold<int>(
      0,
      (best, m) => m.paise > best ? m.paise : best,
    );

    if (peak == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          'No revenue recorded in the last ${rows.length} months',
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _MonthRow(
            row: rows[i],
            fraction: rows[i].paise / peak,
            isSelected: rows[i].month == selected,
            onTap: onMonthTap == null ? null : () => onMonthTap!(rows[i].month),
          ),
        ],
      ],
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.row,
    required this.fraction,
    required this.isSelected,
    this.onTap,
  });

  final MonthTotal row;
  final double fraction;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMM yyyy').format(row.month.start);

    return _Tappable(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: isSelected
                  ? AppTypography.tableCellStrong.copyWith(
                      color: AppColors.primaryBlue,
                    )
                  : AppTypography.tableCell,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${row.count}',
              style: AppTypography.tableCellNumeric.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 10,
                child: Stack(
                  children: [
                    Container(color: AppColors.surfaceSunken),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: Container(
                        color: isSelected
                            ? AppColors.primaryBlue
                            : AppPalette.navy300,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 96,
            child: Text(
              row.paise == 0 ? '—' : rupeesFromPaise(row.paise),
              style: AppTypography.tableCellNumeric.copyWith(
                color: row.paise == 0
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
