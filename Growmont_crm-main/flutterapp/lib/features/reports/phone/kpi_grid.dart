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
                ? _Tile(
                    tiles[i + c],
                    size: fill
                        ? _TileSize.large
                        : (columns >= 4 ? _TileSize.medium : _TileSize.small),
                  )
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

enum _TileSize { small, medium, large }

class _Tile extends StatelessWidget {
  const _Tile(this.data, {this.size = _TileSize.small});

  final KpiData data;
  final _TileSize size;

  @override
  Widget build(BuildContext context) {
    // Phone tiles stay compact; on PC the tiles beside the revenue card are
    // as tall as that card, so the type scales up to fill them.
    final (labelSize, valueSize, deltaSize) = switch (size) {
      _TileSize.small => (13.0, 22.0, 12.0),
      _TileSize.medium => (15.0, 30.0, 13.0),
      _TileSize.large => (16.0, 40.0, 14.0),
    };
    final label = Text(
      data.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PhoneText.muted.copyWith(fontSize: labelSize),
    );
    final value = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        data.value,
        maxLines: 1,
        style: PhoneText.number(valueSize, color: data.valueColor),
      ),
    );
    final delta = data.deltaText == null
        ? null
        : Text(
            data.deltaText!,
            maxLines: 1,
            style: PhoneText.number(
              deltaSize,
              weight: FontWeight.w600,
              color: data.deltaColor,
            ),
          );

    if (size == _TileSize.large) {
      // Label on top, figure anchored to the bottom: no floating block of
      // small text in the middle of a tall card.
      return PhoneCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const Spacer(),
            value,
            if (delta != null) ...[const SizedBox(height: 4), delta],
          ],
        ),
      );
    }
    return PhoneCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          SizedBox(height: size == _TileSize.small ? 6 : 8),
          value,
          if (delta != null) ...[const SizedBox(height: 4), delta],
        ],
      ),
    );
  }
}
