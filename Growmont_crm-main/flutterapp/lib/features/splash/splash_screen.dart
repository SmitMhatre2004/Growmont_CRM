import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Total time the splash owns the screen, including its fade-out.
const Duration kSplashDuration = Duration(milliseconds: 3600);

/// The official full Growmont logo asset shown on the splash.
const String kSplashLogoAsset = 'assets/images/growmont_logo.png';
const String kSplashMarkAsset = kSplashLogoAsset;

/// The sweeping rule under the logo. Exposed so tests can verify its sweep.
const Key splashRuleKey = Key('splash-rule');

/// Holds [child] behind a full-bleed splash for [kSplashDuration], then fades
/// the splash away. Runs on initial app boot and re-triggers smoothly when
/// transitioning from successful login to the authenticated app UI.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.isAuthenticated = false,
  });

  final Widget child;
  final bool isAuthenticated;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  int _splashSession = 0;
  bool _showingSplash = true;
  bool _initialBootComplete = false;

  @override
  void didUpdateWidget(covariant SplashGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When initial boot has completed and user transitions from unauthenticated to authenticated:
    if (_initialBootComplete &&
        !oldWidget.isAuthenticated &&
        widget.isAuthenticated) {
      setState(() {
        _splashSession++;
        _showingSplash = true;
      });
    }
  }

  void _onSplashFinished() {
    if (mounted) {
      setState(() {
        _showingSplash = false;
        _initialBootComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showingSplash) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: SplashScreen(
            key: ValueKey(_splashSession),
            onFinished: _onSplashFinished,
          ),
        ),
      ],
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kSplashDuration,
  );

  // Each element is driven off one controller via intervals so the sequence
  // stays readable, feels deeply satisfying, and totals exactly kSplashDuration.
  //
  // Elements softly blur-in from a dreamy gaussian haze into razor-sharp
  // clarity, staggered progressively down the column.

  // 1. Full Logo: enters first, softly resolving from a 16px blur into crisp focus.
  late final Animation<double> _logoFade = _curve(0.08, 0.46);
  late final Animation<double> _logoBlur = Tween(
    begin: 16.0,
    end: 0.0,
  ).animate(_curve(0.08, 0.46));
  late final Animation<double> _logoScale = Tween(
    begin: 0.90,
    end: 1.0,
  ).animate(_curve(0.08, 0.46));
  late final Animation<double> _logoRise = Tween(
    begin: 12.0,
    end: 0.0,
  ).animate(_curve(0.08, 0.46));

  // 2. Sweeping Rule: smoothly expands with a subtle glow blur.
  late final Animation<double> _ruleSweep = _curve(
    0.40,
    0.68,
    curve: Curves.easeInOutCubic,
  );
  late final Animation<double> _ruleBlur = Tween(
    begin: 6.0,
    end: 0.0,
  ).animate(_curve(0.40, 0.60));

  // 3. Tagline ("Employee Portal"): drifts up into clean focus.
  late final Animation<double> _taglineFade = _curve(0.54, 0.78);
  late final Animation<double> _taglineBlur = Tween(
    begin: 8.0,
    end: 0.0,
  ).animate(_curve(0.54, 0.78));
  late final Animation<double> _taglineRise = Tween(
    begin: 10.0,
    end: 0.0,
  ).animate(_curve(0.54, 0.78));

  // 4. Exit fade: smooth transition into the app after a comfortable brand hold.
  late final Animation<double> _exitFade = Tween(
    begin: 1.0,
    end: 0.0,
  ).animate(_curve(0.88, 1.0, curve: Curves.easeInOutCubic));

  Animation<double> _curve(
    double begin,
    double end, {
    Curve curve = AppMotion.curve,
  }) => CurvedAnimation(
    parent: _controller,
    curve: Interval(begin, end, curve: curve),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() => widget.onFinished?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _blurLayer({required double sigma, required Widget child}) {
    if (sigma <= 0.05) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppLayout.isMobile(context);
    final logoWidth = isMobile ? 240.0 : 320.0;
    final ruleWidth = isMobile ? 120.0 : 160.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Opacity(
        opacity: _exitFade.value,
        child: Material(
          color: AppColors.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _logoFade.value,
                  child: _blurLayer(
                    sigma: _logoBlur.value,
                    child: Transform.translate(
                      offset: Offset(0, _logoRise.value),
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Image.asset(
                          kSplashLogoAsset,
                          width: logoWidth,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isMobile ? AppSpacing.xl : AppSpacing.xxl),
                _blurLayer(
                  sigma: _ruleBlur.value,
                  child: SizedBox(
                    key: splashRuleKey,
                    height: 3,
                    width: ruleWidth * _ruleSweep.value,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: AppRadius.brXs,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Opacity(
                  opacity: _taglineFade.value,
                  child: _blurLayer(
                    sigma: _taglineBlur.value,
                    child: Transform.translate(
                      offset: Offset(0, _taglineRise.value),
                      child: Text(
                        'Employee Portal',
                        style: AppTypography.bodySecondary.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
