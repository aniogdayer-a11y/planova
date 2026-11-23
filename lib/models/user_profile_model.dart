class UserProfileModel {
  final int id;
  final String name;
  final String workspace;
  final String tagline;
  final String avatarUrl;
  final int streakCount;
  final String lastActiveDate;

  UserProfileModel({
    this.id = 1,
    required this.name,
    required this.workspace,
    required this.tagline,
    required this.avatarUrl,
    required this.streakCount,
    required this.lastActiveDate,
  });

  UserProfileModel copyWith({
    int? id,
    String? name,
    String? workspace,
    String? tagline,
    String? avatarUrl,
    int? streakCount,
    String? lastActiveDate,
  }) {
    return UserProfileModel(
      id: id ?? this.id,
      name: name ?? this.name,
      workspace: workspace ?? this.workspace,
      tagline: tagline ?? this.tagline,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      streakCount: streakCount ?? this.streakCount,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'workspace': workspace,
      'tagline': tagline,
      'avatar_url': avatarUrl,
      'streak_count': streakCount,
      'last_active_date': lastActiveDate,
    };
  }

  factory UserProfileModel.fromMap(Map<String, dynamic> map) {
    return UserProfileModel(
      id: (map['id'] as int?) ?? 1,
      name: (map['name'] as String?) ?? 'Dayer',
      workspace: (map['workspace'] as String?) ?? 'Personal workspace',
      tagline:
          (map['tagline'] as String?) ?? 'A little more focused, every day.',
      avatarUrl: (map['avatar_url'] as String?) ?? '',
      streakCount: (map['streak_count'] as int?) ?? 0,
      lastActiveDate: (map['last_active_date'] as String?) ?? '',
    );
  }
}
