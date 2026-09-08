import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/interaction.dart';
import '../../../models/reminder.dart';
import '../../../models/sale.dart';
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

  /// Shades of the same blue, darkest first, so the largest slice reads
  /// strongest and the series stays monochrome.
  static const _palette = <Color>[
    Color(0xFF1E3A8A),
    Color(0xFF1D4ED8),
    Color(0xFF2563EB),
    Color(0xFF3B82F6),
    Color(0xFF60A5FA),
    Color(0xFF93C5FD),
  ];

  static String _productLabel(String code) {
    for (final (value, label) in productCategories) {
      if (value == code) return label;
    }
    return code.isEmpty ? 'Unspecified' : code;
  }

  /// Revenue split by product, largest first, with a rolled-up "Other".
  static List<({String label, double rupees})> revenueByProduct(List<Sale> sales) {
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

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _revenueTrendCard()),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: _productMixCard()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _revenueTrendCard(),
        const SizedBox(height: 10),
        _productMixCard(),
      ],
    );
  }

  static Widget _chartCard({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? headerAction,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (headerAction == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.cardTitle),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.caption),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTypography.cardTitle),
                        const SizedBox(height: 2),
                        Text(subtitle, style: AppTypography.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  headerAction,
                ],
              ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _revenueTrendCard() {
    return _chartCard(
      title: 'Revenue Trend',
      subtitle: 'Booked value, last 6 months',
      child: MonthlyRevenueChart(
        sales: sales,
        emptyMessage: 'No sales in the last 6 months',
      ),
    );
  }

  Widget _productMixCard() {
    return _ProductMixCard(sales: sales, palette: _palette);
  }
}

class _ProductMixCard extends StatefulWidget {
  const _ProductMixCard({
    required this.sales,
    required this.palette,
  });

  final List<Sale> sales;
  final List<Color> palette;

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
        subtitle: 'Revenue share by product',
        child: const SizedBox(
          height: 190,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  size: 28,
                  color: AppColors.textMuted,
                ),
                SizedBox(height: 6),
                Text(
                  'No product revenue yet',
                  style: AppTypography.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Keep selection valid within available items
    if (_selectedLabel == null || !series.any((e) => e.label == _selectedLabel)) {
      _selectedLabel = series.first.label;
    }

    int selectedIndex = series.indexWhere((e) => e.label == _selectedLabel);
    if (selectedIndex == -1) selectedIndex = 0;

    final selected = series[selectedIndex];
    final selectedPercent = (selected.rupees / total * 100).toStringAsFixed(0);

    return DashboardAnalytics._chartCard(
      title: 'Product Mix',
      subtitle: 'Revenue share by product',
      headerAction: DropdownButtonHideUnderline(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButton<String>(
            value: _selectedLabel,
            isDense: true,
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(8),
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            style: AppTypography.itemSubtitle,
            selectedItemBuilder: (context) {
              return series.map((item) {
                final color = widget.palette[series.indexOf(item) % widget.palette.length];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
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
                );
              }).toList();
            },
            items: series.map((item) {
              final color = widget.palette[series.indexOf(item) % widget.palette.length];
              return DropdownMenuItem<String>(
                value: item.label,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        item.label,
                        style: AppTypography.itemSubtitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedLabel = value;
                });
              }
            },
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 310;

          final pieWidget = SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 46,
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          return;
                        }
                        if (event is FlTapUpEvent) {
                          final touchedIndex = pieTouchResponse
                              .touchedSection!
                              .touchedSectionIndex;
                          if (touchedIndex >= 0 &&
                              touchedIndex < series.length) {
                            setState(() {
                              _selectedLabel = series[touchedIndex].label;
                            });
                          }
                        }
                      },
                    ),
                    sections: [
                      for (var i = 0; i < series.length; i++)
                        PieChartSectionData(
                          value: series[i].rupees,
                          color: widget.palette[i % widget.palette.length],
                          radius: i == selectedIndex ? 44 : 38,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                // Center label showing selected product's revenue and percentage
                IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          compactRupees(selected.rupees),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '$selectedPercent%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          final listWidget = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < series.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    setState(() {
                      _selectedLabel = series[i].label;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 5,
                      horizontal: 2,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: widget.palette[i % widget.palette.length],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            series[i].label,
                            style: i == selectedIndex
                                ? AppTypography.itemSubtitle.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  )
                                : AppTypography.itemSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${(series[i].rupees / total * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: i == selectedIndex
                                ? FontWeight.bold
                                : FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );

          if (isNarrow) {
            return Column(
              children: [
                pieWidget,
                const SizedBox(height: 12),
                listWidget,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: pieWidget),
              const SizedBox(width: 14),
              Expanded(flex: 5, child: listWidget),
            ],
          );
        },
      ),
    );
  }
}
