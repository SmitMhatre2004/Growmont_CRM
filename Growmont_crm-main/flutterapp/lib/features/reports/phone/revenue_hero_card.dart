// lib/features/reports/phone/revenue_hero_card.dart
//
// The big revenue figure, its change against the previous period (hidden
// when there is nothing to compare with) and, optionally, a slim area chart.

import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/charts/charts.dart';
import 'phone_style.dart';

class RevenueHeroCard extends StatelessWidget {
  const RevenueHeroCard({
    super.key,
    required this.revenue,
    required this.daily,
    required this.previousLabel,
    this.showChart = true,
    this.chartHeight = 120,
    this.expandChart = false,
    this.centerContent = false,
  });

  /// Paise, with the previous period as baseline.
  final MetricDelta revenue;
  final List<DayTotal> daily;
  final String previousLabel;

  /// False on the employee report, whose Daily activity section covers it.
  final bool showChart;

  /// Height of the area chart (the phone default is slim).
  final double chartHeight;

  /// Wide layout: the chart takes whatever height the card is given. The
  /// card must then sit in a bounded height.
  final bool expandChart;

  /// Centre the figure vertically (a card stretched beside taller tiles).
  final bool centerContent;

  /// Whether [build] draws the chart for these figures.
  bool get hasChart => showChart && revenue.current > 0 && daily.length > 1;

  @override
  Widget build(BuildContext context) {
    final hasDelta = revenue.percentChange != null;

    return PhoneCard(
      child: Column(
        mainAxisAlignment: centerContent
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Revenue', style: PhoneText.label),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fullMoney(revenue.current),
              maxLines: 1,
              style: PhoneText.number(36),
            ),
          ),
          if (hasDelta) ...[
            const SizedBox(height: 10),
            DeltaPill(delta: revenue, previousLabel: previousLabel),
          ],
          if (hasChart) ...[
            const SizedBox(height: 16),
            if (expandChart)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => DailyRevenueChart(
                    days: daily,
                    height: constraints.maxHeight.clamp(100.0, 400.0),
                  ),
                ),
              )
            else
              DailyRevenueChart(days: daily, height: chartHeight),
          ],
        ],
      ),
    );
  }
}

/// "▲ 12.3% vs Oct" on a tinted pill. Nothing at all with no baseline.
class DeltaPill extends StatelessWidget {
  const DeltaPill({
    super.key,
    required this.delta,
    required this.previousLabel,
  });

  final MetricDelta delta;
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final percent = delta.percentChange;
    if (percent == null) return const SizedBox.shrink();

    final Color ink;
    final Color fill;
    final String text;
    IconData? icon;

    if (delta.isFlat) {
      ink = AppColors.textSecondary;
      fill = AppColors.surfaceSunken;
      text = '${percentText(0)}% vs $previousLabel';
    } else {
      final up = delta.isUp;
      ink = up ? AppColors.success : AppColors.danger;
      fill = up ? AppColors.successSoft : AppColors.dangerSoft;
      icon = up ? Icons.arrow_drop_up : Icons.arrow_drop_down;
      text = '${percentText(percent)}% vs $previousLabel';
    }

    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 10 : 4, 3, 10, 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 20, color: ink),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PhoneText.number(13, weight: FontWeight.w700, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Revenue over the period as a slim area chart (bucketed weekly or monthly
/// for long ranges), no y labels; touch shows the bucket's value.
class DailyRevenueChart extends StatelessWidget {
  const DailyRevenueChart({super.key, required this.days, this.height = 120});

  final List<DayTotal> days;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = bucketDaily(days);
    // A month or less of daily sales is mostly empty days; a smooth area
    // turns that into a lone spike, so short ranges read as daily bars.
    if (days.length <= 62) {
      return GrowBarChart(
        bars: [
          for (final p in points)
            ChartBar(label: p.label ?? '', value: p.y, detail: p.detail),
        ],
        height: height,
        showYAxis: false,
      );
    }
    return GrowAreaChart(points: points, height: height, showYAxis: false);
  }
}
