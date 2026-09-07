import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';
import '../../../models/interaction.dart';
import '../../../models/reminder.dart';
import '../../../models/sale.dart';
import '../auth/auth_provider.dart';
import '../reminders/widgets/add_reminder_modal.dart';

enum ProfileTab { sales, interactions, reminders }

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Employee? _employee;
  List<Sale> _sales = [];
  List<Interaction> _interactions = [];
  List<Reminder> _reminders = [];
  ProfileTab _tab = ProfileTab.reminders;
  bool _loading = true;
  bool _showProfilePanel = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab == 'reminders') _tab = ProfileTab.reminders;
    if (widget.initialTab == 'interactions') _tab = ProfileTab.interactions;
    if (widget.initialTab == 'productSales') _tab = ProfileTab.sales;
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getEmployee(user.id),
        api.getEmployeeSales(user.id),
        api.getInteractions(),
        api.getReminders(),
      ]);
      if (mounted) {
        setState(() {
          _employee = results[0] as Employee;
          _sales = results[1] as List<Sale>;
          _interactions = results[2] as List<Interaction>;
          _reminders = results[3] as List<Reminder>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteReminder(dynamic id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiServiceProvider).deleteReminder(id);
    _load();
  }

  Future<void> _showReminderModal({Reminder? existing}) async {
    final user = ref.read(authProvider).user;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddReminderModal(existing: existing, currentUser: user),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_employee == null) return const Center(child: Text('Profile not found'));

    final isWide = MediaQuery.sizeOf(context).width >= 768;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Profile', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              ),
              if (!isWide)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showProfilePanel = !_showProfilePanel),
                  icon: const Icon(Icons.person_outline),
                  label: Text(_showProfilePanel ? 'Hide Info' : 'My Info'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _showReminderModal(),
                icon: const Icon(Icons.add),
                label: const Text('Add Reminder'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 280, child: _ProfileInfoPanel(employee: _employee!)),
                      const SizedBox(width: 16),
                      Expanded(child: _tabContent()),
                    ],
                  )
                : Column(
                    children: [
                      if (_showProfilePanel) ...[
                        _ProfileInfoPanel(employee: _employee!),
                        const SizedBox(height: 16),
                      ],
                      Expanded(child: _tabContent()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabContent() {
    return Card(
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _tabChip('Product Sales', ProfileTab.sales),
                _tabChip('Interactions', ProfileTab.interactions),
                _tabChip('Reminders', ProfileTab.reminders),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (_tab) {
              ProfileTab.sales => _salesTab(),
              ProfileTab.interactions => _interactionsTab(),
              ProfileTab.reminders => _remindersTab(),
            },
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, ProfileTab tab) {
    final selected = _tab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _tab = tab),
        selectedColor: AppColors.primaryGreen,
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey.shade700),
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _salesTab() {
    if (_sales.isEmpty) return const Center(child: Text('No sales yet'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sales.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final s = _sales[i];
        return ListTile(
          title: Text(s.clientName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${s.productDisplay ?? s.product} • ${AppFormatters.formatDate(s.date)}'),
          trailing: Text(AppFormatters.formatAmount(s.amount),
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
        );
      },
    );
  }

  Widget _interactionsTab() {
    if (_interactions.isEmpty) return const Center(child: Text('No interactions yet'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _interactions.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final item = _interactions[i];
        return ListTile(
          title: Text(item.clientName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${item.clientContact} • Follow-up: ${AppFormatters.formatDate(item.followUpDate)}',
          ),
          trailing: Chip(
            label: Text(item.priorityDisplay ?? item.priority, style: const TextStyle(fontSize: 11)),
            backgroundColor: priorityBackgroundColor(item.priority),
          ),
        );
      },
    );
  }

  Widget _remindersTab() {
    if (_reminders.isEmpty) return const Center(child: Text('No reminders yet'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _reminders.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final r = _reminders[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: r.type == 'CORPORATE' ? Colors.blue.shade100 : Colors.purple.shade100,
            child: Icon(
              r.type == 'CORPORATE' ? Icons.business : Icons.person,
              color: r.type == 'CORPORATE' ? Colors.blue : Colors.purple,
              size: 20,
            ),
          ),
          title: Text(r.eventName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${AppFormatters.formatDate(r.date)} at ${AppFormatters.formatTime(r.time)}'
            '${r.description.isNotEmpty ? '\n${r.description}' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(
                label: Text(r.priority.replaceAll(' Priority', ''), style: const TextStyle(fontSize: 10)),
                backgroundColor: priorityBackgroundColor(r.priority),
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue),
                onPressed: () => _showReminderModal(existing: r),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteReminder(r.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileInfoPanel extends StatelessWidget {
  const _ProfileInfoPanel({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  child: Text(
                    employee.name.split(' ').map((p) => p[0]).take(2).join(),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(employee.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Main info', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _infoField('Gender', employee.genderDisplay),
            _infoField('Birthday', AppFormatters.formatDate(employee.dob)),
            const SizedBox(height: 20),
            const Text('Contact Info', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _infoField('Email', employee.email),
            _infoField('Mobile', employee.mobileNo),
          ],
        ),
      ),
    );
  }

  Widget _infoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: value,
            readOnly: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}
