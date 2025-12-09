import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'signed_url_cache_service.dart';

/// Сервис для кэширования и предзагрузки медиа файлов постов
class MediaCacheService {
  static final MediaCacheService _instance = MediaCacheService._internal();
  factory MediaCacheService() => _instance;
  MediaCacheService._internal();

  // Кэш менеджер с настройками
  static CacheManager? _cacheManager;
  static const String _cacheKey = 'post_media_cache';
  
  // Настройки кэша (загружаются из SharedPreferences)
  int _maxCacheSize = 1000;
  int _stalePeriodDays = 30;
  bool _preloadEnabled = true;
  int _preloadCount = 10;
  bool _preloadThumbnails = true;
  bool _preloadVideos = false;

  /// Инициализация кэш менеджера с настройками
  Future<void> init() async {
    await _loadSettings();
    // Кэш менеджер создастся при первом обращении
  }

  /// Загрузить настройки из SharedPreferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _maxCacheSize = prefs.getInt('cache_max_size') ?? 1000;
    _stalePeriodDays = prefs.getInt('cache_stale_days') ?? 30;
    _preloadEnabled = prefs.getBool('cache_preload_enabled') ?? true;
    _preloadCount = prefs.getInt('cache_preload_count') ?? 10;
    _preloadThumbnails = prefs.getBool('cache_preload_thumbnails') ?? true;
    _preloadVideos = prefs.getBool('cache_preload_videos') ?? false;
  }

  /// Обновить настройки
  Future<void> updateSettings({
    int? maxCacheSize,
    int? stalePeriodDays,
    bool? preloadEnabled,
    int? preloadCount,
    bool? preloadThumbnails,
    bool? preloadVideos,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (maxCacheSize != null) {
      _maxCacheSize = maxCacheSize;
      await prefs.setInt('cache_max_size', maxCacheSize);
    }
    if (stalePeriodDays != null) {
      _stalePeriodDays = stalePeriodDays;
      await prefs.setInt('cache_stale_days', stalePeriodDays);
    }
    if (preloadEnabled != null) {
      _preloadEnabled = preloadEnabled;
      await prefs.setBool('cache_preload_enabled', preloadEnabled);
    }
    if (preloadCount != null) {
      _preloadCount = preloadCount;
      await prefs.setInt('cache_preload_count', preloadCount);
    }
    if (preloadThumbnails != null) {
      _preloadThumbnails = preloadThumbnails;
      await prefs.setBool('cache_preload_thumbnails', preloadThumbnails);
    }
    if (preloadVideos != null) {
      _preloadVideos = preloadVideos;
      await prefs.setBool('cache_preload_videos', preloadVideos);
    }

    // Пересоздаем кэш менеджер с новыми настройками
    _cacheManager = null; // Сброс для пересоздания при следующем обращении
  }


  /// Получить кэш менеджер
  CacheManager get cacheManager {
    if (_cacheManager == null) {
      _cacheManager = _createCacheManager();
    }
    return _cacheManager as CacheManager;
  }
  
  /// Создать и вернуть кэш менеджер
  CacheManager _createCacheManager() {
    return CacheManager(
      Config(
        _cacheKey,
        stalePeriod: Duration(days: _stalePeriodDays),
        maxNrOfCacheObjects: _maxCacheSize,
        repo: JsonCacheInfoRepository(databaseName: _cacheKey),
        fileService: HttpFileService(),
      ),
    );
  }

  /// Получить signed URL для медиа
  Future<String> _getSignedUrl(String mediaUrl, String? postId) async {
    final signedUrlCache = SignedUrlCacheService();
    final apiService = ApiService();
    
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    if (accessToken != null) {
      apiService.setAccessToken(accessToken);
    }

    return await signedUrlCache.getSignedUrl(
      path: mediaUrl,
      postId: postId,
      apiService: apiService,
    );
  }

  /// Предзагрузить медиа для поста
  Future<void> preloadPostMedia(Post post) async {
    if (!_preloadEnabled) return;

    try {
      // Предзагружаем thumbnail если включено
      if (_preloadThumbnails && post.thumbnailUrl != null) {
        final thumbSignedUrl = await _getSignedUrl(post.thumbnailUrl!, post.id);
        await cacheManager.downloadFile(
          thumbSignedUrl,
          key: 'post_${post.id}_thumb_${post.thumbnailUrl}',
        );
        print('MediaCacheService: ✅ Thumbnail предзагружен для поста ${post.id}');
      }

      // Предзагружаем основное медиа
      if (post.mediaUrl != null) {
        // Для видео предзагружаем только если включено
        if (post.mediaType == 'video' && !_preloadVideos) {
          return;
        }

        final signedUrl = await _getSignedUrl(post.mediaUrl!, post.id);
        await cacheManager.downloadFile(
          signedUrl,
          key: 'post_${post.id}_${post.mediaUrl}',
        );
        print('MediaCacheService: ✅ Медиа предзагружено для поста ${post.id}');
      }
    } catch (e) {
      print('MediaCacheService: ❌ Ошибка предзагрузки медиа для поста ${post.id}: $e');
    }
  }

  /// Предзагрузить медиа для списка постов
  Future<void> preloadPostsMedia(List<Post> posts) async {
    if (!_preloadEnabled || posts.isEmpty) return;

    // Загружаем первые N постов сразу (приоритет)
    final postsToPreload = posts.take(_preloadCount).toList();
    
    print('MediaCacheService: 🚀 Начинаем предзагрузку медиа для ${postsToPreload.length} постов');
    
    // Загружаем параллельно
    await Future.wait(
      postsToPreload.map((post) => preloadPostMedia(post)),
      eagerError: false, // Продолжаем даже при ошибках
    );

    // Остальные загружаем в фоне (не блокируем UI)
    if (posts.length > _preloadCount) {
      Future.delayed(const Duration(seconds: 2), () {
        for (final post in posts.skip(_preloadCount)) {
          preloadPostMedia(post); // Запускаем в фоне
        }
      });
    }
  }

  /// Получить кэшированный файл
  Future<File?> getCachedFile(String mediaUrl, String postId, {bool isThumbnail = false}) async {
    try {
      final key = isThumbnail 
          ? 'post_${postId}_thumb_$mediaUrl'
          : 'post_${postId}_$mediaUrl';
      
      final fileInfo = await cacheManager.getFileFromCache(key);
      return fileInfo?.file;
    } catch (e) {
      print('MediaCacheService: Ошибка получения кэшированного файла: $e');
      return null;
    }
  }

  /// Очистить кэш для конкретного поста
  Future<void> clearPostCache(String postId, String? mediaUrl, String? thumbnailUrl) async {
    try {
      if (mediaUrl != null) {
        await cacheManager.removeFile('post_${postId}_$mediaUrl');
      }
      if (thumbnailUrl != null) {
        await cacheManager.removeFile('post_${postId}_thumb_$thumbnailUrl');
      }
      print('MediaCacheService: 🗑️ Кэш очищен для поста $postId');
    } catch (e) {
      print('MediaCacheService: Ошибка очистки кэша: $e');
    }
  }

  /// Очистить весь кэш медиа
  Future<void> clearAllCache() async {
    try {
      await cacheManager.emptyCache();
      print('MediaCacheService: 🗑️ Весь кэш медиа очищен');
    } catch (e) {
      print('MediaCacheService: Ошибка очистки всего кэша: $e');
    }
  }

  /// Получить размер кэша
  /// Примечание: точный размер кэша сложно получить через flutter_cache_manager
  /// Возвращаем приблизительное значение на основе количества файлов
  Future<int> getCacheSize() async {
    try {
      // К сожалению, flutter_cache_manager не предоставляет прямой способ
      // получить размер кэша. Можно было бы использовать path_provider,
      // но это усложнит код. Для UI достаточно показать количество файлов.
      // Возвращаем 0, размер будет рассчитываться на основе других метрик
      return 0;
    } catch (e) {
      print('MediaCacheService: Ошибка получения размера кэша: $e');
      return 0;
    }
  }

  /// Получить статистику кэша
  Future<Map<String, dynamic>> getStats() async {
    try {
      final cacheSize = await getCacheSize();
      // Приблизительный расчет: средний размер файла ~500KB, умножаем на количество
      final estimatedSize = _maxCacheSize * 500 * 1024; // Примерная оценка
      return {
        'cacheSizeBytes': cacheSize,
        'cacheSizeMB': cacheSize > 0 
            ? (cacheSize / (1024 * 1024)).toStringAsFixed(2)
            : '~${(estimatedSize / (1024 * 1024)).toStringAsFixed(0)}',
        'maxCacheSize': _maxCacheSize,
        'stalePeriodDays': _stalePeriodDays,
        'preloadEnabled': _preloadEnabled,
        'preloadCount': _preloadCount,
        'preloadThumbnails': _preloadThumbnails,
        'preloadVideos': _preloadVideos,
      };
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
  }

  /// Получить текущие настройки
  Map<String, dynamic> getSettings() {
    return {
      'maxCacheSize': _maxCacheSize,
      'stalePeriodDays': _stalePeriodDays,
      'preloadEnabled': _preloadEnabled,
      'preloadCount': _preloadCount,
      'preloadThumbnails': _preloadThumbnails,
      'preloadVideos': _preloadVideos,
    };
  }
}

