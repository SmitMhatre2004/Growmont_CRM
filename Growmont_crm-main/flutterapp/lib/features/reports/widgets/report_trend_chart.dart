// lib/features/reports/widgets/report_trend_chart.dart
//
// The 12-month revenue trend, with the selected month highlighted so the
// reader can see where the month they are reading about sits in the run.
//
// Styling (grid, axis labels, tooltip, line geometry) deliberately mirrors
// MonthlyRevenueChart so the dashboard's chart and this one read as the
// same chart with a different window — see that file for the originals.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/monthly_revenue_chart.dart' show compactRupees;
import 'month_picker_bar.dart';

class ReportTrendChart extends StatelessWidget {
  const ReportTrendChart({
    super.key,
    required this.series,
    required this.selected,
    this.height = 220,
    this.onMonthTap,
  });

  final List<MonthTotal> series;

  /// The month the report is about; drawn in the accent colour while the
  /// rest of the window stays muted.
  final ReportMonth selected;

  final double height;

  /// Tapping a month re-runs the report for that month. Optional so the
  /// chart stays usable in a read-only context such as a test.
  final ValueChanged<ReportMonth>? onMonthTap;

  LineTooltipItem _tooltipItem(MonthTotal item, double y) {
    return LineTooltipItem(
      '${formatReportMonth(item.month, short: true)}\n',
      const TextStyle(
        color: AppColors.borderStrong,
        fontWeight: FontWeight.w500,
        fontSize: 11,
        height: 14 / 11,
      ),
      children: [
        TextSpan(
          text: compactRupees(y),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        TextSpan(
          text: '\n${item.count} ${item.count == 1 ? 'deal' : 'deals'}',
          style: const TextStyle(
            color: AppColors.borderStrong,
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final peak = series.fold<double>(
      0,
      (best, m) => m.rupees > best ? m.rupees : best,
    );

    if (peak <= 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.show_chart_rounded,
                size: AppSizing.iconXl,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No revenue recorded in the last ${series.length} months',
                style: AppTypography.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Narrow screens cannot fit 12 month labels; every other one keeps the
    // axis readable without dropping any points.
    final labelStride = MediaQuery.sizeOf(context).width < 640 ? 2 : 1;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: -0.4,
          maxX: series.length - 0.6,
          minY: 0,
          maxY: peak * 1.25,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.divider, strokeWidth: 1),
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
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  // minX/maxX are padded fractions, and fl_chart also asks for
                  // titles at those edges; only whole numbers are months.
                  if (value != value.roundToDouble()) {
                    return const SizedBox.shrink();
                  }
                  final i = value.toInt();
                  if (i < 0 || i >= series.length) {
                    return const SizedBox.shrink();
                  }
                  final month = series[i].month;
                  final isSelected = month == selected;
                  // The selected month always keeps its label even when
                  // the stride would have hidden it.
                  if (!isSelected &&
                      (series.length - 1 - i) % labelStride != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      formatReportMonth(month, short: true).split(' ').first,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? AppColors.primaryBlue
                            : AppColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchSpotThreshold: 24,
            touchCallback: (event, response) {
              if (onMonthTap == null) return;
              // Only a deliberate press re-runs the report.
              //
              // NOT FlTouchEvent.isInterestedForInteractions: that returns
              // true for FlPointerHoverEvent too, so on desktop merely
              // moving the mouse across the chart selected whatever month
              // was under the cursor without anyone clicking.
              //
              // Gated on the DOWN event rather than the up/end one because
              // fl_chart reports no spots once the touch has ended.
              if (event is! FlTapDownEvent && event is! FlLongPressStart) {
                return;
              }
              final spots = response?.lineBarSpots;
              if (spots == null || spots.isEmpty) return;
              final index = spots.first.spotIndex;
              if (index < 0 || index >= series.length) return;
              onMonthTap!(series[index].month);
            },
            getTouchedSpotIndicator: (barData, indexes) => [
              for (final _ in indexes)
                const TouchedSpotIndicatorData(
                  FlLine(color: AppColors.border, strokeWidth: 1),
                  FlDotData(show: false),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.textPrimary,
              tooltipRoundedRadius: AppRadius.md,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  if (spot.spotIndex >= 0 && spot.spotIndex < series.length)
                    _tooltipItem(series[spot.spotIndex], spot.y)
                  else
                    null,
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < series.length; i++)
                  FlSpot(i.toDouble(), series[i].rupees),
              ],
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: AppColors.primaryBlue,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  final isSel = index >= 0 &&
                      index < series.length &&
                      series[index].month == selected;
                  return FlDotCirclePainter(
                    radius: isSel ? 7 : 3.5,
                    color: isSel ? AppColors.primaryBlue : Colors.white,
                    strokeWidth: isSel ? 3 : 2,
                    strokeColor:
                        isSel ? Colors.white : AppColors.primaryBlue,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primaryBlue.withValues(alpha: 0.22),
                    AppColors.primaryBlue.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
