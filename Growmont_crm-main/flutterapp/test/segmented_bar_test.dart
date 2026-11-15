// test/segmented_bar_test.dart
//
// The segmented bar and the mini stat row — the two forms that exist so
// the report is not four copies of the same chart.
//
// What is worth pinning here is the part that would quietly go wrong:
// an ordered scale must stay in scale order, zero parts must not draw a
// block, and the list must carry the figures the bar deliberately does
// not print.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/reports/widgets/segmented_bar.dart';

CategoryTotal cat(String label, int paise, {int count = 1}) =>
    CategoryTotal(label: label, paise: paise, count: count);

Future<void> pumpBar(
  WidgetTester tester, {
  required List<CategoryTotal> rows,
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width + 80, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SegmentedBarList(rows: rows, animate: false),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpStats(
  WidgetTester tester, {
  required List<CategoryTotal> rows,
}) async {
  tester.view.physicalSize = const Size(500, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 380, child: MiniStatRow(rows: rows)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SegmentedBarList', () {
    testWidgets('lists every part with its name, amount and share', (
      tester,
    ) async {
      await pumpBar(
        tester,
        rows: [cat('Monthly', 7500000), cat('Yearly', 2500000)],
      );

      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Yearly'), findsOneWidget);
      expect(find.text('₹75,000'), findsOneWidget);
      expect(find.text('₹25,000'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the given scale order, not largest first', (
      tester,
    ) async {
      // Deliberately smallest first: an ordered scale must not be
      // re-sorted by size on its way to the screen.
      await pumpBar(
        tester,
        rows: [
          cat('Monthly', 1000000),
          cat('Quarterly', 5000000),
          cat('Yearly', 2000000),
        ],
      );

      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d == 'Monthly' || d == 'Quarterly' || d == 'Yearly')
          .toList();
      expect(labels, ['Monthly', 'Quarterly', 'Yearly']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero part draws nothing and is not listed', (tester) async {
      await pumpBar(
        tester,
        rows: [
          cat('Monthly', 5000000),
          cat('Quarterly', 0, count: 0),
          cat('Yearly', 5000000),
        ],
      );

      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Yearly'), findsOneWidget);
      expect(find.text('Quarterly'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shares are computed over the parts that are present', (
      tester,
    ) async {
      await pumpBar(
        tester,
        rows: [cat('A', 5000000), cat('B', 0, count: 0), cat('C', 5000000)],
      );
      // 50/50 between the two present parts, not 33/33 across three.
      expect(find.text('50%'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an all-zero set shows the empty message', (tester) async {
      await pumpBar(
        tester,
        rows: [cat('Monthly', 0, count: 0), cat('Yearly', 0, count: 0)],
      );
      expect(find.textContaining('Nothing to break down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty list shows the empty message', (tester) async {
      await pumpBar(tester, rows: const []);
      expect(find.textContaining('Nothing to break down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tiny sliver keeps a decimal rather than reading 0%', (
      tester,
    ) async {
      await pumpBar(
        tester,
        rows: [cat('Big', 99900000), cat('Sliver', 100000)],
      );
      expect(find.text('0%'), findsNothing);
      expect(find.textContaining('0.1%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a very narrow rail without overflowing', (
      tester,
    ) async {
      await pumpBar(
        tester,
        width: 260,
        rows: [
          cat('Half Yearly', 5960000),
          cat('One Time', 17190000),
          cat('Quarterly', 10440000),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('MiniStatRow', () {
    testWidgets('shows a label and count per entry', (tester) async {
      await pumpStats(
        tester,
        rows: [
          const CategoryTotal(label: 'High', paise: 0, count: 4),
          const CategoryTotal(label: 'Medium', paise: 0, count: 2),
          const CategoryTotal(label: 'Low', paise: 0, count: 1),
        ],
      );

      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('MEDIUM'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero entry still renders, as a zero', (tester) async {
      await pumpStats(
        tester,
        rows: [
          const CategoryTotal(label: 'High', paise: 0, count: 0),
          const CategoryTotal(label: 'Low', paise: 0, count: 3),
        ],
      );
      expect(find.text('0'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty list shows the empty message', (tester) async {
      await pumpStats(tester, rows: const []);
      expect(find.textContaining('Nothing logged'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
