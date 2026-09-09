import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/excel/excel_io.dart';
import '../../core/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../models/employee.dart';
import '../../shared/widgets/error_state.dart';
import '../auth/auth_provider.dart';
import 'employees_excel.dart';
import 'widgets/add_employee_modal.dart';
import 'widgets/pending_requests_section.dart';

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

  final _searchFocusNode = FocusNode();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
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
              backgroundColor: AppColors.danger,
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
            backgroundColor: AppColors.danger,
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

  Future<void> _exportEmployees() async {
    try {
      final savedPath = await ExcelIO.exportWorkbook(
        filename: 'employees_export.xlsx',
        sheetName: 'Employees',
        headers: employeesExportHeaders,
        rows: _employees.map(employeeExportRow).toList(),
        shareText: 'Employees Export',
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

  Future<void> _importEmployees() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final rows = await ExcelIO.readDataRows(result.files.single.path!);
      final api = ref.read(firestoreServiceProvider);
      var count = 0;
      for (final row in rows) {
        final payload = employeeImportPayload(row);
        if (payload == null) continue;
        try {
          await api.createEmployee(payload);
          count++;
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $count employee(s)')),
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
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleRow(),
        if (isAdmin) const PendingRequestsSection(),
        _buildTabsRow(isAdmin),
        _buildSearchRow(),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? AppSpacing.lg : AppSpacing.xxl,
            ),
            child: _body(isAdmin, isMobile),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  // -- Title row: "Employees" ---------------------------------------------

  Widget _buildTitleRow() {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        isMobile ? 10 : 16,
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        isMobile ? 8 : 12,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Employees',
          style: isMobile
              ? AppTypography.pageTitleMobile
              : AppTypography.pageTitle,
        ),
      ),
    );
  }

  // -- Tabs Row: Filters (UP) + Add Employee --------------------------------

  Widget _outlinedIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 40.0,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppSizing.iconMd),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          backgroundColor: AppColors.surface,
        ),
      ),
    );
  }

  Widget _buildTabsRow(bool isAdmin) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final addButton = SizedBox(
      height: 40.0,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
        ),
        onPressed: () => _showModal(),
        icon: const Icon(Icons.add, size: AppSizing.iconMd),
        label: const Text('Add Employee'),
      ),
    );

    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _outlinedIconButton(
          icon: Icons.download_outlined,
          label: 'Export',
          onPressed: _exportEmployees,
        ),
        const SizedBox(width: AppSpacing.sm),
        _outlinedIconButton(
          icon: Icons.upload_outlined,
          label: 'Import',
          onPressed: _importEmployees,
        ),
        const SizedBox(width: AppSpacing.sm),
        addButton,
      ],
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _roleFilters(),
            ),
            if (isAdmin) ...[
              const SizedBox(height: AppSpacing.md),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: actionButtons,
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          _roleFilters(),
          const Spacer(),
          if (isAdmin) actionButtons,
        ],
      ),
    );
  }

  // -- Search Row: Search bar (BELOW) + Count Badge -------------------------

  Widget _buildSearchRow() {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final isSearchFocused = _searchFocusNode.hasFocus;

    final searchBar = Material(
      color: Colors.white,
      elevation: isSearchFocused ? 2.0 : 1.5,
      shadowColor: isSearchFocused
          ? AppColors.primaryBlue.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(
          color: isSearchFocused ? AppColors.primaryBlue : AppColors.border,
          width: isSearchFocused ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 40.0,
        child: TextField(
          focusNode: _searchFocusNode,
          controller: _searchController,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search by name, email, phone or role...',
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            prefixIcon: const Icon(
              Icons.search,
              color: AppColors.textMuted,
              size: AppSizing.iconMd,
            ),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: AppColors.textMuted,
                      size: AppSizing.iconMd,
                    ),
                    onPressed: () => setState(() {
                      _search = '';
                      _searchController.clear();
                    }),
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => setState(() {
            _search = v;
          }),
        ),
      ),
    );

    final countBadge = Text(
      '${_filtered.length} ${_filtered.length == 1 ? 'employee' : 'employees'}',
      style: AppTypography.tableCellStrong.copyWith(fontSize: 14),
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchBar,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          Expanded(flex: 1, child: searchBar),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: countBadge,
            ),
          ),
        ],
      ),
    );
  }

  // -- Role Filters (Sliding Segment) ---------------------------------------

  Widget _roleFilters() {
    final activeIndex = switch (_roleFilter) {
      RoleFilter.all => 0,
      RoleFilter.admin => 1,
      RoleFilter.employee => 2,
    };
    const itemWidth = 110.0;
    const controlHeight = 40.0;
    const radius = 10.0;

    final slidingSegment = Container(
      height: controlHeight,
      decoration: BoxDecoration(
        color: AppColors.surfaceHeader,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
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
                  onTap: () => setState(() => _roleFilter = RoleFilter.all),
                ),
                _slidingSegmentItem(
                  label: 'Admins ($_adminCount)',
                  isSelected: activeIndex == 1,
                  width: itemWidth,
                  onTap: () => setState(() => _roleFilter = RoleFilter.admin),
                ),
                _slidingSegmentItem(
                  label: 'Employees (${_employees.length - _adminCount})',
                  isSelected: activeIndex == 2,
                  width: itemWidth,
                  onTap: () =>
                      setState(() => _roleFilter = RoleFilter.employee),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return slidingSegment;
  }

  Widget _slidingSegmentItem({
    required String label,
    required bool isSelected,
    required double width,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      height: AppSizing.controlSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            style: TextStyle(
              fontSize: 13,
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                          size: AppSizing.iconDisplay,
                          color: AppColors.textMuted,
                        ),
                        SizedBox(height: AppSpacing.md),
                        Text(
                          'No employees found',
                          style: AppTypography.itemTitle,
                        ),
                        SizedBox(height: AppSpacing.xs),
                        Text(
                          'Try adjusting your search or filters',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ))
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
                      const SizedBox(width: AppSpacing.sm),
                      _roleBadge(isAdminRole),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _contactLine(Icons.email_outlined, employee.email),
                  if (employee.mobileNo.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    _contactLine(Icons.phone_outlined, employee.mobileNo),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _miniStat(
                        Icons.handshake_outlined,
                        '${employee.clientsCount}',
                        'clients',
                        AppColors.info,
                      ),
                      _miniStat(
                        Icons.trending_up_rounded,
                        '${employee.salesCount}',
                        'sales',
                        AppColors.success,
                      ),
                      _miniStat(
                        Icons.forum_outlined,
                        '${employee.interactionsCount}',
                        'chats',
                        AppAccents.purpleBase,
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
                  size: AppSizing.iconMd,
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
                          size: AppSizing.iconSm,
                          color: AppColors.info,
                        ),
                        SizedBox(width: AppSpacing.sm),
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
                          size: AppSizing.iconSm,
                          color: AppColors.danger,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xs),
                child: Icon(
                  Icons.chevron_right,
                  size: AppSizing.iconMd,
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: isAdminRole ? AppColors.surfaceSelected : AppAccents.greenTint,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: isAdminRole ? AppAccents.blueBorder : AppAccents.greenBorder,
        ),
      ),
      child: Text(
        employee.role.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: isAdminRole ? AppAccents.blueStrong : AppAccents.greenTeal,
        ),
      ),
    );
  }

  Widget _contactLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: AppSizing.iconXs, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.xs),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizing.iconXs, color: accent),
          const SizedBox(width: AppSpacing.xs),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
