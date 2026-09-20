import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/excel/excel_io.dart';
import '../../core/io/record_import.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/employee.dart';
import '../../models/interaction.dart';
import '../../models/reminder.dart';
import '../../models/sale.dart';
import '../../shared/widgets/error_state.dart';
import '../auth/auth_provider.dart';
import '../reminders/reminders_excel.dart';
import '../reminders/widgets/add_reminder_modal.dart';
import 'widgets/data_location_card.dart';
import 'widgets/sync_status_card.dart';
import 'widgets/update_card.dart';

enum ProfileTab { sales, interactions, reminders, system }

/// True on the desktop platforms this app ships an installer for — gates
/// the self-update card and the local data-location card, neither of
/// which make sense on mobile/web.
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

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
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
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
        // This screen always shows the signed-in user's own profile, so
        // prefer their live account name/email/photo (e.g. from Google)
        // over the employee record, which usually has none of these set.
        var employee = results[0] as Employee;
        if (user.avatar != null || user.name.isNotEmpty) {
          employee = employee.copyWith(
            name: user.name.isNotEmpty ? user.name : null,
            email: user.email.isNotEmpty ? user.email : null,
            avatar: user.avatar,
          );
        }
        setState(() {
          _employee = employee;
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
            SnackBar(
              content: Text('Refresh failed: $e'),
              backgroundColor: AppColors.danger,
            ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
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

  Future<void> _exportReminders() async {
    try {
      final savedPath = await ExcelIO.exportWorkbook(
        filename: 'reminders_export.xlsx',
        sheetName: 'Reminders',
        headers: remindersExcelHeaders,
        rows: _reminders.map(reminderExportRow).toList(),
        shareText: 'Reminders Export',
      );
      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $savedPath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _importReminders() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final rows = await ExcelIO.readDataRows(result.files.single.path!);
      final currentUserName =
          ref.read(authProvider).user?.name ?? 'Team Member';
      final api = ref.read(firestoreServiceProvider);

      final outcome = await runRecordImport(
        payloads: rows
            .map(
              (r) =>
                  reminderImportPayload(r, currentUserName: currentUserName),
            )
            .nonNulls,
        existingIdBySignature: {
          for (final r in _reminders) reminderSignatureOf(r): r.id,
        },
        signatureFields: remindersSignatureFields,
        create: api.createReminder,
        update: api.updateReminder,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outcome.describe('reminder'))),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
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

    final isMobile = AppLayout.isMobile(context);
    final isWide = !isMobile;
    final size = MediaQuery.sizeOf(context);
    final isShort = size.height < 450;
    final isLandscapeOrWide = size.width >= 500;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showSideBySide =
            isWide || (_showProfilePanel && constraints.maxWidth >= 650);

        Widget titleAndActions;
        if (isWide || isLandscapeOrWide) {
          titleAndActions = Row(
            children: [
              Text(
                'Profile',
                style: isWide
                    ? AppTypography.pageTitle
                    : AppTypography.pageTitleMobile,
              ),
              const Spacer(),
              if (!isWide) ...[
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showProfilePanel = !_showProfilePanel),
                  icon: const Icon(
                    Icons.person_outline,
                    size: AppSizing.iconMd,
                  ),
                  label: Text(_showProfilePanel ? 'Hide Info' : 'My Info'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: isShort ? VisualDensity.compact : null,
                    padding: isShort
                        ? const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              FilledButton.icon(
                onPressed: () => _showReminderModal(),
                icon: Icon(
                  Icons.add,
                  size: isWide ? AppSizing.iconLg : AppSizing.iconMd,
                ),
                label: const Text('Add Reminder'),
                style: FilledButton.styleFrom(
                  visualDensity: isShort ? VisualDensity.compact : null,
                  padding: isShort
                      ? const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        )
                      : null,
                ),
              ),
            ],
          );
        } else {
          titleAndActions = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Profile', style: AppTypography.pageTitleMobile),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(
                        () => _showProfilePanel = !_showProfilePanel,
                      ),
                      icon: const Icon(
                        Icons.person_outline,
                        size: AppSizing.iconMd,
                      ),
                      label: Text(_showProfilePanel ? 'Hide Info' : 'My Info'),
                      style: OutlinedButton.styleFrom(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showReminderModal(),
                      icon: const Icon(Icons.add, size: AppSizing.iconMd),
                      label: const Text('Add Reminder'),
                      style: FilledButton.styleFrom(),
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        final content = Padding(
          padding: EdgeInsets.fromLTRB(
            isWide ? 24 : (isShort ? 12 : 16),
            isShort ? 6 : (isWide ? 16 : 10),
            isWide ? 24 : (isShort ? 12 : 16),
            isShort ? 6 : (isWide ? 16 : 12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleAndActions,
              SizedBox(height: isShort ? AppSpacing.sm : AppSpacing.lg),
              Expanded(
                child: showSideBySide
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
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: _tabContent(isShort: isShort)),
                        ],
                      )
                    : (_showProfilePanel
                        ? _ProfileInfoPanel(
                            employee: _employee!,
                            salesCount: _sales.length,
                            interactionsCount: _interactions.length,
                            remindersCount: _reminders.length,
                            totalSales: _totalSalesAmount,
                          )
                        : _tabContent(isShort: isShort)),
              ),
            ],
          ),
        );

        final minComfortHeight = showSideBySide ? 320.0 : 280.0;

        if (constraints.maxHeight.isFinite &&
            constraints.maxHeight < minComfortHeight) {
          return SingleChildScrollView(
            child: SizedBox(
              height: minComfortHeight,
              child: content,
            ),
          );
        }

        return content;
      },
    );
  }

  Widget _reminderImportExportRow({bool isShort = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        isShort ? AppSpacing.xs : AppSpacing.md,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _exportReminders,
              icon: Icon(
                Icons.download_outlined,
                size: isShort ? AppSizing.iconSm : AppSizing.iconMd,
              ),
              label: const Text('Export'),
              style: OutlinedButton.styleFrom(
                visualDensity: isShort ? VisualDensity.compact : null,
                padding: isShort
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                    : null,
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                backgroundColor: AppColors.surface,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _importReminders,
              icon: Icon(
                Icons.upload_outlined,
                size: isShort ? AppSizing.iconSm : AppSizing.iconMd,
              ),
              label: const Text('Import'),
              style: OutlinedButton.styleFrom(
                visualDensity: isShort ? VisualDensity.compact : null,
                padding: isShort
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
                    : null,
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                backgroundColor: AppColors.surface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabContent({bool isShort = false}) {
    return Card(
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: isShort ? AppSpacing.xs : AppSpacing.md,
            ),
            child: Row(
              children: [
                _tabChip('Product Sales', ProfileTab.sales, _sales.length,
                    isShort: isShort),
                _tabChip(
                  'Interactions',
                  ProfileTab.interactions,
                  _interactions.length,
                  isShort: isShort,
                ),
                _tabChip('Reminders', ProfileTab.reminders, _reminders.length,
                    isShort: isShort),
                _tabChip('System', ProfileTab.system, 0,
                    showCount: false, isShort: isShort),
              ],
            ),
          ),
          if (_tab == ProfileTab.reminders)
            _reminderImportExportRow(isShort: isShort),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primaryGreen,
              child: switch (_tab) {
                ProfileTab.sales => _salesTab(),
                ProfileTab.interactions => _interactionsTab(),
                ProfileTab.reminders => _remindersTab(),
                ProfileTab.system => _systemTab(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemTab() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_isDesktop) ...[
          const UpdateCard(),
          const SizedBox(height: AppSpacing.lg),
          const DataLocationCard(),
          const SizedBox(height: AppSpacing.lg),
        ],
        const SyncStatusCard(),
      ],
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height:
                constraints.maxHeight > 140.0 ? constraints.maxHeight : 140.0,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: AppSizing.iconDisplay,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(message, style: AppTypography.itemSubtitle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(
    String label,
    ProfileTab tab,
    int count, {
    bool showCount = true,
    bool isShort = false,
  }) {
    final selected = _tab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(
        visualDensity: isShort ? VisualDensity.compact : null,
        materialTapTargetSize:
            isShort ? MaterialTapTargetSize.shrinkWrap : null,
        label: Text(showCount ? '$label ($count)' : label),
        selected: selected,
        onSelected: (_) => setState(() => _tab = tab),
        selectedColor: AppColors.primaryGreen,
        labelStyle: TextStyle(
          fontSize: isShort ? 12 : null,
          color: selected ? Colors.white : AppColors.textSecondary,
        ),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _sales.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final s = _sales[i];
        final prod = (s.productDisplay != null && s.productDisplay!.isNotEmpty)
            ? s.productDisplay!
            : s.product;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSelected,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppAccents.blueTint),
                ),
                child: Text(
                  prod,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppAccents.blueLabel,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  s.clientName,
                  style: AppTypography.itemTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: AppSizing.iconXs,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    AppFormatters.formatDate(s.date),
                    style: AppTypography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _interactions.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final item = _interactions[i];
        final priorityLabel =
            (item.priorityDisplay != null && item.priorityDisplay!.isNotEmpty)
            ? item.priorityDisplay!
            : item.priority;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          title: Text(item.clientName, style: AppTypography.itemTitle),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                if (item.clientContact.isNotEmpty) ...[
                  const Icon(
                    Icons.phone_outlined,
                    size: AppSizing.iconXs,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      item.clientContact,
                      style: AppTypography.itemSubtitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                const Icon(
                  Icons.event_outlined,
                  size: AppSizing.iconXs,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    'Follow-up: ${AppFormatters.formatDate(item.followUpDate)}',
                    style: AppTypography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          trailing: Container(
            width: 72,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: priorityBackgroundColor(item.priority),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              priorityLabel,
              textAlign: TextAlign.center,
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _reminders.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final r = _reminders[i];
        final isCorp = r.type == 'CORPORATE';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: isCorp
                ? AppColors.surfaceSelected
                : AppAccents.purpleSoft,
            child: Icon(
              isCorp ? Icons.business : Icons.person,
              color: isCorp ? AppColors.info : AppAccents.purpleBase,
              size: AppSizing.iconMd,
            ),
          ),
          title: Text(r.eventName, style: AppTypography.itemTitle),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      size: AppSizing.iconXs,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '${AppFormatters.formatDate(r.date)} at ${AppFormatters.formatTime(r.time)}',
                        style: AppTypography.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (r.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    r.description,
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          trailing: MediaQuery.sizeOf(context).width < 500
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: priorityBackgroundColor(r.priority),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        r.priority.replaceAll(' Priority', ''),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: priorityTextColor(r.priority),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        size: AppSizing.iconMd,
                        color: AppColors.textSecondary,
                      ),
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
                              Icon(
                                Icons.edit_outlined,
                                size: AppSizing.iconSm,
                                color: AppColors.info,
                              ),
                              SizedBox(width: AppSpacing.sm),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: AppSizing.iconSm,
                                color: AppColors.danger,
                              ),
                              SizedBox(width: AppSpacing.sm),
                              Text(
                                'Delete',
                                style: TextStyle(color: AppColors.danger),
                              ),
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
                      width: 72,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: priorityBackgroundColor(r.priority),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        r.priority.replaceAll(' Priority', ''),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: priorityTextColor(r.priority),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: AppSizing.iconMd,
                        color: AppColors.info,
                      ),
                      tooltip: 'Edit Reminder',
                      onPressed: () => _showReminderModal(existing: r),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: AppSizing.iconMd,
                        color: AppColors.danger,
                      ),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primaryGreen.withValues(
                    alpha: 0.12,
                  ),
                  backgroundImage: avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          employee.initials,
                          style: AppTypography.sectionTitle.copyWith(
                            color: AppColors.primaryGreen,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employee.name, style: AppTypography.itemTitle),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: isAdmin
                              ? AppColors.surfaceSelected
                              : AppAccents.greenTint,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(
                            color: isAdmin
                                ? AppAccents.blueBorder
                                : AppAccents.greenBorder,
                          ),
                        ),
                        child: Text(
                          employee.role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: isAdmin
                                ? AppAccents.blueStrong
                                : AppAccents.greenTeal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('ACTIVITY', style: AppTypography.overline),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    'Sales',
                    '$salesCount',
                    AppColors.success,
                    AppAccents.greenSoft,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _statTile(
                    'Interactions',
                    '$interactionsCount',
                    AppAccents.purpleBase,
                    AppAccents.purpleSoft,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _statTile(
                    'Reminders',
                    '$remindersCount',
                    AppColors.info,
                    AppColors.surfaceSelected,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppAccents.greenSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppAccents.greenBorderSoft),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL SALES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppAccents.greenDeep,
                    ),
                  ),
                  Text(
                    AppFormatters.formatAmount(totalSales.toString()),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppAccents.greenStrong,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('MAIN INFO', style: AppTypography.overline),
            const SizedBox(height: AppSpacing.md),
            _infoField('Gender', employee.genderDisplay),
            _infoField('Birthday', AppFormatters.formatDate(employee.dob)),
            const SizedBox(height: AppSpacing.xl),
            const Text('CONTACT INFO', style: AppTypography.overline),
            const SizedBox(height: AppSpacing.md),
            _infoField('Email', employee.email),
            _infoField(
              'Mobile',
              employee.mobileNo.isNotEmpty ? employee.mobileNo : 'Not provided',
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, Color accent, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.metricMedium.copyWith(color: accent),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
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
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.captionSemibold),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceHeader,
              borderRadius: BorderRadius.circular(AppRadius.md),
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
