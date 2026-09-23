// lib/features/profile/widgets/account_security_card.dart
//
// Profile -> System card for the signed-in user's own sign-in: which
// address they log in with, and changing their password.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/auth_provider.dart';
import 'change_password_dialog.dart';

class AccountSecurityCard extends ConsumerWidget {
  const AccountSecurityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

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
                  child: const Icon(
                    Icons.lock_outline,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('ACCOUNT & SECURITY', style: AppTypography.sectionTitle),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Signed in as', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  user?.email ?? '',
                  style: AppTypography.itemTitle,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user?.isAdmin == true) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'You are an administrator. Add, edit, restrict or remove '
                    'accounts, set passwords and change roles from the '
                    'Employees page.',
                    style: AppTypography.caption,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => showChangePasswordDialog(context),
                    icon: const Icon(Icons.key_outlined, size: AppSizing.iconSm),
                    label: const Text('Change password'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
