class User {
  final String id;
  final String username;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? bio;
  final String? websiteUrl;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final DateTime createdAt;
  final String? locationVisibility; // 'nobody', 'mutual_followers', 'followers', 'close_friends'
  final bool? locationSharingEnabled;
  final bool? hasStories; // Whether user has active stories

  User({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.bio,
    this.websiteUrl,
    required this.followersCount,
    required this.followingCount,
    required this.postsCount,
    required this.createdAt,
    this.locationVisibility,
    this.locationSharingEnabled,
    this.hasStories,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '', // Email может отсутствовать для некоторых запросов
      avatarUrl: json['avatar_url'],
      bio: json['bio'],
      websiteUrl: json['website_url'],
      followersCount: json['followers_count'] ?? 0,
      followingCount: json['following_count'] ?? 0,
      postsCount: json['posts_count'] ?? 0,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      locationVisibility: json['location_visibility'],
      locationSharingEnabled: json['location_sharing_enabled'],
      hasStories: json['hasStories'],
    );
  }

  // Фабрика для создания User из профиля (без email и других опциональных полей)
  factory User.fromProfileJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      name: json['name'] ?? '',
      email: '', // Email не требуется для профилей
      avatarUrl: json['avatar_url'],
      bio: json['bio'],
      websiteUrl: json['website_url'],
      followersCount: 0, // Могут отсутствовать для участников чата
      followingCount: 0,
      postsCount: 0,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      locationVisibility: json['location_visibility'],
      locationSharingEnabled: json['location_sharing_enabled'],
      hasStories: json['hasStories'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'name': name,
      'email': email,
      'avatar_url': avatarUrl,
      'bio': bio,
      'website_url': websiteUrl,
      'followers_count': followersCount,
      'following_count': followingCount,
      'posts_count': postsCount,
      'created_at': createdAt.toIso8601String(),
      'location_visibility': locationVisibility,
      'location_sharing_enabled': locationSharingEnabled,
    };
  }
}

class Post {
  final String id;
  final String userId;
  final String caption;
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'
  final int likesCount;
  final int commentsCount;
  final List<String> mentions;
  final List<String> hashtags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? user; // Author info
  final List<Comment>? comments;
  final bool isLiked;
  final bool isSaved;
  final String? thumbnailUrl;
  final double? latitude; // For geo-posts
  final double? longitude; // For geo-posts
  final String? visibility; // 'public', 'friends', 'private'
  final DateTime? expiresAt; // Expiration time for geo-posts
  final User? coauthor; // Post coauthor
  final String? externalLinkUrl; // External link URL
  final String? externalLinkText; // External link button text (6-8 characters)

  Post({
    required this.id,
    required this.userId,
    required this.caption,
    required this.mediaUrl,
    required this.mediaType,
    required this.likesCount,
    required this.commentsCount,
    required this.mentions,
    required this.hashtags,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.comments,
    this.isLiked = false,
    this.isSaved = false,
    this.thumbnailUrl,
    this.latitude,
    this.longitude,
    this.visibility,
    this.expiresAt,
    this.coauthor,
    this.externalLinkUrl,
    this.externalLinkText,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    // Debug: log coauthor data for specific post
    final postId = json['id'] ?? '';
    if (postId == '5bad2462-d6a1-4644-abe6-6f4f8c59994c') {
      print('Post.fromJson DEBUG for post $postId:');
      print('  - coauthor field: ${json['coauthor']}');
      print('  - post_coauthors field: ${json['post_coauthors']}');
      if (json['post_coauthors'] != null) {
        print('  - post_coauthors type: ${json['post_coauthors'].runtimeType}');
        if (json['post_coauthors'] is List && (json['post_coauthors'] as List).isNotEmpty) {
          print('  - first post_coauthor: ${json['post_coauthors'][0]}');
          print('  - first coauthor field: ${json['post_coauthors'][0]?['coauthor']}');
        }
      }
    }
    
    return Post(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      caption: json['caption'] ?? '',
      mediaUrl: json['media_url'] ?? '',
      mediaType: json['media_type'] ?? 'image',
      likesCount: json['likes_count'] ?? 0,
      // Используем comments_count из API, если есть, иначе считаем из массива comments
      commentsCount: json['comments_count'] ?? json['comments']?.length ?? 0,
      mentions: List<String>.from(json['mentions'] ?? []),
      hashtags: List<String>.from(json['hashtags'] ?? []),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
      user: json['profiles'] != null ? User.fromJson(json['profiles']) : null,
      comments: json['comments'] != null 
          ? (json['comments'] as List).map((c) => Comment.fromJson(c)).toList()
          : null,
      isLiked: json['is_liked'] ?? false,
      isSaved: json['is_saved'] ?? false,
      thumbnailUrl: json['thumbnail_url'],
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      visibility: json['visibility'],
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      coauthor: json['coauthor'] != null ? User.fromJson(json['coauthor']) : null,
      externalLinkUrl: json['external_link_url'],
      externalLinkText: json['external_link_text'],
    );
  }
  
  // Debug method to log coauthor data
  static void logCoauthorData(Map<String, dynamic> json, String postId) {
    print('Post.fromJson DEBUG for post $postId:');
    print('  - coauthor field: ${json['coauthor']}');
    print('  - post_coauthors field: ${json['post_coauthors']}');
    if (json['post_coauthors'] != null) {
      print('  - post_coauthors type: ${json['post_coauthors'].runtimeType}');
      if (json['post_coauthors'] is List && (json['post_coauthors'] as List).isNotEmpty) {
        print('  - first post_coauthor: ${json['post_coauthors'][0]}');
        print('  - first coauthor field: ${json['post_coauthors'][0]?['coauthor']}');
      }
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'caption': caption,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'mentions': mentions,
      'hashtags': hashtags,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'profiles': user?.toJson(),
      'comments': comments?.map((c) => c.toJson()).toList(),
      'is_liked': isLiked,
      'is_saved': isSaved,
      'thumbnail_url': thumbnailUrl,
      'latitude': latitude,
      'longitude': longitude,
      'visibility': visibility,
      'expires_at': expiresAt?.toIso8601String(),
      'coauthor': coauthor?.toJson(),
      'external_link_url': externalLinkUrl,
      'external_link_text': externalLinkText,
    };
  }

  Post copyWith({
    String? id,
    String? userId,
    String? caption,
    String? mediaUrl,
    String? mediaType,
    int? likesCount,
    int? commentsCount,
    List<String>? mentions,
    List<String>? hashtags,
    DateTime? createdAt,
    DateTime? updatedAt,
    User? user,
    List<Comment>? comments,
    bool? isLiked,
    bool? isSaved,
    String? thumbnailUrl,
    double? latitude,
    double? longitude,
    String? visibility,
    DateTime? expiresAt,
    User? coauthor,
    String? externalLinkUrl,
    String? externalLinkText,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      caption: caption ?? this.caption,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      mentions: mentions ?? this.mentions,
      hashtags: hashtags ?? this.hashtags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      user: user ?? this.user,
      comments: comments ?? this.comments,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      visibility: visibility ?? this.visibility,
      expiresAt: expiresAt ?? this.expiresAt,
      coauthor: coauthor ?? this.coauthor,
      externalLinkUrl: externalLinkUrl ?? this.externalLinkUrl,
      externalLinkText: externalLinkText ?? this.externalLinkText,
    );
  }
}

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String content;
  final String? parentCommentId;
  final DateTime createdAt;
  final User? user;
  final List<Comment>? replies;
  final int likesCount;
  final int dislikesCount;
  final bool isLiked;
  final bool isDisliked;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    this.parentCommentId,
    required this.createdAt,
    this.user,
    this.replies,
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.isLiked = false,
    this.isDisliked = false,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] ?? '',
      postId: json['post_id'] ?? '',
      userId: json['user_id'] ?? '',
      content: json['content'] ?? '',
      parentCommentId: json['parent_comment_id'],
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      user: json['profiles'] != null ? User.fromJson(json['profiles']) : null,
      replies: json['replies'] != null 
          ? (json['replies'] as List).map((r) => Comment.fromJson(r)).toList()
          : null,
      likesCount: json['likes_count'] ?? 0,
      dislikesCount: json['dislikes_count'] ?? 0,
      isLiked: json['is_liked'] ?? false,
      isDisliked: json['is_disliked'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'post_id': postId,
      'user_id': userId,
      'content': content,
      'parent_comment_id': parentCommentId,
      'created_at': createdAt.toIso8601String(),
      'profiles': user?.toJson(),
      'replies': replies?.map((r) => r.toJson()).toList(),
      'likes_count': likesCount,
      'dislikes_count': dislikesCount,
      'is_liked': isLiked,
      'is_disliked': isDisliked,
    };
  }

  Comment copyWith({
    String? id,
    String? postId,
    String? userId,
    String? content,
    String? parentCommentId,
    DateTime? createdAt,
    User? user,
    List<Comment>? replies,
    int? likesCount,
    int? dislikesCount,
    bool? isLiked,
    bool? isDisliked,
  }) {
    return Comment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      createdAt: createdAt ?? this.createdAt,
      user: user ?? this.user,
      replies: replies ?? this.replies,
      likesCount: likesCount ?? this.likesCount,
      dislikesCount: dislikesCount ?? this.dislikesCount,
      isLiked: isLiked ?? this.isLiked,
      isDisliked: isDisliked ?? this.isDisliked,
    );
  }
}

class NotificationModel {
  final String id;
  final String userId;
  final String actorId;
  final String type; // 'like', 'comment', 'follow', 'mention'
  final String? postId;
  final String? commentId;
  final bool isRead;
  final DateTime createdAt;
  final User? actor;
  final Post? post;
  final Comment? comment;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.actorId,
    required this.type,
    this.postId,
    this.commentId,
    required this.isRead,
    required this.createdAt,
    this.actor,
    this.post,
    this.comment,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      actorId: json['actor_id'] ?? '',
      type: json['type'] ?? '',
      postId: json['post_id'],
      commentId: json['comment_id'],
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      actor: json['actor'] != null ? User.fromJson(json['actor']) : null,
      post: json['post'] != null ? Post.fromJson(json['post']) : null,
      comment: json['comment'] != null ? Comment.fromJson(json['comment']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'actor_id': actorId,
      'type': type,
      'post_id': postId,
      'comment_id': commentId,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'actor': actor?.toJson(),
      'post': post?.toJson(),
      'comment': comment?.toJson(),
    };
  }
}

class AuthResponse {
  final User user;
  final String accessToken;
  final String refreshToken;
  final User? profile;

  AuthResponse({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.profile,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: User.fromJson(json['user'] ?? {}),
      accessToken: json['session']?['access_token'] ?? '',
      refreshToken: json['session']?['refresh_token'] ?? '',
      profile: json['profile'] != null ? User.fromJson(json['profile']) : null,
    );
  }
}
