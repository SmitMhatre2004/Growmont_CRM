import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/client.dart';
import '../../../models/employee.dart';
import '../../../models/interaction.dart';
import '../../../models/user.dart';
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
    _followUpDate = e != null ? DateTime.parse(e.followUpDate) : DateTime.now();
    final timeParts = (e?.followUpTime ?? '10:00:00').split(':');
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
    if (_followUpDate.isBefore(_date)) {
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
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey(
                'interaction_client_${_clientId}_${_clients.length}',
              ),
              initialValue: _clients.any((c) => c.id == _clientId)
                  ? _clientId
                  : null,
              decoration: InputDecoration(
                labelText: 'Client *',
                helperText: _loadingClients
                    ? 'Loading clients...'
                    : (_employeeId != null && _clients.isEmpty)
                    ? 'No clients assigned to this employee'
                    : null,
              ),
              items: _clients
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        c.contactNumber.isNotEmpty
                            ? '${c.name} (${c.contactNumber})'
                            : c.name,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _clientId = v),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Interaction Date *'),
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
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Follow-up Date *'),
              subtitle: Text(
                AppFormatters.formatDate(
                  AppFormatters.toApiDate(_followUpDate),
                ),
              ),
              trailing: const Icon(Icons.event, size: AppSizing.iconMd),
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
              contentPadding: EdgeInsets.zero,
              title: const Text('Follow-up Time *'),
              subtitle: Text(_followUpTime.format(context)),
              trailing: const Icon(Icons.access_time, size: AppSizing.iconMd),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _followUpTime,
                );
                if (t != null) setState(() => _followUpTime = t);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            if (_isEmployee)
              TextFormField(
                initialValue: widget.currentUser?.name,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Employee'),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('employee_${_employeeId}_${_employees.length}'),
                isExpanded: true,
                initialValue: _employees.any((e) => e.id == _employeeId)
                    ? _employeeId
                    : null,
                decoration: const InputDecoration(labelText: 'Employee *'),
                items: _employees
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() => _employeeId = v);
                  _loadClientsFor(v);
                },
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: priorityChoices
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.$1,
                      child: Text(c.$2, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _priority = v!),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Discussion Notes'),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: AppSizing.controlLg,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Saving...' : 'Save Interaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
