// lib/features/profile/widgets/update_card.dart
//
// Self-update status card for Profile -> System. Not a port of CruSam's
// UpdateCard (which hardcodes a private design-token class for a different
// app) — built fresh on Growmont's own AppColors/AppTypography/AppSpacing/
// AppRadius/AppSizing tokens, but with the same structure and states.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/updater/update_dialog.dart';
import '../../../core/updater/update_notifier.dart';
import '../../../core/updater/update_service.dart';

class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key});

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  String _currentVersion = '…';

  @override
  void initState() {
    super.initState();
    _fetchCurrentVersion();
  }

  Future<void> _fetchCurrentVersion() async {
    try {
      final version = await UpdateService.getCurrentVersion();
      if (mounted) setState(() => _currentVersion = version);
    } catch (_) {
      // Leave the placeholder — non-fatal.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UpdateNotifier.instance,
      builder: (ctx, _) {
        final notifier = UpdateNotifier.instance;
        final info = notifier.info;
        final hasUpdate = notifier.hasUpdate;
        final isBusy = notifier.isBusy;
        final displayVersion = info?.currentVersion ?? _currentVersion;

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
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.system_update_outlined,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('APP VERSION', style: AppTypography.sectionTitle),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      icon: Icons.tag_outlined,
                      label: 'Current version',
                      value: 'v$displayVersion',
                    ),
                    if (info != null)
                      _InfoRow(
                        icon: Icons.cloud_outlined,
                        label: 'Latest version',
                        value: 'v${info.latestVersion}',
                        valueColor: hasUpdate ? AppColors.success : AppColors.textPrimary,
                      ),
                    const SizedBox(height: AppSpacing.md),
                    _StatusBadge(notifier: notifier),
                    if (notifier.state == UpdateState.error &&
                        notifier.errorMessage != null) ...[
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
                          notifier.errorMessage!,
                          style: AppTypography.caption.copyWith(color: AppColors.danger),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isBusy
                                ? null
                                : () async {
                                    await notifier.checkForUpdate();
                                    if (mounted && notifier.info != null) {
                                      setState(() {
                                        _currentVersion = notifier.info!.currentVersion;
                                      });
                                    }
                                  },
                            icon: isBusy && notifier.state == UpdateState.checking
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh, size: AppSizing.iconSm),
                            label: const Text('Check'),
                          ),
                        ),
                        if (hasUpdate) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: isBusy ? null : () => UpdateDialog.show(ctx),
                              icon: const Icon(Icons.download_outlined, size: AppSizing.iconSm),
                              label: const Text('Update Now'),
                            ),
                          ),
                        ],
                      ],
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
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: AppSizing.iconXs, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Text('$label:', style: AppTypography.caption),
            const SizedBox(width: AppSpacing.xs),
            Text(
              value,
              style: AppTypography.bodyPrimary.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.notifier});

  final UpdateNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final hasUpdate = notifier.hasUpdate;
    final state = notifier.state;
    final info = notifier.info;

    if (state == UpdateState.checking) {
      return _badge(Icons.sync_outlined, 'Checking for updates…',
          AppColors.surfaceHeader, AppColors.textSecondary);
    }
    if (state == UpdateState.downloading) {
      return _badge(
        Icons.download_outlined,
        'Downloading ${(notifier.downloadProgress * 100).toStringAsFixed(0)}%…',
        AppColors.surfaceHeader,
        AppColors.textSecondary,
      );
    }
    if (state == UpdateState.launching) {
      return _badge(Icons.launch_outlined, 'Launching updater…',
          AppColors.surfaceHeader, AppColors.textSecondary);
    }
    if (hasUpdate) {
      return _badge(Icons.new_releases_outlined, 'Update available: v${info!.latestVersion}',
          AppColors.warningSoft, AppColors.warning);
    }
    if (info != null && !hasUpdate) {
      return _badge(Icons.check_circle_outline, 'App is up to date',
          AppColors.successSoft, AppColors.success);
    }
    return _badge(Icons.info_outline, 'Tap "Check" to look for updates',
        AppColors.surfaceHeader, AppColors.textMuted);
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
