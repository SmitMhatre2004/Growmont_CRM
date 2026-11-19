import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_widgets.dart';

/// Amber used for half days. Not in the shared palette, which has no true
/// amber between its yellow and its brown warning.
const Color kHalfDayAmber = Color(0xFFF59E0B);

/// Leading blank cells before the 1st of [month] in a Monday-first grid.
int calendarLeadingBlanks(DateTime month) =>
    DateTime(month.year, month.month, 1).weekday - 1;

/// Full, Half, Absent and Late for the month, above the calendar. Uses the
/// server's summary; for an older server that sends none of the new fields
/// it counts the days itself.
class AttendanceSummaryStrip extends StatelessWidget {
  const AttendanceSummaryStrip({super.key, required this.data});

  final MonthData data;

  @override
  Widget build(BuildContext context) {
    final s = data.summary;
    var full = s.fullDays;
    var half = s.halfDays;
    if (s.attendedValue == null) {
      full = data.days.where((d) => d.kind == DayKind.full).length;
      half = data.days
          .where(
            (d) => d.kind == DayKind.half || d.kind == DayKind.missedCheckout,
          )
          .length;
    }
    Widget tile(String label, int n, Color color) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$n',
              style: AppTypography.metricLarge.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHeader,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          tile('Full', full, AppColors.primaryGreenDark),
          tile('Half', half, AppColors.warning),
          tile('Absent', s.absent, AppColors.danger),
          tile('Late', s.late, AppColors.textPrimary),
        ],
      ),
    );
  }
}

/// The month as a Monday-first grid. Cells are coloured by [MonthDay.kind];
/// today carries a navy ring on top of whatever it is.
class AttendanceCalendar extends StatelessWidget {
  const AttendanceCalendar({
    super.key,
    required this.month,
    required this.data,
    required this.today,
    required this.onDayTap,
  });

  final DateTime month;
  final MonthData data;

  /// 'YYYY-MM-DD' of the current office day.
  final String today;
  final ValueChanged<MonthDay> onDayTap;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final byDate = {for (final d in data.days) d.date: d};
    final blanks = calendarLeadingBlanks(month);
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final weeks = ((blanks + count) / 7).ceil();

    MonthDay dayFor(int n) {
      final key = dateKeyOf(DateTime(month.year, month.month, n));
      return byDate[key] ??
          MonthDay(
            date: key,
            type: 'working',
            status: 'upcoming',
            kind: DayKind.notTracked,
          );
    }

    return Column(
      key: const ValueKey('attendance-calendar'),
      children: [
        Row(
          children: [
            for (final w in _weekdays.indexed)
              Expanded(
                child: Center(
                  child: Text(
                    w.$2,
                    style: AppTypography.captionSemibold.copyWith(
                      color: w.$1 == 6
                          ? AppColors.textMuted
                          : AppColors.textCaption,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var w = 0; w < weeks; w++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(w * 7 + c - blanks + 1, count, dayFor)),
            ],
          ),
      ],
    );
  }

  Widget _cell(int n, int count, MonthDay Function(int) dayFor) {
    if (n < 1 || n > count) return const SizedBox(height: 44);
    final day = dayFor(n);
    return _DayCell(
      number: n,
      day: day,
      isToday: day.date == today,
      onTap: () => onDayTap(day),
    );
  }
}

String dayKindLabel(String kind) => switch (kind) {
  DayKind.full => 'Full day',
  DayKind.half => 'Half day',
  DayKind.missedCheckout => 'Missed check-out',
  DayKind.inProgress => 'In progress',
  DayKind.holiday => 'Holiday',
  DayKind.weeklyOff => 'Weekly off',
  DayKind.extra => 'Worked on an off day',
  DayKind.absent => 'Absent',
  DayKind.upcoming => 'Upcoming',
  _ => 'Not counted',
};

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.number,
    required this.day,
    required this.isToday,
    required this.onTap,
  });

  final int number;
  final MonthDay day;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = day.kind;
    final needsNote = day.record?.hasNeedsNote == true;
    final textColor = switch (kind) {
      DayKind.full => Colors.white,
      DayKind.absent => AppColors.danger,
      DayKind.holiday => AppColors.chatText,
      DayKind.weeklyOff => AppColors.textMuted,
      DayKind.upcoming || DayKind.notTracked => AppColors.textSecondary,
      _ => AppColors.textPrimary,
    };
    return Semantics(
      button: true,
      label:
          '${attendanceDateLabel(day.date)}, ${dayKindLabel(kind)}'
          '${isToday ? ', today' : ''}${needsNote ? ', note needed' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('day-${day.date}'),
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          height: 44,
          child: Center(
            child: SizedBox(
              width: 38,
              height: 38,
              child: CustomPaint(
                painter: DayCellPainter(kind: kind, isToday: isToday),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      '$number',
                      style: AppTypography.bodySecondary.copyWith(
                        color: textColor,
                        fontWeight: isToday || kind == DayKind.full
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontFeatures: AppTypography.tabular,
                      ),
                    ),
                    if (needsNote)
                      const Positioned(
                        top: 1,
                        right: 3,
                        child: _Dot(color: AppColors.warning, size: 8),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1),
    ),
  );
}

/// Draws the shape of one day: solid, half-filled, outlined, tinted, with the
/// small dots and the today ring. Public so the legend uses the same drawing.
class DayCellPainter extends CustomPainter {
  const DayCellPainter({required this.kind, this.isToday = false});

  final String kind;
  final bool isToday;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;

    switch (kind) {
      case DayKind.full:
        canvas.drawCircle(c, r, fill..color = AppColors.primaryGreen);
      case DayKind.half || DayKind.missedCheckout:
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          math.pi / 2,
          math.pi,
          true,
          fill..color = kHalfDayAmber.withValues(alpha: 0.85),
        );
        canvas.drawCircle(
          c,
          r,
          stroke
            ..color = kHalfDayAmber
            ..strokeWidth = 1.6,
        );
        if (kind == DayKind.missedCheckout) {
          canvas.drawCircle(
            c + Offset(r * 0.8, -r * 0.8),
            3.2,
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(
            c + Offset(r * 0.8, -r * 0.8),
            2.4,
            Paint()..color = AppColors.danger,
          );
        }
      case DayKind.inProgress:
        canvas.drawCircle(
          c,
          r,
          stroke
            ..color = AppColors.primaryGreen
            ..strokeWidth = 2,
        );
      case DayKind.holiday:
        canvas.drawCircle(c, r, fill..color = AppColors.chatSoft);
      case DayKind.absent:
        canvas.drawCircle(c, r, fill..color = AppColors.dangerSoft);
        canvas.drawCircle(
          c,
          r,
          stroke
            ..color = AppColors.danger.withValues(alpha: 0.25)
            ..strokeWidth = 1,
        );
      case DayKind.extra:
        canvas.drawCircle(
          c + Offset(0, r * 0.95),
          2.2,
          fill..color = AppColors.primaryGreen,
        );
      default:
        break;
    }

    if (isToday) {
      canvas.drawCircle(
        c,
        size.shortestSide / 2 - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = AppColors.primaryBlue
          ..strokeWidth = 2.4,
      );
    }
  }

  @override
  bool shouldRepaint(DayCellPainter old) =>
      old.kind != kind || old.isToday != isToday;
}

/// A compact key to the colours.
class AttendanceCalendarLegend extends StatelessWidget {
  const AttendanceCalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String kind, {bool today = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: CustomPaint(
            painter: DayCellPainter(kind: kind, isToday: today),
          ),
        ),
        const SizedBox(width: 2),
        Text(label, style: AppTypography.caption),
      ],
    );
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        item('Full', DayKind.full),
        item('Half', DayKind.half),
        item('Absent', DayKind.absent),
        item('Holiday', DayKind.holiday),
        item('In progress', DayKind.inProgress),
        item('Today', DayKind.upcoming, today: true),
      ],
    );
  }
}

/// True when a day's times may be edited by an admin: today or any past day,
/// never a future one. [date] and [today] are 'YYYY-MM-DD'.
bool canEditDayTimes(String date, String today) => date.compareTo(today) <= 0;

/// Opens the sheet for one day. [onWriteNote] is called, after the sheet has
/// closed, when the person taps Write note / Edit note.
///
/// [onEditTimes] is given only to an admin: it adds an "Edit times" / "Add
/// timing" action (called after the sheet has closed) for today and past
/// days, never for a future day. [today] is the current office day.
Future<void> showDayDetailSheet(
  BuildContext context, {
  required MonthDay day,
  required void Function(String kind, AttendanceRecord record)? onWriteNote,
  VoidCallback? onEditTimes,
  String? today,
}) {
  final editable =
      onEditTimes != null &&
      canEditDayTimes(day.date, today ?? dateKeyOf(DateTime.now()));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheet) => _DaySheet(
      day: day,
      onWriteNote: onWriteNote == null
          ? null
          : (kind, record) {
              Navigator.pop(sheet);
              onWriteNote(kind, record);
            },
      onEditTimes: editable
          ? () {
              Navigator.pop(sheet);
              onEditTimes();
            }
          : null,
    ),
  );
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.day, this.onWriteNote, this.onEditTimes});

  final MonthDay day;
  final void Function(String kind, AttendanceRecord record)? onWriteNote;
  final VoidCallback? onEditTimes;

  @override
  Widget build(BuildContext context) {
    final r = day.record;
    final kind = day.kind;
    final hasIn = r != null && r.hasCheckIn;

    final headline = switch (kind) {
      DayKind.holiday => day.holidayName ?? 'Holiday',
      DayKind.weeklyOff => 'Weekly off',
      _ => dayKindLabel(kind),
    };

    final explanation = switch (kind) {
      DayKind.missedCheckout =>
        'No check-out was recorded, so this counts as a half day until an '
            'admin adds the time.',
      DayKind.absent => 'No check-in was recorded for this working day.',
      DayKind.inProgress => 'Checked in and still at work.',
      DayKind.half =>
        'Worked less than a full day, so this counts as a half day.',
      DayKind.extra => 'Worked on an off day.',
      DayKind.upcoming => 'This day has not happened yet.',
      DayKind.notTracked => 'Attendance is not counted for this day.',
      _ => null,
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          key: const ValueKey('day-sheet'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              attendanceDateLabel(day.date, withYear: true),
              style: AppTypography.headingLargeMobile,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              headline,
              style: AppTypography.itemTitle.copyWith(
                color: switch (kind) {
                  DayKind.full => AppColors.primaryGreenDark,
                  DayKind.absent => AppColors.danger,
                  DayKind.half || DayKind.missedCheckout => AppColors.warning,
                  _ => AppColors.textSecondary,
                },
              ),
            ),
            if (explanation != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(explanation, style: AppTypography.bodySecondary),
            ],
            if (hasIn) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  _time('In', r.checkInLocal!),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Icon(
                      Icons.arrow_forward,
                      size: AppSizing.iconSm,
                      color: AppColors.textMuted,
                    ),
                  ),
                  _time('Out', r.checkOutLocal ?? 'No check-out'),
                ],
              ),
              if (r.workedMinutes != null && r.hasCheckOut) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Worked ${workedText(r.workedMinutes!)}',
                  style: AppTypography.bodySecondary,
                ),
              ],
              if (r.isLate || r.isEarly) ...[
                const SizedBox(height: AppSpacing.sm),
                AttendanceReviewItems(
                  record: r,
                  onWriteNote: onWriteNote == null
                      ? null
                      : (k) => onWriteNote!(k, r),
                ),
              ],
            ],
            if (onEditTimes != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('day-edit-times'),
                  onPressed: onEditTimes,
                  icon: const Icon(Icons.edit_outlined, size: AppSizing.iconSm),
                  label: Text(hasIn ? 'Edit times' : 'Add timing'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _time(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.caption),
      Text(
        value,
        style: AppTypography.metricMedium.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}
