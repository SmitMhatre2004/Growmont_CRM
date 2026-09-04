import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/client.dart';
import '../../models/employee.dart';
import '../../models/sale.dart';

class EmployeeDetailScreen extends ConsumerStatefulWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});

  final int employeeId;

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  Employee? _employee;
  List<Client> _clients = [];
  List<Sale> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getEmployee(widget.employeeId),
        api.getEmployeeClients(widget.employeeId),
        api.getEmployeeSales(widget.employeeId),
      ]);
      if (mounted) {
        setState(() {
          _employee = results[0] as Employee;
          _clients = results[1] as List<Client>;
          _sales = results[2] as List<Sale>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_employee == null) return const Center(child: Text('Employee not found'));

    final emp = _employee!;
    final avatarUrl = AppConfig.mediaUrl(emp.avatar);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty ? Text(emp.name.split(' ').map((p) => p[0]).take(2).join(), style: const TextStyle(fontSize: 24)) : null,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(emp.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        Text(emp.email, style: TextStyle(color: Colors.grey.shade600)),
                        Text('${emp.mobileNo} • ${emp.genderDisplay} • ${emp.role}'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          children: [
                            _statChip('Clients', emp.clientsCount),
                            _statChip('Sales', emp.salesCount),
                            _statChip('Interactions', emp.interactionsCount),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Clients', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_clients.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No clients')))
          else
            Card(
              child: Column(
                children: _clients.map((c) => ListTile(
                  title: Text(c.name),
                  subtitle: Text(c.contactNumber),
                )).toList(),
              ),
            ),
          const SizedBox(height: 24),
          const Text('Sales', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_sales.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No sales')))
          else
            Card(
              child: Column(
                children: _sales.map((s) => ListTile(
                  title: Text(s.clientName),
                  subtitle: Text('${s.productDisplay} • ${AppFormatters.formatDate(s.date)}'),
                  trailing: Text(AppFormatters.formatAmount(s.amount), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count) {
    return Chip(label: Text('$label: $count'));
  }
}
