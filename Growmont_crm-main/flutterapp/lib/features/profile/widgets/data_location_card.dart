// lib/features/profile/widgets/data_location_card.dart
//
// Desktop-only diagnostic card for Profile -> System: shows exactly where
// Growmont CRM's local database lives, so a user (or support) can confirm
// it survives updates/reinstalls without hunting through AppData by hand.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_paths.dart';
import '../../../core/theme/app_theme.dart';

class DataLocationCard extends StatefulWidget {
  const DataLocationCard({super.key});

  @override
  State<DataLocationCard> createState() => _DataLocationCardState();
}

class _DataLocationCardState extends State<DataLocationCard> {
  AppStorageInfo? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await AppPaths.resolveStorageInfo();
    if (mounted) setState(() => _info = info);
  }

  Future<void> _copyPaths() async {
    final info = _info;
    if (info == null) return;
    await Clipboard.setData(ClipboardData(text: info.toDiagnosticText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Storage paths copied to clipboard')),
    );
  }

  Future<void> _openFolder() async {
    final info = _info;
    if (info == null || !Platform.isWindows) return;
    try {
      await Process.run('explorer', [info.databaseDirectory]);
    } catch (_) {
      // Non-fatal — Explorer failing to launch shouldn't crash the card.
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;

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
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.folder_outlined, size: 12, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('DATA STORAGE', style: AppTypography.sectionTitle),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: info == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PathRow(label: 'Database folder', value: info.databaseDirectory),
                      _PathRow(
                        label: 'Database file',
                        value: info.database.exists
                            ? '${info.database.path} (${info.database.sizeLabel})'
                            : '${info.database.path} (not created yet)',
                      ),
                      _PathRow(label: 'Local backups', value: '${info.backupCount} kept'),
                      _PathRow(label: 'Program folder', value: info.executableDirectory),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.infoSoft,
                          borderRadius: AppRadius.brSm,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, size: AppSizing.iconXs, color: AppColors.info),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Your data lives outside the program folder, so updates '
                                'and reinstalls never touch it.',
                                style: AppTypography.caption.copyWith(color: AppColors.info),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _copyPaths,
                              icon: const Icon(Icons.copy_outlined, size: AppSizing.iconSm),
                              label: const Text('Copy paths'),
                            ),
                          ),
                          if (Platform.isWindows) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openFolder,
                                icon: const Icon(Icons.open_in_new, size: AppSizing.iconSm),
                                label: const Text('Open folder'),
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
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.caption),
            const SizedBox(height: 2),
            SelectableText(
              value,
              style: AppTypography.bodyPrimary.copyWith(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      );
}
