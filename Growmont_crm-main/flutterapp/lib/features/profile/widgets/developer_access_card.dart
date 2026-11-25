// lib/features/profile/widgets/developer_access_card.dart
//
// Profile -> Account and system card, admin-only: accounts an admin has
// excluded from the employee headcount. Excluding/including never changes
// who can log in, their role, or any permission — it only changes whether
// the account counts toward "total employees" on the Employees screen.
// Those accounts no longer render as rows there, so this card is where an
// admin finds and manages them instead; it is not a way to hide anything —
// any admin who opens their own Profile page sees it, plainly labeled.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';
import '../../../shared/widgets/inline_error_banner.dart';
import '../../auth/auth_provider.dart';

class DeveloperAccessCard extends ConsumerStatefulWidget {
  const DeveloperAccessCard({super.key});

  @override
  ConsumerState<DeveloperAccessCard> createState() =>
      _DeveloperAccessCardState();
}

class _DeveloperAccessCardState extends ConsumerState<DeveloperAccessCard> {
  List<Employee>? _excluded;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final all = await api.getEmployees();
      if (mounted) {
        setState(() {
          _excluded = all.where((e) => e.excludeFromHeadcount).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
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

  Future<void> _include(Employee employee) async {
    final name = employee.name.isNotEmpty ? employee.name : employee.email;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmIncludeDialog(employee: employee),
    );
    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name is counted in employee totals again')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;
    // Non-admins never see this card at all — same gate as the admin-only
    // blurb in AccountSecurityCard.
    if (!isAdmin) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surfaceHeader,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.neutral,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'DEVELOPER / SYSTEM ACCESS',
                    style: AppTypography.sectionTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null) {
      return InlineErrorBanner(message: _error!);
    }

    final excluded = _excluded ?? const <Employee>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Accounts excluded from the employee headcount. They still sign '
          'in and act normally — this list is just where you manage that '
          'exclusion.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        if (excluded.isEmpty)
          const Text(
            'No accounts are currently excluded.',
            style: AppTypography.caption,
          )
        else
          for (var i = 0; i < excluded.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            _row(excluded[i]),
          ],
      ],
    );
  }

  Widget _row(Employee employee) {
    final isAdminRole = employee.role.toUpperCase() == 'ADMIN';
    final name = employee.name.isNotEmpty ? employee.name : employee.email;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: AppTypography.itemTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _roleBadge(isAdminRole),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  employee.email,
                  style: AppTypography.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: () => _include(employee),
            child: const Text('Include in employee count'),
          ),
        ],
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
        color: isAdminRole
            ? AppColors.surfaceSelected
            : AppColors.primaryGreenSoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: isAdminRole ? AppPalette.navy200 : AppColors.primaryGreenBorder,
        ),
      ),
      child: Text(
        isAdminRole ? 'ADMIN' : 'EMPLOYEE',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: isAdminRole ? AppColors.primaryBlue : AppColors.primaryGreenDark,
        ),
      ),
    );
  }
}

/// A confirmation that runs the include call itself, so a failure is shown
/// in place and the admin can retry or cancel — same convention as
/// EmployeeAdminMenu's confirm dialogs.
class _ConfirmIncludeDialog extends ConsumerStatefulWidget {
  const _ConfirmIncludeDialog({required this.employee});

  final Employee employee;

  @override
  ConsumerState<_ConfirmIncludeDialog> createState() =>
      _ConfirmIncludeDialogState();
}

class _ConfirmIncludeDialogState
    extends ConsumerState<_ConfirmIncludeDialog> {
  bool _running = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await ref
          .read(apiServiceProvider)
          .setEmployeeHeadcountExclusion(widget.employee.id, false);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;
    final name = emp.name.isNotEmpty ? emp.name : emp.email;
    return AlertDialog(
      title: Text('Include $name in employee count?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name will be counted in employee totals again and will '
              'reappear on the Employees screen.',
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              InlineErrorBanner(message: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _running ? null : _go,
          child: Text(_running ? 'Working...' : 'Include'),
        ),
      ],
    );
  }
}
