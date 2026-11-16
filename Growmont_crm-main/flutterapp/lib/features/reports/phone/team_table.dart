// lib/features/reports/phone/team_table.dart
//
// The wide Team tab: "Active n of m" and one table card with tappable column
// headers that sort. Tapping a row opens that person's report. Idle people
// always sit last, dimmed.

import 'package:flutter/material.dart';

import '../../../core/reports/period_summary_builder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/monogram.dart';
import 'phone_style.dart';

/// The sortable columns, in display order.
enum TeamColumn {
  employee('Employee', 30),
  revenue('Revenue', 17),
  change('Change', 11),
  deals('Deals', 10),
  clients('Clients', 10),
  followUps('Follow-ups', 12),
  newClients('New clients', 13),
  overdue('Overdue', 10);

  const TeamColumn(this.label, this.flex);
  final String label;
  final int flex;

  bool get isNumeric => this != TeamColumn.employee;

  /// The direction a first tap sorts in: A to Z for names, biggest first
  /// for figures.
  bool get ascendingFirst => this == TeamColumn.employee;

  num _value(EmployeePeriodRow r) => switch (this) {
    TeamColumn.employee => 0,
    TeamColumn.revenue => r.revenuePaise,
    TeamColumn.change =>
      r.revenueDelta.percentChange ?? double.negativeInfinity,
    TeamColumn.deals => r.dealCount,
    TeamColumn.clients => r.clientCount,
    TeamColumn.followUps => r.interactionCount,
    TeamColumn.newClients => r.newClientCount,
    TeamColumn.overdue => r.overdueCount,
  };

  int compare(EmployeePeriodRow a, EmployeePeriodRow b) {
    if (this == TeamColumn.employee) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    return _value(a).compareTo(_value(b));
  }
}

/// Active people by [column] ([ascending] or not; revenue then name break
/// ties), idle people after them in their incoming order.
List<EmployeePeriodRow> sortTeamBy(
  List<EmployeePeriodRow> rows,
  TeamColumn column,
  bool ascending,
) {
  final active = rows.where((r) => !r.isIdle).toList()
    ..sort((a, b) {
      final primary = column.compare(a, b);
      if (primary != 0) return ascending ? primary : -primary;
      final byRevenue = b.revenuePaise.compareTo(a.revenuePaise);
      return byRevenue != 0 ? byRevenue : a.name.compareTo(b.name);
    });
  return [...active, ...rows.where((r) => r.isIdle)];
}

const double _rankWidth = 36;

class TeamTable extends StatelessWidget {
  const TeamTable({
    super.key,
    required this.rows,
    required this.column,
    required this.ascending,
    required this.onSort,
    required this.onEmployeeTap,
  });

  final List<EmployeePeriodRow> rows;
  final TeamColumn column;
  final bool ascending;
  final ValueChanged<TeamColumn> onSort;
  final ValueChanged<EmployeePeriodRow> onEmployeeTap;

  /// Narrower than this the table scrolls sideways instead of squeezing.
  static const double _minWidth = 820;

  @override
  Widget build(BuildContext context) {
    final sorted = sortTeamBy(rows, column, ascending);
    final activeCount = rows.where((r) => !r.isIdle).length;

    final table = Column(
      children: [
        _headerRow(),
        const Divider(height: 1, color: AppColors.divider),
        for (var i = 0; i < sorted.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.divider),
          _TeamTableRow(
            row: sorted[i],
            position: i + 1,
            onTap: () => onEmployeeTap(sorted[i]),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Active $activeCount of ${rows.length}', style: PhoneText.label),
        const SizedBox(height: 12),
        PhoneCard(
          padding: EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _minWidth) return table;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: _minWidth, child: table),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _headerRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const SizedBox(width: _rankWidth),
          for (final c in TeamColumn.values)
            Expanded(
              flex: c.flex,
              child: _HeaderCell(
                column: c,
                active: c == column,
                ascending: ascending,
                onTap: () => onSort(c),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final TeamColumn column;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = PhoneText.label.copyWith(
      color: active ? AppColors.textPrimary : AppColors.textSecondary,
    );
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: column.isNumeric
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              SizedBox(
                width: 16,
                child: active
                    ? Icon(
                        ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                        color: AppColors.textPrimary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamTableRow extends StatelessWidget {
  const _TeamTableRow({
    required this.row,
    required this.position,
    required this.onTap,
  });

  final EmployeePeriodRow row;
  final int position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idle = row.isIdle;
    final delta = row.revenueDelta;
    final percent = delta.percentChange;
    final changeColor = percent == null || delta.isFlat
        ? AppColors.textMuted
        : delta.isUp
        ? AppColors.success
        : AppColors.danger;
    final changeText = percent == null
        ? '–'
        : delta.isFlat
        ? '0%'
        : '${delta.isUp ? '+' : '−'}${percentText(percent)}%';

    Widget cell(
      TeamColumn c,
      String text, {
      Color color = AppColors.textPrimary,
      FontWeight weight = FontWeight.w500,
    }) => Expanded(
      flex: c.flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: PhoneText.number(14, weight: weight, color: color),
      ),
    );

    String count(int n) => n == 0 ? '–' : '$n';
    final overdue = row.overdueCount > 0;

    return Opacity(
      opacity: idle ? 0.55 : 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: _rankWidth,
                child: Text(
                  idle ? '–' : '$position',
                  style: PhoneText.number(
                    14,
                    weight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Expanded(
                flex: TeamColumn.employee.flex,
                child: Row(
                  children: [
                    Monogram(name: row.name, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhoneText.rowTitle,
                      ),
                    ),
                  ],
                ),
              ),
              cell(
                TeamColumn.revenue,
                row.revenuePaise == 0 ? '–' : fullMoney(row.revenuePaise),
                weight: FontWeight.w700,
              ),
              cell(
                TeamColumn.change,
                changeText,
                color: changeColor,
                weight: FontWeight.w600,
              ),
              cell(TeamColumn.deals, count(row.dealCount)),
              cell(TeamColumn.clients, count(row.clientCount)),
              cell(TeamColumn.followUps, count(row.interactionCount)),
              cell(TeamColumn.newClients, count(row.newClientCount)),
              cell(
                TeamColumn.overdue,
                count(row.overdueCount),
                color: overdue ? AppColors.danger : AppColors.textPrimary,
                weight: overdue ? FontWeight.w700 : FontWeight.w500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
