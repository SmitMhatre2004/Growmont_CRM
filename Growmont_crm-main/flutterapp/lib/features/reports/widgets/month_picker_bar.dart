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

/// Opens the month-and-year grid. Null when dismissed.
Future<ReportMonth?> pickReportMonth(
  BuildContext context, {
  required ReportMonth month,
  required ReportMonth latest,
}) {
  return showDialog<ReportMonth>(
    context: context,
    builder: (context) => _MonthYearDialog(month: month, latest: latest),
  );
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
