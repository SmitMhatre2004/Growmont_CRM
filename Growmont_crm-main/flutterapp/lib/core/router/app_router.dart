import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/sales',
            builder: (context, state) => const SalesScreen(),
          ),
          GoRoute(
            path: '/interactions',
            builder: (context, state) => const InteractionsScreen(),
          ),
          GoRoute(
            path: '/employees',
            builder: (context, state) => const EmployeesListScreen(),
          ),
          GoRoute(
            path: '/employees/:id',
            builder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return EmployeeDetailScreen(employeeId: id);
            },
          ),
          GoRoute(
            path: '/info-portal',
            builder: (context, state) => const InfoPortalScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) {
              final tab = state.uri.queryParameters['tab'];
              return ProfileScreen(initialTab: tab);
            },
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Page not found: ${state.uri}'),
            const SizedBox(height: 16),
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
    ref.listen(authProvider, (_, __) => notifyListeners());
  }

  final Ref ref;
}
