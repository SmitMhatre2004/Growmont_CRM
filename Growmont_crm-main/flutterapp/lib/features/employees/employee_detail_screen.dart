import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/client.dart';
import '../../models/employee.dart';
import '../../models/sale.dart';

class EmployeeDetailScreen extends ConsumerStatefulWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});

  final String employeeId;

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
    if (_employee == null) return const Center(child: Text('Employee not found'));

    final emp = _employee!;
    final avatarUrl = AppConfig.mediaUrl(emp.avatar);

    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb Navigation
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/employees');
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.textSecondary),
                      SizedBox(width: 4),
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
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('/', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ),
              Expanded(
                child: Text(
                  emp.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Employee Profile Hero Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: isMobile ? 28 : 36,
                        backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
                        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl.isEmpty
                            ? Text(
                                emp.name.split(' ').map((p) => p[0]).take(2).join(),
                                style: TextStyle(
                                  fontSize: isMobile ? 18 : 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryGreen,
                                ),
                              )
                            : null,
                      ),
                      SizedBox(width: isMobile ? 14 : 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                Text(emp.name, style: AppTypography.pageTitle),
                                _roleBadge(emp.role),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              runSpacing: 6,
                              children: [
                                _contactItem(Icons.email_outlined, emp.email),
                                if (emp.mobileNo.isNotEmpty)
                                  _contactItem(Icons.phone_outlined, emp.mobileNo),
                                if (emp.genderDisplay.isNotEmpty)
                                  _contactItem(Icons.badge_outlined, emp.genderDisplay),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 18),

                  // Modern Responsive KPI Metric Cards
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 520;
                      final clientCard = _kpiStatCard(
                        title: 'CLIENTS',
                        value: emp.clientsCount.toString(),
                        icon: Icons.people_alt_outlined,
                        accentColor: const Color(0xFF2563EB),
                        bgColor: const Color(0xFFEFF6FF),
                      );
                      final salesCard = _kpiStatCard(
                        title: 'SALES',
                        value: emp.salesCount.toString(),
                        icon: Icons.trending_up_rounded,
                        accentColor: const Color(0xFF16A34A),
                        bgColor: const Color(0xFFF0FDF4),
                      );
                      final interactionsCard = _kpiStatCard(
                        title: 'INTERACTIONS',
                        value: emp.interactionsCount.toString(),
                        icon: Icons.forum_outlined,
                        accentColor: const Color(0xFF9333EA),
                        bgColor: const Color(0xFFFAF5FF),
                      );

                      if (isNarrow) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: clientCard),
                                const SizedBox(width: 10),
                                Expanded(child: salesCard),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(width: double.infinity, child: interactionsCard),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: clientCard),
                          const SizedBox(width: 14),
                          Expanded(child: salesCard),
                          const SizedBox(width: 14),
                          Expanded(child: interactionsCard),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Clients Section
          Row(
            children: [
              const Text('Assigned Clients', style: AppTypography.sectionTitle),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '${_clients.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_clients.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.people_outline, size: 36, color: AppColors.textMuted),
                      SizedBox(height: 8),
                      Text('No assigned clients found', style: AppTypography.itemSubtitle),
                    ],
                  ),
                ),
              ),
            )
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _clients.length,
                separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final c = _clients[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFEFF6FF),
                      child: Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ),
                    title: Text(c.name, style: AppTypography.itemTitle),
                    subtitle: Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          c.contactNumber.isNotEmpty ? c.contactNumber : 'No contact',
                          style: AppTypography.itemSubtitle,
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                  );
                },
              ),
            ),
          const SizedBox(height: 28),

          // Sales Section
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sales History', style: AppTypography.sectionTitle),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '${_sales.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (_sales.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'TOTAL: ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF166534),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        AppFormatters.formatAmount(_totalSalesAmount.toString()),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_sales.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.shopping_bag_outlined, size: 36, color: AppColors.textMuted),
                      SizedBox(height: 8),
                      Text('No sales records found', style: AppTypography.itemSubtitle),
                    ],
                  ),
                ),
              ),
            )
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _sales.length,
                separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final s = _sales[i];
                  final prodName = (s.productDisplay != null && s.productDisplay!.isNotEmpty)
                      ? s.productDisplay!
                      : s.product;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
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
                            prodName,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E40AF),
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
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            AppFormatters.formatDate(s.date),
                            style: AppTypography.caption,
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
              ),
            ),
        ],
      ),
    );
  }

  Widget _roleBadge(String role) {
    final isAdmin = role.toLowerCase() == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isAdmin ? const Color(0xFFBFDBFE) : const Color(0xFFA7F3D0)),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isAdmin ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _contactItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 5),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: accentColor.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}
