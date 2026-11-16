// lib/features/reports/phone/period_bar.dart
//
// The period controls shared by the Reports screen and the employee report.
//
// Month mode (default):  <  November 2026 v  >   [date-range button]
// Custom range:          [ 1 Oct - 15 Nov 2026  x ]   (x returns to the
//                        current month)

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/month_picker_bar.dart' show pickReportMonth;
import 'period_selection.dart';
import 'phone_style.dart';

/// Test seam: replaces the system date-range dialog. Null in production.
@visibleForTesting
Future<DateTimeRange?> Function(
  BuildContext context,
  DateTimeRange? initial,
  DateTime today,
)?
debugDateRangePicker;

/// Asks for a custom range with the platform picker, themed in the app's
/// colours. Resolves to the new selection, or null if dismissed.
Future<ReportPeriodSelection?> pickReportDateRange(
  BuildContext context,
  ReportPeriodSelection current,
) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final r = current.range;
  final lastDay = DateTime(
    r.endExclusive.year,
    r.endExclusive.month,
    r.endExclusive.day - 1,
  );
  final initial = DateTimeRange(
    start: r.start.isAfter(today) ? today : r.start,
    end: lastDay.isAfter(today) ? today : lastDay,
  );

  final DateTimeRange? picked;
  final hook = debugDateRangePicker;
  if (hook != null) {
    picked = await hook(context, initial, today);
  } else {
    picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: initial,
      saveText: 'Apply',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primaryBlue,
            onPrimary: Colors.white,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
  }
  if (picked == null) return null;
  return ReportPeriodSelection.customCapped(
    picked.start,
    picked.end,
    latestMonth: current.latestMonth,
    today: today,
  );
}

class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.selection,
    required this.onChanged,
    this.rangeAlignment = Alignment.center,
  });

  final ReportPeriodSelection selection;
  final ValueChanged<ReportPeriodSelection> onChanged;

  /// Where the custom-range pill sits in the width it is given.
  final Alignment rangeAlignment;

  Future<void> _pickRange(BuildContext context) async {
    final picked = await pickReportDateRange(context, selection);
    if (picked != null && picked != selection) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return selection.isMonth
        ? _MonthRow(
            selection: selection,
            onChanged: onChanged,
            onCustom: () => _pickRange(context),
          )
        : _RangePill(
            selection: selection,
            onTap: () => _pickRange(context),
            alignment: rangeAlignment,
            onClear: () => onChanged(selection.toCurrentMonth()),
          );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.selection,
    required this.onChanged,
    required this.onCustom,
  });

  final ReportPeriodSelection selection;
  final ValueChanged<ReportPeriodSelection> onChanged;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final canGoNext = selection.canGoNext;

    Widget arrow(IconData icon, String tooltip, VoidCallback? onPressed) {
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

    return Row(
      children: [
        arrow(
          Icons.chevron_left,
          'Previous month',
          () => onChanged(selection.previous()),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () async {
              final picked = await pickReportMonth(
                context,
                month: selection.month,
                latest: selection.latestMonth,
              );
              if (picked != null && picked != selection.month) {
                onChanged(selection.withMonth(picked));
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      selection.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: PhoneText.rowTitle,
                    ),
                  ),
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
        arrow(
          Icons.chevron_right,
          canGoNext ? 'Next month' : 'No later month to report on',
          canGoNext ? () => onChanged(selection.next()) : null,
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Custom range',
          child: SizedBox(
            width: 40,
            height: 40,
            child: OutlinedButton(
              onPressed: onCustom,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Icon(Icons.date_range, size: AppSizing.iconMd),
            ),
          ),
        ),
      ],
    );
  }
}

class _RangePill extends StatelessWidget {
  const _RangePill({
    required this.selection,
    required this.onTap,
    required this.onClear,
    this.alignment = Alignment.center,
  });

  final ReportPeriodSelection selection;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.full),
                ),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.date_range,
                        size: AppSizing.iconMd,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          selection.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PhoneText.rowTitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Back to current month',
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(AppRadius.full),
                ),
                onTap: onClear,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.close,
                    size: AppSizing.iconSm,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
