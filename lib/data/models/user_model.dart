class AppUser {
  final String uid;
  final String name;
  final String email;
  final String role; // 'patient' atau 'midwife'
  final bool verified;
  final String? credentialLabel;
  final String? bio;
  final DateTime createdAt;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.verified = false,
    this.credentialLabel,
    this.bio,
    required this.createdAt,
  });

  bool get isPatient => role == 'patient';
  bool get isMidwife => role == 'midwife';
  bool get canAccessMidwifeFeatures => isMidwife && verified;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'name': name,
    'email': email,
    'role': role,
    'verified': verified,
    'credential_label': credentialLabel,
    'bio': bio,
    'created_at': createdAt.toIso8601String(),
  };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    uid: json['uid'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: json['role'] as String,
    verified: json['verified'] as bool? ?? false,
    credentialLabel: json['credential_label'] as String?,
    bio: json['bio'] as String?,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
  );

  AppUser copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    bool? verified,
    String? credentialLabel,
    String? bio,
    DateTime? createdAt,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      verified: verified ?? this.verified,
      credentialLabel: credentialLabel ?? this.credentialLabel,
      bio: bio ?? this.bio,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
