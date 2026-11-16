// test/ranked_bar_chart_test.dart
//
// The ranked bar chart's contract: every row rendered, the tail folded,
// and — the part most likely to break — a value label that is placed
// inside its bar only when it actually fits, and outside it otherwise.
//
// Animation is disabled in these tests. The entrance tween is real
// behaviour, but asserting against a half-grown bar would make every
// geometry check a race.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/reports/widgets/ranked_bar_chart.dart';

CategoryTotal cat(String label, int paise, {int count = 1}) =>
    CategoryTotal(label: label, paise: paise, count: count);

Future<void> pumpChart(
  WidgetTester tester, {
  required List<CategoryTotal> rows,
  int? maxRows = 8,
  bool showAmount = true,
  double width = 720,
}) async {
  tester.view.physicalSize = Size(width + 80, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: RankedBarChart(
              rows: rows,
              maxRows: maxRows,
              showAmount: showAmount,
              animate: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders a row per category, largest first', (tester) async {
    await pumpChart(
      tester,
      rows: [
        cat('PMS', 21610000, count: 12),
        cat('General Insurance', 11860000, count: 7),
        cat('Bonds', 3410000, count: 2),
      ],
    );

    expect(find.text('PMS'), findsOneWidget);
    expect(find.text('General Insurance'), findsOneWidget);
    expect(find.text('Bonds'), findsOneWidget);

    // Rank numerals make the ordering explicit.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the deal count as a second measure', (tester) async {
    await pumpChart(tester, rows: [cat('PMS', 21610000, count: 12)]);
    expect(find.text('12 deals'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('singular count is not pluralized', (tester) async {
    await pumpChart(tester, rows: [cat('PMS', 500000, count: 1)]);
    expect(find.text('1 deal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares are computed against the visible total', (tester) async {
    await pumpChart(
      tester,
      rows: [cat('A', 7500000), cat('B', 2500000)],
    );
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tiny share keeps one decimal rather than rounding to 0%', (
    tester,
  ) async {
    await pumpChart(
      tester,
      rows: [cat('Big', 99900000), cat('Tiny', 100000)],
    );
    expect(find.text('0%'), findsNothing);
    expect(find.textContaining('0.1%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('value label placement', () {
    // The label is white when it sits inside the bar and ink-coloured when
    // it sits outside, so its colour is a reliable proxy for which branch
    // ran — and the thing worth pinning, since a mis-measure would clip
    // the figure.
    Color labelColour(WidgetTester tester, String text) {
      return tester.widget<Text>(find.text(text)).style!.color!;
    }

    testWidgets('a long bar carries its value inside', (tester) async {
      await pumpChart(tester, rows: [cat('Leader', 21610000, count: 12)]);
      expect(labelColour(tester, '₹2,16,100'), Colors.white);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short bar moves its value outside the end', (tester) async {
      await pumpChart(
        tester,
        rows: [cat('Leader', 90000000), cat('Sliver', 100000)],
      );
      // The leader fills the track, so its own label is inside...
      expect(labelColour(tester, '₹9,00,000'), Colors.white);
      // ...while the sliver's cannot fit and sits outside in ink.
      expect(labelColour(tester, '₹1,000'), AppColors.textPrimary);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very narrow card pushes labels outside, never clips', (
      tester,
    ) async {
      await pumpChart(
        tester,
        width: 340,
        rows: [cat('Mutual Funds', 21610000, count: 12)],
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('tail folding', () {
    testWidgets('rows past maxRows fold into one Other bar', (tester) async {
      await pumpChart(
        tester,
        maxRows: 4,
        rows: [for (var i = 0; i < 10; i++) cat('Cat $i', (10 - i) * 100000)],
      );

      expect(find.textContaining('Other (7)'), findsOneWidget);
      expect(find.text('Cat 0'), findsOneWidget);
      expect(find.text('Cat 9'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('folding keeps the shares adding to the whole', (tester) async {
      await pumpChart(
        tester,
        maxRows: 2,
        rows: [cat('A', 5000000), cat('B', 3000000), cat('C', 2000000)],
      );
      // A is 50%, and B+C fold into one row worth the remaining 50%.
      expect(find.text('50%'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an existing Other category is not shadowed', (tester) async {
      await pumpChart(
        tester,
        maxRows: 2,
        rows: [cat('Other', 5000000), cat('B', 3000000), cat('C', 1000000)],
      );
      expect(find.textContaining('Other categories'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('null maxRows shows everything', (tester) async {
      await pumpChart(
        tester,
        maxRows: null,
        rows: [for (var i = 0; i < 12; i++) cat('Cat $i', (12 - i) * 100000)],
      );
      expect(find.text('Cat 11'), findsOneWidget);
      expect(find.textContaining('Other'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a count-only chart hides the amount and the deals line', (
    tester,
  ) async {
    await pumpChart(
      tester,
      showAmount: false,
      rows: [
        const CategoryTotal(label: 'High', paise: 0, count: 4),
        const CategoryTotal(label: 'Low', paise: 0, count: 1),
      ],
    );

    expect(find.text('4'), findsWidgets);
    // No rupee figures, and no "n deals" subtitle, on a chart with no money.
    expect(find.textContaining('₹'), findsNothing);
    expect(find.textContaining('deals'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an all-zero series still renders every row', (tester) async {
    await pumpChart(
      tester,
      showAmount: false,
      rows: [
        const CategoryTotal(label: 'High', paise: 0, count: 0),
        const CategoryTotal(label: 'Medium', paise: 0, count: 0),
      ],
    );
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('narrow layout', () {
    // In a side rail the bar drops under the name. A bar squeezed between
    // a truncated label and two figures is unreadable, and comparing
    // lengths down the list is the only job the bar has.

    testWidgets('a narrow card still shows name, figure and share', (
      tester,
    ) async {
      await pumpChart(
        tester,
        width: 330,
        rows: [cat('One Time', 17190000, count: 2), cat('Monthly', 8620000, count: 2)],
      );

      expect(find.text('One Time'), findsOneWidget);
      expect(find.text('₹1,71,900'), findsOneWidget);
      expect(find.text('67%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the figure is not repeated on the bar when stacked', (
      tester,
    ) async {
      await pumpChart(
        tester,
        width: 330,
        rows: [cat('One Time', 17190000, count: 2)],
      );

      // Exactly once: on the line above the bar, never also inside it.
      expect(find.text('₹1,71,900'), findsOneWidget);
      // And in ink, not the white used for an in-bar label.
      expect(
        tester.widget<Text>(find.text('₹1,71,900')).style!.color,
        AppColors.textPrimary,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long category name does not overflow a narrow card', (
      tester,
    ) async {
      await pumpChart(
        tester,
        width: 300,
        rows: [
          cat('General Insurance And Allied Products', 9000000, count: 4),
          cat('Half Yearly', 5960000, count: 1),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('an empty list shows the empty message', (tester) async {
    await pumpChart(tester, rows: const []);
    expect(
      find.textContaining('Nothing to break down'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
