import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NetworkSpeed {
  fast,    // > 5 Mbps
  medium,  // 1-5 Mbps
  slow,    // < 1 Mbps
  unknown,
}

/// Сервис для определения скорости соединения
class NetworkSpeedDetector {
  static const String _speedKey = 'network_speed';
  static const String _lastCheckKey = 'network_speed_last_check';
  static const Duration _cacheDuration = Duration(minutes: 5);
  
  final Dio _dio = Dio();

  /// Определить скорость соединения
  Future<NetworkSpeed> detectSpeed() async {
    try {
      // Проверяем кеш
      final cached = await _getCachedSpeed();
      if (cached != null) {
        return cached;
      }

      // Загружаем тестовый файл для измерения скорости
      // Используем небольшой файл (например, изображение)
      const testUrl = 'https://via.placeholder.com/100x100.jpg';
      const testSizeBytes = 10000; // Примерный размер файла
      
      final stopwatch = Stopwatch()..start();
      
      try {
        await _dio.get(
          testUrl,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        
        stopwatch.stop();
        final durationSeconds = stopwatch.elapsedMilliseconds / 1000.0;
        
        if (durationSeconds <= 0) {
          return NetworkSpeed.unknown;
        }
        
        // Вычисляем скорость в Mbps
        final speedMbps = (testSizeBytes * 8) / (durationSeconds * 1000000);
        
        NetworkSpeed speed;
        if (speedMbps > 5) {
          speed = NetworkSpeed.fast;
        } else if (speedMbps > 1) {
          speed = NetworkSpeed.medium;
        } else {
          speed = NetworkSpeed.slow;
        }
        
        // Кешируем результат
        await _saveCachedSpeed(speed);
        
        print('NetworkSpeedDetector: Detected speed: $speed (${speedMbps.toStringAsFixed(2)} Mbps)');
        return speed;
      } catch (e) {
        print('NetworkSpeedDetector: Error downloading test file: $e');
        return NetworkSpeed.unknown;
      }
    } catch (e) {
      print('NetworkSpeedDetector: Error detecting speed: $e');
      return NetworkSpeed.unknown;
    }
  }

  /// Получить текущую скорость (из кеша или определить)
  Future<NetworkSpeed> getCurrentSpeed() async {
    final cached = await _getCachedSpeed();
    if (cached != null) {
      return cached;
    }
    return await detectSpeed();
  }

  /// Получить кешированную скорость
  Future<NetworkSpeed?> _getCachedSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckStr = prefs.getString(_lastCheckKey);
      
      if (lastCheckStr == null) {
        return null;
      }
      
      final lastCheck = DateTime.parse(lastCheckStr);
      final age = DateTime.now().difference(lastCheck);
      
      if (age > _cacheDuration) {
        return null; // Кеш устарел
      }
      
      final speedStr = prefs.getString(_speedKey);
      if (speedStr == null) {
        return null;
      }
      
      return NetworkSpeed.values.firstWhere(
        (s) => s.toString() == speedStr,
        orElse: () => NetworkSpeed.unknown,
      );
    } catch (e) {
      print('NetworkSpeedDetector: Error getting cached speed: $e');
      return null;
    }
  }

  /// Сохранить скорость в кеш
  Future<void> _saveCachedSpeed(NetworkSpeed speed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_speedKey, speed.toString());
      await prefs.setString(_lastCheckKey, DateTime.now().toIso8601String());
    } catch (e) {
      print('NetworkSpeedDetector: Error saving cached speed: $e');
    }
  }

  /// Очистить кеш скорости
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_speedKey);
      await prefs.remove(_lastCheckKey);
    } catch (e) {
      print('NetworkSpeedDetector: Error clearing cache: $e');
    }
  }
}

