// lib/core/local/local_store.dart
//
// The only class that touches the `documents` / `sync_pending` tables
// directly. Everything else (CrmRepository, SyncEngine) goes through here.
//
// See LOCAL_FIRST_AND_UPDATER_PLAN.md §3.2 for the full contract.

import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'local_database.dart';
import 'sync_models.dart';

class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();

  final _changes = StreamController<String>.broadcast();

  /// Broadcast of collection names that just changed locally (a local
  /// write, a remote pull, or a reconciliation). CrmRepository's streams
  /// listen to this and re-query.
  Stream<String> get changes => _changes.stream;

  String get _now => DateTime.now().toUtc().toIso8601String();

  // ── Reads ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> all(String collection) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'documents',
      where: 'collection = ? AND is_deleted = 0',
      whereArgs: [collection],
    );
    return rows.map(_decodeRow).toList();
  }

  Future<Map<String, dynamic>?> byId(String collection, String id) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'documents',
      where: 'collection = ? AND doc_id = ? AND is_deleted = 0',
      whereArgs: [collection, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decodeRow(rows.first);
  }

  Map<String, dynamic> _decodeRow(Map<String, dynamic> row) {
    final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    return {...payload, 'id': row['doc_id']};
  }

  // ── Local writes (dirty = 1, queued) ────────────────────────────────

  Future<void> putLocal(
    String collection,
    String id,
    Map<String, dynamic> json,
  ) async {
    final db = await LocalDatabase.instance.database;
    final now = _now;
    final payload = jsonEncode(json);

    await db.insert(
      'documents',
      {
        'collection': collection,
        'doc_id': id,
        'payload': payload,
        'updated_at': now,
        'is_deleted': 0,
        'deleted_at': null,
        'synced_at': null,
        'dirty': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _enqueueSet(db, collection, id, payload, now);
    _changes.add(collection);
  }

  Future<void> _enqueueSet(
    DatabaseExecutor db,
    String collection,
    String id,
    String payload,
    String now,
  ) async {
    // Collapse with an existing un-attempted 'set' op for the same
    // document instead of piling up redundant pushes on rapid edits.
    final existing = await db.query(
      'sync_pending',
      where: "collection = ? AND doc_id = ? AND op = 'set' AND attempts = 0",
      whereArgs: [collection, id],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'sync_pending',
        {'payload': payload, 'created_at': now},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      return;
    }
    await db.insert('sync_pending', {
      'collection': collection,
      'doc_id': id,
      'op': 'set',
      'payload': payload,
      'created_at': now,
      'attempts': 0,
      'last_error': null,
    });
  }

  Future<void> deleteLocal(String collection, String id) async {
    final db = await LocalDatabase.instance.database;
    final now = _now;

    await db.update(
      'documents',
      {
        'is_deleted': 1,
        'deleted_at': now,
        'dirty': 1,
      },
      where: 'collection = ? AND doc_id = ?',
      whereArgs: [collection, id],
    );

    await db.insert('sync_pending', {
      'collection': collection,
      'doc_id': id,
      'op': 'delete',
      'payload': null,
      'created_at': now,
      'attempts': 0,
      'last_error': null,
    });

    _changes.add(collection);
  }

  // ── Remote writes (from a Firestore pull — never override a dirty row) ─

  Future<void> putRemote(
    String collection,
    String id,
    Map<String, dynamic> json,
  ) async {
    final db = await LocalDatabase.instance.database;

    final existing = await db.query(
      'documents',
      columns: ['dirty'],
      where: 'collection = ? AND doc_id = ?',
      whereArgs: [collection, id],
      limit: 1,
    );
    if (existing.isNotEmpty && (existing.first['dirty'] as int) == 1) {
      // A queued local edit always wins until it has been pushed.
      return;
    }

    await db.insert(
      'documents',
      {
        'collection': collection,
        'doc_id': id,
        'payload': jsonEncode(json),
        'updated_at': _now,
        'is_deleted': 0,
        'deleted_at': null,
        'synced_at': _now,
        'dirty': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(collection);
  }

  Future<void> deleteRemote(String collection, String id) async {
    final db = await LocalDatabase.instance.database;

    final existing = await db.query(
      'documents',
      columns: ['dirty'],
      where: 'collection = ? AND doc_id = ?',
      whereArgs: [collection, id],
      limit: 1,
    );
    if (existing.isNotEmpty && (existing.first['dirty'] as int) == 1) {
      return;
    }

    await db.delete(
      'documents',
      where: 'collection = ? AND doc_id = ?',
      whereArgs: [collection, id],
    );
    _changes.add(collection);
  }

  /// Hard-deletes local rows in [collection] that are clean (not dirty),
  /// have been confirmed synced at least once, and no longer appear in
  /// [serverIds] — i.e. they were deleted on another device. Never touches
  /// a dirty row or a row that has never been synced (a doc created
  /// offline, not yet pushed, must survive a pull that doesn't know about
  /// it yet).
  Future<void> reconcilePull(String collection, Set<String> serverIds) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'documents',
      columns: ['doc_id'],
      where: 'collection = ? AND dirty = 0 AND synced_at IS NOT NULL',
      whereArgs: [collection],
    );

    final toDelete = rows
        .map((r) => r['doc_id'] as String)
        .where((id) => !serverIds.contains(id))
        .toList();
    if (toDelete.isEmpty) return;

    final batch = db.batch();
    for (final id in toDelete) {
      batch.delete(
        'documents',
        where: 'collection = ? AND doc_id = ?',
        whereArgs: [collection, id],
      );
    }
    await batch.commit(noResult: true);
    _changes.add(collection);
  }

  // ── Outbox ───────────────────────────────────────────────────────────

  Future<List<PendingOp>> pending({int limit = 100}) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'sync_pending',
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map((row) {
      final rawPayload = row['payload'] as String?;
      return PendingOp(
        id: row['id'] as int,
        collection: row['collection'] as String,
        docId: row['doc_id'] as String,
        op: row['op'] as String,
        payload: rawPayload == null
            ? null
            : jsonDecode(rawPayload) as Map<String, dynamic>,
        createdAt: row['created_at'] as String,
        attempts: row['attempts'] as int,
        lastError: row['last_error'] as String?,
      );
    }).toList();
  }

  Future<void> markPushed(int opId, String collection, String id) async {
    final db = await LocalDatabase.instance.database;

    await db.delete('sync_pending', where: 'id = ?', whereArgs: [opId]);

    final remaining = await db.query(
      'sync_pending',
      where: 'collection = ? AND doc_id = ?',
      whereArgs: [collection, id],
      limit: 1,
    );
    if (remaining.isNotEmpty) return; // more ops still queued for this doc

    final doc = await db.query(
      'documents',
      columns: ['is_deleted'],
      where: 'collection = ? AND doc_id = ?',
      whereArgs: [collection, id],
      limit: 1,
    );
    if (doc.isEmpty) return;

    if ((doc.first['is_deleted'] as int) == 1) {
      // The queued deletion has been confirmed pushed — remove the local
      // tombstone entirely.
      await db.delete(
        'documents',
        where: 'collection = ? AND doc_id = ?',
        whereArgs: [collection, id],
      );
    } else {
      await db.update(
        'documents',
        {'dirty': 0, 'synced_at': _now},
        where: 'collection = ? AND doc_id = ?',
        whereArgs: [collection, id],
      );
    }
    _changes.add(collection);
  }

  Future<void> markFailed(int opId, String error) async {
    final db = await LocalDatabase.instance.database;
    await db.rawUpdate(
      'UPDATE sync_pending SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, opId],
    );
  }

  Future<int> pendingCount() async {
    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_pending');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
