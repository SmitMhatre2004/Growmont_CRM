// lib/features/reports/phone/overview_sections.dart
//
// Overview-only blocks: top performers, largest deals, and the trailing
// twelve months bar chart.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/reports/monthly_report_builder.dart';
import '../../../core/reports/period_summary_builder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/sale.dart';
import '../../../shared/charts/charts.dart';
import '../../../shared/widgets/monogram.dart';
import '../../../shared/widgets/monthly_revenue_chart.dart' show salePaise;
import 'phone_style.dart';

String dealsText(int n) => n == 1 ? '1 deal' : '$n deals';

/// Top five by revenue: rank, avatar, name and deal count, revenue, and a
/// thin bar for their share of the team.
class TopPerformers extends StatelessWidget {
  const TopPerformers({super.key, required this.rows, this.limit = 5});

  /// Highest revenue first, as PeriodSummary.employees is.
  final List<EmployeePeriodRow> rows;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final top = rows.where((r) => r.revenuePaise > 0).take(limit).toList();

    return PhoneCard(
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _PerformerRow(row: top[i], rank: i + 1),
          ],
        ],
      ),
    );
  }
}

class _PerformerRow extends StatelessWidget {
  const _PerformerRow({required this.row, required this.rank});

  final EmployeePeriodRow row;
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: PhoneText.number(
                  14,
                  weight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Monogram(name: row.name, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhoneText.rowTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(dealsText(row.dealCount), style: PhoneText.muted),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(compactMoney(row.revenuePaise), style: PhoneText.number(15)),
          ],
        ),
        const SizedBox(height: 10),
        GrowTrack(fraction: row.share),
      ],
    );
  }
}

/// Largest sales of the period: client, "Product · Rep", amount and date.
class LargestDeals extends StatelessWidget {
  const LargestDeals({
    super.key,
    required this.deals,
    required this.employeeNames,
  });

  final List<Sale> deals;
  final Map<String, String> employeeNames;

  @override
  Widget build(BuildContext context) {
    final rows = deals.take(kTopDealCount).toList();

    return PhoneCard(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 12),
            ],
            _DealRow(sale: rows[i], employeeNames: employeeNames),
          ],
        ],
      ),
    );
  }
}

class _DealRow extends StatelessWidget {
  const _DealRow({required this.sale, required this.employeeNames});

  final Sale sale;
  final Map<String, String> employeeNames;

  @override
  Widget build(BuildContext context) {
    final product = sale.productDisplay?.isNotEmpty == true
        ? sale.productDisplay!
        : MonthlyReportBuilder.labelFor(productCategories, sale.product);
    final repId = MonthlyReportBuilder.repIdOf(sale);
    final rep =
        (sale.salesRepName?.isNotEmpty == true
            ? sale.salesRepName
            : employeeNames[repId]) ??
        '';
    final day = parseEventDate(sale.date);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sale.clientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhoneText.rowTitle,
              ),
              const SizedBox(height: 2),
              Text(
                rep.isEmpty ? product : '$product · $rep',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhoneText.muted,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fullMoney(salePaise(sale)), style: PhoneText.number(15)),
            if (day != null) ...[
              const SizedBox(height: 2),
              Text(DateFormat('d MMM').format(day), style: PhoneText.muted),
            ],
          ],
        ),
      ],
    );
  }
}

/// Twelve monthly bars ending at the selected month; the selected one is
/// solid and carries its value, the rest are muted. Tapping a bar selects
/// that month.
class TrailingMonthsChart extends StatelessWidget {
  const TrailingMonthsChart({
    super.key,
    required this.months,
    required this.onMonthTap,
  });

  final List<MonthTotal> months;
  final ValueChanged<ReportMonth> onMonthTap;

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();

    final selectedIndex = months.length - 1;

    return PhoneCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Initials when the slots are too narrow for "Oct".
          final full = constraints.maxWidth / months.length >= 28;
          return GrowBarChart(
            height: 170,
            selectedIndex: selectedIndex,
            showValueOnSelected: true,
            selectedValueFormatter: (v) => compactMoney(v * 100),
            onTap: (i) {
              if (i != selectedIndex) onMonthTap(months[i].month);
            },
            bars: [
              for (final m in months)
                ChartBar(
                  label: DateFormat(
                    full ? 'MMM' : 'MMMMM',
                  ).format(m.month.start),
                  tooltipLabel: DateFormat('MMMM yyyy').format(m.month.start),
                  value: m.rupees,
                ),
            ],
          );
        },
      ),
    );
  }
}
