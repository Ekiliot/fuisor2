class Post {
  final String id;
  final String userId;
  final String caption;
  final String mediaUrl;
  final String mediaType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? username;
  final String? avatarUrl;
  final int likesCount;
  final int commentsCount;
  final List<Comment> comments;
  final bool isLiked;
  final String? thumbnailUrl;

  Post({
    required this.id,
    required this.userId,
    required this.caption,
    required this.mediaUrl,
    required this.mediaType,
    required this.createdAt,
    required this.updatedAt,
    this.username,
    this.avatarUrl,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.comments = const [],
    this.isLiked = false,
    this.thumbnailUrl,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      caption: json['caption'] ?? '',
      mediaUrl: json['media_url'] ?? '',
      mediaType: json['media_type'] ?? 'image',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      username: json['profiles']?['username'],
      avatarUrl: json['profiles']?['avatar_url'],
      likesCount: json['likes_count'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
      comments: (json['comments'] as List?)
          ?.map((comment) => Comment.fromJson(comment))
          .toList() ?? [],
      isLiked: json['is_liked'] ?? false,
      thumbnailUrl: json['thumbnail_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'caption': caption,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'username': username,
      'avatar_url': avatarUrl,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'comments': comments.map((comment) => comment.toJson()).toList(),
      'is_liked': isLiked,
      'thumbnail_url': thumbnailUrl,
    };
  }

  // Check if post was edited
  bool get isEdited => createdAt != updatedAt;

  Post copyWith({
    String? id,
    String? userId,
    String? caption,
    String? mediaUrl,
    String? mediaType,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? username,
    String? avatarUrl,
    int? likesCount,
    int? commentsCount,
    List<Comment>? comments,
    bool? isLiked,
    String? thumbnailUrl,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      caption: caption ?? this.caption,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      comments: comments ?? this.comments,
      isLiked: isLiked ?? this.isLiked,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }
}

class Comment {
  final String id;
  final String content;
  final String userId;
  final String? username;
  final String? avatarUrl;
  final String? parentCommentId;
  final DateTime createdAt;
  final int likesCount;
  final int dislikesCount;
  final bool isLiked;
  final bool isDisliked;

  Comment({
    required this.id,
    required this.content,
    required this.userId,
    this.username,
    this.avatarUrl,
    this.parentCommentId,
    required this.createdAt,
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.isLiked = false,
    this.isDisliked = false,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      userId: json['user_id'] ?? '',
      username: json['profiles']?['username'],
      avatarUrl: json['profiles']?['avatar_url'],
      parentCommentId: json['parent_comment_id'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      likesCount: json['likes_count'] ?? 0,
      dislikesCount: json['dislikes_count'] ?? 0,
      isLiked: json['is_liked'] ?? false,
      isDisliked: json['is_disliked'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'user_id': userId,
      'username': username,
      'avatar_url': avatarUrl,
      'parent_comment_id': parentCommentId,
      'created_at': createdAt.toIso8601String(),
      'likes_count': likesCount,
      'dislikes_count': dislikesCount,
      'is_liked': isLiked,
      'is_disliked': isDisliked,
    };
  }

  Comment copyWith({
    String? id,
    String? content,
    String? userId,
    String? username,
    String? avatarUrl,
    String? parentCommentId,
    DateTime? createdAt,
    int? likesCount,
    int? dislikesCount,
    bool? isLiked,
    bool? isDisliked,
  }) {
    return Comment(
      id: id ?? this.id,
      content: content ?? this.content,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      createdAt: createdAt ?? this.createdAt,
      likesCount: likesCount ?? this.likesCount,
      dislikesCount: dislikesCount ?? this.dislikesCount,
      isLiked: isLiked ?? this.isLiked,
      isDisliked: isDisliked ?? this.isDisliked,
    );
  }
}
