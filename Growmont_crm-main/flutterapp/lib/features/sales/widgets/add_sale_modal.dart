import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/client.dart';
import '../../../models/employee.dart';
import '../../../models/sale.dart';
import '../../../models/user.dart';
import '../../../shared/widgets/app_modal_shell.dart';

class AddSaleModal extends ConsumerStatefulWidget {
  const AddSaleModal({
    super.key,
    this.existing,
    this.currentUser,
    this.defaultProduct,
  });

  final Sale? existing;
  final AppUser? currentUser;
  final String? defaultProduct;

  @override
  ConsumerState<AddSaleModal> createState() => _AddSaleModalState();
}

class _AddSaleModalState extends ConsumerState<AddSaleModal> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late TextEditingController _company;
  late TextEditingController _scheme;
  late TextEditingController _amount;
  late TextEditingController _remarks;
  String _product = 'MF';
  String _frequency = 'M';
  String? _salesRep;
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
    _company = TextEditingController(text: e?.company ?? '');
    _scheme = TextEditingController(text: e?.scheme ?? '');
    _amount = TextEditingController(text: e?.amount ?? '');
    _remarks = TextEditingController(text: e?.remarks ?? '');
    _product =
        e?.product ??
        (widget.defaultProduct != null && widget.defaultProduct != 'ALL'
            ? widget.defaultProduct!
            : 'MF');
    _frequency = e?.frequency ?? 'M';
    _isEmployee = widget.currentUser?.role == UserRole.employee;
    _salesRep = e?.salesRep ?? (_isEmployee ? widget.currentUser?.id : null);
    _clientId = e?.clientId;
    _loadEmployees();
    if (_isEmployee) _loadClientsFor(_salesRep);
  }

  Future<void> _loadEmployees() async {
    if (_isEmployee) return;
    try {
      final list = await ref.read(apiServiceProvider).getEmployeesDropdown();
      if (mounted) {
        setState(() {
          _employees = list;
          if (_salesRep == null ||
              !_employees.any((emp) => emp.id == _salesRep)) {
            if (_employees.isNotEmpty) {
              final userInList = _employees.any(
                (emp) => emp.id == widget.currentUser?.id,
              );
              _salesRep = userInList
                  ? widget.currentUser?.id
                  : _employees.first.id;
            } else {
              _salesRep = null;
            }
          }
        });
      }
    } catch (_) {}
    _loadClientsFor(_salesRep);
  }

  /// A sale can only be booked against a client owned by the chosen sales
  /// rep, so the client list is reloaded whenever the rep changes.
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
    _company.dispose();
    _scheme.dispose();
    _amount.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_salesRep == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a sales representative')),
      );
      return;
    }
    if (_clientId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a client')));
      return;
    }

    final client = _clients.firstWhere((c) => c.id == _clientId);
    final salesRepName = _isEmployee
        ? widget.currentUser?.name
        : _employees.firstWhere((e) => e.id == _salesRep).name;
    setState(() => _loading = true);
    final payload = {
      'date': AppFormatters.toApiDate(_date),
      'client_name': client.name,
      'client_id': client.id,
      'sales_rep': _salesRep,
      'sales_rep_name': ?salesRepName,
      'product': _product,
      'company': _company.text.trim(),
      'scheme': _scheme.text.trim(),
      'amount': _amount.text.trim(),
      'frequency': _frequency,
      'remarks': _remarks.text.trim(),
    };

    try {
      final api = ref.read(apiServiceProvider);
      if (widget.existing != null) {
        await api.updateSale(widget.existing!.id, payload);
      } else {
        await api.createSale(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
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
      title: widget.existing != null ? 'Edit Sale' : 'Add New Sale',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date *',
                  suffixIcon: Icon(
                    Icons.calendar_today,
                    size: AppSizing.iconMd,
                  ),
                ),
                child: Text(
                  AppFormatters.formatDate(AppFormatters.toApiDate(_date)),
                  style: AppTypography.input,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_isEmployee)
              TextFormField(
                initialValue: widget.currentUser?.name,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Sales Representative *',
                ),
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('sales_rep_${_salesRep}_${_employees.length}'),
                isExpanded: true,
                initialValue: _employees.any((e) => e.id == _salesRep)
                    ? _salesRep
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Sales Representative *',
                ),
                items: _employees
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(
                          '${e.name} (${e.role})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() => _salesRep = v);
                  _loadClientsFor(v);
                },
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              key: ValueKey('sale_client_${_clientId}_${_clients.length}'),
              isExpanded: true,
              initialValue: _clients.any((c) => c.id == _clientId)
                  ? _clientId
                  : null,
              decoration: InputDecoration(
                labelText: 'Client *',
                helperText: _loadingClients
                    ? 'Loading clients...'
                    : (_salesRep != null && _clients.isEmpty)
                    ? 'No clients assigned to this employee'
                    : null,
              ),
              items: _clients
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _clientId = v),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            modalFieldPair(
              context,
              DropdownButtonFormField<String>(
                initialValue: _product,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Product *'),
                items: productCategories
                    .where((c) => c.$1 != 'ALL')
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.$1,
                        child: Text(c.$2, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _product = v!),
              ),
              TextFormField(
                controller: _company,
                decoration: const InputDecoration(labelText: 'Company *'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _scheme,
              decoration: const InputDecoration(labelText: 'Scheme *'),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            modalFieldPair(
              context,
              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount *'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Frequency *'),
                items: frequencyChoices
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.$1,
                        child: Text(c.$2, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _frequency = v!),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _remarks,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Remarks'),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: AppSizing.controlLg,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Saving...' : 'Save Sale'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
