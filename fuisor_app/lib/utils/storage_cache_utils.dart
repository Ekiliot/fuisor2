import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StorageCacheUtils {
  /// Получает размер директории в байтах
  static Future<int> _getDirectorySize(Directory dir) async {
    int size = 0;
    try {
      if (await dir.exists()) {
        await for (var entity in dir.list(recursive: true)) {
          if (entity is File) {
            try {
              size += await entity.length();
            } catch (e) {
              // Игнорируем ошибки отдельных файлов
            }
          }
        }
      }
    } catch (e) {
      print('Error calculating directory size: $e');
    }
    return size;
  }

  /// Получает размер кэша изображений
  static Future<int> getImageCacheSize() async {
    // На веб-платформе path_provider не работает
    if (kIsWeb) {
      return 0;
    }

    int totalSize = 0;
    
    try {
      // Попытка 1: Временная директория
      try {
        final cacheDir = await getTemporaryDirectory();
        final imageCacheDir = Directory('${cacheDir.path}/libCachedImageData');
        if (await imageCacheDir.exists()) {
          totalSize += await _getDirectorySize(imageCacheDir);
        }
      } catch (e) {
        if (!e.toString().contains('MissingPluginException')) {
          print('Error accessing temp directory: $e');
        }
      }

      // Попытка 2: Директория кэша приложения
      try {
        final appCacheDir = await getApplicationCacheDirectory();
        final cachedImageDir = Directory('${appCacheDir.path}/libCachedImageData');
        if (await cachedImageDir.exists()) {
          totalSize += await _getDirectorySize(cachedImageDir);
        }
        
        // Также проверяем другие возможные пути
        final cachedImageDir2 = Directory('${appCacheDir.path}/CachedNetworkImage');
        if (await cachedImageDir2.exists()) {
          totalSize += await _getDirectorySize(cachedImageDir2);
        }
      } catch (e) {
        if (!e.toString().contains('MissingPluginException')) {
          print('Error accessing app cache directory: $e');
        }
      }

      // Попытка 3: Проверяем корневую директорию кэша приложения
      try {
        final appCacheDir = await getApplicationCacheDirectory();
        if (await appCacheDir.exists()) {
          // Ищем все файлы изображений в корне кэша
          await for (var entity in appCacheDir.list()) {
            if (entity is File) {
              final name = entity.path.toLowerCase();
              if (name.endsWith('.jpg') || name.endsWith('.jpeg') || 
                  name.endsWith('.png') || name.endsWith('.gif') ||
                  name.endsWith('.webp')) {
                try {
                  totalSize += await entity.length();
                } catch (_) {}
              }
            }
          }
        }
      } catch (e) {
        // Игнорируем ошибки
      }

      return totalSize;
    } catch (e) {
      if (e.toString().contains('MissingPluginException')) {
        print('Path provider not available, returning 0 for image cache size');
      } else {
        print('Error getting image cache size: $e');
      }
      return 0;
    }
  }

  /// Получает размер кэша видео
  static Future<int> getVideoCacheSize() async {
    // На веб-платформе path_provider не работает
    if (kIsWeb) {
      return 0;
    }

    int totalSize = 0;

    try {
      final cacheDir = await getTemporaryDirectory();
      
      // Проверяем директорию кэша видео
      final videoCacheDir = Directory('${cacheDir.path}/video_cache');
      if (await videoCacheDir.exists()) {
        totalSize += await _getDirectorySize(videoCacheDir);
      }
      
      // Также проверяем общую временную директорию на видео файлы
      if (await cacheDir.exists()) {
        try {
          await for (var entity in cacheDir.list()) {
            if (entity is File) {
              final name = entity.path.toLowerCase();
              if (name.endsWith('.mp4') || name.endsWith('.mov') || 
                  name.endsWith('.avi') || name.endsWith('.mkv')) {
                try {
                  totalSize += await entity.length();
                } catch (_) {}
              }
            }
          }
        } catch (e) {
          print('Error reading cache directory: $e');
        }
      }

      // Также проверяем директорию кэша приложения
      try {
        final appCacheDir = await getApplicationCacheDirectory();
        if (await appCacheDir.exists()) {
          await for (var entity in appCacheDir.list()) {
            if (entity is File) {
              final name = entity.path.toLowerCase();
              if (name.endsWith('.mp4') || name.endsWith('.mov') || 
                  name.endsWith('.avi') || name.endsWith('.mkv')) {
                try {
                  totalSize += await entity.length();
                } catch (_) {}
              }
            }
          }
        }
      } catch (e) {
        // Игнорируем ошибки
      }

      return totalSize;
    } catch (e) {
      if (e.toString().contains('MissingPluginException')) {
        print('Path provider not available, returning 0 for video cache size');
      } else {
        print('Error getting video cache size: $e');
      }
      return 0;
    }
  }

  /// Получает общий размер кэша
  static Future<int> getTotalCacheSize() async {
    try {
      final imageSize = await getImageCacheSize();
      final videoSize = await getVideoCacheSize();
      return imageSize + videoSize;
    } catch (e) {
      print('Error getting total cache size: $e');
      return 0;
    }
  }

  /// Очищает кэш изображений
  static Future<void> clearImageCache() async {
    try {
      // Очищаем кэш CachedNetworkImage (это работает всегда, включая веб)
      await CachedNetworkImage.evictFromCache('');
      
      // Пытаемся удалить директории кэша, если path_provider доступен
      if (!kIsWeb) {
        try {
          final cacheDir = await getTemporaryDirectory();
          final imageCacheDir = Directory('${cacheDir.path}/libCachedImageData');
          if (await imageCacheDir.exists()) {
            await imageCacheDir.delete(recursive: true);
          }
        } catch (e) {
          if (!e.toString().contains('MissingPluginException')) {
            print('Error deleting image cache directory: $e');
          }
        }
        
        try {
          final appCacheDir = await getApplicationCacheDirectory();
          final cachedImageDir = Directory('${appCacheDir.path}/libCachedImageData');
          if (await cachedImageDir.exists()) {
            await cachedImageDir.delete(recursive: true);
          }
          
          final cachedImageDir2 = Directory('${appCacheDir.path}/CachedNetworkImage');
          if (await cachedImageDir2.exists()) {
            await cachedImageDir2.delete(recursive: true);
          }
        } catch (e) {
          if (!e.toString().contains('MissingPluginException')) {
            print('Error deleting app cache directory: $e');
          }
        }
      }
      
      print('Image cache cleared successfully');
    } catch (e) {
      print('Error clearing image cache: $e');
    }
  }

  /// Очищает кэш видео
  static Future<void> clearVideoCache() async {
    // На веб-платформе очистка видео кэша ограничена
    if (kIsWeb) {
      print('Web platform: video cache clearing limited');
      return;
    }

    try {
      final cacheDir = await getTemporaryDirectory();
      
      // Удаляем директорию кэша видео
      final videoCacheDir = Directory('${cacheDir.path}/video_cache');
      if (await videoCacheDir.exists()) {
        await videoCacheDir.delete(recursive: true);
      }
      
      // Удаляем видео файлы из временной директории
      if (await cacheDir.exists()) {
        try {
          await for (var entity in cacheDir.list()) {
            if (entity is File) {
              final name = entity.path.toLowerCase();
              if (name.endsWith('.mp4') || name.endsWith('.mov') || 
                  name.endsWith('.avi') || name.endsWith('.mkv')) {
                try {
                  await entity.delete();
                } catch (e) {
                  print('Error deleting video file ${entity.path}: $e');
                }
              }
            }
          }
        } catch (e) {
          print('Error reading cache directory for video cleanup: $e');
        }
      }

      // Также очищаем из директории кэша приложения
      try {
        final appCacheDir = await getApplicationCacheDirectory();
        if (await appCacheDir.exists()) {
          await for (var entity in appCacheDir.list()) {
            if (entity is File) {
              final name = entity.path.toLowerCase();
              if (name.endsWith('.mp4') || name.endsWith('.mov') || 
                  name.endsWith('.avi') || name.endsWith('.mkv')) {
                try {
                  await entity.delete();
                } catch (e) {
                  print('Error deleting video file ${entity.path}: $e');
                }
              }
            }
          }
        }
      } catch (e) {
        // Игнорируем ошибки
      }
      
      print('Video cache cleared successfully');
    } catch (e) {
      if (e.toString().contains('MissingPluginException')) {
        print('Path provider not available, video cache clear skipped');
      } else {
        print('Error clearing video cache: $e');
      }
    }
  }

  /// Очищает весь кэш
  static Future<void> clearAllCache() async {
    try {
      await clearImageCache();
      await clearVideoCache();
      print('All cache cleared successfully');
    } catch (e) {
      print('Error clearing all cache: $e');
      // Не пробрасываем ошибку, так как частичная очистка уже могла быть выполнена
    }
  }

  /// Форматирует размер в читаемый формат
  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}

