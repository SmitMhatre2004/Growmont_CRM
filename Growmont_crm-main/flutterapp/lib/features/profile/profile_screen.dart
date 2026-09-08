import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/employee.dart';
import '../../models/interaction.dart';
import '../../models/reminder.dart';
import '../../models/sale.dart';
import '../../shared/widgets/error_state.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab == 'reminders') _tab = ProfileTab.reminders;
    if (widget.initialTab == 'interactions') _tab = ProfileTab.interactions;
    if (widget.initialTab == 'productSales') _tab = ProfileTab.sales;
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab && widget.initialTab != null) {
      if (widget.initialTab == 'reminders') _tab = ProfileTab.reminders;
      if (widget.initialTab == 'interactions') _tab = ProfileTab.interactions;
      if (widget.initialTab == 'productSales') _tab = ProfileTab.sales;
      setState(() {});
    }
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() {
      // Only take over the screen on the first load, so a pull-to-refresh
      // leaves the current profile visible.
      if (_employee == null) _loading = true;
      _error = null;
    });
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getEmployee(user.id),
        api.getEmployeeSales(user.id),
        api.getInteractions(employeeId: user.id),
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
        if (_employee != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Refresh failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  double get _totalSalesAmount {
    double total = 0;
    for (final s in _sales) {
      total += double.tryParse(s.amount) ?? 0;
    }
    return total;
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
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddReminderModal(existing: existing, currentUser: user),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_employee == null) {
      return ErrorState(
        message: _error ?? 'We could not load your profile.',
        title: _error == null ? 'Profile not found' : 'Something went wrong',
        icon: Icons.person_off_outlined,
        onRetry: _load,
      );
    }

    final isWide = MediaQuery.sizeOf(context).width >= 768;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 16 : 10,
        isWide ? 24 : 16,
        isWide ? 16 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isWide) ...[
            const Text('Profile', style: AppTypography.pageTitleMobile),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showProfilePanel = !_showProfilePanel),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(_showProfilePanel ? 'Hide Info' : 'My Info'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showReminderModal(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Reminder'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text('Profile', style: AppTypography.pageTitle),
                ),
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
                      SizedBox(
                        width: 280,
                        child: _ProfileInfoPanel(
                          employee: _employee!,
                          salesCount: _sales.length,
                          interactionsCount: _interactions.length,
                          remindersCount: _reminders.length,
                          totalSales: _totalSalesAmount,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: _tabContent()),
                    ],
                  )
                : Column(
                    children: [
                      if (_showProfilePanel) ...[
                        _ProfileInfoPanel(
                          employee: _employee!,
                          salesCount: _sales.length,
                          interactionsCount: _interactions.length,
                          remindersCount: _reminders.length,
                          totalSales: _totalSalesAmount,
                        ),
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
                _tabChip('Product Sales', ProfileTab.sales, _sales.length),
                _tabChip('Interactions', ProfileTab.interactions, _interactions.length),
                _tabChip('Reminders', ProfileTab.reminders, _reminders.length),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primaryGreen,
              child: switch (_tab) {
                ProfileTab.sales => _salesTab(),
                ProfileTab.interactions => _interactionsTab(),
                ProfileTab.reminders => _remindersTab(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 36, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  Text(message, style: AppTypography.itemSubtitle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, ProfileTab tab, int count) {
    final selected = _tab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('$label ($count)'),
        selected: selected,
        onSelected: (_) => setState(() => _tab = tab),
        selectedColor: AppColors.primaryGreen,
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey.shade700),
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _salesTab() {
    if (_sales.isEmpty) {
      return _emptyState(Icons.shopping_bag_outlined, 'No sales records found');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _sales.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final s = _sales[i];
        final prod = (s.productDisplay != null && s.productDisplay!.isNotEmpty)
            ? s.productDisplay!
            : s.product;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: Text(
                  prod,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E40AF),
                  ),
                ),
              ),
              Expanded(
                child: Text(s.clientName, style: AppTypography.itemTitle, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(AppFormatters.formatDate(s.date), style: AppTypography.caption),
              ],
            ),
          ),
          trailing: Text(
            AppFormatters.formatAmount(s.amount),
            style: AppTypography.amount,
          ),
        );
      },
    );
  }

  Widget _interactionsTab() {
    if (_interactions.isEmpty) {
      return _emptyState(Icons.forum_outlined, 'No interactions found');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _interactions.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final item = _interactions[i];
        final priorityLabel = (item.priorityDisplay != null && item.priorityDisplay!.isNotEmpty)
            ? item.priorityDisplay!
            : item.priority;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Text(item.clientName, style: AppTypography.itemTitle),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                if (item.clientContact.isNotEmpty) ...[
                  const Icon(Icons.phone_outlined, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text(item.clientContact, style: AppTypography.itemSubtitle),
                  const SizedBox(width: 10),
                ],
                const Icon(Icons.event_outlined, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Text('Follow-up: ${AppFormatters.formatDate(item.followUpDate)}', style: AppTypography.caption),
              ],
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: priorityBackgroundColor(item.priority),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              priorityLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: priorityTextColor(item.priority),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _remindersTab() {
    if (_reminders.isEmpty) {
      return _emptyState(Icons.notifications_outlined, 'No reminders found');
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _reminders.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final r = _reminders[i];
        final isCorp = r.type == 'CORPORATE';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: isCorp ? const Color(0xFFEFF6FF) : const Color(0xFFFAF5FF),
            child: Icon(
              isCorp ? Icons.business : Icons.person,
              color: isCorp ? const Color(0xFF2563EB) : const Color(0xFF9333EA),
              size: 18,
            ),
          ),
          title: Text(r.eventName, style: AppTypography.itemTitle),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule_outlined, size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${AppFormatters.formatDate(r.date)} at ${AppFormatters.formatTime(r.time)}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                if (r.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(r.description, style: AppTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          trailing: MediaQuery.sizeOf(context).width < 500
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: priorityBackgroundColor(r.priority),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.priority.replaceAll(' Priority', ''),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: priorityTextColor(r.priority),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                      padding: EdgeInsets.zero,
                      onSelected: (val) {
                        if (val == 'edit') _showReminderModal(existing: r);
                        if (val == 'delete') _deleteReminder(r.id);
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 16, color: Color(0xFF2563EB)),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 16, color: Color(0xFFDC2626)),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Color(0xFFDC2626))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: priorityBackgroundColor(r.priority),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.priority.replaceAll(' Priority', ''),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: priorityTextColor(r.priority),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF2563EB)),
                      tooltip: 'Edit Reminder',
                      onPressed: () => _showReminderModal(existing: r),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                      tooltip: 'Delete Reminder',
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
  const _ProfileInfoPanel({
    required this.employee,
    required this.salesCount,
    required this.interactionsCount,
    required this.remindersCount,
    required this.totalSales,
  });

  final Employee employee;
  final int salesCount;
  final int interactionsCount;
  final int remindersCount;
  final double totalSales;

  @override
  Widget build(BuildContext context) {
    final isAdmin = employee.role.toLowerCase() == 'admin';
    final avatarUrl = AppConfig.mediaUrl(employee.avatar);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
                  backgroundImage:
                      avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          employee.initials,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryGreen,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employee.name, style: AppTypography.itemTitle),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isAdmin ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isAdmin ? const Color(0xFFBFDBFE) : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Text(
                          employee.role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: isAdmin ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('ACTIVITY', style: AppTypography.overline),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _statTile('Sales', '$salesCount',
                      const Color(0xFF16A34A), const Color(0xFFF0FDF4)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statTile('Interactions', '$interactionsCount',
                      const Color(0xFF9333EA), const Color(0xFFFAF5FF)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statTile('Reminders', '$remindersCount',
                      const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL SALES',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Color(0xFF166534),
                    ),
                  ),
                  Text(
                    AppFormatters.formatAmount(totalSales.toString()),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('MAIN INFO', style: AppTypography.overline),
            const SizedBox(height: 10),
            _infoField('Gender', employee.genderDisplay),
            _infoField('Birthday', AppFormatters.formatDate(employee.dob)),
            const SizedBox(height: 18),
            const Text('CONTACT INFO', style: AppTypography.overline),
            const SizedBox(height: 10),
            _infoField('Email', employee.email),
            _infoField('Mobile', employee.mobileNo.isNotEmpty ? employee.mobileNo : 'Not provided'),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, Color accent, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: accent.withValues(alpha: 0.85),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _infoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.captionSemibold),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
