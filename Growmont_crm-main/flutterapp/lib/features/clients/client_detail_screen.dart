import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/client.dart';
import '../../models/client_transfer.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/monthly_revenue_chart.dart';
import '../auth/auth_provider.dart';
import '../interactions/widgets/interaction_detail_modal.dart';
import 'widgets/transfer_client_modal.dart';

class ClientDetailScreen extends ConsumerStatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen> {
  Client? _client;
  List<Sale> _sales = [];
  List<Interaction> _interactions = [];
  List<ClientTransfer> _transfers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_client == null) _loading = true;
      _error = null;
    });
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getClient(widget.clientId),
        api.getSales(clientId: widget.clientId),
        api.getInteractions(clientId: widget.clientId),
        api.getClientTransfers(widget.clientId),
      ]);
      if (mounted) {
        setState(() {
          _client = results[0] as Client;
          _sales = results[1] as List<Sale>;
          _interactions = results[2] as List<Interaction>;
          _transfers = results[3] as List<ClientTransfer>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
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

  bool get _isAdmin => ref.read(authProvider).user?.isAdmin ?? false;

  bool get _canTransfer {
    if (_isAdmin) return true;
    final currentUid = ref.read(authProvider).user?.id;
    return currentUid != null &&
        currentUid.isNotEmpty &&
        _client?.employeeId == currentUid;
  }

  Future<void> _openTransferModal() async {
    if (_client == null) return;
    final transferred = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => TransferClientModal(
        client: _client!,
        currentUser: ref.read(authProvider).user,
        onTransferred: (_) => _load(),
      ),
    );
    if (transferred == true) {
      _load();
    }
  }

  void _backToList() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/clients');
    }
  }

  double get _totalSalesAmount {
    double total = 0;
    for (final s in _sales) {
      total += double.tryParse(s.amount) ?? 0;
    }
    return total;
  }

  String get _ownerName {
    final client = _client!;
    if (client.employeeName?.isNotEmpty == true) return client.employeeName!;
    return client.employeeId.isNotEmpty ? client.employeeId : 'Unassigned';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_client == null) {
      return ErrorState(
        message:
            _error ??
            'This client no longer exists, or is not assigned to you.',
        title: _error == null ? 'Client not found' : 'Something went wrong',
        icon: Icons.person_off_outlined,
        onRetry: _load,
      );
    }

    final client = _client!;
    final isMobile = AppLayout.isMobile(context);
    // Two-pane detail from 900 up; below that it stays single-pane.
    final isTablet = AppLayout.isWide(context);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryGreen,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isMobile ? AppSpacing.md : AppSpacing.lg,
          isMobile ? 8 : 12,
          isMobile ? AppSpacing.md : AppSpacing.lg,
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBreadcrumb(client.name),
            const SizedBox(height: AppSpacing.sm),
            _buildProfileCard(client, isMobile),
            const SizedBox(height: AppSpacing.md),
            if (isTablet)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _buildRevenueCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildSalesHistoryCard(),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        _buildInteractionsCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildTransferHistoryCard(),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildRevenueCard(),
                  const SizedBox(height: AppSpacing.md),
                  _buildInteractionsCard(),
                  const SizedBox(height: AppSpacing.md),
                  _buildSalesHistoryCard(),
                  const SizedBox(height: AppSpacing.md),
                  _buildTransferHistoryCard(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section builders
  // ---------------------------------------------------------------------------

  Widget _buildBreadcrumb(String clientName) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: _backToList,
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: AppSizing.iconSm,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: AppSpacing.xs),
                Text(
                  'Clients',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            '/',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            clientName,
            style: AppTypography.tableCellStrong,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(Client client, bool isMobile) {
    return _card(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: isMobile ? 22 : 28,
                backgroundColor: AppColors.surfaceSelected,
                child: Text(
                  client.name.isNotEmpty ? client.name[0].toUpperCase() : 'C',
                  style: TextStyle(
                    fontSize: isMobile ? 15 : 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.name,
                      style: isMobile
                          ? AppTypography.headingLarge.copyWith(fontSize: 18)
                          : AppTypography.headingLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (client.contactNumber.isNotEmpty)
                          InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: client.contactNumber),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Phone number copied'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: _contactItem(
                              Icons.phone_outlined,
                              client.contactNumber,
                            ),
                          ),
                        _contactItem(Icons.badge_outlined, _ownerName),
                      ],
                    ),
                  ],
                ),
              ),
              if (_canTransfer) ...[
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _openTransferModal,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('Transfer'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 520;
              final revenueCard = _kpiStatCard(
                title: 'REVENUE',
                value: AppFormatters.formatAmount(_totalSalesAmount.toString()),
                icon: Icons.payments_outlined,
                accentColor: AppColors.success,
                bgColor: AppColors.primaryGreenSoft,
              );
              final salesCard = _kpiStatCard(
                title: 'SALES',
                value: '${_sales.length}',
                icon: Icons.trending_up_rounded,
                accentColor: AppColors.info,
                bgColor: AppColors.surfaceSelected,
              );
              final interactionsCard = _kpiStatCard(
                title: 'INTERACTIONS',
                value: '${_interactions.length}',
                icon: Icons.forum_outlined,
                accentColor: AppColors.chat,
                bgColor: AppColors.chatSoft,
              );

              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: revenueCard),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: salesCard),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(width: double.infinity, child: interactionsCard),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: revenueCard),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: salesCard),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: interactionsCard),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Revenue Trend', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'Booked value, last 6 months',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          MonthlyRevenueChart(
            sales: _sales,
            height: 160,
            emptyMessage: 'No sales in the last 6 months',
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Interactions', _interactions.length),
          const SizedBox(height: AppSpacing.sm),
          if (_interactions.isEmpty)
            _emptyState(Icons.forum_outlined, 'No interactions recorded')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _interactions.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final it = _interactions[i];
                return ListTile(
                  dense: true,
                  minVerticalPadding: 0,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                  ),
                  onTap: () => _showInteractionDetail(it),
                  title: Row(
                    children: [
                      Text(
                        AppFormatters.formatDate(it.date),
                        style: AppTypography.itemTitle.copyWith(fontSize: 13),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _buildPriorityBadge(it.priority),
                    ],
                  ),
                  subtitle: it.discussionNotes.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            it.discussionNotes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption,
                          ),
                        )
                      : null,
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: AppSizing.iconMd,
                    color: AppColors.textMuted,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSalesHistoryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            'Sales History',
            _sales.length,
            trailing: _sales.isEmpty
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreenSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.primaryGreenBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'TOTAL: ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.green700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          AppFormatters.formatAmount(
                            _totalSalesAmount.toString(),
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.money,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_sales.isEmpty)
            _emptyState(Icons.shopping_bag_outlined, 'No sales records found')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sales.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final s = _sales[i];
                final prodName =
                    (s.productDisplay != null && s.productDisplay!.isNotEmpty)
                    ? s.productDisplay!
                    : s.product;
                final prodColor = productColor(prodName);
                return ListTile(
                  dense: true,
                  minVerticalPadding: 0,
                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxs,
                        ),
                        margin: const EdgeInsets.only(right: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: prodColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(
                            color: prodColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          prodName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: prodColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: AppSizing.iconXs,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          AppFormatters.formatDate(s.date),
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  trailing: Text(
                    AppFormatters.formatAmount(s.amount),
                    style: AppTypography.amount.copyWith(fontSize: 13),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTransferHistoryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Transfer History', _transfers.length),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'Ownership changes between employees and admins',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_transfers.isEmpty)
            _emptyState(
              Icons.swap_horiz_rounded,
              'No transfers yet. Still with $_ownerName.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transfers.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final t = _transfers[i];
                final from = t.fromEmployeeName.isNotEmpty
                    ? t.fromEmployeeName
                    : 'Unassigned';
                final meta = [
                  AppFormatters.formatDateTime(t.transferredAt),
                  if (t.transferredByName.isNotEmpty)
                    'by ${t.transferredByName}',
                  if (t.reason.isNotEmpty) t.reason,
                ].join(' · ');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$from  →  ${t.toEmployeeName}',
                        style: AppTypography.itemTitle.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(meta, style: AppTypography.caption),
                      if (t.notes.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          t.notes,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper widgets
  // ---------------------------------------------------------------------------

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(AppSpacing.md),
          child: child,
        ),
      ),
    );
  }

  Widget _cardHeader(String title, int count, {Widget? trailing}) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: AppTypography.cardTitle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceHover,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Text('$count', style: AppTypography.captionSemibold),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: AppSizing.iconXl, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.xs),
            Text(message, style: AppTypography.itemSubtitle),
          ],
        ),
      ),
    );
  }

  Widget _contactItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSizing.iconXs, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Text(text, style: AppTypography.bodySecondary),
      ],
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color color;
    Color bg;
    switch (priority.trim().toUpperCase()) {
      case 'HIGH':
        color = AppColors.danger;
        bg = AppColors.dangerSoft;
        break;
      case 'MEDIUM':
        color = AppColors.warning;
        bg = AppColors.warningSoft;
        break;
      case 'LOW':
      default:
        color = AppColors.primaryBlue;
        bg = AppColors.surfaceHover;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _kpiStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppSizing.iconSm, color: accentColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: accentColor.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.metricMedium.copyWith(color: accentColor),
          ),
        ],
      ),
    );
  }
}
