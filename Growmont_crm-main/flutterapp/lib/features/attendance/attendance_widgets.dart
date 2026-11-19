import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_form.dart';
import '../../shared/widgets/app_modal_shell.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/inline_error_banner.dart';
import '../../shared/widgets/status_badge.dart';
import 'attendance_models.dart';
import 'attendance_service.dart';

/// "Tue 12 Nov" for a 'YYYY-MM-DD' key; the key itself if it cannot parse.
String attendanceDateLabel(String date, {bool withYear = false}) {
  final d = DateTime.tryParse(date);
  if (d == null) return date;
  return DateFormat(withYear ? 'EEE d MMM yyyy' : 'EEE d MMM').format(d);
}

String attendanceMonthLabel(DateTime month) =>
    DateFormat('MMMM yyyy').format(month);

String _minutesText(int m) => m == 1 ? '1 min' : '$m min';

/// "Late 25 min" / "Left 40 min early".
String reviewKindText(String kind, int minutes) => kind == 'late'
    ? 'Late ${_minutesText(minutes)}'
    : 'Left ${_minutesText(minutes)} early';

Widget statusBadgeFor(String status, {String? holidayName}) {
  switch (status) {
    case 'present':
      return const StatusBadge.won(label: 'Present');
    case 'absent':
      return const StatusBadge.overdue(label: 'Absent');
    case 'off':
      return StatusBadge.inactive(label: holidayName ?? 'Off day');
    default:
      return const StatusBadge.inactive(label: 'Upcoming');
  }
}

Widget reviewBadgeFor(String status) {
  switch (status) {
    case 'needs_note':
      return const StatusBadge.followUp(label: 'Note needed');
    case 'pending':
      return const StatusBadge.fresh(label: 'Awaiting review');
    case 'approved':
      return const StatusBadge.won(label: 'Approved');
    case 'rejected':
      return const StatusBadge.overdue(label: 'Rejected');
    default:
      return const SizedBox.shrink();
  }
}

/// "8 h 59 min" / "45 min" for a worked duration.
String workedText(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The late and early lines of one record, each with its review state, the
/// person's note, the admin's comment and the write/edit note action.
class AttendanceReviewItems extends StatelessWidget {
  const AttendanceReviewItems({
    super.key,
    required this.record,
    required this.onWriteNote,
  });

  final AttendanceRecord record;

  /// Called with 'late' or 'early'. Null hides the write-note action.
  final void Function(String kind)? onWriteNote;

  @override
  Widget build(BuildContext context) {
    Widget item(String kind, ReviewInfo info, int minutes) {
      if (minutes <= 0) return const SizedBox.shrink();
      final canWrite =
          onWriteNote != null && (info.needsNote || info.isPending);
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        kind == 'late' ? Icons.schedule : Icons.logout,
                        size: 13,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        reviewKindText(kind, minutes),
                        style: AppTypography.captionSemibold.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                reviewBadgeFor(info.status),
                if (canWrite)
                  TextButton(
                    onPressed: () => onWriteNote!(kind),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                    ),
                    child: Text(info.needsNote ? 'Write note' : 'Edit note'),
                  ),
              ],
            ),
            if (info.note != null)
              Text('Your note: ${info.note}', style: AppTypography.caption),
            if (info.isDecided && info.comment != null)
              Text(
                'Admin${info.decidedByName != null ? ' (${info.decidedByName})' : ''}: ${info.comment}',
                style: AppTypography.caption,
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item('late', record.late, record.lateMinutes),
        item('early', record.early, record.earlyMinutes),
      ],
    );
  }
}

/// The bordered card the profile screen uses, with an optional header.
class AttendancePanel extends StatelessWidget {
  const AttendancePanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.leading,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  /// Replaces the small icon badge in the header (the profile cards put the
  /// attendance pill here).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surfaceHeader,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                leading ??
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.info,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(icon, size: 12, color: Colors.white),
                    ),
                SizedBox(
                  width: leading == null ? AppSpacing.sm : AppSpacing.md,
                ),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: child),
        ],
      ),
    );
  }
}

/// Loading, error-with-retry and data for any attendance provider.
class AttendanceAsync<T> extends StatelessWidget {
  const AttendanceAsync({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
    this.isEmpty,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage = '',
    this.emptyIcon = Icons.inbox_outlined,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;
  final bool Function(T data)? isEmpty;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    // A refresh keeps showing the previous data rather than flashing a
    // spinner over it.
    if (value.hasValue && !value.hasError) {
      final data = value.requireValue;
      if (isEmpty != null && isEmpty!(data)) {
        return _EmptyBlock(
          icon: emptyIcon,
          title: emptyTitle,
          message: emptyMessage,
        );
      }
      return builder(data);
    }
    if (value.hasError) {
      return ErrorState(
        message: attendanceErrorMessage(value.error!),
        onRetry: onRetry,
      );
    }
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.xxl),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizing.iconDisplay, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AppTypography.itemTitle),
            if (message.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A "Label    value" row that wraps instead of overflowing.
class AttendanceInfoRow extends StatelessWidget {
  const AttendanceInfoRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: AppTypography.caption),
          ),
          Expanded(child: Text(value, style: AppTypography.bodyPrimary)),
        ],
      ),
    );
  }
}

/// Month stepper: previous, label, next. [canGoNext] false stops at today.
class AttendanceMonthStepper extends StatelessWidget {
  const AttendanceMonthStepper({
    super.key,
    required this.month,
    required this.onChanged,
    this.allowFuture = false,
  });

  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final bool allowFuture;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            attendanceMonthLabel(month),
            textAlign: TextAlign.center,
            style: AppTypography.itemTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: isCurrent && !allowFuture
              ? null
              : () => onChanged(DateTime(month.year, month.month + 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// Dialog to write or edit the note on a late / early item. Returns true when
/// the note was saved.
Future<bool> showAttendanceNoteDialog(
  BuildContext context, {
  required AttendanceService service,
  required String date,
  required String kind,
  required int minutes,
  String? existingNote,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _NoteDialog(
      service: service,
      date: date,
      kind: kind,
      minutes: minutes,
      existingNote: existingNote,
    ),
  );
  return saved == true;
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.service,
    required this.date,
    required this.kind,
    required this.minutes,
    this.existingNote,
  });

  final AttendanceService service;
  final String date;
  final String kind;
  final int minutes;
  final String? existingNote;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.existingNote);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final text = _controller.text.trim();
    if (text.length < 3 || text.length > 500) {
      setState(() => _error = 'Please write between 3 and 500 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.submitNote(
        date: widget.date,
        kind: widget.kind,
        note: text,
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
      title: widget.kind == 'late'
          ? 'Why were you late?'
          : 'Why did you leave early?',
      subtitle:
          '${attendanceDateLabel(widget.date)} - ${reviewKindText(widget.kind, widget.minutes)}. An admin will review your note.',
      footer: AppFormActions(
        submitLabel: 'Send note',
        busy: _busy,
        onSubmit: _save,
      ),
      child: AppFormColumn(
        children: [
          if (_error != null) InlineErrorBanner(message: _error!),
          AppFormField(
            label: 'Your note',
            child: TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Explain briefly what happened',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
