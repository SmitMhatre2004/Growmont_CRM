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

  final int id;
  final String date;
  final String clientName;
  final String clientContact;
  final int employee;
  final String? employeeName;
  final int? employeeId;
  final String followUpDate;
  final String followUpTime;
  final String priority;
  final String? priorityDisplay;
  final String discussionNotes;

  factory Interaction.fromJson(Map<String, dynamic> json) {
    return Interaction(
      id: json['id'] as int,
      date: json['date'] as String,
      clientName: json['client_name'] as String? ?? '',
      clientContact: json['client_contact'] as String? ?? '',
      employee: json['employee'] as int,
      employeeName: json['employee_name'] as String?,
      employeeId: json['employee_id'] as int?,
      followUpDate: json['follow_up_date'] as String,
      followUpTime: json['follow_up_time'] as String,
      priority: json['priority'] as String? ?? 'MEDIUM',
      priorityDisplay: json['priority_display'] as String?,
      discussionNotes: json['discussion_notes'] as String? ?? '',
    );
  }

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
