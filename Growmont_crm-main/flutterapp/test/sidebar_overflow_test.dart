import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/models/user.dart';
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
  testWidgets('AppSidebar renders at various widths without RenderFlex overflow', (
    WidgetTester tester,
  ) async {
    for (final width in [80.0, 100.0, 140.0, 160.0, 195.0]) {
      for (final isCompact in [true, false, null]) {
        final router = GoRouter(
          initialLocation: '/dashboard',
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => Scaffold(
                body: SizedBox(
                  width: width,
                  height: 800,
                  child: AppSidebar(isCompact: isCompact),
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

        expect(
          tester.takeException(),
          isNull,
          reason: 'Failed at width $width, isCompact $isCompact',
        );
      }
    }
  });

  testWidgets('AppSidebar smoothly transitions between collapsed and expanded without error', (
    WidgetTester tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const Scaffold(
            body: SizedBox(
              width: 220,
              height: 800,
              child: AppSidebar(),
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

    // Verify toggle icon is found
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
