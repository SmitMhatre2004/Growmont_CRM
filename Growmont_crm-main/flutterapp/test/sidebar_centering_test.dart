import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/models/user.dart';
import 'package:growmont_crm/shared/widgets/app_shell.dart';
import 'package:growmont_crm/shared/widgets/app_sidebar.dart';

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      user: AppUser(
        id: '1',
        email: 'admin@growmont.com',
        name: 'Admin User',
        role: UserRole.admin,
      ),
    );
  }
}

void main() {
  testWidgets('Check icon center positions when collapsed in AppSidebar', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const Scaffold(
            body: SizedBox(
              width: 80,
              height: 800,
              child: AppSidebar(isCompact: true),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          sidebarCollapsedProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sidebarFinder = find.byType(AppSidebar);
    final sidebarRect = tester.getRect(sidebarFinder);

    final iconFinders = find.byType(Icon);
    for (final iconFinder in iconFinders.evaluate()) {
      final rect = tester.getRect(find.byWidget(iconFinder.widget));
      final icon = iconFinder.widget as Icon;
      final offset = (rect.center.dx - sidebarRect.center.dx).abs();
      expect(offset, lessThan(0.01), reason: 'Icon ${icon.icon} is not centered');
    }

    final avatarFinder = find.byType(CircleAvatar);
    for (final avatar in avatarFinder.evaluate()) {
      final rect = tester.getRect(find.byWidget(avatar.widget));
      final offset = (rect.center.dx - sidebarRect.center.dx).abs();
      expect(offset, lessThan(0.01), reason: 'CircleAvatar is not centered');
    }
  });

  testWidgets('Check icon center positions when collapsed in AppShell', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AppShell(
            navigationShell: navigationShell,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/dashboard',
                  builder: (context, state) => const SizedBox(),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          sidebarCollapsedProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sidebarFinder = find.byType(AppSidebar);
    final sidebarRect = tester.getRect(sidebarFinder);

    final iconFinders = find.byType(Icon);
    for (final iconFinder in iconFinders.evaluate()) {
      final rect = tester.getRect(find.byWidget(iconFinder.widget));
      final icon = iconFinder.widget as Icon;
      final offset = (rect.center.dx - sidebarRect.center.dx).abs();
      expect(offset, lessThan(0.01), reason: 'AppShell Icon ${icon.icon} is not centered');
    }

    final avatarFinder = find.byType(CircleAvatar);
    for (final avatar in avatarFinder.evaluate()) {
      final rect = tester.getRect(find.byWidget(avatar.widget));
      final offset = (rect.center.dx - sidebarRect.center.dx).abs();
      expect(offset, lessThan(0.01), reason: 'AppShell CircleAvatar is not centered');
    }
  });

  testWidgets('Icon positions move directly and monotonically during collapse without overshoot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final widths = [195.0, 160.0, 130.0, 100.0, 80.0];
    final salesIconCenters = <double>[];

    for (final w in widths) {
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => Scaffold(
              body: SizedBox(
                width: w,
                height: 800,
                child: const AppSidebar(isCompact: false),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _FakeAuthNotifier()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find Sales icon (inactive, so no active nudge)
      final salesIconFinder = find.byIcon(Icons.bar_chart_outlined);
      final rect = tester.getRect(salesIconFinder);
      salesIconCenters.add(rect.center.dx);
    }

    // Sales icon center should move smoothly and monotonically from expanded (37.5) to collapsed (40.0)
    // without ever exceeding 40.0 or overshooting
    for (int i = 0; i < salesIconCenters.length - 1; i++) {
      expect(
        salesIconCenters[i] <= salesIconCenters[i + 1] + 0.01,
        isTrue,
        reason: 'Icon center moved backwards/overshot: $salesIconCenters',
      );
      expect(
        salesIconCenters[i] <= 40.01,
        isTrue,
        reason: 'Icon center swung past 40.0: $salesIconCenters',
      );
    }
  });
}
