// lib/shared/charts/chart_frame.dart
//
// The shared scaffold under the area and bar charts. fl_chart draws the
// plot (grid, curve / bars); everything around it is laid out here from one
// known plot rectangle, so labels, the cursor, the highlighted dot and the
// tooltip all line up with the data exactly and never overlap:
//
//   * y labels in a left gutter sized to the widest tick;
//   * x labels thinned to a stride that always fits, anchored to the newest
//     point and clamped inside the card;
//   * hover (mouse), tap and horizontal drag (touch) pick the nearest index;
//   * a white rounded tooltip sits above the point, flipping below it when
//     there is no room, and is clamped inside the chart horizontally.

import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart' show FlGridData, FlLine;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// Rounded axis maximum and step, so ticks land on 1/2/5 x 10^n.
class NiceScale {
  const NiceScale(this.max, this.step);

  final double max;
  final double step;

  List<double> get ticks => [
    for (var v = 0.0; v <= max + step * 0.001; v += step) v,
  ];
}

/// A rounded scale for [dataMax] with about [target] intervals and some
/// head-room so the peak never touches the top edge.
NiceScale niceScale(double dataMax, {int target = 4}) {
  if (!dataMax.isFinite || dataMax <= 0) return const NiceScale(100, 25);
  final raw = dataMax / target;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final nice = norm <= 1
      ? 1
      : norm <= 2
      ? 2
      : norm <= 5
      ? 5
      : 10;
  final step = nice * mag;
  var max = step * (dataMax / step).ceil();
  if (dataMax > max * 0.94) max += step;
  return NiceScale(max, step);
}

/// The white tooltip card: muted heading, bold value, optional detail line.
class ChartTooltipCard extends StatelessWidget {
  const ChartTooltipCard({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.dotColor,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: ChartTheme.tooltipShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dotColor != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChartTheme.tooltipLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ChartTheme.tooltipValue,
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ChartTheme.tooltipDetail,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

typedef ChartPlotBuilder =
    Widget Function(BuildContext context, Size plot, int? active);

/// Lays out the axes and touch handling around the plot [plotBuilder] draws.
class ChartFrame extends StatefulWidget {
  const ChartFrame({
    super.key,
    required this.height,
    required this.count,
    required this.scale,
    required this.xLabels,
    required this.slots,
    required this.plotBuilder,
    required this.anchorValue,
    required this.tooltipBuilder,
    this.showYAxis = true,
    this.showXAxis = true,
    this.cursor = false,
    this.dotColor = ChartTheme.accent,
    this.onTap,
    this.topPadding = 12,
    this.restingValueText,
    this.restingIndex,
    this.activeOverlay,
  });

  final double height;
  final int count;
  final NiceScale scale;

  /// One label per index; the frame thins them to fit.
  final List<String> xLabels;

  /// True for bars (an index owns an equal slot, labels sit at its centre);
  /// false for a line (first and last index sit on the plot edges).
  final bool slots;

  final ChartPlotBuilder plotBuilder;

  /// The data value at index i; the tooltip and dot anchor to it.
  final double Function(int i) anchorValue;
  final Widget Function(int i) tooltipBuilder;

  final bool showYAxis;
  final bool showXAxis;

  /// Dashed vertical cursor and a highlighted dot at the active index.
  final bool cursor;
  final Color dotColor;

  /// A press-and-release on index i (not hover).
  final ValueChanged<int>? onTap;

  final double topPadding;

  /// A value label drawn above [restingIndex] while nothing is touched.
  final String? restingValueText;
  final int? restingIndex;

  /// Drawn over the plot for the active index, e.g. the darkened bar. Gets
  /// the plot rect and the anchor point of the data value.
  final Widget Function(int i, Rect plot, Offset anchor)? activeOverlay;

  @override
  State<ChartFrame> createState() => _ChartFrameState();
}

class _ChartFrameState extends State<ChartFrame> {
  static const double _xStrip = 24;
  static const double _yGap = 8;

  int? _active;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _set(int? i, {bool touch = false}) {
    _hideTimer?.cancel();
    if (touch && i != null) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _active = null);
      });
    }
    if (i == _active) return;
    setState(() => _active = i);
  }

  static double _textWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    if (n == 0) return SizedBox(height: widget.height);

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 300.0;
          final h = widget.height;
          final ticks = widget.scale.ticks;

          var gutter = 0.0;
          if (widget.showYAxis) {
            for (final t in ticks) {
              gutter = math.max(
                gutter,
                _textWidth(ChartTheme.axisMoney(t), ChartTheme.axis),
              );
            }
            gutter += _yGap + 4;
          }
          final insetL = widget.slots ? 0.0 : 6.0;
          final insetR = widget.slots ? 0.0 : 8.0;
          final bottom = widget.showXAxis ? _xStrip : 0.0;
          final plot = Rect.fromLTRB(
            gutter + insetL,
            widget.topPadding,
            math.max(gutter + insetL + 40, w - insetR),
            math.max(widget.topPadding + 40, h - bottom),
          );

          double xAt(int i) {
            if (widget.slots) return plot.left + (i + 0.5) * plot.width / n;
            if (n == 1) return plot.left + plot.width / 2;
            return plot.left + i / (n - 1) * plot.width;
          }

          double yAt(double v) =>
              plot.bottom - (v / widget.scale.max).clamp(0.0, 1.0) * plot.height;

          int indexAt(double dx) {
            if (widget.slots) {
              return ((dx - plot.left) / (plot.width / n)).floor().clamp(
                0,
                n - 1,
              );
            }
            if (n == 1) return 0;
            return ((dx - plot.left) / plot.width * (n - 1)).round().clamp(
              0,
              n - 1,
            );
          }

          final active = _active != null && _active! < n ? _active : null;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Y labels.
              if (widget.showYAxis)
                for (final t in ticks)
                  Positioned(
                    left: 0,
                    width: gutter - _yGap,
                    top: yAt(t) - 7,
                    height: 14,
                    child: Text(
                      ChartTheme.axisMoney(t),
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.right,
                      style: ChartTheme.axis,
                    ),
                  ),
              // The plot.
              Positioned.fromRect(
                rect: plot,
                child: widget.plotBuilder(context, plot.size, active),
              ),
              if (active != null && widget.activeOverlay != null)
                widget.activeOverlay!(
                  active,
                  plot,
                  Offset(xAt(active), yAt(widget.anchorValue(active))),
                ),
              // X labels.
              if (widget.showXAxis) ..._xLabels(plot, w, xAt),
              // Cursor and dot.
              if (widget.cursor && active != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CursorPainter(
                        x: xAt(active),
                        top: plot.top,
                        bottom: plot.bottom,
                        dotY: yAt(widget.anchorValue(active)),
                        color: widget.dotColor,
                      ),
                    ),
                  ),
                ),
              // Resting value label (selected bar).
              if (active == null &&
                  widget.restingValueText != null &&
                  widget.restingIndex != null &&
                  widget.restingIndex! < n)
                Positioned(
                  left: xAt(widget.restingIndex!) - 40,
                  width: 80,
                  top:
                      yAt(widget.anchorValue(widget.restingIndex!)) - 20,
                  height: 16,
                  child: Center(
                    child: Text(
                      widget.restingValueText!,
                      maxLines: 1,
                      softWrap: false,
                      style: ChartTheme.number(
                        12,
                        color: ChartTheme.accentDark,
                      ),
                    ),
                  ),
                ),
              // Touch handling.
              Positioned.fill(
                child: MouseRegion(
                  onHover: (e) => _set(indexAt(e.localPosition.dx)),
                  onExit: (_) => _set(null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _set(
                      indexAt(d.localPosition.dx),
                      touch: d.kind != PointerDeviceKind.mouse,
                    ),
                    onTapUp: (d) =>
                        widget.onTap?.call(indexAt(d.localPosition.dx)),
                    onHorizontalDragStart: (d) =>
                        _set(indexAt(d.localPosition.dx), touch: true),
                    onHorizontalDragUpdate: (d) =>
                        _set(indexAt(d.localPosition.dx), touch: true),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              // Tooltip.
              if (active != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomSingleChildLayout(
                      delegate: _TooltipLayout(
                        Offset(xAt(active), yAt(widget.anchorValue(active))),
                      ),
                      child: widget.tooltipBuilder(active),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _xLabels(Rect plot, double w, double Function(int) xAt) {
    final n = widget.count;
    if (widget.xLabels.length != n) return const [];
    var longest = widget.xLabels.first;
    for (final l in widget.xLabels) {
      if (l.length > longest.length) longest = l;
    }
    final labelW = _textWidth(longest, ChartTheme.axis);
    final slotW = widget.slots
        ? plot.width / n
        : (n > 1 ? plot.width / (n - 1) : plot.width);
    // A line's end labels are clamped inward, so they need more room.
    final need = widget.slots ? labelW + 10 : labelW * 1.3 + 14;
    final stride = math.max(1, (need / slotW).ceil());

    final out = <Widget>[];
    for (var i = n - 1; i >= 0; i -= stride) {
      final text = widget.xLabels[i];
      if (text.isEmpty) continue;
      final tw = _textWidth(text, ChartTheme.axis);
      final left = (xAt(i) - tw / 2)
          .clamp(0.0, math.max(0.0, w - tw))
          .toDouble();
      out.add(
        Positioned(
          left: left,
          top: plot.bottom + 8,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: ChartTheme.axis,
          ),
        ),
      );
    }
    return out;
  }
}

class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout(this.anchor);

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.max(0, constraints.maxWidth - 8));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final dx = (anchor.dx - childSize.width / 2)
        .clamp(0.0, math.max(0.0, size.width - childSize.width))
        .toDouble();
    var dy = anchor.dy - childSize.height - 14;
    if (dy < 0) {
      dy = anchor.dy + 16;
      if (dy + childSize.height > size.height) {
        dy = math.max(0.0, size.height - childSize.height);
      }
    }
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_TooltipLayout old) => old.anchor != anchor;
}

class _CursorPainter extends CustomPainter {
  const _CursorPainter({
    required this.x,
    required this.top,
    required this.bottom,
    required this.dotY,
    required this.color,
  });

  final double x;
  final double top;
  final double bottom;
  final double dotY;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ChartTheme.cursor
      ..strokeWidth = 1;
    final dash = ChartTheme.dash;
    var y = top;
    while (y < bottom) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash[0], bottom).toDouble()),
        line,
      );
      y += (dash[0] + dash[1]).toDouble();
    }
    final centre = Offset(x, dotY);
    canvas.drawCircle(centre, 9, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawCircle(centre, 5, Paint()..color = Colors.white);
    canvas.drawCircle(
      centre,
      5,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_CursorPainter old) =>
      old.x != x ||
      old.top != top ||
      old.bottom != bottom ||
      old.dotY != dotY ||
      old.color != color;
}

/// Dashed 1px horizontal grid, no vertical lines, shared by the plots.
FlGridData chartGrid(double step) => FlGridData(
  show: true,
  drawVerticalLine: false,
  horizontalInterval: step,
  getDrawingHorizontalLine: (_) => const FlLine(
    color: ChartTheme.grid,
    strokeWidth: 1,
    dashArray: ChartTheme.dash,
  ),
);
