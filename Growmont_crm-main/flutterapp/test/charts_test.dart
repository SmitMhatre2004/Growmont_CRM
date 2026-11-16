// test/charts_test.dart
//
// The shared chart kit: bucketDaily's granularity boundaries, the rounded
// axis scale, and every widget rendering with data and empty inside a
// 320px-wide column without overflow, plus the tooltip / tap behaviour.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/shared/charts/charts.dart';

List<DayTotal> _days(int n, {int sale = 1}) {
  final start = DateTime(2025, 1, 1);
  return [
    for (var i = 0; i < n; i++)
      DayTotal(
        day: DateTime(start.year, start.month, start.day + i),
        paise: 100000 * (1 + i % 5),
        count: i % sale == 0 ? 1 : 0,
      ),
  ];
}

Future<void> _pump(WidgetTester tester, Widget child, {double width = 320}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('bucketDaily', () {
    test('is empty for no days', () {
      expect(bucketDaily(const []), isEmpty);
    });

    test('62 days stay daily, 63 go weekly', () {
      expect(bucketUnitFor(62), BucketUnit.day);
      expect(bucketUnitFor(63), BucketUnit.week);

      final daily = bucketDaily(_days(62));
      expect(daily, hasLength(62));
      expect(daily.first.label, '1 Jan');

      final weekly = bucketDaily(_days(63));
      expect(weekly.length, lessThan(15));
      expect(weekly.first.label, startsWith('Wk of '));
    });

    test('366 days stay weekly, 367 go monthly', () {
      expect(bucketUnitFor(366), BucketUnit.week);
      expect(bucketUnitFor(367), BucketUnit.month);

      expect(bucketDaily(_days(366)).first.label, startsWith('Wk of '));

      final monthly = bucketDaily(_days(367));
      expect(monthly, hasLength(13));
      expect(monthly.first.label, 'Jan 25');
      expect(monthly.last.label, 'Jan 26');
    });

    test('totals and counts survive bucketing', () {
      final days = _days(120);
      for (final unit in BucketUnit.values) {
        final points = bucketDaily(days, unit: unit);
        expect(
          points.fold<double>(0, (s, p) => s + p.y),
          days.fold<double>(0, (s, d) => s + d.rupees),
        );
        expect(
          points.fold<int>(0, (s, p) => s + p.count),
          days.fold<int>(0, (s, d) => s + d.count),
        );
      }
    });

    test('weeks start on Monday and the first label names the first day', () {
      // 2025-01-01 is a Wednesday.
      final points = bucketDaily(_days(70));
      expect(points.first.x, DateTime(2025, 1, 1));
      expect(points[1].x, DateTime(2025, 1, 6));
    });

    test('an explicit unit overrides the automatic one', () {
      expect(bucketDaily(_days(120), unit: BucketUnit.month), hasLength(4));
    });
  });

  group('niceScale', () {
    test('rounds the maximum up to a 1/2/5 step with head-room', () {
      final s = niceScale(1180000);
      expect(s.step, 500000);
      expect(s.max, greaterThanOrEqualTo(1180000));
      expect(s.ticks.first, 0);
      expect(s.ticks.length, inInclusiveRange(4, 6));
    });

    test('never returns a zero scale', () {
      expect(niceScale(0).max, greaterThan(0));
    });
  });

  group('formatting', () {
    test('axis labels are compact and drop a trailing .0', () {
      expect(ChartTheme.axisMoney(0), '₹0');
      expect(ChartTheme.axisMoney(20000), '₹20K');
      expect(ChartTheme.axisMoney(75500), '₹75.5K');
      expect(ChartTheme.axisMoney(120000), '₹1.2L');
      expect(ChartTheme.axisMoney(10000000), '₹1Cr');
    });
  });

  group('widgets at 320px', () {
    final points = bucketDaily(_days(90));
    final bars = [
      for (var i = 0; i < 12; i++)
        ChartBar(label: 'M${i + 1}', value: 10000.0 * (i + 1)),
    ];
    final slices = [
      const ChartSlice(label: 'PMS And Portfolio Services', value: 5000000),
      const ChartSlice(label: 'Mutual Funds', value: 3000000),
      const ChartSlice(label: 'Zero', value: 0),
      const ChartSlice(label: 'Bonds', value: 1000000),
    ];

    testWidgets('area chart renders with data', (tester) async {
      await _pump(tester, GrowAreaChart(points: points));
      expect(tester.takeException(), isNull);
    });

    testWidgets('area chart handles one point and no y axis', (tester) async {
      await _pump(
        tester,
        GrowAreaChart(
          points: const [ChartPoint(label: 'Only', y: 5)],
          showYAxis: false,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('area chart renders empty', (tester) async {
      await _pump(tester, const GrowAreaChart(points: []));
      expect(find.text('No data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bar chart renders with data and empty', (tester) async {
      await _pump(tester, GrowBarChart(bars: bars, selectedIndex: 11));
      expect(tester.takeException(), isNull);

      await _pump(tester, const GrowBarChart(bars: []));
      expect(find.text('No data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bar chart with a long daily series does not overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        GrowBarChart(
          bars: [
            for (var i = 0; i < 62; i++)
              ChartBar(label: '${i + 1}', value: (i % 7) * 1000.0),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('donut renders stacked, measured and empty', (tester) async {
      await _pump(
        tester,
        GrowDonutChart(slices: slices, centerLabel: 'Revenue', stacked: true),
      );
      expect(find.text('Zero'), findsNothing);
      expect(tester.takeException(), isNull);

      await _pump(tester, GrowDonutChart(slices: slices));
      expect(tester.takeException(), isNull);

      await _pump(tester, const GrowDonutChart(slices: []));
      expect(find.text('No data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ranked bars render with data and empty', (tester) async {
      await _pump(
        tester,
        const GrowRankedBars(
          items: [
            RankedItem(
              label: 'A very long category name that has to be cut short',
              value: 9,
              valueText: '₹9,00,000',
              subText: '4 deals',
              shareText: '90%',
            ),
            RankedItem(label: 'Small', value: 1, valueText: '₹1,000'),
          ],
        ),
      );
      expect(find.text('Small'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pump(tester, const GrowRankedBars(items: []));
      expect(find.text('No data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('segment bar and legend render with data and empty', (
      tester,
    ) async {
      const segments = [
        ChartSegment(
          label: 'Monthly',
          value: 3,
          color: Colors.blue,
          valueText: '₹3K',
        ),
        ChartSegment(label: 'Skipped', value: 0, color: Colors.red),
        ChartSegment(
          label: 'A rather long frequency label',
          value: 1,
          color: Colors.green,
          valueText: '₹1K',
        ),
      ];
      await _pump(
        tester,
        const Column(
          children: [
            GrowSegmentBar(segments: segments),
            GrowSegmentLegend(segments: segments),
          ],
        ),
      );
      expect(find.text('Skipped'), findsNothing);
      expect(find.text('75%'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pump(
        tester,
        const Column(
          children: [
            GrowSegmentBar(segments: []),
            GrowSegmentLegend(segments: []),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChartEmpty keeps its height', (tester) async {
      await _pump(tester, const ChartEmpty(height: 120));
      expect(tester.getSize(find.byType(ChartEmpty)).height, 120);
    });
  });

  group('interaction', () {
    testWidgets('hovering an area chart shows a tooltip card', (tester) async {
      await _pump(
        tester,
        GrowAreaChart(
          points: bucketDaily(_days(30)),
          valueFormatter: (v) => 'VALUE ${v.round()}',
        ),
        width: 600,
      );
      expect(find.byType(ChartTooltipCard), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(GrowAreaChart)));
      await tester.pump();

      expect(find.byType(ChartTooltipCard), findsOneWidget);
      expect(find.textContaining('VALUE'), findsOneWidget);

      await mouse.moveTo(const Offset(5, 790));
      await tester.pump();
      expect(find.byType(ChartTooltipCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a bar reports its index and shows the tooltip', (
      tester,
    ) async {
      final taps = <int>[];
      await _pump(
        tester,
        GrowBarChart(
          bars: [
            for (var i = 0; i < 4; i++)
              ChartBar(label: 'B$i', value: 1000.0 * (i + 1), detail: 'd$i'),
          ],
          onTap: taps.add,
          selectedIndex: 3,
          showValueOnSelected: true,
        ),
        width: 600,
      );

      final rect = tester.getRect(find.byType(GrowBarChart));
      await tester.tapAt(Offset(rect.left + rect.width * 0.2, rect.center.dy));
      await tester.pump();

      expect(taps, [0]);
      expect(find.byType(ChartTooltipCard), findsOneWidget);
      expect(find.text('d0'), findsOneWidget);

      // The touch tooltip fades on its own after a few seconds.
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(ChartTooltipCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
