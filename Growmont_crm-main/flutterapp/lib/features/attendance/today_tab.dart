import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/inline_error_banner.dart';
import '../auth/auth_provider.dart';
import 'attendance_calendar.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_widgets.dart';
import 'mark_actions.dart';
import 'mark_flow.dart';
import 'team_tab.dart';

/// "Today" for every signed-in person: the day, the mark button and the
/// month so far.
class AttendanceTodayTab extends ConsumerStatefulWidget {
  const AttendanceTodayTab({super.key});

  @override
  ConsumerState<AttendanceTodayTab> createState() => _AttendanceTodayTabState();
}

class _AttendanceTodayTabState extends ConsumerState<AttendanceTodayTab>
    with WidgetsBindingObserver {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Timer? _dayWatcher;
  String _localDay = dateKeyOf(DateTime.now());

  // Mark state. _busy is set before any await so a second tap is ignored
  // even before the button has rebuilt as disabled.
  bool _busy = false;
  String _status = '';
  MarkFailed? _failure;
  String? _lastAction;

  MonthKey get _monthKey => (employeeId: null, month: monthKeyOf(_month));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dayWatcher = Timer.periodic(const Duration(seconds: 30), (_) {
      final day = dateKeyOf(DateTime.now());
      if (day != _localDay) {
        final moved = monthAfterDayChange(_month, _localDay, day);
        _localDay = day;
        if (mounted && moved != _month) setState(() => _month = moved);
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _dayWatcher?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(attendanceTodayProvider);
    ref.invalidate(attendanceMonthProvider);
  }

  Future<void> _mark(String action) async {
    if (_busy || ref.read(attendanceMarkBusyProvider)) return;
    _busy = true;
    setState(() {
      _status = 'Starting...';
      _failure = null;
      _lastAction = action;
    });

    final outcome = await performMark(
      context,
      action,
      onStatus: (s) {
        if (mounted) setState(() => _status = s);
      },
    );
    _busy = false;
    if (!mounted) return;

    switch (outcome) {
      case MarkFailed():
        setState(() {
          _status = '';
          _failure = outcome;
        });
      case MarkSuccess():
        setState(() {
          _status = '';
          _failure = null;
        });
      case MarkCancelled() || null:
        setState(() => _status = '');
    }
  }

  Future<void> _fixAction(MarkFix fix) async {
    final location = ref.read(locationGatewayProvider);
    switch (fix) {
      case MarkFix.retry:
        final action = _lastAction;
        if (action != null) await _mark(action);
      case MarkFix.openAppSettings:
        await location.openAppSettings();
      case MarkFix.openLocationSettings:
        await location.openLocationSettings();
      case MarkFix.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(attendanceTodayProvider);
    final month = ref.watch(attendanceMonthProvider(_monthKey));
    final isMobile = AppLayout.isMobile(context);

    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await ref
            .read(attendanceTodayProvider.future)
            .catchError((_) => TodayInfo.fromJson(const {}));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isMobile ? AppSpacing.lg : AppSpacing.xxl,
          AppSpacing.sm,
          isMobile ? AppSpacing.lg : AppSpacing.xxl,
          AppSpacing.xxl,
        ),
        children: [
          AttendanceAsync<TodayInfo>(
            value: today,
            onRetry: _refresh,
            builder: _todayCard,
          ),
          const SizedBox(height: AppSpacing.lg),
          ..._notePrompts(today.valueOrNull, month.valueOrNull),
          AttendancePanel(
            title: 'My month',
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
                  onRetry: () => ref.invalidate(attendanceMonthProvider),
                  isEmpty: (d) => d.days.isEmpty,
                  emptyTitle: 'No days to show',
                  emptyMessage: 'Nothing is counted for this month yet.',
                  emptyIcon: Icons.event_busy_outlined,
                  builder: (d) => _monthBody(d, today.valueOrNull),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthBody(MonthData d, TodayInfo? t) {
    final todayKey = t?.date.isNotEmpty == true
        ? t!.date
        : dateKeyOf(DateTime.now());
    final user = ref.watch(authProvider).user;
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
            onWriteNote: (kind, record) => writeAttendanceNote(
              context,
              date: record.date,
              kind: kind,
              record: record,
            ),
            // Admins only: edit this day's times for themselves. The server
            // rejects future days and validates the times.
            onEditTimes: user?.isAdmin == true
                ? () => showAdminTimingEditor(
                    context,
                    ref,
                    row: TeamRow(
                      employeeId: user!.id,
                      name: user.name,
                      status: day.status,
                      record: day.record,
                    ),
                    date: day.date,
                  )
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AttendanceCalendarLegend(),
      ],
    );
  }

  // -- Today card -----------------------------------------------------------

  bool get _isBusy => _busy || ref.watch(attendanceMarkBusyProvider);

  Widget _todayCard(TodayInfo t) {
    final canMark = ref.watch(canMarkAttendanceProvider);
    final record = t.record;
    final hasIn = record?.hasCheckIn == true;
    final hasOut = record?.hasCheckOut == true;
    final status = hasOut
        ? 'Day complete'
        : hasIn
        ? 'Checked in'
        : 'Not marked';
    // The one big number: the time worked once the day is complete, the time
    // you checked in, and the office clock while nothing is marked.
    final keyTime = hasOut
        ? (record!.workedMinutes != null
              ? workedText(record.workedMinutes!)
              : record.checkOutLocal!)
        : hasIn
        ? record!.checkInLocal!
        : t.time;
    final (dayIcon, dayLabel) = switch (t.dayType) {
      'holiday' => (Icons.celebration_outlined, t.holidayName ?? 'Holiday'),
      'weekly_off' => (Icons.weekend_outlined, 'Weekly off'),
      _ => (Icons.work_outline, 'Working day'),
    };

    return Container(
      key: const ValueKey('today-card'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  attendanceDateLabel(t.date, withYear: true),
                  style: AppTypography.caption,
                ),
              ),
              Tooltip(
                message: dayLabel,
                child: Semantics(
                  label: dayLabel,
                  child: ExcludeSemantics(
                    child: Container(
                      key: const ValueKey('day-type-icon'),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: t.dayType == 'working'
                            ? AppColors.successSoft
                            : AppColors.chatSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        dayIcon,
                        size: AppSizing.iconSm,
                        color: t.dayType == 'working'
                            ? AppColors.primaryGreenDark
                            : AppColors.chatText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            status,
            style: AppTypography.fieldLabel.copyWith(
              color: hasIn
                  ? AppColors.primaryGreenDark
                  : AppColors.textSecondary,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              keyTime,
              key: const ValueKey('today-key-time'),
              maxLines: 1,
              style: AppTypography.heroNumber,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${t.settings.arrival} – ${t.settings.leave} '
            '· ${t.settings.graceMinutes} min grace',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          _timeline(record),
          if (record != null && (record.isLate || record.isEarly)) ...[
            const SizedBox(height: AppSpacing.sm),
            AttendanceReviewItems(
              record: record,
              onWriteNote: (kind) => writeAttendanceNote(
                context,
                date: record.date,
                kind: kind,
                record: record,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (!t.configured)
            const InlineErrorBanner(
              message:
                  'Attendance is not set up yet. An admin needs to set the '
                  'office location first.',
            ),
          if (!canMark)
            _phoneOnlyNotice()
          else ...[
            if (_failure != null) ...[
              InlineErrorBanner(message: _failure!.message),
              const SizedBox(height: AppSpacing.sm),
              if (_failure!.fix != MarkFix.none)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : () => _fixAction(_failure!.fix),
                    icon: Icon(
                      _failure!.fix == MarkFix.retry
                          ? Icons.refresh
                          : Icons.settings_outlined,
                      size: AppSizing.iconSm,
                    ),
                    label: Text(markFixLabel(_failure!.fix) ?? ''),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
            ],
            ..._markButtons(record),
            if (_busy && _status.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// In -> Out on one line, with the worked time under it once both exist.
  Widget _timeline(AttendanceRecord? r) {
    Widget stop(String label, String? value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.caption),
        Text(
          value ?? '--:--',
          style: AppTypography.itemTitle.copyWith(
            fontFeatures: AppTypography.tabular,
            color: value == null ? AppColors.textMuted : AppColors.textPrimary,
          ),
        ),
      ],
    );
    final worked = r?.workedMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            stop('In', r?.checkInLocal),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.borderStrong)),
                    Icon(
                      Icons.arrow_forward,
                      size: AppSizing.iconSm,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            stop('Out', r?.checkOutLocal),
          ],
        ),
        if (worked != null && r!.hasCheckOut) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Worked ${workedText(worked)}',
            key: const ValueKey('worked-time'),
            style: AppTypography.caption,
          ),
        ],
      ],
    );
  }

  Widget _phoneOnlyNotice() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.smartphone_outlined,
            size: AppSizing.iconLg,
            color: AppColors.info,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Mark attendance from the phone app',
              style: AppTypography.itemTitle.copyWith(color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _markButtons(AttendanceRecord? record) {
    final size = Size.fromHeight(
      AppLayout.isMobile(context) ? AppSizing.controlLg : AppSizing.controlMd,
    );
    final hasIn = record?.hasCheckIn == true;
    final hasOut = record?.hasCheckOut == true;

    if (!hasIn) {
      return [
        FilledButton.icon(
          onPressed: _isBusy ? null : () => _mark('in'),
          style: FilledButton.styleFrom(minimumSize: size),
          icon: _isBusy ? _spinner() : const Icon(Icons.login, size: 18),
          label: const Text('Mark present'),
        ),
      ];
    }
    if (!hasOut) {
      return [
        FilledButton.icon(
          onPressed: _isBusy ? null : () => _mark('out'),
          style: FilledButton.styleFrom(minimumSize: size),
          icon: _isBusy ? _spinner() : const Icon(Icons.logout, size: 18),
          label: const Text('Mark check-out'),
        ),
      ];
    }
    return [
      FilledButton.icon(
        onPressed: null,
        style: FilledButton.styleFrom(minimumSize: size),
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Done'),
      ),
      const SizedBox(height: AppSpacing.sm),
      OutlinedButton(
        onPressed: _isBusy ? null : () => _mark('out'),
        style: OutlinedButton.styleFrom(minimumSize: size),
        child: Text(_isBusy ? 'Please wait...' : 'Update check-out'),
      ),
    ];
  }

  Widget _spinner() => const SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
  );

  // -- Late / early items ---------------------------------------------------

  /// A prominent prompt for every late/early item still waiting on a note.
  List<Widget> _notePrompts(TodayInfo? today, MonthData? month) {
    final byDate = <String, AttendanceRecord>{};
    for (final d in month?.days ?? const <MonthDay>[]) {
      final r = d.record;
      if (r != null && r.hasNeedsNote) byDate[r.date] = r;
    }
    final tr = today?.record;
    if (tr != null && tr.hasNeedsNote) byDate[tr.date] = tr;
    if (byDate.isEmpty) return const [];

    final records = byDate.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return [
      for (final r in records)
        for (final kind in const ['late', 'early'])
          if ((kind == 'late' ? r.late : r.early).needsNote)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                  borderRadius: AppRadius.brMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Please write a note',
                      style: AppTypography.itemTitle.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${attendanceDateLabel(r.date)}: '
                      '${reviewKindText(kind, kind == 'late' ? r.lateMinutes : r.earlyMinutes)}. '
                      'An admin cannot review it until you explain.',
                      style: AppTypography.bodySecondary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton(
                      onPressed: () => writeAttendanceNote(
                        context,
                        date: r.date,
                        kind: kind,
                        record: r,
                      ),
                      child: const Text('Write note'),
                    ),
                  ],
                ),
              ),
            ),
    ];
  }
}
