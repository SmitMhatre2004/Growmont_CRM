import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/firestore_service.dart';
import 'package:growmont_crm/core/providers.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/features/sales/sales_screen.dart';
import 'package:growmont_crm/features/clients/clients_list_screen.dart';
import 'package:growmont_crm/features/interactions/interactions_screen.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';
import 'package:growmont_crm/models/user.dart';

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      user: AppUser(
        id: 'user_1',
        email: 'rep@growmont.com',
        name: 'Sales Rep',
        role: UserRole.employee,
      ),
    );
  }
}

class _FakeFirestoreService implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<Sale>> getSales({String? salesRepId, String? clientId}) async => [];

  @override
  Future<List<Client>> getClients({String? employeeId}) async => [];

  @override
  Future<List<Interaction>> getInteractions({
    String? employeeId,
    String? clientId,
  }) async => [];
}

void main() {
  testWidgets('SalesScreen renders empty state at small phone viewport without RenderFlex overflow', (
    WidgetTester tester,
  ) async {
    const size = Size(320, 640);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SalesScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(SalesScreen), findsOneWidget);
    expect(find.text('No sales recorded yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SalesScreen renders empty state at ultra-compact height (180px available) without overflow', (
    WidgetTester tester,
  ) async {
    const size = Size(320, 480);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SalesScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(SalesScreen), findsOneWidget);
    expect(find.text('No sales recorded yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ClientsListScreen renders empty state at small phone viewport without overflow', (
    WidgetTester tester,
  ) async {
    const size = Size(320, 480);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: ClientsListScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ClientsListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('InteractionsScreen renders empty state at small phone viewport without overflow', (
    WidgetTester tester,
  ) async {
    const size = Size(320, 480);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: InteractionsScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(InteractionsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
