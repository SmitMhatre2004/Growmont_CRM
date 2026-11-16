// lib/shared/charts/grow_segment_bar.dart
//
// A rounded proportion bar split into segments (2px gaps), plus a legend.
// Hovering or pressing a segment dims the others and opens a white tooltip
// card with its name, value and share.

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'chart_models.dart';
import 'chart_theme.dart';

class GrowSegmentBar extends StatefulWidget {
  const GrowSegmentBar({
    super.key,
    required this.segments,
    this.height = 10,
    this.animate = true,
  });

  final List<ChartSegment> segments;
  final double height;
  final bool animate;

  @override
  State<GrowSegmentBar> createState() => _GrowSegmentBarState();
}

class _GrowSegmentBarState extends State<GrowSegmentBar> {
  int? _hover;

  void _set(int? i) {
    if (i == _hover) return;
    setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final present = [
      for (final s in widget.segments)
        if (s.value > 0) s,
    ];
    if (present.isEmpty) return SizedBox(height: widget.height);
    final total = present.fold<double>(0, (s, e) => s + e.value);

    Widget bar() => ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: SizedBox(
        height: widget.height,
        child: Row(
          children: [
            for (var i = 0; i < present.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (present[i].value / total * 1000).round().clamp(1, 1000),
                child: _Segment(
                  segment: present[i],
                  share: present[i].value / total,
                  dimmed: _hover != null && _hover != i,
                  onActive: (on) => _set(on ? i : null),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!widget.animate) return bar();

    // Wipes in from the left so the proportions are never briefly wrong.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.01, end: 1),
      duration: ChartTheme.animation,
      curve: ChartTheme.curve,
      builder: (context, t, child) =>
          Align(alignment: Alignment.centerLeft, widthFactor: t, child: child),
      child: bar(),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.share,
    required this.dimmed,
    required this.onActive,
  });

  final ChartSegment segment;
  final double share;
  final bool dimmed;
  final ValueChanged<bool> onActive;

  @override
  Widget build(BuildContext context) {
    final value = segment.valueText;
    return Tooltip(
      richMessage: TextSpan(
        children: [
          TextSpan(text: segment.label, style: ChartTheme.tooltipLabel),
          TextSpan(
            text: '\n${value == null ? '' : '$value  '}${ChartTheme.percent(share)}',
            style: ChartTheme.tooltipValue,
          ),
        ],
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: ChartTheme.tooltipShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.all(8),
      preferBelow: false,
      verticalOffset: 14,
      triggerMode: TooltipTriggerMode.tap,
      waitDuration: Duration.zero,
      showDuration: const Duration(seconds: 2),
      child: MouseRegion(
        onEnter: (_) => onActive(true),
        onExit: (_) => onActive(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: dimmed ? segment.color.withValues(alpha: 0.4) : segment.color,
        ),
      ),
    );
  }
}

/// One row per segment: dot, label, value, share.
class GrowSegmentLegend extends StatelessWidget {
  const GrowSegmentLegend({super.key, required this.segments, this.rowGap = 10});

  final List<ChartSegment> segments;
  final double rowGap;

  @override
  Widget build(BuildContext context) {
    final present = [
      for (final s in segments)
        if (s.value > 0) s,
    ];
    final total = present.fold<double>(0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < present.length; i++) ...[
          if (i > 0) SizedBox(height: rowGap),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: present[i].color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  present[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ChartTheme.rowLabel,
                ),
              ),
              const SizedBox(width: 8),
              if (present[i].valueText != null)
                Text(present[i].valueText!, style: ChartTheme.number(14)),
              SizedBox(
                width: 44,
                child: Text(
                  ChartTheme.percent(present[i].value / total),
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
        ],
      ],
    );
  }
}
