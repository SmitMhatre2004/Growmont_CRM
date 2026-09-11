import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/client.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/monthly_revenue_chart.dart';

class ClientDetailScreen extends ConsumerStatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<ClientDetailScreen> createState() =>
      _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen> {
  Client? _client;
  List<Sale> _sales = [];
  List<Interaction> _interactions = [];
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
      ]);
      if (mounted) {
        setState(() {
          _client = results[0] as Client;
          _sales = results[1] as List<Sale>;
          _interactions = results[2] as List<Interaction>;
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

  double get _totalSalesAmount {
    double total = 0;
    for (final s in _sales) {
      total += double.tryParse(s.amount) ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_client == null) {
      return ErrorState(
        message: _error ?? 'This client no longer exists, or is not assigned to you.',
        title: _error == null ? 'Client not found' : 'Something went wrong',
        icon: Icons.person_off_outlined,
        onRetry: _load,
      );
    }

    final client = _client!;
    final isMobile = AppLayout.isMobile(context);
    final isTablet = !isMobile && MediaQuery.sizeOf(context).width >= 900;

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
                  Expanded(flex: 5, child: _buildRevenueCard()),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(flex: 4, child: _buildInteractionsCard()),
                ],
              )
            else
              Column(
                children: [
                  _buildRevenueCard(),
                  const SizedBox(height: AppSpacing.md),
                  _buildInteractionsCard(),
                ],
              ),
            const SizedBox(height: AppSpacing.md),
            _buildSalesHistoryCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(String clientName) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/clients');
            }
          },
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
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
        child: Row(
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
                  color: AppAccents.blueStrong,
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
                      _contactItem(
                        Icons.phone_outlined,
                        client.contactNumber.isNotEmpty
                            ? client.contactNumber
                            : 'No contact',
                      ),
                      if (client.employeeName?.isNotEmpty ?? false)
                        _contactItem(
                          Icons.badge_outlined,
                          'Owned by ${client.employeeName}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
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
      ),
    );
  }

  Widget _buildInteractionsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Interactions', style: AppTypography.cardTitle),
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
                  child: Text(
                    '${_interactions.length}',
                    style: AppTypography.captionSemibold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_interactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    'No interactions recorded',
                    style: AppTypography.itemSubtitle,
                  ),
                ),
              )
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
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      AppFormatters.formatDate(it.date),
                      style: AppTypography.itemTitle.copyWith(fontSize: 13),
                    ),
                    subtitle: it.discussionNotes.isNotEmpty
                        ? Text(
                            it.discussionNotes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption,
                          )
                        : null,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesHistoryCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Flexible(
                  child: Text(
                    'Sales History',
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
                  child: Text(
                    '${_sales.length}',
                    style: AppTypography.captionSemibold,
                  ),
                ),
                const Spacer(),
                if (_sales.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: AppAccents.greenSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppAccents.greenBorderSoft),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'TOTAL: ',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppAccents.greenDeep,
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
                            color: AppAccents.greenStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_sales.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    'No sales records found',
                    style: AppTypography.itemSubtitle,
                  ),
                ),
              )
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 2,
                    ),
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
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: prodColor,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppFormatters.formatDate(s.date),
                            style: AppTypography.itemTitle.copyWith(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
}
