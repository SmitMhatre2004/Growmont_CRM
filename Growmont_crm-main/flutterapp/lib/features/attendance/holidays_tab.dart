import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_form.dart';
import '../../shared/widgets/app_modal_shell.dart';
import '../../shared/widgets/inline_error_banner.dart';
import '../../shared/widgets/toolbar_action_button.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_service.dart';
import 'attendance_widgets.dart';

/// Admin: the year's holidays - add, rename, remove.
class AttendanceHolidaysTab extends ConsumerStatefulWidget {
  const AttendanceHolidaysTab({super.key});

  @override
  ConsumerState<AttendanceHolidaysTab> createState() =>
      _AttendanceHolidaysTabState();
}

class _AttendanceHolidaysTabState extends ConsumerState<AttendanceHolidaysTab> {
  int _year = DateTime.now().year;

  void _reload() {
    ref.invalidate(attendanceHolidaysProvider);
    // Holidays change which days count, so everything derived is stale.
    ref.invalidate(attendanceMonthProvider);
    ref.invalidate(attendanceTodayProvider);
    ref.invalidate(attendanceTeamDayProvider);
    ref.invalidate(attendanceTeamMonthProvider);
    ref.invalidate(attendanceApprovalsProvider);
  }

  Future<void> _edit({Holiday? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _HolidayDialog(
        service: ref.read(attendanceServiceProvider),
        existing: existing,
        year: _year,
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _remove(Holiday h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove holiday?'),
        content: Text(
          '${h.name} on ${attendanceDateLabel(h.date, withYear: true)} will '
          'become a normal working day again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(attendanceServiceProvider).removeHoliday(h.date);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(attendanceErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppLayout.isMobile(context);
    final pad = isMobile ? AppSpacing.lg : AppSpacing.xxl;

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, AppSpacing.xxl),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous year',
              onPressed: () => setState(() => _year--),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '$_year',
                textAlign: TextAlign.center,
                style: AppTypography.itemTitle,
              ),
            ),
            IconButton(
              tooltip: 'Next year',
              onPressed: () => setState(() => _year++),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: AppToolbarButton(
            icon: Icons.add,
            label: 'Add holiday',
            isPrimary: true,
            onPressed: () => _edit(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AttendanceAsync<List<Holiday>>(
          value: ref.watch(attendanceHolidaysProvider(_year)),
          onRetry: () => ref.invalidate(attendanceHolidaysProvider(_year)),
          isEmpty: (list) => list.isEmpty,
          emptyTitle: 'No holidays in $_year',
          emptyMessage: 'Add one and it will not count as a working day.',
          emptyIcon: Icons.beach_access_outlined,
          builder: (list) {
            final sorted = [...list]..sort((a, b) => a.date.compareTo(b.date));
            return AttendancePanel(
              title: 'Holidays $_year',
              icon: Icons.beach_access_outlined,
              child: Column(
                children: [
                  for (final h in sorted)
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.divider),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _edit(existing: h),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      h.name,
                                      style: AppTypography.bodyPrimary,
                                    ),
                                    Text(
                                      attendanceDateLabel(h.date),
                                      style: AppTypography.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Rename',
                            onPressed: () => _edit(existing: h),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () => _remove(h),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HolidayDialog extends StatefulWidget {
  const _HolidayDialog({
    required this.service,
    required this.year,
    this.existing,
  });

  final AttendanceService service;
  final int year;
  final Holiday? existing;

  @override
  State<_HolidayDialog> createState() => _HolidayDialogState();
}

class _HolidayDialogState extends State<_HolidayDialog> {
  late DateTime _date =
      DateTime.tryParse(widget.existing?.date ?? '') ??
      DateTime(widget.year, DateTime.now().month, DateTime.now().day);
  late final _name = TextEditingController(text: widget.existing?.name);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 60) {
      setState(() => _error = 'The name must be 2 to 60 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.setHoliday(dateKeyOf(_date), name);
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
    final editing = widget.existing != null;
    return AppModalShell(
      title: editing ? 'Rename holiday' : 'Add holiday',
      subtitle: 'Saving a date that already has a holiday renames it.',
      footer: AppFormActions(
        submitLabel: editing ? 'Save' : 'Add',
        busy: _busy,
        onSubmit: _save,
      ),
      child: AppFormColumn(
        children: [
          if (_error != null) InlineErrorBanner(message: _error!),
          AppFormField(
            label: 'Date',
            child: editing
                ? AppReadOnlyField(
                    value: attendanceDateLabel(
                      dateKeyOf(_date),
                      withYear: true,
                    ),
                  )
                : AppDateField(
                    value: _date,
                    onChanged: (d) => setState(() => _date = d),
                  ),
          ),
          AppFormField(
            label: 'Name',
            child: TextField(
              controller: _name,
              enabled: !_busy,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. Diwali'),
            ),
          ),
        ],
      ),
    );
  }
}
