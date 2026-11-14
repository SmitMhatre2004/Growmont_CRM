// lib/features/reports/widgets/report_export_picker.dart
//
// Asks which file(s) an export should produce.
//
// Separate from shared/widgets/export_format_picker.dart on purpose: that
// one offers Excel or JSON for a raw record dump, and every list screen
// depends on its two-value enum. A report is a formatted document, so its
// choices are PDF (to read or send), Excel (to work with), or both — a
// third value on the shared enum would force every existing call site to
// handle a case it cannot produce.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// What the user picked. [both] writes two files, asking for a location
/// once per file.
enum ReportExportFormat { pdf, excel, both }

/// Returns the chosen format, or null if the dialog was dismissed.
Future<ReportExportFormat?> pickReportExportFormat(BuildContext context) {
  return showDialog<ReportExportFormat>(
    context: context,
    builder: (context) => AlertDialog(
      insetPadding: AppLayout.modalInset(context),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      title: const Text('Export report'),
      contentPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FormatTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF document',
              subtitle: 'Formatted to read, print or email as-is',
              onTap: () => Navigator.pop(context, ReportExportFormat.pdf),
            ),
            _FormatTile(
              icon: Icons.table_chart_outlined,
              title: 'Excel workbook',
              subtitle: 'One sheet per section, with figures you can sum',
              onTap: () => Navigator.pop(context, ReportExportFormat.excel),
            ),
            _FormatTile(
              icon: Icons.library_add_check_outlined,
              title: 'Both',
              subtitle: 'Saves the PDF and the workbook, one after the other',
              onTap: () => Navigator.pop(context, ReportExportFormat.both),
            ),
          ],
        ),
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

/// Matches the tile in shared/widgets/export_format_picker.dart so the two
/// dialogs look like the same control.
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
      leading: Container(
        width: AppSizing.controlMd,
        height: AppSizing.controlMd,
        decoration: BoxDecoration(
          color: AppColors.surfaceSelected,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, size: AppSizing.iconLg, color: AppColors.primaryBlue),
      ),
      title: Text(title, style: AppTypography.itemTitle),
      subtitle: Text(subtitle, style: AppTypography.caption),
      onTap: onTap,
    );
  }
}
