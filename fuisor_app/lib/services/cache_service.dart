import 'package:hive_flutter/hive_flutter.dart';
import '../models/user.dart';

/// Сервис для кеширования данных приложения
/// Использует Hive для быстрого локального хранения
/// Реализован как синглтон для единого экземпляра во всем приложении
class CacheService {
  // Синглтон экземпляр
  static CacheService? _instance;
  
  // Приватный конструктор
  CacheService._internal();
  
  // Фабричный конструктор для получения экземпляра
  factory CacheService() {
    _instance ??= CacheService._internal();
    return _instance!;
  }

  // Имена боксов для разных типов данных
  static const String _postsBoxName = 'posts_cache';
  static const String _commentsBoxName = 'comments_cache';
  static const String _usersBoxName = 'users_cache';
  static const String _feedBoxName = 'feed_cache';
  static const String _hashtagPostsBoxName = 'hashtag_posts_cache';
  static const String _userPostsBoxName = 'user_posts_cache';
  static const String _videoPostsBoxName = 'video_posts_cache';
  static const String _mentionedPostsBoxName = 'mentioned_posts_cache';

  // Боксы для хранения данных (используем dynamic для гибкости)
  late Box _postsBox;
  late Box _commentsBox;
  late Box _usersBox;
  late Box _feedBox;
  late Box _hashtagPostsBox;
  late Box _userPostsBox;
  late Box _videoPostsBox;
  late Box _mentionedPostsBox;

  bool _isInitialized = false;

  /// Инициализация всех боксов
  Future<void> init() async {
    if (_isInitialized) {
      print('CacheService: Already initialized, skipping...');
      return;
    }

    print('CacheService: Initializing Hive...');
    await Hive.initFlutter();

    print('CacheService: Opening boxes...');
    _postsBox = await Hive.openBox(_postsBoxName);
    print('CacheService: ✓ Posts box opened (${_postsBox.length} items)');
    
    _commentsBox = await Hive.openBox(_commentsBoxName);
    print('CacheService: ✓ Comments box opened (${_commentsBox.length} items)');
    
    _usersBox = await Hive.openBox(_usersBoxName);
    print('CacheService: ✓ Users box opened (${_usersBox.length} items)');
    
    _feedBox = await Hive.openBox(_feedBoxName);
    print('CacheService: ✓ Feed box opened (${_feedBox.length} items)');
    
    _hashtagPostsBox = await Hive.openBox(_hashtagPostsBoxName);
    print('CacheService: ✓ Hashtag posts box opened (${_hashtagPostsBox.length} items)');
    
    _userPostsBox = await Hive.openBox(_userPostsBoxName);
    print('CacheService: ✓ User posts box opened (${_userPostsBox.length} items)');
    
    _videoPostsBox = await Hive.openBox(_videoPostsBoxName);
    print('CacheService: ✓ Video posts box opened (${_videoPostsBox.length} items)');
    
    _mentionedPostsBox = await Hive.openBox(_mentionedPostsBoxName);
    print('CacheService: ✓ Mentioned posts box opened (${_mentionedPostsBox.length} items)');

    _isInitialized = true;
    print('CacheService: ✅ Initialized successfully. Total cache size: ${getCacheSize()} items');
  }

  // ==================== ПОСТЫ ====================

  /// Кеширование списка постов
  Future<void> cachePosts(List<Post> posts, {String? key}) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot cache posts - service not initialized');
      return;
    }

    final cacheKey = key ?? 'all_posts';
    final postsJson = posts.map((p) => p.toJson()).toList();
    final timestamp = DateTime.now();
    
    print('CacheService: 💾 Caching ${posts.length} posts with key: "$cacheKey"');
    await _postsBox.put(cacheKey, postsJson);
    await _postsBox.put('${cacheKey}_timestamp', timestamp.toIso8601String());
    
    print('CacheService: ✅ Successfully cached ${posts.length} posts (key: "$cacheKey", timestamp: ${timestamp.toIso8601String()})');
  }

  /// Получение закешированных постов
  List<Post>? getCachedPosts({String? key}) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cached posts - service not initialized');
      return null;
    }

    final cacheKey = key ?? 'all_posts';
    print('CacheService: 🔍 Looking for cached posts with key: "$cacheKey"');
    
    final postsJson = _postsBox.get(cacheKey);
    
    if (postsJson == null || postsJson is! List) {
      print('CacheService: ❌ No cached posts found for key: "$cacheKey"');
      return null;
    }

    try {
      final posts = postsJson
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      print('CacheService: ✅ Retrieved ${posts.length} cached posts (key: "$cacheKey")');
      return posts;
    } catch (e) {
      print('CacheService: ❌ Error parsing cached posts (key: "$cacheKey"): $e');
      return null;
    }
  }

  /// Проверка актуальности кеша постов
  bool isPostsCacheValid({String? key, Duration maxAge = const Duration(minutes: 5)}) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot check cache validity - service not initialized');
      return false;
    }

    final cacheKey = key ?? 'all_posts';
    final timestampStr = _postsBox.get('${cacheKey}_timestamp');
    
    if (timestampStr == null || timestampStr is! String) {
      print('CacheService: ❌ Cache validity check failed - no timestamp found (key: "$cacheKey")');
      return false;
    }

    try {
      final timestamp = DateTime.parse(timestampStr);
      final age = DateTime.now().difference(timestamp);
      final isValid = age < maxAge;
      
      print('CacheService: ${isValid ? "✅" : "❌"} Cache validity check (key: "$cacheKey"): ${isValid ? "VALID" : "EXPIRED"} - age: ${age.inMinutes}min, max: ${maxAge.inMinutes}min');
      return isValid;
    } catch (e) {
      print('CacheService: ❌ Error parsing timestamp (key: "$cacheKey"): $e');
      return false;
    }
  }

  // ==================== FEED ====================

  /// Кеширование feed постов
  Future<void> cacheFeed(List<Post> posts) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot cache feed - service not initialized');
      return;
    }

    final postsJson = posts.map((p) => p.toJson()).toList();
    final timestamp = DateTime.now();
    
    print('CacheService: 💾 Caching ${posts.length} feed posts');
    await _feedBox.put('feed', postsJson);
    await _feedBox.put('feed_timestamp', timestamp.toIso8601String());
    
    print('CacheService: ✅ Successfully cached ${posts.length} feed posts (timestamp: ${timestamp.toIso8601String()})');
  }

  /// Получение закешированного feed
  List<Post>? getCachedFeed() {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cached feed - service not initialized');
      return null;
    }

    print('CacheService: 🔍 Looking for cached feed');
    final postsJson = _feedBox.get('feed');
    
    if (postsJson == null || postsJson is! List) {
      print('CacheService: ❌ No cached feed found');
      return null;
    }

    try {
      final posts = postsJson
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      print('CacheService: ✅ Retrieved ${posts.length} cached feed posts');
      return posts;
    } catch (e) {
      print('CacheService: ❌ Error parsing cached feed: $e');
      return null;
    }
  }

  /// Проверка актуальности кеша feed
  bool isFeedCacheValid({Duration maxAge = const Duration(minutes: 5)}) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot check feed cache validity - service not initialized');
      return false;
    }

    final timestampStr = _feedBox.get('feed_timestamp');
    if (timestampStr == null || timestampStr is! String) {
      print('CacheService: ❌ Feed cache validity check failed - no timestamp found');
      return false;
    }

    try {
      final timestamp = DateTime.parse(timestampStr);
      final age = DateTime.now().difference(timestamp);
      final isValid = age < maxAge;
      
      print('CacheService: ${isValid ? "✅" : "❌"} Feed cache validity: ${isValid ? "VALID" : "EXPIRED"} - age: ${age.inMinutes}min, max: ${maxAge.inMinutes}min');
      return isValid;
    } catch (e) {
      print('CacheService: ❌ Error parsing feed timestamp: $e');
      return false;
    }
  }

  // ==================== VIDEO POSTS ====================

  /// Кеширование видео постов
  Future<void> cacheVideoPosts(List<Post> posts) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot cache video posts - service not initialized');
      return;
    }

    final postsJson = posts.map((p) => p.toJson()).toList();
    final timestamp = DateTime.now();
    
    print('CacheService: 💾 Caching ${posts.length} video posts');
    await _videoPostsBox.put('video_posts', postsJson);
    await _videoPostsBox.put('video_posts_timestamp', timestamp.toIso8601String());
    
    print('CacheService: ✅ Successfully cached ${posts.length} video posts');
  }

  /// Получение закешированных видео постов
  List<Post>? getCachedVideoPosts() {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cached video posts - service not initialized');
      return null;
    }

    print('CacheService: 🔍 Looking for cached video posts');
    final postsJson = _videoPostsBox.get('video_posts');
    
    if (postsJson == null || postsJson is! List) {
      print('CacheService: ❌ No cached video posts found');
      return null;
    }

    try {
      final posts = postsJson
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      print('CacheService: ✅ Retrieved ${posts.length} cached video posts');
      return posts;
    } catch (e) {
      print('CacheService: ❌ Error parsing cached video posts: $e');
      return null;
    }
  }

  // ==================== HASHTAG POSTS ====================

  /// Кеширование постов по хештегу
  Future<void> cacheHashtagPosts(String hashtag, List<Post> posts) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot cache hashtag posts - service not initialized');
      return;
    }

    final postsJson = posts.map((p) => p.toJson()).toList();
    final timestamp = DateTime.now();
    
    print('CacheService: 💾 Caching ${posts.length} posts for hashtag: "$hashtag"');
    await _hashtagPostsBox.put(hashtag, postsJson);
    await _hashtagPostsBox.put('${hashtag}_timestamp', timestamp.toIso8601String());
    
    print('CacheService: ✅ Successfully cached ${posts.length} posts for hashtag: "$hashtag"');
  }

  /// Получение закешированных постов по хештегу
  List<Post>? getCachedHashtagPosts(String hashtag) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cached hashtag posts - service not initialized');
      return null;
    }

    print('CacheService: 🔍 Looking for cached posts for hashtag: "$hashtag"');
    final postsJson = _hashtagPostsBox.get(hashtag);
    
    if (postsJson == null || postsJson is! List) {
      print('CacheService: ❌ No cached posts found for hashtag: "$hashtag"');
      return null;
    }

    try {
      final posts = postsJson
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      print('CacheService: ✅ Retrieved ${posts.length} cached posts for hashtag: "$hashtag"');
      return posts;
    } catch (e) {
      print('CacheService: ❌ Error parsing cached hashtag posts (hashtag: "$hashtag"): $e');
      return null;
    }
  }

  // ==================== USER POSTS ====================

  /// Кеширование постов пользователя
  Future<void> cacheUserPosts(String userId, List<Post> posts) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot cache user posts - service not initialized');
      return;
    }

    final postsJson = posts.map((p) => p.toJson()).toList();
    final timestamp = DateTime.now();
    
    print('CacheService: 💾 Caching ${posts.length} posts for user: "$userId"');
    await _userPostsBox.put(userId, postsJson);
    await _userPostsBox.put('${userId}_timestamp', timestamp.toIso8601String());
    
    print('CacheService: ✅ Successfully cached ${posts.length} posts for user: "$userId"');
  }

  /// Получение закешированных постов пользователя
  List<Post>? getCachedUserPosts(String userId) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cached user posts - service not initialized');
      return null;
    }

    print('CacheService: 🔍 Looking for cached posts for user: "$userId"');
    final postsJson = _userPostsBox.get(userId);
    
    if (postsJson == null || postsJson is! List) {
      print('CacheService: ❌ No cached posts found for user: "$userId"');
      return null;
    }

    try {
      final posts = postsJson
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      print('CacheService: ✅ Retrieved ${posts.length} cached posts for user: "$userId"');
      return posts;
    } catch (e) {
      print('CacheService: ❌ Error parsing cached user posts (userId: "$userId"): $e');
      return null;
    }
  }

  // ==================== MENTIONED POSTS ====================

  /// Кеширование постов с упоминаниями
  Future<void> cacheMentionedPosts(List<Post> posts) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot cache mentioned posts - service not initialized');
      return;
    }

    final postsJson = posts.map((p) => p.toJson()).toList();
    final timestamp = DateTime.now();
    
    print('CacheService: 💾 Caching ${posts.length} mentioned posts');
    await _mentionedPostsBox.put('mentioned', postsJson);
    await _mentionedPostsBox.put('mentioned_timestamp', timestamp.toIso8601String());
    
    print('CacheService: ✅ Successfully cached ${posts.length} mentioned posts');
  }

  /// Получение закешированных постов с упоминаниями
  List<Post>? getCachedMentionedPosts() {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cached mentioned posts - service not initialized');
      return null;
    }

    print('CacheService: 🔍 Looking for cached mentioned posts');
    final postsJson = _mentionedPostsBox.get('mentioned');
    
    if (postsJson == null || postsJson is! List) {
      print('CacheService: ❌ No cached mentioned posts found');
      return null;
    }

    try {
      final posts = postsJson
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      print('CacheService: ✅ Retrieved ${posts.length} cached mentioned posts');
      return posts;
    } catch (e) {
      print('CacheService: ❌ Error parsing cached mentioned posts: $e');
      return null;
    }
  }

  // ==================== КОММЕНТАРИИ ====================

  /// Кеширование комментариев для поста
  Future<void> cacheComments(String postId, List<Comment> comments) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot cache comments - service not initialized');
      return;
    }

    final commentsJson = comments.map((c) => c.toJson()).toList();
    final timestamp = DateTime.now();
    
    print('CacheService: 💾 Caching ${comments.length} comments for post: "$postId"');
    await _commentsBox.put(postId, commentsJson);
    await _commentsBox.put('${postId}_timestamp', timestamp.toIso8601String());
    
    print('CacheService: ✅ Successfully cached ${comments.length} comments for post: "$postId"');
  }

  /// Получение закешированных комментариев
  List<Comment>? getCachedComments(String postId) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cached comments - service not initialized');
      return null;
    }

    print('CacheService: 🔍 Looking for cached comments for post: "$postId"');
    final commentsJson = _commentsBox.get(postId);
    
    if (commentsJson == null || commentsJson is! List) {
      print('CacheService: ❌ No cached comments found for post: "$postId"');
      return null;
    }

    try {
      final comments = commentsJson
          .map((json) => Comment.fromJson(json as Map<String, dynamic>))
          .toList();
      print('CacheService: ✅ Retrieved ${comments.length} cached comments for post: "$postId"');
      return comments;
    } catch (e) {
      print('CacheService: ❌ Error parsing cached comments (postId: "$postId"): $e');
      return null;
    }
  }

  /// Проверка актуальности кеша комментариев
  bool isCommentsCacheValid(String postId, {Duration maxAge = const Duration(minutes: 10)}) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot check comments cache validity - service not initialized');
      return false;
    }

    final timestampStr = _commentsBox.get('${postId}_timestamp');
    if (timestampStr == null || timestampStr is! String) {
      print('CacheService: ❌ Comments cache validity check failed - no timestamp found (postId: "$postId")');
      return false;
    }

    try {
      final timestamp = DateTime.parse(timestampStr);
      final age = DateTime.now().difference(timestamp);
      final isValid = age < maxAge;
      
      print('CacheService: ${isValid ? "✅" : "❌"} Comments cache validity (postId: "$postId"): ${isValid ? "VALID" : "EXPIRED"} - age: ${age.inMinutes}min, max: ${maxAge.inMinutes}min');
      return isValid;
    } catch (e) {
      print('CacheService: ❌ Error parsing comments timestamp (postId: "$postId"): $e');
      return false;
    }
  }

  /// Обновление комментариев в кеше (добавление нового)
  Future<void> addCommentToCache(String postId, Comment comment) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot add comment to cache - service not initialized');
      return;
    }

    print('CacheService: ➕ Adding comment to cache (postId: "$postId", commentId: "${comment.id}")');
    final existingComments = getCachedComments(postId) ?? [];
    existingComments.insert(0, comment);
    await cacheComments(postId, existingComments);
    print('CacheService: ✅ Comment added to cache (total comments: ${existingComments.length})');
  }

  // ==================== ПОЛЬЗОВАТЕЛИ ====================

  /// Кеширование пользователя
  Future<void> cacheUser(User user) async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot cache user - service not initialized');
      return;
    }

    final timestamp = DateTime.now();
    print('CacheService: 💾 Caching user: "${user.username}" (id: "${user.id}")');
    await _usersBox.put(user.id, user.toJson());
    await _usersBox.put('${user.id}_timestamp', timestamp.toIso8601String());
    print('CacheService: ✅ Successfully cached user: "${user.username}"');
  }

  /// Получение закешированного пользователя
  User? getCachedUser(String userId) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cached user - service not initialized');
      return null;
    }

    print('CacheService: 🔍 Looking for cached user: "$userId"');
    final userJson = _usersBox.get(userId);
    
    if (userJson == null || userJson is! Map) {
      print('CacheService: ❌ No cached user found: "$userId"');
      return null;
    }

    try {
      final user = User.fromJson(Map<String, dynamic>.from(userJson));
      print('CacheService: ✅ Retrieved cached user: "${user.username}" (id: "$userId")');
      return user;
    } catch (e) {
      print('CacheService: ❌ Error parsing cached user (userId: "$userId"): $e');
      return null;
    }
  }

  /// Проверка актуальности кеша пользователя
  bool isUserCacheValid(String userId, {Duration maxAge = const Duration(hours: 1)}) {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot check user cache validity - service not initialized');
      return false;
    }

    final timestampStr = _usersBox.get('${userId}_timestamp');
    if (timestampStr == null || timestampStr is! String) {
      print('CacheService: ❌ User cache validity check failed - no timestamp found (userId: "$userId")');
      return false;
    }

    try {
      final timestamp = DateTime.parse(timestampStr);
      final age = DateTime.now().difference(timestamp);
      final isValid = age < maxAge;
      
      print('CacheService: ${isValid ? "✅" : "❌"} User cache validity (userId: "$userId"): ${isValid ? "VALID" : "EXPIRED"} - age: ${age.inHours}h, max: ${maxAge.inHours}h');
      return isValid;
    } catch (e) {
      print('CacheService: ❌ Error parsing user timestamp (userId: "$userId"): $e');
      return false;
    }
  }

  // ==================== УПРАВЛЕНИЕ КЕШЕМ ====================

  /// Очистка всего кеша
  Future<void> clearAllCache() async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot clear cache - service not initialized');
      return;
    }

    final beforeSize = getCacheSize();
    print('CacheService: 🗑️ Clearing all cache (current size: $beforeSize items)');
    
    await _postsBox.clear();
    print('CacheService: ✓ Posts cache cleared');
    
    await _commentsBox.clear();
    print('CacheService: ✓ Comments cache cleared');
    
    await _feedBox.clear();
    print('CacheService: ✓ Feed cache cleared');
    
    await _hashtagPostsBox.clear();
    print('CacheService: ✓ Hashtag posts cache cleared');
    
    await _userPostsBox.clear();
    print('CacheService: ✓ User posts cache cleared');
    
    await _videoPostsBox.clear();
    print('CacheService: ✓ Video posts cache cleared');
    
    await _mentionedPostsBox.clear();
    print('CacheService: ✓ Mentioned posts cache cleared');
    
    // Пользователей не очищаем - они могут быть полезны
    print('CacheService: ℹ️ Users cache preserved');
    
    final afterSize = getCacheSize();
    print('CacheService: ✅ All cache cleared (freed ${beforeSize - afterSize} items, remaining: $afterSize items)');
  }

  /// Очистка кеша постов
  Future<void> clearPostsCache() async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot clear posts cache - service not initialized');
      return;
    }

    print('CacheService: 🗑️ Clearing posts cache');
    await _postsBox.clear();
    await _feedBox.clear();
    await _hashtagPostsBox.clear();
    await _userPostsBox.clear();
    await _videoPostsBox.clear();
    await _mentionedPostsBox.clear();
    print('CacheService: ✅ Posts cache cleared');
  }

  /// Очистка кеша комментариев
  Future<void> clearCommentsCache() async {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot clear comments cache - service not initialized');
      return;
    }

    final beforeSize = _commentsBox.length;
    print('CacheService: 🗑️ Clearing comments cache (current size: $beforeSize items)');
    await _commentsBox.clear();
    print('CacheService: ✅ Comments cache cleared');
  }

  /// Очистка устаревшего кеша (старше указанного времени)
  Future<void> clearOldCache({Duration maxAge = const Duration(days: 7)}) async {
    if (!_isInitialized) return;

    final now = DateTime.now();
    final cutoff = now.subtract(maxAge);

    // Очистка устаревших постов
    final feedTimestamp = _feedBox.get('feed_timestamp');
    if (feedTimestamp != null && feedTimestamp is String) {
      try {
        final timestamp = DateTime.parse(feedTimestamp);
        if (timestamp.isBefore(cutoff)) {
          await _feedBox.clear();
        }
      } catch (e) {
        // Игнорируем ошибки парсинга
      }
    }

    // Аналогично для других типов данных
    // Можно расширить при необходимости
  }

  /// Получение размера кеша (приблизительно)
  int getCacheSize() {
    if (!_isInitialized) return 0;

    int size = 0;
    size += _postsBox.length;
    size += _commentsBox.length;
    size += _feedBox.length;
    size += _hashtagPostsBox.length;
    size += _userPostsBox.length;
    size += _videoPostsBox.length;
    size += _mentionedPostsBox.length;
    size += _usersBox.length;

    return size;
  }

  /// Получение детальной статистики кеша
  Map<String, int> getCacheStats() {
    if (!_isInitialized) {
      print('CacheService: ⚠️ Cannot get cache stats - service not initialized');
      return {};
    }

    final stats = {
      'posts': _postsBox.length,
      'comments': _commentsBox.length,
      'feed': _feedBox.length,
      'hashtag_posts': _hashtagPostsBox.length,
      'user_posts': _userPostsBox.length,
      'video_posts': _videoPostsBox.length,
      'mentioned_posts': _mentionedPostsBox.length,
      'users': _usersBox.length,
      'total': getCacheSize(),
    };

    print('CacheService: 📊 Cache statistics:');
    stats.forEach((key, value) {
      if (key != 'total') {
        print('CacheService:   - $key: $value items');
      }
    });
    print('CacheService:   - TOTAL: ${stats['total']} items');

    return stats;
  }
}

