import 'package:cloud_firestore/cloud_firestore.dart';

class Client {
  const Client({
    required this.id,
    required this.name,
    required this.contactNumber,
    this.employeeIds = const [],
  });

  final String id;
  final String name;
  final String contactNumber;
  final List<String> employeeIds;

  factory Client.fromJson(Map<String, dynamic> json, [String? docId]) {
    return Client(
      id: (docId ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      contactNumber: json['contact_number'] as String? ?? '',
      employeeIds: (json['employee_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  factory Client.fromFirestore(DocumentSnapshot doc) {
    return Client.fromJson(doc.data() as Map<String, dynamic>? ?? {}, doc.id);
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'contact_number': contactNumber,
        'employee_ids': employeeIds,
      };
}
