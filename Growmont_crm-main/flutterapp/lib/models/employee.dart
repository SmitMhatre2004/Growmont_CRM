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

  final int id;
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

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      mobileNo: json['mobile_no'] as String? ?? '',
      gender: json['gender'] as String? ?? 'M',
      dob: json['dob'] as String? ?? '',
      avatar: json['avatar'] as String?,
      role: json['role'] as String? ?? 'EMPLOYEE',
      clientsCount: json['clients_count'] as int? ?? 0,
      salesCount: json['sales_count'] as int? ?? 0,
      interactionsCount: json['interactions_count'] as int? ?? 0,
    );
  }

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
}

class EmployeeDropdown {
  const EmployeeDropdown({
    required this.id,
    required this.name,
    required this.role,
  });

  final int id;
  final String name;
  final String role;

  factory EmployeeDropdown.fromJson(Map<String, dynamic> json) {
    return EmployeeDropdown(
      id: json['id'] as int,
      name: json['name'] as String,
      role: json['role'] as String? ?? 'EMPLOYEE',
    );
  }
}
