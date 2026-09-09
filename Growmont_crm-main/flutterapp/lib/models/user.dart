enum UserRole { admin, employee }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final String? avatar;
  final UserRole role;

  bool get isAdmin => role == UserRole.admin;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatar: json['avatar'] as String? ?? json['avatar_url'] as String?,
      role: (json['role'] as String?)?.toUpperCase() == 'ADMIN'
          ? UserRole.admin
          : UserRole.employee,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'avatar': avatar,
    'role': role == UserRole.admin ? 'ADMIN' : 'EMPLOYEE',
  };

  String get initials {
    return name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join()
        .toUpperCase();
  }
}
