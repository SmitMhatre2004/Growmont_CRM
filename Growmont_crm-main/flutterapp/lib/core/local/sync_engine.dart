// lib/core/local/sync_engine.dart
//
// Drives the local-first sync loop: attaches live Firestore listeners per
// collection (writing every incoming doc into LocalStore via putRemote),
// and drains LocalStore's outbox (sync_pending) whenever connectivity
// returns or a caller asks for it.
//
// See LOCAL_FIRST_AND_UPDATER_PLAN.md §4 for the full design rationale.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'firestore_json.dart';
import 'local_database.dart';
import 'local_store.dart';
import 'sync_models.dart';

class SyncEngine extends ChangeNotifier {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  static const List<String> collections = [
    'employees',
    'clients',
    'sales',
    'interactions',
    'reminders',
  ];

  SyncSnapshot _snapshot = const SyncSnapshot();
  SyncSnapshot get snapshot => _snapshot;

  FirebaseFirestore? _firestore;
  String? _uid;
  bool _started = false;
  bool _draining = false;
  bool _backedUpThisSession = false;

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _listeners = [];
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  void _update(SyncSnapshot Function(SyncSnapshot) transform) {
    _snapshot = transform(_snapshot);
    notifyListeners();
  }

  /// Idempotent. If [uid] is null (signed out), stops any active sync
  /// instead. Otherwise attaches per-collection listeners and kicks off an
  /// outbox drain.
  Future<void> start(FirebaseFirestore fs, String? uid) async {
    if (uid == null) {
      await stop();
      return;
    }
    if (_started && _uid == uid) return; // already running for this user
    await stop(); // tear down any previous user's listeners first

    _firestore = fs;
    _uid = uid;
    _started = true;

    if (!_backedUpThisSession) {
      await LocalDatabase.instance.createPreSyncBackup();
      _backedUpThisSession = true;
    }

    for (final collection in collections) {
      final query = collection == 'reminders'
          ? fs.collection('reminders').where('employee_id', isEqualTo: uid)
          : fs.collection(collection);

      final sub = query.snapshots().listen(
        (snapshot) => _onSnapshot(collection, snapshot),
        onError: (Object e) {
          _update((s) => s.copyWith(status: SyncStatus.error, lastError: e.toString()));
          debugPrint('SyncEngine listener error ($collection): $e');
        },
      );
      _listeners.add(sub);
    }

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        unawaited(drainOutbox());
      } else {
        _update((s) => s.copyWith(status: SyncStatus.offline));
      }
    });

    unawaited(drainOutbox());
  }

  Future<void> _onSnapshot(
    String collection,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    for (final doc in snapshot.docs) {
      await LocalStore.instance.putRemote(collection, doc.id, toJsonSafe(doc.data()));
    }
    // A cache-only snapshot is not evidence that a doc was deleted
    // server-side — only reconcile against a snapshot Firestore confirms
    // came from the server.
    if (!snapshot.metadata.isFromCache) {
      final serverIds = snapshot.docs.map((d) => d.id).toSet();
      await LocalStore.instance.reconcilePull(collection, serverIds);
    }
    _update((s) => s.copyWith(lastSyncedAt: DateTime.now(), clearError: true));
  }

  /// Pushes every queued outbox op to Firestore, in order, stopping at the
  /// first failure (so a dead network doesn't burn through the whole
  /// queue). Guarded against overlapping calls.
  Future<void> drainOutbox() async {
    if (_draining) return;
    final fs = _firestore;
    if (fs == null) return;

    _draining = true;
    _update((s) => s.copyWith(status: SyncStatus.syncing));

    try {
      while (true) {
        final batch = await LocalStore.instance.pending(limit: 1);
        if (batch.isEmpty) break;
        final op = batch.first;

        if (op.attempts >= 5) {
          // Give up on this op — record why, but don't let it block
          // everything behind it forever.
          await LocalStore.instance.markPushed(op.id, op.collection, op.docId);
          _update((s) => s.copyWith(
                lastError: 'Gave up on ${op.collection}/${op.docId} after '
                    '${op.attempts} attempts: ${op.lastError}',
              ));
          continue;
        }

        try {
          if (op.op == 'set') {
            await fs
                .collection(op.collection)
                .doc(op.docId)
                .set(toFirestore(op.collection, op.payload!), SetOptions(merge: true));
          } else {
            await fs.collection(op.collection).doc(op.docId).delete();
          }
          await LocalStore.instance.markPushed(op.id, op.collection, op.docId);
        } catch (e) {
          await LocalStore.instance.markFailed(op.id, e.toString());
          _update((s) => s.copyWith(status: SyncStatus.error, lastError: e.toString()));
          break; // stop draining — the network or the write is failing
        }
      }

      final remaining = await LocalStore.instance.pendingCount();
      _update((s) => s.copyWith(
            status: SyncStatus.idle,
            pendingCount: remaining,
            lastSyncedAt: remaining == 0 ? DateTime.now() : s.lastSyncedAt,
          ));
    } finally {
      _draining = false;
    }
  }

  /// Manual "Sync now": drains the outbox, then does a one-shot fetch of
  /// every collection so a fresh pull happens even if no snapshot event
  /// has fired yet.
  Future<void> syncNow() async {
    final fs = _firestore;
    final uid = _uid;
    if (fs == null || uid == null) return;

    await drainOutbox();

    for (final collection in collections) {
      try {
        final query = collection == 'reminders'
            ? fs.collection('reminders').where('employee_id', isEqualTo: uid)
            : fs.collection(collection);
        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          await LocalStore.instance.putRemote(collection, doc.id, toJsonSafe(doc.data()));
        }
        await LocalStore.instance.reconcilePull(
          collection,
          snapshot.docs.map((d) => d.id).toSet(),
        );
      } catch (e) {
        _update((s) => s.copyWith(status: SyncStatus.error, lastError: e.toString()));
        return;
      }
    }
    _update((s) => s.copyWith(status: SyncStatus.idle, lastSyncedAt: DateTime.now(), clearError: true));
  }

  Future<void> stop() async {
    for (final sub in _listeners) {
      await sub.cancel();
    }
    _listeners.clear();
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _firestore = null;
    _uid = null;
    _started = false;
  }
}
