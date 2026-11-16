// lib/shared/charts/chart_models.dart
//
// Plain data the chart widgets take in.

import 'package:flutter/material.dart';

/// One point of a line / area series. Give either a [x] date or a [label].
class ChartPoint {
  const ChartPoint({
    this.x,
    this.label,
    required this.y,
    this.detail,
    this.count = 0,
  });

  final DateTime? x;
  final String? label;
  final double y;

  /// How many records were summed into [y] (set by bucketDaily).
  final int count;

  /// Optional extra tooltip line, e.g. "3 sales".
  final String? detail;
}

class ChartBar {
  const ChartBar({
    required this.label,
    required this.value,
    this.highlight = false,
    this.tooltipLabel,
    this.detail,
  });

  /// X-axis label.
  final String label;
  final double value;

  /// Draws this bar in the full colour while the others are muted.
  final bool highlight;

  /// Tooltip heading when it should differ from [label].
  final String? tooltipLabel;

  /// Optional extra tooltip line, e.g. "4 follow-ups".
  final String? detail;
}

class ChartSlice {
  const ChartSlice({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;
}

class RankedItem {
  const RankedItem({
    required this.label,
    required this.value,
    required this.valueText,
    this.subText,
    this.shareText,
    this.color,
  });

  final String label;

  /// Magnitude the track is sized by (relative to the largest item).
  final double value;
  final String valueText;
  final String? subText;

  /// Muted figure after the value, usually the share ("42%").
  final String? shareText;
  final Color? color;
}

class ChartSegment {
  const ChartSegment({
    required this.label,
    required this.value,
    required this.color,
    this.valueText,
  });

  final String label;
  final double value;
  final Color color;

  /// Shown in the tooltip and legend next to the share.
  final String? valueText;
}
