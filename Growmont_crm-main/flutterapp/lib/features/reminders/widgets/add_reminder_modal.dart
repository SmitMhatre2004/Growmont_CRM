import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/reminder.dart';
import '../../../models/user.dart';
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
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _eventName,
              decoration: const InputDecoration(labelText: 'Event Name *'),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: reminderTypeChoices
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.$1,
                      child: Text(c.$2, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: const [
                DropdownMenuItem(value: 'HIGH', child: Text('High Priority')),
                DropdownMenuItem(
                  value: 'MEDIUM',
                  child: Text('Medium Priority'),
                ),
                DropdownMenuItem(value: 'LOW', child: Text('Low Priority')),
              ],
              onChanged: (v) => setState(() => _priority = v!),
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date *'),
              subtitle: Text(
                AppFormatters.formatDate(AppFormatters.toApiDate(_date)),
              ),
              trailing: const Icon(
                Icons.calendar_today,
                size: AppSizing.iconMd,
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time *'),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.access_time, size: AppSizing.iconMd),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (t != null) setState(() => _time = t);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('End Time (optional)'),
              subtitle: Text(_endTime?.format(context) ?? 'Not set'),
              trailing: const Icon(Icons.schedule, size: AppSizing.iconMd),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _endTime ?? _time,
                );
                if (t != null) setState(() => _endTime = t);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat Reminder'),
              value: _repeatReminder,
              onChanged: (v) {
                setState(() {
                  _repeatReminder = v;
                  if (v && _repeatType == 'NONE') {
                    _repeatType = 'DAILY';
                  }
                });
              },
            ),
            if (_repeatReminder) ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: ValueKey('repeat_type_$_repeatType'),
                isExpanded: true,
                initialValue: _repeatType == 'NONE' ? 'DAILY' : _repeatType,
                decoration: const InputDecoration(labelText: 'Repeat Type'),
                items: repeatTypeChoices
                    .where((c) => c.$1 != 'NONE')
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.$1,
                        child: Text(c.$2, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _repeatType = v!),
              ),
              if (_repeatType == 'WEEKLY') ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: 8,
                  children: weekDays.map((day) {
                    final selected = _repeatDays.contains(day);
                    return FilterChip(
                      label: Text(day),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _repeatDays.add(day);
                          } else {
                            _repeatDays.remove(day);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeat Every Day'),
                value: _repeatEveryDay,
                onChanged: (v) => setState(() => _repeatEveryDay = v),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: AppSizing.controlLg,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Saving...' : 'Save Reminder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
