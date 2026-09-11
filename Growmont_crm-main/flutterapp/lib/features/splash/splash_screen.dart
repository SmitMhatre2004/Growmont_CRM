import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Total time the splash owns the screen, including its fade-out.
const Duration kSplashDuration = Duration(milliseconds: 3000);

// Sampled straight from the logo artwork rather than reused from AppColors:
// the wordmark text sits directly under the mark, so any drift between the
// two greens reads as a mistake at this size.
const Color _markGreen = Color(0xFF008A3C);
const Color _markNavy = Color(0xFF002FA1);

/// The sweeping rule under the wordmark. Exposed so a test can assert it
/// actually has width — it previously collapsed to nothing without failing.
const Key splashRuleKey = Key('splash-rule');

/// Holds [child] behind a full-bleed splash for [kSplashDuration], then fades
/// the splash away. The app boots and auth resolves underneath, so the splash
/// costs nothing beyond the time it is deliberately shown.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: SplashScreen(
            onFinished: () {
              if (mounted) setState(() => _finished = true);
            },
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
  // stays readable and always totals exactly kSplashDuration.
  late final Animation<double> _markFade = _curve(0.05, 0.30);
  late final Animation<double> _markScale = Tween(
    begin: 0.86,
    end: 1.0,
  ).animate(_curve(0.05, 0.32));
  late final Animation<double> _wordFade = _curve(0.20, 0.42);
  late final Animation<double> _wordRise = Tween(
    begin: 12.0,
    end: 0.0,
  ).animate(_curve(0.20, 0.44));
  late final Animation<double> _ruleSweep = _curve(0.34, 0.58);
  late final Animation<double> _taglineFade = _curve(0.46, 0.66);
  late final Animation<double> _exitFade = Tween(
    begin: 1.0,
    end: 0.0,
  ).animate(_curve(0.88, 1.0));

  Animation<double> _curve(double begin, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(begin, end, curve: AppMotion.curve),
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

  @override
  Widget build(BuildContext context) {
    final isMobile = AppLayout.isMobile(context);
    final markWidth = isMobile ? 132.0 : 168.0;
    final wordSize = isMobile ? 34.0 : 44.0;

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
                  opacity: _markFade.value,
                  child: Transform.scale(
                    scale: _markScale.value,
                    child: Image.asset(
                      'assets/images/growmont_mark.png',
                      width: markWidth,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                SizedBox(height: isMobile ? AppSpacing.xxl : AppSpacing.xxxl),
                Opacity(
                  opacity: _wordFade.value,
                  child: Transform.translate(
                    offset: Offset(0, _wordRise.value),
                    child: Text.rich(
                      TextSpan(
                        children: const [
                          TextSpan(
                            text: 'Grow',
                            style: TextStyle(color: _markGreen),
                          ),
                          TextSpan(
                            text: 'mont',
                            style: TextStyle(color: _markNavy),
                          ),
                        ],
                        style: TextStyle(
                          fontFamily: AppTypography.display,
                          fontSize: wordSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.0,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  key: splashRuleKey,
                  height: 3,
                  width: 96 * _ruleSweep.value,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: _markGreen,
                      borderRadius: AppRadius.brXs,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Opacity(
                  opacity: _taglineFade.value,
                  child: Text(
                    'Employee Portal',
                    style: AppTypography.bodySecondary.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1.6,
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
