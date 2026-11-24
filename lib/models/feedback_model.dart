class FeedbackModel {
  final String id;
  final String userId;
  final String authorName;
  final String authorAvatar;
  final String content;
  final String category;
  final String recommendation;
  final String visibility;
  final bool isSeed;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int likesCount;
  final bool isLikedByMe;
  final bool isMine;

  FeedbackModel({
    required this.id,
    required this.userId,
    required this.authorName,
    this.authorAvatar = '',
    required this.content,
    this.category = 'General Feedback',
    this.recommendation = 'yes',
    this.visibility = 'public',
    this.isSeed = false,
    required this.createdAt,
    this.updatedAt,
    this.likesCount = 0,
    this.isLikedByMe = false,
    this.isMine = false,
  });

  FeedbackModel copyWith({
    String? id,
    String? userId,
    String? authorName,
    String? authorAvatar,
    String? content,
    String? category,
    String? recommendation,
    String? visibility,
    bool? isSeed,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? likesCount,
    bool? isLikedByMe,
    bool? isMine,
  }) {
    return FeedbackModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      content: content ?? this.content,
      category: category ?? this.category,
      recommendation: recommendation ?? this.recommendation,
      visibility: visibility ?? this.visibility,
      isSeed: isSeed ?? this.isSeed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isMine: isMine ?? this.isMine,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'author_name': authorName,
      'author_avatar': authorAvatar,
      'content': content,
      'category': category,
      'recommendation': recommendation,
      'visibility': visibility,
      'is_seed': isSeed,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      'likes_count': likesCount,
      'is_liked_by_me': isLikedByMe ? 1 : 0,
      'is_mine': isMine ? 1 : 0,
    };
  }

  factory FeedbackModel.fromMap(Map<String, dynamic> map) {
    return FeedbackModel(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      authorName: (map['author_name'] as String?)?.trim().isNotEmpty == true
          ? map['author_name'] as String
          : 'Planova',
      authorAvatar: (map['author_avatar'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      category: (map['category'] as String?) ?? 'General Feedback',
      recommendation: (map['recommendation'] as String?) ?? 'yes',
      visibility: (map['visibility'] as String?) ?? 'public',
      isSeed: map['is_seed'] == true || map['is_seed'] == 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
      likesCount: (map['likes_count'] as num?)?.toInt() ?? 0,
      isLikedByMe: map['is_liked_by_me'] == true || map['is_liked_by_me'] == 1,
      isMine: map['is_mine'] == true || map['is_mine'] == 1,
    );
  }
}
