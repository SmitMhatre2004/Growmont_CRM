import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A screen-toolbar button that collapses to an icon on phones.
///
/// Every list screen has the same toolbar: two secondary actions
/// (Export / Import) followed by a primary "Add ..." action. At full size that
/// row is ~330pt wide, so on a phone it was wrapped in a horizontal
/// [SingleChildScrollView] and slid off the edge — half a button visible, no
/// affordance that it scrolled.
///
/// Instead the secondary actions drop their labels below
/// [AppLayout.mobileBreakpoint] and become square icon buttons, keeping the
/// whole group under ~200pt so it fits beside the selection count with room to
/// spare. The primary action keeps its label — it is the one users look for.
class AppToolbarButton extends StatelessWidget {
  const AppToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Primary actions stay filled and keep their label at every width.
  final bool isPrimary;

  static const double _height = AppSizing.controlMd;

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isMobile(context);

    if (isPrimary) {
      return SizedBox(
        height: _height,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add, size: AppSizing.iconMd),
          label: Text(label, overflow: TextOverflow.ellipsis),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.md : AppSpacing.lg,
            ),
          ),
        ),
      );
    }

    if (compact) {
      return Tooltip(
        message: label,
        child: SizedBox(
          width: _height,
          height: _height,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              backgroundColor: AppColors.surface,
              padding: EdgeInsets.zero,
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.brMd,
              ),
            ),
            child: Icon(icon, size: AppSizing.iconMd),
          ),
        ),
      );
    }

    return SizedBox(
      height: _height,
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
}
