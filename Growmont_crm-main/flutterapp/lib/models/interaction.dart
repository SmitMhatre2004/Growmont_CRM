import 'package:cloud_firestore/cloud_firestore.dart';

class Interaction {
  const Interaction({
    required this.id,
    required this.date,
    required this.clientName,
    required this.clientContact,
    required this.employee,
    this.employeeName,
    this.employeeId,
    required this.followUpDate,
    required this.followUpTime,
    required this.priority,
    this.priorityDisplay,
    this.discussionNotes = '',
  });

  final String id;
  final String date;
  final String clientName;
  final String clientContact;
  final String employee;
  final String? employeeName;
  final String? employeeId;
  final String followUpDate;
  final String followUpTime;
  final String priority;
  final String? priorityDisplay;
  final String discussionNotes;

  factory Interaction.fromJson(Map<String, dynamic> json, [String? docId]) {
    String dateStr = '';
    final rawDate = json['date'];
    if (rawDate is Timestamp) {
      dateStr = rawDate.toDate().toIso8601String().split('T').first;
    } else if (rawDate is String) {
      dateStr = rawDate;
    }

    String followUpDateStr = '';
    final rawFollowUp = json['follow_up_date'];
    if (rawFollowUp is Timestamp) {
      followUpDateStr = rawFollowUp.toDate().toIso8601String().split('T').first;
    } else if (rawFollowUp is String) {
      followUpDateStr = rawFollowUp;
    }

    final emp = (json['employee_id'] ?? json['employee'] ?? '').toString();

    return Interaction(
      id: (docId ?? json['id'] ?? '').toString(),
      date: dateStr,
      clientName: json['client_name'] as String? ?? '',
      clientContact: json['client_contact'] as String? ?? '',
      employee: emp,
      employeeName: json['employee_name'] as String?,
      employeeId: emp,
      followUpDate: followUpDateStr,
      followUpTime: json['follow_up_time'] as String? ?? '',
      priority: json['priority'] as String? ?? 'MEDIUM',
      priorityDisplay: json['priority_display'] as String?,
      discussionNotes: json['discussion_notes'] as String? ?? '',
    );
  }

  factory Interaction.fromFirestore(DocumentSnapshot doc) {
    return Interaction.fromJson(
      doc.data() as Map<String, dynamic>? ?? {},
      doc.id,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'date': Timestamp.fromDate(DateTime.tryParse(date) ?? DateTime.now()),
    'client_name': clientName,
    'client_contact': clientContact,
    'employee_id': employee,
    if (employeeName != null) 'employee_name': employeeName,
    'follow_up_date': followUpDate.isNotEmpty
        ? Timestamp.fromDate(DateTime.tryParse(followUpDate) ?? DateTime.now())
        : null,
    'follow_up_time': followUpTime.length == 5
        ? '$followUpTime:00'
        : followUpTime,
    'priority': priority,
    'discussion_notes': discussionNotes,
    'created_at': FieldValue.serverTimestamp(),
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> toPayload() => {
    'date': date,
    'client_name': clientName,
    'client_contact': clientContact,
    'employee': employee,
    'follow_up_date': followUpDate,
    'follow_up_time': followUpTime.length == 5
        ? '$followUpTime:00'
        : followUpTime,
    'priority': priority,
    'discussion_notes': discussionNotes,
  };
}
