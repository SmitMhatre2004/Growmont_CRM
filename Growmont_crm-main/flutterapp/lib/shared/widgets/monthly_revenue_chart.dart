import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/sale.dart';

/// A sale's value in paise. Money is summed in paise so repeated float
/// addition cannot drift; [Sale.amount] is only a fallback for older rows
/// written before `amount_paise` existed.
int salePaise(Sale s) => s.amountPaise != 0
    ? s.amountPaise
    : ((double.tryParse(s.amount) ?? 0) * 100).round();

/// Compact rupee label in Indian units: Cr, L, K.
String compactRupees(double rupees) {
  if (rupees >= 10000000) return '₹${(rupees / 10000000).toStringAsFixed(1)}Cr';
  if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  if (rupees >= 1000) return '₹${(rupees / 1000).toStringAsFixed(0)}K';
  return '₹${rupees.toStringAsFixed(0)}';
}

/// Revenue per month across the trailing [months] months, oldest first.
List<({String label, double rupees})> monthlyRevenue(
  List<Sale> sales, {
  int months = 6,
}) {
  final now = DateTime.now();
  final totals = <String, double>{};
  final buckets = <({String key, String label})>[];

  for (var i = months - 1; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i);
    final key = '${m.year}-${m.month}';
    buckets.add((key: key, label: DateFormat('MMM').format(m)));
    totals[key] = 0;
  }

  for (final s in sales) {
    final d = DateTime.tryParse(s.date);
    if (d == null) continue;
    final key = '${d.year}-${d.month}';
    if (totals.containsKey(key)) {
      totals[key] = totals[key]! + salePaise(s) / 100;
    }
  }

  return [
    for (final b in buckets) (label: b.label, rupees: totals[b.key] ?? 0),
  ];
}

/// Blue to match the dashboard's chart palette.
const _defaultBarColor = AppColors.info;

/// Bar chart of booked revenue per month, shared by the dashboard and the
/// employee detail screen.
class MonthlyRevenueChart extends StatelessWidget {
  const MonthlyRevenueChart({
    super.key,
    required this.sales,
    this.months = 6,
    this.height = 190,
    this.barColor = _defaultBarColor,
    this.emptyMessage = 'No sales in this period',
  });

  final List<Sale> sales;
  final int months;
  final double height;
  final Color barColor;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final series = monthlyRevenue(sales, months: months);
    final peak = series.fold<double>(0, (m, e) => e.rupees > m ? e.rupees : m);

    if (peak <= 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                size: AppSizing.iconXl,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                emptyMessage,
                style: AppTypography.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          // Head-room so the tallest bar never touches the top edge.
          maxY: peak * 1.25,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.border, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (value, meta) {
                  if (value <= 0) return const SizedBox.shrink();
                  return Text(
                    compactRupees(value),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= series.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      series[i].label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF0F172A),
              tooltipRoundedRadius: AppRadius.md,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final item = series[group.x.toInt()];
                return BarTooltipItem(
                  '${item.label}\n',
                  const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    height: 1.3,
                  ),
                  children: [
                    TextSpan(
                      text: AppFormatters.formatAmount(rod.toY.toString()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < series.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: series[i].rupees,
                    width: 18,
                    color: barColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
