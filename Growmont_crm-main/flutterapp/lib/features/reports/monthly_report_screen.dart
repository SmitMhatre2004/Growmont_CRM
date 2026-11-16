// lib/features/reports/monthly_report_screen.dart
//
// The Reports screen, on every width: [ReportsView] draws it, phone-first
// with a wide arrangement from 768 up. This widget owns loading, scoping and
// the selected period.
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
// Loading strategy: the four collections are read once on entry (and on an
// explicit refresh), and every report is rebuilt from them in memory. Reads
// are local (SQLite, no network), and the aggregation is a single pass per
// collection — see MonthlyReportBuilder and PeriodSummaryBuilder.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/reports/monthly_report.dart';
import '../../core/reports/monthly_report_builder.dart';
import '../../core/theme/app_theme.dart';
import '../../models/client.dart';
import '../../models/employee.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../shared/widgets/error_state.dart';
import '../auth/auth_provider.dart';
import 'phone/employee_report_view.dart' show ReportData;
import 'phone/period_selection.dart';
import 'phone/reports_view.dart';

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

  /// A month (default) or a custom range.
  late ReportPeriodSelection _selection = ReportPeriodSelection.month(
    _latest,
    latestMonth: _latest,
  );

  bool _loading = true;
  String? _error;

  List<Sale> _sales = const [];
  List<Interaction> _interactions = const [];
  List<Client> _clients = const [];
  Map<String, String> _employeeNames = const {};

  /// Developer / test accounts, left out of the reports.
  Set<String> _excludedIds = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads every collection the report needs. All four reads are local, so
  /// this is cheap enough to run on entry and on an explicit refresh — but
  /// NOT on a period change, which only re-aggregates what is already here.
  ///
  /// [showSpinner] is false for pull-to-refresh, whose own indicator is
  /// already on screen; the page keeps its scroll position and tab.
  Future<void> _load({bool showSpinner = true}) async {
    setState(() {
      _loading = showSpinner;
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
        _excludedIds = {
          for (final e in roster)
            if (e.excludeFromHeadcount) e.id,
        };
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

  // ── Build ──────────────────────────────────────────────────────────────

  /// The loaded lists. An admin's view leaves out developer / test accounts
  /// entirely (see [ReportData.scoped]); a non-admin, who may themselves be
  /// one, always sees their own data.
  ReportData? _dataCache;
  bool? _dataAdmin;

  ReportData _data(bool isAdmin, String userId, String userName) {
    final cached = _dataCache;
    if (cached != null &&
        _dataAdmin == isAdmin &&
        identical(_dataSales, _sales) &&
        identical(_dataInteractions, _interactions) &&
        identical(_dataClients, _clients) &&
        identical(_dataNames, _employeeNames)) {
      return cached;
    }
    _dataSales = _sales;
    _dataInteractions = _interactions;
    _dataClients = _clients;
    _dataNames = _employeeNames;
    _dataAdmin = isAdmin;
    return _dataCache = ReportData.scoped(
      sales: _sales,
      interactions: _interactions,
      clients: _clients,
      employeeNames: isAdmin ? _employeeNames : {userId: userName},
      excludedIds: isAdmin ? _excludedIds : const {},
    );
  }

  List<Sale>? _dataSales;
  List<Interaction>? _dataInteractions;
  List<Client>? _dataClients;
  Map<String, String>? _dataNames;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorState(
        title: 'Could not build the report',
        message: _error!,
        onRetry: _load,
      );
    }

    final user = ref.read(authProvider).user;
    final isAdmin = user?.isAdmin == true;
    final userId = user?.id ?? '';
    final userName = user?.name ?? 'My activity';
    final data = _data(isAdmin, userId, userName);

    // The twelve-month chart's series (and the month-by-month table), from
    // the same scoped lists as the cards. Custom ranges have no month.
    final MonthlyReport? report = _loading || !_selection.isMonth
        ? null
        : MonthlyReportBuilder.build(
            period: _selection.month,
            scope: isAdmin ? ReportScope.company : ReportScope.individual,
            scopeLabel: isAdmin ? 'Whole company' : userName,
            sales: data.sales,
            interactions: data.interactions,
            clients: data.clients,
            employeeNames: data.employeeNames,
          );

    return ReportsView(
      isAdmin: isAdmin,
      userId: userId,
      userName: userName,
      selection: _selection,
      onSelectionChanged: (s) => setState(() => _selection = s),
      loading: _loading,
      onRefresh: () => _load(showSpinner: false),
      data: data,
      monthlyReport: report,
      wide: !AppLayout.isMobile(context),
    );
  }
}
