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
import '../interactions/widgets/interaction_detail_modal.dart';
import '../reminders/reminders_excel.dart';
import '../reminders/widgets/add_reminder_modal.dart';
import 'widgets/account_security_card.dart';
import 'widgets/data_location_card.dart';
import 'widgets/sync_status_card.dart';
import 'widgets/update_card.dart';
import '../../shared/widgets/monogram.dart';
import '../../shared/widgets/status_badge.dart';

/// The three record lists at the foot of the profile. Account and system
/// settings are deliberately not in here: they used to be a fourth tab, which
/// hid them behind a chip that most people never pressed.
enum ProfileTab { sales, interactions, reminders }

/// True on the desktop platforms this app ships an installer for — gates
/// the local data-location card, which has no meaning on mobile/web.
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// True on the platforms that can self-update from a GitHub release:
/// Windows via the Inno Setup installer, Android via the packaged APK.
/// Kept separate from [_isDesktop] because Android shows the update card
/// but none of the other desktop-only cards.
bool get _canSelfUpdate =>
    !kIsWeb && (Platform.isWindows || Platform.isAndroid);

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
  String? _error;

  /// Anchors the records section so a deep link like `/profile?tab=reminders`
  /// can scroll to it instead of dropping the reader at the top of the page.
  final GlobalKey _recordsKey = GlobalKey();

  void _scrollToRecords() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _recordsKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: AppMotion.slow,
        curve: AppMotion.curve,
        alignment: 0.05,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialTab == 'reminders') _tab = ProfileTab.reminders;
    if (widget.initialTab == 'interactions') _tab = ProfileTab.interactions;
    if (widget.initialTab == 'productSales') _tab = ProfileTab.sales;
    // Arriving from "view all in reminders" should land on the list, not at
    // the top of a page the reader then has to scroll themselves.
    if (widget.initialTab != null) _scrollToRecords();
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
      _scrollToRecords();
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

  Future<void> _showInteractionDetail(Interaction item) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => InteractionDetailModal(
        interaction: item,
        currentUser: ref.read(authProvider).user,
        onUpdated: _load,
      ),
    );
    if (saved == true) _load();
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

    // One screen, one scroll. Everything that used to sit behind the "My Info"
    // toggle or the "System" chip is now simply on the page, in the order
    // someone reads it: who you are, then your account, then your records.
    final isMobile = AppLayout.isMobile(context);
    final gutter = isMobile ? AppSpacing.lg : AppSpacing.xxl;

    EdgeInsets band(double top, [double bottom = 0]) =>
        EdgeInsets.fromLTRB(gutter, top, gutter, bottom);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryBlue,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: band(isMobile ? AppSpacing.lg : AppSpacing.xl),
            sliver: SliverToBoxAdapter(child: _pageHeader(isMobile)),
          ),
          SliverPadding(
            padding: band(AppSpacing.lg),
            sliver: SliverToBoxAdapter(
              child: _ProfileIdentityCard(
                employee: _employee!,
                salesCount: _sales.length,
                interactionsCount: _interactions.length,
                remindersCount: _reminders.length,
                totalSales: _totalSalesAmount,
                isMobile: isMobile,
              ),
            ),
          ),
          SliverPadding(
            padding: band(AppSpacing.xxxl),
            sliver: SliverToBoxAdapter(child: _accountSection(isMobile)),
          ),
          SliverPadding(
            padding: band(AppSpacing.xxxl, AppSpacing.md),
            sliver: SliverToBoxAdapter(child: _recordsHeader(isMobile)),
          ),
          SliverPadding(
            padding: band(0, AppSpacing.xxxl),
            sliver: _recordsSliver(),
          ),
        ],
      ),
    );
  }

  /// The page title. Reminders are created from the dashboard; this screen
  /// reads and edits what is already there.
  Widget _pageHeader(bool isMobile) {
    return Text(
      'Profile',
      style: isMobile
          ? AppTypography.pageTitleMobile
          : AppTypography.pageTitle,
    );
  }

  /// A section heading on the canvas: 18/23, with optional trailing actions.
  Widget _sectionHeader(String title, {String? subtitle, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.sectionTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle, style: AppTypography.caption),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// Account and system settings. These were the "System" tab; on a phone that
  /// chip scrolled off the end of the row, so the cards were effectively
  /// invisible. They are now a plain section of the page.
  Widget _accountSection(bool isMobile) {
    final cards = <Widget>[
      const AccountSecurityCard(),
      if (_canSelfUpdate) const UpdateCard(),
      if (_isDesktop) const DataLocationCard(),
      const SyncStatusCard(),
    ];

    Widget body;
    if (isMobile || cards.length < 2) {
      body = Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            cards[i],
          ],
        ],
      );
    } else {
      // Two columns on anything wider than a phone, so a desktop window does
      // not show four full-width cards stacked down a long page.
      final left = <Widget>[];
      final right = <Widget>[];
      for (var i = 0; i < cards.length; i++) {
        (i.isEven ? left : right).add(cards[i]);
      }
      Widget column(List<Widget> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            items[i],
          ],
        ],
      );
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: column(left)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: column(right)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Account and system',
          subtitle: 'Password, updates and how this device syncs.',
        ),
        body,
      ],
    );
  }

  /// Heading, segmented control and the reminder import/export actions.
  Widget _recordsHeader(bool isMobile) {
    return Column(
      key: _recordsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Your records',
          subtitle: 'Everything logged against your name.',
          trailing: (!isMobile && _tab == ProfileTab.reminders)
              ? _reminderImportExportRow()
              : null,
        ),
        _RecordSegments(
          selected: _tab,
          counts: {
            ProfileTab.sales: _sales.length,
            ProfileTab.interactions: _interactions.length,
            ProfileTab.reminders: _reminders.length,
          },
          onSelect: (tab) => setState(() => _tab = tab),
        ),
        if (isMobile && _tab == ProfileTab.reminders) ...[
          const SizedBox(height: AppSpacing.md),
          _reminderImportExportRow(),
        ],
      ],
    );
  }

  /// The selected record list, as a card-shaped sliver so it stays lazy inside
  /// the page scroll however many rows it holds.
  Widget _recordsSliver() {
    final sliver = switch (_tab) {
      ProfileTab.sales => _salesSliver(),
      ProfileTab.interactions => _interactionsSliver(),
      ProfileTab.reminders => _remindersSliver(),
    };
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      sliver: SliverPadding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        sliver: sliver,
      ),
    );
  }

  Widget _reminderImportExportRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: _exportReminders,
          icon: const Icon(Icons.download_outlined, size: AppSizing.iconMd),
          label: const Text('Export'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppSizing.controlSm),
            textStyle: AppTypography.buttonSmall,
            foregroundColor: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _importReminders,
          icon: const Icon(Icons.upload_outlined, size: AppSizing.iconMd),
          label: const Text('Import'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppSizing.controlSm),
            textStyle: AppTypography.buttonSmall,
            foregroundColor: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: AppSizing.iconEmptyState,
                color: AppColors.borderStrong,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(message, style: AppTypography.itemSubtitle),
            ],
          ),
        ),
      ),
    );
  }

  Widget _salesSliver() {
    if (_sales.isEmpty) {
      return _emptyState(Icons.shopping_bag_outlined, 'No sales records found');
    }
    return SliverList.separated(
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
                  border: Border.all(color: AppPalette.navy200),
                ),
                child: Text(
                  prod,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue,
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

  Widget _interactionsSliver() {
    if (_interactions.isEmpty) {
      return _emptyState(Icons.forum_outlined, 'No interactions found');
    }
    return SliverList.separated(
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
          onTap: () => _showInteractionDetail(item),
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
                    item.followUpDate.isEmpty
                        ? 'No follow-up'
                        : 'Follow-up: ${AppFormatters.formatDate(item.followUpDate)}',
                    style: AppTypography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          trailing: SizedBox(
            width: 72,
            child: Center(child: PriorityBadge(priority: priorityLabel)),
          ),
        );
      },
    );
  }

  Widget _remindersSliver() {
    if (_reminders.isEmpty) {
      return _emptyState(Icons.notifications_outlined, 'No reminders found');
    }
    return SliverList.separated(
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
                : AppColors.chatSoft,
            child: Icon(
              isCorp ? Icons.business : Icons.person,
              color: isCorp ? AppColors.info : AppColors.chat,
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
                    SizedBox(
                      width: 72,
                      child: Center(
                        child: PriorityBadge(
                          priority: r.priority.replaceAll(' Priority', ''),
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
                    SizedBox(
                      width: 72,
                      child: Center(
                        child: PriorityBadge(
                          priority: r.priority.replaceAll(' Priority', ''),
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

/// The record-list switch: three equal segments on one track.
///
/// This used to be a horizontally scrolling row of chips, which on a phone put
/// the last entry off screen. Equal segments mean every list is one tap away
/// at any width.
class _RecordSegments extends StatelessWidget {
  const _RecordSegments({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final ProfileTab selected;
  final Map<ProfileTab, int> counts;
  final ValueChanged<ProfileTab> onSelect;

  static const _labels = {
    ProfileTab.sales: 'Sales',
    ProfileTab.interactions: 'Chats',
    ProfileTab.reminders: 'Reminders',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizing.controlMd,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceHeader,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final tab in ProfileTab.values)
            Expanded(
              child: _Segment(
                label: _labels[tab]!,
                count: counts[tab] ?? 0,
                isSelected: tab == selected,
                onTap: () => onSelect(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brSm,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.transparent,
            borderRadius: AppRadius.brSm,
            border: Border.all(
              color: isSelected ? AppColors.border : Colors.transparent,
            ),
            boxShadow: isSelected ? AppShadows.xs : null,
          ),
          alignment: Alignment.center,
          child: Text(
            // The count is part of the label so the segment says how much is
            // behind it before you press it.
            count > 0 ? '$label  $count' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.buttonSmall.copyWith(
              color: isSelected ? AppColors.primaryBlue : AppColors.textCaption,
            ),
          ),
        ),
      ),
    );
  }
}

/// Who you are, what you have done, and your details - all of it on screen
/// from the moment the page opens.
///
/// This replaces the old panel that lived behind a "My Info" toggle. Hiding a
/// person's own details behind a button made the profile screen open on a list
/// of reminders and nothing else, which read as an empty page on a phone.
class _ProfileIdentityCard extends StatelessWidget {
  const _ProfileIdentityCard({
    required this.employee,
    required this.salesCount,
    required this.interactionsCount,
    required this.remindersCount,
    required this.totalSales,
    required this.isMobile,
  });

  final Employee employee;
  final int salesCount;
  final int interactionsCount;
  final int remindersCount;
  final double totalSales;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = AppConfig.mediaUrl(employee.avatar);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      padding: EdgeInsets.all(isMobile ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _identityRow(avatarUrl),
          const SizedBox(height: AppSpacing.xl),
          _activity(),
          const SizedBox(height: AppSpacing.xl),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.xl),
          const Text('YOUR DETAILS', style: AppTypography.overline),
          const SizedBox(height: AppSpacing.md),
          _details(),
        ],
      ),
    );
  }

  /// Avatar, name, role and the two things people actually need to read back
  /// to someone: their email and their mobile number.
  Widget _identityRow(String avatarUrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Monogram(
          name: employee.name,
          size: isMobile ? AppSizing.avatarMd + 8 : AppSizing.avatarLg,
          imageUrl: avatarUrl,
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                employee.name,
                style: isMobile
                    ? AppTypography.headingLargeMobile
                    : AppTypography.headingLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                employee.email,
                style: AppTypography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _roleBadge(),
      ],
    );
  }

  /// Admin is a navy badge, everyone else green: the same pair used in the
  /// employees list, so a role reads the same wherever it appears.
  Widget _roleBadge() {
    final isAdmin = employee.role.toLowerCase() == 'admin';
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isAdmin
            ? AppColors.surfaceSelected
            : AppColors.primaryGreenSoft,
        borderRadius: AppRadius.brSm,
        border: Border.all(
          color: isAdmin ? AppPalette.navy200 : AppColors.primaryGreenBorder,
        ),
      ),
      child: Text(
        employee.role.toUpperCase(),
        style: AppTypography.overline.copyWith(
          color: isAdmin ? AppColors.primaryBlue : AppColors.primaryGreenDark,
        ),
      ),
    );
  }

  /// Three counts and the money they add up to.
  Widget _activity() {
    final tiles = [
      _statTile('Sales', '$salesCount', AppStatus.won),
      _statTile('Chats', '$interactionsCount', AppStatus.chat),
      _statTile('Reminders', '$remindersCount', AppStatus.fresh),
    ];

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.primaryGreenSoft,
            borderRadius: AppRadius.brMd,
            border: Border.all(color: AppColors.primaryGreenBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL SALES',
                style: AppTypography.overline.copyWith(
                  color: AppPalette.green700,
                ),
              ),
              Text(
                AppFormatters.formatAmount(totalSales.toString()),
                style: AppTypography.amountLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Two columns on anything wider than a phone; one column on a phone, where
  /// nothing scrolls sideways.
  Widget _details() {
    final fields = [
      ('Gender', employee.genderDisplay),
      ('Birthday', AppFormatters.formatDate(employee.dob)),
      ('Email', employee.email),
      (
        'Mobile',
        employee.mobileNo.isNotEmpty ? employee.mobileNo : 'Not provided',
      ),
    ];

    if (isMobile) {
      return Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            _infoField(fields[i].$1, fields[i].$2),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final f in fields)
              SizedBox(width: columnWidth, child: _infoField(f.$1, f.$2)),
          ],
        );
      },
    );
  }

  Widget _statTile(String label, String value, StatusTone tone) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: AppRadius.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.metricMedium.copyWith(color: tone.text),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: AppTypography.overline.copyWith(color: tone.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// A label above its value, the way every other field in the product reads.
  Widget _infoField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTypography.overline),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: AppSizing.controlMd),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceHeader,
            borderRadius: AppRadius.brMd,
            border: Border.all(color: AppColors.border),
          ),
          child: Text(value, style: AppTypography.fieldValue),
        ),
      ],
    );
  }
}
