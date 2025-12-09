import 'dart:collection';
import '../services/api_service.dart';

/// Кешированная запись signed URL
class _CachedSignedUrl {
  final String url;
  final DateTime expiresAt;

  _CachedSignedUrl(this.url, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Сервис для кеширования signed URL на уровне приложения
/// Предотвращает множественные запросы одного и того же signed URL
class SignedUrlCacheService {
  static final SignedUrlCacheService _instance = SignedUrlCacheService._internal();
  factory SignedUrlCacheService() => _instance;
  SignedUrlCacheService._internal();

  // LRU кеш для signed URL
  final LinkedHashMap<String, _CachedSignedUrl> _cache = LinkedHashMap();
  static const int _maxCacheSize = 200; // Максимальное количество кешированных URL
  static const Duration _defaultTtl = Duration(days: 7); // TTL по умолчанию (7 дней)

  /// Получить ключ для кеша
  String _getCacheKey({
    required String path,
    String? chatId,
    String? postId,
  }) {
    if (chatId != null) {
      return 'chat_${chatId}_$path';
    } else if (postId != null) {
      return 'post_${postId}_$path';
    } else {
      return 'path_$path';
    }
  }

  /// Получить кешированный signed URL без запроса нового (если есть)
  /// Возвращает null, если signed URL нет в кеше или истек
  String? getCachedSignedUrl({
    required String path,
    String? chatId,
    String? postId,
  }) {
    final key = _getCacheKey(path: path, chatId: chatId, postId: postId);
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      return cached.url;
    }
    return null;
  }

  /// Получить signed URL из кеша или запросить новый
  Future<String> getSignedUrl({
    required String path,
    String? chatId,
    String? postId,
    required ApiService apiService,
    Duration? ttl,
  }) async {
    final key = _getCacheKey(path: path, chatId: chatId, postId: postId);
    
    // Проверяем кеш
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      print('SignedUrlCacheService: ✅ Используем кешированный signed URL для $key');
      return cached.url;
    }

    // Если кеш переполнен, удаляем старые записи (LRU)
    if (_cache.length >= _maxCacheSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      print('SignedUrlCacheService: 🗑️ Удален старый кеш (LRU): $oldestKey');
    }

    // Запрашиваем новый signed URL
    print('SignedUrlCacheService: 📡 Запрос нового signed URL для $key');
    String signedUrl;
    
    try {
      // ВАЖНО: Проверяем тип пути ПЕРЕД выбором API
      // Пути постов начинаются с post_ или thumb_
      final isPostPath = path.startsWith('post_') || path.startsWith('thumb_');
      
      // Если это путь поста (post_ или thumb_), используем post API
      if (isPostPath) {
        final result = await apiService.getPostMediaSignedUrl(
          mediaPath: path,
          postId: postId,
        );
        signedUrl = result['signedUrl']!;
      } 
      // Если передан chatId и это НЕ путь поста, используем chat API
      else if (chatId != null) {
        signedUrl = await apiService.getMediaSignedUrl(
          chatId: chatId,
          mediaPath: path,
        );
      } else {
        throw Exception('Cannot determine signed URL method: need either postId for post paths (post_/thumb_) or chatId for message paths');
      }

      // Определяем TTL из signed URL (обычно 1 час) или используем переданный
      final actualTtl = ttl ?? _defaultTtl;
      final expiresAt = DateTime.now().add(actualTtl);

      // Сохраняем в кеш
      _cache[key] = _CachedSignedUrl(signedUrl, expiresAt);
      
      // Перемещаем в конец (LRU)
      _cache.remove(key);
      _cache[key] = _CachedSignedUrl(signedUrl, expiresAt);

      print('SignedUrlCacheService: ✅ Signed URL закеширован: $key (TTL: ${actualTtl.inMinutes} мин)');
      return signedUrl;
    } catch (e) {
      print('SignedUrlCacheService: ❌ Ошибка получения signed URL: $e');
      rethrow;
    }
  }

  /// Инвалидировать кеш для конкретного пути
  void invalidate({
    required String path,
    String? chatId,
    String? postId,
  }) {
    final key = _getCacheKey(path: path, chatId: chatId, postId: postId);
    _cache.remove(key);
    print('SignedUrlCacheService: 🗑️ Инвалидирован кеш для $key');
  }

  /// Очистить весь кеш
  void clear() {
    _cache.clear();
    print('SignedUrlCacheService: 🗑️ Весь кеш очищен');
  }

  /// Очистить истекшие записи
  void clearExpired() {
    final expiredKeys = _cache.entries
        .where((entry) => entry.value.isExpired)
        .map((entry) => entry.key)
        .toList();
    
    for (final key in expiredKeys) {
      _cache.remove(key);
    }
    
    if (expiredKeys.isNotEmpty) {
      print('SignedUrlCacheService: 🗑️ Удалено ${expiredKeys.length} истекших записей');
    }
  }

  /// Получить статистику кеша
  Map<String, dynamic> getStats() {
    final total = _cache.length;
    final expired = _cache.values.where((cached) => cached.isExpired).length;
    final valid = total - expired;
    
    return {
      'total': total,
      'valid': valid,
      'expired': expired,
      'maxSize': _maxCacheSize,
    };
  }

  /// Периодическая очистка истекших записей (вызывать периодически)
  void periodicCleanup() {
    clearExpired();
  }
}

