import 'package:cloud_firestore/cloud_firestore.dart';

/// Account review status, gating access alongside the 3-day self-signup
/// grace period. Absent on legacy docs predating this feature — treat a
/// missing/unrecognized value as [active], matching every reader across
/// the app (client and Cloud Functions).
enum EmployeeStatus { pending, active, restricted, rejected }

EmployeeStatus _employeeStatusFromString(String? raw) {
  switch (raw?.toUpperCase()) {
    case 'PENDING':
      return EmployeeStatus.pending;
    case 'RESTRICTED':
      return EmployeeStatus.restricted;
    case 'REJECTED':
      return EmployeeStatus.rejected;
    case 'ACTIVE':
    default:
      return EmployeeStatus.active;
  }
}

String _employeeStatusToString(EmployeeStatus status) {
  switch (status) {
    case EmployeeStatus.pending:
      return 'PENDING';
    case EmployeeStatus.restricted:
      return 'RESTRICTED';
    case EmployeeStatus.rejected:
      return 'REJECTED';
    case EmployeeStatus.active:
      return 'ACTIVE';
  }
}

DateTime? _timestampToDate(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
  return null;
}

class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.email,
    required this.mobileNo,
    required this.gender,
    required this.dob,
    this.avatar,
    required this.role,
    this.clientsCount = 0,
    this.salesCount = 0,
    this.interactionsCount = 0,
    this.status = EmployeeStatus.active,
    this.accessExpiresAt,
    this.requestedAt,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.restrictedAt,
  });

  final String id;
  final String name;
  final String email;
  final String mobileNo;
  final String gender;
  final String dob;
  final String? avatar;
  final String role;
  final int clientsCount;
  final int salesCount;
  final int interactionsCount;
  final EmployeeStatus status;
  final DateTime? accessExpiresAt;
  final DateTime? requestedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final DateTime? restrictedAt;

  bool get isPending => status == EmployeeStatus.pending;
  bool get isRestricted => status == EmployeeStatus.restricted;
  bool get isRejected => status == EmployeeStatus.rejected;
  bool get isActive => status == EmployeeStatus.active;

  /// Time left in the 3-day grace period, or null if not [isPending] or no
  /// expiry is set. Can be negative once the window has lapsed but the
  /// scheduled sweep hasn't caught up yet.
  Duration? get timeRemaining {
    if (accessExpiresAt == null) return null;
    return accessExpiresAt!.difference(DateTime.now());
  }

  factory Employee.fromJson(Map<String, dynamic> json, [String? docId]) {
    String dobStr = '';
    final rawDob = json['dob'];
    if (rawDob is Timestamp) {
      dobStr = rawDob.toDate().toIso8601String().split('T').first;
    } else if (rawDob is String) {
      dobStr = rawDob;
    }

    return Employee(
      id: (docId ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      mobileNo: json['mobile_no'] as String? ?? '',
      gender: json['gender'] as String? ?? 'M',
      dob: dobStr,
      avatar: json['avatar_url'] as String? ?? json['avatar'] as String?,
      role: json['role'] as String? ?? 'EMPLOYEE',
      clientsCount: json['clients_count'] as int? ?? 0,
      salesCount: json['sales_count'] as int? ?? 0,
      interactionsCount: json['interactions_count'] as int? ?? 0,
      status: _employeeStatusFromString(json['status'] as String?),
      accessExpiresAt: _timestampToDate(json['access_expires_at']),
      requestedAt: _timestampToDate(json['requested_at']),
      approvedBy: json['approved_by'] as String?,
      approvedAt: _timestampToDate(json['approved_at']),
      rejectedBy: json['rejected_by'] as String?,
      rejectedAt: _timestampToDate(json['rejected_at']),
      restrictedAt: _timestampToDate(json['restricted_at']),
    );
  }

  factory Employee.fromFirestore(DocumentSnapshot doc) {
    return Employee.fromJson(doc.data() as Map<String, dynamic>? ?? {}, doc.id);
  }

  Employee copyWith({String? name, String? email, String? avatar}) {
    return Employee(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      mobileNo: mobileNo,
      gender: gender,
      dob: dob,
      avatar: avatar ?? this.avatar,
      role: role,
      clientsCount: clientsCount,
      salesCount: salesCount,
      interactionsCount: interactionsCount,
      status: status,
      accessExpiresAt: accessExpiresAt,
      requestedAt: requestedAt,
      approvedBy: approvedBy,
      approvedAt: approvedAt,
      rejectedBy: rejectedBy,
      rejectedAt: rejectedAt,
      restrictedAt: restrictedAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'email': email,
    'mobile_no': mobileNo,
    'gender': gender,
    'dob': dob,
    'avatar_url': avatar,
    'role': role,
    'status': _employeeStatusToString(status),
    'clients_count': clientsCount,
    'sales_count': salesCount,
    'interactions_count': interactionsCount,
  };

  String get genderDisplay {
    switch (gender) {
      case 'M':
        return 'Male';
      case 'F':
        return 'Female';
      case 'O':
        return 'Other';
      default:
        return gender;
    }
  }

  /// Up to two uppercase initials, tolerant of blank or multi-spaced names.
  String get initials {
    final letters = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join()
        .toUpperCase();
    return letters.isEmpty ? '?' : letters;
  }
}

class EmployeeDropdown {
  const EmployeeDropdown({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;
  final String role;

  factory EmployeeDropdown.fromJson(
    Map<String, dynamic> json, [
    String? docId,
  ]) {
    return EmployeeDropdown(
      id: (docId ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? 'EMPLOYEE',
    );
  }

  factory EmployeeDropdown.fromFirestore(DocumentSnapshot doc) {
    return EmployeeDropdown.fromJson(
      doc.data() as Map<String, dynamic>? ?? {},
      doc.id,
    );
  }
}
