import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';
import '../../../models/sale.dart';
import '../../../models/user.dart';

class AddSaleModal extends ConsumerStatefulWidget {
  const AddSaleModal({super.key, this.existing, this.currentUser});

  final Sale? existing;
  final AppUser? currentUser;

  @override
  ConsumerState<AddSaleModal> createState() => _AddSaleModalState();
}

class _AddSaleModalState extends ConsumerState<AddSaleModal> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late TextEditingController _clientName;
  late TextEditingController _company;
  late TextEditingController _scheme;
  late TextEditingController _amount;
  late TextEditingController _remarks;
  String _product = 'MF';
  String _frequency = 'M';
  String? _salesRep;
  List<EmployeeDropdown> _employees = [];
  bool _loading = false;
  bool _isEmployee = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e != null ? DateTime.parse(e.date) : DateTime.now();
    _clientName = TextEditingController(text: e?.clientName ?? '');
    _company = TextEditingController(text: e?.company ?? '');
    _scheme = TextEditingController(text: e?.scheme ?? '');
    _amount = TextEditingController(text: e?.amount ?? '');
    _remarks = TextEditingController(text: e?.remarks ?? '');
    _product = e?.product ?? 'MF';
    _frequency = e?.frequency ?? 'M';
    _salesRep = e?.salesRep ?? widget.currentUser?.id;
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

    setState(() => _loading = true);
    final payload = {
      'date': AppFormatters.toApiDate(_date),
      'client_name': _clientName.text.trim(),
      'sales_rep': _salesRep,
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
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
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
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      widget.existing != null ? 'Edit Sale' : 'Add New Sale',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              title: const Text('Date *'),
                              subtitle: Text(AppFormatters.formatDate(AppFormatters.toApiDate(_date))),
                              trailing: const Icon(Icons.calendar_today),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _date,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) setState(() => _date = picked);
                              },
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _clientName,
                              decoration: const InputDecoration(labelText: 'Client Name *'),
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_isEmployee)
                        TextFormField(
                          initialValue: widget.currentUser?.name,
                          readOnly: true,
                          decoration: const InputDecoration(labelText: 'Sales Representative *'),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _salesRep,
                          decoration: const InputDecoration(labelText: 'Sales Representative *'),
                          items: _employees
                              .map((e) => DropdownMenuItem(value: e.id, child: Text('${e.name} (${e.role})')))
                              .toList(),
                          onChanged: (v) => setState(() => _salesRep = v),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _product,
                              decoration: const InputDecoration(labelText: 'Product *'),
                              items: productCategories
                                  .where((c) => c.$1 != 'ALL')
                                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                                  .toList(),
                              onChanged: (v) => setState(() => _product = v!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _company,
                              decoration: const InputDecoration(labelText: 'Company *'),
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _scheme,
                        decoration: const InputDecoration(labelText: 'Scheme *'),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _amount,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Amount *'),
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _frequency,
                              decoration: const InputDecoration(labelText: 'Frequency *'),
                              items: frequencyChoices
                                  .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                                  .toList(),
                              onChanged: (v) => setState(() => _frequency = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _remarks,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Remarks'),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: Text(_loading ? 'Saving...' : 'Save Sale'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
