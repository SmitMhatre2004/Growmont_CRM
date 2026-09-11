// lib/features/profile/widgets/sync_status_card.dart
//
// Shows the local-first sync engine's current state for Profile -> System:
// whether it's syncing, offline, or errored; how many local changes are
// still queued to push; when it last synced; and a manual "Sync now".

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/local/sync_engine.dart';
import '../../../core/local/sync_models.dart';
import '../../../core/theme/app_theme.dart';

class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SyncEngine.instance,
      builder: (context, _) {
        final snapshot = SyncEngine.instance.snapshot;

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
                        color: AppColors.info,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.sync_outlined, size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('SYNC STATUS', style: AppTypography.sectionTitle),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statusBadge(snapshot),
                    if (snapshot.pendingCount > 0) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${snapshot.pendingCount} change'
                        '${snapshot.pendingCount == 1 ? '' : 's'} waiting to upload',
                        style: AppTypography.caption,
                      ),
                    ],
                    if (snapshot.lastSyncedAt != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Last synced ${DateFormat('MMM d, h:mm a').format(snapshot.lastSyncedAt!)}',
                        style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                    if (snapshot.lastError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.dangerSoft,
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                          borderRadius: AppRadius.brSm,
                        ),
                        child: Text(
                          snapshot.lastError!,
                          style: AppTypography.caption.copyWith(color: AppColors.danger),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: snapshot.status == SyncStatus.syncing
                            ? null
                            : () => SyncEngine.instance.syncNow(),
                        icon: snapshot.status == SyncStatus.syncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync, size: AppSizing.iconSm),
                        label: const Text('Sync now'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusBadge(SyncSnapshot snapshot) {
    switch (snapshot.status) {
      case SyncStatus.syncing:
        return _badge(Icons.sync_outlined, 'Syncing…', AppColors.infoSoft, AppColors.info);
      case SyncStatus.offline:
        return _badge(Icons.cloud_off_outlined, 'Offline — changes will sync when '
            'you\'re back online', AppColors.surfaceHeader, AppColors.textSecondary);
      case SyncStatus.error:
        return _badge(Icons.error_outline, 'Sync error', AppColors.dangerSoft, AppColors.danger);
      case SyncStatus.idle:
        return snapshot.pendingCount > 0
            ? _badge(Icons.cloud_upload_outlined, 'Waiting to sync',
                AppColors.warningSoft, AppColors.warning)
            : _badge(Icons.check_circle_outline, 'All changes synced',
                AppColors.successSoft, AppColors.success);
    }
  }

  Widget _badge(IconData icon, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brSm),
        child: Row(
          children: [
            Icon(icon, size: AppSizing.iconXs, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: AppTypography.caption.copyWith(color: fg, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
}
