// lib/shared/charts/grow_ranked_bars.dart
//
// One row per item: label (and optional sub-line) on the left, value and
// share on the right, and a rounded 8px track under it whose fill animates
// in. Bars share one baseline, so lengths compare directly.

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'chart_empty.dart';
import 'chart_models.dart';
import 'chart_theme.dart';

class GrowRankedBars extends StatelessWidget {
  const GrowRankedBars({
    super.key,
    required this.items,
    this.rowGap = 14,
    this.animate = true,
    this.emptyMessage = 'No data',
  });

  final List<RankedItem> items;
  final double rowGap;
  final bool animate;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return ChartEmpty(height: 80, message: emptyMessage);

    final peak = items.fold<double>(0, (m, e) => e.value > m ? e.value : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: rowGap),
          _RankedRow(
            item: items[i],
            fraction: peak <= 0 ? 0 : items[i].value / peak,
            animate: animate,
          ),
        ],
      ],
    );
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.item,
    required this.fraction,
    required this.animate,
  });

  final RankedItem item;
  final double fraction;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ChartTheme.rowLabel,
                  ),
                  if (item.subText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChartTheme.rowSub,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(item.valueText, style: ChartTheme.number(14)),
            if (item.shareText != null)
              SizedBox(
                width: 44,
                child: Text(
                  item.shareText!,
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
        const SizedBox(height: 8),
        GrowTrack(
          fraction: fraction,
          color: item.color ?? ChartTheme.accent,
          animate: animate,
        ),
      ],
    );
  }
}

/// The rounded track with an animated fill, optionally with a marker line
/// (e.g. a team average) at [marker] (0..1) across it.
class GrowTrack extends StatelessWidget {
  const GrowTrack({
    super.key,
    required this.fraction,
    this.color = ChartTheme.accent,
    this.height = 8,
    this.animate = true,
    this.marker,
  });

  final double fraction;
  final Color color;
  final double height;
  final bool animate;
  final double? marker;

  Widget _fill(double f) => FractionallySizedBox(
    widthFactor: f,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: SizedBox(height: height),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    final track = DecoratedBox(
      decoration: BoxDecoration(
        color: ChartTheme.track,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: animate
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: f),
                  duration: ChartTheme.animation,
                  curve: ChartTheme.curve,
                  builder: (context, v, _) => _fill(v),
                )
              : _fill(f),
        ),
      ),
    );
    if (marker == null) return track;

    return SizedBox(
      height: height + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          track,
          Align(
            alignment: Alignment((marker!.clamp(0.0, 1.0)) * 2 - 1, 0),
            child: Container(
              width: 2,
              height: height + 8,
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
