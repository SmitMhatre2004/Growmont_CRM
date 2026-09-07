import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';
import '../../../models/interaction.dart';
import '../../../models/user.dart';

class AddInteractionModal extends ConsumerStatefulWidget {
  const AddInteractionModal({super.key, this.existing, this.currentUser});

  final Interaction? existing;
  final AppUser? currentUser;

  @override
  ConsumerState<AddInteractionModal> createState() => _AddInteractionModalState();
}

class _AddInteractionModalState extends ConsumerState<AddInteractionModal> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late DateTime _followUpDate;
  late TimeOfDay _followUpTime;
  late TextEditingController _clientName;
  late TextEditingController _clientContact;
  late TextEditingController _notes;
  String _priority = 'MEDIUM';
  String? _employeeId;
  List<EmployeeDropdown> _employees = [];
  bool _loading = false;
  bool _isEmployee = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e != null ? DateTime.parse(e.date) : DateTime.now();
    _followUpDate = e != null ? DateTime.parse(e.followUpDate) : DateTime.now();
    final timeParts = (e?.followUpTime ?? '10:00:00').split(':');
    _followUpTime = TimeOfDay(
      hour: int.tryParse(timeParts[0]) ?? 10,
      minute: int.tryParse(timeParts[1]) ?? 0,
    );
    _clientName = TextEditingController(text: e?.clientName ?? '');
    _clientContact = TextEditingController(text: e?.clientContact ?? '');
    _notes = TextEditingController(text: e?.discussionNotes ?? '');
    _priority = e?.priority ?? 'MEDIUM';
    _employeeId = e?.employee ?? widget.currentUser?.id;
    _isEmployee = widget.currentUser?.role == UserRole.employee;
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    if (_isEmployee) return;
    try {
      final list = await ref.read(apiServiceProvider).getEmployeesDropdown();
      if (mounted) setState(() => _employees = list);
    } catch (_) {}
  }

  @override
  void dispose() {
    _clientName.dispose();
    _clientContact.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_followUpDate.isBefore(_date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow-up date cannot be before interaction date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_employeeId == null) return;

    setState(() => _loading = true);
    final payload = {
      'date': AppFormatters.toApiDate(_date),
      'client_name': _clientName.text.trim(),
      'client_contact': _clientContact.text.trim(),
      'employee': _employeeId,
      'follow_up_date': AppFormatters.toApiDate(_followUpDate),
      'follow_up_time': AppFormatters.toApiTime(_followUpTime),
      'priority': _priority,
      'discussion_notes': _notes.text.trim(),
    };

    try {
      final api = ref.read(apiServiceProvider);
      if (widget.existing != null) {
        await api.updateInteraction(widget.existing!.id, payload);
      } else {
        await api.createInteraction(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Material(
          child: Form(
            key: _formKey,
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Text(widget.existing != null ? 'Edit Interaction' : 'Add Interaction',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _clientName,
                  decoration: const InputDecoration(labelText: 'Client Name *'),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _clientContact,
                  decoration: const InputDecoration(labelText: 'Client Contact *'),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Interaction Date *'),
                  subtitle: Text(AppFormatters.formatDate(AppFormatters.toApiDate(_date))),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
                ListTile(
                  title: const Text('Follow-up Date *'),
                  subtitle: Text(AppFormatters.formatDate(AppFormatters.toApiDate(_followUpDate))),
                  trailing: const Icon(Icons.event),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _followUpDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _followUpDate = d);
                  },
                ),
                ListTile(
                  title: const Text('Follow-up Time *'),
                  subtitle: Text(_followUpTime.format(context)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _followUpTime);
                    if (t != null) setState(() => _followUpTime = t);
                  },
                ),
                const SizedBox(height: 12),
                if (_isEmployee)
                  TextFormField(
                    initialValue: widget.currentUser?.name,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Employee'),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _employeeId,
                    decoration: const InputDecoration(labelText: 'Employee *'),
                    items: _employees
                        .map((e) => DropdownMenuItem(value: e.id, child: Text(e.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _employeeId = v),
                  ),
                DropdownButtonFormField<String>(
                  value: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: priorityChoices
                      .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                      .toList(),
                  onChanged: (v) => setState(() => _priority = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Discussion Notes'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: Text(_loading ? 'Saving...' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
