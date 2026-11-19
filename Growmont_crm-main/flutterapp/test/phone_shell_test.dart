import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/attendance/attendance_providers.dart';
import 'package:growmont_crm/features/attendance/dashboard_ring.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/models/user.dart';
import 'package:growmont_crm/shared/widgets/app_bottom_nav.dart';
import 'package:growmont_crm/shared/widgets/app_shell.dart';
import 'package:growmont_crm/shared/widgets/branch_container.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_fakes.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    user: AppUser(id: '1', email: 'admin@growmont.com', name: 'Admin User', role: UserRole.admin),
    isLoading: false,
  );
}

/// A page with state worth keeping: a counter and a scroll position.
class _Counter extends StatefulWidget {
  const _Counter(this.name);
  final String name;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        key: ValueKey('tap-${widget.name}'),
        onPressed: () => setState(() => taps++),
        child: Text('${widget.name} taps: $taps'),
      ),
      Expanded(
        child: ListView(
          key: ValueKey('list-${widget.name}'),
          controller: scroll,
          children: [for (var i = 0; i < 60; i++) SizedBox(height: 60, child: Text('${widget.name} row $i'))],
        ),
      ),
    ],
  );
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage(this.onChartDrag);
  final VoidCallback onChartDrag;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        key: const ValueKey('fake-chart'),
        width: double.infinity,
        height: 200,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (_) => onChartDrag(),
          child: const ColoredBox(color: Colors.blue),
        ),
      ),
      const Expanded(child: SizedBox.expand(key: ValueKey('empty-area'))),
    ],
  );
}

class _Shell {
  _Shell(this.router);
  final GoRouter router;
  String get path => router.routeInformationProvider.value.uri.path;
}

GoRouter _router({VoidCallback? onChartDrag}) {
  GoRoute page(String path, Widget child, {List<RouteBase> routes = const []}) => GoRoute(
    path: path,
    pageBuilder: (c, s) => NoTransitionPage(child: child),
    routes: routes,
  );
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchContainer,
        builder: (c, s, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [page('/dashboard', _DashboardPage(onChartDrag ?? () {}))]),
          StatefulShellBranch(routes: [page('/sales', const _Counter('sales'))]),
          StatefulShellBranch(routes: [page('/interactions', const _Counter('interactions'))]),
          StatefulShellBranch(routes: [
            page(
              '/clients',
              const _Counter('clients'),
              routes: [
                GoRoute(
                  path: ':id',
                  pageBuilder: (c, s) => NoTransitionPage(child: Scaffold(body: Text('detail ${s.pathParameters['id']}'))),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [page('/employees', const _Counter('employees'))]),
          StatefulShellBranch(routes: [page('/info-portal', const _Counter('info'))]),
          StatefulShellBranch(routes: [page('/profile', const _Counter('profile'))]),
          StatefulShellBranch(routes: [page('/reports', const _Counter('reports'))]),
          StatefulShellBranch(routes: [page('/attendance', const _Counter('attendance'))]),
        ],
      ),
    ],
  );
}

Future<_Shell> _pump(
  WidgetTester t, {
  Size size = const Size(390, 800),
  VoidCallback? onChartDrag,
  FakeAttendanceService? service,
  FakeLocation? location,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final router = _router(onChartDrag: onChartDrag);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        canMarkAttendanceProvider.overrideWithValue(service != null),
        if (service != null) ...[
          attendanceServiceProvider.overrideWithValue(service),
          locationGatewayProvider.overrideWithValue(location ?? FakeLocation()),
          biometricGatewayProvider.overrideWithValue(FakeBiometric()),
        ],
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  addTearDown(() async => t.pumpWidget(const SizedBox()));
  await _settle(t);
  return _Shell(router);
}

Future<void> _settle(WidgetTester t, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _swipe(WidgetTester t, {required bool left, Finder? at}) async {
  await t.fling(at ?? find.byType(PageView), Offset(left ? -300 : 300, 0), 1200);
  await _settle(t);
}

/// Records every HapticFeedback the app asks the platform for.
List<String> _spyHaptics(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

int _navBranch(WidgetTester t) => t.widget<AppBottomNav>(find.byType(AppBottomNav)).currentBranch;

double _pagerPage(WidgetTester t) =>
    t.widget<PageView>(find.byKey(const ValueKey('branch-pager'))).controller!.page!;

void main() {
  group('phone swipe between the main screens', () {
    testWidgets('swiping follows the finger, changes page and moves the nav selection', (t) async {
      final s = await _pump(t);
      expect(s.path, '/dashboard');
      expect(_navBranch(t), 0);

      await _swipe(t, left: true);
      expect(s.path, '/sales');
      expect(_navBranch(t), 1);
      expect(_pagerPage(t), closeTo(1, 0.01));

      await _swipe(t, left: true);
      expect(s.path, '/interactions');
      await _swipe(t, left: false);
      expect(s.path, '/sales');
      expect(_navBranch(t), 1);
    });

    testWidgets('mid-drag the pages follow the finger', (t) async {
      await _pump(t);
      final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('empty-area'))));
      await g.moveBy(const Offset(-120, 0)); // crosses the touch slop
      await t.pump();
      await g.moveBy(const Offset(-100, 0));
      await t.pump();
      final page = _pagerPage(t);
      expect(page, greaterThan(0.15));
      expect(page, lessThan(0.4));
      await g.up();
      await _settle(t);
    });

    testWidgets('a bottom-nav tap moves the page and the URL', (t) async {
      final s = await _pump(t);
      await t.tap(find.descendant(of: find.byType(AppBottomNav), matching: find.text('Interactions')));
      await _settle(t, frames: 20);
      expect(s.path, '/interactions');
      expect(_pagerPage(t), closeTo(2, 0.01));
      expect(_navBranch(t), 2);

      await t.tap(find.descendant(of: find.byType(AppBottomNav), matching: find.text('Dashboard')));
      await _settle(t, frames: 20);
      expect(s.path, '/dashboard');
      expect(_pagerPage(t), closeTo(0, 0.01));
    });

    testWidgets('a deep link or router change moves the pager', (t) async {
      final s = await _pump(t);
      s.router.go('/clients');
      await _settle(t, frames: 20);
      expect(_pagerPage(t), closeTo(3, 0.01));
      expect(_navBranch(t), 3);
    });

    testWidgets('swiping past Clients opens More: no branch change, haptic once', (t) async {
      final haptics = _spyHaptics(t);
      final s = await _pump(t);
      s.router.go('/clients');
      await _settle(t, frames: 20);
      await _swipe(t, left: true);
      expect(s.path, '/clients'); // never advances to another branch
      expect(_navBranch(t), 3);
      expect(find.text('Reports'), findsOneWidget); // the More sheet's entries
      expect(find.text('Attendance'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
      // Closing More returns to Clients.
      await t.tapAt(const Offset(20, 60));
      await _settle(t);
      expect(find.text('Reports'), findsNothing);
      expect(s.path, '/clients');
      expect(_navBranch(t), 3);
    });

    testWidgets('a small pull past Clients springs back: no sheet, no haptic', (t) async {
      final haptics = _spyHaptics(t);
      final s = await _pump(t);
      s.router.go('/clients');
      await _settle(t, frames: 20);
      final g = await t.startGesture(t.getCenter(find.byType(PageView)));
      await g.moveBy(const Offset(-30, 0)); // crosses the touch slop
      await g.moveBy(const Offset(-40, 0)); // ~10% of 390, well below the 20% threshold
      await t.pump();
      // Mid-pull the page is nudged; it settles back on release.
      expect(t.getTopLeft(find.byType(PageView)).dx, lessThan(0));
      await g.up();
      await _settle(t);
      expect(t.getTopLeft(find.byType(PageView)).dx, 0);
      expect(find.text('Reports'), findsNothing);
      expect(haptics, isEmpty);
      expect(s.path, '/clients');
    });

    testWidgets('one long drag past Clients opens More once', (t) async {
      final haptics = _spyHaptics(t);
      final s = await _pump(t);
      s.router.go('/clients');
      await _settle(t, frames: 20);
      final g = await t.startGesture(t.getCenter(find.byType(PageView)));
      for (var i = 0; i < 14; i++) {
        await g.moveBy(const Offset(-30, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await _settle(t);
      expect(find.text('Reports'), findsOneWidget);
      expect(haptics, hasLength(1));
      expect(s.path, '/clients');
    });

    testWidgets('dragging past the Dashboard end does nothing', (t) async {
      final haptics = _spyHaptics(t);
      final s = await _pump(t);
      await _swipe(t, left: false);
      expect(s.path, '/dashboard');
      expect(find.text('Reports'), findsNothing);
      expect(haptics, isEmpty);
    });

    testWidgets('no swiping before Dashboard either', (t) async {
      final s = await _pump(t);
      await _swipe(t, left: false);
      expect(s.path, '/dashboard');
    });

    testWidgets('a pushed page never swipes to another tab, and back returns to the root', (t) async {
      final s = await _pump(t);
      s.router.go('/clients/42');
      await _settle(t, frames: 20);
      expect(find.text('detail 42'), findsOneWidget);

      await _swipe(t, left: true);
      await _swipe(t, left: false);
      expect(s.path, '/clients/42');

      await t.binding.handlePopRoute();
      await _settle(t, frames: 20);
      expect(s.path, '/clients');
      // Back at the root, swiping works again.
      await _swipe(t, left: false);
      expect(s.path, '/interactions');
    });

    testWidgets('a screen reached through More is not in the swipe row', (t) async {
      final s = await _pump(t);
      s.router.go('/attendance');
      await _settle(t, frames: 20);
      expect(find.text('attendance taps: 0'), findsOneWidget);
      await _swipe(t, left: true, at: find.byKey(const ValueKey('tap-attendance')));
      await _swipe(t, left: false, at: find.byKey(const ValueKey('tap-attendance')));
      expect(s.path, '/attendance');
      expect(_navBranch(t), 8);
    });

    testWidgets('an inner horizontal drag (chart) keeps its drag; swiping elsewhere changes page', (t) async {
      var chartDrags = 0;
      final s = await _pump(t, onChartDrag: () => chartDrags++);

      await t.fling(find.byKey(const ValueKey('fake-chart')), const Offset(-200, 0), 800);
      await _settle(t);
      expect(chartDrags, greaterThan(0));
      expect(s.path, '/dashboard');

      await _swipe(t, left: true, at: find.byKey(const ValueKey('empty-area')));
      expect(s.path, '/sales');
    });

    testWidgets('a PageSwipeGuard keeps a drag that starts on it from changing page', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(390, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          StatefulShellRoute(
            navigatorContainerBuilder: buildBranchContainer,
            builder: (c, s, shell) => AppShell(navigationShell: shell),
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/dashboard',
                  builder: (c, s) => const PageSwipeGuard(child: SizedBox.expand(key: ValueKey('guarded'))),
                ),
              ]),
              StatefulShellBranch(routes: [GoRoute(path: '/sales', builder: (c, s) => const SizedBox())]),
              StatefulShellBranch(routes: [GoRoute(path: '/interactions', builder: (c, s) => const SizedBox())]),
              StatefulShellBranch(routes: [GoRoute(path: '/clients', builder: (c, s) => const SizedBox())]),
            ],
          ),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [authProvider.overrideWith(_Auth.new), canMarkAttendanceProvider.overrideWithValue(false)],
          child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
        ),
      );
      addTearDown(() async => t.pumpWidget(const SizedBox()));
      await _settle(t);

      // A touch that has landed on the guard, then moves: no page change.
      final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('guarded'))));
      await t.pump(const Duration(milliseconds: 50));
      await g.moveBy(const Offset(-200, 0));
      await t.pump();
      await g.up();
      await _settle(t);
      expect(router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('state and scroll position survive swiping away and back', (t) async {
      final s = await _pump(t);
      await _swipe(t, left: true);
      expect(s.path, '/sales');

      await t.tap(find.byKey(const ValueKey('tap-sales')));
      await t.tap(find.byKey(const ValueKey('tap-sales')));
      await t.pump();
      await t.drag(find.byKey(const ValueKey('list-sales')), const Offset(0, -400));
      await _settle(t);
      final offset = t.widget<ListView>(find.byKey(const ValueKey('list-sales'))).controller!.offset;
      expect(offset, greaterThan(100));

      await _swipe(t, left: true); // interactions
      await _swipe(t, left: true); // clients
      await _swipe(t, left: false);
      await _swipe(t, left: false); // back to sales
      expect(s.path, '/sales');
      expect(find.text('sales taps: 2'), findsOneWidget);
      expect(t.widget<ListView>(find.byKey(const ValueKey('list-sales'))).controller!.offset, offset);
    });
  });

  group('PC layout is unchanged', () {
    testWidgets('no PageView, the sidebar is there, and there is no top bar', (t) async {
      final s = await _pump(t, size: const Size(1280, 800));
      expect(find.byType(PageView), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(AppBottomNav), findsNothing);
      s.router.go('/sales');
      await _settle(t);
      expect(find.byType(PageView), findsNothing);
      expect(find.text('sales taps: 0'), findsOneWidget);
    });

    testWidgets('dragging sideways does not change page', (t) async {
      final s = await _pump(t, size: const Size(1280, 800));
      await t.fling(find.byKey(const ValueKey('empty-area')), const Offset(-300, 0), 1200);
      await _settle(t);
      expect(s.path, '/dashboard');
    });
  });

  group('phone top bar', () {
    testWidgets('is transparent with no divider, tint or elevation, and dark status icons', (t) async {
      await _pump(t);
      final bar = t.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, Colors.transparent);
      expect(bar.surfaceTintColor, Colors.transparent);
      expect(bar.elevation, 0);
      expect(bar.scrolledUnderElevation, 0);
      // No bottom border line.
      final shape = bar.shape;
      expect(shape, isA<Border>());
      expect((shape! as Border).bottom, BorderSide.none);
      expect(bar.systemOverlayStyle?.statusBarColor, Colors.transparent);
      expect(bar.systemOverlayStyle?.statusBarIconBrightness, Brightness.dark);

      // The page background shows through: the scaffold paints it, and the bar
      // itself paints nothing over it.
      final material = t.widget<Material>(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Material)).first,
      );
      expect(material.color, Colors.transparent);
      expect(t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, AppColors.background);
    });

    testWidgets('keeps the logo and avatar, and content still starts below the bar', (t) async {
      await _pump(t);
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      final barBottom = t.getRect(find.byType(AppBar)).bottom;
      final pageTop = t.getTopLeft(find.byType(PageView)).dy;
      expect(pageTop, greaterThanOrEqualTo(barBottom - 0.5));
    });

    testWidgets('the logo is about 30% bigger than before (28 to 36), left-aligned and not clipped', (t) async {
      await _pump(t);
      final logo = find.descendant(of: find.byType(AppBar), matching: find.byType(Image));
      expect(kPhoneLogoHeight, greaterThanOrEqualTo(28 * 1.28));
      expect(t.widget<Image>(logo).height, kPhoneLogoHeight);
      expect(t.getSize(logo).height, kPhoneLogoHeight);
      expect(t.getRect(logo).top, greaterThanOrEqualTo(t.getRect(find.byType(AppBar)).top));
      expect(t.getRect(logo).bottom, lessThanOrEqualTo(t.getRect(find.byType(AppBar)).bottom));
      expect(t.getTopLeft(logo).dx, AppSpacing.lg); // still left-aligned
    });

    testWidgets('stays transparent on every phone branch, scrolled or not', (t) async {
      final s = await _pump(t);
      for (final path in ['/sales', '/attendance', '/profile']) {
        s.router.go(path);
        await _settle(t, frames: 20);
        final bar = t.widget<AppBar>(find.byType(AppBar));
        expect(bar.backgroundColor, Colors.transparent, reason: path);
        expect(bar.scrolledUnderElevation, 0, reason: path);
      }
    });
  });

  group('offscreen pages do not tick', () {
    testWidgets('only the page in view (and one mid-swipe) has tickers enabled', (t) async {
      final s = await _pump(t);
      bool tickerOf(Element e) {
        var result = false;
        void visit(Element c) {
          if (c.widget is TickerMode) {
            result = (c.widget as TickerMode).enabled;
            return;
          }
          c.visitChildren(visit);
        }

        e.visitChildren(visit);
        return result;
      }

      List<bool> enabled() => [
        for (final e in find
            .byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_PageTickerMode',
              skipOffstage: false,
            )
            .evaluate())
          tickerOf(e),
      ];
      expect(enabled(), [true]); // other pages are built on first visit

      await _swipe(t, left: true);
      expect(s.path, '/sales');
      expect(enabled(), [false, true]); // the Dashboard is kept alive, not ticking
    });
  });

  group('Dashboard ring follows the visible page', () {
    testWidgets('shown on the Dashboard only; the stream stops when swiped away and restarts on return', (t) async {
      final service = FakeAttendanceService();
      final location = FakeLocation();
      final s = await _pump(t, service: service, location: location);
      expect(find.byType(RingVisual), findsOneWidget);
      expect(location.watchStarts, 1);
      expect(location.watching, isTrue);

      // A real avatar sits to the right of the ring.
      expect(t.getCenter(find.byType(RingVisual)).dx, lessThan(t.getCenter(find.byType(CircleAvatar)).dx));

      await _swipe(t, left: true);
      expect(s.path, '/sales');
      expect(find.byType(RingVisual), findsNothing);
      expect(location.watchCancels, 1);
      expect(location.watching, isFalse);

      await _swipe(t, left: false);
      expect(s.path, '/dashboard');
      expect(find.byType(RingVisual), findsOneWidget);
      expect(location.watchStarts, 2);
      expect(location.watching, isTrue);
    });

    testWidgets('not shown on a PC layout or when attendance cannot be marked', (t) async {
      await _pump(t);
      expect(find.byType(RingVisual), findsNothing);
    });
  });
}
