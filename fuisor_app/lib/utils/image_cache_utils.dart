import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ImageCacheUtils {
  static const String _cacheSizeLimitKey = 'image_cache_size_limit_mb';
  static const String _cacheUnlimitedKey = 'image_cache_unlimited';
  static const int _defaultCacheSizeMB = 100; // По умолчанию 100 МБ
  static const int _minCacheSizeMB = 10;
  static const int _maxCacheSizeMB = 1000;
  
  /// Получить текущий лимит кеша (в МБ). -1 означает неограниченно
  static Future<int> getCacheSizeLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isUnlimited = prefs.getBool(_cacheUnlimitedKey) ?? false;
      if (isUnlimited) {
        return -1; // Неограниченно
      }
      return prefs.getInt(_cacheSizeLimitKey) ?? _defaultCacheSizeMB;
    } catch (e) {
      print('ImageCacheUtils: Error getting cache size limit: $e');
      return _defaultCacheSizeMB;
    }
  }
  
  /// Установить лимит кеша (в МБ). -1 означает неограниченно
  static Future<void> setCacheSizeLimit(int sizeMB) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (sizeMB < 0) {
        // Неограниченно
        await prefs.setBool(_cacheUnlimitedKey, true);
        await prefs.remove(_cacheSizeLimitKey);
      } else {
        // Ограничено
        final clampedSize = sizeMB.clamp(_minCacheSizeMB, _maxCacheSizeMB);
        await prefs.setInt(_cacheSizeLimitKey, clampedSize);
        await prefs.setBool(_cacheUnlimitedKey, false);
        
        // Применяем лимит немедленно
        await _applyCacheLimit(clampedSize);
      }
      print('ImageCacheUtils: Cache size limit set to ${sizeMB < 0 ? "unlimited" : "${sizeMB}MB"}');
    } catch (e) {
      print('ImageCacheUtils: Error setting cache size limit: $e');
    }
  }
  
  /// Проверить, неограничен ли кеш
  static Future<bool> isCacheUnlimited() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_cacheUnlimitedKey) ?? false;
    } catch (e) {
      return false;
    }
  }
  
  /// Получить минимальный размер кеша
  static int getMinCacheSize() => _minCacheSizeMB;
  
  /// Получить максимальный размер кеша
  static int getMaxCacheSize() => _maxCacheSizeMB;
  
  /// Получить размер кеша в байтах
  static Future<int> getCacheSize() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (cacheDir == null) return 0;
      
      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (e) {
            // Игнорируем ошибки чтения файлов
          }
        }
      }
      
      return totalSize;
    } catch (e) {
      print('ImageCacheUtils: Error getting cache size: $e');
      return 0;
    }
  }
  
  /// Получить директорию кеша изображений
  static Future<Directory?> _getCacheDirectory() async {
    try {
      // Используем стандартные пути для кеша изображений
      final cacheDir = await getTemporaryDirectory();
      // CachedNetworkImage использует libCachedImageData
      final imageCacheDir = Directory('${cacheDir.path}/libCachedImageData');
      
      if (await imageCacheDir.exists()) {
        return imageCacheDir;
      }
      
      // Альтернативные пути
      final appCacheDir = await getApplicationCacheDirectory();
      final cachedImageDir = Directory('${appCacheDir.path}/libCachedImageData');
      if (await cachedImageDir.exists()) {
        return cachedImageDir;
      }
      
      return null;
    } catch (e) {
      print('ImageCacheUtils: Error getting cache directory: $e');
      return null;
    }
  }
  
  /// Применить лимит кеша - очистить старые файлы если превышен лимит
  static Future<void> _applyCacheLimit(int maxSizeMB) async {
    try {
      final currentSize = await getCacheSize();
      final maxSizeBytes = maxSizeMB * 1024 * 1024;
      
      if (currentSize <= maxSizeBytes) {
        return; // Размер в норме
      }
      
      print('ImageCacheUtils: Cache size ${(currentSize / 1024 / 1024).toStringAsFixed(2)}MB exceeds limit ${maxSizeMB}MB, cleaning...');
      
      // Получаем все файлы с датами изменения
      final cacheDir = await _getCacheDirectory();
      if (cacheDir == null) return;
      
      final files = <_CacheFile>[];
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            files.add(_CacheFile(
              file: entity,
              size: stat.size,
              modified: stat.modified,
            ));
          } catch (e) {
            // Игнорируем ошибки
          }
        }
      }
      
      // Сортируем по дате изменения (старые первыми)
      files.sort((a, b) => a.modified.compareTo(b.modified));
      
      // Удаляем старые файлы пока не достигнем лимита
      int currentTotalSize = files.fold(0, (sum, f) => sum + f.size);
      int deletedCount = 0;
      
      for (final cacheFile in files) {
        if (currentTotalSize <= maxSizeBytes) {
          break; // Достигли лимита
        }
        
        try {
          await cacheFile.file.delete();
          currentTotalSize -= cacheFile.size;
          deletedCount++;
        } catch (e) {
          print('ImageCacheUtils: Error deleting cache file: $e');
        }
      }
      
      print('ImageCacheUtils: Deleted $deletedCount old cache files, new size: ${(currentTotalSize / 1024 / 1024).toStringAsFixed(2)}MB');
    } catch (e) {
      print('ImageCacheUtils: Error applying cache limit: $e');
    }
  }
  
  /// Проверить и очистить кеш если превышен лимит (вызывать периодически)
  static Future<void> checkAndCleanCacheIfNeeded() async {
    try {
      final isUnlimited = await isCacheUnlimited();
      if (isUnlimited) {
        return; // Неограниченный кеш - не проверяем
      }
      
      final limitMB = await getCacheSizeLimit();
      if (limitMB > 0) {
        await _applyCacheLimit(limitMB);
      }
    } catch (e) {
      print('ImageCacheUtils: Error checking cache limit: $e');
    }
  }
  
  /// Очищает весь кэш изображений
  static Future<void> clearImageCache() async {
    try {
      await CachedNetworkImage.evictFromCache('');
      // Также очищаем через DefaultCacheManager
      await DefaultCacheManager().emptyCache();
      print('Image cache cleared successfully');
    } catch (e) {
      print('Error clearing image cache: $e');
    }
  }
  
  /// Очищает кэш для конкретного URL
  static Future<void> clearImageCacheForUrl(String url) async {
    try {
      await CachedNetworkImage.evictFromCache(url);
      print('Image cache cleared for URL: $url');
    } catch (e) {
      print('Error clearing image cache for URL $url: $e');
    }
  }
  
  /// Форматировать размер в байтах в читаемый формат
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

/// Вспомогательный класс для хранения информации о файле в кеше
class _CacheFile {
  final File file;
  final int size;
  final DateTime modified;
  
  _CacheFile({
    required this.file,
    required this.size,
    required this.modified,
  });
}
