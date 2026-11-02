import 'package:cloud_firestore/cloud_firestore.dart';

class ClientTransfer {
  const ClientTransfer({
    required this.id,
    required this.clientId,
    this.clientName = '',
    required this.fromEmployeeId,
    required this.fromEmployeeName,
    required this.toEmployeeId,
    required this.toEmployeeName,
    required this.transferredById,
    required this.transferredByName,
    this.transferredByRole = 'ADMIN',
    required this.transferredAt,
    this.reason = '',
    this.notes = '',
  });

  final String id;
  final String clientId;
  final String clientName;
  final String fromEmployeeId;
  final String fromEmployeeName;
  final String toEmployeeId;
  final String toEmployeeName;
  final String transferredById;
  final String transferredByName;
  final String transferredByRole;
  final String transferredAt;
  final String reason;
  final String notes;

  factory ClientTransfer.fromJson(Map<String, dynamic> json, [String? docId]) {
    return ClientTransfer(
      id: (docId ?? json['id'] ?? '').toString(),
      clientId: (json['client_id'] ?? json['clientId'] ?? '').toString(),
      clientName: (json['client_name'] ?? json['clientName'] ?? '').toString(),
      fromEmployeeId:
          (json['from_employee_id'] ?? json['fromEmployeeId'] ?? '').toString(),
      fromEmployeeName:
          (json['from_employee_name'] ?? json['fromEmployeeName'] ?? '')
              .toString(),
      toEmployeeId:
          (json['to_employee_id'] ?? json['toEmployeeId'] ?? '').toString(),
      toEmployeeName:
          (json['to_employee_name'] ?? json['toEmployeeName'] ?? '').toString(),
      transferredById:
          (json['transferred_by_id'] ?? json['transferredById'] ?? '')
              .toString(),
      transferredByName:
          (json['transferred_by_name'] ?? json['transferredByName'] ?? '')
              .toString(),
      transferredByRole:
          (json['transferred_by_role'] ?? json['transferredByRole'] ?? 'ADMIN')
              .toString()
              .toUpperCase(),
      transferredAt:
          (json['transferred_at'] ?? json['transferredAt'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }

  factory ClientTransfer.fromFirestore(DocumentSnapshot doc) {
    return ClientTransfer.fromJson(
      doc.data() as Map<String, dynamic>? ?? {},
      doc.id,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'client_name': clientName,
        'from_employee_id': fromEmployeeId,
        'from_employee_name': fromEmployeeName,
        'to_employee_id': toEmployeeId,
        'to_employee_name': toEmployeeName,
        'transferred_by_id': transferredById,
        'transferred_by_name': transferredByName,
        'transferred_by_role': transferredByRole,
        'transferred_at': transferredAt,
        'reason': reason,
        'notes': notes,
      };

  Map<String, dynamic> toFirestore() => {
        'client_id': clientId,
        'client_name': clientName,
        'from_employee_id': fromEmployeeId,
        'from_employee_name': fromEmployeeName,
        'to_employee_id': toEmployeeId,
        'to_employee_name': toEmployeeName,
        'transferred_by_id': transferredById,
        'transferred_by_name': transferredByName,
        'transferred_by_role': transferredByRole,
        'transferred_at': transferredAt,
        'reason': reason,
        'notes': notes,
      };
}
