// lib/features/reports/phone/phone_style.dart
//
// Type styles, money formatting and the card / section shells shared by the
// phone Reports screens. Numbers are always set in the display font with
// tabular figures so columns of them line up.

import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';

class PhoneText {
  const PhoneText._();

  /// Display-font figure with tabular numerals.
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
    letterSpacing: size >= 20 ? -0.4 : -0.1,
    height: 1.15,
  );

  static const TextStyle label = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 1.25,
  );

  static const TextStyle muted = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textCaption,
    height: 1.25,
  );

  static const TextStyle rowTitle = TextStyle(
    fontFamily: AppTypography.text,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: AppTypography.display,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.25,
  );
}

/// Whole rupees in Indian grouping, from paise: ₹12,34,567.
String fullMoney(num paise) =>
    AppFormatters.formatAmount((paise / 100).toStringAsFixed(2));

/// ₹1.2L, ₹3.0L, ₹12.5K, ₹1.2Cr, ₹850. Always one decimal above ₹1,000.
String compactMoney(num paise) {
  final negative = paise < 0;
  final rupees = paise.abs() / 100;
  String body;
  if (rupees >= 10000000) {
    body = '${_one(rupees / 10000000)}Cr';
  } else if (rupees >= 100000) {
    final v = _one(rupees / 100000);
    body = v == '100.0' ? '1.0Cr' : '${v}L';
  } else if (rupees >= 1000) {
    final v = _one(rupees / 1000);
    body = v == '100.0' ? '1.0L' : '${v}K';
  } else {
    body = rupees.toStringAsFixed(0);
  }
  return '${negative ? '−' : ''}₹$body';
}

String _one(double v) => v.toStringAsFixed(1);

String percentText(double percent) {
  final magnitude = percent.abs();
  return magnitude >= 100
      ? magnitude.toStringAsFixed(0)
      : magnitude.toStringAsFixed(1);
}

/// A signed change line for a KPI tile: "+3", "−12%" with its colour; null with no baseline.
({String text, Color color})? kpiDelta(
  MetricDelta delta, {
  bool percent = false,
}) {
  // No baseline: nothing to compare against, so no line at all.
  if (delta.previous == 0) return null;
  if (percent) {
    final p = delta.percentChange;
    if (p == null) return null;
    if (delta.isFlat) return (text: '0%', color: AppColors.textMuted);
    return (
      text: '${delta.isUp ? '+' : '−'}${percentText(p)}%',
      color: delta.isUp ? AppColors.success : AppColors.danger,
    );
  }
  final change = delta.change;
  if (change == 0) return (text: '0', color: AppColors.textMuted);
  return (
    text: '${change > 0 ? '+' : '−'}${change.abs().round()}',
    color: change > 0 ? AppColors.success : AppColors.danger,
  );
}

/// White, 16px-radius, 1px-border panel. No shadow.
class PhoneCard extends StatelessWidget {
  const PhoneCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(16);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: shape,
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A 16/700 title, 12px of air, then the body.
class PhoneSection extends StatelessWidget {
  const PhoneSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.minTitleHeight,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// Minimum height of the title row, so titles of side-by-side sections
  /// line up whether or not one of them has a [trailing] button.
  final double? minTitleHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minTitleHeight ?? 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: PhoneText.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Stacks [sections] with the 24px rhythm between them.
List<Widget> spaced(List<Widget> sections, {double gap = 24}) => [
  for (var i = 0; i < sections.length; i++) ...[
    if (i > 0) SizedBox(height: gap),
    sections[i],
  ],
];

/// The single muted line shown in place of the sections of an empty period.
class EmptyPeriodLine extends StatelessWidget {
  const EmptyPeriodLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(child: Text(text, style: PhoneText.muted)),
  );
}
