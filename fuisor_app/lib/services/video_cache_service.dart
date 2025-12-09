import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для кеширования видео файлов
/// Использует postId как постоянный ключ кеша вместо временного signed URL
class VideoCacheService {
  static const String _cacheKey = 'video_cache_info';
  static const int _maxCacheSize = 500 * 1024 * 1024; // 500MB
  
  final CacheManager _cacheManager = DefaultCacheManager();
  final Dio _dio = Dio();
  
  /// Генерирует ключ кеша на основе postId
  /// Используем postId как постоянный идентификатор вместо временного signed URL
  String _getCacheKey(String postId) {
    return 'video_post_$postId';
  }
  
  /// Получить кешированный файл видео по postId
  Future<File?> getCachedVideo(String postId) async {
    try {
      final cacheKey = _getCacheKey(postId);
      final fileInfo = await _cacheManager.getFileFromCache(cacheKey);
      if (fileInfo != null && fileInfo.file.existsSync()) {
        return fileInfo.file;
      }
      return null;
    } catch (e) {
      print('VideoCacheService: Error getting cached video for post $postId: $e');
      return null;
    }
  }
  
  /// Проверить, есть ли видео в кеше по postId
  Future<bool> isVideoCached(String postId) async {
    final file = await getCachedVideo(postId);
    return file != null;
  }
  
  /// Загрузить и закешировать видео
  /// postId - уникальный идентификатор поста (используется как ключ кеша)
  /// videoUrl - URL для загрузки (может быть signed URL)
  Future<File> downloadVideo(
    String postId,
    String videoUrl, {
    Function(int received, int total)? onProgress,
  }) async {
    try {
      // Сначала проверяем кеш по postId
      final cachedFile = await getCachedVideo(postId);
      if (cachedFile != null) {
        print('VideoCacheService: Using cached video for post $postId');
        return cachedFile;
      }
      
      // Загружаем через cache manager с использованием postId как ключа
      final cacheKey = _getCacheKey(postId);
      final fileInfo = await _cacheManager.downloadFile(
        videoUrl,
        key: cacheKey, // ВАЖНО: Используем postId как ключ кеша
        authHeaders: {},
      );
      
      // Обновляем информацию о кеше
      await _updateCacheInfo(postId, fileInfo.file.lengthSync());
      
      print('VideoCacheService: Downloaded and cached video for post $postId');
      return fileInfo.file;
    } catch (e) {
      print('VideoCacheService: Error downloading video for post $postId: $e');
      rethrow;
    }
  }
  
  /// Предзагрузить видео в фоне
  /// postId - уникальный идентификатор поста
  /// videoUrl - URL для загрузки
  Future<void> preloadVideo(String postId, String videoUrl, {int priority = 0}) async {
    try {
      // Проверяем, не закешировано ли уже по postId
      if (await isVideoCached(postId)) {
        print('VideoCacheService: Video already cached for post $postId');
        return;
      }
      
      // Загружаем видео (синхронно, чтобы гарантировать загрузку)
      print('VideoCacheService: Starting preload for post $postId (priority: $priority)');
      await downloadVideo(postId, videoUrl);
      print('VideoCacheService: Preloaded video successfully for post $postId');
    } catch (e) {
      print('VideoCacheService: Error preloading video for post $postId: $e');
      // Не пробрасываем ошибку, чтобы не блокировать основной поток
    }
  }
  
  /// Получить размер кеша
  Future<int> getCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheInfo = prefs.getString(_cacheKey);
      if (cacheInfo == null) return 0;
      
      final entries = cacheInfo.split('|');
      int totalSize = 0;
      for (final entry in entries) {
        if (entry.isEmpty) continue;
        final parts = entry.split(':');
        if (parts.length == 2) {
          totalSize += int.tryParse(parts[1]) ?? 0;
        }
      }
      return totalSize;
    } catch (e) {
      print('VideoCacheService: Error getting cache size: $e');
      return 0;
    }
  }
  
  /// Очистить кеш
  Future<void> clearCache() async {
    try {
      await _cacheManager.emptyCache();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      print('VideoCacheService: Cache cleared');
    } catch (e) {
      print('VideoCacheService: Error clearing cache: $e');
    }
  }
  
  /// Очистить старые файлы из кеша (LRU)
  Future<void> cleanOldCache() async {
    try {
      final cacheSize = await getCacheSize();
      if (cacheSize > _maxCacheSize) {
        // Удаляем самые старые файлы
        await _cacheManager.emptyCache();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_cacheKey);
        print('VideoCacheService: Old cache cleaned');
      }
    } catch (e) {
      print('VideoCacheService: Error cleaning old cache: $e');
    }
  }
  
  /// Обновить информацию о кеше
  Future<void> _updateCacheInfo(String postId, int fileSize) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_cacheKey) ?? '';
      final entries = existing.split('|').where((e) => e.isNotEmpty).toList();
      
      // Удаляем старую запись для этого postId
      entries.removeWhere((e) => e.startsWith('$postId:'));
      
      // Добавляем новую запись
      entries.add('$postId:$fileSize');
      
      await prefs.setString(_cacheKey, entries.join('|'));
    } catch (e) {
      print('VideoCacheService: Error updating cache info: $e');
    }
  }
  
  /// Получить размер видео по URL (без загрузки)
  Future<int?> getVideoSize(String videoUrl) async {
    try {
      final response = await _dio.head(videoUrl);
      final contentLength = response.headers.value('content-length');
      if (contentLength != null) {
        return int.tryParse(contentLength);
      }
      return null;
    } catch (e) {
      print('VideoCacheService: Error getting video size: $e');
      return null;
    }
  }
}

