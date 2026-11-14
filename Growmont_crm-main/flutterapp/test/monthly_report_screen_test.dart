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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/firestore_service.dart';
import 'package:growmont_crm/core/providers.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/features/reports/monthly_report_screen.dart';
import 'package:growmont_crm/features/reports/widgets/report_tables.dart';
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

  /// Honours the owner filter the way CrmRepository does. The local
  /// database is NOT pre-scoped — it survives a sign-out and can hold a
  /// previous admin's rows — so an unfiltered read here returns
  /// everything, which is precisely the leak being guarded against.
  @override
  Future<List<Sale>> getSales({String? salesRepId, String? clientId}) async {
    if (throwOnLoad) throw Exception('local database unavailable');
    salesCalled = true;
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

/// Scrolls the report until [target] is built and visible.
///
/// The report is a ListView, so a section far enough down the page has not
/// been created yet and no finder — offstage-inclusive or not — will see
/// it until it is scrolled into range.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 300, maxScrolls: 80);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a spinner while loading, then the report', (tester) async {
    await _pump(tester, service: _FakeService(sales: [_sale()]));

    // First frame: still awaiting the (async) fake reads.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Monthly Report'), findsOneWidget);
    expect(find.text('REVENUE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the empty state when the month has no activity', (
    tester,
  ) async {
    await _pump(tester, service: _FakeService());
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing recorded in'), findsOneWidget);
    // The KPI grid must not render a wall of zeroes alongside it.
    expect(find.text('REVENUE'), findsNothing);
    expect(find.text('Reload data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders an error state with a retry when loading fails', (
    tester,
  ) async {
    await _pump(tester, service: _FakeService(throwOnLoad: true));
    await tester.pumpAndSettle();

    expect(find.text('Could not build the report'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('populated report shows every section for an admin', (
    tester,
  ) async {
    await _pump(
      tester,
      service: _FakeService(
        sales: [_sale(), _sale(id: 's2', date: _thisMonth(3), paise: 250000)],
        interactions: [_interaction()],
        clients: [
          Client(
            id: 'c1',
            name: 'Acme Industries',
            contactNumber: '9999999999',
            createdAt: _thisMonth(1),
          ),
        ],
        roster: const [
          EmployeeDropdown(id: 'emp1', name: 'Asha Rao', role: 'EMPLOYEE'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Revenue trend'), findsOneWidget);

    for (final section in const [
      'Revenue by product',
      'Largest deals',
      'Team performance',
      'Month-over-month',
      'How to read this report',
    ]) {
      await _scrollTo(tester, find.text(section));
      expect(find.text(section), findsOneWidget, reason: 'missing: $section');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('an employee sees no team section', (tester) async {
    await _pump(
      tester,
      role: UserRole.employee,
      service: _FakeService(sales: [_sale()]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Team performance'), findsNothing);
    expect(find.byType(TeamPerformanceTable), findsNothing);
    // Their own figures are still there.
    expect(find.text('REVENUE'), findsOneWidget);
    expect(find.textContaining('Asha Rao'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stepping back a month re-runs the report', (tester) async {
    // Dated last month, so it is absent from the default month and present
    // after one step back.
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 15);

    await _pump(
      tester,
      service: _FakeService(
        sales: [_sale(date: lastMonth.toIso8601String(), paise: 777700)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing recorded in'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing recorded in'), findsNothing);
    expect(find.text('REVENUE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cannot step past the current month', (tester) async {
    await _pump(tester, service: _FakeService(sales: [_sale()]));
    await tester.pumpAndSettle();

    // The forward arrow is disabled on the latest month, and says why.
    expect(find.byTooltip('No later month to report on'), findsOneWidget);
    final forward = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('No later month to report on'),
        matching: find.byType(IconButton),
      ),
    );
    expect(forward.onPressed, isNull);
  });

  testWidgets('warns when records cannot be placed in a month', (tester) async {
    await _pump(
      tester,
      service: _FakeService(
        sales: [_sale(), _sale(id: 'bad', date: '')],
        clients: [
          const Client(id: 'c9', name: 'No Date Ltd', contactNumber: '1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final notice = find.text('Some records could not be placed in a month');
    await _scrollTo(tester, notice);

    expect(notice, findsOneWidget);
    expect(find.textContaining('1 sale(s) have no usable date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Scope isolation ──────────────────────────────────────────────────
  //
  // Regression guard for a real leak: the screen originally read
  // getSales() with no owner filter, trusting the sync layer to have
  // pulled only the signed-in user's rows. The local SQLite database is
  // not cleared on sign-out, so after an admin had used the machine it
  // still held the whole company's documents — and an employee's report
  // showed company-wide totals under their own name.

  testWidgets('an employee only ever reads their own records', (tester) async {
    final service = _FakeService(
      sales: [
        _sale(id: 'mine', rep: 'emp1', paise: 300000),
        _sale(id: 'theirs', rep: 'emp2', paise: 900000),
      ],
      interactions: [
        _interaction(id: 'i1'),
        _interaction(id: 'i2', employee: 'emp2'),
      ],
    );

    await _pump(tester, service: service, role: UserRole.employee);
    await tester.pumpAndSettle();

    // The screen must ASK for a scoped read...
    expect(service.salesCalled, isTrue);
    expect(service.lastSalesRepId, 'emp1');
    expect(service.lastInteractionEmployeeId, 'emp1');
    expect(service.lastClientEmployeeId, 'emp1');

    // ...and the figures must reflect only their own rows. 3,000 is this
    // employee's sale; 12,000 would be the company total.
    expect(find.textContaining('3,000'), findsWidgets);
    expect(
      find.textContaining('12,000'),
      findsNothing,
      reason: 'company-wide revenue must never reach an employee report',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an admin reads unfiltered, company-wide', (tester) async {
    final service = _FakeService(
      sales: [
        _sale(id: 'a', rep: 'emp1', paise: 300000),
        _sale(id: 'b', rep: 'emp2', paise: 900000),
      ],
    );

    await _pump(tester, service: service, role: UserRole.admin);
    await tester.pumpAndSettle();

    expect(service.lastSalesRepId, isNull);
    expect(service.lastInteractionEmployeeId, isNull);
    expect(service.lastClientEmployeeId, isNull);
    // Both reps' sales are included: 3,000 + 9,000.
    expect(find.textContaining('12,000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export offers PDF, Excel and both', (tester) async {
    await _pump(tester, service: _FakeService(sales: [_sale()]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();

    expect(find.text('Export report'), findsWidgets); // button + dialog title
    expect(find.text('PDF document'), findsOneWidget);
    expect(find.text('Excel workbook'), findsOneWidget);
    expect(find.text('Both'), findsOneWidget);

    // Dismissing must not start an export or leave the button spinning.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('PDF document'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export button is disabled while the report is loading', (
    tester,
  ) async {
    // No pump or settle past the first frame: the fake's reads are async,
    // so the report is still loading here. One extra pump would flush the
    // microtask that completes them.
    await _pump(tester, service: _FakeService(sales: [_sale()]));

    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);

    await tester.pumpAndSettle();
  });

  testWidgets('renders on a small phone without overflowing', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 640),
      service: _FakeService(
        sales: [
          _sale(),
          _sale(id: 's2', date: _thisMonth(4), paise: 123456789, repName: 'Asha Rao'),
        ],
        interactions: [_interaction()],
        roster: const [
          EmployeeDropdown(id: 'emp1', name: 'Asha Rao', role: 'EMPLOYEE'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Scroll the whole report to catch an overflow further down the list.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in a short landscape window without overflowing', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(740, 360),
      service: _FakeService(sales: [_sale()], interactions: [_interaction()]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
