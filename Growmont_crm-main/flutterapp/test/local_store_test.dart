import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:growmont_crm/core/local/local_database.dart';
import 'package:growmont_crm/core/local/local_store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // inMemoryDatabasePath opens a brand-new anonymous in-memory database
    // on every openDatabase() call, so pairing it with resetForTest() in
    // setUp() below gives each test a fully isolated database.
    LocalDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    await LocalDatabase.resetForTest();
  });

  final store = LocalStore.instance;

  test('putLocal then all() round-trips the document with dirty=1 semantics', () async {
    await store.putLocal('clients', 'c1', {'name': 'Acme'});
    final docs = await store.all('clients');

    expect(docs.length, 1);
    expect(docs.first['id'], 'c1');
    expect(docs.first['name'], 'Acme');

    final pending = await store.pending();
    expect(pending.length, 1);
    expect(pending.first.op, 'set');
    expect(pending.first.docId, 'c1');
  });

  test('putRemote does not overwrite a dirty row', () async {
    await store.putLocal('clients', 'c1', {'name': 'Local Edit'});
    await store.putRemote('clients', 'c1', {'name': 'Server Value'});

    final doc = await store.byId('clients', 'c1');
    expect(doc!['name'], 'Local Edit');
  });

  test('putRemote writes normally when the row is not dirty', () async {
    await store.putRemote('clients', 'c1', {'name': 'Server Value'});
    final doc = await store.byId('clients', 'c1');
    expect(doc!['name'], 'Server Value');
  });

  test('deleteLocal hides the row from all() but queues a delete op', () async {
    await store.putRemote('clients', 'c1', {'name': 'Acme'});
    await store.deleteLocal('clients', 'c1');

    final docs = await store.all('clients');
    expect(docs, isEmpty);

    final pending = await store.pending();
    expect(pending.length, 1);
    expect(pending.first.op, 'delete');
  });

  test('rapid putLocal calls collapse into a single outbox op', () async {
    await store.putLocal('sales', 's1', {'amount_paise': 100});
    await store.putLocal('sales', 's1', {'amount_paise': 200});
    await store.putLocal('sales', 's1', {'amount_paise': 300});

    final pending = await store.pending();
    expect(pending.length, 1);
    expect(pending.first.payload!['amount_paise'], 300);
  });

  test('reconcilePull deletes a vanished clean+synced row but spares a dirty one', () async {
    await store.putRemote('clients', 'clean', {'name': 'Clean'});
    await store.putRemote('clients', 'dirty', {'name': 'Dirty (server)'});
    await store.putLocal('clients', 'dirty', {'name': 'Dirty (local edit)'});

    // Server now only reports 'clean' — 'dirty' vanished from the snapshot,
    // but it has an unpushed local edit and must survive.
    await store.reconcilePull('clients', {'clean'});

    final clean = await store.byId('clients', 'clean');
    final dirty = await store.byId('clients', 'dirty');
    expect(clean, isNotNull);
    expect(dirty, isNotNull);
    expect(dirty!['name'], 'Dirty (local edit)');
  });

  test('reconcilePull spares a never-synced (offline-created) row', () async {
    // Created offline, never confirmed by the server (synced_at is still
    // null) — a pull that doesn't know about it yet must not delete it.
    await store.putLocal('clients', 'new1', {'name': 'Created offline'});

    await store.reconcilePull('clients', <String>{});

    final doc = await store.byId('clients', 'new1');
    expect(doc, isNotNull);
  });

  test('markPushed clears dirty and sets synced_at for a completed set', () async {
    await store.putLocal('clients', 'c1', {'name': 'Acme'});
    final pending = await store.pending();
    expect(pending.length, 1);

    await store.markPushed(pending.first.id, 'clients', 'c1');

    final remaining = await store.pending();
    expect(remaining, isEmpty);

    final count = await store.pendingCount();
    expect(count, 0);

    // Confirmed-synced document must now survive a reconcilePull that no
    // longer reports it deleted, i.e. it behaves like a normal clean row.
    final doc = await store.byId('clients', 'c1');
    expect(doc, isNotNull);
  });

  test('markPushed hard-deletes the local row for a completed delete', () async {
    await store.putRemote('clients', 'c1', {'name': 'Acme'});
    await store.deleteLocal('clients', 'c1');
    final pending = await store.pending();
    expect(pending.length, 1);

    await store.markPushed(pending.first.id, 'clients', 'c1');

    final doc = await store.byId('clients', 'c1');
    expect(doc, isNull);
  });

  test('markFailed increments attempts and records the error', () async {
    await store.putLocal('clients', 'c1', {'name': 'Acme'});
    final pending = await store.pending();
    await store.markFailed(pending.first.id, 'network unreachable');

    final after = await store.pending();
    expect(after.first.attempts, 1);
    expect(after.first.lastError, 'network unreachable');
  });
}
