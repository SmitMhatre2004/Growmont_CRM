import 'package:cloud_firestore/cloud_firestore.dart';

class Client {
  const Client({
    required this.id,
    required this.name,
    required this.contactNumber,
    this.employeeId = '',
    this.employeeName,
    this.createdAt,
  });

  final String id;
  final String name;
  final String contactNumber;
  final String employeeId;
  final String? employeeName;

  /// When this client was first added, as an ISO-8601 string, or null when
  /// the record carries no `created_at` — which older rows and rows added
  /// by the Excel importer may not. Read-only: it is never written from
  /// here (createClient stamps it server-side), and is deliberately absent
  /// from [toFirestore] so round-tripping a Client cannot overwrite it.
  ///
  /// Kept as the raw string rather than a DateTime because the field has
  /// mixed provenance — a server timestamp on older rows, the writing
  /// device's clock on rows created through the local-first path — and the
  /// reporting layer needs to apply its own parsing rule. See
  /// `core/reports/monthly_report.dart`.
  final String? createdAt;

  factory Client.fromJson(Map<String, dynamic> json, [String? docId]) {
    return Client(
      id: (docId ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      contactNumber: json['contact_number'] as String? ?? '',
      employeeId: (json['employee_id'] ?? '').toString(),
      employeeName: json['employee_name'] as String?,
      createdAt: _readTimestamp(json['created_at']),
    );
  }

  /// `created_at` arrives as a Firestore [Timestamp] on the direct-network
  /// path and as an ISO string out of the local SQLite payload. Both
  /// normalize to an ISO string here; anything else becomes null.
  static String? _readTimestamp(Object? raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate().toIso8601String();
    if (raw is DateTime) return raw.toIso8601String();
    final text = raw.toString();
    return text.isEmpty ? null : text;
  }

  factory Client.fromFirestore(DocumentSnapshot doc) {
    return Client.fromJson(doc.data() as Map<String, dynamic>? ?? {}, doc.id);
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'contact_number': contactNumber,
    'employee_id': employeeId,
    if (employeeName != null) 'employee_name': employeeName,
  };

  Client copyWith({
    String? id,
    String? name,
    String? contactNumber,
    String? employeeId,
    String? employeeName,
    String? createdAt,
  }) {
    return Client(
      id: id ?? this.id,
      name: name ?? this.name,
      contactNumber: contactNumber ?? this.contactNumber,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
