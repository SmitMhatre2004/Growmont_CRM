import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/client.dart';
import '../../models/employee.dart';
import '../../models/sale.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/monthly_revenue_chart.dart';

class EmployeeDetailScreen extends ConsumerStatefulWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});

  final String employeeId;

  @override
  ConsumerState<EmployeeDetailScreen> createState() =>
      _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  Employee? _employee;
  List<Client> _clients = [];
  List<Sale> _sales = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_employee == null) _loading = true;
      _error = null;
    });
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_employee == null) {
      return ErrorState(
        message: _error ?? 'This employee no longer exists.',
        title: _error == null ? 'Employee not found' : 'Something went wrong',
        icon: Icons.person_off_outlined,
        onRetry: _load,
      );
    }

    final emp = _employee!;
    final avatarUrl = AppConfig.mediaUrl(emp.avatar);
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final isTablet = MediaQuery.sizeOf(context).width >= 900;

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
            // Breadcrumb Navigation
            _buildBreadcrumb(emp.name),

            const SizedBox(height: AppSpacing.sm),

            // Profile Hero Card
            _buildProfileCard(emp, avatarUrl, isMobile),

            const SizedBox(height: AppSpacing.md),

            // Responsive two‑column grid for wide screens
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
                  Expanded(flex: 4, child: _buildClientsCard()),
                ],
              )
            else
              // Single column layout for mobile / narrow tablets
              Column(
                children: [
                  _buildRevenueCard(),
                  const SizedBox(height: AppSpacing.md),
                  _buildClientsCard(),
                  const SizedBox(height: AppSpacing.md),
                  _buildSalesHistoryCard(),
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

  Widget _buildBreadcrumb(String employeeName) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/employees');
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
                  'Employees',
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
            employeeName,
            style: AppTypography.tableCellStrong,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(Employee emp, String avatarUrl, bool isMobile) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: isMobile ? 22 : 28,
                  backgroundColor: AppColors.primaryGreen.withValues(
                    alpha: 0.12,
                  ),
                  backgroundImage: avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          emp.initials,
                          style: TextStyle(
                            fontSize: isMobile ? 15 : 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryGreen,
                          ),
                        )
                      : null,
                ),
                SizedBox(width: isMobile ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            emp.name,
                            style: isMobile
                                ? AppTypography.headingLarge.copyWith(fontSize: 18)
                                : AppTypography.headingLarge,
                          ),
                          _roleBadge(emp.role),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _contactItem(Icons.email_outlined, emp.email),
                          if (emp.mobileNo.isNotEmpty)
                            _contactItem(Icons.phone_outlined, emp.mobileNo),
                          if (emp.genderDisplay.isNotEmpty)
                            _contactItem(
                              Icons.badge_outlined,
                              emp.genderDisplay,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: AppSpacing.md),

            // KPI Metric Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 520;
                final clientCard = _kpiStatCard(
                  title: 'CLIENTS',
                  value: emp.clientsCount.toString(),
                  icon: Icons.people_alt_outlined,
                  accentColor: AppColors.info,
                  bgColor: AppColors.surfaceSelected,
                );
                final salesCard = _kpiStatCard(
                  title: 'SALES',
                  value: emp.salesCount.toString(),
                  icon: Icons.trending_up_rounded,
                  accentColor: AppColors.success,
                  bgColor: AppAccents.greenSoft,
                );
                final interactionsCard = _kpiStatCard(
                  title: 'INTERACTIONS',
                  value: emp.interactionsCount.toString(),
                  icon: Icons.forum_outlined,
                  accentColor: AppAccents.purpleBase,
                  bgColor: AppAccents.purpleSoft,
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: clientCard),
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
                    Expanded(child: clientCard),
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

  Widget _buildClientsCard() {
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
                const Text(
                  'Assigned Clients',
                  style: AppTypography.cardTitle,
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
                    '${_clients.length}',
                    style: AppTypography.captionSemibold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_clients.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: AppSizing.iconXl,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        'No assigned clients found',
                        style: AppTypography.itemSubtitle,
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _clients.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final c = _clients[i];
                  return ListTile(
                    dense: true,
                    minVerticalPadding: 0,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 0,
                    ),
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.surfaceSelected,
                      child: Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppAccents.blueStrong,
                        ),
                      ),
                    ),
                    title: Text(c.name, style: AppTypography.itemTitle),
                    subtitle: Row(
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: AppSizing.iconXs,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          c.contactNumber.isNotEmpty
                              ? c.contactNumber
                              : 'No contact',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
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
                const Text('Sales History', style: AppTypography.cardTitle),
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
                  child: Column(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: AppSizing.iconXl,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        'No sales records found',
                        style: AppTypography.itemSubtitle,
                      ),
                    ],
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
                            s.clientName,
                            style: AppTypography.itemTitle.copyWith(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper widgets
  // ---------------------------------------------------------------------------

  Widget _roleBadge(String role) {
    final isAdmin = role.toLowerCase() == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: isAdmin ? AppColors.surfaceSelected : AppAccents.greenTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: isAdmin ? AppAccents.blueBorder : AppAccents.greenBorder,
        ),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isAdmin ? AppAccents.blueStrong : AppAccents.greenTeal,
          letterSpacing: 0.4,
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
                  fontSize: 10,
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
            style: AppTypography.metricMedium.copyWith(color: accentColor),
          ),
        ],
      ),
    );
  }
}
