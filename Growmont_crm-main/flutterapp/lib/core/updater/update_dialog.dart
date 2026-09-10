// lib/core/updater/update_dialog.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'update_notifier.dart';

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const UpdateDialog(),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UpdateNotifier.instance,
      builder: (dialogContext, child) {
        final notifier = UpdateNotifier.instance;
        final info = notifier.info;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xxxl),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.sidebarBg, AppColors.sidebarBgDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: AppRadius.topLg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: AppRadius.brSm,
                            ),
                            child: const Icon(
                              Icons.system_update_outlined,
                              color: Colors.white,
                              size: AppSizing.iconLg,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'Update Available',
                            style: AppTypography.cardTitle
                                .copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                      if (info != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            _VersionBadge(
                              label: 'Current',
                              version: info.currentVersion,
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: Colors.white70,
                              ),
                            ),
                            _VersionBadge(
                              label: 'New',
                              version: info.latestVersion,
                              highlight: true,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (info != null)
                        Text(info.message, style: AppTypography.bodySecondary),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                          borderRadius: AppRadius.brSm,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              size: 15,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'All your data and settings are kept safe.',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (notifier.state == UpdateState.error &&
                          notifier.errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.dangerSoft,
                            border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.3),
                            ),
                            borderRadius: AppRadius.brSm,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 16,
                                color: AppColors.danger,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  notifier.errorMessage!,
                                  style: AppTypography.caption
                                      .copyWith(color: AppColors.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (notifier.state == UpdateState.downloading) ...[
                        const SizedBox(height: AppSpacing.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Downloading…', style: AppTypography.caption),
                                Text(
                                  '${(notifier.downloadProgress * 100).toStringAsFixed(0)}%',
                                  style: AppTypography.captionSemibold,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: notifier.downloadProgress,
                                minHeight: 6,
                                backgroundColor: AppColors.border,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primaryGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (notifier.state == UpdateState.launching) ...[
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text('Launching updater…', style: AppTypography.caption),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          if (!(info?.force ?? false))
                            Expanded(
                              child: OutlinedButton(
                                onPressed: notifier.isBusy
                                    ? null
                                    : () => Navigator.pop(context),
                                child: const Text('Later'),
                              ),
                            ),
                          if (!(info?.force ?? false))
                            const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: notifier.isBusy
                                  ? null
                                  : () {
                                      notifier.clearError();
                                      notifier.downloadAndInstall();
                                    },
                              icon: notifier.isBusy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.download_outlined, size: 16),
                              label: Text(
                                notifier.isBusy ? 'Updating…' : 'Update Now',
                              ),
                            ),
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
      },
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({
    required this.label,
    required this.version,
    this.highlight = false,
  });

  final String label;
  final String version;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: highlight
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: AppRadius.brSm,
          border: Border.all(
            color: highlight
                ? Colors.white.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: Colors.white60,
                fontSize: 10,
              ),
            ),
            Text(
              'v$version',
              style: AppTypography.bodyPrimary.copyWith(
                color: highlight ? Colors.white : Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
}
