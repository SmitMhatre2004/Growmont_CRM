// lib/features/reports/phone/wide_layout.dart
//
// Layout pieces for the Reports screens at 768 and wider: the centred
// max-width page edge, the header row (title or identity on the left, period
// bar and Export on the right), the hero + KPI block and the two-column
// section rows. All of them fall back to a single stacked column when the
// space they are given is narrow, so a 768 window with the sidebar open still
// reads cleanly.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import 'kpi_grid.dart';
import 'period_bar.dart';
import 'period_selection.dart';
import 'phone_style.dart';
import 'revenue_hero_card.dart';

const double kReportsMaxWidth = 1280;
const double kWideMinGutter = 28;

/// Width the period bar takes in the wide header.
const double kWidePeriodBarWidth = 300;

/// Content width from which the hero card and a 2x2 KPI grid sit side by side.
const double kHeroSideBySideMin = 1040;

/// Content width from which sections go two to a row.
const double kTwoColumnMin = 640;

/// Horizontal page padding for a viewport [width]: the gutter, widened so the
/// content never grows past [kReportsMaxWidth] and stays centred.
double wideSidePadding(double width) =>
    math.max(kWideMinGutter, (width - kReportsMaxWidth) / 2);

/// Outlined "Export" button; a spinner while [exporting].
class ExportButton extends StatelessWidget {
  const ExportButton({
    super.key,
    required this.onPressed,
    required this.exporting,
  });

  final VoidCallback onPressed;
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: exporting ? null : onPressed,
        icon: exporting
            ? const SizedBox(
                width: AppSizing.iconSm,
                height: AppSizing.iconSm,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_outlined, size: AppSizing.iconMd),
        label: const Text('Export'),
      ),
    );
  }
}

/// [leading] on the left; the period bar and Export on the right of the same
/// row when there is room ([inlineMin] wide), else Export beside [leading]
/// and the period bar on its own row below.
class WideHeader extends StatelessWidget {
  const WideHeader({
    super.key,
    required this.leading,
    required this.selection,
    required this.onSelectionChanged,
    required this.onExport,
    required this.exporting,
    this.inlineMin = 700,
  });

  final Widget leading;
  final ReportPeriodSelection selection;
  final ValueChanged<ReportPeriodSelection> onSelectionChanged;
  final VoidCallback onExport;
  final bool exporting;
  final double inlineMin;

  @override
  Widget build(BuildContext context) {
    final export = ExportButton(onPressed: onExport, exporting: exporting);
    final bar = PeriodBar(
      selection: selection,
      onChanged: onSelectionChanged,
      rangeAlignment: Alignment.centerRight,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= inlineMin) {
          return Row(
            children: [
              Expanded(child: leading),
              const SizedBox(width: 16),
              SizedBox(width: kWidePeriodBarWidth, child: bar),
              const SizedBox(width: 12),
              export,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: leading),
                const SizedBox(width: 12),
                export,
              ],
            ),
            const SizedBox(height: 8),
            bar,
          ],
        );
      },
    );
  }
}

/// The "Reports" page title.
class WideTitle extends StatelessWidget {
  const WideTitle({super.key});

  @override
  Widget build(BuildContext context) => const Text(
    'Reports',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: AppTypography.pageTitle,
  );
}

/// The revenue hero card with the KPI tiles: side by side (hero two thirds,
/// 2x2 tiles one third) on a wide area; otherwise the hero on top and the
/// tiles four across below (two across when very narrow).
class WideHeroKpis extends StatelessWidget {
  const WideHeroKpis({
    super.key,
    required this.revenue,
    required this.daily,
    required this.previousLabel,
    required this.tiles,
    this.showChart = true,
  });

  final MetricDelta revenue;
  final List<DayTotal> daily;
  final String previousLabel;
  final List<KpiData> tiles;
  final bool showChart;

  /// Height of the side-by-side block when the hero draws its chart: a
  /// ~200px chart under the figure.
  static const double _chartRowHeight = 340;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        RevenueHeroCard hero({
          bool expand = false,
          bool center = false,
          double chartHeight = 200,
        }) => RevenueHeroCard(
          revenue: revenue,
          daily: daily,
          previousLabel: previousLabel,
          showChart: showChart,
          chartHeight: chartHeight,
          expandChart: expand,
          centerContent: center,
        );

        if (width >= kHeroSideBySideMin) {
          final withChart = hero().hasChart;
          final row = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: withChart ? hero(expand: true) : hero(center: true),
              ),
              const SizedBox(width: 16),
              Expanded(child: KpiGrid(tiles: tiles, fill: true)),
            ],
          );
          return withChart
              ? SizedBox(height: _chartRowHeight, child: row)
              : IntrinsicHeight(child: row);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero(),
            const SizedBox(height: 16),
            KpiGrid(tiles: tiles, columns: width >= 560 ? 4 : 2),
          ],
        );
      },
    );
  }
}

/// [left] and [right] on one row with the given flex, or stacked when the
/// width is under [kTwoColumnMin]. A null [right] gives [left] the full row.
class SplitRow extends StatelessWidget {
  const SplitRow({
    super.key,
    required this.left,
    this.right,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });

  final Widget left;
  final Widget? right;
  final int leftFlex;
  final int rightFlex;

  @override
  Widget build(BuildContext context) {
    final r = right;
    if (r == null) return left;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kTwoColumnMin) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced([left, r]),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            const SizedBox(width: 16),
            Expanded(flex: rightFlex, child: r),
          ],
        );
      },
    );
  }
}

/// Pairs [sections] two to a row in order (a lone last one takes the full
/// row), 24px between rows.
List<Widget> pairedRows(List<Widget> sections) {
  final rows = <Widget>[];
  for (var i = 0; i < sections.length; i += 2) {
    rows.add(
      SplitRow(
        left: sections[i],
        right: i + 1 < sections.length ? sections[i + 1] : null,
      ),
    );
  }
  return rows;
}
