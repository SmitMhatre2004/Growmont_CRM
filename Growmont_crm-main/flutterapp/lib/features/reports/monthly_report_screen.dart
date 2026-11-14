// lib/features/reports/monthly_report_screen.dart
//
// The Monthly Report screen.
//
// Scope is enforced HERE, by passing an owner filter on every read for a
// non-admin — the same thing sales_screen, interactions_screen and
// clients_list_screen each do.
//
// Do not be tempted to drop that filter on the grounds that SyncEngine
// only pulls a non-admin's own rows. The local SQLite database survives a
// sign-out (SyncEngine.stop cancels listeners and nothing clears the
// tables), so on a shared machine it can still hold everything a previous
// admin synced. An unfiltered read would hand that to the next user.
//
// The admin-only sections are gated on isAdmin on top of that.
//
// Loading strategy: the four collections are read once per month change
// and the whole report is rebuilt from them in memory. Reads are local
// (SQLite, no network), and the aggregation is a single pass per
// collection — see MonthlyReportBuilder.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/excel/excel_io.dart';
import '../../core/io/file_saver.dart';
import '../../core/providers.dart';
import '../../core/reports/monthly_report.dart';
import '../../core/reports/monthly_report_builder.dart';
import '../../core/reports/monthly_report_excel.dart';
import '../../core/reports/monthly_report_pdf.dart';
import '../../core/theme/app_theme.dart';
import '../../models/client.dart';
import '../../models/employee.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/monthly_revenue_chart.dart' show compactRupees;
import '../auth/auth_provider.dart';
import 'widgets/month_picker_bar.dart';
import 'widgets/report_cards.dart';
import 'widgets/report_export_picker.dart';
import 'widgets/report_tables.dart';
import 'widgets/report_trend_chart.dart';

class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  /// Forward travel stops here. Captured once per build cycle rather than
  /// read from the clock at every comparison, so the cap cannot shift
  /// mid-interaction if the screen is open across midnight on the 1st.
  final ReportMonth _latest = ReportMonth.current();

  late ReportMonth _period = _latest;

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  List<Sale> _sales = const [];
  List<Interaction> _interactions = const [];
  List<Client> _clients = const [];
  Map<String, String> _employeeNames = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads every collection the report needs. All four reads are local, so
  /// this is cheap enough to run on entry and on an explicit refresh — but
  /// NOT on a month change, which only re-aggregates what is already here.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final isAdmin = ref.read(authProvider).user?.isAdmin == true;

      // Non-admins are filtered to their own records explicitly, exactly
      // as sales_screen.dart, interactions_screen.dart and
      // clients_list_screen.dart all do.
      //
      // It is NOT enough to rely on the sync layer having pulled only
      // this user's rows. The local SQLite database is not cleared when
      // the signed-in user changes (SyncEngine.stop only cancels its
      // listeners), so after an admin has used the machine it still holds
      // the whole company's documents — and an unfiltered read would show
      // them to the next person who signs in.
      final selfId = isAdmin ? null : ref.read(authProvider).user?.id;

      // Started together, awaited individually: Future.wait over mixed
      // element types would collapse them to Object and force a cast back.
      final salesFuture = api.getSales(salesRepId: selfId);
      final interactionsFuture = api.getInteractions(employeeId: selfId);
      final clientsFuture = api.getClients(employeeId: selfId);
      // Only the company report names other people, so only it needs the
      // roster. An employee's own name comes from auth.
      final rosterFuture = isAdmin
          ? api.getEmployeesDropdown()
          : Future.value(const <EmployeeDropdown>[]);

      final sales = await salesFuture;
      final interactions = await interactionsFuture;
      final clients = await clientsFuture;
      final roster = await rosterFuture;

      if (!mounted) return;
      setState(() {
        _sales = sales;
        _interactions = interactions;
        _clients = clients;
        _employeeNames = {for (final e in roster) e.id: e.name};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  MonthlyReport _buildReport() {
    final user = ref.read(authProvider).user;
    final isAdmin = user?.isAdmin == true;

    return MonthlyReportBuilder.build(
      period: _period,
      scope: isAdmin ? ReportScope.company : ReportScope.individual,
      scopeLabel: isAdmin ? 'Whole company' : (user?.name ?? 'My activity'),
      sales: _sales,
      interactions: _interactions,
      clients: _clients,
      employeeNames: _employeeNames,
    );
  }

  /// Asks for a format, then writes it. Both outputs render from the same
  /// [MonthlyReport] the screen is showing, so a PDF and a workbook saved
  /// from one tap always carry identical figures.
  Future<void> _export(MonthlyReport report) async {
    final choice = await pickReportExportFormat(context);
    if (choice == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      final shareText =
          'Growmont CRM report — ${formatReportMonth(report.period)}';
      final saved = <String>[];

      // PDF first when both are requested: it is the one a person reads,
      // so it is the one worth getting out of the way while they are still
      // paying attention to the save dialogs.
      if (choice == ReportExportFormat.pdf ||
          choice == ReportExportFormat.both) {
        final fonts = await ReportPdfFonts.load();
        final path = await FileSaver.save(
          filename: MonthlyReportPdf.filename(report),
          bytes: await MonthlyReportPdf.build(report, fonts),
          extensions: const ['pdf'],
          shareText: shareText,
        );
        if (path != null) saved.add(path);
      }

      if (choice == ReportExportFormat.excel ||
          choice == ReportExportFormat.both) {
        final path = await ExcelIO.exportMultiSheetWorkbook(
          filename: MonthlyReportExcel.filename(report),
          sheets: MonthlyReportExcel.sheets(report),
          shareText: shareText,
        );
        if (path != null) saved.add(path);
      }

      if (!mounted) return;
      // No paths on mobile (the share sheet handles it) or if every save
      // dialog was cancelled — neither is worth a toast.
      if (saved.length == 1) {
        _toast('Report saved to ${saved.first}');
      } else if (saved.length > 1) {
        _toast('Saved ${saved.length} files:\n${saved.join('\n')}');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('Could not export the report: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = AppLayout.isMobile(context);
    final gutter = isMobile ? AppSpacing.lg : AppSpacing.xxl;

    if (_error != null) {
      return ErrorState(
        title: 'Could not build the report',
        message: _error!,
        onRetry: _load,
      );
    }

    final report = _loading ? null : _buildReport();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titleRow(isMobile, gutter, report),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    0,
                    gutter,
                    AppSpacing.xxl,
                  ),
                  children: _sections(report!, isMobile),
                ),
        ),
      ],
    );
  }

  Widget _titleRow(bool isMobile, double gutter, MonthlyReport? report) {
    final isShort = MediaQuery.sizeOf(context).height < 450;

    final title = Text(
      'Monthly Report',
      style: isShort
          ? AppTypography.pageTitleMobile.copyWith(fontSize: 18)
          : (isMobile
                ? AppTypography.pageTitleMobile
                : AppTypography.pageTitle),
      overflow: TextOverflow.ellipsis,
    );

    final picker = MonthPickerBar(
      month: _period,
      latest: _latest,
      onChanged: (month) => setState(() => _period = month),
    );

    final exportButton = SizedBox(
      height: AppSizing.controlMd,
      child: OutlinedButton.icon(
        onPressed: report == null || _exporting ? null : () => _export(report),
        icon: _exporting
            ? const SizedBox(
                width: AppSizing.iconSm,
                height: AppSizing.iconSm,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_outlined, size: AppSizing.iconMd),
        label: Text(isMobile ? 'Export' : 'Export report'),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        isShort ? 4 : 16,
        gutter,
        isShort ? 4 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: AppSpacing.md),
          // Wrap rather than Row: on a phone the picker and the export
          // button stack instead of squeezing the month name to an
          // ellipsis.
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [picker, exportButton],
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(MonthlyReport report, bool isMobile) {
    final previousLabel = formatReportMonth(report.period.previous, short: true);

    return [
      _scopeLine(report),
      const SizedBox(height: AppSpacing.md),

      if (report.isEmpty) ...[
        _emptyMonth(report),
        const SizedBox(height: AppSpacing.md),
      ] else ...[
        _kpiGrid(report, previousLabel, isMobile),
        const SizedBox(height: AppSpacing.md),

        ReportCard(
          title: 'Revenue trend',
          subtitle:
              'Last ${report.trailingRevenue.length} months by sale date. '
              'Tap a bar to open that month.',
          child: ReportTrendChart(
            series: report.trailingRevenue,
            selected: report.period,
            onMonthTap: (month) {
              if (month.compareTo(_latest) > 0) return;
              setState(() => _period = month);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        _breakdownPair(report, isMobile),
        const SizedBox(height: AppSpacing.md),

        ReportCard(
          title: 'Payment frequency',
          subtitle: 'How this month\'s revenue is scheduled to recur',
          child: BreakdownTable(rows: report.revenueByFrequency),
        ),
        const SizedBox(height: AppSpacing.md),

        ReportCard(
          title: 'Largest deals',
          subtitle: 'The biggest sales recorded this month',
          child: TopDealsTable(deals: report.topDeals),
        ),
        const SizedBox(height: AppSpacing.md),

        _activityCard(report),
        const SizedBox(height: AppSpacing.md),

        if (report.scope == ReportScope.company) ...[
          ReportCard(
            title: 'Team performance',
            subtitle:
                'By the employee recorded on each sale, so transfers do not '
                'move past credit',
            child: TeamPerformanceTable(
              rows: report.team,
              previousLabel: previousLabel,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        _comparisonCard(report, previousLabel),
        const SizedBox(height: AppSpacing.md),
      ],

      if (report.quality.hasIssues) ...[
        _qualityNotice(report),
        const SizedBox(height: AppSpacing.md),
      ],

      _footnote(report),
    ];
  }

  /// Who and what the figures cover, plus when they were computed. Reads
  /// are local, so "now" is really "as of the last sync" — saying so is
  /// the difference between a stale report and a wrong one.
  Widget _scopeLine(MonthlyReport report) {
    final generated = DateFormat('d MMM yyyy, h:mm a').format(
      report.generatedAt,
    );
    return Text(
      '${report.scopeLabel} · ${formatReportMonth(report.period)} '
      '(1–${report.period.dayCount} ${DateFormat('MMM').format(report.period.start)}) '
      '· computed $generated from synced data',
      style: AppTypography.caption,
    );
  }

  Widget _kpiGrid(MonthlyReport report, String previousLabel, bool isMobile) {
    final cards = <Widget>[
      ReportKpiCard(
        label: 'REVENUE',
        value: AppFormatters.formatAmount(
          report.revenueRupees.toStringAsFixed(2),
        ),
        delta: report.revenue,
        previousLabel: previousLabel,
        valueColor: AppColors.money,
        note: 'By sale date',
      ),
      ReportKpiCard(
        label: 'DEALS CLOSED',
        value: '${report.deals.current}',
        delta: report.deals,
        previousLabel: previousLabel,
        note: 'Every recorded sale is a closed sale',
      ),
      ReportKpiCard(
        label: 'AVG DEAL VALUE',
        value: AppFormatters.formatAmount(
          (report.avgDealPaise / 100).toStringAsFixed(2),
        ),
        delta: report.avgDeal,
        previousLabel: previousLabel,
        note: 'Revenue ÷ deals',
      ),
      ReportKpiCard(
        label: 'ACTIVE CLIENTS',
        value: '${report.activeClients.current}',
        delta: report.activeClients,
        previousLabel: previousLabel,
        note: 'Distinct clients who bought',
      ),
      ReportKpiCard(
        label: 'NEW CLIENTS',
        value: '${report.newClients.current}',
        delta: report.newClients,
        previousLabel: previousLabel,
        note: report.quality.clientsWithoutCreatedAt > 0
            ? 'By date added — ${report.quality.clientsWithoutCreatedAt} '
                  'client(s) have no date, so this is a minimum'
            : 'By date added',
      ),
      ReportKpiCard(
        label: 'INTERACTIONS',
        value: '${report.interactions.current}',
        delta: report.interactions,
        previousLabel: previousLabel,
        note: 'Client conversations logged',
      ),
    ];

    // A fixed 3-up grid would leave a 420pt-wide window with unreadable
    // cards, so the column count is derived from the width instead.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 3
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        const gap = AppSpacing.md;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

  Widget _breakdownPair(MonthlyReport report, bool isMobile) {
    final product = ReportCard(
      title: 'Revenue by product',
      subtitle: 'Which lines carried the month',
      child: BreakdownTable(rows: report.revenueByProduct, maxRows: 7),
    );
    final company = ReportCard(
      title: 'Revenue by company',
      subtitle: 'Where the business was placed',
      child: BreakdownTable(rows: report.revenueByCompany, maxRows: 7),
    );

    if (isMobile || MediaQuery.sizeOf(context).width < 900) {
      return Column(
        children: [
          product,
          const SizedBox(height: AppSpacing.md),
          company,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: product),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: company),
      ],
    );
  }

  Widget _activityCard(MonthlyReport report) {
    return ReportCard(
      title: 'Client activity and follow-up load',
      subtitle: 'Interactions by priority, and follow-ups falling in this month',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BreakdownTable(
            rows: report.interactionsByPriority,
            showAmount: false,
            countLabel: 'Logs',
            emptyMessage: 'No interactions logged this month',
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Follow-ups scheduled',
                  '${report.followUpsScheduled}',
                ),
              ),
              Expanded(
                child: _miniStat(
                  'Date already passed',
                  '${report.followUpsPastDue}',
                  valueColor: report.followUpsPastDue > 0
                      ? AppColors.warning
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const ReportNotice(
            message:
                'An interaction has no "done" field in this CRM, so these '
                'count follow-ups whose date falls in the month — not '
                'whether anyone acted on them.',
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.metricLabel),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: AppTypography.metricMedium.copyWith(color: valueColor),
        ),
      ],
    );
  }

  Widget _comparisonCard(MonthlyReport report, String previousLabel) {
    final rows = <({String label, MetricDelta delta, bool money})>[
      (label: 'Revenue', delta: report.revenue, money: true),
      (label: 'Deals closed', delta: report.deals, money: false),
      (label: 'Average deal value', delta: report.avgDeal, money: true),
      (label: 'Active clients', delta: report.activeClients, money: false),
      (label: 'New clients', delta: report.newClients, money: false),
      (label: 'Interactions', delta: report.interactions, money: false),
    ];

    String format(num value, bool money) => money
        ? compactRupees(value / 100)
        : '${value.round()}';

    return ReportCard(
      title: 'Month-over-month',
      subtitle:
          '${formatReportMonth(report.period, short: true)} against '
          '$previousLabel',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Text('Metric', style: AppTypography.tableHeader),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  formatReportMonth(report.period, short: true),
                  style: AppTypography.tableHeader,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  previousLabel,
                  style: AppTypography.tableHeader,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 4,
                child: Text('Change', style: AppTypography.tableHeader),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    rows[i].label,
                    style: AppTypography.tableCell,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    format(rows[i].delta.current, rows[i].money),
                    style: AppTypography.tableCellNumeric,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    format(rows[i].delta.previous, rows[i].money),
                    style: AppTypography.tableCellNumeric.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DeltaChip(
                      delta: rows[i].delta,
                      previousLabel: previousLabel,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyMonth(MonthlyReport report) {
    final isFirstMonth = _sales.isEmpty && _interactions.isEmpty;

    return ReportCard(
      title: 'Nothing recorded in ${formatReportMonth(report.period)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: AppSizing.iconEmptyState,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            isFirstMonth
                ? 'There are no sales or interactions in this device\'s data '
                      'yet. If you have just signed in, give the first sync a '
                      'moment and refresh.'
                : 'No sales, interactions or new clients fall in this month. '
                      'Pick another month above, or tap a bar on a month with '
                      'activity.',
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: AppSizing.iconSm),
            label: const Text('Reload data'),
          ),
        ],
      ),
    );
  }

  Widget _qualityNotice(MonthlyReport report) {
    final quality = report.quality;
    final parts = <String>[
      if (quality.salesWithoutDate > 0)
        '${quality.salesWithoutDate} sale(s) have no usable date',
      if (quality.interactionsWithoutDate > 0)
        '${quality.interactionsWithoutDate} interaction(s) have no usable date',
      if (quality.clientsWithoutCreatedAt > 0)
        '${quality.clientsWithoutCreatedAt} client(s) have no date added',
    ];

    return ReportNotice(
      tone: ReportNoticeTone.warning,
      icon: Icons.warning_amber_outlined,
      title: 'Some records could not be placed in a month',
      message:
          '${parts.join('; ')}. These are left out of every month rather than '
          'guessed at, so the totals above are a minimum. Fixing the dates on '
          'those records will correct the figures.',
    );
  }

  /// States plainly what this CRM does not track, so a zero is never
  /// mistaken for an absence and an absence is never mistaken for a zero.
  Widget _footnote(MonthlyReport report) {
    return ReportCard(
      title: 'How to read this report',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ReportNotice(
            message:
                'Figures are recalculated from current records every time '
                'this screen opens. Editing or deleting an old sale changes '
                'that month\'s numbers — no month-end snapshot is stored.',
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Not tracked in this CRM', style: AppTypography.captionSemibold),
          const SizedBox(height: AppSpacing.xs),
          for (final item in kUntrackedMetrics)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '· ',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
