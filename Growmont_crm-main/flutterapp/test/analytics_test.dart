import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/features/dashboard/widgets/analytics_section.dart';
import 'package:growmont_crm/models/sale.dart';
import 'package:growmont_crm/shared/widgets/monthly_revenue_chart.dart';

Sale saleOn(
  DateTime date, {
  int? paise,
  String? amount,
  String product = 'mf',
  String? productDisplay,
}) {
  return Sale.fromJson({
    'id': 's_${date.microsecondsSinceEpoch}',
    'date': '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'amount_paise': ?paise,
    'amount': ?amount,
    'product': product,
    'product_display': ?productDisplay,
  });
}

void main() {
  group('Dashboard analytics aggregation', () {
    test('salePaise prefers amount_paise over the rupee string', () {
      expect(salePaise(saleOn(DateTime(2026, 1, 5), paise: 123456)), 123456);
    });

    test('salePaise falls back to the rupee amount when paise is absent', () {
      expect(salePaise(saleOn(DateTime(2026, 1, 5), amount: '1234.56')), 123456);
    });

    test('compactRupees uses Indian units', () {
      expect(compactRupees(500), '₹500');
      expect(compactRupees(45000), '₹45K');
      expect(compactRupees(150000), '₹1.5L');
      expect(compactRupees(25000000), '₹2.5Cr');
    });

    test('monthlyRevenue returns one bucket per month, oldest first', () {
      final series = monthlyRevenue([], months: 6);
      expect(series.length, 6);
      expect(series.every((e) => e.rupees == 0), isTrue);
    });

    test('monthlyRevenue sums sales into their own month', () {
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, 15);
      final twoMonthsAgo = DateTime(now.year, now.month - 2, 10);

      final series = monthlyRevenue([
        saleOn(thisMonth, paise: 100000), // ₹1,000
        saleOn(thisMonth, paise: 50000), // ₹500
        saleOn(twoMonthsAgo, paise: 250000), // ₹2,500
      ], months: 6);

      expect(series.last.rupees, 1500); // current month is last
      expect(series[series.length - 3].rupees, 2500);
    });

    test('monthlyRevenue ignores sales outside the window and bad dates', () {
      final now = DateTime.now();
      final longAgo = DateTime(now.year - 2, now.month, 10);

      final series = monthlyRevenue([
        saleOn(longAgo, paise: 999999),
        Sale.fromJson({'id': 'bad', 'date': 'not-a-date', 'amount_paise': 4242}),
      ], months: 6);

      expect(series.fold<double>(0, (sum, e) => sum + e.rupees), 0);
    });

    test('revenueByProduct groups by product and sorts highest first', () {
      final now = DateTime.now();
      final series = DashboardAnalytics.revenueByProduct([
        saleOn(now, paise: 100000, productDisplay: 'Mutual Fund'),
        saleOn(now, paise: 500000, productDisplay: 'Health Insurance'),
        saleOn(now, paise: 200000, productDisplay: 'Mutual Fund'),
      ]);

      expect(series.length, 2);
      expect(series[0].label, 'Health Insurance');
      expect(series[0].rupees, 5000);
      expect(series[1].label, 'Mutual Fund');
      expect(series[1].rupees, 3000);
    });

    test('revenueByProduct rolls up beyond top 5 into Other without duplicate key crash', () {
      final now = DateTime.now();
      final sales = [
        saleOn(now, paise: 600000, productDisplay: 'Product 1'),
        saleOn(now, paise: 500000, productDisplay: 'Product 2'),
        saleOn(now, paise: 400000, productDisplay: 'Product 3'),
        saleOn(now, paise: 300000, productDisplay: 'Product 4'),
        saleOn(now, paise: 200000, productDisplay: 'Other'),
        saleOn(now, paise: 100000, productDisplay: 'Product 6'),
        saleOn(now, paise: 50000, productDisplay: 'Product 7'),
      ];

      final series = DashboardAnalytics.revenueByProduct(sales);
      expect(series.length, 6);
      final labels = series.map((e) => e.label).toSet();
      expect(labels.length, series.length);
      expect(series.any((e) => e.label == 'Other Products'), isTrue);
    });

    testWidgets('Product Mix dropdown changes selection correctly', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final sales = [
        saleOn(now, paise: 500000, productDisplay: 'Mutual Funds'),
        saleOn(now, paise: 300000, productDisplay: 'Life Insurance'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardAnalytics(
                sales: sales,
                interactions: const [],
                reminders: const [],
              ),
            ),
          ),
        ),
      );

      final dropdownFinder = find.byWidgetPredicate(
        (w) =>
            w is DropdownButton<String> &&
            (w.value == 'Mutual Funds' || w.value == 'Life Insurance'),
      );
      expect(dropdownFinder, findsOneWidget);

      final DropdownButton<String> initialDropdown = tester.widget(dropdownFinder);
      expect(initialDropdown.value, 'Mutual Funds');

      // Tap dropdown to open menu
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Select 'Life Insurance'
      final menuItemFinder = find.widgetWithText(DropdownMenuItem<String>, 'Life Insurance').last;
      await tester.tap(menuItemFinder);
      await tester.pumpAndSettle();

      // Verify dropdown updated
      final DropdownButton<String> updatedDropdown = tester.widget(dropdownFinder);
      expect(updatedDropdown.value, 'Life Insurance');
    });

    testWidgets('Revenue Trend and Product Mix cards match height when side by side', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final sales = [
        saleOn(now, paise: 500000, productDisplay: 'Mutual Funds'),
        saleOn(now, paise: 300000, productDisplay: 'Life Insurance'),
        saleOn(now, paise: 120000, productDisplay: 'General Insurance'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardAnalytics(
                sales: sales,
                interactions: const [],
                reminders: const [],
              ),
            ),
          ),
        ),
      );

      // The equal-height layout uses IntrinsicHeight, which throws if any
      // descendant is a LayoutBuilder.
      expect(tester.takeException(), isNull);

      Size cardSize(String title) => tester.getSize(
        find
            .ancestor(of: find.text(title), matching: find.byType(Container))
            .first,
      );

      expect(cardSize('Revenue Trend').height, cardSize('Product Mix').height);
    });

    testWidgets('Tapping legend item in Product Mix updates selected product', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final sales = [
        saleOn(now, paise: 500000, productDisplay: 'Mutual Funds'),
        saleOn(now, paise: 300000, productDisplay: 'Life Insurance'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardAnalytics(
                sales: sales,
                interactions: const [],
                reminders: const [],
              ),
            ),
          ),
        ),
      );

      // Tap legend item for 'Life Insurance'
      final legendItemFinder = find.widgetWithText(InkWell, 'Life Insurance');
      expect(legendItemFinder, findsOneWidget);
      await tester.tap(legendItemFinder);
      await tester.pumpAndSettle();

      final DropdownButton<String> dropdown = tester.widget(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButton<String> &&
              (w.value == 'Mutual Funds' || w.value == 'Life Insurance'),
        ),
      );
      expect(dropdown.value, 'Life Insurance');
    });
  });
}
