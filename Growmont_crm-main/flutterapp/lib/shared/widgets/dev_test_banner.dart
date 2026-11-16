// lib/shared/widgets/dev_test_banner.dart
//
// A persistent, non-dismissible strip shown across every screen while the
// signed-in account is a developer/test account (Employee.excludeFromHeadcount
// / AppUser.excludeFromHeadcount). Purely for self-transparency — the same
// spirit as a "developer observing" indicator — never hidden while the flag
// is true, and renders nothing at all for a normal account.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/auth_provider.dart';

class DevTestBanner extends ConsumerWidget {
  const DevTestBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDevAccount =
        ref.watch(authProvider).user?.excludeFromHeadcount == true;
    if (!isDevAccount) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: AppColors.neutralSoft,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_outlined, size: 13, color: AppColors.neutral),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Developer test account — not counted as staff',
            style: AppTypography.caption.copyWith(
              color: AppColors.neutral,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
