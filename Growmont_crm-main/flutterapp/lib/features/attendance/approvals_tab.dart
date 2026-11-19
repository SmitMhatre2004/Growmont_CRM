import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_service.dart';
import 'attendance_widgets.dart';
import 'team_tab.dart';

/// Admin: late and early items waiting for a decision.
class AttendanceApprovalsTab extends ConsumerStatefulWidget {
  const AttendanceApprovalsTab({super.key});

  @override
  ConsumerState<AttendanceApprovalsTab> createState() =>
      _AttendanceApprovalsTabState();
}

class _AttendanceApprovalsTabState
    extends ConsumerState<AttendanceApprovalsTab> {
  final _busy = <String>{};

  String _id(ApprovalItem i) => '${i.employeeId}|${i.date}|${i.kind}';

  Future<void> _decide(ApprovalItem item, String decision) async {
    final id = _id(item);
    if (_busy.contains(id)) return;
    final comment = TextEditingController();
    final approve = decision == 'approved';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve this item?' : 'Reject this item?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.employeeName}, ${attendanceDateLabel(item.date)}: '
                '${reviewKindText(item.kind, item.minutes)}.',
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: comment,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    final text = comment.text;
    comment.dispose();
    if (go != true || !mounted) return;

    setState(() => _busy.add(id));
    String message;
    try {
      await ref
          .read(attendanceServiceProvider)
          .review(
            employeeId: item.employeeId,
            date: item.date,
            kind: item.kind,
            decision: decision,
            comment: text,
          );
      message = approve ? 'Approved.' : 'Rejected.';
    } catch (e) {
      message = attendanceErrorMessage(e);
    }
    if (!mounted) return;
    setState(() => _busy.remove(id));
    // Success, or not_pending because another admin decided it first: either
    // way the list should now reflect the server.
    ref.invalidate(attendanceApprovalsProvider);
    ref.invalidate(attendanceTeamDayProvider);
    ref.invalidate(attendanceTeamMonthProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addCheckout(MissedCheckout m) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => EditTimingsDialog(
        service: ref.read(attendanceServiceProvider),
        row: TeamRow(
          employeeId: m.employeeId,
          name: m.employeeName,
          status: 'present',
          record: AttendanceRecord(date: m.date, checkInLocal: m.checkIn),
        ),
        date: m.date,
      ),
    );
    if (changed == true) {
      ref.invalidate(attendanceApprovalsProvider);
      ref.invalidate(attendanceTeamDayProvider);
      ref.invalidate(attendanceTeamMonthProvider);
      ref.invalidate(attendanceMonthProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppLayout.isMobile(context);
    final pad = isMobile ? AppSpacing.lg : AppSpacing.xxl;
    final value = ref.watch(attendanceApprovalsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(attendanceApprovalsProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, AppSpacing.xxl),
        children: [
          AttendanceAsync<ApprovalsData>(
            value: value,
            onRetry: () => ref.invalidate(attendanceApprovalsProvider),
            isEmpty: (d) => d.total == 0,
            emptyTitle: 'Nothing to approve',
            emptyMessage:
                'Late and early notes and missed check-outs appear here.',
            emptyIcon: Icons.task_alt_outlined,
            builder: (d) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.items.isNotEmpty) ...[
                  Text('Notes to review', style: AppTypography.sectionTitle),
                  const SizedBox(height: AppSpacing.md),
                  for (final item in d.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _card(item),
                    ),
                ],
                if (d.missedCheckouts.isNotEmpty) ...[
                  if (d.items.isNotEmpty) const SizedBox(height: AppSpacing.md),
                  Text('Missed check-outs', style: AppTypography.sectionTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Counted as a half day until you add the check-out time.',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final m in d.missedCheckouts) _missedRow(m),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _missedRow(MissedCheckout m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          key: ValueKey('missed-${m.employeeId}-${m.date}'),
          borderRadius: AppRadius.brLg,
          onTap: () => _addCheckout(m),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(
                  Icons.logout,
                  size: AppSizing.iconLg,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.employeeName,
                        style: AppTypography.itemTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${attendanceDateLabel(m.date)}'
                        '${m.checkIn == null ? '' : ' \u00b7 in at ${m.checkIn}'}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text('Add time', style: AppTypography.buttonSmall),
                const Icon(
                  Icons.chevron_right,
                  size: AppSizing.iconMd,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(ApprovalItem item) {
    final busy = _busy.contains(_id(item));
    return AttendancePanel(
      title: item.employeeName,
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${attendanceDateLabel(item.date)} - ${reviewKindText(item.kind, item.minutes)}',
            style: AppTypography.itemTitle,
          ),
          const SizedBox(height: AppSpacing.xs),
          AttendanceInfoRow(
            item.kind == 'late' ? 'Expected in' : 'Expected out',
            item.expected ?? '-',
          ),
          AttendanceInfoRow(
            item.kind == 'late' ? 'Checked in' : 'Checked out',
            item.actual ?? '-',
          ),
          AttendanceInfoRow('Note', item.note ?? 'No note'),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _decide(item, 'rejected'),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : () => _decide(item, 'approved'),
                  child: Text(busy ? 'Saving...' : 'Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
