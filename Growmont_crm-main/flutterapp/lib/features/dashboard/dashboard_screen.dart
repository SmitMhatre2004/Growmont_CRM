import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user.dart';
import '../../models/interaction.dart';
import '../../models/reminder.dart';
import '../../models/sale.dart';
import '../auth/auth_provider.dart';
import 'todo_widget.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Sale> _sales = [];
  List<Interaction> _interactions = [];
  List<Reminder> _reminders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getSales(),
        api.getInteractions(),
        api.getReminders(),
      ]);
      if (mounted) {
        setState(() {
          _sales = (results[0] as List<Sale>).take(5).toList();
          _interactions = results[1] as List<Interaction>;
          _reminders = results[2] as List<Reminder>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isWide = MediaQuery.sizeOf(context).width >= 768;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back, ${user?.name ?? 'User'}!',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          const Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 24),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _leftColumn(user)),
                const SizedBox(width: 24),
                Expanded(child: _rightColumn(user)),
              ],
            )
          else
            Column(
              children: [
                _leftColumn(user),
                const SizedBox(height: 24),
                _rightColumn(user),
              ],
            ),
        ],
      ),
    );
  }

  Widget _leftColumn(AppUser? user) {
    return Column(
      children: [
        _sectionCard(
          title: 'Upcoming Follow-ups',
          icon: Icons.calendar_today,
          child: _interactions.isEmpty
              ? const _EmptyState('No upcoming follow-ups')
              : Column(
                  children: _interactions.take(5).map((i) {
                    return _InteractionTile(interaction: i);
                  }).toList(),
                ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          title: 'Recent Sales',
          icon: Icons.attach_money,
          subtitle: 'Last 5 entries',
          child: _sales.isEmpty
              ? const _EmptyState('No sales yet')
              : Column(
                  children: _sales.map((s) => _SaleTile(sale: s)).toList(),
                ),
        ),
      ],
    );
  }

  Widget _rightColumn(AppUser? user) {
    return Column(
      children: [
        InkWell(
          onTap: () => context.push('/profile?tab=reminders'),
          borderRadius: BorderRadius.circular(16),
          child: _sectionCard(
            title: 'Reminders',
            icon: Icons.notifications_outlined,
            child: _reminders.isEmpty
                ? const _EmptyState('No reminders')
                : Column(
                    children: [
                      ..._reminders.map((r) => _ReminderTile(
                            reminder: r,
                            showEmployee: user?.isAdmin == true,
                          )),
                      if (_reminders.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${_reminders.length} reminder(s) • Tap to manage',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: Colors.yellow.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TodoWidget(userId: user?.id ?? 0),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryBlue, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const Spacer(),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(message, style: TextStyle(color: Colors.grey.shade500))),
    );
  }
}

class _InteractionTile extends StatelessWidget {
  const _InteractionTile({required this.interaction});
  final Interaction interaction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(interaction.clientName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(interaction.clientContact, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(AppFormatters.formatDate(interaction.followUpDate),
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              Text(AppFormatters.formatTime(interaction.followUpTime),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
          const SizedBox(width: 8),
          _PriorityChip(priority: interaction.priority, label: interaction.priorityDisplay ?? interaction.priority),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sale.clientName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${sale.company} • ${sale.productDisplay ?? sale.product}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(AppFormatters.formatAmount(sale.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
              Text(AppFormatters.formatDate(sale.date),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.showEmployee});
  final Reminder reminder;
  final bool showEmployee;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: priorityBackgroundColor(reminder.priority),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: priorityTextColor(reminder.priority).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reminder.eventName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  '${AppFormatters.formatDate(reminder.date)} at ${AppFormatters.formatTime(reminder.time)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (showEmployee && reminder.employeeName != null)
                  Text('👤 ${reminder.employeeName}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Icon(
            reminder.type == 'CORPORATE' ? Icons.business : Icons.person,
            size: 18,
            color: priorityTextColor(reminder.priority),
          ),
        ],
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority, required this.label});
  final String priority;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: priorityBackgroundColor(priority),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: priorityTextColor(priority).withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: priorityTextColor(priority))),
    );
  }
}