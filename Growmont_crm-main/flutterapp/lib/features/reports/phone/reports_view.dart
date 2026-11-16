// lib/features/reports/phone/reports_view.dart
//
// The Reports screen body, on every width. The parent screen owns loading,
// scoping, export and the selected month; this widget turns the loaded lists
// into the period bar (a month, or an optional custom range), the Overview /
// Team tabs (admin) or the person's own report (everyone else), and Export.
//
// [ReportsView.wide] (768 and up) re-arranges the same sections: the title,
// period bar and Export share a header row, the tabs sit left-aligned, and
// the cards go two to a row inside a centred 1280px column. The phone layout
// is the default and is untouched by it.

import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/reports/monthly_report_builder.dart'
    show kUnspecifiedLabel;
import '../../../core/reports/period_summary_builder.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/report_tables.dart' show MonthlyHistoryTable;
import 'breakdowns.dart';
import 'employee_report_view.dart';
import 'kpi_grid.dart';
import 'overview_sections.dart';
import 'period_bar.dart';
import 'period_selection.dart';
import 'phone_style.dart';
import 'report_export.dart';
import 'revenue_hero_card.dart';
import 'team_tab.dart';
import 'team_table.dart';
import 'wide_layout.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({
    super.key,
    required this.isAdmin,
    required this.userId,
    required this.selection,
    required this.onSelectionChanged,
    required this.loading,
    required this.onRefresh,
    required this.data,
    this.monthlyReport,
    this.userName = '',
    this.wide = false,
  });

  final bool isAdmin;
  final String userId;

  final ReportPeriodSelection selection;
  final ValueChanged<ReportPeriodSelection> onSelectionChanged;

  final bool loading;

  /// Pull-to-refresh: the screen's existing reload.
  final Future<void> Function() onRefresh;

  /// Already scoped: roster and records of developer / test accounts are out
  /// of it (see [ReportData.scoped]).
  final ReportData data;

  /// The monthly report for the selected month; null in custom-range mode.
  /// Supplies the "Last 12 months" series and the month-by-month table.
  final MonthlyReport? monthlyReport;

  /// The signed-in user's display name, printed in the PDF footer.
  final String userName;

  /// The 768-and-up arrangement.
  final bool wide;

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// Non-admin page scroll, so a period change can return to the top.
  final ScrollController _selfScroll = ScrollController();

  TeamSort _sort = TeamSort.revenue;

  /// Wide Team table sort.
  TeamColumn _column = TeamColumn.revenue;
  bool _ascending = false;

  bool _exporting = false;

  PeriodSummary? _summary;
  ReportPeriodSelection? _summaryFor;
  ReportData? _summaryData;

  @override
  void dispose() {
    _tabs.dispose();
    _selfScroll.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final sel = widget.selection;
    final choice = await showPhoneExportSheet(context, allowExcel: sel.isMonth);
    if (choice == null || !mounted) return;
    setState(() => _exporting = true);
    await exportPhoneReport(
      context,
      choice: choice,
      data: widget.data,
      selection: sel,
      generatedBy: widget.userName,
      // A non-admin's report is their own; an admin's is the company's.
      employeeId: widget.isAdmin ? null : widget.userId,
    );
    if (mounted) setState(() => _exporting = false);
  }

  PeriodSummary _summaryNow() {
    final sel = widget.selection;
    final cached = _summary;
    if (cached != null &&
        identical(_summaryData, widget.data) &&
        _summaryFor == sel) {
      return cached;
    }
    final built = PeriodSummaryBuilder.build(
      range: sel.range,
      previous: sel.previousRange,
      sales: widget.data.sales,
      interactions: widget.data.interactions,
      clients: widget.data.clients,
      employeeNames: widget.data.employeeNames,
    );
    _summary = built;
    _summaryData = widget.data;
    _summaryFor = sel;
    return built;
  }

  void _openEmployee(EmployeePeriodRow row) {
    // Root navigator: a full-screen route over the bottom bar.
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeReportScreen(
          employeeId: row.employeeId,
          initialPeriod: widget.selection,
          data: widget.data,
          generatedBy: widget.userName,
        ),
      ),
    );
  }

  void _sortBy(TeamColumn c) {
    setState(() {
      if (c == _column) {
        _ascending = !_ascending;
      } else {
        _column = c;
        _ascending = c.ascendingFirst;
      }
    });
  }

  Widget _titleRow({required bool showExport}) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Reports',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.pageTitleMobile,
          ),
        ),
        if (showExport)
          SizedBox(
            width: 44,
            height: 44,
            child: _exporting
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Export',
                    onPressed: _export,
                    icon: const Icon(Icons.download_outlined),
                    color: AppColors.textPrimary,
                  ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.wide) return _content(16);
    return LayoutBuilder(
      builder: (context, constraints) =>
          _content(wideSidePadding(constraints.maxWidth)),
    );
  }

  /// [side] is the horizontal page padding (16 on a phone).
  Widget _content(double side) {
    final wide = widget.wide;

    if (widget.loading) {
      return Padding(
        padding: EdgeInsets.fromLTRB(side, wide ? 24 : 16, side, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide) const WideTitle() else _titleRow(showExport: false),
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );
    }

    return widget.isAdmin ? _adminBody(side) : _selfBody(side);
  }

  // ── Non-admin: their own report ────────────────────────────────────────

  Widget _selfBody(double side) {
    final wide = widget.wide;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        controller: _selfScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(side, wide ? 24 : 16, side, 32),
        children: [
          if (!wide) ...[
            _titleRow(showExport: true),
            const SizedBox(height: 16),
          ],
          EmployeeReportPanel(
            employeeId: widget.userId,
            initialPeriod: widget.selection,
            data: widget.data,
            wide: wide,
            onExport: wide ? _export : null,
            exporting: _exporting,
            onPeriodChanged: (p) {
              widget.onSelectionChanged(p);
              if (_selfScroll.hasClients) _selfScroll.jumpTo(0);
            },
          ),
        ],
      ),
    );
  }

  // ── Admin: Overview | Team ─────────────────────────────────────────────

  Widget _adminBody(double side) {
    final sel = widget.selection;
    final wide = widget.wide;

    return RefreshIndicator(
      // The refresh gesture starts in whichever tab list is on screen, which
      // sits inside the pager and the outer scroll view.
      notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
      onRefresh: widget.onRefresh,
      child: NestedScrollView(
        // A new period starts every tab again from the top.
        key: ValueKey(sel),
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: wide
                ? Padding(
                    padding: EdgeInsets.fromLTRB(side, 24, side, 16),
                    child: WideHeader(
                      leading: const WideTitle(),
                      selection: sel,
                      onSelectionChanged: widget.onSelectionChanged,
                      onExport: _export,
                      exporting: _exporting,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _titleRow(showExport: true),
                        const SizedBox(height: 4),
                        PeriodBar(
                          selection: sel,
                          onChanged: widget.onSelectionChanged,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedTabs(controller: _tabs, wide: wide, side: side),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _TabPage(
              storageKey: 'overview-${sel.label}',
              side: side,
              top: wide ? 24 : 16,
              child: _OverviewLazy(builder: _overview),
            ),
            _TabPage(
              storageKey: 'team-${sel.label}',
              side: side,
              top: wide ? 24 : 16,
              child: _OverviewLazy(builder: _team),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview() {
    final summary = _summaryNow();
    final sel = widget.selection;
    final wide = widget.wide;
    final hero = RevenueHeroCard(
      revenue: summary.revenue,
      daily: summary.daily,
      previousLabel: sel.previousLabel,
    );

    if (summary.isEmpty) {
      return Column(
        children: [
          hero,
          const SizedBox(height: 24),
          EmptyPeriodLine(sel.emptyText),
        ],
      );
    }

    final dealsD = kpiDelta(summary.deals);
    final clientsD = kpiDelta(summary.clients);
    final newD = kpiDelta(summary.newClients);
    final folD = kpiDelta(summary.interactions);

    final topRows = summary.employees.where((r) => r.revenuePaise > 0).toList();
    final report = widget.monthlyReport;
    final trailingMonths = sel.isMonth && report != null
        ? report.trailingRevenue
        : const <MonthTotal>[];

    final tiles = [
      KpiData(
        'Deals',
        '${summary.deals.current}',
        deltaText: dealsD?.text,
        deltaColor: dealsD?.color ?? AppColors.textMuted,
      ),
      KpiData(
        'Clients',
        '${summary.clients.current}',
        deltaText: clientsD?.text,
        deltaColor: clientsD?.color ?? AppColors.textMuted,
      ),
      KpiData(
        'New clients',
        '${summary.newClients.current}',
        deltaText: newD?.text,
        deltaColor: newD?.color ?? AppColors.textMuted,
      ),
      KpiData(
        'Follow-ups',
        '${summary.interactions.current}',
        deltaText: folD?.text,
        deltaColor: folD?.color ?? AppColors.textMuted,
      ),
    ];

    final top = topRows.isEmpty
        ? null
        : PhoneSection(
            title: 'Top performers',
            minTitleHeight: wide ? 32 : null,
            trailing: TextButton(
              onPressed: () => _tabs.animateTo(1),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('See all'),
            ),
            child: TopPerformers(rows: topRows),
          );
    final products = summary.revenueByProduct.any((r) => r.paise > 0)
        ? PhoneSection(
            title: 'Products',
            minTitleHeight: wide ? 32 : null,
            child: RankedBars(rows: summary.revenueByProduct),
          )
        : null;
    final frequency = summary.revenueByFrequency.any((r) => r.paise > 0)
        ? PhoneSection(
            title: 'Payment frequency',
            minTitleHeight: wide ? 32 : null,
            child: FrequencyBreakdown(rows: summary.revenueByFrequency),
          )
        : null;
    // Sales with no company recorded are all "Unspecified": nothing to rank.
    final company =
        summary.revenueByCompany.any(
          (r) => r.paise > 0 && r.label != kUnspecifiedLabel,
        )
        ? PhoneSection(
            title: 'Revenue by company',
            minTitleHeight: wide ? 32 : null,
            child: RankedBars(rows: summary.revenueByCompany),
          )
        : null;
    final followUps = PhoneSection(
      title: 'Follow-ups',
      minTitleHeight: wide ? 32 : null,
      child: FollowUpsCard(
        logged: summary.interactions.current.toInt(),
        overdue: summary.followUpsOverdue,
        upcoming: summary.followUpsUpcoming,
        byPriority: summary.interactionsByPriority,
      ),
    );
    final largest = summary.topDeals.isEmpty
        ? null
        : PhoneSection(
            title: 'Largest deals',
            minTitleHeight: wide ? 32 : null,
            child: LargestDeals(
              deals: summary.topDeals,
              employeeNames: widget.data.employeeNames,
            ),
          );
    final trailing = trailingMonths.isEmpty
        ? null
        : PhoneSection(
            title: 'Last 12 months',
            minTitleHeight: wide ? 32 : null,
            child: TrailingMonthsChart(
              months: trailingMonths,
              onMonthTap: (m) => widget.onSelectionChanged(sel.withMonth(m)),
            ),
          );

    if (!wide) {
      return Column(
        children: spaced([
          hero,
          KpiGrid(tiles: tiles),
          ?top,
          ?products,
          ?frequency,
          ?company,
          followUps,
          ?largest,
          ?trailing,
        ]),
      );
    }

    final history = trailingMonths.isEmpty
        ? null
        : PhoneSection(
            title: 'Month by month',
            minTitleHeight: wide ? 32 : null,
            child: PhoneCard(
              child: MonthlyHistoryTable(
                months: trailingMonths,
                selected: sel.month,
                onMonthTap: (m) => widget.onSelectionChanged(sel.withMonth(m)),
              ),
            ),
          );

    return Column(
      children: spaced([
        WideHeroKpis(
          revenue: summary.revenue,
          daily: summary.daily,
          previousLabel: sel.previousLabel,
          tiles: tiles,
        ),
        ...pairedRows([
          ?top,
          ?products,
          ?frequency,
          followUps,
          ?company,
          ?largest,
        ]),
        ?trailing,
        ?history,
      ]),
    );
  }

  Widget _team() {
    final summary = _summaryNow();
    if (summary.employees.isEmpty) {
      return EmptyPeriodLine(widget.selection.emptyText);
    }
    if (widget.wide) {
      return TeamTable(
        rows: summary.employees,
        column: _column,
        ascending: _ascending,
        onSort: _sortBy,
        onEmployeeTap: _openEmployee,
      );
    }
    return TeamTab(
      rows: summary.employees,
      sort: _sort,
      onSortChanged: (s) => setState(() => _sort = s),
      onEmployeeTap: _openEmployee,
    );
  }
}

/// Defers building a tab's content to its own build, so the Team tab does
/// no work until it is shown.
class _OverviewLazy extends StatelessWidget {
  const _OverviewLazy({required this.builder});

  final Widget Function() builder;

  @override
  Widget build(BuildContext context) => builder();
}

/// One tab's own scroll view: its position is its own (and starts at the
/// top), and it sits below the pinned tab bar.
class _TabPage extends StatelessWidget {
  const _TabPage({
    required this.storageKey,
    required this.child,
    required this.side,
    required this.top,
  });

  final String storageKey;
  final Widget child;
  final double side;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => CustomScrollView(
        key: PageStorageKey<String>(storageKey),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, top, side, 32),
            sliver: SliverToBoxAdapter(child: child),
          ),
        ],
      ),
    );
  }
}

/// The pinned Overview | Team bar. Full width on a phone; left-aligned
/// within the page column when [wide].
class _PinnedTabs extends SliverPersistentHeaderDelegate {
  const _PinnedTabs({
    required this.controller,
    required this.wide,
    required this.side,
  });

  final TabController controller;
  final bool wide;
  final double side;

  static const double _height = 48;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final bar = Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: wide,
        tabAlignment: wide ? TabAlignment.start : null,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: AppColors.primaryBlue,
        indicatorWeight: 2,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: PhoneText.rowTitle,
        unselectedLabelStyle: PhoneText.rowTitle.copyWith(
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Team'),
        ],
      ),
    );
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: wide ? EdgeInsets.symmetric(horizontal: side) : null,
      child: bar,
    );
  }

  @override
  bool shouldRebuild(_PinnedTabs oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.wide != wide ||
      oldDelegate.side != side;
}
