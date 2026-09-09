import 'dart:math' as math;

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

    if (isWide) {
      // IntrinsicHeight + stretch makes both cards match the taller one's
      // height, regardless of chart size or how many products are listed.
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: _revenueTrendCard()),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: _productMixCard()),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _revenueTrendCard(),
        const SizedBox(height: AppSpacing.md),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.sectionTitle),
                  const SizedBox(height: AppSpacing.xxs),
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
                        Text(title, style: AppTypography.sectionTitle),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(subtitle, style: AppTypography.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  headerAction,
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

  Widget _productMixCard() {
    return _ProductMixCard(sales: sales);
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

  // Helper to format a DateTime as "Apr 1"
  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  // Build aggregated daily revenue data for the selected range
  List<FlSpot> _buildRevenueSpots() {
    if (widget.sales.isEmpty) return [];

    final parsedDates = widget.sales
        .map((s) => DateTime.tryParse(s.date))
        .whereType<DateTime>()
        .toList();
    if (parsedDates.isEmpty) return [];

    // Determine reference date: most recent sale date
    final referenceDate = parsedDates.reduce((a, b) => a.isAfter(b) ? a : b);

    int daysToSubtract;
    switch (_timeRange) {
      case '7d':
        daysToSubtract = 7;
        break;
      case '30d':
        daysToSubtract = 30;
        break;
      default: // '90d'
        daysToSubtract = 90;
    }

    final startDate = referenceDate.subtract(Duration(days: daysToSubtract));
    final endDate = referenceDate;

    // Generate list of dates from startDate to endDate inclusive
    final dates = <DateTime>[];
    for (
      var d = startDate;
      !d.isAfter(endDate);
      d = d.add(const Duration(days: 1))
    ) {
      dates.add(DateTime(d.year, d.month, d.day));
    }

    // Sum revenue for each date
    final revenueByDate = <DateTime, double>{};
    for (final sale in widget.sales) {
      final parsed = DateTime.tryParse(sale.date);
      if (parsed == null) continue;
      final saleDate = DateTime(parsed.year, parsed.month, parsed.day);
      if (saleDate.isBefore(startDate) || saleDate.isAfter(endDate)) continue;
      revenueByDate[saleDate] =
          (revenueByDate[saleDate] ?? 0) + salePaise(sale) / 100;
    }

    // Convert to FlSpot, x = index
    return [
      for (var i = 0; i < dates.length; i++)
        FlSpot(i.toDouble(), revenueByDate[dates[i]] ?? 0),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final spots = _buildRevenueSpots();
    final hasData = spots.isNotEmpty && spots.any((spot) => spot.y > 0);

    return DashboardAnalytics._chartCard(
      title: 'Revenue Trend',
      subtitle: 'Booked value over time',
      headerAction: _buildTimeRangeSelector(),
      child: hasData
          ? Column(
              children: [
                SizedBox(height: 250, child: _buildChart(spots)),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Text('Revenue', style: AppTypography.caption),
                  ],
                ),
              ],
            )
          : const SizedBox(
              height: 250,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.show_chart_rounded,
                      size: AppSizing.iconXl,
                      color: AppColors.textMuted,
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Text(
                      'No revenue in selected period',
                      style: AppTypography.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
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

  Widget _buildChart(List<FlSpot> spots) {
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: _calculateMaxY(spots),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _calculateInterval(spots),
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.border.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: _calculateXInterval(spots.length),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= spots.length) return const SizedBox();
                final date = _dateFromIndex(index);
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _formatDate(date),
                    style: AppTypography.caption.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: _calculateInterval(spots),
              getTitlesWidget: (value, meta) {
                return Text(
                  value == 0 ? '0' : compactRupees(value),
                  style: AppTypography.caption.copyWith(fontSize: 10),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            tooltipRoundedRadius: AppRadius.md,
            tooltipPadding: const EdgeInsets.all(AppSpacing.sm),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                final date = _dateFromIndex(index);
                return LineTooltipItem(
                  '${_formatDate(date)}\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: 'Revenue: ${compactRupees(spot.y)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.normal,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            barWidth: 2.5,
            color: AppColors.primaryBlue,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primaryBlue.withValues(alpha: 0.8),
                  AppColors.primaryBlue.withValues(alpha: 0.1),
                ],
                stops: const [0.05, 0.95],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  // Helper to convert index back to a DateTime based on the current range
  DateTime _dateFromIndex(int index) {
    if (widget.sales.isEmpty) return DateTime.now();
    final parsedDates = widget.sales
        .map((s) => DateTime.tryParse(s.date))
        .whereType<DateTime>()
        .toList();
    if (parsedDates.isEmpty) return DateTime.now();
    final referenceDate = parsedDates.reduce((a, b) => a.isAfter(b) ? a : b);
    int daysToSubtract;
    switch (_timeRange) {
      case '7d':
        daysToSubtract = 7;
        break;
      case '30d':
        daysToSubtract = 30;
        break;
      default:
        daysToSubtract = 90;
    }
    final startDate = referenceDate.subtract(Duration(days: daysToSubtract));
    return startDate.add(Duration(days: index));
  }

  double _calculateMaxY(List<FlSpot> spots) {
    if (spots.isEmpty) return 100;
    final maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    // Add some padding
    return maxY * 1.2;
  }

  double _calculateInterval(List<FlSpot> spots) {
    final maxY = _calculateMaxY(spots);
    if (maxY <= 0) return 10;
    // Choose a nice round number: 1, 2, 5, 10, 20, 50, 100, etc.
    final rawInterval = maxY / 4;
    final magnitude = _magnitude(rawInterval);
    final normalized = rawInterval / magnitude;
    double niceInterval;
    if (normalized <= 1) {
      niceInterval = 1;
    } else if (normalized <= 2) {
      niceInterval = 2;
    } else if (normalized <= 5) {
      niceInterval = 5;
    } else {
      niceInterval = 10;
    }
    return niceInterval * magnitude;
  }

  double _magnitude(double value) {
    if (value == 0) return 1;
    final exponent = (math.log(value.abs()) / math.ln10).floor();
    return math.pow(10, exponent).toDouble();
  }

  double _calculateXInterval(int dataLength) {
    if (dataLength <= 0) return 1;
    if (dataLength <= 7) return 1;
    if (dataLength <= 30) return 5;
    return 14; // ~ weekly for 90 days
  }
}

class _ProductMixCard extends StatefulWidget {
  const _ProductMixCard({required this.sales});

  final List<Sale> sales;

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
                  size: AppSizing.iconXl,
                  color: AppColors.textMuted,
                ),
                SizedBox(height: AppSpacing.sm),
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
    if (_selectedLabel == null ||
        !series.any((e) => e.label == _selectedLabel)) {
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
            selectedItemBuilder: (context) {
              return series.map((item) {
                final color = productColor(item.label);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        item.label,
                        style: AppTypography.itemSubtitle.copyWith(
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
            items: series.map((item) {
              final color = productColor(item.label);
              return DropdownMenuItem<String>(
                value: item.label,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
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
            height: 195,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 40,
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
                          color: productColor(series[i].label),
                          radius: i == selectedIndex ? 54 : 34,
                          showTitle: false,
                        ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
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
                          style: AppTypography.metricMedium,
                        ),
                      ),
                      Text('$selectedPercent%', style: AppTypography.caption),
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
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  onTap: () {
                    setState(() {
                      _selectedLabel = series[i].label;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: productColor(series[i].label),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            series[i].label,
                            style: i == selectedIndex
                                ? AppTypography.itemSubtitle.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  )
                                : AppTypography.itemSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${(series[i].rupees / total * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: i == selectedIndex
                                ? FontWeight.w700
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
                const SizedBox(height: AppSpacing.md),
                listWidget,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: pieWidget),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 5, child: listWidget),
            ],
          );
        },
      ),
    );
  }
}
