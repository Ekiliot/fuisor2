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
  final String? city; // City name
  final String? district; // District/neighborhood
  final String? street; // Street name
  final String? address; // Specific address
  final String? country; // Country name
  final String? locationVisibility; // What to show: 'country', 'city', 'district', 'street', 'address' or comma-separated combination

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
    this.city,
    this.district,
    this.street,
    this.address,
    this.country,
    this.locationVisibility,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
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
      city: json['city'],
      district: json['district'],
      street: json['street'],
      address: json['address'],
      country: json['country'],
      locationVisibility: json['location_visibility'],
    );
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
      'city': city,
      'district': district,
      'street': street,
      'address': address,
      'country': country,
      'location_visibility': locationVisibility,
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
    String? city,
    String? district,
    String? street,
    String? address,
    String? country,
    String? locationVisibility,
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
      city: city ?? this.city,
      district: district ?? this.district,
      street: street ?? this.street,
      address: address ?? this.address,
      country: country ?? this.country,
      locationVisibility: locationVisibility ?? this.locationVisibility,
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

/// Location information for recommendations
class LocationInfo {
  final String? country;
  final String? city;
  final String? district;
  final String? street;
  final String? address;

  LocationInfo({
    this.country,
    this.city,
    this.district,
    this.street,
    this.address,
  });

  factory LocationInfo.fromJson(Map<String, dynamic> json) {
    return LocationInfo(
      country: json['country'],
      city: json['city'],
      district: json['district'],
      street: json['street'],
      address: json['address'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'country': country,
      'city': city,
      'district': district,
      'street': street,
      'address': address,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationInfo &&
        other.country == country &&
        other.city == city &&
        other.district == district;
  }

  @override
  int get hashCode => country.hashCode ^ city.hashCode ^ district.hashCode;

  @override
  String toString() {
    final parts = <String>[];
    if (district != null && district!.isNotEmpty) parts.add(district!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (country != null && country!.isNotEmpty) parts.add(country!);
    return parts.join(', ');
  }
}

/// Location suggestion based on user interactions
class LocationSuggestion {
  final String district;
  final String city;
  final String country;
  final int interactionCount;

  LocationSuggestion({
    required this.district,
    required this.city,
    required this.country,
    required this.interactionCount,
  });

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    return LocationSuggestion(
      district: json['district'] ?? '',
      city: json['city'] ?? '',
      country: json['country'] ?? '',
      interactionCount: json['interactionCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'district': district,
      'city': city,
      'country': country,
      'interactionCount': interactionCount,
    };
  }

  @override
  String toString() {
    return '$district, $city ($interactionCount interactions)';
  }
}

/// Recommendation settings for personalized feed
class RecommendationSettings {
  final List<LocationInfo> locations; // Up to 3 locations
  final int? radius; // in meters (0-100000)
  final bool autoLocation;
  final bool enabled;
  final bool promptShown;
  final bool explorerModeEnabled;
  final DateTime? explorerModeExpiresAt;

  RecommendationSettings({
    this.locations = const [],
    this.radius,
    this.autoLocation = false,
    this.enabled = false,
    this.promptShown = false,
    this.explorerModeEnabled = false,
    this.explorerModeExpiresAt,
  });

  /// Check if explorer mode is currently active
  bool get isExplorerModeActive {
    if (!explorerModeEnabled) return false;
    if (explorerModeExpiresAt == null) return false;
    return DateTime.now().isBefore(explorerModeExpiresAt!);
  }

  /// Get remaining time for explorer mode in minutes
  int? get explorerModeRemainingMinutes {
    if (!isExplorerModeActive) return null;
    final remaining = explorerModeExpiresAt!.difference(DateTime.now());
    return remaining.inMinutes;
  }

  factory RecommendationSettings.fromJson(Map<String, dynamic> json) {
    final locationsList = json['locations'] as List<dynamic>? ?? [];
    final locations = locationsList
        .map((loc) => LocationInfo.fromJson(loc as Map<String, dynamic>))
        .toList();

    return RecommendationSettings(
      locations: locations,
      radius: json['radius'],
      autoLocation: json['autoLocation'] ?? false,
      enabled: json['enabled'] ?? false,
      promptShown: json['promptShown'] ?? false,
      explorerModeEnabled: json['explorerModeEnabled'] ?? false,
      explorerModeExpiresAt: json['explorerModeExpiresAt'] != null
          ? DateTime.parse(json['explorerModeExpiresAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'locations': locations.map((loc) => loc.toJson()).toList(),
      'radius': radius,
      'autoLocation': autoLocation,
      'enabled': enabled,
      'promptShown': promptShown,
      'explorerModeEnabled': explorerModeEnabled,
      'explorerModeExpiresAt': explorerModeExpiresAt?.toIso8601String(),
    };
  }

  RecommendationSettings copyWith({
    List<LocationInfo>? locations,
    int? radius,
    bool? autoLocation,
    bool? enabled,
    bool? promptShown,
    bool? explorerModeEnabled,
    DateTime? explorerModeExpiresAt,
  }) {
    return RecommendationSettings(
      locations: locations ?? this.locations,
      radius: radius ?? this.radius,
      autoLocation: autoLocation ?? this.autoLocation,
      enabled: enabled ?? this.enabled,
      promptShown: promptShown ?? this.promptShown,
      explorerModeEnabled: explorerModeEnabled ?? this.explorerModeEnabled,
      explorerModeExpiresAt: explorerModeExpiresAt ?? this.explorerModeExpiresAt,
    );
  }
}
