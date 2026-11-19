// lib/shared/charts/chart_theme.dart
//
// Tokens for the chart kit. Every chart in the app reads its colours, text
// styles, motion and money formatting from here so they all look the same:
// dashed horizontal grid, muted axis text, white tooltip cards.

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../features/reports/phone/phone_style.dart'
    show compactMoney, fullMoney;
import '../../features/reports/widgets/report_chart_theme.dart';

class ChartTheme {
  const ChartTheme._();

  /// Primary data colour (navy500). See report_chart_theme.dart for why this
  /// is not the brand navy.
  static const Color accent = ReportChart.accent;

  /// Pressed / hovered shade of [accent].
  static const Color accentDark = AppPalette.navy700;

  /// Categorical palette, fixed order across the product.
  static const List<Color> palette = AppChart.series;

  static Color paletteAt(int i) => AppChart.seriesAt(i);

  static const Color grid = AppPalette.slate200;
  static const Color cursor = AppPalette.slate300;
  static const Color track = AppPalette.slate100;

  static const Duration animation = Duration(milliseconds: 600);
  static const Curve curve = Curves.easeOutCubic;

  /// Dash pattern of the horizontal grid and the touch cursor.
  static const List<int> dash = [4, 4];

  static const TextStyle axis = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
    height: 1.2,
  );

  static const TextStyle tooltipLabel = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.25,
  );

  static const TextStyle tooltipValue = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    fontFeatures: AppTypography.tabular,
    height: 1.25,
  );

  static const TextStyle tooltipDetail = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
    height: 1.25,
  );

  static const TextStyle rowLabel = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static const TextStyle rowSub = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.25,
  );

  static TextStyle number(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textPrimary,
  }) => TextStyle(
    fontFamily: AppTypography.display,
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: AppTypography.tabular,
    height: 1.2,
  );

  static List<BoxShadow> get tooltipShadow => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.12),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  /// ₹1.2L, ₹75.5K, ₹1.2Cr: one shared formatter (phone_style.dart).
  static String compact(double rupees) => compactMoney(rupees * 100);

  /// Axis ticks drop a trailing ".0": ₹20K rather than ₹20.0K.
  static String axisMoney(double rupees) {
    if (rupees == 0) return '₹0';
    return compact(
      rupees,
    ).replaceFirstMapped(RegExp(r'\.0(?=[KLC])'), (_) => '');
  }

  /// Full Indian-grouped rupees, ₹12,34,567.
  static String fullRupees(double rupees) => fullMoney(rupees * 100);

  /// "62%", "0.4%" for a sliver, "<0.1%" below that.
  static String percent(double fraction) {
    final p = fraction * 100;
    if (p <= 0) return '0%';
    if (p < 1) return p < 0.1 ? '<0.1%' : '${p.toStringAsFixed(1)}%';
    return '${p.round()}%';
  }
}
