import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/firestore_service.dart';
import 'package:growmont_crm/core/providers.dart';
import 'package:growmont_crm/core/storage/token_storage.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/features/clients/clients_list_screen.dart';
import 'package:growmont_crm/features/dashboard/dashboard_screen.dart';
import 'package:growmont_crm/features/dashboard/todo_widget.dart';
import 'package:growmont_crm/features/employees/employees_list_screen.dart';
import 'package:growmont_crm/features/info_portal/info_portal_screen.dart';
import 'package:growmont_crm/features/interactions/interactions_screen.dart';
import 'package:growmont_crm/features/profile/profile_screen.dart';
import 'package:growmont_crm/features/sales/sales_screen.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/employee.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/reminder.dart';
import 'package:growmont_crm/models/sale.dart';
import 'package:growmont_crm/models/user.dart';

class _FakeAdminAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      user: AppUser(
        id: 'admin_1',
        email: 'admin@growmont.com',
        name: 'Admin User',
        role: UserRole.admin,
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

  @override
  Future<Employee> getEmployee(dynamic id) async => const Employee(
        id: 'admin_1',
        name: 'Admin User',
        email: 'admin@growmont.com',
        mobileNo: '1234567890',
        gender: 'M',
        dob: '1990-01-01',
        role: 'admin',
      );

  @override
  Future<List<Sale>> getEmployeeSales(dynamic id) async => [];

  @override
  Future<List<Reminder>> getReminders() async => [
        const Reminder(
          id: 'rem_1',
          employee: 'admin_1',
          eventName: 'Follow up call',
          date: '2026-09-12',
          time: '10:00 AM',
          priority: 'MEDIUM',
          type: 'REGULAR',
        ),
      ];

  @override
  Future<List<Employee>> getEmployees() async => [];

  @override
  Stream<List<Sale>> streamSales({String? salesRepId, String? clientId}) =>
      Stream.value([]);

  @override
  Stream<List<Interaction>> streamInteractions({
    String? employeeId,
    String? clientId,
  }) =>
      Stream.value([]);

  @override
  Stream<List<Reminder>> streamReminders() => Stream.value([]);
}

class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage() : super(const FlutterSecureStorage());

  @override
  Future<String?> getStickyNotes() async => 'Test note';

  @override
  Future<void> saveStickyNotes(String notes) async {}
}

void main() {
  // Common landscape phone resolutions (including exact Android 2400x1080 with bars: 914.3x233.2 and 882.3x113.2)
  const landscapeSizes = [
    Size(914.3, 233.2),
    Size(882.3, 113.2),
    Size(872, 392),
    Size(840, 390),
    Size(800, 360),
    Size(640, 360),
    Size(640, 320),
    Size(800, 200),
    Size(600, 160),
  ];

  group('TodoWidget responsive tests', () {
    for (final width in [180.0, 220.0, 250.0, 280.0, 350.0]) {
      testWidgets('TodoWidget renders at width $width without overflow', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = Size(width + 40, 400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SizedBox(
                  width: width,
                  child: const TodoWidget(userId: 'user_1'),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('EmployeesListScreen landscape tests', () {
    for (final size in landscapeSizes) {
      testWidgets('EmployeesListScreen renders at ${size.width}x${size.height} without overflow', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
              apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: EmployeesListScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SalesScreen landscape tests', () {
    for (final size in landscapeSizes) {
      testWidgets('SalesScreen renders at ${size.width}x${size.height} without overflow', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
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
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('InteractionsScreen landscape tests', () {
    for (final size in landscapeSizes) {
      testWidgets('InteractionsScreen renders at ${size.width}x${size.height} without overflow', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
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
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('InfoPortalScreen landscape tests', () {
    for (final size in landscapeSizes) {
      testWidgets('InfoPortalScreen renders at ${size.width}x${size.height} without overflow', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
              apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: InfoPortalScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ClientsListScreen landscape tests', () {
    for (final size in landscapeSizes) {
      testWidgets('ClientsListScreen renders at ${size.width}x${size.height} without overflow', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
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
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('DashboardScreen landscape tests', () {
    for (final size in landscapeSizes) {
      testWidgets('DashboardScreen renders at ${size.width}x${size.height} without overflow', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
              apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
              tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: DashboardScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ProfileScreen landscape tests', () {
    for (final size in landscapeSizes) {
      testWidgets(
        'ProfileScreen renders at ${size.width}x${size.height} without overflow',
        (WidgetTester tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
                apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
                tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
              ],
              child: MaterialApp(
                theme: AppTheme.light,
                home: const Scaffold(
                  body: ProfileScreen(),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'ProfileScreen on Reminders tab at 882.3x113.2 renders without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(882.3, 113.2);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
              apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
              tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: ProfileScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        final remindersChip = find.textContaining('Reminders');
        expect(remindersChip, findsOneWidget);
        await tester.tap(remindersChip);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ProfileScreen with My Info toggled at 882.3x113.2 renders without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(882.3, 113.2);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
              apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
              tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: ProfileScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        final myInfoBtn = find.text('My Info');
        if (myInfoBtn.evaluate().isNotEmpty) {
          await tester.tap(myInfoBtn);
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ProfileScreen with My Info toggled at 379.4x728.0 (portrait) renders without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(379.4, 728.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAdminAuthNotifier()),
              apiServiceProvider.overrideWithValue(_FakeFirestoreService()),
              tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: ProfileScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        final myInfoBtn = find.text('My Info');
        if (myInfoBtn.evaluate().isNotEmpty) {
          await tester.tap(myInfoBtn);
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
      },
    );
  });
}
