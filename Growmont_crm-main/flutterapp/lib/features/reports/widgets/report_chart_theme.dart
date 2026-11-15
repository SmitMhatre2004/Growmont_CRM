// lib/features/reports/widgets/report_chart_theme.dart
//
// Chart tokens for the Monthly Report, and the reasoning behind them.
//
// ── The colours were validated, not chosen by eye ────────────────────────
//
// Run against the data-viz palette validator (light surface), these are
// the results that picked the values below:
//
//   navy500 #2458A8 + green500 #2D8A4E   all checks PASS
//   navy500 #2458A8 + slate400 #94A3B8   ΔE 26.2 normal / 24.6 protan
//   navy500 #2458A8 + slate500 #64748B   FAIL: ΔE 13.0 normal (<15)
//   navy600 #0F4491                      FAIL: lightness 0.402 (band .43–.77)
//
// So the accent is navy500 — NOT AppColors.primaryBlue (navy700 #00337C),
// which sits below the lightness band and reads as a heavy block at bar
// size. primaryBlue stays correct for buttons and text; it is the wrong
// value for a large filled mark.
//
// The app's existing five-slot AppChart.series palette fails the same
// band check (navy700 too dark, green300 too light). It is left alone —
// the dashboard's product pie depends on it — but nothing here extends it.
// These charts need one hue plus a de-emphasis gray, never five identities.
//
// ── Forms ────────────────────────────────────────────────────────────────
//
// Deliberately NO donut or pie. Product mix runs to seventeen categories
// with close values, which is the exact case ranked horizontal bars answer
// and a donut cannot: segments laid end to end cannot be compared, and
// past six parts adjacent slices blur. Revenue by product and by company
// are therefore ranked bars on one baseline, single hue, largest first.
//
// The trend is EMPHASIS, not two categorical series: this year is the
// subject and last year is context, so one hue carries the subject and a
// gray carries the context. That also sidesteps seating a second identity
// colour for something that is not a second identity.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ReportChart {
  const ReportChart._();

  /// The single accent every data mark uses. See the header for why this
  /// is navy500 rather than AppColors.primaryBlue.
  static const Color accent = AppPalette.navy500;

  /// Context / de-emphasis, for last year's line and for a zero bar's
  /// track. Its contrast against white is 2.5:1, below the 3:1 mark, which
  /// the validator flags as "relief required" — so every chart using it
  /// carries a legend with visible text labels and a table of the same
  /// figures beside it. Never use it alone to carry meaning.
  static const Color context = AppPalette.slate400;

  /// A second identity, only where two things genuinely are different
  /// subjects. Validated against [accent]: all checks pass.
  static const Color accentAlt = AppPalette.green500;

  /// Hairline grid and axis rules: one step off the surface, solid, never
  /// dashed.
  static const Color grid = AppColors.divider;

  /// Bars are capped rather than filling their slot, so the band keeps
  /// some air. 4px rounded data-end, square at the baseline.
  static const double barThickness = 18;
  static const double barMaxThickness = 24;
  static const Radius barEnd = Radius.circular(4);

  /// 2px line, round cap/join.
  static const double lineWidth = 2;

  /// Markers are >= 8px across, carrying a 2px ring in the surface colour
  /// so they stay legible where the two series cross.
  static const double markerRadius = 4;
  static const double markerRing = 2;

  /// The 2px of surface that separates touching marks. White does the
  /// separating; a stroke around a mark would add ink that is not data.
  static const double surfaceGap = 2;

  /// Series hue at ~10% for an area wash — never a saturated block.
  static Color wash(Color series) => series.withValues(alpha: 0.10);

  /// Axis tick / label text. Text never wears the data colour; identity
  /// comes from the coloured mark beside it.
  static const TextStyle axisLabel = TextStyle(
    fontSize: 11,
    color: AppColors.textMuted,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle axisLabelStrong = TextStyle(
    fontSize: 11,
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w700,
  );
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
