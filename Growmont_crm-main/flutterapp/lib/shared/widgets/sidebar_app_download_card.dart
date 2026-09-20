import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/firebase/mobile_install.dart';
import '../../core/theme/app_theme.dart';

/// The "get the mobile app" panel that sits just above the profile card in
/// the sidebar.
///
/// Driven by the same 0..1 collapse progress [t] as the nav items rather than
/// by a controller of its own, so it grows and fades in step with the rail's
/// width animation instead of racing it.
///
/// Collapsed, the panel is nothing but a short centred rule. An 80px rail has
/// no room for a QR code, and one shrunk to fit would be too dense for a phone
/// camera to resolve — so everything below the rule is built only once the rail
/// starts opening. That also keeps the collapsed sidebar free of the stray
/// [Icon] and [CircleAvatar] widgets that `sidebar_centering_test` measures.
///
/// It is also a one-time nudge rather than a fixture — see
/// [mobileAppInstalledProvider].
class SidebarAppDownloadCard extends ConsumerWidget {
  const SidebarAppDownloadCard({super.key, required this.t});

  /// 0.0 when the sidebar is fully collapsed, 1.0 when fully expanded.
  final double t;

  /// The QR is *sized* from [t] rather than drawn full size and clipped, so it
  /// can never ask for more width than the rail currently has — which is what
  /// would overflow partway through the collapse animation.
  static const double _qrMin = 26;
  static const double _qrMax = 92;

  /// Below this the rail is too narrow for the labels to be worth the space.
  static const double _labelsFrom = 0.55;

  Future<void> _openDownloadPage(BuildContext context) async {
    // Captured before the await: the messenger cannot be looked up from a
    // context that may have been unmounted while the browser was launching.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uri = Uri.tryParse(AppConfig.appDownloadUrl);

    var opened = false;
    if (uri != null && uri.hasScheme) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }

    if (!opened) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open the download page.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Retires itself once this account has opened the CRM on a phone: the nudge
    // has been acted on, and a standing QR for software you already have is
    // just clutter. An unknown answer — still loading, offline, no Firebase —
    // reads as "not installed", so the card fails *visible* rather than
    // silently never appearing for anyone.
    //
    // `maybeWhen`, not `.value`: AsyncValue.value *rethrows* an error state, so
    // a rules rejection or a failed auth provider would throw out of the
    // sidebar's build rather than quietly leaving the card up.
    final bool hasMobileApp = ref
        .watch(mobileAppInstalledProvider)
        .maybeWhen(data: (installed) => installed, orElse: () => false);

    // This computer's own choice outranks the account signal in both
    // directions — see Profile -> System.
    final bool? override = ref.watch(sidebarQrOverrideProvider);
    final bool visible = override ?? !hasMobileApp;
    if (!visible) {
      return const SizedBox.shrink();
    }

    final double p = t.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsed, this rule is the whole section: it stretches out of a
          // short centred dash as the rail opens, so the panel never appears
          // or vanishes abruptly.
          LayoutBuilder(
            builder: (context, constraints) => Container(
              height: 1,
              width: lerpDouble(24.0, constraints.maxWidth, p),
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          if (p > 0.02) ...[
            SizedBox(height: lerpDouble(0, AppSpacing.md, p)!),
            Opacity(opacity: p, child: _buildCard(context, p)),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, double p) {
    final double qrSize = lerpDouble(_qrMin, _qrMax, p)!;
    final double cardPad = lerpDouble(AppSpacing.xs, AppSpacing.md, p)!;
    final double platePad = lerpDouble(2, 6, p)!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Tooltip(
          message: 'Open the app download page',
          waitDuration: const Duration(milliseconds: 300),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => _openDownloadPage(context),
            child: Padding(
              padding: EdgeInsets.all(cardPad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The white plate is not decoration: a QR needs a light
                  // quiet zone around it or a camera will not lock onto it
                  // against the green.
                  Container(
                    padding: EdgeInsets.all(platePad),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: QrImageView(
                      data: AppConfig.appDownloadUrl,
                      version: QrVersions.auto,
                      size: qrSize,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.sidebarBg,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.sidebarBg,
                      ),
                      semanticsLabel: 'QR code to download the mobile app',
                      errorStateBuilder: (context, error) => SizedBox(
                        width: qrSize,
                        height: qrSize,
                        child: const Center(
                          child: Text(
                            'QR unavailable',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (p > _labelsFrom) ...[
                    SizedBox(height: lerpDouble(0, AppSpacing.sm, p)!),
                    Opacity(
                      opacity: ((p - _labelsFrom) / (1 - _labelsFrom)).clamp(
                        0.0,
                        1.0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Get the mobile app',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Scan to install on your phone',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.70),
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
