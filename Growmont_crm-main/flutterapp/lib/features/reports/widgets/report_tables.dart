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

/// Per-employee contribution for the period. Admin-only; the screen
/// decides whether to render it at all.
class TeamPerformanceTable extends StatelessWidget {
  const TeamPerformanceTable({
    super.key,
    required this.rows,
    required this.previousLabel,
    this.onEmployeeTap,
  });

  final List<EmployeePerformance> rows;
  final String previousLabel;

  /// Opens one person's own report. Null leaves the rows inert — the
  /// table is then just a table, with no affordance suggesting otherwise.
  final ValueChanged<EmployeePerformance>? onEmployeeTap;

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
          _Tappable(
            onTap: onEmployeeTap == null
                ? null
                : () => onEmployeeTap!(rows[i]),
            child: isNarrow ? _stackedRow(rows[i]) : _wideRow(rows[i]),
          ),
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
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DeltaChip(
                    delta: row.revenueDelta,
                    previousLabel: previousLabel,
                  ),
                ),
              ),
              if (onEmployeeTap != null)
                const Icon(
                  Icons.chevron_right,
                  size: AppSizing.iconMd,
                  color: AppColors.textMuted,
                ),
            ],
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

/// Wraps a row so it highlights under the pointer and opens on a tap.
/// Kept separate so the row builders stay layout-only.
class _Tappable extends StatefulWidget {
  const _Tappable({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: widget.child,
        ),
      ),
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
