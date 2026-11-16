// lib/shared/charts/chart_empty.dart

import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// Muted centred message at a chart's height, so a card does not collapse
/// when there is nothing to draw.
class ChartEmpty extends StatelessWidget {
  const ChartEmpty({super.key, this.height = 160, this.message = 'No data'});

  final double height;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: ChartTheme.axis.copyWith(fontSize: 13),
        ),
      ),
    );
  }
}
