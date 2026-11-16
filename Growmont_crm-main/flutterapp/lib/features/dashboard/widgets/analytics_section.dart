import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart' show DayTotal;
import '../../../core/theme/app_theme.dart';
import '../../../models/interaction.dart';
import '../../../models/reminder.dart';
import '../../../models/sale.dart';
import '../../../shared/charts/charts.dart';
import '../../../shared/widgets/monthly_revenue_chart.dart';

/// Revenue and activity analytics derived from the data the dashboard has
/// already loaded, so drawing them costs no extra reads.
class DashboardAnalytics extends StatelessWidget {
  const DashboardAnalytics({
    super.key,
    required this.sales,
    required this.interactions,
    required this.reminders,
  });

  final List<Sale> sales;
  final List<Interaction> interactions;
  final List<Reminder> reminders;

  static String _productLabel(String code) {
    for (final (value, label) in productCategories) {
      if (value == code) return label;
    }
    return code.isEmpty ? 'Unspecified' : code;
  }

  /// Revenue split by product, largest first, with a rolled-up "Other".
  static List<({String label, double rupees})> revenueByProduct(
    List<Sale> sales,
  ) {
    final totals = <String, double>{};
    for (final s in sales) {
      final label = (s.productDisplay != null && s.productDisplay!.isNotEmpty)
          ? s.productDisplay!
          : _productLabel(s.product);
      totals[label] = (totals[label] ?? 0) + salePaise(s) / 100;
    }

    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.length <= 5) {
      return [for (final e in entries) (label: e.key, rupees: e.value)];
    }

    final top5 = entries.take(5).toList();
    final other = entries.skip(5).fold<double>(0, (sum, e) => sum + e.value);
    final hasOther = top5.any((e) => e.key == 'Other');
    final otherLabel = hasOther ? 'Other Products' : 'Other';
    return [
      for (final e in top5) (label: e.key, rupees: e.value),
      (label: otherLabel, rupees: other),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    // The product mix card's pie/list layout depends on how wide that card
    // ends up, so it is measured here rather than inside the card: a
    // LayoutBuilder *under* the IntrinsicHeight below would throw, since
    // intrinsic dimensions cannot be computed through one.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (isWide) {
          // The mix card is flex 2 of 5 once the gap is taken out, and
          // _chartCard pads its content by AppSpacing.lg on each side.
          final mixContentWidth =
              (constraints.maxWidth - AppSpacing.md) * 2 / 5 - AppSpacing.lg * 2;

          // IntrinsicHeight + stretch makes both cards match the taller
          // one's height, regardless of chart size or how many products
          // are listed.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _revenueTrendCard()),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: _productMixCard(isNarrow: mixContentWidth < 310),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _revenueTrendCard(),
            const SizedBox(height: AppSpacing.md),
            _productMixCard(
              isNarrow: constraints.maxWidth - AppSpacing.lg * 2 < 310,
            ),
          ],
        );
      },
    );
  }

  static Widget _chartCard({
    required String title,
    required Widget child,
    Widget? headerAction,
  }) {
    final heading = Text(title, style: AppTypography.sectionTitle);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (headerAction == null)
              heading
            else
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  heading,
                  FittedBox(fit: BoxFit.scaleDown, child: headerAction),
                ],
              ),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }

  Widget _revenueTrendCard() {
    return _RevenueTrendAreaChart(sales: sales);
  }

  Widget _productMixCard({required bool isNarrow}) {
    return _ProductMixCard(sales: sales, isNarrow: isNarrow);
  }
}

class _RevenueTrendAreaChart extends StatefulWidget {
  const _RevenueTrendAreaChart({required this.sales});

  final List<Sale> sales;

  @override
  State<_RevenueTrendAreaChart> createState() => _RevenueTrendAreaChartState();
}

class _RevenueTrendAreaChartState extends State<_RevenueTrendAreaChart> {
  String _timeRange = '90d';

  static int _daysFor(String range) => switch (range) {
    '7d' => 7,
    '30d' => 30,
    _ => 90,
  };

  /// Daily revenue for the selected range, ending today and
  /// zero-filled so a quiet stretch keeps its width. Bucketing (weekly for
  /// three months) happens afterwards in [bucketDaily].
  List<DayTotal> _dailyTotals() {
    final dated = <(DateTime, Sale)>[];
    for (final sale in widget.sales) {
      final parsed = DateTime.tryParse(sale.date);
      if (parsed != null) {
        dated.add((DateTime(parsed.year, parsed.month, parsed.day), sale));
      }
    }
    if (dated.isEmpty) return const [];

    // The window ends today (or on a future-dated sale, if any), so
    // "Last 7 days" really means the last 7 days.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final latest =
        dated.map((e) => e.$1).reduce((a, b) => a.isAfter(b) ? a : b);
    final end = latest.isAfter(today) ? latest : today;
    final start = DateTime(end.year, end.month, end.day - _daysFor(_timeRange));

    final paise = <DateTime, int>{};
    final counts = <DateTime, int>{};
    for (final (day, sale) in dated) {
      if (day.isBefore(start) || day.isAfter(end)) continue;
      paise[day] = (paise[day] ?? 0) + salePaise(sale);
      counts[day] = (counts[day] ?? 0) + 1;
    }

    final span = end.difference(start).inDays;
    return [
      for (var i = 0; i <= span; i++)
        () {
          final day = DateTime(start.year, start.month, start.day + i);
          return DayTotal(
            day: day,
            paise: paise[day] ?? 0,
            count: counts[day] ?? 0,
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final points = bucketDaily(_dailyTotals());
    final hasData = points.any((p) => p.y > 0);

    return DashboardAnalytics._chartCard(
      title: 'Revenue Trend',
      headerAction: _buildTimeRangeSelector(),
      child: hasData
          ? GrowAreaChart(points: points, height: 250)
          : const ChartEmpty(
              height: 250,
              message: 'No revenue in selected period',
            ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButton<String>(
          value: _timeRange,
          isDense: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          icon: const Icon(Icons.keyboard_arrow_down, size: AppSizing.iconMd),
          style: AppTypography.itemSubtitle,
          items: const [
            DropdownMenuItem(value: '90d', child: Text('Last 3 months')),
            DropdownMenuItem(value: '30d', child: Text('Last 30 days')),
            DropdownMenuItem(value: '7d', child: Text('Last 7 days')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _timeRange = value;
              });
            }
          },
        ),
      ),
    );
  }
}

class _ProductMixCard extends StatefulWidget {
  const _ProductMixCard({required this.sales, required this.isNarrow});

  final List<Sale> sales;

  /// Stack the pie above the legend instead of side by side. Measured by
  /// the parent, since this card may sit under an IntrinsicHeight.
  final bool isNarrow;

  @override
  State<_ProductMixCard> createState() => _ProductMixCardState();
}

class _ProductMixCardState extends State<_ProductMixCard> {
  String? _selectedLabel;

  @override
  Widget build(BuildContext context) {
    final series = DashboardAnalytics.revenueByProduct(widget.sales);
    final total = series.fold<double>(0, (sum, e) => sum + e.rupees);

    if (total <= 0) {
      return DashboardAnalytics._chartCard(
        title: 'Product Mix',
        child: const ChartEmpty(height: 190, message: 'No product revenue yet'),
      );
    }

    // Keep selection valid within available items
    if (_selectedLabel == null ||
        !series.any((e) => e.label == _selectedLabel)) {
      _selectedLabel = series.first.label;
    }
    var selectedIndex = series.indexWhere((e) => e.label == _selectedLabel);
    if (selectedIndex == -1) selectedIndex = 0;

    return DashboardAnalytics._chartCard(
      title: 'Product Mix',
      headerAction: _buildProductSelector(series),
      child: GrowDonutChart(
        slices: [
          for (final e in series)
            ChartSlice(
              label: e.label,
              value: e.rupees,
              color: productColor(e.label),
            ),
        ],
        centerLabel: 'Revenue',
        stacked: widget.isNarrow,
        selectedIndex: selectedIndex,
        onSelected: (i) => setState(() => _selectedLabel = series[i].label),
      ),
    );
  }

  Widget _buildProductSelector(List<({String label, double rupees})> series) {
    Widget dot(String label, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: productColor(label),
        shape: BoxShape.circle,
      ),
    );

    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButton<String>(
          value: _selectedLabel,
          isDense: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          icon: const Icon(Icons.keyboard_arrow_down, size: AppSizing.iconMd),
          style: AppTypography.itemSubtitle,
          selectedItemBuilder: (context) => [
            for (final item in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  dot(item.label, 10),
                  const SizedBox(width: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      item.label,
                      style: AppTypography.itemSubtitle.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
          ],
          items: [
            for (final item in series)
              DropdownMenuItem<String>(
                value: item.label,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(item.label, 11),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        item.label,
                        style: AppTypography.itemSubtitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _selectedLabel = value);
          },
        ),
      ),
    );
  }
}
