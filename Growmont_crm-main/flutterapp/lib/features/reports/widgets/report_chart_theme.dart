// lib/features/reports/widgets/report_chart_theme.dart
//
// The report charts' accent colours, and the reasoning behind them. The
// drawing itself lives in the shared chart kit (lib/shared/charts).
//
// The colours were validated against the data-viz palette validator
// (light surface):
//
//   navy500 #2458A8 + green500 #2D8A4E   all checks PASS
//   navy500 #2458A8 + slate400 #94A3B8   dE 26.2 normal / 24.6 protan
//   navy500 #2458A8 + slate500 #64748B   FAIL: dE 13.0 normal (<15)
//   navy600 #0F4491                      FAIL: lightness 0.402 (band .43-.77)
//
// So the accent is navy500, NOT AppColors.primaryBlue (navy700 #00337C),
// which sits below the lightness band and reads as a heavy block at bar
// size. primaryBlue stays correct for buttons and text; it is the wrong
// value for a large filled mark.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ReportChart {
  const ReportChart._();

  /// The single accent every data mark uses.
  static const Color accent = AppPalette.navy500;

  /// Context / de-emphasis, e.g. a rolled-up "Others" bar. Its contrast
  /// against white is 2.5:1, so it is never the only carrier of meaning:
  /// the row's label and figures sit beside it.
  static const Color context = AppPalette.slate400;
}

/// A legend. Always present for two or more series; a single-series chart
/// gets none, because its title already says what is plotted.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.entries});

  final List<({String label, Color color})> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: entry.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                entry.label,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// The validated ordinal ramp, light to dark, in scale order.
const List<Color> kOrdinalRamp = [
  AppPalette.navy300,
  AppPalette.navy400,
  AppPalette.navy500,
  AppPalette.navy700,
  AppPalette.navy900,
];
