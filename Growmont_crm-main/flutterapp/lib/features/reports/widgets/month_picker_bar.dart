// lib/features/reports/widgets/month_picker_bar.dart
//
// The reporting-period selector: previous/next arrows around the month
// name, plus a month-and-year grid for jumping further back.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';

/// Formats a period the way every heading, chip and export in the report
/// spells it, so the month name is written once.
String formatReportMonth(ReportMonth month, {bool short = false}) {
  return DateFormat(short ? 'MMM yyyy' : 'MMMM yyyy').format(month.start);
}

/// Previous / current / next control for the selected [month].
///
/// [latest] caps forward travel — there is nothing to report on a month
/// that has not started, and letting the user walk into empty future
/// months just looks broken.
class MonthPickerBar extends StatelessWidget {
  const MonthPickerBar({
    super.key,
    required this.month,
    required this.latest,
    required this.onChanged,
  });

  final ReportMonth month;
  final ReportMonth latest;
  final ValueChanged<ReportMonth> onChanged;

  bool get _canGoForward => month.compareTo(latest) < 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(
            icon: Icons.chevron_left,
            tooltip: 'Previous month',
            onPressed: () => onChanged(month.previous),
          ),
          // Fixed width so the row does not jump as the month name's
          // length changes between, say, May and September.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 132),
            child: InkWell(
              onTap: () => _pick(context),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      formatReportMonth(month),
                      style: AppTypography.tableCellStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: AppSizing.iconLg,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _arrow(
            icon: Icons.chevron_right,
            tooltip: _canGoForward ? 'Next month' : 'No later month to report on',
            onPressed: _canGoForward ? () => onChanged(month.next) : null,
          ),
        ],
      ),
    );
  }

  Widget _arrow({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: AppSizing.iconLg),
        color: AppColors.textSecondary,
        disabledColor: AppColors.textMuted,
        visualDensity: VisualDensity.compact,
        splashRadius: AppSizing.iconXl,
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<ReportMonth>(
      context: context,
      builder: (context) => _MonthYearDialog(month: month, latest: latest),
    );
    if (picked != null && picked != month) onChanged(picked);
  }
}

/// Year stepper over a 12-month grid. A full date picker would be the
/// wrong control here — the day never matters, and a calendar invites the
/// user to pick one.
class _MonthYearDialog extends StatefulWidget {
  const _MonthYearDialog({required this.month, required this.latest});

  final ReportMonth month;
  final ReportMonth latest;

  @override
  State<_MonthYearDialog> createState() => _MonthYearDialogState();
}

class _MonthYearDialogState extends State<_MonthYearDialog> {
  late int _year = widget.month.year;

  /// Ten years of history is well past the life of this deployment and
  /// keeps the stepper from wandering somewhere with no data at all.
  int get _earliestYear => widget.latest.year - 10;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: AppLayout.modalInset(context),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      title: const Text('Reporting period'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _year > _earliestYear
                      ? () => setState(() => _year--)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  color: AppColors.textSecondary,
                ),
                Text('$_year', style: AppTypography.sectionTitle),
                IconButton(
                  onPressed: _year < widget.latest.year
                      ? () => setState(() => _year++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 2.2,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var m = 1; m <= 12; m++) _monthTile(ReportMonth(_year, m)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, widget.latest),
          child: const Text('This month'),
        ),
      ],
    );
  }

  Widget _monthTile(ReportMonth candidate) {
    final isSelected = candidate == widget.month;
    final isFuture = candidate.compareTo(widget.latest) > 0;

    return Opacity(
      opacity: isFuture ? 0.4 : 1,
      child: Material(
        color: isSelected ? AppColors.surfaceSelected : AppColors.surfaceSunken,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brMd,
          side: BorderSide(
            color: isSelected ? AppColors.primaryBlue : AppColors.border,
          ),
        ),
        child: InkWell(
          onTap: isFuture ? null : () => Navigator.pop(context, candidate),
          borderRadius: AppRadius.brMd,
          child: Center(
            child: Text(
              DateFormat('MMM').format(candidate.start),
              style: AppTypography.tableCell.copyWith(
                color: isSelected
                    ? AppColors.primaryBlue
                    : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
