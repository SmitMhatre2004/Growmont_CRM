import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/client.dart';
import '../../../models/employee.dart';
import '../../../models/user.dart';

class AddClientModal extends ConsumerStatefulWidget {
  const AddClientModal({super.key, this.existing, this.currentUser});

  final Client? existing;
  final AppUser? currentUser;

  @override
  ConsumerState<AddClientModal> createState() => _AddClientModalState();
}

class _AddClientModalState extends ConsumerState<AddClientModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _contactNumber;
  String? _employeeId;
  List<EmployeeDropdown> _employees = [];
  bool _loadingEmployees = true;
  bool _loading = false;
  bool _isEmployee = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _isEmployee = widget.currentUser?.role == UserRole.employee;
    _name = TextEditingController(text: c?.name ?? '');
    _contactNumber = TextEditingController(text: c?.contactNumber ?? '');
    _employeeId = _isEmployee
        ? widget.currentUser?.id
        : (c?.employeeId.isNotEmpty == true ? c?.employeeId : null);
    if (_isEmployee) {
      _loadingEmployees = false;
    } else {
      _loadEmployees();
    }
  }

  Future<void> _loadEmployees() async {
    try {
      final list = await ref.read(apiServiceProvider).getEmployeesDropdown();
      if (mounted) {
        setState(() {
          _employees = list;
          _loadingEmployees = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _contactNumber.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please assign this client to an employee'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    final employeeName = _isEmployee
        ? widget.currentUser?.name
        : _employees.firstWhere((e) => e.id == _employeeId).name;
    final map = <String, dynamic>{
      'name': _name.text.trim(),
      'contact_number': _contactNumber.text.trim(),
      'employee_id': _employeeId,
      'employee_name': employeeName,
    };

    try {
      final api = ref.read(apiServiceProvider);
      if (widget.existing != null) {
        await api.updateClient(widget.existing!.id, map);
      } else {
        await api.createClient(map);
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
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizing.modalMaxWidth),
        child: SingleChildScrollView(
          padding: AppLayout.modalPadding,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.existing != null ? 'Edit Client' : 'Add Client',
                      style: AppTypography.sectionTitle,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Client Name *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _contactNumber,
                  decoration: const InputDecoration(
                    labelText: 'Contact Number *',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_isEmployee)
                  TextFormField(
                    initialValue: widget.currentUser?.name,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Assigned Employee',
                      helperText: 'Clients you add are assigned to you',
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('client_owner_${_employeeId}_${_employees.length}'),
                    initialValue: _employees.any((e) => e.id == _employeeId)
                        ? _employeeId
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Assigned Employee *',
                      helperText: _loadingEmployees
                          ? 'Loading employees...'
                          : 'Each client can only be assigned to one employee',
                    ),
                    items: _employees
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _employeeId = v),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Required' : null,
                  ),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  width: double.infinity,
                  height: AppSizing.controlLg,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                    ),
                    child: Text(_loading ? 'Saving...' : 'Save Client'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
