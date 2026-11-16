// lib/shared/charts/grow_bar_chart.dart
//
// Rounded-top bars in the Recharts style. The touched bar darkens; with a
// selection, the other bars fall back to a muted tint. Tapping reports the
// index, and the selected bar can carry its value above it.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'chart_empty.dart';
import 'chart_frame.dart';
import 'chart_models.dart';
import 'chart_theme.dart';

class GrowBarChart extends StatelessWidget {
  const GrowBarChart({
    super.key,
    required this.bars,
    this.height = 200,
    this.valueFormatter,
    this.onTap,
    this.selectedIndex,
    this.showValueOnSelected = false,
    this.selectedValueFormatter,
    this.color,
    this.showYAxis = true,
    this.emptyMessage = 'No data',
  });

  final List<ChartBar> bars;
  final double height;

  /// Tooltip value. Defaults to full rupees.
  final String Function(double value)? valueFormatter;

  /// A deliberate press (not hover) on the bar at this index.
  final ValueChanged<int>? onTap;

  final int? selectedIndex;

  /// Writes the selected bar's value above it while nothing is touched.
  final bool showValueOnSelected;

  /// Formatter for that label. Defaults to the compact rupee form.
  final String Function(double value)? selectedValueFormatter;

  final Color? color;
  final bool showYAxis;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return ChartEmpty(height: height, message: emptyMessage);

    final base = color ?? ChartTheme.accent;
    final dark = Color.lerp(base, Colors.black, 0.28)!;
    final format = valueFormatter ?? ChartTheme.fullRupees;
    final n = bars.length;
    final peak = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    final scale = niceScale(peak);
    final hasSelection =
        selectedIndex != null || bars.any((b) => b.highlight);
    double barWidth(double plotWidth) =>
        math.min(plotWidth / n * 0.58, 32.0).clamp(3.0, 32.0);
    bool selectedAt(int i) => i == selectedIndex || bars[i].highlight;

    final restingText =
        showValueOnSelected &&
            selectedIndex != null &&
            selectedIndex! >= 0 &&
            selectedIndex! < n
        ? (selectedValueFormatter ?? ChartTheme.compact)(
            bars[selectedIndex!].value,
          )
        : null;

    return ChartFrame(
      height: height,
      count: n,
      scale: scale,
      xLabels: [for (final b in bars) b.label],
      slots: true,
      showYAxis: showYAxis,
      topPadding: restingText != null ? 26 : 12,
      onTap: onTap,
      restingIndex: selectedIndex,
      restingValueText: restingText,
      anchorValue: (i) => bars[i].value,
      tooltipBuilder: (i) => ChartTooltipCard(
        label: bars[i].tooltipLabel ?? bars[i].label,
        value: format(bars[i].value),
        detail: bars[i].detail,
      ),
      activeOverlay: (i, plot, anchor) {
        final width = barWidth(plot.width);
        return Positioned(
          left: anchor.dx - width / 2,
          top: anchor.dy,
          width: width,
          height: math.max(0.0, plot.bottom - anchor.dy),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: dark,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(math.min(6, width / 2)),
                ),
              ),
            ),
          ),
        );
      },
      plotBuilder: (context, plot, active) {
        final width = barWidth(plot.width);
        final radius = Radius.circular(math.min(6, width / 2));

        Color colourOf(int i) {
          if (hasSelection && !selectedAt(i)) {
            return base.withValues(alpha: 0.28);
          }
          return base;
        }

        return BarChart(
          BarChartData(
            minY: 0,
            maxY: scale.max,
            alignment: BarChartAlignment.spaceAround,
            gridData: chartGrid(scale.step),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            barGroups: [
              for (var i = 0; i < n; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: bars[i].value,
                      width: width,
                      color: colourOf(i),
                      borderRadius: BorderRadius.vertical(top: radius),
                    ),
                  ],
                ),
            ],
          ),
          duration: ChartTheme.animation,
          curve: ChartTheme.curve,
        );
      },
    );
  }
}
