import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/status_badge.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_service.dart';
import 'attendance_widgets.dart';
import 'dashboard_ring.dart';

/// This month's attendance at a glance. [employeeId] null shows the
/// signed-in person; an admin passes the person being viewed.
///
/// The card owns its loading and failure states, so a failed call shows a
/// retry inside the card and never touches the screen that hosts it.
class AttendanceSummaryCard extends ConsumerWidget {
  const AttendanceSummaryCard({
    super.key,
    this.employeeId,
    this.onOpenAttendance,
  });

  final String? employeeId;

  /// Own profile: tapping the pill opens the Attendance screen. Null (the
  /// employee detail an admin sees) leaves the pill display-only. Nothing is
  /// ever marked from this card.
  final VoidCallback? onOpenAttendance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final key = (employeeId: employeeId, month: monthKeyOf(now));
    final value = ref.watch(attendanceMonthProvider(key));

    return AttendancePanel(
      title: 'Attendance - ${attendanceMonthLabel(now)}',
      icon: Icons.fingerprint,
      leading: AttendancePillBadge(onTap: onOpenAttendance),
      child: value.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(attendanceErrorMessage(e), style: AppTypography.caption),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(attendanceMonthProvider(key)),
              icon: const Icon(Icons.refresh, size: AppSizing.iconSm),
              label: const Text('Retry'),
            ),
          ],
        ),
        data: (data) => _Summary(summary: data.summary),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s.workingDays == 0) {
      return Text(
        s.isRated
            ? 'No working days counted yet this month.'
            : 'Not rated yet. No working days have been counted this month.',
        style: AppTypography.bodySecondary,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${s.present} of ${s.workingDays} working days present',
          style: AppTypography.itemTitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          children: [
            _fact(
              'Attendance',
              s.percent == null ? 'Not rated yet' : '${s.percent}%',
            ),
            _fact(
              'Rating',
              s.stars == null
                  ? 'Not rated yet'
                  : '${_stars(s.stars!)} ${s.stars!.toStringAsFixed(1)}',
            ),
            _fact(
              'Rank',
              s.rank == null || s.rankedOf == null
                  ? 'Not ranked'
                  : '#${s.rank} of ${s.rankedOf}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            StatusBadge.followUp(label: 'Late ${s.late}'),
            StatusBadge.followUp(label: 'Early ${s.early}'),
            StatusBadge.overdue(label: 'Absent ${s.absent}'),
            if (s.pending > 0)
              StatusBadge.fresh(label: '${s.pending} awaiting review'),
          ],
        ),
      ],
    );
  }

  Widget _fact(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: AppTypography.caption),
      Text(value, style: AppTypography.itemTitle),
    ],
  );

  /// Five stars, filled to the nearest whole star.
  static String _stars(double v) {
    final n = v.round().clamp(0, 5);
    return '${'★' * n}${'☆' * (5 - n)}';
  }
}
