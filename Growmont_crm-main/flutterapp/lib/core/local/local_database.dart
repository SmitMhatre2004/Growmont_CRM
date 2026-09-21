// lib/core/local/local_database.dart
//
// The local-first document store's underlying SQLite database
// (growmont.db). One generic `documents` table holds every Firestore
// collection's docs as JSON, plus an outbox (`sync_pending`) and a small
// key/value table (`sync_meta`) for sync bookkeeping.
//
// See LOCAL_FIRST_AND_UPDATER_PLAN.md §3 for the full design rationale.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../storage/app_paths.dart';

class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();

  static Database? _db;
  static Future<Database>? _opening;

  /// Test-only override — when set, [_init] opens this path instead of
  /// resolving via [AppPaths]. Lets unit tests point at an in-memory
  /// database (sqflite_common_ffi's `inMemoryDatabasePath`) instead of
  /// going through a path_provider platform channel, which isn't available
  /// in a plain `flutter test` run.
  @visibleForTesting
  static String? debugDatabasePathOverride;

  /// Shared by every caller. The first open is memoized, not just its
  /// result: at startup many LocalStore calls arrive at once, and [_init]
  /// may close and reopen the connection, which must not happen underneath
  /// another caller already holding it.
  Future<Database> get database {
    final db = _db;
    if (db != null) return Future.value(db);
    return _opening ??= _init().then((db) {
      _db = db;
      return db;
    }).whenComplete(() => _opening = null);
  }

  /// Test-only: closes the cached database handle (if any) and clears it,
  /// so the next [database] access reopens a fresh one. Combined with
  /// [debugDatabasePathOverride], this gives each test a clean, isolated
  /// in-memory database.
  @visibleForTesting
  static Future<void> resetForTest() async {
    final db = _db;
    _db = null;
    _opening = null;
    if (db != null) {
      await db.close();
    }
  }

  static const _maxOpenAttempts = 5;

  Future<Database> _init() async {
    final path = debugDatabasePathOverride ?? await _resolveDbPath();
    for (var attempt = 1;; attempt++) {
      final db = await openDatabase(
        path,
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async => _createTables(db),
        // All statements use IF NOT EXISTS, so re-running on every open is
        // safe and self-healing — no separate migration path needed yet.
        onOpen: (db) async => _createTables(db),
      );
      if (await _isWritable(db)) return db;

      if (attempt == _maxOpenAttempts) {
        // Reads still work, so the app can at least show its data; every
        // write will report the read-only error.
        debugPrint('LocalDatabase: $path is still read-only after '
            '$attempt attempts');
        return db;
      }
      debugPrint('LocalDatabase: $path opened read-only, reopening '
          '(attempt $attempt)');
      await db.close();
      await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
    }
  }

  /// Whether [db] can actually write.
  ///
  /// On Windows, SQLite does not fail when growmont.db cannot be opened for
  /// writing at the instant it is opened — say another handle holds it
  /// without write sharing, as a file copy does. It silently opens the file
  /// read-only instead, and every write for the rest of the session then
  /// fails with "attempt to write a readonly database". `openDatabase`
  /// cannot tell; this can.
  ///
  /// It has to be a real row write: such a connection still accepts
  /// BEGIN IMMEDIATE and COMMIT, and only refuses once a page is actually
  /// written. The transaction is always rolled back, so nothing is kept.
  static Future<bool> _isWritable(Database db) async {
    try {
      await db.transaction((txn) async {
        await txn.insert(
          'sync_meta',
          {'key': '_write_probe', 'value': ''},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        throw const _RollBack();
      });
    } on _RollBack {
      return true;
    } on DatabaseException catch (e) {
      // Anything else — e.g. busy because another instance is writing —
      // says nothing about this connection's own access.
      return !e.isReadOnlyError();
    }
  }

  /// Resolves the absolute path to `growmont.db`.
  ///
  /// Desktop (Windows/Linux/macOS): resolved via [AppPaths], which uses
  /// path_provider's application-support directory instead of the install
  /// folder — see app_paths.dart for why that matters.
  ///
  /// Android/iOS: unchanged. The native sqflite plugin's `getDatabasesPath()`
  /// already returns a correct, sandboxed, app-private directory there.
  static Future<String> _resolveDbPath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return AppPaths.childPath('growmont.db');
    }
    return p.join(await getDatabasesPath(), 'growmont.db');
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        collection  TEXT    NOT NULL,
        doc_id      TEXT    NOT NULL,
        payload     TEXT    NOT NULL,
        updated_at  TEXT,
        is_deleted  INTEGER NOT NULL DEFAULT 0,
        deleted_at  TEXT,
        synced_at   TEXT,
        dirty       INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (collection, doc_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_documents_collection ON documents(collection, is_deleted)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_documents_dirty ON documents(dirty)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_pending (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        collection  TEXT    NOT NULL,
        doc_id      TEXT    NOT NULL,
        op          TEXT    NOT NULL,
        payload     TEXT,
        created_at  TEXT    NOT NULL,
        attempts    INTEGER NOT NULL DEFAULT 0,
        last_error  TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_target ON sync_pending(collection, doc_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  /// Writes a timestamped backup of growmont.db to the same directory.
  /// Meant to be called once per session, before the first pull. Keeps the
  /// 3 most recent backups; older ones are silently pruned.
  ///
  /// The backup is taken with VACUUM INTO, through the open connection —
  /// not by copying the file. On Windows a file copy holds the source
  /// without write sharing, and sync starts this in the same second the UI
  /// first opens the database: if the open landed mid-copy, SQLite silently
  /// fell back to read-only and every save failed for the whole session.
  /// Going through the connection also means the backup is a consistent
  /// snapshot rather than a copy of a file that may be mid-write.
  ///
  /// Errors are non-fatal — a backup failure must NEVER block startup or
  /// sync.
  Future<void> createPreSyncBackup() async {
    try {
      final dbPath = debugDatabasePathOverride ?? await _resolveDbPath();
      final src = File(dbPath);
      if (!src.existsSync()) return;

      final db = await database;
      final backupDir = src.parent;

      // Timestamp format: 2026-03-01T08-30-00 (colons replaced so it's a
      // valid filename on Windows and Linux).
      final ts = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;

      final dest = File(p.join(backupDir.path, 'growmont.backup.$ts.db'));
      try {
        await db.execute('VACUUM INTO ?', [dest.path]);
      } on DatabaseException {
        // SQLite before 3.27 has no VACUUM INTO — the system SQLite on
        // Android 10 and older. A file copy is harmless there (no share
        // modes), and anywhere else it is now safe too: the connection
        // above is already open, so a copy can no longer downgrade it.
        await src.copy(dest.path);
      }
      debugPrint('LocalDatabase.createPreSyncBackup: wrote ${dest.path}');

      // Prune: keep only the 3 most recent backups (newest first by
      // filename, which sorts correctly since the timestamp is ISO-ordered).
      final backups = backupDir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = p.basename(f.path);
            return name.startsWith('growmont.backup.') && name.endsWith('.db');
          })
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));

      for (final old in backups.skip(3)) {
        old.deleteSync();
        debugPrint('LocalDatabase.createPreSyncBackup: pruned ${old.path}');
      }
    } catch (e) {
      debugPrint('LocalDatabase.createPreSyncBackup error (non-fatal): $e');
    }
  }
}

/// Thrown inside [LocalDatabase._isWritable]'s probe transaction purely to
/// make sqflite roll it back.
class _RollBack implements Exception {
  const _RollBack();
}
