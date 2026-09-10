// lib/core/local/crm_repository.dart
//
// Local-first facade over FirestoreService.
//
// Extends rather than wraps deliberately: every member this class does
// NOT override keeps its original network behavior, so all existing call
// sites (apiServiceProvider is declared Provider<FirestoreService>) keep
// compiling and behaving exactly as before. Only the members listed below
// are redirected through LocalStore.
//
// See LOCAL_FIRST_AND_UPDATER_PLAN.md §6 for the full design rationale —
// in particular §0 rule 4: nothing outside this file should need to change
// for local-first reads/writes to work.

import 'dart:async';

import '../../models/client.dart';
import '../../models/employee.dart';
import '../../models/interaction.dart';
import '../../models/reminder.dart';
import '../../models/sale.dart';
import '../firebase/firestore_service.dart';
import 'firestore_json.dart';
import 'local_store.dart';
import 'payload_normalizer.dart';
import 'sync_engine.dart';

class CrmRepository extends FirestoreService {
  CrmRepository({
    super.firestore,
    super.auth,
    super.functions,
    super.storage,
    super.devUid,
  });

  final LocalStore _store = LocalStore.instance;

  // ── Shared helpers ──────────────────────────────────────────────────

  /// Newest-first comparator over the models' ISO date strings. Mirrors
  /// FirestoreService's private _byDateDesc exactly (that one is
  /// unreachable from here since it's library-private).
  static int _byDateDesc(String a, String b) {
    final dateA = DateTime.tryParse(a);
    final dateB = DateTime.tryParse(b);
    if (dateA == null && dateB == null) return 0;
    if (dateA == null) return 1;
    if (dateB == null) return -1;
    return dateB.compareTo(dateA);
  }

  List<Reminder> _sortReminders(List<Reminder> reminders) {
    reminders.sort((a, b) {
      final byDate = _byDateDesc(a.date, b.date);
      return byDate != 0 ? byDate : b.time.compareTo(a.time);
    });
    return reminders;
  }

  /// Fetches a single doc directly from Firestore and caches it locally.
  /// Used as a fallback for a local cache-miss on getEmployee/getClient so
  /// a profile that hasn't synced yet still resolves. Returns null if the
  /// doc doesn't exist or the fetch fails (offline with no local copy).
  Future<Map<String, dynamic>?> _fetchAndCache(String collection, String id) async {
    try {
      final snap = await firestore.collection(collection).doc(id).get();
      if (!snap.exists) return null;
      final json = toJsonSafe(snap.data()!);
      await _store.putRemote(collection, id, json);
      return {...json, 'id': id};
    } catch (_) {
      return null;
    }
  }

  /// Reads the existing local document, merges [data] over it, strips the
  /// injected 'id' key, and normalizes — the shared shape behind every
  /// update* override. Throws if the document isn't in the local store;
  /// an update to a doc that was never read/created locally is a bug, not
  /// something to silently paper over by creating a new doc.
  Future<Map<String, dynamic>> _mergeForUpdate(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final existing = await _store.byId(collection, docId);
    if (existing == null) {
      throw Exception(
        'Cannot update $collection/$docId: not found in the local store.',
      );
    }
    final merged = {...existing, ...data}..remove('id');
    return PayloadNormalizer.forCollection(
      collection,
      merged,
      isCreate: false,
      currentUid: currentUid,
    );
  }

  void _drain() => unawaited(SyncEngine.instance.drainOutbox());

  // ── Employees (reads local; create/review/delete/provision stay online) ─

  @override
  Future<List<Employee>> getEmployees() async {
    final docs = await _store.all('employees');
    final employees = docs.map(Employee.fromJson).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return employees;
  }

  @override
  Future<Employee> getEmployee(dynamic id) async {
    final docId = id.toString();
    final local = await _store.byId('employees', docId);
    if (local != null) return Employee.fromJson(local);

    final fetched = await _fetchAndCache('employees', docId);
    if (fetched == null) {
      throw Exception('Employee not found');
    }
    return Employee.fromJson(fetched);
  }

  @override
  Future<List<EmployeeDropdown>> getEmployeesDropdown() async {
    final docs = await _store.all('employees');
    final list = docs.map(EmployeeDropdown.fromJson).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Future<void> updateEmployee(dynamic id, Map<String, dynamic> data) async {
    final docId = id.toString();
    final payload = await _mergeForUpdate('employees', docId, data);
    await _store.putLocal('employees', docId, payload);
    _drain();
  }

  // provisionPendingEmployee, reviewEmployee, createEmployee, deleteEmployee,
  // streamPendingReview: intentionally NOT overridden — these are
  // Cloud-Function-backed or admin-review flows with no offline semantics
  // and must stay live.

  // ── Clients ──────────────────────────────────────────────────────────

  @override
  Future<List<Client>> getClients({String? employeeId}) async {
    final docs = await _store.all('clients');
    var clients = docs.map(Client.fromJson).toList();
    if (employeeId != null && employeeId.isNotEmpty) {
      clients = clients.where((c) => c.employeeId == employeeId).toList();
    }
    clients.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return clients;
  }

  @override
  Future<Client> getClient(dynamic id) async {
    final docId = id.toString();
    final local = await _store.byId('clients', docId);
    if (local != null) return Client.fromJson(local);

    final fetched = await _fetchAndCache('clients', docId);
    if (fetched == null) {
      throw Exception('Client not found');
    }
    return Client.fromJson(fetched);
  }

  // getEmployeeClients is inherited unchanged — FirestoreService's
  // implementation calls this.getClients(employeeId: ...), which resolves
  // to the override above via normal virtual dispatch.

  @override
  Future<Client> createClient(Map<String, dynamic> data) async {
    final id = firestore.collection('clients').doc().id;
    final payload = PayloadNormalizer.forCollection(
      'clients',
      data,
      isCreate: true,
      currentUid: currentUid,
    );
    await _store.putLocal('clients', id, payload);
    _drain();
    return Client.fromJson(payload, id);
  }

  @override
  Future<Client> updateClient(dynamic id, Map<String, dynamic> data) async {
    final docId = id.toString();
    final payload = await _mergeForUpdate('clients', docId, data);
    await _store.putLocal('clients', docId, payload);
    _drain();
    return Client.fromJson(payload, docId);
  }

  @override
  Future<void> deleteClient(dynamic id) async {
    await _store.deleteLocal('clients', id.toString());
    _drain();
  }

  // ── Sales ────────────────────────────────────────────────────────────

  @override
  Future<List<Sale>> getSales({String? salesRepId, String? clientId}) async {
    final docs = await _store.all('sales');
    var sales = docs.map(Sale.fromJson).toList();
    if (salesRepId != null && salesRepId.isNotEmpty) {
      sales = sales.where((s) => s.salesRepId == salesRepId || s.salesRep == salesRepId).toList();
    }
    if (clientId != null && clientId.isNotEmpty) {
      sales = sales.where((s) => s.clientId == clientId).toList();
    }
    sales.sort((a, b) => _byDateDesc(a.date, b.date));
    return sales;
  }

  @override
  Future<List<Sale>> getEmployeeSales(dynamic id) {
    // Overridden because FirestoreService.getEmployeeSales queries
    // Firestore directly rather than delegating to getSales(), so it
    // would otherwise bypass the local store entirely.
    return getSales(salesRepId: id.toString());
  }

  @override
  Stream<List<Sale>> streamSales({String? salesRepId, String? clientId}) async* {
    yield await getSales(salesRepId: salesRepId, clientId: clientId);
    await for (final changed in _store.changes) {
      if (changed == 'sales') {
        yield await getSales(salesRepId: salesRepId, clientId: clientId);
      }
    }
  }

  @override
  Future<Sale> createSale(Map<String, dynamic> data) async {
    final id = firestore.collection('sales').doc().id;
    final payload = PayloadNormalizer.forCollection(
      'sales',
      data,
      isCreate: true,
      currentUid: currentUid,
    );
    await _store.putLocal('sales', id, payload);
    _drain();
    return Sale.fromJson(payload, id);
  }

  @override
  Future<Sale> updateSale(dynamic id, Map<String, dynamic> data) async {
    final docId = id.toString();
    final payload = await _mergeForUpdate('sales', docId, data);
    await _store.putLocal('sales', docId, payload);
    _drain();
    return Sale.fromJson(payload, docId);
  }

  @override
  Future<void> deleteSale(dynamic id) async {
    await _store.deleteLocal('sales', id.toString());
    _drain();
  }

  // ── Interactions ─────────────────────────────────────────────────────

  @override
  Future<List<Interaction>> getInteractions({
    String? employeeId,
    String? clientId,
  }) async {
    final docs = await _store.all('interactions');
    var interactions = docs.map(Interaction.fromJson).toList();
    if (employeeId != null && employeeId.isNotEmpty) {
      interactions = interactions
          .where((i) => i.employeeId == employeeId || i.employee == employeeId)
          .toList();
    }
    if (clientId != null && clientId.isNotEmpty) {
      interactions = interactions.where((i) => i.clientId == clientId).toList();
    }
    interactions.sort((a, b) => _byDateDesc(a.date, b.date));
    return interactions;
  }

  @override
  Stream<List<Interaction>> streamInteractions({
    String? employeeId,
    String? clientId,
  }) async* {
    yield await getInteractions(employeeId: employeeId, clientId: clientId);
    await for (final changed in _store.changes) {
      if (changed == 'interactions') {
        yield await getInteractions(employeeId: employeeId, clientId: clientId);
      }
    }
  }

  @override
  Future<Interaction> createInteraction(Map<String, dynamic> data) async {
    final id = firestore.collection('interactions').doc().id;
    final payload = PayloadNormalizer.forCollection(
      'interactions',
      data,
      isCreate: true,
      currentUid: currentUid,
    );
    await _store.putLocal('interactions', id, payload);
    _drain();
    return Interaction.fromJson(payload, id);
  }

  @override
  Future<Interaction> updateInteraction(dynamic id, Map<String, dynamic> data) async {
    final docId = id.toString();
    final payload = await _mergeForUpdate('interactions', docId, data);
    await _store.putLocal('interactions', docId, payload);
    _drain();
    return Interaction.fromJson(payload, docId);
  }

  @override
  Future<void> deleteInteraction(dynamic id) async {
    await _store.deleteLocal('interactions', id.toString());
    _drain();
  }

  // ── Reminders ────────────────────────────────────────────────────────

  @override
  Future<List<Reminder>> getReminders() async {
    if (currentUid == null) return [];
    final docs = await _store.all('reminders');
    final mine = docs.where((r) => r['employee_id'] == currentUid).toList();
    return _sortReminders(mine.map(Reminder.fromJson).toList());
  }

  @override
  Stream<List<Reminder>> streamReminders() async* {
    yield await getReminders();
    await for (final changed in _store.changes) {
      if (changed == 'reminders') {
        yield await getReminders();
      }
    }
  }

  @override
  Future<Reminder> createReminder(Map<String, dynamic> data) async {
    final id = firestore.collection('reminders').doc().id;
    final payload = PayloadNormalizer.forCollection(
      'reminders',
      data,
      isCreate: true,
      currentUid: currentUid,
    );
    await _store.putLocal('reminders', id, payload);
    _drain();
    return Reminder.fromJson(payload, id);
  }

  @override
  Future<Reminder> updateReminder(dynamic id, Map<String, dynamic> data) async {
    final docId = id.toString();
    final payload = await _mergeForUpdate('reminders', docId, data);
    await _store.putLocal('reminders', docId, payload);
    _drain();
    return Reminder.fromJson(payload, docId);
  }

  @override
  Future<void> deleteReminder(dynamic id) async {
    await _store.deleteLocal('reminders', id.toString());
    _drain();
  }

  // changePassword: intentionally NOT overridden — Firebase Auth call,
  // no offline semantics.
}
