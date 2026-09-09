import 'package:cloud_firestore/cloud_firestore.dart';

class Client {
  const Client({
    required this.id,
    required this.name,
    required this.contactNumber,
    this.employeeId = '',
    this.employeeName,
  });

  final String id;
  final String name;
  final String contactNumber;
  final String employeeId;
  final String? employeeName;

  factory Client.fromJson(Map<String, dynamic> json, [String? docId]) {
    return Client(
      id: (docId ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      contactNumber: json['contact_number'] as String? ?? '',
      employeeId: (json['employee_id'] ?? '').toString(),
      employeeName: json['employee_name'] as String?,
    );
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
}
