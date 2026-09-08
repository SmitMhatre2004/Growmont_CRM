import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/employee.dart';
import '../../shared/widgets/error_state.dart';
import '../auth/auth_provider.dart';
import 'widgets/add_employee_modal.dart';

enum RoleFilter { all, admin, employee }

class EmployeesListScreen extends ConsumerStatefulWidget {
  const EmployeesListScreen({super.key});

  @override
  ConsumerState<EmployeesListScreen> createState() =>
      _EmployeesListScreenState();
}

class _EmployeesListScreenState extends ConsumerState<EmployeesListScreen> {
  List<Employee> _employees = [];
  String _search = '';
  RoleFilter _roleFilter = RoleFilter.all;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      // Keep existing rows on screen during a pull-to-refresh; the
      // RefreshIndicator already shows its own spinner.
      if (_employees.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiServiceProvider).getEmployees();
      if (mounted) {
        setState(() {
          _employees = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
        if (_employees.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Refresh failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  List<Employee> get _filtered {
    final q = _search.toLowerCase();
    return _employees.where((e) {
      final matchesRole = switch (_roleFilter) {
        RoleFilter.all => true,
        RoleFilter.admin => e.role.toLowerCase() == 'admin',
        RoleFilter.employee => e.role.toLowerCase() != 'admin',
      };
      if (!matchesRole) return false;
      if (q.isEmpty) return true;
      return e.name.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q) ||
          e.mobileNo.toLowerCase().contains(q) ||
          e.role.toLowerCase().contains(q);
    }).toList();
  }

  int get _adminCount =>
      _employees.where((e) => e.role.toLowerCase() == 'admin').length;

  Future<void> _delete(Employee emp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Delete ${emp.name}? This cannot be undone.'),
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
    try {
      await ref.read(apiServiceProvider).deleteEmployee(emp.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showModal({Employee? employee}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddEmployeeModal(existing: employee),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        isMobile ? 10 : 16,
        isMobile ? 16 : 24,
        isMobile ? 14 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(isAdmin, isMobile),
          const SizedBox(height: 14),
          _searchField(),
          const SizedBox(height: 10),
          _roleFilters(),
          const SizedBox(height: 14),
          Expanded(child: _body(isAdmin, isMobile)),
        ],
      ),
    );
  }

  Widget _header(bool isAdmin, bool isMobile) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Employees',
          style: isMobile
              ? AppTypography.pageTitleMobile
              : AppTypography.pageTitle,
        ),
        const SizedBox(height: 4),
        const Text(
          'Manage team members, roles, permissions and track performance',
          style: AppTypography.pageSubtitle,
        ),
      ],
    );

    final addButton = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryGreen,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => _showModal(),
      icon: const Icon(Icons.add, size: 18),
      label: const Text(
        'Add Employee',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          if (isAdmin) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: addButton),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        if (isAdmin) addButton,
      ],
    );
  }

  Widget _searchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search by name, email, phone or role...',
          hintStyle: AppTypography.caption,
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: AppColors.textMuted,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 0,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: AppColors.primaryGreen,
              width: 1.5,
            ),
          ),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  Widget _roleFilters() {
    final activeIndex = switch (_roleFilter) {
      RoleFilter.all => 0,
      RoleFilter.admin => 1,
      RoleFilter.employee => 2,
    };
    const itemWidth = 110.0;
    const controlHeight = 38.0;
    const radius = 10.0;

    final slidingSegment = Container(
      height: controlHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        width: itemWidth * 3,
        child: Stack(
          children: [
            // The physical moving indicator pill
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: activeIndex * itemWidth,
              top: 0,
              bottom: 0,
              width: itemWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(radius - 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 5,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
              ),
            ),
            // Clickable segment labels
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _slidingSegmentItem(
                  label: 'All (${_employees.length})',
                  isSelected: activeIndex == 0,
                  width: itemWidth,
                  controlHeight: controlHeight,
                  radius: radius,
                  onTap: () => setState(() => _roleFilter = RoleFilter.all),
                ),
                _slidingSegmentItem(
                  label: 'Admins ($_adminCount)',
                  isSelected: activeIndex == 1,
                  width: itemWidth,
                  controlHeight: controlHeight,
                  radius: radius,
                  onTap: () => setState(() => _roleFilter = RoleFilter.admin),
                ),
                _slidingSegmentItem(
                  label: 'Employees (${_employees.length - _adminCount})',
                  isSelected: activeIndex == 2,
                  width: itemWidth,
                  controlHeight: controlHeight,
                  radius: radius,
                  onTap: () =>
                      setState(() => _roleFilter = RoleFilter.employee),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: slidingSegment,
    );
  }

  Widget _slidingSegmentItem({
    required String label,
    required bool isSelected,
    required double width,
    required double controlHeight,
    required double radius,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      height: controlHeight - 6,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius - 3),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  Widget _body(bool isAdmin, bool isMobile) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final card = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: _filtered.isEmpty
          ? (_error != null
                ? ErrorState(
                    message: _error!,
                    title: 'Could not load employees',
                    icon: Icons.people_outline,
                    onRetry: _load,
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 42,
                          color: AppColors.textMuted,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No employees found',
                          style: AppTypography.itemTitle,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Try adjusting your search or filters',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ))
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _filtered.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final emp = _filtered[i];
                return _EmployeeRow(
                  employee: emp,
                  isMobile: isMobile,
                  canManage: isAdmin,
                  onOpen: () => context.push('/employees/${emp.id}'),
                  onEdit: () => _showModal(employee: emp),
                  onDelete: () => _delete(emp),
                );
              },
            ),
    );

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryGreen,
      child: card,
    );
  }
}

/// One employee row: identity, contact and their book of business at a glance.
class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.employee,
    required this.isMobile,
    required this.canManage,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Employee employee;
  final bool isMobile;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = AppConfig.mediaUrl(employee.avatar);
    final isAdminRole = employee.role.toLowerCase() == 'admin';

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 18,
          vertical: 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: isMobile ? 20 : 22,
              backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
              backgroundImage: avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl.isEmpty
                  ? Text(
                      employee.initials,
                      style: TextStyle(
                        fontSize: isMobile ? 13 : 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryGreen,
                      ),
                    )
                  : null,
            ),
            SizedBox(width: isMobile ? 11 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          employee.name,
                          style: AppTypography.itemTitle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _roleBadge(isAdminRole),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _contactLine(Icons.email_outlined, employee.email),
                  if (employee.mobileNo.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _contactLine(Icons.phone_outlined, employee.mobileNo),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _miniStat(
                        Icons.handshake_outlined,
                        '${employee.clientsCount}',
                        'clients',
                        const Color(0xFF2563EB),
                      ),
                      _miniStat(
                        Icons.trending_up_rounded,
                        '${employee.salesCount}',
                        'sales',
                        const Color(0xFF16A34A),
                      ),
                      _miniStat(
                        Icons.forum_outlined,
                        '${employee.interactionsCount}',
                        'chats',
                        const Color(0xFF9333EA),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (canManage)
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'Manage employee',
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: Color(0xFF2563EB),
                        ),
                        SizedBox(width: 8),
                        Text('Edit', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Color(0xFFDC2626),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roleBadge(bool isAdminRole) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isAdminRole ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isAdminRole
              ? const Color(0xFFBFDBFE)
              : const Color(0xFFA7F3D0),
        ),
      ),
      child: Text(
        employee.role.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: isAdminRole
              ? const Color(0xFF1D4ED8)
              : const Color(0xFF047857),
        ),
      ),
    );
  }

  Widget _contactLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: AppTypography.itemSubtitle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _miniStat(IconData icon, String value, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
