// lib/shared/widgets/hero_stat_card.dart
//
// The phone summary card: one headline number on the left, a short
// label/value list on the right, split by a thin divider.

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class HeroStat {
  const HeroStat(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;
}

class HeroStatCard extends StatelessWidget {
  const HeroStatCard({
    super.key,
    required this.label,
    required this.value,
    this.valueSuffix,
    this.footer,
    this.badge,
    this.stats = const [],
    this.onTap,
    this.compactValue = false,
  });

  /// Small uppercase heading, e.g. "REVENUE".
  final String label;

  /// The big number.
  final String value;

  /// Muted text right after the value, e.g. "/12".
  final String? valueSuffix;

  /// One short line under the number (or a widget such as a delta chip).
  final Widget? footer;

  /// Optional widget at the top-right of the left column.
  final Widget? badge;

  final List<HeroStat> stats;
  final VoidCallback? onTap;

  /// Smaller headline for long values (money) or nested cards.
  final bool compactValue;

  @override
  Widget build(BuildContext context) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ?badge,
          ],
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontFamily: AppTypography.display,
                    fontSize: compactValue ? 30 : 44,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    height: 1.05,
                    color: AppColors.textPrimary,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
                if (valueSuffix != null)
                  TextSpan(
                    text: valueSuffix,
                    style: TextStyle(
                      fontFamily: AppTypography.display,
                      fontSize: compactValue ? 16 : 22,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 12),
          footer!,
        ],
      ],
    );

    final right = Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final s in stats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.text,
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      s.value,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: AppTypography.display,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: s.valueColor ?? AppColors.textPrimary,
                        fontFeatures: AppTypography.tabular,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final card = Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: stats.isEmpty
          ? left
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 11, child: left),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                  ),
                  Expanded(flex: 10, child: right),
                ],
              ),
            ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
