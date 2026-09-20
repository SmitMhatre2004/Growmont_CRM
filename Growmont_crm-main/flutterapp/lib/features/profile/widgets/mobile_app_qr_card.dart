// lib/features/profile/widgets/mobile_app_qr_card.dart
//
// Profile -> System control for the sidebar's "scan to install" QR code.
//
// The QR retires itself once the account signs in on a phone. This card is the
// way back when that was wrong — a wiped phone, a flag set by accident — and
// the way to dismiss it early. The choice is per computer, not per account, so
// hiding it on a shared desktop doesn't remove it from your own laptop.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/mobile_install.dart';
import '../../../core/theme/app_theme.dart';

class MobileAppQrCard extends ConsumerWidget {
  const MobileAppQrCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool? override = ref.watch(sidebarQrOverrideProvider);
    final bool hasMobileApp = ref
        .watch(mobileAppInstalledProvider)
        .maybeWhen(data: (installed) => installed, orElse: () => false);

    final bool showing = override ?? !hasMobileApp;

    final String subtitle;
    if (override != null) {
      subtitle = 'Set manually on this computer.';
    } else if (hasMobileApp) {
      subtitle = 'Hidden automatically — this account has signed in on a phone.';
    } else {
      subtitle = 'Shown until this account signs in on a phone.';
    }

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
                    Icons.qr_code_2,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('MOBILE APP', style: AppTypography.sectionTitle),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: showing,
                  onChanged: (value) =>
                      ref.read(sidebarQrOverrideProvider.notifier).set(value),
                  title: const Text('Show the download QR in the sidebar'),
                  subtitle: Text(subtitle, style: AppTypography.caption),
                ),
                if (override != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          ref.read(sidebarQrOverrideProvider.notifier).set(null),
                      icon: const Icon(
                        Icons.restart_alt,
                        size: AppSizing.iconSm,
                      ),
                      label: const Text('Reset to automatic'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
