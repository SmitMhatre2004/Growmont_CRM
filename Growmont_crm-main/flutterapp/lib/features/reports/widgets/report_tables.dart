// lib/features/reports/widgets/report_tables.dart
//
// The report's tabular sections: category breakdowns, the team table and
// the month's largest sales.
//
// All three are plain Columns of Rows rather than DataTable, matching how
// the rest of this app builds its lists, and so they can wrap sensibly on
// a phone instead of forcing a horizontal scroll.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/sale.dart';
import '../../../shared/widgets/monthly_revenue_chart.dart' show compactRupees;
import 'report_cards.dart';

/// Rupee text for a paise amount, in full Indian-grouped form.
String rupeesFromPaise(int paise) =>
    AppFormatters.formatAmount((paise / 100).toStringAsFixed(2));

/// A breakdown row with a share-of-total bar behind the label, so the
/// biggest contributors are visible without reading the numbers.
class BreakdownTable extends StatelessWidget {
  const BreakdownTable({
    super.key,
    required this.rows,
    this.emptyMessage = 'Nothing to break down for this month',
    this.maxRows,
    this.showAmount = true,
    this.countLabel = 'Deals',
  });

  final List<CategoryTotal> rows;

  final String emptyMessage;

  /// Caps how many rows render, rolling the rest into one "Other" row so
  /// a firm selling 18 product lines does not get an 18-row table. Null
  /// shows everything.
  final int? maxRows;

  /// False for breakdowns with no money on them, such as interaction
  /// priority, where an amount column would just read as zeroes.
  final bool showAmount;

  final String countLabel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          emptyMessage,
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    final visible = _collapse(rows, maxRows);
    final total = showAmount
        ? visible.fold<int>(0, (sum, r) => sum + r.paise)
        : visible.fold<int>(0, (sum, r) => sum + r.count);
    final largest = visible.fold<int>(
      0,
      (best, r) => (showAmount ? r.paise : r.count) > best
          ? (showAmount ? r.paise : r.count)
          : best,
    );

    return Column(
      children: [
        _headerRow(),
        const Divider(height: AppSpacing.lg, color: AppColors.divider),
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _row(visible[i], total: total, largest: largest),
        ],
      ],
    );
  }

  Widget _headerRow() {
    return Row(
      children: [
        Expanded(flex: 4, child: Text('Category', style: AppTypography.tableHeader)),
        Expanded(
          flex: 2,
          child: Text(
            countLabel,
            style: AppTypography.tableHeader,
            textAlign: TextAlign.right,
          ),
        ),
        if (showAmount)
          Expanded(
            flex: 3,
            child: Text(
              'Amount',
              style: AppTypography.tableHeader,
              textAlign: TextAlign.right,
            ),
          ),
        Expanded(
          flex: 2,
          child: Text(
            'Share',
            style: AppTypography.tableHeader,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _row(CategoryTotal row, {required int total, required int largest}) {
    final value = showAmount ? row.paise : row.count;
    final share = total == 0 ? 0.0 : value / total;
    final barWidth = largest == 0 ? 0.0 : value / largest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                row.label,
                style: AppTypography.tableCell,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${row.count}',
                style: AppTypography.tableCellNumeric,
                textAlign: TextAlign.right,
              ),
            ),
            if (showAmount)
              Expanded(
                flex: 3,
                child: Text(
                  rupeesFromPaise(row.paise),
                  style: AppTypography.tableCellNumeric.copyWith(
                    color: AppColors.money,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Expanded(
              flex: 2,
              child: Text(
                '${(share * 100).toStringAsFixed(share < 0.1 && share > 0 ? 1 : 0)}%',
                style: AppTypography.tableCellNumeric.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: LinearProgressIndicator(
            value: barWidth.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation(AppColors.primaryBlue),
          ),
        ),
      ],
    );
  }

  /// Keeps the top [limit] rows and sums the tail into one "Other" row, so
  /// the table's share column still adds to 100%.
  static List<CategoryTotal> _collapse(List<CategoryTotal> rows, int? limit) {
    if (limit == null || rows.length <= limit) return rows;

    final head = rows.take(limit - 1).toList();
    final tail = rows.skip(limit - 1);
    final label = rows.any((r) => r.label == 'Other')
        ? 'Other categories'
        : 'Other';

    return [
      ...head,
      CategoryTotal(
        label: '$label (${tail.length})',
        paise: tail.fold<int>(0, (sum, r) => sum + r.paise),
        count: tail.fold<int>(0, (sum, r) => sum + r.count),
      ),
    ];
  }
}

/// Per-employee contribution for the period. Admin-only; the screen
/// decides whether to render it at all.
class TeamPerformanceTable extends StatelessWidget {
  const TeamPerformanceTable({
    super.key,
    required this.rows,
    required this.previousLabel,
  });

  final List<EmployeePerformance> rows;
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          'No recorded activity from anyone this month or last.',
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    final isNarrow = MediaQuery.sizeOf(context).width < 760;

    return Column(
      children: [
        if (!isNarrow) ...[
          Row(
            children: [
              Expanded(flex: 4, child: Text('Employee', style: AppTypography.tableHeader)),
              Expanded(
                flex: 2,
                child: Text('Deals', style: AppTypography.tableHeader, textAlign: TextAlign.right),
              ),
              Expanded(
                flex: 3,
                child: Text('Revenue', style: AppTypography.tableHeader, textAlign: TextAlign.right),
              ),
              Expanded(
                flex: 3,
                child: Text('Avg deal', style: AppTypography.tableHeader, textAlign: TextAlign.right),
              ),
              Expanded(
                flex: 2,
                child: Text('Logs', style: AppTypography.tableHeader, textAlign: TextAlign.right),
              ),
              Expanded(flex: 3, child: Text('vs $previousLabel', style: AppTypography.tableHeader)),
            ],
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
        ],
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Divider(height: AppSpacing.lg, color: AppColors.divider),
          isNarrow ? _stackedRow(rows[i]) : _wideRow(rows[i]),
        ],
      ],
    );
  }

  Widget _wideRow(EmployeePerformance row) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            row.name,
            style: AppTypography.tableCellStrong,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            '${row.dealCount}',
            style: AppTypography.tableCellNumeric,
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            rupeesFromPaise(row.revenuePaise),
            style: AppTypography.tableCellNumeric.copyWith(color: AppColors.money),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            rupeesFromPaise(row.avgDealPaise),
            style: AppTypography.tableCellNumeric,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            '${row.interactionCount}',
            style: AppTypography.tableCellNumeric,
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: DeltaChip(
              delta: row.revenueDelta,
              previousLabel: previousLabel,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stackedRow(EmployeePerformance row) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.name,
                style: AppTypography.tableCellStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              rupeesFromPaise(row.revenuePaise),
              style: AppTypography.tableCellNumeric.copyWith(
                color: AppColors.money,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${row.dealCount} deals · avg ${compactRupees(row.avgDealPaise / 100)} · ${row.interactionCount} logs',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.xs),
        DeltaChip(delta: row.revenueDelta, previousLabel: previousLabel),
      ],
    );
  }
}

/// The month's largest sales. Gives a business owner the "what actually
/// moved the number" answer the totals cannot.
class TopDealsTable extends StatelessWidget {
  const TopDealsTable({super.key, required this.deals});

  final List<Sale> deals;

  @override
  Widget build(BuildContext context) {
    if (deals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          'No sales recorded in this month.',
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < deals.length; i++) ...[
          if (i > 0)
            const Divider(height: AppSpacing.lg, color: AppColors.divider),
          _row(deals[i]),
        ],
      ],
    );
  }

  Widget _row(Sale sale) {
    final date = DateTime.tryParse(sale.date);
    final product = sale.productDisplay?.isNotEmpty == true
        ? sale.productDisplay!
        : sale.product;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sale.clientName.isEmpty ? '—' : sale.clientName,
                style: AppTypography.tableCellStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                [
                  if (date != null) DateFormat('dd MMM').format(date),
                  if (product.isNotEmpty) product,
                  if (sale.salesRepName?.isNotEmpty == true) sale.salesRepName!,
                ].join(' · '),
                style: AppTypography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          rupeesFromPaise(
            sale.amountPaise != 0
                ? sale.amountPaise
                : ((double.tryParse(sale.amount) ?? 0) * 100).round(),
          ),
          style: AppTypography.tableCellNumeric.copyWith(
            color: AppColors.money,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
