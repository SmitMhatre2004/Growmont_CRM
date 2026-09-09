import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';

enum _ReviewFilter { pending, restricted, rejected }

/// Admin-facing section on the Employees screen surfacing every account
/// still awaiting a decision: currently-pending Google-signup grace-period
/// requests (with a live countdown) plus previously restricted/rejected
/// accounts an admin may want to grant access to after the fact.
class PendingRequestsSection extends ConsumerStatefulWidget {
  const PendingRequestsSection({super.key});

  @override
  ConsumerState<PendingRequestsSection> createState() =>
      _PendingRequestsSectionState();
}

class _PendingRequestsSectionState
    extends ConsumerState<PendingRequestsSection> {
  StreamSubscription<List<Employee>>? _sub;
  Timer? _ticker;
  List<Employee> _items = [];
  bool _expanded = true;
  _ReviewFilter _filter = _ReviewFilter.pending;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(firestoreServiceProvider)
        .streamPendingReview()
        .listen((items) {
          if (mounted) setState(() => _items = items);
        });
    // Purely re-renders the countdown text each second; no refetch.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  List<Employee> get _filtered => _items.where((e) {
    switch (_filter) {
      case _ReviewFilter.pending:
        return e.isPending;
      case _ReviewFilter.restricted:
        return e.isRestricted;
      case _ReviewFilter.rejected:
        return e.isRejected;
    }
  }).toList();

  int _countFor(_ReviewFilter f) => _items.where((e) {
    switch (f) {
      case _ReviewFilter.pending:
        return e.isPending;
      case _ReviewFilter.restricted:
        return e.isRestricted;
      case _ReviewFilter.rejected:
        return e.isRejected;
    }
  }).length;

  Future<void> _accept(Employee emp) async {
    final role = await showDialog<String>(
      context: context,
      builder: (_) => _AcceptDialog(employee: emp),
    );
    if (role == null) return;
    await _review(emp, decision: 'ACCEPT', role: role);
  }

  Future<void> _reject(Employee emp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Employee'),
        content: Text(
          'Reject ${emp.name}? Their account will be disabled until an '
          'admin grants access again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _review(emp, decision: 'REJECT');
  }

  Future<void> _review(
    Employee emp, {
    required String decision,
    String? role,
  }) async {
    setState(() => _busyIds.add(emp.id));
    try {
      await ref
          .read(firestoreServiceProvider)
          .reviewEmployee(employeeId: emp.id, decision: decision, role: role);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update ${emp.name}: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(emp.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final pendingCount = _countFor(_ReviewFilter.pending);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        0,
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        AppSpacing.md,
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.how_to_reg_outlined,
                      size: AppSizing.iconMd,
                      color: AppColors.primaryBlue,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Access Requests', style: AppTypography.itemTitle),
                    if (pendingCount > 0) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _badge('$pendingCount new', AppColors.primaryBlue),
                    ],
                    const Spacer(),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(
                        'Pending',
                        _ReviewFilter.pending,
                        _countFor(_ReviewFilter.pending),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _filterChip(
                        'Restricted',
                        _ReviewFilter.restricted,
                        _countFor(_ReviewFilter.restricted),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _filterChip(
                        'Rejected',
                        _ReviewFilter.rejected,
                        _countFor(_ReviewFilter.rejected),
                      ),
                    ],
                  ),
                ),
              ),
              _filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xl,
                      ),
                      child: Center(
                        child: Text(
                          'No ${_filter.name} requests',
                          style: AppTypography.caption,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (_, i) => _RequestRow(
                        employee: _filtered[i],
                        isMobile: isMobile,
                        busy: _busyIds.contains(_filtered[i].id),
                        onAccept: () => _accept(_filtered[i]),
                        onReject: () => _reject(_filtered[i]),
                      ),
                    ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, _ReviewFilter f, int count) {
    final selected = _filter == f;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = f),
      selectedColor: AppColors.primaryBlue.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? AppColors.primaryBlue : AppColors.textSecondary,
      ),
      side: BorderSide(
        color: selected ? AppColors.primaryBlue : AppColors.border,
      ),
      backgroundColor: AppColors.surface,
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.employee,
    required this.isMobile,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final Employee employee;
  final bool isMobile;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  String _countdownText() {
    final remaining = employee.timeRemaining;
    if (remaining == null) return '';
    if (remaining.isNegative) return 'Expired — awaiting sweep';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;
    if (days > 0) return '${days}d ${hours}h ${minutes}m left';
    if (hours > 0) return '${hours}h ${minutes}m left';
    return '${minutes}m ${seconds}s left';
  }

  Widget _statusChip() {
    late final String label;
    late final Color color;
    if (employee.isPending) {
      label = 'PENDING';
      color = AppColors.warning;
    } else if (employee.isRestricted) {
      label = 'RESTRICTED';
      color = AppColors.textMuted;
    } else {
      label = 'REJECTED';
      color = AppColors.danger;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = AppConfig.mediaUrl(employee.avatar);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 12,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
            backgroundImage: avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: avatarUrl.isEmpty
                ? Text(
                    employee.initials,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryGreen,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: AppSpacing.md),
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
                    _statusChip(),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  employee.email,
                  style: AppTypography.itemSubtitle,
                  overflow: TextOverflow.ellipsis,
                ),
                if (employee.isPending) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _countdownText(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: (employee.timeRemaining?.isNegative ?? false)
                          ? AppColors.danger
                          : AppColors.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Accept',
                  onPressed: onAccept,
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                  ),
                ),
                IconButton(
                  tooltip: 'Reject',
                  onPressed: onReject,
                  icon: const Icon(
                    Icons.cancel_outlined,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Small role-confirmation dialog shown before accepting a request, mirroring
/// AddEmployeeModal's dialog chrome and role dropdown.
class _AcceptDialog extends StatefulWidget {
  const _AcceptDialog({required this.employee});

  final Employee employee;

  @override
  State<_AcceptDialog> createState() => _AcceptDialogState();
}

class _AcceptDialogState extends State<_AcceptDialog> {
  late String _role = widget.employee.role.toUpperCase() == 'ADMIN'
      ? 'ADMIN'
      : 'EMPLOYEE';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizing.modalMaxWidth),
        child: Padding(
          padding: AppLayout.modalPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Accept Employee', style: AppTypography.sectionTitle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Grant ${widget.employee.name} (${widget.employee.email}) '
                'permanent access.',
                style: AppTypography.itemSubtitle,
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'EMPLOYEE', child: Text('Employee')),
                  DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                ],
                onChanged: (v) => setState(() => _role = v!),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                    ),
                    onPressed: () => Navigator.pop(context, _role),
                    child: const Text('Accept'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
