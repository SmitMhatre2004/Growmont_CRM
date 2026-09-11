// lib/core/local/sync_models.dart
//
// Small data classes shared between LocalStore and SyncEngine.

/// One row from the `sync_pending` outbox — a not-yet-pushed local write.
class PendingOp {
  const PendingOp({
    required this.id,
    required this.collection,
    required this.docId,
    required this.op,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });

  final int id;
  final String collection;
  final String docId;

  /// 'set' or 'delete'.
  final String op;

  /// JSON payload for a 'set' op; null for 'delete'.
  final Map<String, dynamic>? payload;
  final String createdAt;
  final int attempts;
  final String? lastError;
}

enum SyncStatus { idle, syncing, offline, error }

class SyncSnapshot {
  const SyncSnapshot({
    this.status = SyncStatus.idle,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final SyncStatus status;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? lastError;

  SyncSnapshot copyWith({
    SyncStatus? status,
    int? pendingCount,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncSnapshot(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}
