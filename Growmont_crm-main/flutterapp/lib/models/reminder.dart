import 'package:cloud_firestore/cloud_firestore.dart';

class Reminder {
  const Reminder({
    required this.id,
    required this.employee,
    this.employeeName,
    required this.eventName,
    required this.type,
    required this.priority,
    required this.date,
    required this.time,
    this.endTime,
    this.description = '',
    this.repeatReminder = false,
    this.repeatType = 'NONE',
    this.repeatDays = const [],
    this.repeatEveryDay = false,
  });

  final String id;
  final String employee;
  final String? employeeName;
  final String eventName;
  final String type;
  final String priority;
  final String date;
  final String time;
  final String? endTime;
  final String description;
  final bool repeatReminder;
  final String repeatType;
  final List<String> repeatDays;
  final bool repeatEveryDay;

  factory Reminder.fromJson(Map<String, dynamic> json, [String? docId]) {
    String dateStr = '';
    final rawDate = json['date'];
    if (rawDate is Timestamp) {
      dateStr = rawDate.toDate().toIso8601String().split('T').first;
    } else if (rawDate is String) {
      dateStr = rawDate;
    }

    final emp = (json['employee_id'] ?? json['employee'] ?? '').toString();

    return Reminder(
      id: (docId ?? json['id'] ?? '').toString(),
      employee: emp,
      employeeName: json['employee_name'] as String?,
      eventName: json['event_name'] as String? ?? '',
      type: json['type'] as String? ?? 'CORPORATE',
      priority: json['priority'] as String? ?? 'MEDIUM',
      date: dateStr,
      time: json['time'] as String? ?? '10:00:00',
      endTime: json['end_time'] as String?,
      description: json['description'] as String? ?? '',
      repeatReminder: json['repeat_reminder'] as bool? ?? false,
      repeatType: json['repeat_type'] as String? ?? 'NONE',
      repeatDays: (json['repeat_days'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      repeatEveryDay: json['repeat_every_day'] as bool? ?? false,
    );
  }

  factory Reminder.fromFirestore(DocumentSnapshot doc) {
    return Reminder.fromJson(doc.data() as Map<String, dynamic>? ?? {}, doc.id);
  }

  Map<String, dynamic> toFirestore() => {
        'employee_id': employee,
        if (employeeName != null) 'employee_name': employeeName,
        'event_name': eventName,
        'type': type,
        'priority': priority,
        'date': Timestamp.fromDate(DateTime.tryParse(date) ?? DateTime.now()),
        'time': time.length == 5 ? '$time:00' : time,
        if (endTime != null && endTime!.isNotEmpty)
          'end_time': endTime!.length == 5 ? '$endTime:00' : endTime,
        'description': description,
        'repeat_reminder': repeatReminder,
        'repeat_type': repeatType,
        'repeat_days': repeatDays,
        'repeat_every_day': repeatEveryDay,
        'is_sent': false,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toPayload() => {
        'employee': employee,
        'event_name': eventName,
        'type': type,
        'priority': priority,
        'date': date,
        'time': time.length == 5 ? '$time:00' : time,
        if (endTime != null && endTime!.isNotEmpty)
          'end_time': endTime!.length == 5 ? '$endTime:00' : endTime,
        'description': description,
        'repeat_reminder': repeatReminder,
        'repeat_type': repeatType,
        'repeat_days': repeatDays,
        'repeat_every_day': repeatEveryDay,
      };
}
