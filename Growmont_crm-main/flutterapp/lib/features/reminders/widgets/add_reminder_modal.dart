import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/reminder.dart';
import '../../../models/user.dart';
import '../../../shared/widgets/app_form.dart';
import '../../../shared/widgets/app_modal_shell.dart';

class AddReminderModal extends ConsumerStatefulWidget {
  const AddReminderModal({super.key, this.existing, this.currentUser});

  final Reminder? existing;
  final AppUser? currentUser;

  @override
  ConsumerState<AddReminderModal> createState() => _AddReminderModalState();
}

class _AddReminderModalState extends ConsumerState<AddReminderModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _eventName;
  late TextEditingController _description;
  late DateTime _date;
  late TimeOfDay _time;
  TimeOfDay? _endTime;
  String _type = 'CORPORATE';
  String _priority = 'MEDIUM';
  bool _repeatReminder = false;
  String _repeatType = 'NONE';
  List<String> _repeatDays = [];
  bool _repeatEveryDay = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _eventName = TextEditingController(text: e?.eventName ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _date = e != null ? DateTime.parse(e.date) : DateTime.now();
    final timeParts = (e?.time ?? '09:00:00').split(':');
    _time = TimeOfDay(
      hour: int.tryParse(timeParts[0]) ?? 9,
      minute: int.tryParse(timeParts[1]) ?? 0,
    );
    if (e?.endTime != null && e!.endTime!.isNotEmpty) {
      final endParts = e.endTime!.split(':');
      _endTime = TimeOfDay(
        hour: int.tryParse(endParts[0]) ?? 10,
        minute: int.tryParse(endParts[1]) ?? 0,
      );
    }
    _type = e?.type ?? 'CORPORATE';
    _priority = e?.priority ?? 'MEDIUM';
    _repeatReminder = e?.repeatReminder ?? false;
    _repeatType = e?.repeatType ?? 'NONE';
    _repeatDays = List.from(e?.repeatDays ?? []);
    _repeatEveryDay = e?.repeatEveryDay ?? false;
  }

  @override
  void dispose() {
    _eventName.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = widget.currentUser?.id;
    if (userId == null) return;

    setState(() => _loading = true);
    final payload = {
      'employee': userId,
      'event_name': _eventName.text.trim(),
      'type': _type,
      'priority': _priority,
      'date': AppFormatters.toApiDate(_date),
      'time': AppFormatters.toApiTime(_time),
      'end_time': _endTime != null ? AppFormatters.toApiTime(_endTime!) : null,
      'description': _description.text.trim(),
      'repeat_reminder': _repeatReminder,
      'repeat_type': _repeatReminder ? _repeatType : 'NONE',
      'repeat_days': _repeatReminder ? _repeatDays : <String>[],
      'repeat_every_day': _repeatEveryDay,
    };

    try {
      final api = ref.read(apiServiceProvider);
      if (widget.existing != null) {
        await api.updateReminder(widget.existing!.id, payload);
      } else {
        await api.createReminder(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      title: widget.existing != null ? 'Edit Reminder' : 'Add Reminder',
      footer: AppFormActions(
        submitLabel: 'Save Reminder',
        busy: _loading,
        onSubmit: _submit,
      ),
      child: Form(
        key: _formKey,
        child: AppFormColumn(
          gap: kFormSectionGap,
          children: [
            AppFormSection(
              title: 'Event',
              children: [
                AppFormField(
                  label: 'Event name',
                  child: TextFormField(
                    controller: _eventName,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Portfolio review with client',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter an event name'
                        : null,
                  ),
                ),
                modalFieldPair(
                  context,
                  AppFormField(
                    label: 'Type',
                    child: AppDropdownField<String>(
                      value: _type,
                      items: choiceItems(reminderTypeChoices),
                      onChanged: (v) => setState(() => _type = v!),
                    ),
                  ),
                  AppFormField(
                    label: 'Priority',
                    child: AppDropdownField<String>(
                      value: _priority,
                      items: choiceItems(priorityChoices),
                      onChanged: (v) => setState(() => _priority = v!),
                    ),
                  ),
                ),
                AppFormField(
                  label: 'Description',
                  optional: true,
                  child: TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Details to remember',
                    ),
                  ),
                ),
              ],
            ),
            AppFormSection(
              title: 'When',
              children: [
                AppFormField(
                  label: 'Date',
                  child: AppDateField(
                    value: _date,
                    firstDate: DateTime.now(),
                    onChanged: (d) => setState(() => _date = d),
                  ),
                ),
                modalFieldPair(
                  context,
                  AppFormField(
                    label: 'Start time',
                    child: AppTimeField(
                      value: _time,
                      onChanged: (t) => setState(() => _time = t),
                    ),
                  ),
                  AppFormField(
                    label: 'End time',
                    optional: true,
                    child: AppTimeField(
                      value: _endTime,
                      initialTime: _time,
                      placeholder: 'Not set',
                      onChanged: (t) => setState(() => _endTime = t),
                      onClear: () => setState(() => _endTime = null),
                    ),
                  ),
                ),
              ],
            ),
            AppToggleSection(
              title: 'Repeat',
              subtitle: 'Remind again on a schedule',
              value: _repeatReminder,
              onChanged: (v) => setState(() {
                _repeatReminder = v;
                if (v && _repeatType == 'NONE') _repeatType = 'DAILY';
              }),
              child: AppFormColumn(
                children: [
                  AppFormField(
                    label: 'Repeats',
                    child: AppDropdownField<String>(
                      key: ValueKey('repeat_type_$_repeatType'),
                      value: _repeatType == 'NONE' ? 'DAILY' : _repeatType,
                      items: choiceItems(
                        repeatTypeChoices
                            .where((c) => c.$1 != 'NONE')
                            .toList(),
                      ),
                      onChanged: (v) => setState(() => _repeatType = v!),
                    ),
                  ),
                  if (_repeatType == 'WEEKLY')
                    AppFormField(
                      label: 'On these days',
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final day in weekDays)
                            FilterChip(
                              label: Text(day),
                              selected: _repeatDays.contains(day),
                              onSelected: (v) => setState(() {
                                if (v) {
                                  _repeatDays.add(day);
                                } else {
                                  _repeatDays.remove(day);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Repeat every day',
                          style: AppTypography.bodyPrimary,
                        ),
                      ),
                      Switch(
                        value: _repeatEveryDay,
                        onChanged: (v) => setState(() => _repeatEveryDay = v),
                      ),
                    ],
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
