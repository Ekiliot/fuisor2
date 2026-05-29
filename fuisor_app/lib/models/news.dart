import 'user.dart';

class NewsCategory {
  final String id;
  final String nameEn;
  final String nameRu;
  final String? icon;
  final int orderIndex;

  NewsCategory({
    required this.id,
    required this.nameEn,
    required this.nameRu,
    this.icon,
    required this.orderIndex,
  });

  factory NewsCategory.fromJson(Map<String, dynamic> json) {
    return NewsCategory(
      id: json['id'] ?? '',
      nameEn: json['name_en'] ?? '',
      nameRu: json['name_ru'] ?? '',
      icon: json['icon'],
      orderIndex: json['order_index'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name_en': nameEn,
      'name_ru': nameRu,
      'icon': icon,
      'order_index': orderIndex,
    };
  }
}

class NewsSubcategory {
  final String id;
  final String categoryId;
  final String nameEn;
  final String nameRu;
  final int orderIndex;

  NewsSubcategory({
    required this.id,
    required this.categoryId,
    required this.nameEn,
    required this.nameRu,
    required this.orderIndex,
  });

  factory NewsSubcategory.fromJson(Map<String, dynamic> json) {
    return NewsSubcategory(
      id: json['id'] ?? '',
      categoryId: json['category_id'] ?? '',
      nameEn: json['name_en'] ?? '',
      nameRu: json['name_ru'] ?? '',
      orderIndex: json['order_index'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'name_en': nameEn,
      'name_ru': nameRu,
      'order_index': orderIndex,
    };
  }
}

class News {
  final String id;
  final String userId;
  final String title;
  final String content;
  final String? sanitizedContent;
  final String categoryId;
  final String? subcategoryId;
  final String? coverImageUrl;
  final String? coauthorUserId;
  final User? coauthor;
  final String? externalLinkUrl;
  final String? externalLinkText;
  final int viewsCount;
  final int likesCount;
  final int commentsCount;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? user; // Author info
  final NewsCategory? category;
  final NewsSubcategory? subcategory;
  final bool isLiked;

  News({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    this.sanitizedContent,
    required this.categoryId,
    this.subcategoryId,
    this.coverImageUrl,
    this.coauthorUserId,
    this.coauthor,
    this.externalLinkUrl,
    this.externalLinkText,
    required this.viewsCount,
    required this.likesCount,
    required this.commentsCount,
    required this.isPublished,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.category,
    this.subcategory,
    required this.isLiked,
  });

  factory News.fromJson(Map<String, dynamic> json) {
    // Parse user (author)
    User? user;
    if (json['profiles'] != null) {
      user = User.fromProfileJson(json['profiles']);
    }

    // Parse coauthor
    User? coauthor;
    String? coauthorUserId;
    if (json['coauthor'] != null) {
      coauthor = User.fromProfileJson(json['coauthor']);
      coauthorUserId = coauthor.id;
    } else if (json['coauthor_user_id'] != null) {
      coauthorUserId = json['coauthor_user_id'];
    }

    // Parse category
    NewsCategory? category;
    if (json['category'] != null) {
      category = NewsCategory.fromJson(json['category']);
    }

    // Parse subcategory
    NewsSubcategory? subcategory;
    if (json['subcategory'] != null) {
      subcategory = NewsSubcategory.fromJson(json['subcategory']);
    }

    return News(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      sanitizedContent: json['sanitized_content'],
      categoryId: json['category_id'] ?? '',
      subcategoryId: json['subcategory_id'],
      coverImageUrl: json['cover_image_url'],
      coauthorUserId: coauthorUserId,
      coauthor: coauthor,
      externalLinkUrl: json['external_link_url'],
      externalLinkText: json['external_link_text'],
      viewsCount: json['views_count'] ?? 0,
      likesCount: json['likes_count'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
      isPublished: json['is_published'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
      user: user,
      category: category,
      subcategory: subcategory,
      isLiked: json['is_liked'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'content': content,
      'sanitized_content': sanitizedContent,
      'category_id': categoryId,
      'subcategory_id': subcategoryId,
      'cover_image_url': coverImageUrl,
      'coauthor_user_id': coauthorUserId,
      'external_link_url': externalLinkUrl,
      'external_link_text': externalLinkText,
      'views_count': viewsCount,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'is_published': isPublished,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_liked': isLiked,
    };
  }

  News copyWith({
    String? id,
    String? userId,
    String? title,
    String? content,
    String? sanitizedContent,
    String? categoryId,
    String? subcategoryId,
    String? coverImageUrl,
    String? coauthorUserId,
    User? coauthor,
    String? externalLinkUrl,
    String? externalLinkText,
    int? viewsCount,
    int? likesCount,
    int? commentsCount,
    bool? isPublished,
    DateTime? createdAt,
    DateTime? updatedAt,
    User? user,
    NewsCategory? category,
    NewsSubcategory? subcategory,
    bool? isLiked,
  }) {
    return News(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      content: content ?? this.content,
      sanitizedContent: sanitizedContent ?? this.sanitizedContent,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      coauthorUserId: coauthorUserId ?? this.coauthorUserId,
      coauthor: coauthor ?? this.coauthor,
      externalLinkUrl: externalLinkUrl ?? this.externalLinkUrl,
      externalLinkText: externalLinkText ?? this.externalLinkText,
      viewsCount: viewsCount ?? this.viewsCount,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      user: user ?? this.user,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

