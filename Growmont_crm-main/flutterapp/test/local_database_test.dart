import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:growmont_crm/core/local/local_database.dart';
import 'package:growmont_crm/core/local/local_store.dart';

void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // A real file rather than an in-memory database: everything under test
  // here is about how the file on disk is opened and backed up.
  setUp(() async {
    await LocalDatabase.resetForTest();
    dir = await Directory.systemTemp.createTemp('growmont_db_test');
    dbPath = p.join(dir.path, 'growmont.db');
    LocalDatabase.debugDatabasePathOverride = dbPath;
  });

  tearDown(() async {
    await LocalDatabase.resetForTest();
    LocalDatabase.debugDatabasePathOverride = null;
    await dir.delete(recursive: true);
  });

  test('pre-sync backup leaves the database writable and captures its data',
      () async {
    await LocalStore.instance.putLocal('clients', 'c1', {'name': 'Acme'});

    await LocalDatabase.instance.createPreSyncBackup();

    // The old file-copy backup could leave the session's connection
    // read-only on Windows, failing every save after it.
    await LocalStore.instance.putLocal('clients', 'c2', {'name': 'Beta'});
    expect(await LocalStore.instance.byId('clients', 'c2'), isNotNull);

    final backups = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('growmont.backup.'))
        .toList();
    expect(backups, hasLength(1));

    final backup = await databaseFactoryFfi.openDatabase(
      backups.single.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final rows = await backup.query('documents', columns: ['doc_id']);
    await backup.close();
    expect(rows.map((r) => r['doc_id']), ['c1']);
  });

  test('concurrent first callers share one connection', () async {
    final dbs = await Future.wait([
      LocalDatabase.instance.database,
      LocalDatabase.instance.database,
    ]);
    expect(identical(dbs[0], dbs[1]), isTrue);
  });

  test('a connection that opens read-only is reopened once the file is '
      'writable again', () async {
    await LocalStore.instance.putLocal('clients', 'c1', {'name': 'Acme'});
    await LocalDatabase.resetForTest();

    // Stand-in for the file copy that used to hold growmont.db while it was
    // being opened: the read-only attribute sends SQLite down the same
    // silent fall-back-to-read-only path. Cleared before the first retry.
    await Process.run('attrib', ['+R', dbPath]);
    final opening = LocalDatabase.instance.database;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await Process.run('attrib', ['-R', dbPath]);
    await opening;

    await LocalStore.instance.putLocal('clients', 'c2', {'name': 'Beta'});
    expect(await LocalStore.instance.byId('clients', 'c2'), isNotNull);
  }, skip: !Platform.isWindows);
}
