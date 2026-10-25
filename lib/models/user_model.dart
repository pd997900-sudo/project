class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role; // 'reporter' or 'community'
  final String? avatarUrl;
  final bool isVerified;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    required this.role,
    this.avatarUrl,
    this.isVerified = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isReporter => role.toLowerCase() == 'reporter';
  bool get isCommunity => role.toLowerCase() == 'community';

  bool get hasValidName {
    final n = name.trim();
    return n.isNotEmpty &&
        !n.contains('@') &&
        n != 'Registered User' &&
        n != 'Registered Voter' &&
        n != 'Citizen User' &&
        n != 'Citizen Reporter' &&
        n != 'Name not available' &&
        n != 'Reporter name unavailable';
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      role: json['role'] ?? 'reporter',
      avatarUrl: json['avatar_url'],
      isVerified: json['is_verified'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'avatar_url': avatarUrl,
      'is_verified': isVerified,
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? role,
    String? avatarUrl,
    bool? isVerified,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt,
    );
  }
}
