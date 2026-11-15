// lib/features/reports/widgets/report_trend_chart.dart
//
// Booked revenue per day, over a period the reader picks.
//
// Form: a line, because the question is shape-over-time. One series, so
// no legend is strictly required — but a single key is kept under the
// plot because the card sits beside others and the key names what the
// area wash is.
//
// Days with no sales are plotted as zeros rather than skipped. Skipping
// them would space the x-axis by "days that happened to have a sale",
// which quietly compresses quiet stretches and makes a dead month look
// as wide as a busy week.
//
// A caveat worth knowing: at daily granularity a business that books a
// handful of sales a week draws a comb of spikes rather than a trend.
// That is the data being honest, not the chart misbehaving — the period
// selector is there so a reader who wants the shape rather than the
// detail can widen the window.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/monthly_revenue_chart.dart' show compactRupees;
import 'report_chart_theme.dart';

/// Windows the selector offers, longest label first so the control does
/// not resize as the choice changes.
enum TrendPeriod {
  oneMonth(30, 'Last 30 days'),
  threeMonths(90, 'Last 3 months'),
  sixMonths(182, 'Last 6 months'),
  twelveMonths(365, 'Last 12 months');

  const TrendPeriod(this.days, this.label);

  final int days;
  final String label;
}

class ReportTrendChart extends StatefulWidget {
  const ReportTrendChart({
    super.key,
    required this.series,
    this.initialPeriod = TrendPeriod.threeMonths,
    this.height = 240,
    this.onDayTap,
  });

  /// One entry per day, oldest first, ending on the reported month's last
  /// day. The chart slices the tail of this, so changing the period costs
  /// no recomputation.
  final List<DayTotal> series;

  final TrendPeriod initialPeriod;
  final double height;

  /// Optional: a deliberate press on the plot reports the day under it.
  final ValueChanged<DateTime>? onDayTap;

  @override
  State<ReportTrendChart> createState() => _ReportTrendChartState();
}

class _ReportTrendChartState extends State<ReportTrendChart> {
  late TrendPeriod _period = widget.initialPeriod;

  List<DayTotal> get _window {
    if (widget.series.length <= _period.days) return widget.series;
    return widget.series.sublist(widget.series.length - _period.days);
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final peakPaise = window.fold<int>(
      0,
      (best, d) => d.paise > best ? d.paise : best,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _PeriodSelector(
            value: _period,
            onChanged: (period) => setState(() => _period = period),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (peakPaise <= 0)
          SizedBox(
            height: widget.height,
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
                    'No revenue booked in the ${_period.label.toLowerCase()}',
                    style: AppTypography.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else ...[
          SizedBox(
            height: widget.height,
            child: _plot(context, window, peakPaise / 100),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Center(
            child: ChartLegend(
              entries: [(label: 'Revenue', color: ReportChart.accent)],
            ),
          ),
        ],
      ],
    );
  }

  Widget _plot(BuildContext context, List<DayTotal> window, double peak) {
    // Roughly six date labels, whatever the window and the width.
    final targetLabels = MediaQuery.sizeOf(context).width < 640 ? 4 : 6;
    final stride = (window.length / targetLabels).ceil().clamp(1, 999);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: peak * 1.2,
        minX: 0,
        maxX: (window.length - 1).toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          // Solid hairlines. A dashed grid reads as "projection" or
          // "threshold" when it is only a grid.
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: ReportChart.grid, strokeWidth: 1),
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
              reservedSize: 52,
              getTitlesWidget: (value, meta) {
                if (value <= 0 || value >= meta.max) {
                  return const SizedBox.shrink();
                }
                return Text(
                  compactRupees(value),
                  style: ReportChart.axisLabel,
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= window.length) {
                  return const SizedBox.shrink();
                }
                // Anchored to the newest day so the right edge is always
                // labelled; without that the last tick drifts with the
                // window length.
                if ((window.length - 1 - i) % stride != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    DateFormat('d MMM').format(window[i].day),
                    style: ReportChart.axisLabel,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          // Nearest-point rather than fl_chart's 10px band: on a window
          // of ninety points the live strip would otherwise be narrower
          // than a fingertip.
          touchSpotThreshold: 10000,
          touchCallback: (event, response) {
            if (widget.onDayTap == null) return;
            // Only a deliberate press. isInterestedForInteractions is
            // true for FlPointerHoverEvent, so gating on it would fire
            // this as the mouse crossed the plot.
            if (event is! FlTapDownEvent && event is! FlLongPressStart) {
              return;
            }
            final spots = response?.lineBarSpots;
            if (spots == null || spots.isEmpty) return;
            final index = spots.first.x.round();
            if (index < 0 || index >= window.length) return;
            widget.onDayTap!(window[index].day);
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            tooltipRoundedRadius: AppRadius.md,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            getTooltipItems: (touched) {
              return touched.map((spot) {
                final item = window[spot.x.round()];
                return LineTooltipItem(
                  '${DateFormat('d MMM yyyy').format(item.day)}\n',
                  const TextStyle(
                    color: AppColors.borderStrong,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    height: 14 / 11,
                  ),
                  children: [
                    TextSpan(
                      text: AppFormatters.formatAmount(
                        item.rupees.toStringAsFixed(2),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (item.count > 0)
                      TextSpan(
                        text:
                            '\n${item.count} ${item.count == 1 ? 'sale' : 'sales'}',
                        style: const TextStyle(
                          color: AppColors.borderStrong,
                          fontWeight: FontWeight.w500,
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
            spots: [
              for (var i = 0; i < window.length; i++)
                FlSpot(i.toDouble(), window[i].rupees),
            ],
            isCurved: false,
            color: ReportChart.accent,
            barWidth: ReportChart.lineWidth,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            // No dot per day: at ninety points a marker on every one is
            // the "number on every data point" failure drawn as ink.
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: ReportChart.wash(ReportChart.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// The period control. A plain menu button rather than a row of chips:
/// four options is too many for chips in a card header, and the current
/// choice has to stay readable at a glance.
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});

  final TrendPeriod value;
  final ValueChanged<TrendPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TrendPeriod>(
      initialValue: value,
      tooltip: 'Change the period',
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      itemBuilder: (context) => [
        for (final period in TrendPeriod.values)
          PopupMenuItem(
            value: period,
            child: Text(
              period.label,
              style: AppTypography.bodyPrimary.copyWith(
                fontWeight:
                    period == value ? FontWeight.w700 : FontWeight.w500,
                color: period == value
                    ? AppColors.primaryBlue
                    : AppColors.textPrimary,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value.label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.keyboard_arrow_down,
              size: AppSizing.iconMd,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
