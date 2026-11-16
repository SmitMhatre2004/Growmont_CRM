// test/monthly_report_screen_test.dart
//
// Widget tests for the Monthly Report screen: that it renders its loading,
// empty, error and populated states; that the period selector works; that
// an employee never sees the team section; and that it survives a small
// phone viewport without a RenderFlex overflow (the failure mode this
// repo's other layout tests exist to catch).
//
// The data layer is faked through `implements FirestoreService`, the same
// way empty_state_overflow_test.dart and landscape_and_overflow_test.dart
// do it — the real service's constructor resolves FirebaseFirestore.instance
// and cannot run without Firebase being initialized.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/firestore_service.dart';
import 'package:growmont_crm/core/providers.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/features/reports/monthly_report_screen.dart';
import 'package:growmont_crm/features/reports/phone/employee_report_view.dart';
import 'package:growmont_crm/features/reports/phone/period_bar.dart';
import 'package:growmont_crm/features/reports/phone/period_selection.dart';
import 'package:growmont_crm/features/reports/phone/team_tab.dart';
import 'package:growmont_crm/features/reports/phone/team_table.dart';
import 'package:growmont_crm/features/reports/phone/wide_layout.dart';
import 'package:growmont_crm/core/reports/monthly_report.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/employee.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';
import 'package:growmont_crm/models/user.dart';

// ── Fakes ───────────────────────────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.role);
  final UserRole role;

  @override
  AuthState build() => AuthState(
    user: AppUser(
      id: 'emp1',
      email: 'asha@growmont.com',
      name: 'Asha Rao',
      role: role,
    ),
  );
}

class _FakeService implements FirestoreService {
  _FakeService({
    this.sales = const [],
    this.interactions = const [],
    this.clients = const [],
    this.roster = const [],
    this.throwOnLoad = false,
  });

  final List<Sale> sales;
  final List<Interaction> interactions;
  final List<Client> clients;
  final List<EmployeeDropdown> roster;
  final bool throwOnLoad;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// Filters recorded exactly as the screen passed them, so a test can
  /// assert the screen asked for a scoped read rather than relying on the
  /// data happening to be small.
  String? lastSalesRepId;
  String? lastInteractionEmployeeId;
  String? lastClientEmployeeId;
  bool salesCalled = false;
  int salesCalls = 0;

  /// Honours the owner filter the way CrmRepository does. The local
  /// database is NOT pre-scoped — it survives a sign-out and can hold a
  /// previous admin's rows — so an unfiltered read here returns
  /// everything, which is precisely the leak being guarded against.
  @override
  Future<List<Sale>> getSales({String? salesRepId, String? clientId}) async {
    if (throwOnLoad) throw Exception('local database unavailable');
    salesCalled = true;
    salesCalls++;
    lastSalesRepId = salesRepId;
    if (salesRepId == null || salesRepId.isEmpty) return sales;
    return sales
        .where((s) => s.salesRepId == salesRepId || s.salesRep == salesRepId)
        .toList();
  }

  @override
  Future<List<Interaction>> getInteractions({
    String? employeeId,
    String? clientId,
  }) async {
    lastInteractionEmployeeId = employeeId;
    if (employeeId == null || employeeId.isEmpty) return interactions;
    return interactions
        .where((i) => (i.employeeId ?? i.employee) == employeeId)
        .toList();
  }

  @override
  Future<List<Client>> getClients({String? employeeId}) async {
    lastClientEmployeeId = employeeId;
    if (employeeId == null || employeeId.isEmpty) return clients;
    return clients.where((c) => c.employeeId == employeeId).toList();
  }

  @override
  Future<List<EmployeeDropdown>> getEmployeesDropdown() async => roster;
}

// ── Fixtures ────────────────────────────────────────────────────────────

/// Dated inside the month the screen opens on, so the tests do not depend
/// on the day the suite runs.
String _thisMonth(int day) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, day).toIso8601String();
}

Sale _sale({
  String id = 's1',
  String? date,
  int paise = 500000,
  String rep = 'emp1',
  String? repName,
  String clientName = 'Acme Industries',
}) {
  return Sale(
    id: id,
    date: date ?? _thisMonth(1),
    clientName: clientName,
    clientId: 'c1',
    salesRep: rep,
    salesRepId: rep,
    salesRepName: repName,
    product: 'MF',
    company: 'HDFC',
    scheme: 'Growth',
    amount: (paise / 100).toStringAsFixed(2),
    amountPaise: paise,
    frequency: 'M',
  );
}

Interaction _interaction({
  String id = 'i1',
  String? date,
  String employee = 'emp1',
}) => Interaction(
  id: id,
  date: date ?? _thisMonth(2),
  clientName: 'Acme Industries',
  clientContact: '9999999999',
  employee: employee,
  employeeId: employee,
  followUpDate: '',
  followUpTime: '',
  priority: 'HIGH',
);

Future<void> _pump(
  WidgetTester tester, {
  required _FakeService service,
  UserRole role = UserRole.admin,
  Size size = const Size(1280, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(role)),
        apiServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: MonthlyReportScreen()),
      ),
    ),
  );
}

final nowDate = DateTime.now();
final monthLabel = DateFormat('MMMM yyyy').format(nowDate);
final today = DateTime(nowDate.year, nowDate.month, nowDate.day);

/// Makes the date-range dialog answer with [start]..[end].
void pickRange(DateTime start, DateTime end) {
  debugDateRangePicker = (context, initial, today) async =>
      DateTimeRange(start: start, end: end);
  addTearDown(() => debugDateRangePicker = null);
}

DateTime prevMonthDay(int day) =>
    DateTime(nowDate.year, nowDate.month - 1, day);

String customLabel(DateTime start, DateTime end) =>
    ReportPeriodSelection.customCapped(
      start,
      end,
      latestMonth: ReportMonth.current(),
    ).label;

void main() {
  // ── Wide layout (768 and up) ─────────────────────────────────────────

  group('wide layout', () {
    const desktop = Size(1440, 900);
    const laptop = Size(1024, 768);
    const tablet = Size(768, 1024);

    const roster = [
      EmployeeDropdown(id: 'emp1', name: 'Asha Rao', role: 'EMPLOYEE'),
      EmployeeDropdown(id: 'emp2', name: 'Bilal Khan', role: 'EMPLOYEE'),
      EmployeeDropdown(id: 'emp3', name: 'Quiet Person', role: 'EMPLOYEE'),
    ];

    /// Asha: two deals, 4,000. Bilal: one deal, 9,000. Quiet Person: idle.
    /// One sale last month so the history table has a real row to tap.
    _FakeService twoReps() => _FakeService(
      sales: [
        _sale(id: 'a', rep: 'emp1', repName: 'Asha Rao', paise: 300000),
        _sale(
          id: 'a2',
          date: _thisMonth(2),
          rep: 'emp1',
          repName: 'Asha Rao',
          paise: 100000,
        ),
        _sale(id: 'b', rep: 'emp2', repName: 'Bilal Khan', paise: 900000),
        _sale(
          id: 'old',
          date: prevMonthDay(10).toIso8601String(),
          rep: 'emp2',
          repName: 'Bilal Khan',
          paise: 200000,
        ),
      ],
      interactions: [_interaction()],
      roster: roster,
    );

    Offset middle(WidgetTester tester) => Offset(
      tester.view.physicalSize.width / 2,
      tester.view.physicalSize.height * 0.6,
    );

    /// Drags the page up in steps so every lazily built section is laid out
    /// at least once, failing on the first overflow.
    Future<void> scrollThrough(WidgetTester tester) async {
      for (var i = 0; i < 14; i++) {
        await tester.dragFrom(middle(tester), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }

    Future<void> toTop(WidgetTester tester) async {
      await tester.dragFrom(middle(tester), const Offset(0, 9000));
      await tester.pumpAndSettle();
    }

    Future<void> reveal(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;
    double left(WidgetTester tester, Finder f) => tester.getTopLeft(f).dx;

    Finder inTable(String text) =>
        find.descendant(of: find.byType(TeamTable), matching: find.text(text));

    Future<void> openTeam(WidgetTester tester) async {
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a spinner while loading, then the report', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Monthly Report'), findsNothing);
      expect(find.text('Revenue'), findsOneWidget);
      expect(find.textContaining('13,000'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders an error state with a retry when loading fails', (
      tester,
    ) async {
      await _pump(tester, service: _FakeService(throwOnLoad: true));
      await tester.pumpAndSettle();
      expect(find.text('Could not build the report'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('an empty month is the hero and one muted line', (
      tester,
    ) async {
      await _pump(
        tester,
        service: _FakeService(roster: roster),
        size: desktop,
      );
      await tester.pumpAndSettle();

      expect(find.text('No activity this month'), findsOneWidget);
      expect(find.text('₹0'), findsOneWidget);
      expect(find.text('Top performers'), findsNothing);
      expect(find.text('Deals'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header: title left; period bar and Export on the same row', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();

      final title = tester.getCenter(find.text('Reports'));
      final period = tester.getCenter(find.text(monthLabel));
      final export = tester.getCenter(find.text('Export'));
      expect((period.dy - title.dy).abs(), lessThan(24));
      expect((export.dy - title.dy).abs(), lessThan(24));
      expect(title.dx, lessThan(period.dx));
      expect(period.dx, lessThan(export.dx));

      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Custom range'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsWidgets);

      // Tabs sit left-aligned, not stretched across the page.
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
      expect(left(tester, find.text('Overview')), lessThan(300));
      expect(left(tester, find.text('Team')), lessThan(400));
      expect(find.text('Week'), findsNothing);
    });

    testWidgets('1440: sections present; hero and KPI grid side by side', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();

      for (final label in const [
        'Deals',
        'Clients',
        'New clients',
        'Follow-ups',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'missing KPI $label');
      }

      // Hero on the left two thirds, the 2x2 tiles on the right third.
      final hero = left(tester, find.text('Revenue'));
      final deals = left(tester, find.text('Deals'));
      final clients = left(tester, find.text('Clients'));
      final newClients = left(tester, find.text('New clients'));
      expect(deals, greaterThan(hero + 600));
      expect(clients, greaterThan(deals));
      expect(
        top(tester, find.text('Clients')),
        closeTo(top(tester, find.text('Deals')), 1),
      );
      expect(newClients, closeTo(deals, 1));
      expect(
        top(tester, find.text('New clients')),
        greaterThan(top(tester, find.text('Deals')) + 40),
      );

      for (final section in const [
        'Top performers',
        'Products',
        'Payment frequency',
        'Revenue by company',
        'Largest deals',
        'Last 12 months',
        'Month by month',
      ]) {
        await reveal(tester, find.text(section));
        expect(find.text(section), findsOneWidget, reason: 'missing: $section');
      }
      expect(find.text('Follow-ups'), findsWidgets);

      // Two to a row: Top performers | Products, Revenue by company |
      // Largest deals; the last two sections take the full width.
      expect(
        top(tester, find.text('Top performers')),
        closeTo(top(tester, find.text('Products')), 1),
      );
      expect(
        left(tester, find.text('Top performers')),
        lessThan(left(tester, find.text('Products'))),
      );
      expect(
        top(tester, find.text('Revenue by company')),
        closeTo(top(tester, find.text('Largest deals')), 1),
      );
      expect(
        top(tester, find.text('Last 12 months')),
        greaterThan(top(tester, find.text('Largest deals'))),
      );
      expect(
        top(tester, find.text('Month by month')),
        greaterThan(top(tester, find.text('Last 12 months'))),
      );

      // No subtitles or helper captions.
      expect(find.text('Booked value per day'), findsNothing);
      expect(find.text('Largest first'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1024: hero on top, KPI tiles four across, sections paired', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: laptop);
      await tester.pumpAndSettle();

      final revenueTop = top(tester, find.text('Revenue'));
      final dealsTop = top(tester, find.text('Deals'));
      expect(dealsTop, greaterThan(revenueTop + 100));
      for (final other in const ['Clients', 'New clients']) {
        expect(
          top(tester, find.text(other)),
          closeTo(dealsTop, 1),
          reason: '$other should sit on the same row',
        );
      }
      expect(
        left(tester, find.text('Clients')),
        greaterThan(left(tester, find.text('Deals'))),
      );

      for (final section in const [
        'Top performers',
        'Products',
        'Payment frequency',
        'Revenue by company',
        'Largest deals',
        'Last 12 months',
        'Month by month',
      ]) {
        await reveal(tester, find.text(section));
        expect(find.text(section), findsOneWidget, reason: 'missing: $section');
      }
      expect(
        top(tester, find.text('Revenue by company')),
        closeTo(top(tester, find.text('Largest deals')), 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow content area stacks paired sections', (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<void> pumpRow(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const SplitRow(
                    left: SizedBox(key: Key('l'), height: 40),
                    right: SizedBox(key: Key('r'), height: 40),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await pumpRow(496);
      expect(tester.getTopLeft(find.byKey(const Key('r'))).dy, greaterThan(40));
      expect(tester.getTopLeft(find.byKey(const Key('r'))).dx, 0);

      await pumpRow(712);
      expect(tester.getTopLeft(find.byKey(const Key('r'))).dy, 0);
      expect(
        tester.getTopLeft(find.byKey(const Key('r'))).dx,
        greaterThan(300),
      );
    });

    testWidgets('team: columns, active count, idle last and dimmed', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();
      await openTeam(tester);

      expect(find.text('Active 2 of 3'), findsOneWidget);
      for (final column in const [
        'Employee',
        'Revenue',
        'Change',
        'Deals',
        'Clients',
        'Follow-ups',
        'New clients',
        'Overdue',
      ]) {
        expect(inTable(column), findsOneWidget, reason: 'missing $column');
      }
      // The sort chips are the phone's; the table has headers instead.
      expect(find.byType(TeamTable), findsOneWidget);
      expect(find.byType(TeamTab), findsNothing);

      // Revenue, highest first by default; the idle person last.
      expect(
        top(tester, find.text('Bilal Khan')),
        lessThan(top(tester, find.text('Asha Rao'))),
      );
      expect(
        top(tester, find.text('Asha Rao')),
        lessThan(top(tester, find.text('Quiet Person'))),
      );
      expect(find.text('No activity'), findsNothing);
      expect(find.textContaining('9,000'), findsWidgets);
      final dimmed = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Quiet Person'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(dimmed.opacity, lessThan(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('team: tapping a header sorts; tapping again reverses', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();
      await openTeam(tester);

      double y(String name) => top(tester, find.text(name));

      // Deals: Asha has two, Bilal one.
      await tester.tap(inTable('Deals'));
      await tester.pumpAndSettle();
      expect(y('Asha Rao'), lessThan(y('Bilal Khan')));
      expect(y('Bilal Khan'), lessThan(y('Quiet Person')));

      await tester.tap(inTable('Deals'));
      await tester.pumpAndSettle();
      expect(y('Bilal Khan'), lessThan(y('Asha Rao')));
      // Idle people stay last whichever way it is sorted.
      expect(y('Asha Rao'), lessThan(y('Quiet Person')));

      // Names sort A to Z first.
      await tester.tap(inTable('Employee'));
      await tester.pumpAndSettle();
      expect(y('Asha Rao'), lessThan(y('Bilal Khan')));
      await tester.tap(inTable('Employee'));
      await tester.pumpAndSettle();
      expect(y('Bilal Khan'), lessThan(y('Asha Rao')));
      expect(y('Asha Rao'), lessThan(y('Quiet Person')));

      // Back to revenue: highest first.
      await tester.tap(inTable('Revenue'));
      await tester.pumpAndSettle();
      expect(y('Bilal Khan'), lessThan(y('Asha Rao')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('team: a row opens a wide employee report and returns', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();
      await openTeam(tester);

      await tester.tap(find.text('Bilal Khan'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeReportScreen), findsOneWidget);
      expect(find.text('Bilal Khan'), findsOneWidget);
      expect(find.text('Rank #1 of 3'), findsOneWidget);
      // Identity, period bar and Export share the header row.
      final name = tester.getCenter(find.text('Bilal Khan'));
      expect(
        (tester.getCenter(find.text(monthLabel)).dy - name.dy).abs(),
        lessThan(30),
      );
      expect(
        (tester.getCenter(find.text('Export')).dy - name.dy).abs(),
        lessThan(30),
      );
      expect(find.byTooltip('Export'), findsNothing);

      // Hero left, KPI tiles right.
      expect(
        left(tester, find.text('Deals').first),
        greaterThan(left(tester, find.text('Revenue').first) + 600),
      );
      expect(find.textContaining('9,000'), findsWidgets);

      // Vs team average | Products on one row; Daily activity full width;
      // Activity | Upcoming follow-ups below it.
      await reveal(tester, find.text('Vs team average'));
      expect(
        top(tester, find.text('Vs team average')),
        closeTo(top(tester, find.text('Products')), 1),
      );
      expect(find.text('Daily activity'), findsOneWidget);
      expect(
        top(tester, find.text('Daily activity')),
        greaterThan(top(tester, find.text('Products'))),
      );
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EmployeeReportScreen), findsNothing);
      expect(find.text('Active 2 of 3'), findsOneWidget);
    });

    testWidgets('team sort survives opening and leaving an employee', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: laptop);
      await tester.pumpAndSettle();
      await openTeam(tester);
      await tester.tap(inTable('Deals'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Asha Rao'));
      await tester.pumpAndSettle();
      expect(find.byType(EmployeeReportScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        top(tester, find.text('Asha Rao')),
        lessThan(top(tester, find.text('Bilal Khan'))),
      );
    });

    testWidgets('stepping back a month re-runs the report', (tester) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      final previous = DateFormat(
        'MMMM yyyy',
      ).format(DateTime(nowDate.year, nowDate.month - 1));
      expect(find.text(previous), findsOneWidget);
      expect(find.textContaining('2,000'), findsWidgets);
      expect(find.textContaining('13,000'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens on the current month; next is disabled', (tester) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();

      expect(find.text(monthLabel), findsOneWidget);
      final forward = tester.widget<IconButton>(
        find.descendant(
          of: find.byTooltip('No later month to report on'),
          matching: find.byType(IconButton),
        ),
      );
      expect(forward.onPressed, isNull);
    });

    testWidgets('custom range applies, hides month-only sections, x returns', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Month by month'));
      expect(find.text('Last 12 months'), findsOneWidget);
      await toTop(tester);

      final start = prevMonthDay(10);
      pickRange(start, today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();

      final label = customLabel(start, today);
      expect(find.text(label), findsOneWidget);
      expect(find.text(monthLabel), findsNothing);
      expect(find.byTooltip('Previous month'), findsNothing);
      // The same sections, minus the ones that need a month.
      await reveal(tester, find.text('Revenue by company'));
      expect(find.text('Revenue by company'), findsOneWidget);
      expect(find.text('Last 12 months'), findsNothing);
      expect(find.text('Month by month'), findsNothing);
      expect(tester.takeException(), isNull);
      await toTop(tester);

      // Team works on the range too.
      await openTeam(tester);
      expect(find.byType(TeamTable), findsOneWidget);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back to current month'));
      await tester.pumpAndSettle();
      expect(find.text(monthLabel), findsOneWidget);
      expect(find.text(label), findsNothing);
      await reveal(tester, find.text('Month by month'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('employee report opens on the custom range in use', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();
      final start = prevMonthDay(10);
      pickRange(start, today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();
      await openTeam(tester);
      await tester.tap(find.text('Bilal Khan'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeReportScreen), findsOneWidget);
      expect(find.text(customLabel(start, today)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a month in Month by month opens that month', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();

      final last = DateTime(nowDate.year, nowDate.month - 1);
      final row = find.text(DateFormat('MMM yyyy').format(last));
      await reveal(tester, row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      await toTop(tester);
      expect(find.text(DateFormat('MMMM yyyy').format(last)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('export sheet: PDF, and Excel only in month mode', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: desktop);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('PDF report'), findsOneWidget);
      expect(find.text('Excel'), findsOneWidget);
      // A bottom sheet, but not stretched across a 1440 window.
      expect(tester.getSize(find.text('PDF report')).width, lessThan(600));
      await tester.tapAt(const Offset(10, 10)); // dismiss
      await tester.pumpAndSettle();

      pickRange(prevMonthDay(10), today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('PDF report'), findsOneWidget);
      expect(find.text('Excel'), findsNothing);
    });

    testWidgets('an admin reads unfiltered, company-wide', (tester) async {
      final service = twoReps();
      await _pump(tester, service: service, size: desktop);
      await tester.pumpAndSettle();

      expect(service.lastSalesRepId, isNull);
      expect(service.lastInteractionEmployeeId, isNull);
      expect(service.lastClientEmployeeId, isNull);
      expect(find.textContaining('13,000'), findsWidgets);
    });

    testWidgets('an employee sees their own report, wide, with no tabs', (
      tester,
    ) async {
      final service = _FakeService(
        sales: [
          _sale(id: 'mine', rep: 'emp1', paise: 300000),
          _sale(id: 'theirs', rep: 'emp2', paise: 900000),
        ],
        interactions: [_interaction()],
      );
      await _pump(
        tester,
        role: UserRole.employee,
        service: service,
        size: desktop,
      );
      await tester.pumpAndSettle();

      // The screen must ASK for a scoped read, and show only their figures.
      expect(service.lastSalesRepId, 'emp1');
      expect(service.lastInteractionEmployeeId, 'emp1');
      expect(service.lastClientEmployeeId, 'emp1');
      expect(find.textContaining('3,000'), findsWidgets);
      expect(find.textContaining('12,000'), findsNothing);

      expect(find.text('Overview'), findsNothing);
      expect(find.text('Team'), findsNothing);
      expect(find.byType(TeamTable), findsNothing);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.textContaining('Rank #'), findsNothing);
      expect(find.text('Vs team average'), findsNothing);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text(monthLabel), findsOneWidget);
      expect(find.text('Daily activity'), findsOneWidget);

      // Hero left, KPI tiles right; period bar and Export beside the name.
      expect(
        left(tester, find.text('Deals')),
        greaterThan(left(tester, find.text('Revenue')) + 600),
      );
      expect(
        (tester.getCenter(find.text('Export')).dy -
                tester.getCenter(find.text('Asha Rao')).dy)
            .abs(),
        lessThan(30),
      );
      await reveal(tester, find.text('Activity'));
      expect(find.text('Activity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an employee exports PDF only on a custom range', (
      tester,
    ) async {
      await _pump(
        tester,
        role: UserRole.employee,
        service: _FakeService(sales: [_sale()]),
        size: laptop,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('Excel'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      pickRange(prevMonthDay(10), today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('PDF report'), findsOneWidget);
      expect(find.text('Excel'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [tablet, laptop, desktop]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('admin overview, team and employee fit at $tag', (
        tester,
      ) async {
        final stamp = DateTime.now().toIso8601String();
        await _pump(
          tester,
          size: size,
          service: _FakeService(
            sales: [
              _sale(id: 'a', rep: 'emp1', repName: 'Asha Rao', paise: 12345678),
              _sale(
                id: 'b',
                date: _thisMonth(3),
                rep: 'emp2',
                repName: 'Bilal Khan',
                paise: 987654321,
                clientName: 'A very long client name Private Limited India',
              ),
              _sale(id: 'c', date: stamp, rep: 'emp2', paise: 250000),
              _sale(
                id: 'old',
                date: prevMonthDay(10).toIso8601String(),
                rep: 'emp1',
                repName: 'Asha Rao',
                paise: 4500000,
              ),
            ],
            interactions: [
              _interaction(),
              _interaction(id: 'i2', employee: 'emp2'),
            ],
            roster: roster,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
        await toTop(tester);

        // Team tab, sorted a couple of ways, then a person.
        await openTeam(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(inTable('New clients'));
        await tester.pumpAndSettle();
        await tester.tap(inTable('Change'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
        await toTop(tester);

        await tester.tap(find.text('Bilal Khan'));
        await tester.pumpAndSettle();
        expect(find.byType(EmployeeReportScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);

        // A custom range inside the employee report.
        await toTop(tester);
        pickRange(prevMonthDay(10), today);
        await tester.tap(find.byTooltip('Custom range'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);

        // And a custom range on the main screen.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Overview'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Custom range'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
      });

      testWidgets('an employee report fits at $tag', (tester) async {
        await _pump(
          tester,
          role: UserRole.employee,
          size: size,
          service: _FakeService(
            sales: [
              _sale(paise: 123456789),
              _sale(id: 's2', date: _thisMonth(5), paise: 4500),
            ],
            interactions: [
              _interaction(),
              _interaction(id: 'i2'),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
      });
    }
  });

  group('phone layout', () {
    const phone = Size(390, 844);

    const roster = [
      EmployeeDropdown(id: 'emp1', name: 'Asha Rao', role: 'EMPLOYEE'),
      EmployeeDropdown(id: 'emp2', name: 'Bilal Khan', role: 'EMPLOYEE'),
      EmployeeDropdown(id: 'emp3', name: 'Quiet Person', role: 'EMPLOYEE'),
    ];

    _FakeService twoReps() => _FakeService(
      sales: [
        _sale(id: 'a', rep: 'emp1', repName: 'Asha Rao', paise: 300000),
        _sale(id: 'b', rep: 'emp2', repName: 'Bilal Khan', paise: 900000),
      ],
      interactions: [_interaction()],
      roster: roster,
    );

    /// Drags the page up in steps so every lazily built section is laid out
    /// at least once, failing on the first overflow.
    Offset middle(WidgetTester tester) => Offset(
      tester.view.physicalSize.width / 2,
      tester.view.physicalSize.height * 0.6,
    );

    Future<void> scrollThrough(WidgetTester tester) async {
      for (var i = 0; i < 14; i++) {
        await tester.dragFrom(middle(tester), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }

    Future<void> toTop(WidgetTester tester) async {
      await tester.dragFrom(middle(tester), const Offset(0, 9000));
      await tester.pumpAndSettle();
    }

    Future<void> reveal(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    testWidgets('overview shows revenue, KPIs and the sections', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: phone);
      await tester.pumpAndSettle();

      expect(find.text('Reports'), findsOneWidget);
      // Opens on the current month; no Week | Month switch.
      expect(
        find.text(DateFormat('MMMM yyyy').format(DateTime.now())),
        findsOneWidget,
      );
      expect(find.text('Week'), findsNothing);
      expect(find.byTooltip('Custom range'), findsOneWidget);
      expect(find.text('Week'), findsNothing);
      expect(find.text('Month'), findsNothing);
      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
      expect(find.byTooltip('Export'), findsOneWidget);

      expect(find.text('Revenue'), findsOneWidget);
      expect(find.textContaining('12,000'), findsWidgets);
      for (final label in const [
        'Deals',
        'Clients',
        'New clients',
        'Follow-ups',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'missing KPI $label');
      }

      for (final section in const [
        'Top performers',
        'Products',
        'Payment frequency',
        'Revenue by company',
        'Largest deals',
        'Last 12 months',
      ]) {
        await reveal(tester, find.text(section));
        expect(find.text(section), findsOneWidget, reason: 'missing: $section');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('no subtitles or helper captions', (tester) async {
      await _pump(tester, service: twoReps(), size: phone);
      await tester.pumpAndSettle();

      expect(find.text('Booked value per day'), findsNothing);
      expect(find.text('Largest first'), findsNothing);
      expect(find.text('Weekly'), findsNothing);
    });

    testWidgets('tapping a bar in Last 12 months selects that month', (
      tester,
    ) async {
      await _pump(
        tester,
        service: _FakeService(
          sales: [
            _sale(),
            _sale(
              id: 'old',
              date: DateTime(
                DateTime.now().year,
                DateTime.now().month - 2,
                10,
              ).toIso8601String(),
              paise: 700000,
            ),
          ],
          roster: roster,
        ),
        size: phone,
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Last 12 months'));

      final chart = find.byType(BarChart).last;
      final box = tester.getRect(chart);
      // 12 slots across the card's inner width; the third-from-last bar.
      final slot = box.width / 12;
      await tester.tapAt(Offset(box.left + slot * 9.5, box.bottom - 40));
      await tester.pumpAndSettle();

      final target = DateTime(DateTime.now().year, DateTime.now().month - 2);
      await toTop(tester);
      expect(find.text(DateFormat('MMMM yyyy').format(target)), findsOneWidget);
    });

    testWidgets('team tab lists everyone; a row opens that person', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: phone);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      expect(find.text('Active 2 of 3'), findsOneWidget);
      expect(find.text('Bilal Khan'), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Quiet Person'), findsOneWidget);
      expect(find.text('No activity'), findsOneWidget);
      // Ranked by revenue, the idle person last.
      expect(
        tester.getTopLeft(find.text('Bilal Khan')).dy,
        lessThan(tester.getTopLeft(find.text('Asha Rao')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Asha Rao')).dy,
        lessThan(tester.getTopLeft(find.text('Quiet Person')).dy),
      );

      await tester.tap(find.text('Bilal Khan'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeReportScreen), findsOneWidget);
      // The name is in the header row only, not repeated in the app bar.
      expect(find.text('Bilal Khan'), findsOneWidget);
      expect(find.text('Week'), findsNothing);
      expect(find.text('Month'), findsNothing);
      expect(find.byTooltip('Custom range'), findsOneWidget);
      expect(find.byTooltip('Export'), findsOneWidget);
      expect(find.text('Avg deal'), findsNothing);
      expect(find.text('New clients'), findsNothing);
      expect(find.text('Clients'), findsOneWidget);
      expect(find.text('Rank #1 of 3'), findsOneWidget);
      expect(find.text('75% of team'), findsOneWidget);
      expect(find.textContaining('9,000'), findsWidgets);
      expect(find.textContaining('12,000'), findsNothing);
      expect(find.text('Vs team average'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EmployeeReportScreen), findsNothing);
      expect(find.text('Active 2 of 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('team sort chips reorder the rows', (tester) async {
      await _pump(
        tester,
        service: _FakeService(
          sales: [
            _sale(id: 'a', rep: 'emp1', repName: 'Asha Rao', paise: 100000),
            _sale(id: 'b', rep: 'emp1', repName: 'Asha Rao', paise: 100000),
            _sale(id: 'c', rep: 'emp2', repName: 'Bilal Khan', paise: 900000),
          ],
          roster: roster,
        ),
        size: phone,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('Bilal Khan'), lessThan(y('Asha Rao')));

      await tester.tap(find.text('Deals'));
      await tester.pumpAndSettle();
      expect(y('Asha Rao'), lessThan(y('Bilal Khan')));
    });

    test('period labels', () {
      final latest = ReportMonth(2026, 11);
      String l(DateTime a, DateTime b) =>
          ReportPeriodSelection.custom(a, b, latestMonth: latest).label;
      expect(
        l(DateTime(2026, 11, 1), DateTime(2026, 11, 15)),
        '1 – 15 Nov 2026',
      );
      expect(
        l(DateTime(2026, 10, 1), DateTime(2026, 11, 15)),
        '1 Oct – 15 Nov 2026',
      );
      expect(
        l(DateTime(2025, 12, 20), DateTime(2026, 1, 3)),
        '20 Dec 2025 – 3 Jan 2026',
      );
      final month = ReportPeriodSelection.month(latest, latestMonth: latest);
      expect(month.label, 'November 2026');
      expect(month.deltaLabel, 'vs Oct');
      expect(
        ReportPeriodSelection.custom(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 15),
          latestMonth: latest,
        ).deltaLabel,
        'vs previous period',
      );
    });

    testWidgets('opens on the current month; next is disabled', (tester) async {
      await _pump(tester, service: twoReps(), size: phone);
      await tester.pumpAndSettle();

      expect(find.text(monthLabel), findsOneWidget);
      final forward = tester.widget<IconButton>(
        find.descendant(
          of: find.byTooltip('No later month to report on'),
          matching: find.byType(IconButton),
        ),
      );
      expect(forward.onPressed, isNull);
    });

    testWidgets('custom range applies, hides Last 12 months, x returns', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: phone);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Last 12 months'));
      expect(find.text('Last 12 months'), findsOneWidget);
      await toTop(tester);

      final start = prevMonthDay(10);
      pickRange(start, today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();

      final label = customLabel(start, today);
      expect(find.text(label), findsOneWidget);
      expect(find.text(monthLabel), findsNothing);
      expect(find.byTooltip('Previous month'), findsNothing);
      expect(find.byTooltip('Custom range'), findsNothing);
      await scrollThrough(tester);
      expect(find.text('Last 12 months'), findsNothing);
      await toTop(tester);

      await tester.tap(find.byTooltip('Back to current month'));
      await tester.pumpAndSettle();
      expect(find.text(monthLabel), findsOneWidget);
      expect(find.text(label), findsNothing);
      await reveal(tester, find.text('Last 12 months'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('employee report changes period without touching the main', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: phone);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bilal Khan'));
      await tester.pumpAndSettle();

      // Follows the main screen's month; no Week | Month control.
      expect(find.byType(EmployeeReportScreen), findsOneWidget);
      expect(find.text(monthLabel), findsOneWidget);
      expect(find.text('Week'), findsNothing);

      final start = prevMonthDay(1);
      pickRange(start, today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();
      expect(find.text(customLabel(start, today)), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(monthLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('employee report opens on the custom range in use', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: phone);
      await tester.pumpAndSettle();
      final start = prevMonthDay(10);
      pickRange(start, today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bilal Khan'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeReportScreen), findsOneWidget);
      expect(find.text(customLabel(start, today)), findsOneWidget);
    });

    testWidgets('export sheet: PDF, and Excel only in month mode', (
      tester,
    ) async {
      await _pump(tester, service: twoReps(), size: phone);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      expect(find.text('PDF report'), findsOneWidget);
      expect(find.text('Excel'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // dismiss
      await tester.pumpAndSettle();

      pickRange(prevMonthDay(10), today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      expect(find.text('PDF report'), findsOneWidget);
      expect(find.text('Excel'), findsNothing);
    });

    testWidgets('employee: custom range exports PDF only', (tester) async {
      await _pump(
        tester,
        role: UserRole.employee,
        service: _FakeService(sales: [_sale()]),
        size: phone,
      );
      await tester.pumpAndSettle();
      expect(find.text(monthLabel), findsOneWidget);
      expect(find.text('Week'), findsNothing);

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      expect(find.text('Excel'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      pickRange(prevMonthDay(10), today);
      await tester.tap(find.byTooltip('Custom range'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      expect(find.text('PDF report'), findsOneWidget);
      expect(find.text('Excel'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('developer accounts are out of totals, team and rank', (
      tester,
    ) async {
      await _pump(
        tester,
        service: _FakeService(
          sales: [
            _sale(id: 'a', rep: 'emp1', repName: 'Asha Rao', paise: 300000),
            _sale(id: 'b', rep: 'emp2', repName: 'Bilal Khan', paise: 900000),
            _sale(id: 'd', rep: 'dev1', repName: 'Dev Tester', paise: 5000000),
          ],
          interactions: [_interaction(employee: 'dev1')],
          roster: const [
            EmployeeDropdown(id: 'emp1', name: 'Asha Rao', role: 'EMPLOYEE'),
            EmployeeDropdown(id: 'emp2', name: 'Bilal Khan', role: 'EMPLOYEE'),
            EmployeeDropdown(
              id: 'dev1',
              name: 'Dev Tester',
              role: 'EMPLOYEE',
              excludeFromHeadcount: true,
            ),
          ],
        ),
        size: phone,
      );
      await tester.pumpAndSettle();

      // 3,000 + 9,000; the developer's 50,000 is not in the company total.
      expect(find.textContaining('12,000'), findsWidgets);
      expect(find.textContaining('62,000'), findsNothing);
      expect(find.text('Dev Tester'), findsNothing);

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      expect(find.text('Active 2 of 2'), findsOneWidget);
      expect(find.text('Dev Tester'), findsNothing);

      await tester.tap(find.text('Bilal Khan'));
      await tester.pumpAndSettle();
      expect(find.text('Rank #1 of 2'), findsOneWidget);
      expect(find.text('75% of team'), findsOneWidget);
    });

    testWidgets('team subtitle lists only the non-zero parts', (tester) async {
      await _pump(
        tester,
        service: _FakeService(
          sales: [
            _sale(id: 'a', rep: 'emp1', repName: 'Asha Rao', paise: 300000),
            _sale(id: 'b', rep: 'emp1', repName: 'Asha Rao', paise: 100000),
          ],
          interactions: [
            _interaction(id: 'i1', employee: 'emp2'),
            _interaction(id: 'i2', employee: 'emp2'),
          ],
          clients: [
            Client(
              id: 'n1',
              name: 'Fresh Client',
              contactNumber: '1',
              createdAt: _thisMonth(3),
              employeeId: 'emp3',
            ),
          ],
          roster: roster,
        ),
        size: phone,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      expect(find.text('2 deals'), findsOneWidget);
      expect(find.text('2 follow-ups'), findsOneWidget);
      expect(find.text('1 new client'), findsOneWidget);
      expect(find.textContaining('0 deals'), findsNothing);
      expect(find.textContaining('0 follow-ups'), findsNothing);
    });

    testWidgets('an employee sees their own report, no tabs', (tester) async {
      await _pump(
        tester,
        role: UserRole.employee,
        service: _FakeService(sales: [_sale()], interactions: [_interaction()]),
        size: phone,
      );
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsNothing);
      expect(find.text('Team'), findsNothing);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.textContaining('Rank #'), findsNothing);
      expect(find.textContaining('5,000'), findsWidgets);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Avg deal'), findsNothing);
      expect(find.text('New clients'), findsNothing);
      expect(find.text('Vs team average'), findsNothing);
      await reveal(tester, find.text('Activity'));
      expect(find.text('Activity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty month is the hero and one muted line', (
      tester,
    ) async {
      await _pump(
        tester,
        service: _FakeService(roster: roster),
        size: phone,
      );
      await tester.pumpAndSettle();

      expect(find.text('No activity this month'), findsOneWidget);
      expect(find.text('₹0'), findsOneWidget);
      expect(find.text('Top performers'), findsNothing);
      expect(find.text('Deals'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pull to refresh reloads the data', (tester) async {
      final service = twoReps();
      await _pump(tester, service: service, size: phone);
      await tester.pumpAndSettle();
      expect(service.salesCalls, 1);

      await tester.flingFrom(middle(tester), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(service.salesCalls, 2);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [Size(320, 640), Size(360, 780)]) {
      final tag = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('admin overview, team and employee fit at $tag', (
        tester,
      ) async {
        final stamp = DateTime.now().toIso8601String();
        await _pump(
          tester,
          size: size,
          service: _FakeService(
            sales: [
              _sale(id: 'a', rep: 'emp1', repName: 'Asha Rao', paise: 12345678),
              _sale(
                id: 'b',
                date: _thisMonth(3),
                rep: 'emp2',
                repName: 'Bilal Khan',
                paise: 987654321,
                clientName: 'A very long client name Private Limited India',
              ),
              _sale(id: 'c', date: stamp, rep: 'emp2', paise: 250000),
            ],
            interactions: [
              _interaction(),
              _interaction(id: 'i2', employee: 'emp2'),
            ],
            roster: roster,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);

        await toTop(tester);

        // Team tab, then a person.
        await tester.tap(find.text('Team'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
        await toTop(tester);

        await tester.tap(find.text('Bilal Khan'));
        await tester.pumpAndSettle();
        expect(find.byType(EmployeeReportScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);

        // A custom range inside the employee report.
        await toTop(tester);
        debugDateRangePicker = (context, initial, today) async => DateTimeRange(
          start: DateTime(DateTime.now().year, DateTime.now().month - 1, 10),
          end: DateTime.now(),
        );
        addTearDown(() => debugDateRangePicker = null);
        await tester.tap(find.byTooltip('Custom range'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
      });

      testWidgets('an employee report fits at $tag', (tester) async {
        await _pump(
          tester,
          role: UserRole.employee,
          size: size,
          service: _FakeService(
            sales: [
              _sale(paise: 123456789),
              _sale(id: 's2', date: _thisMonth(5), paise: 4500),
            ],
            interactions: [
              _interaction(),
              _interaction(id: 'i2'),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await scrollThrough(tester);
      });
    }

    testWidgets('team tab fits a short landscape window', (tester) async {
      await _pump(tester, service: twoReps(), size: const Size(740, 360));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await scrollThrough(tester);
    });
  });
}
