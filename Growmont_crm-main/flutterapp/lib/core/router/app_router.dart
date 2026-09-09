import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/employees/employee_detail_screen.dart';
import '../../features/employees/employees_list_screen.dart';
import '../../features/info_portal/info_portal_screen.dart';
import '../../features/interactions/interactions_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/sales/sales_screen.dart';
import '../../shared/widgets/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefreshListenable(ref),
    redirect: (context, state) {
      final isLoading = auth.isLoading;
      final isLoggedIn = auth.isAuthenticated;
      final isLoginRoute = state.matchedLocation == '/';

      if (isLoading) return null;

      if (!isLoggedIn && !isLoginRoute) return '/';
      if (isLoggedIn && isLoginRoute) return '/dashboard';

      final adminOnly = ['/employees', '/info-portal'];
      if (isLoggedIn &&
          auth.user?.isAdmin == false &&
          adminOnly.any((p) => state.matchedLocation.startsWith(p))) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: LoginScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: DashboardScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sales',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SalesScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/interactions',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: InteractionsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/employees',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: EmployeesListScreen()),
                routes: [
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return NoTransitionPage(
                        child: EmployeeDetailScreen(employeeId: id),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/info-portal',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: InfoPortalScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) {
                  final tab = state.uri.queryParameters['tab'];
                  return NoTransitionPage(
                    child: ProfileScreen(initialTab: tab),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: AppSizing.iconEmptyState,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Page not found: ${state.uri}'),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
});

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this.ref) {
    ref.listen(authProvider, (_, next) => notifyListeners());
  }

  final Ref ref;
}
