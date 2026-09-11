import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/splash/splash_screen.dart';

/// The splash is full-bleed and centred, so the sizes that matter are the
/// shortest phone and the widest desktop it has to sit inside.
const _sizes = <String, Size>{
  'small phone 320x640': Size(320, 640),
  'phone 360x740': Size(360, 740),
  'tablet 768x1024': Size(768, 1024),
  'desktop 1440x900': Size(1440, 900),
};

Future<Object?> _pumpSplashAt(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: const SplashScreen(),
      ),
    ),
  );

  // Step through the sequence: every element is on screen by the midpoint,
  // and the exit fade runs at the end.
  for (final t in const [200, 800, 1500, 2200, 2900]) {
    await tester.pump(Duration(milliseconds: t == 200 ? t : 700));
    final error = tester.takeException();
    if (error != null) return error;
  }
  return null;
}

void main() {
  group('Splash layout', () {
    for (final entry in _sizes.entries) {
      testWidgets('fits ${entry.key}', (tester) async {
        expect(await _pumpSplashAt(tester, size: entry.value), isNull);
      });
    }

    testWidgets('fits a small phone at 1.3x text scale', (tester) async {
      expect(
        await _pumpSplashAt(
          tester,
          size: const Size(320, 640),
          textScale: 1.3,
        ),
        isNull,
      );
    });
  });

  testWidgets('the rule under the wordmark actually sweeps out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SplashScreen()),
    );

    await tester.pump(const Duration(milliseconds: 900));
    final start = tester.getSize(find.byKey(splashRuleKey));

    await tester.pump(const Duration(milliseconds: 900));
    final settled = tester.getSize(find.byKey(splashRuleKey));

    expect(settled.height, greaterThan(0), reason: 'rule has no height');
    expect(settled.width, greaterThan(start.width), reason: 'rule never swept');
  });

  group('Splash timing', () {
    testWidgets('reports finished only after the full duration', (
      tester,
    ) async {
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SplashScreen(onFinished: () => finished = true),
        ),
      );

      await tester.pump(kSplashDuration - const Duration(milliseconds: 100));
      expect(finished, isFalse, reason: 'splash ended early');

      await tester.pump(const Duration(milliseconds: 200));
      expect(finished, isTrue, reason: 'splash never ended');
    });

    testWidgets('SplashGate hands the screen to its child when done', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashGate(child: Scaffold(body: Text('app body'))),
        ),
      );

      // The child is mounted underneath from the start, so presence of the
      // splash itself is what distinguishes the two states.
      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(kSplashDuration);
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('app body'), findsOneWidget);
    });
  });
}
