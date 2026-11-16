// lib/features/reports/phone/kpi_grid.dart
//
// Two-column grid of small figure tiles: label, value, optional change.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'phone_style.dart';

class KpiData {
  const KpiData(
    this.label,
    this.value, {
    this.deltaText,
    this.deltaColor = AppColors.textMuted,
    this.valueColor = AppColors.textPrimary,
  });

  final String label;
  final String value;
  final String? deltaText;
  final Color deltaColor;
  final Color valueColor;
}

class KpiGrid extends StatelessWidget {
  const KpiGrid({
    super.key,
    required this.tiles,
    this.columns = 2,
    this.fill = false,
  });

  final List<KpiData> tiles;

  /// Tiles per row: 2 on a phone and beside the hero, 4 in a wide row.
  final int columns;

  /// Share the parent's (bounded) height equally between the rows and centre
  /// each tile's text, so the grid lines up with a card beside it.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += columns) {
      if (i > 0) rows.add(const SizedBox(height: gap));
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: gap));
        cells.add(
          Expanded(
            child: i + c < tiles.length
                ? _Tile(tiles[i + c], centered: fill)
                : const SizedBox(),
          ),
        );
      }
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cells,
      );
      rows.add(fill ? Expanded(child: row) : IntrinsicHeight(child: row));
    }
    return Column(children: rows);
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.data, {this.centered = false});

  final KpiData data;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PhoneText.muted,
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            data.value,
            maxLines: 1,
            style: PhoneText.number(22, color: data.valueColor),
          ),
        ),
        if (data.deltaText != null) ...[
          const SizedBox(height: 4),
          Text(
            data.deltaText!,
            maxLines: 1,
            style: PhoneText.number(
              12,
              weight: FontWeight.w600,
              color: data.deltaColor,
            ),
          ),
        ],
      ],
    );
    return PhoneCard(
      child: centered
          ? Align(alignment: Alignment.centerLeft, child: content)
          : content,
    );
  }
}
