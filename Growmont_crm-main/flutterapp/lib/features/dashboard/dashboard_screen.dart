import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user.dart';
import '../../models/interaction.dart';
import '../../models/reminder.dart';
import '../../models/sale.dart';
import '../auth/auth_provider.dart';
import '../interactions/widgets/add_interaction_modal.dart';
import '../sales/widgets/add_sale_modal.dart';
import '../reminders/widgets/add_reminder_modal.dart';
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

  // --- Modal Helpers ---
  Future<void> _openAddInteraction(AppUser? user, {Interaction? existing}) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddInteractionModal(existing: existing, currentUser: user),
    );
    if (ok == true) _loadData();
  }

  Future<void> _openAddSale(AppUser? user, {Sale? existing}) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddSaleModal(existing: existing, currentUser: user),
    );
    if (ok == true) _loadData();
  }

  Future<void> _openAddReminder(AppUser? user, {Reminder? existing}) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddReminderModal(existing: existing, currentUser: user),
    );
    if (ok == true) _loadData();
  }

  // --- Delete Helpers ---
  Future<void> _deleteInteractionItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Follow-up'),
        content: const Text('Are you sure you want to delete this follow-up interaction?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final parsedId = int.tryParse(id);
        if (parsedId != null && parsedId > 0) {
          await ref.read(apiServiceProvider).deleteInteraction(parsedId);
        } else {
          await ref.read(firestoreServiceProvider).deleteInteraction(id);
        }
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Follow-up deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteSaleItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sale'),
        content: const Text('Are you sure you want to delete this sale record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final parsedId = int.tryParse(id);
        if (parsedId != null && parsedId > 0) {
          await ref.read(apiServiceProvider).deleteSale(parsedId);
        } else {
          await ref.read(firestoreServiceProvider).deleteSale(id);
        }
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sale record deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteReminderItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete / Dismiss Reminder'),
        content: const Text('Are you sure you want to dismiss this reminder?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final parsedId = int.tryParse(id);
        if (parsedId != null && parsedId > 0) {
          await ref.read(apiServiceProvider).deleteReminder(parsedId);
        } else {
          await ref.read(firestoreServiceProvider).deleteReminder(id);
        }
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reminder completed')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to dismiss: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // --- Detail Dialogs ---
  void _showInteractionDetails(Interaction i) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppColors.primaryBlue, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(i.clientName, style: AppTypography.sectionTitle)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Contact:', i.clientContact),
              _detailRow('Follow-up Date:', '${AppFormatters.formatDate(i.followUpDate)} at ${AppFormatters.formatTime(i.followUpTime)}'),
              _detailRow('Interaction Date:', AppFormatters.formatDate(i.date)),
              _detailRow('Priority:', i.priorityDisplay ?? i.priority),
              if (i.employeeName != null && i.employeeName!.isNotEmpty)
                _detailRow('Assigned Staff:', i.employeeName!),
              if (i.discussionNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Discussion Notes:', style: AppTypography.captionSemibold),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(i.discussionNotes, style: AppTypography.caption),
                ),
              ],
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy Contact',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: i.clientContact));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Contact "${i.clientContact}" copied!')),
              );
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showSaleDetails(Sale s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.attach_money, color: AppColors.primaryGreen, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(s.clientName, style: AppTypography.sectionTitle)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Amount:', AppFormatters.formatAmount(s.amount), valueColor: AppColors.primaryGreen, isBold: true),
              _detailRow('Product:', s.productDisplay ?? s.product),
              _detailRow('Company:', s.company),
              _detailRow('Scheme:', s.scheme),
              _detailRow('Frequency:', s.frequencyDisplay ?? s.frequency),
              _detailRow('Date:', AppFormatters.formatDate(s.date)),
              if (s.salesRepName != null && s.salesRepName!.isNotEmpty)
                _detailRow('Sales Rep:', s.salesRepName!),
              if (s.remarks.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Remarks:', style: AppTypography.captionSemibold),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(s.remarks, style: AppTypography.caption),
                ),
              ],
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy Summary',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              final summary = '${s.clientName} - ${AppFormatters.formatAmount(s.amount)} (${s.productDisplay ?? s.product})';
              Clipboard.setData(ClipboardData(text: summary));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sale summary copied to clipboard!')),
              );
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showReminderDetails(Reminder r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(r.type == 'CORPORATE' ? Icons.business : Icons.person, color: AppColors.primaryBlue, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(r.eventName, style: AppTypography.sectionTitle)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Date & Time:', '${AppFormatters.formatDate(r.date)} at ${AppFormatters.formatTime(r.time)}'),
              if (r.endTime != null && r.endTime!.isNotEmpty)
                _detailRow('End Time:', AppFormatters.formatTime(r.endTime!)),
              _detailRow('Type:', r.type),
              _detailRow('Priority:', r.priority),
              if (r.employeeName != null && r.employeeName!.isNotEmpty)
                _detailRow('Employee:', r.employeeName!),
              if (r.repeatReminder)
                _detailRow('Repeat:', '${r.repeatType} (${r.repeatDays.join(", ")})'),
              if (r.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Description:', style: AppTypography.captionSemibold),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(r.description, style: AppTypography.caption),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: AppTypography.captionSemibold),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isWide = MediaQuery.sizeOf(context).width >= 768;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back, ${user?.name ?? 'User'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (isWide) ...[
                _quickActionButton(
                  icon: Icons.add,
                  label: 'Add Sale',
                  isPrimary: true,
                  color: AppColors.primaryGreen,
                  onPressed: () => _openAddSale(user),
                ),
                const SizedBox(width: 8),
                _quickActionButton(
                  icon: Icons.add,
                  label: 'Add Follow-up',
                  isPrimary: false,
                  color: AppColors.primaryBlue,
                  onPressed: () => _openAddInteraction(user),
                ),
                const SizedBox(width: 8),
                _quickActionButton(
                  icon: Icons.add,
                  label: 'Add Reminder',
                  isPrimary: false,
                  color: AppColors.textPrimary,
                  onPressed: () => _openAddReminder(user),
                ),
              ],
            ],
          ),
          if (!isWide) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _quickActionButton(
                    icon: Icons.add,
                    label: 'Add Sale',
                    isPrimary: true,
                    color: AppColors.primaryGreen,
                    onPressed: () => _openAddSale(user),
                  ),
                  const SizedBox(width: 8),
                  _quickActionButton(
                    icon: Icons.add,
                    label: 'Add Follow-up',
                    isPrimary: false,
                    color: AppColors.primaryBlue,
                    onPressed: () => _openAddInteraction(user),
                  ),
                  const SizedBox(width: 8),
                  _quickActionButton(
                    icon: Icons.add,
                    label: 'Add Reminder',
                    isPrimary: false,
                    color: AppColors.textPrimary,
                    onPressed: () => _openAddReminder(user),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _leftColumn(user)),
                const SizedBox(width: 6),
                Expanded(child: _rightColumn(user)),
              ],
            )
          else
            Column(
              children: [
                _leftColumn(user),
                const SizedBox(height: 6),
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
                    return _InteractionTile(
                      interaction: i,
                      onTapDetails: () => _showInteractionDetails(i),
                      onEdit: () => _openAddInteraction(user, existing: i),
                      onDelete: () => _deleteInteractionItem(i.id),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 6),
        _sectionCard(
          title: 'Recent Sales',
          icon: Icons.attach_money,
          subtitle: 'Last 5 entries',
          child: _sales.isEmpty
              ? const _EmptyState('No sales yet')
              : Column(
                  children: _sales.map((s) => _SaleTile(
                    sale: s,
                    onTapDetails: () => _showSaleDetails(s),
                    onEdit: () => _openAddSale(user, existing: s),
                    onDelete: () => _deleteSaleItem(s.id),
                  )).toList(),
                ),
        ),
      ],
    );
  }

  Widget _rightColumn(AppUser? user) {
    return Column(
      children: [
        _sectionCard(
          title: 'Reminders',
          icon: Icons.notifications_outlined,
          child: _reminders.isEmpty
              ? const _EmptyState('No reminders')
              : Column(
                  children: [
                    ..._reminders.map((r) => _ReminderTile(
                          reminder: r,
                          showEmployee: user?.isAdmin == true,
                          onTapDetails: () => _showReminderDetails(r),
                          onEdit: () => _openAddReminder(user, existing: r),
                          onDelete: () => _deleteReminderItem(r.id),
                        )),
                    if (_reminders.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: InkWell(
                          onTap: () => context.push('/profile?tab=reminders'),
                          child: Text(
                            '${_reminders.length} reminder(s) • View all in reminders tab →',
                            style: TextStyle(fontSize: 11, color: AppColors.primaryBlue, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        Card(
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TodoWidget(userId: user?.id),
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
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryBlue, size: 16),
                const SizedBox(width: 6),
                Text(title, style: AppTypography.itemTitle),
                if (subtitle != null) ...[
                  const Spacer(),
                  Text(subtitle, style: AppTypography.caption),
                ],
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required Color color,
    required VoidCallback onPressed,
  }) {
    if (isPrimary) {
      return SizedBox(
        height: 38,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
      );
    }
    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17, color: color),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: color == AppColors.textPrimary
                ? AppColors.border
                : color.withValues(alpha: 0.35),
          ),
          backgroundColor: color == AppColors.textPrimary
              ? Colors.white
              : color.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(child: Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
    );
  }
}

class _InteractionTile extends StatelessWidget {
  const _InteractionTile({
    required this.interaction,
    required this.onTapDetails,
    required this.onEdit,
    required this.onDelete,
  });

  final Interaction interaction;
  final VoidCallback onTapDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  void _copyContact(BuildContext context) {
    if (interaction.clientContact.isEmpty) return;
    Clipboard.setData(ClipboardData(text: interaction.clientContact));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Contact "${interaction.clientContact}" copied!'), duration: const Duration(seconds: 2)),
    );
  }

  void _copyWhatsAppDraft(BuildContext context) {
    final msg = 'Hi ${interaction.clientName}, following up regarding our recent interaction.';
    Clipboard.setData(ClipboardData(text: msg));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('WhatsApp message draft for ${interaction.clientName} copied!'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 500;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTapDetails,
              borderRadius: BorderRadius.circular(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(interaction.clientName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                  Text(interaction.clientContact, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(AppFormatters.formatDate(interaction.followUpDate),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppColors.textPrimary)),
              Text(AppFormatters.formatTime(interaction.followUpTime),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(width: 4),
          _PriorityChip(priority: interaction.priority, label: interaction.priorityDisplay ?? interaction.priority),
          const SizedBox(width: 4),
          // --- Quick Actions Bar on Tile ---
          if (isNarrow)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16, color: Colors.grey),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onSelected: (val) {
                if (val == 'call') _copyContact(context);
                if (val == 'whatsapp') _copyWhatsAppDraft(context);
                if (val == 'details') onTapDetails();
                if (val == 'edit') onEdit();
                if (val == 'delete') onDelete();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'call',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 14, color: AppColors.primaryBlue),
                      SizedBox(width: 6),
                      Text('Copy Contact', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'whatsapp',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.primaryGreen),
                      SizedBox(width: 6),
                      Text('WhatsApp Draft', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'details',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey),
                      SizedBox(width: 6),
                      Text('View Details', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 14, color: Colors.blue),
                      SizedBox(width: 6),
                      Text('Edit', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 14, color: Colors.red),
                      SizedBox(width: 6),
                      Text('Delete', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Call / Copy Contact',
                  child: IconButton(
                    icon: const Icon(Icons.phone_outlined, size: 14, color: AppColors.primaryBlue),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => _copyContact(context),
                  ),
                ),
                Tooltip(
                  message: 'WhatsApp Draft',
                  child: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.primaryGreen),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => _copyWhatsAppDraft(context),
                  ),
                ),
                Tooltip(
                  message: 'View Details',
                  child: IconButton(
                    icon: const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: onTapDetails,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 15, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onSelected: (val) {
                    if (val == 'edit') onEdit();
                    if (val == 'delete') onDelete();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 14, color: Colors.blue),
                          SizedBox(width: 6),
                          Text('Edit', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 14, color: Colors.red),
                          SizedBox(width: 6),
                          Text('Delete', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({
    required this.sale,
    required this.onTapDetails,
    required this.onEdit,
    required this.onDelete,
  });

  final Sale sale;
  final VoidCallback onTapDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  void _copySummary(BuildContext context) {
    final summary = '${sale.clientName} - ${AppFormatters.formatAmount(sale.amount)} (${sale.productDisplay ?? sale.product})';
    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sale summary copied to clipboard!'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 500;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTapDetails,
              borderRadius: BorderRadius.circular(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sale.clientName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                  Text('${sale.company} • ${sale.productDisplay ?? sale.product}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(AppFormatters.formatAmount(sale.amount),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primaryGreen)),
              Text(AppFormatters.formatDate(sale.date),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(width: 4),
          if (isNarrow)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16, color: Colors.grey),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onSelected: (val) {
                if (val == 'copy') _copySummary(context);
                if (val == 'details') onTapDetails();
                if (val == 'edit') onEdit();
                if (val == 'delete') onDelete();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'copy',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.copy_outlined, size: 14, color: AppColors.primaryBlue),
                      SizedBox(width: 6),
                      Text('Copy Summary', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'details',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey),
                      SizedBox(width: 6),
                      Text('View Details', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 14, color: Colors.blue),
                      SizedBox(width: 6),
                      Text('Edit', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 14, color: Colors.red),
                      SizedBox(width: 6),
                      Text('Delete', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Copy Summary',
                  child: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 14, color: AppColors.primaryBlue),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => _copySummary(context),
                  ),
                ),
                Tooltip(
                  message: 'View Details',
                  child: IconButton(
                    icon: const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: onTapDetails,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 15, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onSelected: (val) {
                    if (val == 'edit') onEdit();
                    if (val == 'delete') onDelete();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 14, color: Colors.blue),
                          SizedBox(width: 6),
                          Text('Edit', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      height: 32,
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 14, color: Colors.red),
                          SizedBox(width: 6),
                          Text('Delete', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.showEmployee,
    required this.onTapDetails,
    required this.onEdit,
    required this.onDelete,
  });

  final Reminder reminder;
  final bool showEmployee;
  final VoidCallback onTapDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: priorityBackgroundColor(reminder.priority),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: priorityTextColor(reminder.priority).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTapDetails,
              borderRadius: BorderRadius.circular(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reminder.eventName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                  Text(
                    '${AppFormatters.formatDate(reminder.date)} at ${AppFormatters.formatTime(reminder.time)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (showEmployee && reminder.employeeName != null)
                    Text('👤 ${reminder.employeeName}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
          Icon(
            reminder.type == 'CORPORATE' ? Icons.business : Icons.person,
            size: 15,
            color: priorityTextColor(reminder.priority),
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'View Details',
                child: IconButton(
                  icon: const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: onTapDetails,
                ),
              ),
              Tooltip(
                message: 'Dismiss / Complete',
                child: IconButton(
                  icon: Icon(Icons.check_circle_outline, size: 14, color: priorityTextColor(reminder.priority)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: onDelete,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 15, color: Colors.grey),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 14, color: Colors.blue),
                        SizedBox(width: 6),
                        Text('Edit', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 14, color: Colors.red),
                        SizedBox(width: 6),
                        Text('Dismiss', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: priorityBackgroundColor(priority),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: priorityTextColor(priority).withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: priorityTextColor(priority))),
    );
  }
}