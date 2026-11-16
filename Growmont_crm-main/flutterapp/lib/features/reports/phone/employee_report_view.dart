// lib/features/reports/phone/employee_report_view.dart
//
// One person's report on a phone. [EmployeeReportBody] is the stack of
// sections (used inline by a non-admin and inside the admin's full-screen
// route); [EmployeeReportScreen] is that route.

import 'package:flutter/material.dart';

import '../../../core/reports/employee_report.dart';
import '../../../core/reports/monthly_report_builder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/client.dart';
import '../../../models/interaction.dart';
import '../../../models/sale.dart';
import 'breakdowns.dart';
import 'employee_sections.dart';
import 'kpi_grid.dart';
import 'period_bar.dart';
import 'period_selection.dart';
import 'phone_style.dart';
import 'wide_layout.dart';
import 'report_export.dart';
import 'revenue_hero_card.dart';

/// The in-memory lists every phone report is built from. Already scoped to
/// what the signed-in user may see.
class ReportData {
  const ReportData({
    required this.sales,
    required this.interactions,
    required this.clients,
    required this.employeeNames,
  });

  final List<Sale> sales;
  final List<Interaction> interactions;
  final List<Client> clients;
  final Map<String, String> employeeNames;

  /// The lists with [excludedIds] (developer / test accounts) removed from
  /// everything: their sales, follow-ups and clients, matched by the rules
  /// the builders attribute records by, and their roster entries.
  factory ReportData.scoped({
    required List<Sale> sales,
    required List<Interaction> interactions,
    required List<Client> clients,
    required Map<String, String> employeeNames,
    Set<String> excludedIds = const {},
  }) {
    if (excludedIds.isEmpty) {
      return ReportData(
        sales: sales,
        interactions: interactions,
        clients: clients,
        employeeNames: employeeNames,
      );
    }
    return ReportData(
      sales: [
        for (final s in sales)
          if (!excludedIds.contains(MonthlyReportBuilder.repIdOf(s))) s,
      ],
      interactions: [
        for (final i in interactions)
          if (!excludedIds.contains((i.employeeId ?? i.employee).trim())) i,
      ],
      clients: [
        for (final c in clients)
          if (!excludedIds.contains(c.employeeId.trim())) c,
      ],
      employeeNames: {
        for (final e in employeeNames.entries)
          if (!excludedIds.contains(e.key)) e.key: e.value,
      },
    );
  }

  EmployeeReport employeeReport(
    String employeeId,
    ReportPeriodSelection period,
  ) => EmployeeReportBuilder.build(
    range: period.range,
    previous: period.previousRange,
    employeeId: employeeId,
    sales: sales,
    interactions: interactions,
    clients: clients,
    employeeNames: employeeNames,
  );
}

/// The sections of an employee report, without any scaffolding.
class EmployeeReportBody extends StatelessWidget {
  const EmployeeReportBody({
    super.key,
    required this.report,
    required this.period,
    this.wide = false,
  });

  final EmployeeReport report;
  final ReportPeriodSelection period;

  /// The 768-and-up arrangement: hero and KPI tiles side by side, sections
  /// two to a row.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final hero = RevenueHeroCard(
      revenue: report.revenue,
      daily: report.dailyRevenue,
      previousLabel: period.previousLabel,
      showChart: false,
    );

    final empty =
        report.revenue.current == 0 &&
        report.deals.current == 0 &&
        report.interactions.current == 0 &&
        report.newClients.current == 0 &&
        report.activity.isEmpty;

    if (empty) {
      return Column(
        children: [
          hero,
          const SizedBox(height: 24),
          EmptyPeriodLine(period.emptyText),
        ],
      );
    }

    final dealsDelta = kpiDelta(report.deals);
    final clientsDelta = kpiDelta(report.clients);
    final followUpsDelta = kpiDelta(report.interactions);
    final overdue = report.followUpsOverdue;

    final tiles = [
      KpiData(
        'Deals',
        '${report.deals.current}',
        deltaText: dealsDelta?.text,
        deltaColor: dealsDelta?.color ?? AppColors.textMuted,
      ),
      KpiData(
        'Clients',
        '${report.clients.current}',
        deltaText: clientsDelta?.text,
        deltaColor: clientsDelta?.color ?? AppColors.textMuted,
      ),
      KpiData(
        'Follow-ups',
        '${report.interactions.current}',
        deltaText: followUpsDelta?.text,
        deltaColor: followUpsDelta?.color ?? AppColors.textMuted,
      ),
      KpiData(
        'Overdue',
        '$overdue',
        valueColor: overdue > 0 ? AppColors.danger : AppColors.textPrimary,
      ),
    ];
    final daily = PhoneSection(
      title: 'Daily activity',
      child: DailyActivityChart(
        revenue: report.dailyRevenue,
        followUps: report.dailyInteractions,
        weekly: false,
      ),
    );
    final products = report.revenueByProduct.any((r) => r.paise > 0)
        ? PhoneSection(
            title: 'Products',
            child: RankedBars(rows: report.revenueByProduct),
          )
        : null;
    final activity = report.activity.isNotEmpty
        ? PhoneSection(
            title: 'Activity',
            child: ActivityTimeline(entries: report.activity),
          )
        : null;
    final upcoming = report.upcomingFollowUps.isNotEmpty
        ? PhoneSection(
            title: 'Upcoming follow-ups',
            child: UpcomingFollowUps(items: report.upcomingFollowUps),
          )
        : null;

    if (!wide) {
      return Column(
        children: spaced([
          hero,
          KpiGrid(tiles: tiles),
          VsTeamAverage(report: report),
          daily,
          ?products,
          ?activity,
          ?upcoming,
        ]),
      );
    }

    // VsTeamAverage draws nothing without a team to compare against.
    final hasAverage =
        report.teamAvgRevenuePaise != null &&
        report.teamAvgDeals != null &&
        report.teamAvgInteractions != null;

    return Column(
      children: spaced([
        WideHeroKpis(
          revenue: report.revenue,
          daily: report.dailyRevenue,
          previousLabel: period.previousLabel,
          tiles: tiles,
          showChart: false,
        ),
        if (hasAverage || products != null)
          SplitRow(
            left: hasAverage ? VsTeamAverage(report: report) : products!,
            right: hasAverage ? products : null,
          ),
        daily,
        if (activity != null || upcoming != null)
          SplitRow(
            left: activity ?? upcoming!,
            right: activity != null ? upcoming : null,
            leftFlex: 3,
            rightFlex: 2,
          ),
      ]),
    );
  }
}

/// Identity row, the period bar (month by default, optional custom range) and
/// the report sections. Owns the selected period; changing it rebuilds from the
/// in-memory lists and never reloads.
class EmployeeReportPanel extends StatefulWidget {
  const EmployeeReportPanel({
    super.key,
    required this.employeeId,
    required this.initialPeriod,
    required this.data,
    this.onPeriodChanged,
    this.wide = false,
    this.onExport,
    this.exporting = false,
  });

  final String employeeId;
  final ReportPeriodSelection initialPeriod;
  final ReportData data;
  final ValueChanged<ReportPeriodSelection>? onPeriodChanged;

  /// The 768-and-up arrangement: identity, period bar and Export share one
  /// header row ([onExport] is its Export button).
  final bool wide;
  final VoidCallback? onExport;
  final bool exporting;

  @override
  State<EmployeeReportPanel> createState() => _EmployeeReportPanelState();
}

class _EmployeeReportPanelState extends State<EmployeeReportPanel> {
  late ReportPeriodSelection _period = widget.initialPeriod;

  @override
  Widget build(BuildContext context) {
    final report = widget.data.employeeReport(widget.employeeId, _period);

    void changed(ReportPeriodSelection p) {
      setState(() => _period = p);
      widget.onPeriodChanged?.call(p);
    }

    if (widget.wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WideHeader(
            leading: EmployeeIdentity(report: report),
            selection: _period,
            onSelectionChanged: changed,
            onExport: widget.onExport ?? () {},
            exporting: widget.exporting,
            inlineMin: 880,
          ),
          const SizedBox(height: 24),
          EmployeeReportBody(report: report, period: _period, wide: true),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmployeeIdentity(report: report),
        const SizedBox(height: 16),
        PeriodBar(
          selection: _period,
          onChanged: (p) {
            setState(() => _period = p);
            widget.onPeriodChanged?.call(p);
          },
        ),
        const SizedBox(height: 16),
        EmployeeReportBody(report: report, period: _period),
      ],
    );
  }
}

/// Full-screen route an admin opens from a Team row: a back button and an
/// Export action, then the panel (the name lives in its header). It opens on
/// the main screen's period but changes it independently.
class EmployeeReportScreen extends StatefulWidget {
  const EmployeeReportScreen({
    super.key,
    required this.employeeId,
    required this.initialPeriod,
    required this.data,
    this.generatedBy = '',
  });

  final String employeeId;
  final ReportPeriodSelection initialPeriod;
  final ReportData data;

  /// Printed in the PDF footer.
  final String generatedBy;

  @override
  State<EmployeeReportScreen> createState() => _EmployeeReportScreenState();
}

class _EmployeeReportScreenState extends State<EmployeeReportScreen> {
  late ReportPeriodSelection _period = widget.initialPeriod;
  bool _exporting = false;

  Future<void> _export() async {
    final choice = await showPhoneExportSheet(
      context,
      allowExcel: _period.isMonth,
    );
    if (choice == null || !mounted) return;
    setState(() => _exporting = true);
    await exportPhoneReport(
      context,
      choice: choice,
      data: widget.data,
      selection: _period,
      generatedBy: widget.generatedBy,
      employeeId: widget.employeeId,
    );
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final wide = !AppLayout.isMobile(context);
    final side = wide
        ? wideSidePadding(MediaQuery.sizeOf(context).width)
        : 16.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Wide: Export lives in the report's own header row.
        actions: wide
            ? null
            : [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: _exporting
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'Export',
                          onPressed: _export,
                          icon: const Icon(Icons.download_outlined),
                        ),
                ),
              ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, wide ? 24 : 16, side, 32),
          children: [
            EmployeeReportPanel(
              employeeId: widget.employeeId,
              initialPeriod: widget.initialPeriod,
              data: widget.data,
              wide: wide,
              onExport: wide ? _export : null,
              exporting: _exporting,
              onPeriodChanged: (p) => setState(() => _period = p),
            ),
          ],
        ),
      ),
    );
  }
}
