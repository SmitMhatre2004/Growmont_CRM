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

  /// Test-only override — when set, [_init] opens this path instead of
  /// resolving via [AppPaths]. Lets unit tests point at an in-memory
  /// database (sqflite_common_ffi's `inMemoryDatabasePath`) instead of
  /// going through a path_provider platform channel, which isn't available
  /// in a plain `flutter test` run.
  @visibleForTesting
  static String? debugDatabasePathOverride;

  Future<Database> get database async => _db ??= await _init();

  /// Test-only: closes the cached database handle (if any) and clears it,
  /// so the next [database] access reopens a fresh one. Combined with
  /// [debugDatabasePathOverride], this gives each test a clean, isolated
  /// in-memory database.
  @visibleForTesting
  static Future<void> resetForTest() async {
    final db = _db;
    _db = null;
    if (db != null) {
      await db.close();
    }
  }

  Future<Database> _init() async {
    final path = debugDatabasePathOverride ?? await _resolveDbPath();
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async => _createTables(db),
      // All statements use IF NOT EXISTS, so re-running on every open is
      // safe and self-healing — no separate migration path needed yet.
      onOpen: (db) async => _createTables(db),
    );
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

  /// Copies growmont.db to a timestamped backup in the same directory.
  /// Meant to be called once per session, before the first pull. Keeps the
  /// 3 most recent backups; older ones are silently pruned.
  ///
  /// Errors are non-fatal — a backup failure must NEVER block startup or
  /// sync.
  Future<void> createPreSyncBackup() async {
    try {
      final dbPath = await _resolveDbPath();
      final src = File(dbPath);
      if (!src.existsSync()) return;

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
      await src.copy(dest.path);
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
