// lib/core/local/firestore_json.dart
//
// Codec between "Firestore document data" (may contain Timestamp,
// FieldValue, nested maps/lists of those) and "JSON-safe map" (everything
// is a String/num/bool/null/Map/List — safe to jsonEncode into the local
// SQLite `documents.payload` column).
//
// This is the ONLY place in the app that should convert between the two
// shapes. LocalStore stores/returns JSON-safe maps; SyncEngine calls
// toFirestore() immediately before writing to Firestore and toJsonSafe()
// immediately after reading a snapshot from it.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Date-valued fields per collection. Used on the way OUT (local ->
/// Firestore) to restore real Timestamps, so Firestore queries and
/// security rules that assume a Timestamp type keep working.
const Map<String, List<String>> kDateFields = {
  'employees': [
    'dob',
    'access_expires_at',
    'requested_at',
    'approved_at',
    'rejected_at',
    'restricted_at',
    'created_at',
    'updated_at',
  ],
  'clients': ['created_at', 'updated_at'],
  'sales': ['date', 'created_at', 'updated_at'],
  'interactions': ['date', 'follow_up_date', 'created_at', 'updated_at'],
  'reminders': ['date', 'created_at', 'updated_at'],
};

/// Recursively converts Firestore-native values (Timestamp, DateTime,
/// nested maps/lists of those) into JSON-safe values. Any [FieldValue]
/// sentinel (e.g. FieldValue.serverTimestamp()) is dropped entirely — a
/// sentinel has no meaningful local value and must never be persisted.
Map<String, dynamic> toJsonSafe(Map<String, dynamic> data) {
  final result = <String, dynamic>{};
  data.forEach((key, value) {
    if (value is FieldValue) return; // dropped, not stored
    result[key] = _toJsonSafeValue(value);
  });
  return result;
}

dynamic _toJsonSafeValue(dynamic value) {
  if (value is FieldValue) return null;
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  if (value is Map) {
    final result = <String, dynamic>{};
    value.forEach((k, v) {
      if (v is FieldValue) return;
      result[k.toString()] = _toJsonSafeValue(v);
    });
    return result;
  }
  if (value is List) {
    return value
        .where((v) => v is! FieldValue)
        .map(_toJsonSafeValue)
        .toList();
  }
  return value;
}

/// Converts a locally-stored JSON-safe document back into a Firestore-ready
/// payload: every field listed in [kDateFields] for [collection] that holds
/// a parseable ISO date string is converted to a [Timestamp], and
/// `updated_at` is unconditionally set to [FieldValue.serverTimestamp()].
Map<String, dynamic> toFirestore(String collection, Map<String, dynamic> json) {
  final result = Map<String, dynamic>.from(json);
  final dateFields = kDateFields[collection] ?? const [];
  for (final field in dateFields) {
    final value = result[field];
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        result[field] = Timestamp.fromDate(parsed);
      }
    }
  }
  result['updated_at'] = FieldValue.serverTimestamp();
  return result;
}
