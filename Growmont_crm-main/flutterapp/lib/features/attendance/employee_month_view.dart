import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_provider.dart';
import 'attendance_calendar.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_widgets.dart';
import 'team_tab.dart';

/// Admin only: one employee's month calendar, where an admin can change, add
/// or remove the timings of any past day or today. Renders nothing for a
/// non-admin, so it is safe to place anywhere.
class EmployeeMonthView extends ConsumerStatefulWidget {
  const EmployeeMonthView({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  final String employeeId;
  final String employeeName;

  @override
  ConsumerState<EmployeeMonthView> createState() => _EmployeeMonthViewState();
}

class _EmployeeMonthViewState extends ConsumerState<EmployeeMonthView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  MonthKey get _key =>
      (employeeId: widget.employeeId, month: monthKeyOf(_month));

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProvider).user?.isAdmin != true) {
      return const SizedBox.shrink();
    }
    final month = ref.watch(attendanceMonthProvider(_key));
    return AttendancePanel(
      title: '${widget.employeeName} - month',
      icon: Icons.calendar_month_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AttendanceMonthStepper(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
          AttendanceAsync<MonthData>(
            value: month,
            onRetry: () => ref.invalidate(attendanceMonthProvider(_key)),
            isEmpty: (d) => d.days.isEmpty,
            emptyTitle: 'No days to show',
            emptyMessage: 'Nothing is counted for this month yet.',
            emptyIcon: Icons.event_busy_outlined,
            builder: _body,
          ),
        ],
      ),
    );
  }

  Widget _body(MonthData d) {
    final todayKey = dateKeyOf(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AttendanceSummaryStrip(data: d),
        const SizedBox(height: AppSpacing.md),
        AttendanceCalendar(
          month: _month,
          data: d,
          today: todayKey,
          onDayTap: (day) => showDayDetailSheet(
            context,
            day: day,
            today: todayKey,
            onWriteNote: null, // notes are the employee's own to write
            onEditTimes: () => showAdminTimingEditor(
              context,
              ref,
              row: TeamRow(
                employeeId: widget.employeeId,
                name: widget.employeeName,
                status: day.status,
                record: day.record,
              ),
              date: day.date,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AttendanceCalendarLegend(),
      ],
    );
  }
}

/// Full-screen wrapper opened from the Team tab. Guards itself: a non-admin
/// sees a plain "admins only" message and nothing is loaded.
class EmployeeMonthScreen extends ConsumerWidget {
  const EmployeeMonthScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  final String employeeId;
  final String employeeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;
    return Scaffold(
      appBar: AppBar(title: Text(employeeName)),
      body: !isAdmin
          ? const Center(child: Text('Only admins can view this.'))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                EmployeeMonthView(
                  employeeId: employeeId,
                  employeeName: employeeName,
                ),
              ],
            ),
    );
  }
}
