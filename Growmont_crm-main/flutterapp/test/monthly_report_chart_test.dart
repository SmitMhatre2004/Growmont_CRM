// test/monthly_report_chart_test.dart
//
// The revenue trend chart: a daily line with a period selector.
//
// The bug this file exists for: the touch callback originally gated on
// FlTouchEvent.isInterestedForInteractions, which fl_chart returns true
// for on FlPointerHoverEvent. On desktop that meant moving the mouse
// across the plot selected whatever point was under the cursor — the
// report jumped, and rebuilt on every pointer move, with nobody having
// clicked. The hover test below fails if that gate ever comes back.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/reports/widgets/report_trend_chart.dart';

/// [days] of daily points ending today, with a sale every [everyNthDay]
/// so the series looks like real sparse booking rather than a ramp.
List<DayTotal> _series({int days = 365, int everyNthDay = 3}) {
  final end = DateTime(2025, 6, 30);
  return [
    for (var back = days - 1; back >= 0; back--)
      () {
        final day = DateTime(end.year, end.month, end.day - back);
        final hasSale = back % everyNthDay == 0;
        return DayTotal(
          day: day,
          paise: hasSale ? 100000 + (back % 7) * 25000 : 0,
          count: hasSale ? 1 : 0,
        );
      }(),
  ];
}

Future<void> _pumpChart(
  WidgetTester tester, {
  required List<DayTotal> series,
  ValueChanged<DateTime>? onDayTap,
  Size size = const Size(1200, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width - 80,
            child: ReportTrendChart(series: series, onDayTap: onDayTap),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hovering across the plot never reports a day', (tester) async {
    final tapped = <DateTime>[];
    await _pumpChart(tester, series: _series(), onDayTap: tapped.add);

    // The LineChart's own rect, NOT the widget's: ReportTrendChart is a
    // Column with a selector and a legend, so its rect includes space
    // that is not plot. Sweeping that would prove nothing.
    final box = tester.getRect(find.byType(LineChart));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();

    for (var step = 0; step <= 20; step++) {
      await mouse.moveTo(
        Offset(box.left + box.width * (step / 20), box.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(
      tapped,
      isEmpty,
      reason: 'hovering must not select a day - only a press may',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a press on the plot reports the day under it', (tester) async {
    final tapped = <DateTime>[];
    await _pumpChart(tester, series: _series(), onDayTap: tapped.add);

    await tester.tapAt(tester.getRect(find.byType(LineChart)).center);
    await tester.pumpAndSettle();

    expect(tapped, isNotEmpty, reason: 'a deliberate press must register');
    expect(tester.takeException(), isNull);
  });

  group('period selector', () {
    testWidgets('defaults to three months and offers the other windows', (
      tester,
    ) async {
      await _pumpChart(tester, series: _series());
      expect(find.text('Last 3 months'), findsOneWidget);

      await tester.tap(find.text('Last 3 months'));
      await tester.pumpAndSettle();

      for (final label in const [
        'Last 30 days',
        'Last 6 months',
        'Last 12 months',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing: $label');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a window redraws without error', (tester) async {
      await _pumpChart(tester, series: _series());

      await tester.tap(find.text('Last 3 months'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 12 months').last);
      await tester.pumpAndSettle();

      expect(find.text('Last 12 months'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a window longer than the data shows what there is', (
      tester,
    ) async {
      // Only 20 days of history, but the default window asks for 90.
      await _pumpChart(tester, series: _series(days: 20, everyNthDay: 2));
      expect(find.byType(LineChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a single series carries a key naming what is plotted', (
    tester,
  ) async {
    await _pumpChart(tester, series: _series());
    expect(find.text('Revenue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an all-zero window shows the empty message, not a flat axis', (
    tester,
  ) async {
    await _pumpChart(
      tester,
      series: [
        for (var back = 364; back >= 0; back--)
          DayTotal(
            day: DateTime(2025, 6, 30 - back),
            paise: 0,
            count: 0,
          ),
      ],
    );

    expect(find.textContaining('No revenue booked'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a narrow phone width without overflowing', (
    tester,
  ) async {
    await _pumpChart(
      tester,
      series: _series(),
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
  });
}
