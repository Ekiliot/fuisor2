import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class OnlineStatusProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  Timer? _heartbeatTimer;
  
  // Кэш статусов пользователей с временными метками
  final Map<String, Map<String, dynamic>> _statusCache = {};
  final Map<String, DateTime> _statusTimestamps = {};
  static const Duration _cacheTTL = Duration(minutes: 2); // Время жизни кеша: 2 минуты
  
  /// Запустить отправку heartbeat каждые 30 секунд
  void startHeartbeat(String accessToken) {
    _apiService.setAccessToken(accessToken);
    
    // Отправляем сразу
    _apiService.sendHeartbeat();
    
    // Останавливаем предыдущий таймер если есть
    _heartbeatTimer?.cancel();
    
    // Запускаем новый таймер
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _apiService.sendHeartbeat();
    });
    
    print('OnlineStatusProvider: Heartbeat started');
  }
  
  /// Остановить отправку heartbeat и установить статус офлайн
  Future<void> stopHeartbeat() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    print('OnlineStatusProvider: Heartbeat stopped');
    
    // Устанавливаем статус офлайн в БД
    try {
      await _apiService.setOfflineStatus();
      print('OnlineStatusProvider: User status set to offline');
    } catch (e) {
      print('OnlineStatusProvider: Error setting offline status: $e');
    }
  }
  
  /// Получить статус пользователя
  Future<Map<String, dynamic>> getUserStatus(String userId, String accessToken) async {
    try {
      _apiService.setAccessToken(accessToken);
      final status = await _apiService.getUserStatus(userId);
      
      // Кэшируем статус с временной меткой
      _statusCache[userId] = status;
      _statusTimestamps[userId] = DateTime.now();
      notifyListeners();
      
      return status;
    } catch (e) {
      print('OnlineStatusProvider: Error getting user status: $e');
      // Возвращаем закэшированный статус если есть
      return _statusCache[userId] ?? {
        'is_online': false,
        'status_text': 'long ago',
      };
    }
  }
  
  /// Получить закэшированный статус пользователя
  Map<String, dynamic>? getCachedStatus(String userId) {
    final timestamp = _statusTimestamps[userId];
    if (timestamp == null) return null;
    
    // Проверяем срок действия кеша
    final age = DateTime.now().difference(timestamp);
    if (age > _cacheTTL) {
      // Кеш устарел - удаляем
      _statusCache.remove(userId);
      _statusTimestamps.remove(userId);
      return null;
    }
    
    return _statusCache[userId];
  }
  
  /// Очистить кэш статусов
  void clearCache() {
    _statusCache.clear();
    _statusTimestamps.clear();
    notifyListeners();
  }
  
  /// Очистить устаревшие записи из кеша (можно вызывать периодически)
  void clearExpiredCache() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    
    for (final entry in _statusTimestamps.entries) {
      if (now.difference(entry.value) > _cacheTTL) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      _statusCache.remove(key);
      _statusTimestamps.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    stopHeartbeat();
    super.dispose();
  }
}

