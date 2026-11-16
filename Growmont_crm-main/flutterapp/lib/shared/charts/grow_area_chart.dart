// lib/shared/charts/grow_area_chart.dart
//
// Smooth area chart in the Recharts style: monotone curve, 2px stroke,
// vertical gradient fill, dashed horizontal grid, a dashed cursor with a
// highlighted dot and a white tooltip card on hover / touch.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chart_empty.dart';
import 'chart_frame.dart';
import 'chart_models.dart';
import 'chart_theme.dart';

class GrowAreaChart extends StatelessWidget {
  const GrowAreaChart({
    super.key,
    required this.points,
    this.height = 220,
    this.valueFormatter,
    this.labelFormatter,
    this.color,
    this.showYAxis = true,
    this.onPointTap,
    this.emptyMessage = 'No data',
  });

  final List<ChartPoint> points;
  final double height;

  /// Tooltip value. Defaults to full rupees.
  final String Function(double value)? valueFormatter;

  /// X-axis and tooltip heading. Defaults to the point's label, else "5 Oct".
  final String Function(ChartPoint point)? labelFormatter;

  final Color? color;
  final bool showYAxis;

  /// A deliberate press (not hover) on the point at this index.
  final ValueChanged<int>? onPointTap;

  final String emptyMessage;

  static String _defaultLabel(ChartPoint p) =>
      p.label ?? (p.x == null ? '' : DateFormat('d MMM').format(p.x!));

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return ChartEmpty(height: height, message: emptyMessage);
    }

    final c = color ?? ChartTheme.accent;
    final format = valueFormatter ?? ChartTheme.fullRupees;
    final labelOf = labelFormatter ?? _defaultLabel;
    final labels = [for (final p in points) labelOf(p)];
    final n = points.length;
    final peak = points.fold<double>(0, (m, p) => p.y > m ? p.y : m);
    final scale = niceScale(peak);

    return ChartFrame(
      height: height,
      count: n,
      scale: scale,
      xLabels: labels,
      slots: false,
      showYAxis: showYAxis,
      cursor: true,
      dotColor: c,
      onTap: onPointTap,
      anchorValue: (i) => points[i].y,
      tooltipBuilder: (i) => ChartTooltipCard(
        label: labels[i],
        value: format(points[i].y),
        detail: points[i].detail,
      ),
      plotBuilder: (context, plot, active) => LineChart(
        LineChartData(
          minX: n == 1 ? -0.5 : 0,
          maxX: n == 1 ? 0.5 : (n - 1).toDouble(),
          minY: 0,
          maxY: scale.max,
          gridData: chartGrid(scale.step),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < n; i++) FlSpot(i.toDouble(), points[i].y),
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              curveSmoothness: 0.3,
              color: c,
              barWidth: 2,
              isStrokeCapRound: true,
              isStrokeJoinRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.withValues(alpha: 0.25), c.withValues(alpha: 0)],
                ),
              ),
            ),
          ],
        ),
        duration: ChartTheme.animation,
        curve: ChartTheme.curve,
      ),
    );
  }
}
