import 'dart:async';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';

/// Метаданные кеша для чата
class CacheMetadata {
  final String chatId;
  final DateTime lastSyncTimestamp;
  final String? lastMessageId;
  final bool hasMore;
  final int totalCached;

  CacheMetadata({
    required this.chatId,
    required this.lastSyncTimestamp,
    this.lastMessageId,
    this.hasMore = false,
    this.totalCached = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'chatId': chatId,
      'lastSyncTimestamp': lastSyncTimestamp.toIso8601String(),
      'lastMessageId': lastMessageId,
      'hasMore': hasMore,
      'totalCached': totalCached,
    };
  }

  factory CacheMetadata.fromJson(Map<String, dynamic> json) {
    return CacheMetadata(
      chatId: json['chatId'],
      lastSyncTimestamp: DateTime.parse(json['lastSyncTimestamp']),
      lastMessageId: json['lastMessageId'],
      hasMore: json['hasMore'] ?? false,
      totalCached: json['totalCached'] ?? 0,
    );
  }
}

/// Сервис для кеширования сообщений
class MessageCacheService {
  static const String _metadataBoxName = 'message_cache_metadata';
  static const String _messagesBoxPrefix = 'messages_cache_';
  static const Duration _maxCacheAge = Duration(days: 30);
  static const int _maxMessagesToDownloadMedia = 20; // Скачиваем медиа для последних 20 сообщений

  Box<dynamic>? _metadataBox;
  final Map<String, Box<dynamic>> _messageBoxes = {};
  
  // Защита от race conditions - отслеживание активных операций
  final Map<String, Future<void>> _saveOperations = {};
  final Map<String, Future<void>> _loadOperations = {};
  final Map<String, DateTime> _boxLastUsed = {}; // Для управления жизненным циклом boxes
  Timer? _cleanupTimer; // Таймер для периодической очистки неиспользуемых boxes

  /// Инициализация Hive для кеша сообщений
  Future<void> init() async {
    try {
      // Открываем box для метаданных
      _metadataBox = await Hive.openBox(_metadataBoxName);
      
      // Очищаем старые кеши при инициализации
      await _cleanupOldCaches();
      
      // Запускаем периодическую очистку неиспользуемых boxes (каждые 10 минут)
      _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
        _closeUnusedBoxes();
      });
      
      print('MessageCacheService: Initialized successfully');
    } catch (e) {
      print('MessageCacheService: Error initializing: $e');
      rethrow;
    }
  }
  
  /// Закрыть неиспользуемые boxes (не использовались более 30 минут)
  Future<void> _closeUnusedBoxes() async {
    try {
      final now = DateTime.now();
      final unusedTimeout = const Duration(minutes: 30);
      final boxesToClose = <String>[];
      
      // Находим неиспользуемые boxes
      for (final entry in _boxLastUsed.entries) {
        final age = now.difference(entry.value);
        if (age > unusedTimeout) {
          boxesToClose.add(entry.key);
        }
      }
      
      // Закрываем неиспользуемые boxes
      for (final chatId in boxesToClose) {
        try {
          final box = _messageBoxes.remove(chatId);
          if (box != null) {
            await box.close();
            _boxLastUsed.remove(chatId);
            print('MessageCacheService: Closed unused box for chat $chatId');
          }
        } catch (e) {
          print('MessageCacheService: Error closing box for chat $chatId: $e');
        }
      }
      
      if (boxesToClose.isNotEmpty) {
        print('MessageCacheService: Closed ${boxesToClose.length} unused boxes');
      }
    } catch (e) {
      print('MessageCacheService: Error closing unused boxes: $e');
    }
  }

  /// Получить box для сообщений конкретного чата
  Future<Box<dynamic>> _getMessageBox(String chatId) async {
    if (_messageBoxes.containsKey(chatId)) {
      _boxLastUsed[chatId] = DateTime.now(); // Обновляем время использования
      return _messageBoxes[chatId]!;
    }

    final boxName = '$_messagesBoxPrefix$chatId';
    final box = await Hive.openBox(boxName);
    _messageBoxes[chatId] = box;
    _boxLastUsed[chatId] = DateTime.now();
    return box;
  }

  /// Получить сообщения из кеша
  Future<List<Message>> getCachedMessages(
    String chatId, {
    int? limit,
    int offset = 0,
  }) async {
    // Если идет загрузка для этого чата, ждем ее
    if (_loadOperations.containsKey(chatId)) {
      await _loadOperations[chatId];
    }

    // Создаем операцию загрузки
    final operation = _performLoad(chatId, limit: limit, offset: offset);
    _loadOperations[chatId] = operation;

    try {
      return await operation;
    } finally {
      _loadOperations.remove(chatId);
    }
  }
  
  /// Внутренний метод для выполнения загрузки
  Future<List<Message>> _performLoad(
    String chatId, {
    int? limit,
    int offset = 0,
  }) async {
    try {
      final box = await _getMessageBox(chatId);
      final allKeys = box.keys.toList();
      
      final messages = <Message>[];
      for (final key in allKeys) {
        try {
          final messageJson = box.get(key);
          if (messageJson != null) {
            final messageMap = jsonDecode(messageJson as String);
            messages.add(Message.fromJson(messageMap));
          }
        } catch (e) {
          print('MessageCacheService: Error parsing cached message $key: $e');
        }
      }

      // Сортируем по createdAt (новые последние)
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // Применяем offset и limit
      final startIndex = offset;
      final endIndex = limit != null ? (startIndex + limit).clamp(0, messages.length) : messages.length;
      
      return messages.sublist(startIndex.clamp(0, messages.length), endIndex);
    } catch (e) {
      print('MessageCacheService: Error getting cached messages: $e');
      return [];
    }
  }

  /// Сохранить сообщения в кеш
  Future<void> saveMessages(String chatId, List<Message> messages) async {
    if (messages.isEmpty) return;

    // Если уже идет сохранение для этого чата - ждем его завершения
    if (_saveOperations.containsKey(chatId)) {
      await _saveOperations[chatId];
      return;
    }

    // Создаем операцию сохранения
    final operation = _performSave(chatId, messages);
    _saveOperations[chatId] = operation;

    try {
      await operation;
    } finally {
      _saveOperations.remove(chatId);
    }
  }
  
  /// Внутренний метод для выполнения сохранения
  Future<void> _performSave(String chatId, List<Message> messages) async {
    try {
      final box = await _getMessageBox(chatId);
      
      // Сохраняем каждое сообщение
      for (final message in messages) {
        final messageJson = jsonEncode(message.toJson());
        await box.put(message.id, messageJson);
      }

      // Обновляем метаданные
      await _updateMetadata(chatId, messages);

      print('MessageCacheService: Saved ${messages.length} messages for chat $chatId');
    } catch (e) {
      print('MessageCacheService: Error saving messages: $e');
      rethrow;
    }
  }

  /// Добавить новое сообщение в кеш
  Future<void> addMessage(String chatId, Message message) async {
    try {
      final box = await _getMessageBox(chatId);
      final messageJson = jsonEncode(message.toJson());
      await box.put(message.id, messageJson);
      
      // Обновляем метаданные
      await _updateMetadata(chatId, [message]);
      
      print('MessageCacheService: Added message ${message.id} to cache');
    } catch (e) {
      print('MessageCacheService: Error adding message: $e');
    }
  }

  /// Обновить сообщение в кеше (например, isRead, isLiked)
  Future<void> updateMessage(String chatId, Message message) async {
    try {
      final box = await _getMessageBox(chatId);
      final messageJson = jsonEncode(message.toJson());
      await box.put(message.id, messageJson);
      
      print('MessageCacheService: Updated message ${message.id} in cache');
    } catch (e) {
      print('MessageCacheService: Error updating message: $e');
    }
  }

  /// Получить метаданные кеша для чата
  Future<CacheMetadata?> getCacheMetadata(String chatId) async {
    try {
      if (_metadataBox == null) return null;
      
      final metadataJson = _metadataBox!.get(chatId);
      if (metadataJson == null) return null;
      
      final metadataMap = jsonDecode(metadataJson as String);
      return CacheMetadata.fromJson(metadataMap);
    } catch (e) {
      print('MessageCacheService: Error getting cache metadata: $e');
      return null;
    }
  }

  /// Обновить метаданные кеша
  Future<void> _updateMetadata(String chatId, List<Message> messages) async {
    try {
      if (_metadataBox == null) return;
      
      final box = await _getMessageBox(chatId);
      final totalCached = box.length;
      
      // Находим последнее сообщение
      Message? lastMessage;
      DateTime? lastTimestamp;
      
      for (final message in messages) {
        if (lastTimestamp == null || message.createdAt.isAfter(lastTimestamp)) {
          lastTimestamp = message.createdAt;
          lastMessage = message;
        }
      }

      final metadata = CacheMetadata(
        chatId: chatId,
        lastSyncTimestamp: DateTime.now(),
        lastMessageId: lastMessage?.id,
        hasMore: totalCached >= 15, // Если кешировано >= 15, возможно есть еще
        totalCached: totalCached,
      );

      await _metadataBox!.put(chatId, jsonEncode(metadata.toJson()));
    } catch (e) {
      print('MessageCacheService: Error updating metadata: $e');
    }
  }

  /// Очистить кеш для конкретного чата
  Future<void> clearChatCache(String chatId) async {
    try {
      final box = await _getMessageBox(chatId);
      await box.clear();
      
      if (_metadataBox != null) {
        await _metadataBox!.delete(chatId);
      }
      
      // Закрываем и удаляем box
      await box.close();
      _messageBoxes.remove(chatId);
      
      // Удаляем box из Hive
      await Hive.deleteBoxFromDisk('$_messagesBoxPrefix$chatId');
      
      print('MessageCacheService: Cleared cache for chat $chatId');
    } catch (e) {
      print('MessageCacheService: Error clearing chat cache: $e');
    }
  }

  /// Очистить весь кеш (при выходе из аккаунта)
  Future<void> clearAllCache() async {
    try {
      // Закрываем все открытые boxes
      for (final box in _messageBoxes.values) {
        await box.close();
      }
      _messageBoxes.clear();

      // Получаем список всех чатов из метаданных
      if (_metadataBox != null) {
        final chatIds = _metadataBox!.keys.toList();
        
        // Удаляем все boxes для чатов
        for (final chatId in chatIds) {
          try {
            final boxName = '$_messagesBoxPrefix$chatId';
            await Hive.deleteBoxFromDisk(boxName);
          } catch (e) {
            print('MessageCacheService: Error deleting box for chat $chatId: $e');
          }
        }
      }

      // Очищаем метаданные
      if (_metadataBox != null) {
        await _metadataBox!.clear();
      }

      print('MessageCacheService: Cleared all cache');
    } catch (e) {
      print('MessageCacheService: Error clearing all cache: $e');
    }
  }

  /// Очистить старые кеши (старше 30 дней)
  Future<void> _cleanupOldCaches() async {
    try {
      if (_metadataBox == null) return;

      final now = DateTime.now();
      final keysToDelete = <String>[];

      // Проверяем все метаданные
      for (final key in _metadataBox!.keys) {
        try {
          final metadataJson = _metadataBox!.get(key);
          if (metadataJson != null) {
            final metadataMap = jsonDecode(metadataJson as String);
            final metadata = CacheMetadata.fromJson(metadataMap);
            
            final age = now.difference(metadata.lastSyncTimestamp);
            if (age > _maxCacheAge) {
              keysToDelete.add(key as String);
            }
          }
        } catch (e) {
          print('MessageCacheService: Error checking cache age for $key: $e');
        }
      }

      // Удаляем старые кеши
      for (final chatId in keysToDelete) {
        await clearChatCache(chatId);
      }

      if (keysToDelete.isNotEmpty) {
        print('MessageCacheService: Cleaned up ${keysToDelete.length} old caches');
      }
    } catch (e) {
      print('MessageCacheService: Error cleaning up old caches: $e');
    }
  }

  /// Получить количество закешированных сообщений для чата
  Future<int> getCachedMessagesCount(String chatId) async {
    try {
      final box = await _getMessageBox(chatId);
      return box.length;
    } catch (e) {
      return 0;
    }
  }

  /// Проверить, нужно ли скачивать медиа для сообщения
  /// Скачиваем медиа только для последних N сообщений
  Future<bool> shouldDownloadMedia(String chatId, Message message) async {
    try {
      final box = await _getMessageBox(chatId);
      final allKeys = box.keys.toList();
      
      if (allKeys.length <= _maxMessagesToDownloadMedia) {
        return true; // Если сообщений мало, скачиваем все
      }

      // Получаем последние N сообщений
      final messages = await getCachedMessages(chatId, limit: _maxMessagesToDownloadMedia);
      
      // Проверяем, входит ли наше сообщение в последние N
      final lastMessagesIds = messages.map((m) => m.id).toSet();
      return lastMessagesIds.contains(message.id);
    } catch (e) {
      // При ошибке скачиваем медиа на всякий случай
      return true;
    }
  }

  /// Закрыть все boxes (при завершении работы)
  Future<void> close() async {
    try {
      // Останавливаем таймер очистки
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
      
      // Закрываем все boxes
      for (final box in _messageBoxes.values) {
        await box.close();
      }
      _messageBoxes.clear();
      _boxLastUsed.clear();
      
      // Очищаем активные операции
      _saveOperations.clear();
      _loadOperations.clear();
      
      if (_metadataBox != null) {
        await _metadataBox!.close();
      }
      
      print('MessageCacheService: All boxes closed');
    } catch (e) {
      print('MessageCacheService: Error closing boxes: $e');
    }
  }

  /// Получить все ID сообщений из кеша
  Future<Set<String>> getCachedMessageIds(String chatId) async {
    try {
      final box = await _getMessageBox(chatId);
      return box.keys.map((key) => key.toString()).toSet();
    } catch (e) {
      print('MessageCacheService: Error getting cached message IDs: $e');
      return <String>{};
    }
  }

  /// Проверить, какие сообщения уже есть в кеше
  /// Возвращает только те сообщения, которых нет в кеше
  Future<List<Message>> filterNewMessages(String chatId, List<Message> messages) async {
    try {
      final cachedIds = await getCachedMessageIds(chatId);
      // Возвращаем только те сообщения, которых нет в кеше
      return messages.where((msg) => !cachedIds.contains(msg.id)).toList();
    } catch (e) {
      print('MessageCacheService: Error filtering new messages: $e');
      return messages; // При ошибке возвращаем все
    }
  }

  /// Получить сообщения по ID из кеша
  Future<List<Message>> getMessagesByIds(String chatId, Set<String> messageIds) async {
    try {
      final box = await _getMessageBox(chatId);
      final messages = <Message>[];
      
      for (final messageId in messageIds) {
        try {
          final messageJson = box.get(messageId);
          if (messageJson != null) {
            final messageMap = jsonDecode(messageJson as String);
            messages.add(Message.fromJson(messageMap));
          }
        } catch (e) {
          print('MessageCacheService: Error parsing message $messageId: $e');
        }
      }
      
      // Сортируем по createdAt
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages;
    } catch (e) {
      print('MessageCacheService: Error getting messages by IDs: $e');
      return [];
    }
  }
}

