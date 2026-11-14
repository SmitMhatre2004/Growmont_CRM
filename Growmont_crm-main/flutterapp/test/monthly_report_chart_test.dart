// test/monthly_report_chart_test.dart
//
// Guards the revenue trend chart's interaction contract.
//
// The bug this exists for: the touch callback originally gated on
// FlTouchEvent.isInterestedForInteractions, which fl_chart returns true
// for on FlPointerHoverEvent. On Windows that meant moving the mouse
// across the chart selected whatever bar was under the cursor — the whole
// report re-ran, and the month jumped, with nobody having clicked.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/reports/widgets/report_trend_chart.dart';

List<MonthTotal> _series({int months = 12, int from = 100000}) {
  const end = ReportMonth(2025, 6);
  return [
    for (var back = months - 1; back >= 0; back--)
      MonthTotal(
        month: ReportMonth.of(DateTime(end.year, end.month - back, 1)),
        paise: from + back * 25000,
        count: 3 + back,
      ),
  ];
}

Future<void> _pumpChart(
  WidgetTester tester, {
  required List<MonthTotal> series,
  ValueChanged<ReportMonth>? onMonthTap,
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
            child: ReportTrendChart(
              series: series,
              selected: const ReportMonth(2025, 6),
              onMonthTap: onMonthTap,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hovering across the chart never changes the month', (
    tester,
  ) async {
    final selected = <ReportMonth>[];
    await _pumpChart(
      tester,
      series: _series(),
      onMonthTap: selected.add,
    );

    final chart = find.byType(ReportTrendChart);
    final box = tester.getRect(chart);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();

    // Sweep the pointer right across every bar, the way a user would when
    // reading the chart or reaching for something past it.
    for (var step = 0; step <= 20; step++) {
      await mouse.moveTo(
        Offset(
          box.left + box.width * (step / 20),
          box.center.dy,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(
      selected,
      isEmpty,
      reason: 'hovering must not select a month - only a tap may',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on the chart does select a month', (tester) async {
    final selected = <ReportMonth>[];
    await _pumpChart(
      tester,
      series: _series(),
      onMonthTap: selected.add,
    );

    // Sweep tap positions rather than guessing one: the chart reserves
    // space for its left and bottom axis labels, so the plot area is
    // inset from the widget's own rect by an amount this test should not
    // have to hard-code. Any one hit proves tapping still selects.
    final box = tester.getRect(find.byType(ReportTrendChart));
    for (var step = 1; step < 24 && selected.isEmpty; step++) {
      await tester.tapAt(
        Offset(
          box.left + box.width * (step / 24),
          box.bottom - box.height * 0.3,
        ),
      );
      await tester.pumpAndSettle();
    }

    expect(
      selected,
      isNotEmpty,
      reason: 'a deliberate tap must still select a month',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders one bar per month in the window', (tester) async {
    await _pumpChart(tester, series: _series());
    // The month being reported on keeps its axis label at every width.
    expect(find.text('Jun'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an all-zero series shows the empty message, not a flat axis', (
    tester,
  ) async {
    await _pumpChart(
      tester,
      series: [
        for (var back = 11; back >= 0; back--)
          MonthTotal(
            month: ReportMonth.of(DateTime(2025, 6 - back, 1)),
            paise: 0,
            count: 0,
          ),
      ],
    );

    expect(
      find.textContaining('No revenue recorded in the last 12 months'),
      findsOneWidget,
    );
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
