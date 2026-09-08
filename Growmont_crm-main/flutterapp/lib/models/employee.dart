import 'package:cloud_firestore/cloud_firestore.dart';

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
    );
  }

  factory Employee.fromFirestore(DocumentSnapshot doc) {
    return Employee.fromJson(doc.data() as Map<String, dynamic>? ?? {}, doc.id);
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'mobile_no': mobileNo,
        'gender': gender,
        'dob': dob,
        'avatar_url': avatar,
        'role': role,
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

  factory EmployeeDropdown.fromJson(Map<String, dynamic> json, [String? docId]) {
    return EmployeeDropdown(
      id: (docId ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? 'EMPLOYEE',
    );
  }

  factory EmployeeDropdown.fromFirestore(DocumentSnapshot doc) {
    return EmployeeDropdown.fromJson(doc.data() as Map<String, dynamic>? ?? {}, doc.id);
  }
}
