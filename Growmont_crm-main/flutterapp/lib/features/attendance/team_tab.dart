import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_form.dart';
import '../../shared/widgets/app_modal_shell.dart';
import '../../shared/widgets/inline_error_banner.dart';
import '../auth/auth_provider.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_service.dart';
import 'attendance_widgets.dart';
import 'employee_month_view.dart';

/// Admin: everyone's day, with tap-to-edit timings, and the month ranking.
class AttendanceTeamTab extends ConsumerStatefulWidget {
  const AttendanceTeamTab({super.key});

  @override
  ConsumerState<AttendanceTeamTab> createState() => _AttendanceTeamTabState();
}

class _AttendanceTeamTabState extends ConsumerState<AttendanceTeamTab> {
  DateTime _date = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _ranking = false;

  Future<void> _edit(TeamRow row, String date) =>
      showAdminTimingEditor(context, ref, row: row, date: date);

  void _openMonth(String id, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeMonthScreen(employeeId: id, employeeName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProvider).user?.isAdmin != true) {
      return const Center(child: Text('Only admins can view the team.'));
    }
    final isMobile = AppLayout.isMobile(context);
    final pad = isMobile ? AppSpacing.lg : AppSpacing.xxl;
    final dateKey = dateKeyOf(_date);

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, AppSpacing.xxl),
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('By day')),
            ButtonSegment(value: true, label: Text('Month ranking')),
          ],
          selected: {_ranking},
          onSelectionChanged: (s) => setState(() => _ranking = s.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!_ranking) ...[
          AppDateField(
            value: _date,
            lastDate: DateTime.now(),
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: AppSpacing.md),
          AttendanceAsync<TeamDay>(
            value: ref.watch(attendanceTeamDayProvider(dateKey)),
            onRetry: () => ref.invalidate(attendanceTeamDayProvider(dateKey)),
            isEmpty: (d) => d.rows.isEmpty,
            emptyTitle: 'No team members',
            emptyMessage: 'No active employees to show for this day.',
            emptyIcon: Icons.groups_outlined,
            builder: (d) => AttendancePanel(
              title: attendanceDateLabel(d.date, withYear: true),
              icon: Icons.groups_outlined,
              child: Column(
                children: [for (final r in d.rows) _dayRow(r, d.date)],
              ),
            ),
          ),
        ] else ...[
          AttendanceMonthStepper(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
          AttendanceAsync<List<TeamMonthRow>>(
            value: ref.watch(attendanceTeamMonthProvider(monthKeyOf(_month))),
            onRetry: () => ref.invalidate(attendanceTeamMonthProvider),
            isEmpty: (rows) => rows.isEmpty,
            emptyTitle: 'No ranking yet',
            emptyMessage: 'Nobody has counted working days this month.',
            emptyIcon: Icons.leaderboard_outlined,
            builder: (rows) => AttendancePanel(
              title: 'Ranking',
              icon: Icons.leaderboard_outlined,
              child: Column(children: [for (final r in rows) _rankRow(r)]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dayRow(TeamRow row, String date) {
    final r = row.record;
    final times = r == null || !r.hasCheckIn
        ? 'No check-in'
        : '${r.checkInLocal} - ${r.checkOutLocal ?? 'no check-out'}';
    return InkWell(
      onTap: () => _edit(row, date),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    style: AppTypography.bodyPrimary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(times, style: AppTypography.caption),
                  if (r != null && (r.isLate || r.isEarly))
                    Text(
                      [
                        if (r.isLate) reviewKindText('late', r.lateMinutes),
                        if (r.isEarly) reviewKindText('early', r.earlyMinutes),
                      ].join(' - '),
                      style: AppTypography.caption,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Fixed right-hand columns, so every row's status, pencil and
            // calendar line up whatever the status text length.
            SizedBox(
              width: 88,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: statusBadgeFor(row.status),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(
              Icons.edit_outlined,
              size: AppSizing.iconSm,
              color: AppColors.textMuted,
            ),
            IconButton(
              key: ValueKey('team-month-${row.employeeId}'),
              tooltip: 'View month',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              onPressed: () => _openMonth(row.employeeId, row.name),
              icon: const Icon(
                Icons.calendar_month_outlined,
                size: AppSizing.iconSm,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankRow(TeamMonthRow row) {
    final s = row.summary;
    return InkWell(
      key: ValueKey('rank-${row.employeeId}'),
      onTap: () => _openMonth(row.employeeId, row.name),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Text(
                s.rank == null ? '-' : '#${s.rank}',
                style: AppTypography.itemTitle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    style: AppTypography.bodyPrimary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${s.present} of ${s.workingDays} days'
                    '${s.percent == null ? ' - not rated yet' : ' - ${s.percent}%'}'
                    '${s.stars == null ? '' : ' - ${s.stars!.toStringAsFixed(1)} stars'}',
                    style: AppTypography.caption,
                  ),
                  Text(
                    'Late ${s.late} - Early ${s.early} - Absent ${s.absent}',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the existing admin timing editor for one person and day, and on a
/// save refreshes everything that shows attendance. Returns true when saved.
Future<bool> showAdminTimingEditor(
  BuildContext context,
  WidgetRef ref, {
  required TeamRow row,
  required String date,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => EditTimingsDialog(
      service: ref.read(attendanceServiceProvider),
      row: row,
      date: date,
    ),
  );
  if (changed != true) return false;
  ref.invalidate(attendanceTeamDayProvider);
  ref.invalidate(attendanceTeamMonthProvider);
  ref.invalidate(attendanceApprovalsProvider);
  ref.invalidate(attendanceMonthProvider);
  ref.invalidate(attendanceTodayProvider);
  return true;
}

TimeOfDay? _parseTime(String? hhmm) {
  if (hhmm == null) return null;
  final p = hhmm.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
}

String? _formatTime(TimeOfDay? t) => t == null
    ? null
    : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The timing editor: change or remove one person's check-in/out for a day.
/// Returns true when something was saved.
class EditTimingsDialog extends StatefulWidget {
  const EditTimingsDialog({
    super.key,
    required this.service,
    required this.row,
    required this.date,
  });

  final AttendanceService service;
  final TeamRow row;
  final String date;

  @override
  State<EditTimingsDialog> createState() => EditTimingsDialogState();
}

class EditTimingsDialogState extends State<EditTimingsDialog> {
  late TimeOfDay? _in = _parseTime(widget.row.record?.checkInLocal);
  late TimeOfDay? _out = _parseTime(widget.row.record?.checkOutLocal);
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _removing => _in == null && _out == null;

  Future<void> _save() async {
    if (_busy) return;
    final reason = _reason.text.trim();
    if (reason.length < 3 || reason.length > 300) {
      setState(() => _error = 'A reason of 3 to 300 characters is required.');
      return;
    }
    if (_in == null && _out != null) {
      setState(() => _error = 'Add a check-in time before a check-out time.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.adminEdit(
        employeeId: widget.row.employeeId,
        date: widget.date,
        checkIn: _formatTime(_in),
        checkOut: _formatTime(_out),
        reason: reason,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = attendanceErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      title: widget.row.name,
      subtitle:
          '${attendanceDateLabel(widget.date, withYear: true)}. Change or remove this day\'s timings.',
      footer: AppFormActions(
        submitLabel: _removing ? 'Remove record' : 'Save',
        busy: _busy,
        onSubmit: _save,
      ),
      child: AppFormColumn(
        children: [
          if (_error != null) InlineErrorBanner(message: _error!),
          AppFormField(
            label: 'Check-in',
            child: AppTimeField(
              value: _in,
              placeholder: 'No check-in',
              onChanged: (t) => setState(() => _in = t),
              onClear: () => setState(() => _in = null),
            ),
          ),
          AppFormField(
            label: 'Check-out',
            child: AppTimeField(
              value: _out,
              placeholder: 'No check-out',
              onChanged: (t) => setState(() => _out = t),
              onClear: () => setState(() => _out = null),
            ),
          ),
          if (_removing)
            Text(
              'Both times are empty, so saving will remove this day\'s '
              'record. The change is kept in the audit log.',
              style: AppTypography.caption,
            ),
          AppFormField(
            label: 'Reason',
            child: TextField(
              controller: _reason,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Why are you changing this?',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
