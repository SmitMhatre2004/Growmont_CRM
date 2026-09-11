import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum ExportFormat { excel, json }

/// Asks which file format an export should produce. Returns null if dismissed.
Future<ExportFormat?> pickExportFormat(BuildContext context) {
  return showDialog<ExportFormat>(
    context: context,
    builder: (context) => AlertDialog(
      insetPadding: AppLayout.modalInset(context),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      title: const Text('Export as'),
      contentPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FormatTile(
            icon: Icons.table_chart_outlined,
            title: 'Excel workbook',
            subtitle: 'A .xlsx file that opens in Excel or Sheets',
            onTap: () => Navigator.pop(context, ExportFormat.excel),
          ),
          _FormatTile(
            icon: Icons.data_object,
            title: 'JSON data',
            subtitle: 'A .json file for backup or moving between machines',
            onTap: () => Navigator.pop(context, ExportFormat.json),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: AppSizing.iconXl, color: AppColors.primaryBlue),
      title: Text(title, style: AppTypography.itemTitle),
      subtitle: Text(subtitle, style: AppTypography.caption),
      onTap: onTap,
    );
  }
}
