import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A tinted block showing why a form could not be submitted, placed above
/// the form's fields.
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        borderRadius: AppRadius.brMd,
      ),
      child: Text(
        message,
        style: AppTypography.bodySecondary.copyWith(color: AppColors.danger),
      ),
    );
  }
}
