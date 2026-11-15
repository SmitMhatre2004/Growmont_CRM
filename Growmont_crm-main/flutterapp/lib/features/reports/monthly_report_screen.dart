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
import '../auth/auth_provider.dart';
import 'widgets/month_picker_bar.dart';
import 'widgets/ranked_bar_chart.dart';
import 'widgets/report_cards.dart';
import 'widgets/report_export_picker.dart';
import 'widgets/report_tables.dart';
import 'widgets/segmented_bar.dart';
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

  /// Set when an admin opens one person's row in the team table. Null is
  /// the company-wide report.
  String? _focusEmployeeId;

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

    // An admin who has opened one person's row gets that person's report,
    // built from the same already-loaded records — no reload, because the
    // admin's copy already holds the whole company.
    final focusId = isAdmin ? _focusEmployeeId : null;
    if (focusId != null) {
      return MonthlyReportBuilder.build(
        period: _period,
        scope: ReportScope.individual,
        scopeLabel: _employeeNames[focusId] ?? 'Employee',
        sales: _sales
            .where((s) => (s.salesRepId ?? s.salesRep) == focusId)
            .toList(),
        interactions: _interactions
            .where((i) => (i.employeeId ?? i.employee) == focusId)
            .toList(),
        clients: _clients.where((c) => c.employeeId == focusId).toList(),
        employeeNames: _employeeNames,
      );
    }

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Matches the Dashboard's header: title and a one-line summary
          // on the left, controls on the right, collapsing to stacked
          // rows below the same breakpoint it uses.
          final inlineControls = constraints.maxWidth >= 720;

          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The way back out of one person's report. Without it the
              // only escape is leaving the page and returning.
              if (_focusEmployeeId != null) ...[
                _BackToCompany(
                  onPressed: () =>
                      setState(() => _focusEmployeeId = null),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              title,
              if (report != null && !isShort) ...[
                const SizedBox(height: AppSpacing.xxs),
                _scopeLine(report),
              ],
            ],
          );

          if (inlineControls) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: AppSpacing.md),
                picker,
                const SizedBox(width: AppSpacing.sm),
                exportButton,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
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
          );
        },
      ),
    );
  }

  /// The page body.
  ///
  /// Laid out the way the Dashboard is: full-width rows for the things
  /// that need the room, then a two-column split with a wide main column
  /// and a narrower rail, collapsing to one column on a narrow window at
  /// the same breakpoint the Dashboard uses.
  List<Widget> _sections(MonthlyReport report, bool isMobile) {
    final previousLabel = formatReportMonth(report.period.previous, short: true);

    if (report.isEmpty) {
      return [_emptyMonth(report)];
    }

    return [
      _kpiGrid(report, previousLabel, isMobile),
      const SizedBox(height: AppSpacing.lg),

      // The trend keeps the full width: a daily line over three months is
      // ninety points, and needs every pixel of horizontal room it can get.
      ReportCard(
        title: 'Revenue trend',
        subtitle: 'Booked value per day',
        child: ReportTrendChart(series: report.dailyRevenue),
      ),
      const SizedBox(height: AppSpacing.lg),

      LayoutBuilder(
        builder: (context, constraints) {
          final cards = _cards(report);

          if (constraints.maxWidth < 850) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  cards[i].card,
                ],
              ],
            );
          }

          // Two equal columns, filled by whichever is currently shorter.
          //
          // A fixed "wide column plus narrow rail" split was tried first
          // and looked wrong: the rail ran out of cards while the main
          // column kept going, leaving a tall band of empty page on the
          // right. Card heights vary with the data — a month with four
          // products is half the height of one with twelve, and an
          // employee's report has no team table at all — so no hand-picked
          // assignment stays balanced. Packing by estimated height does.
          final left = <Widget>[];
          final right = <Widget>[];
          var leftHeight = 0.0;
          var rightHeight = 0.0;

          for (final entry in cards) {
            if (leftHeight <= rightHeight) {
              if (left.isNotEmpty) left.add(const SizedBox(height: AppSpacing.md));
              left.add(entry.card);
              leftHeight += entry.weight;
            } else {
              if (right.isNotEmpty) right.add(const SizedBox(height: AppSpacing.md));
              right.add(entry.card);
              rightHeight += entry.weight;
            }
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: left,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: right,
                ),
              ),
            ],
          );
        },
      ),
      if (report.scope == ReportScope.company) ...[
        const SizedBox(height: AppSpacing.lg),
        // Full width rather than in a column: seven columns of figures
        // need the room, and it is the one card that reads worse at half
        // the page.
        ReportCard(
          title: 'Team performance',
          subtitle: 'Revenue stays with whoever recorded the sale',
          child: TeamPerformanceTable(
            rows: report.team,
            previousLabel: formatReportMonth(report.period.previous, short: true),
            onEmployeeTap: (row) =>
                setState(() => _focusEmployeeId = row.employeeId),
          ),
        ),
      ],
    ];
  }

  /// The cards that get packed into columns, each with a rough rendered
  /// height so the packer can balance them.
  ///
  /// The weights only have to be right relative to each other — they
  /// decide which column a card lands in, never how tall it is drawn.
  List<({Widget card, double weight})> _cards(MonthlyReport report) {
    const cardChrome = 96.0;

    double rows(int n, double per) => cardChrome + n * per;

    return [
      (
        card: ReportCard(
          title: 'Revenue by product',
          subtitle: 'Largest first',
          child: RankedBarChart(rows: report.revenueByProduct),
        ),
        weight: rows(
          report.revenueByProduct.length.clamp(0, 8),
          46,
        ),
      ),
      (
        card: ReportCard(
          title: 'Payment frequency',
          subtitle: 'How the revenue is scheduled to recur',
          child: SegmentedBarList(rows: report.revenueByFrequency),
        ),
        weight: rows(
          report.revenueByFrequency.where((r) => r.paise > 0).length,
          30,
        ) + 24,
      ),
      (
        card: ReportCard(
          title: 'Revenue by company',
          subtitle: 'Largest first',
          child: RankedBarChart(rows: report.revenueByCompany),
        ),
        weight: rows(
          report.revenueByCompany.length.clamp(0, 8),
          46,
        ),
      ),
      (card: _activityCard(report), weight: 210),
      (
        card: ReportCard(
          title: 'Largest deals',
          subtitle: 'The biggest sales this month',
          child: TopDealsTable(deals: report.topDeals),
        ),
        weight: rows(report.topDeals.length, 48),
      ),
    ];
  }

  /// Who and what the figures cover, plus when they were computed. Reads
  /// are local, so "now" is really "as of the last sync" — saying so is
  /// the difference between a stale report and a wrong one.
  Widget _scopeLine(MonthlyReport report) {
    final generated = DateFormat('d MMM yyyy, h:mm a').format(
      report.generatedAt,
    );
    // Short enough to read at a glance. The day range and the wording
    // about synced data were accurate but read as small print under the
    // page title; the generation time still earns its place, because a
    // local-first read is only as fresh as the last sync.
    return Text(
      '${report.scopeLabel} · Updated $generated',
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
      ),
      ReportKpiCard(
        label: 'DEALS CLOSED',
        value: '${report.deals.current}',
        delta: report.deals,
        previousLabel: previousLabel,
      ),
      ReportKpiCard(
        label: 'AVG DEAL VALUE',
        value: AppFormatters.formatAmount(
          (report.avgDealPaise / 100).toStringAsFixed(2),
        ),
        delta: report.avgDeal,
        previousLabel: previousLabel,
      ),
      ReportKpiCard(
        label: 'ACTIVE CLIENTS',
        value: '${report.activeClients.current}',
        delta: report.activeClients,
        previousLabel: previousLabel,
      ),
      ReportKpiCard(
        label: 'NEW CLIENTS',
        value: '${report.newClients.current}',
        delta: report.newClients,
        previousLabel: previousLabel,
      ),
      ReportKpiCard(
        label: 'INTERACTIONS',
        value: '${report.interactions.current}',
        delta: report.interactions,
        previousLabel: previousLabel,
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

  Widget _activityCard(MonthlyReport report) {
    return ReportCard(
      title: 'Client activity and follow-up load',
      subtitle: 'Follow-ups are counted by their date - the CRM does not '
          'record whether they were done',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Three counts on an ordered scale. A three-bar chart would be
          // the one-bar-chart failure with two extra bars — the numbers
          // are the content, so they are set as figures, with the ordinal
          // ramp carrying High -> Low underneath them.
          MiniStatRow(
            rows: report.interactionsByPriority,
            emptyMessage: 'No interactions logged this month',
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  'Scheduled',
                  '${report.followUpsScheduled}',
                ),
              ),
              Expanded(
                child: _miniStat(
                  'Date passed',
                  '${report.followUpsPastDue}',
                  valueColor: report.followUpsPastDue > 0
                      ? AppColors.warning
                      : null,
                ),
              ),
            ],
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
}

/// Breadcrumb out of a single employee's report, back to the company one.
class _BackToCompany extends StatelessWidget {
  const _BackToCompany({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.arrow_back,
              size: AppSizing.iconSm,
              color: AppColors.link,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'All employees',
              style: AppTypography.caption.copyWith(
                color: AppColors.link,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
