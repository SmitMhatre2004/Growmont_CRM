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

  final int id;
  final int employee;
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

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as int,
      employee: json['employee'] as int,
      employeeName: json['employee_name'] as String?,
      eventName: json['event_name'] as String? ?? '',
      type: json['type'] as String? ?? 'CORPORATE',
      priority: json['priority'] as String? ?? 'MEDIUM',
      date: json['date'] as String,
      time: json['time'] as String,
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
