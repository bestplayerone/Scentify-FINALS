enum UserRole { customer, admin, superadmin }

extension UserRoleWireValue on UserRole {
  String get wireValue => switch (this) {
    UserRole.customer => 'customer',
    UserRole.admin => 'admin',
    UserRole.superadmin => 'superadmin',
  };

  bool get isAdmin => this == UserRole.admin || this == UserRole.superadmin;

  bool get isSuperAdmin => this == UserRole.superadmin;
}

class UserProfile {
  UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final DateTime createdAt;

  bool get isAdmin => role.isAdmin;

  bool get isSuperAdmin => role.isSuperAdmin;

  UserProfile copyWith({
    String? id,
    String? email,
    String? displayName,
    UserRole? role,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
