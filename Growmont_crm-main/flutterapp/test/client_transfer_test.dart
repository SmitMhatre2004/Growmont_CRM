import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/firestore_service.dart';
import 'package:growmont_crm/core/providers.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/features/clients/client_detail_screen.dart';
import 'package:growmont_crm/features/clients/widgets/transfer_client_modal.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/client_transfer.dart';
import 'package:growmont_crm/models/employee.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';
import 'package:growmont_crm/models/user.dart';

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._user);
  final AppUser _user;

  @override
  AuthState build() {
    return AuthState(user: _user, isLoading: false);
  }
}

class FakeTransferService implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final List<ClientTransfer> _transfers = [];
  final Map<String, Client> _clients = {};

  void seedClient(Client client) {
    _clients[client.id] = client;
  }

  void seedTransfer(ClientTransfer transfer) {
    _transfers.add(transfer);
  }

  @override
  Future<Client> getClient(dynamic id) async {
    final client = _clients[id.toString()];
    if (client != null) return client;
    return Client(
      id: id.toString(),
      name: 'Test Client',
      contactNumber: '9876543210',
      employeeId: 'emp_1',
      employeeName: 'Rahul Verma',
    );
  }

  @override
  Future<List<Sale>> getSales({String? salesRepId, String? clientId}) async => [];

  @override
  Future<List<Interaction>> getInteractions({String? employeeId, String? clientId}) async => [];

  @override
  Future<List<ClientTransfer>> getClientTransfers(String clientId) async {
    return _transfers.where((t) => t.clientId == clientId).toList()
      ..sort((a, b) => b.transferredAt.compareTo(a.transferredAt));
  }

  @override
  Future<List<EmployeeDropdown>> getEmployeesDropdown() async {
    return const [
      EmployeeDropdown(id: 'emp_1', name: 'Rahul Verma', role: 'EMPLOYEE'),
      EmployeeDropdown(id: 'emp_2', name: 'Priya Sharma', role: 'EMPLOYEE'),
      EmployeeDropdown(id: 'admin_1', name: 'Smit Mhatre', role: 'ADMIN'),
    ];
  }

  final List<String> _customReasons = [];

  @override
  Future<List<String>> getTransferReasons() async {
    return _customReasons.toList();
  }

  @override
  Future<void> saveTransferReason(String reason) async {
    final trimmed = reason.trim();
    if (trimmed.isNotEmpty && !_customReasons.contains(trimmed)) {
      _customReasons.add(trimmed);
    }
  }

  @override
  Future<ClientTransfer> transferClient({
    required String clientId,
    required String clientName,
    required String fromEmployeeId,
    required String fromEmployeeName,
    required String toEmployeeId,
    required String toEmployeeName,
    required String transferredById,
    required String transferredByName,
    required String transferredByRole,
    String reason = '',
    String notes = '',
  }) async {
    final transfer = ClientTransfer(
      id: 'tr_${DateTime.now().millisecondsSinceEpoch}',
      clientId: clientId,
      clientName: clientName,
      fromEmployeeId: fromEmployeeId,
      fromEmployeeName: fromEmployeeName,
      toEmployeeId: toEmployeeId,
      toEmployeeName: toEmployeeName,
      transferredById: transferredById,
      transferredByName: transferredByName,
      transferredByRole: transferredByRole,
      transferredAt: DateTime.now().toIso8601String(),
      reason: reason,
      notes: notes,
    );
    _transfers.add(transfer);

    final existing = _clients[clientId];
    if (existing != null) {
      _clients[clientId] = existing.copyWith(
        employeeId: toEmployeeId,
        employeeName: toEmployeeName,
      );
    }

    return transfer;
  }
}

void main() {
  group('ClientTransfer Model Tests', () {
    test('ClientTransfer serialization and deserialization roundtrip', () {
      final transfer = ClientTransfer(
        id: 't_123',
        clientId: 'c_456',
        clientName: 'Sunita Enterprises',
        fromEmployeeId: 'emp_1',
        fromEmployeeName: 'Rahul Verma',
        toEmployeeId: 'emp_2',
        toEmployeeName: 'Priya Sharma',
        transferredById: 'admin_1',
        transferredByName: 'Admin User',
        transferredByRole: 'ADMIN',
        transferredAt: '2026-09-29T10:00:00Z',
        reason: 'Workload Rebalancing',
        notes: 'Handover complete. Client prefers evening updates.',
      );

      final json = transfer.toJson();
      expect(json['client_id'], equals('c_456'));
      expect(json['from_employee_name'], equals('Rahul Verma'));
      expect(json['to_employee_name'], equals('Priya Sharma'));
      expect(json['transferred_by_role'], equals('ADMIN'));

      final restored = ClientTransfer.fromJson(json, 't_123');
      expect(restored.id, equals('t_123'));
      expect(restored.clientName, equals('Sunita Enterprises'));
      expect(restored.fromEmployeeId, equals('emp_1'));
      expect(restored.toEmployeeId, equals('emp_2'));
      expect(restored.reason, equals('Workload Rebalancing'));
      expect(restored.notes, equals('Handover complete. Client prefers evening updates.'));
    });
  });

  group('Client Transfer Role Access Tests', () {
    const adminUser = AppUser(
      id: 'admin_1',
      name: 'Admin Boss',
      email: 'admin@growmont.com',
      role: UserRole.admin,
    );

    const ownerEmployee = AppUser(
      id: 'emp_1',
      name: 'Rahul Verma',
      email: 'rahul@growmont.com',
      role: UserRole.employee,
    );

    const otherEmployee = AppUser(
      id: 'emp_2',
      name: 'Priya Sharma',
      email: 'priya@growmont.com',
      role: UserRole.employee,
    );

    const testClient = Client(
      id: 'client_001',
      name: 'Acme Corp',
      contactNumber: '9876500000',
      employeeId: 'emp_1',
      employeeName: 'Rahul Verma',
    );

    testWidgets('Admin can access transfer form for any client', (tester) async {
      final fakeService = FakeTransferService()..seedClient(testClient);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: TransferClientModal(
                client: testClient,
                currentUser: adminUser,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transfer Client Ownership'), findsOneWidget);
      expect(find.text('Admin Transfer'), findsOneWidget);
      expect(find.text('Confirm Transfer'), findsOneWidget);
      expect(find.text('Transfer Restricted'), findsNothing);
    });

    testWidgets('Employee can transfer their OWN client', (tester) async {
      final fakeService = FakeTransferService()..seedClient(testClient);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: TransferClientModal(
                client: testClient,
                currentUser: ownerEmployee,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transfer Client Ownership'), findsOneWidget);
      expect(find.text('Staff Handover'), findsOneWidget);
      expect(find.text('Confirm Transfer'), findsOneWidget);
      expect(find.text('Transfer Restricted'), findsNothing);
    });

    testWidgets('Employee CANNOT transfer client belonging to another employee', (tester) async {
      final fakeService = FakeTransferService()..seedClient(testClient);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: TransferClientModal(
                client: testClient,
                currentUser: otherEmployee,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transfer Restricted'), findsOneWidget);
      expect(find.textContaining('you can only transfer clients currently assigned to you'), findsOneWidget);
      expect(find.text('Confirm Transfer'), findsNothing);
    });
  });

  group('ClientDetailScreen Transfer Section Tests', () {
    const adminUser = AppUser(
      id: 'admin_1',
      name: 'Admin User',
      email: 'admin@growmont.com',
      role: UserRole.admin,
    );

    const testClient = Client(
      id: 'client_001',
      name: 'Rajesh Trading Co',
      contactNumber: '9123456789',
      employeeId: 'emp_1',
      employeeName: 'Rahul Verma',
    );

    final sampleTransfer = ClientTransfer(
      id: 'tr_1',
      clientId: 'client_001',
      clientName: 'Rajesh Trading Co',
      fromEmployeeId: 'emp_1',
      fromEmployeeName: 'Rahul Verma',
      toEmployeeId: 'emp_2',
      toEmployeeName: 'Priya Sharma',
      transferredById: 'admin_1',
      transferredByName: 'Admin User',
      transferredByRole: 'ADMIN',
      transferredAt: '2026-09-29T14:30:00Z',
      reason: 'Territory Reassignment',
      notes: 'Please introduce yourself on call tomorrow morning.',
    );

    testWidgets('ClientDetailScreen displays Ownership & Transfer History section with timeline', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeService = FakeTransferService()
        ..seedClient(testClient)
        ..seedTransfer(sampleTransfer);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeService),
            authProvider.overrideWith(() => _FakeAuthNotifier(adminUser)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: ClientDetailScreen(clientId: 'client_001'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify transfer section is present
      expect(find.text('Transfer History'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);

      // Verify transfer details are visible
      expect(find.text('Rahul Verma'), findsWidgets);
      expect(find.textContaining('Rahul Verma  →  Priya Sharma'), findsOneWidget);
      expect(find.textContaining('Territory Reassignment'), findsOneWidget);
      expect(find.text('Please introduce yourself on call tomorrow morning.'), findsOneWidget);
    });
  });

  group('Transfer Reason Dropdown & Custom Creation Tests', () {
    const adminUser = AppUser(
      id: 'admin_1',
      name: 'Admin User',
      email: 'admin@growmont.com',
      role: UserRole.admin,
    );

    const testClient = Client(
      id: 'client_001',
      name: 'Acme Corp',
      contactNumber: '9876500000',
      employeeId: 'emp_1',
      employeeName: 'Rahul Verma',
    );

    testWidgets('User can create and save a new custom transfer reason dynamically', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeService = FakeTransferService()..seedClient(testClient);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: TransferClientModal(
                client: testClient,
                currentUser: adminUser,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click on 'Add Custom Reason'
      expect(find.text('Add Custom Reason'), findsOneWidget);
      await tester.tap(find.text('Add Custom Reason'));
      await tester.pumpAndSettle();

      // Input custom reason
      expect(find.text('New Reason Title'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('new_reason_field')), 'Relocated to Pune Branch');
      await tester.pumpAndSettle();

      // Click 'Save & Select'
      await tester.tap(find.text('Save & Select'));
      await tester.pumpAndSettle();

      // Reason should now be in the service's stored reasons
      final savedReasons = await fakeService.getTransferReasons();
      expect(savedReasons, contains('Relocated to Pune Branch'));

      // And the dropdown should now display 'Relocated to Pune Branch'
      expect(find.text('Relocated to Pune Branch'), findsWidgets);

      // Open the dropdown to inspect the options
      await tester.tap(find.text('Relocated to Pune Branch'));
      await tester.pumpAndSettle();

      // Ensure no double plus exists and single item exists
      expect(find.text('+ + Create New Reason...'), findsNothing);
      expect(find.text('Create New Reason...'), findsOneWidget);
    });
  });
}

