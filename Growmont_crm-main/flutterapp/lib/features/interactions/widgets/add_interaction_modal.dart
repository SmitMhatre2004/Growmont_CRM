import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/client.dart';
import '../../../models/employee.dart';
import '../../../models/interaction.dart';
import '../../../models/user.dart';
import '../../../shared/widgets/app_form.dart';
import '../../../shared/widgets/app_modal_shell.dart';

class AddInteractionModal extends ConsumerStatefulWidget {
  const AddInteractionModal({super.key, this.existing, this.currentUser});

  final Interaction? existing;
  final AppUser? currentUser;

  @override
  ConsumerState<AddInteractionModal> createState() =>
      _AddInteractionModalState();
}

class _AddInteractionModalState extends ConsumerState<AddInteractionModal> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late bool _hasFollowUp;
  late DateTime _followUpDate;
  late TimeOfDay _followUpTime;
  late TextEditingController _notes;
  String _priority = 'MEDIUM';
  String? _employeeId;
  String? _clientId;
  List<EmployeeDropdown> _employees = [];
  List<Client> _clients = [];
  bool _loadingClients = false;
  bool _loading = false;
  bool _isEmployee = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e != null ? DateTime.parse(e.date) : DateTime.now();
    // Follow-up is optional: off by default, on only when editing an
    // interaction that already has one.
    final existingFollowUp = DateTime.tryParse(e?.followUpDate ?? '');
    _hasFollowUp = existingFollowUp != null;
    _followUpDate = existingFollowUp ?? DateTime.now();
    final existingTime = e?.followUpTime ?? '';
    final timeParts = (existingTime.isNotEmpty ? existingTime : '10:00:00')
        .split(':');
    _followUpTime = TimeOfDay(
      hour: int.tryParse(timeParts[0]) ?? 10,
      minute: int.tryParse(timeParts[1]) ?? 0,
    );
    _notes = TextEditingController(text: e?.discussionNotes ?? '');
    _priority = e?.priority ?? 'MEDIUM';
    _isEmployee = widget.currentUser?.role == UserRole.employee;
    _employeeId = e?.employee ?? (_isEmployee ? widget.currentUser?.id : null);
    _clientId = e?.clientId;
    _loadEmployees();
    if (_isEmployee) _loadClientsFor(_employeeId);
  }

  Future<void> _loadEmployees() async {
    if (_isEmployee) return;
    try {
      final list = await ref.read(apiServiceProvider).getEmployeesDropdown();
      if (mounted) {
        setState(() {
          _employees = list;
          if (_employeeId == null ||
              !_employees.any((emp) => emp.id == _employeeId)) {
            if (_employees.isNotEmpty) {
              final userInList = _employees.any(
                (emp) => emp.id == widget.currentUser?.id,
              );
              _employeeId = userInList
                  ? widget.currentUser?.id
                  : _employees.first.id;
            } else {
              _employeeId = null;
            }
          }
        });
      }
    } catch (_) {}
    _loadClientsFor(_employeeId);
  }

  /// An interaction can only be logged against a client owned by the chosen
  /// employee, so the client list is reloaded whenever that changes.
  Future<void> _loadClientsFor(String? employeeId) async {
    if (employeeId == null) {
      setState(() {
        _clients = [];
        _clientId = null;
      });
      return;
    }
    setState(() => _loadingClients = true);
    try {
      final list = await ref
          .read(apiServiceProvider)
          .getClients(employeeId: employeeId);
      if (mounted) {
        setState(() {
          _clients = list;
          _loadingClients = false;
          if (_clientId == null || !_clients.any((c) => c.id == _clientId)) {
            _clientId = null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasFollowUp && _followUpDate.isBefore(_date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow-up date cannot be before interaction date'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    if (_employeeId == null) return;
    if (_clientId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a client')));
      return;
    }

    final client = _clients.firstWhere((c) => c.id == _clientId);
    final employeeName = _isEmployee
        ? widget.currentUser?.name
        : _employees.firstWhere((e) => e.id == _employeeId).name;
    setState(() => _loading = true);
    final payload = {
      'date': AppFormatters.toApiDate(_date),
      'client_name': client.name,
      'client_id': client.id,
      'client_contact': client.contactNumber,
      'employee': _employeeId,
      'employee_name': ?employeeName,
      'follow_up_date': _hasFollowUp
          ? AppFormatters.toApiDate(_followUpDate)
          : null,
      'follow_up_time': _hasFollowUp
          ? AppFormatters.toApiTime(_followUpTime)
          : null,
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
      title: widget.existing != null ? 'Edit Interaction' : 'Add Interaction',
      footer: AppFormActions(
        submitLabel: 'Save Interaction',
        busy: _loading,
        onSubmit: _submit,
      ),
      child: Form(
        key: _formKey,
        child: AppFormColumn(
          gap: kFormSectionGap,
          children: [
            AppFormSection(
              title: 'Client',
              children: [
                AppFormField(
                  label: 'Employee',
                  child: _isEmployee
                      ? AppReadOnlyField(value: widget.currentUser?.name ?? '')
                      : AppDropdownField<String>(
                          key: ValueKey(
                            'employee_${_employeeId}_${_employees.length}',
                          ),
                          value: _employees.any((e) => e.id == _employeeId)
                              ? _employeeId
                              : null,
                          hint: 'Select employee',
                          items: [
                            for (final e in _employees)
                              DropdownMenuItem(
                                value: e.id,
                                child: Text(
                                  e.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            setState(() => _employeeId = v);
                            _loadClientsFor(v);
                          },
                          validator: (v) => v == null || v.isEmpty
                              ? 'Select an employee'
                              : null,
                        ),
                ),
                AppFormField(
                  label: 'Client',
                  child: AppDropdownField<String>(
                    key: ValueKey(
                      'interaction_client_${_clientId}_${_clients.length}',
                    ),
                    value: _clients.any((c) => c.id == _clientId)
                        ? _clientId
                        : null,
                    hint: 'Select client',
                    helperText: _loadingClients
                        ? 'Loading clients...'
                        : (_employeeId != null && _clients.isEmpty)
                        ? 'No clients assigned to this employee'
                        : null,
                    items: [
                      for (final c in _clients)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            c.contactNumber.isNotEmpty
                                ? '${c.name} (${c.contactNumber})'
                                : c.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _clientId = v),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Select a client' : null,
                  ),
                ),
              ],
            ),
            AppFormSection(
              title: 'Interaction',
              children: [
                modalFieldPair(
                  context,
                  AppFormField(
                    label: 'Interaction date',
                    child: AppDateField(
                      value: _date,
                      onChanged: (d) => setState(() => _date = d),
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
                  label: 'Discussion notes',
                  optional: true,
                  child: TextFormField(
                    controller: _notes,
                    minLines: 4,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'What was discussed, decisions, next steps',
                    ),
                  ),
                ),
              ],
            ),
            AppToggleSection(
              title: 'Follow-up',
              subtitle: 'Set a date to follow up with this client',
              value: _hasFollowUp,
              onChanged: (v) => setState(() {
                _hasFollowUp = v;
                if (v && _followUpDate.isBefore(_date)) _followUpDate = _date;
              }),
              child: modalFieldPair(
                context,
                AppFormField(
                  label: 'Follow-up date',
                  child: AppDateField(
                    value: _followUpDate,
                    onChanged: (d) => setState(() => _followUpDate = d),
                  ),
                ),
                AppFormField(
                  label: 'Follow-up time',
                  child: AppTimeField(
                    value: _followUpTime,
                    onChanged: (t) => setState(() => _followUpTime = t),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
