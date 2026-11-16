// lib/shared/charts/grow_donut_chart.dart
//
// Ring chart with 2px gaps between slices. The touched slice grows a little
// and the centre swaps to its name, value and share (the donut's tooltip);
// a tap pins a slice. A legend (dot, label, value, share) sits beside or
// below the ring.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'chart_empty.dart';
import 'chart_models.dart';
import 'chart_theme.dart';

class GrowDonutChart extends StatefulWidget {
  const GrowDonutChart({
    super.key,
    required this.slices,
    this.centerLabel = 'Total',
    this.centerValue,
    this.size = 190,
    this.valueFormatter,
    this.stacked,
    this.selectedIndex,
    this.onSelected,
    this.emptyMessage = 'No data',
  });

  final List<ChartSlice> slices;

  /// Shown in the centre while no slice is touched or pinned.
  final String centerLabel;

  /// Defaults to the formatted total.
  final String? centerValue;

  /// Diameter of the ring.
  final double size;

  /// Legend and centre value. Defaults to compact rupees.
  final String Function(double value)? valueFormatter;

  /// Legend below the ring (true) or beside it (false). Null measures the
  /// available width; pass a value when this sits under an IntrinsicHeight,
  /// which cannot measure through a LayoutBuilder.
  final bool? stacked;

  /// Controlled pin. Leave null to let the chart keep its own.
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;

  final String emptyMessage;

  @override
  State<GrowDonutChart> createState() => _GrowDonutChartState();
}

class _GrowDonutChartState extends State<GrowDonutChart> {
  int? _touched;
  int? _pinned;

  /// Slices that actually have a share, with their original index.
  List<(int, ChartSlice)> get _visible => [
    for (var i = 0; i < widget.slices.length; i++)
      if (widget.slices[i].value > 0) (i, widget.slices[i]),
  ];

  Color _colour(int i) =>
      widget.slices[i].color ?? ChartTheme.paletteAt(i);

  String _format(double v) =>
      (widget.valueFormatter ?? ChartTheme.compact)(v);

  void _touch(int? i) {
    if (i == _touched) return;
    setState(() => _touched = i);
  }

  void _pin(int i) {
    setState(() => _pinned = i);
    widget.onSelected?.call(i);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final total = visible.fold<double>(0, (s, e) => s + e.$2.value);
    if (visible.isEmpty || total <= 0) {
      return ChartEmpty(height: widget.size, message: widget.emptyMessage);
    }

    final shown = _touched ?? widget.selectedIndex ?? _pinned;
    final ring = _ring(visible, total, shown);
    final legend = _legend(visible, total, shown);

    final stacked = widget.stacked;
    if (stacked != null) return _compose(ring, legend, stacked);
    return LayoutBuilder(
      builder: (context, c) => _compose(ring, legend, c.maxWidth < 420),
    );
  }

  Widget _compose(Widget ring, Widget legend, bool stacked) {
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: ring),
          const SizedBox(height: AppSpacing.lg),
          legend,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Center(child: ring)),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: legend),
      ],
    );
  }

  Widget _ring(List<(int, ChartSlice)> visible, double total, int? shown) {
    final size = widget.size;
    final centreR = size / 2 - 38;
    final shownSlice = shown != null && shown < widget.slices.length
        ? widget.slices[shown]
        : null;

    final String label;
    final String value;
    final String? sub;
    if (shownSlice != null && shownSlice.value > 0) {
      label = shownSlice.label;
      value = _format(shownSlice.value);
      sub = ChartTheme.percent(shownSlice.value / total);
    } else {
      label = widget.centerLabel;
      value = widget.centerValue ?? _format(total);
      sub = null;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: centreR,
              startDegreeOffset: -90,
              borderData: FlBorderData(show: false),
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final section = response?.touchedSection;
                  final index = section?.touchedSectionIndex ?? -1;
                  final valid =
                      event.isInterestedForInteractions &&
                      index >= 0 &&
                      index < visible.length;
                  _touch(valid ? visible[index].$1 : null);
                  if (event is FlTapUpEvent &&
                      index >= 0 &&
                      index < visible.length) {
                    _pin(visible[index].$1);
                  }
                },
              ),
              sections: [
                for (final (i, s) in visible)
                  PieChartSectionData(
                    value: s.value,
                    color: _colour(i),
                    radius: i == shown ? 32 : 26,
                    showTitle: false,
                  ),
              ],
            ),
            duration: ChartTheme.animation,
            curve: ChartTheme.curve,
          ),
          IgnorePointer(
            child: SizedBox(
              width: centreR * 2 - 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: ChartTheme.tooltipLabel,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: ChartTheme.number(20)),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub, style: ChartTheme.tooltipDetail),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(List<(int, ChartSlice)> visible, double total, int? shown) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in visible)
          MouseRegion(
            onEnter: (_) => _touch(i),
            onExit: (_) => _touch(null),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _pin(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _colour(i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ChartTheme.rowLabel.copyWith(
                          fontSize: 13,
                          fontWeight: i == shown
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _format(s.value),
                      style: ChartTheme.number(13),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        ChartTheme.percent(s.value / total),
                        textAlign: TextAlign.right,
                        style: ChartTheme.number(
                          12,
                          weight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
