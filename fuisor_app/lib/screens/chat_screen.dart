import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/online_status_provider.dart';
import '../providers/posts_provider.dart';
import 'package:provider/provider.dart';
import '../widgets/safe_avatar.dart';
import '../widgets/voice_recorder_widget.dart';
import '../widgets/voice_message_player.dart';
import 'chat_profile_screen.dart';
import 'main_screen.dart';
import '../widgets/cached_network_image_with_signed_url.dart';
import '../services/supabase_storage_service.dart';
import '../services/message_cache_service.dart';
import '../services/signed_url_cache_service.dart';
import '../widgets/lazy_media_loader.dart';
import '../widgets/app_notification.dart';
import 'full_screen_image_viewer.dart';
import 'full_screen_video_viewer.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiService _apiService = ApiService();
  final MessageCacheService _cacheService = MessageCacheService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  User? _currentUser;
  bool _isSending = false;
  String? _sendingMessageId; // ID временного сообщения
  Map<String, double> _uploadProgress = {}; // Прогресс загрузки файлов (messageId -> progress 0.0-1.0)
  Map<String, String> _localThumbnailPaths = {}; // Локальные пути к thumbnail для временных сообщений (messageId -> path)
  bool _showScrollToBottom = false; // Показывать ли кнопку прокрутки вниз
  Timer? _messagesPollTimer; // Таймер для polling новых сообщений
  Map<String, dynamic>? _otherUserStatus; // Статус собеседника
  Timer? _statusPollTimer; // Таймер для обновления статуса
  bool _hasText = false; // Для отслеживания наличия текста в поле ввода
  bool _isRecordingVoice = false; // Для отображения voice recorder
  final ImagePicker _imagePicker = ImagePicker();
  final VoiceRecorderController _voiceRecorderController = VoiceRecorderController();
  final AudioPlayer _previewAudioPlayer = AudioPlayer();
  Offset? _recordStartPosition;
  bool _voiceLocked = false;
  bool _voiceCancelled = false;
  bool _showLockAnimation = false; // Для анимации закрепления
  bool _isCancelling = false; // Для анимации отмены
  bool _isPlayingPreview = false; // Для воспроизведения превью голосового сообщения
  bool _isPolling = false; // БАГ FIX 2: Защита от race condition в polling
  Set<String> _unlockedMessages = {}; // Сообщения, которые были разблокированы для загрузки медиа
  Message? _replyingToMessage; // Сообщение, на которое отвечаем
  Map<String, ValueNotifier<double>> _messageSwipeOffsets = {}; // Смещение сообщений при свайпе (messageId -> ValueNotifier)

  static const double _lockDragThreshold = 70;
  static const double _cancelDragThreshold = 70;
  static const int MAX_MESSAGES_IN_MEMORY = 200; // ОПТИМИЗАЦИЯ: Лимит сообщений в памяти

  @override
  void initState() {
    super.initState();
    print('ChatScreen: initState - chat: ${widget.chat.id.substring(0, 8)}...');
    _loadCurrentUser();
    _loadMessages();
    _loadUserStatus();
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onTextChanged);
    
    // Периодическая очистка истекших signed URL (каждые 5 минут)
    Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      SignedUrlCacheService().periodicCleanup();
    });
    
    // Запускаем polling сообщений и статуса
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('ChatScreen: Post frame callback - starting polling');
      _startMessagesPolling();
      _startStatusPolling();
    });
  }

  void _onTextChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });
      print('ChatScreen: Text changed, hasText: $_hasText');
    }
  }

  void _startMessagesPolling() {
    // Останавливаем предыдущий таймер если есть
    _messagesPollTimer?.cancel();
    
    // Polling каждые 2 секунды для получения новых сообщений
    _messagesPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      // БАГ FIX 2: Защита от race condition - пропускаем если предыдущий запрос еще выполняется
      if (_isPolling) {
        print('ChatScreen: Polling already in progress, skipping...');
        return;
      }
      
      _isPolling = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken == null) return;

        _apiService.setAccessToken(accessToken);
        final result = await _apiService.getMessages(
          widget.chat.id,
          page: 1,
          limit: 50,
        );

        if (mounted) {
          final newMessages = result['messages'] as List<Message>;
          
          // Получаем ID всех сообщений из кеша
          final cachedIds = await _cacheService.getCachedMessageIds(widget.chat.id);
          
          // Получаем ID текущих сообщений в UI
          final existingMessageIds = _messages.map((m) => m.id).toSet();
          
          // Находим новые сообщения (которых нет ни в UI, ни в кеше)
          final addedMessages = newMessages.where((m) => 
            !existingMessageIds.contains(m.id) && !cachedIds.contains(m.id)
          ).toList();
          
          if (addedMessages.isNotEmpty) {
            print('🔄 [ChatScreen Polling] Обнаружено ${addedMessages.length} новых сообщений');
            
            // Сохраняем новые сообщения в кеш (они уже отфильтрованы как новые)
            await _cacheService.saveMessages(widget.chat.id, addedMessages);
            
            // ИСПРАВЛЕНИЕ 1: Используем addPostFrameCallback чтобы избежать лишних рендеров
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
            setState(() {
              // Добавляем новые сообщения в конец (они самые новые, уже отсортированы от API)
              _messages.addAll(addedMessages);
              // ВАЖНО: Всегда сортируем после добавления
              _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            });
            
            print('🔄 [ChatScreen Polling] Сообщения добавлены в список, всего: ${_messages.length}');
            
            // Автоматически прокручиваем вниз при новых сообщениях (при reverse: true это позиция 0)
            _scrollToBottom();
            
            // Помечаем новые сообщения как прочитанные
            // Даем небольшую задержку чтобы UI обновился
            Future.delayed(const Duration(milliseconds: 500), () {
              _markMessagesAsRead();
            });
            });
          }
          
          // Обновляем статусы существующих сообщений (на случай изменения isRead, deletedAt, deletedByIds)
          // ИСПРАВЛЕНИЕ 1 & БАГ FIX 4: Оптимизация с использованием Map для O(1) доступа вместо O(n)
          final List<int> changedIndices = [];
          final messageMap = <String, Message>{};
          for (var msg in newMessages) {
            messageMap[msg.id] = msg;
          }
          
          // БАГ FIX 4: Создаем Map текущих сообщений для быстрого доступа (O(1) вместо O(n))
          final existingMessagesMap = <String, int>{};
          for (int i = 0; i < _messages.length; i++) {
            existingMessagesMap[_messages[i].id] = i;
          }
          
          // Находим только измененные сообщения - теперь O(n) вместо O(n²)
          for (final updatedMsg in newMessages) {
            final index = existingMessagesMap[updatedMsg.id];
            if (index != null) {
              final existingMsg = _messages[index];
              // Проверяем только если статус или удаление изменилось
            if (existingMsg.isRead != updatedMsg.isRead || 
                existingMsg.readAt != updatedMsg.readAt ||
                existingMsg.deletedAt != updatedMsg.deletedAt ||
                existingMsg.deletedByIds?.toString() != updatedMsg.deletedByIds?.toString()) {
                changedIndices.add(index);
                // Обновляем в кеше асинхронно
                _cacheService.updateMessage(widget.chat.id, updatedMsg);
              }
            }
          }
          
          // ИСПРАВЛЕНИЕ 1: Обновляем только если есть реальные изменения
          if (changedIndices.isNotEmpty && mounted) {
            // Используем addPostFrameCallback для батчинга обновлений
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                // Применяем все изменения за один раз
                for (final index in changedIndices) {
                  final existingMsg = _messages[index];
                  final updatedMsg = messageMap[existingMsg.id];
                  if (updatedMsg != null) {
                    // Сохраняем replyTo из старого сообщения, если в новом его нет
                    // (API может не возвращать reply_to при polling)
                    final preservedReplyTo = updatedMsg.replyTo ?? existingMsg.replyTo;
                    _messages[index] = updatedMsg.copyWith(replyTo: preservedReplyTo);
                  }
                }
              });
              print('ChatScreen: Updated ${changedIndices.length} message statuses via polling');
            });
          }
        }
      } catch (e) {
        print('Error polling messages: $e');
        // Не останавливаем polling при ошибке
      } finally {
        // БАГ FIX 2: Всегда сбрасываем флаг даже при ошибке
        _isPolling = false;
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    try {
      print('ChatScreen: _markMessagesAsRead called - messages count: ${_messages.length}, currentUser: ${_currentUser?.id.substring(0, 8)}');
      
      if (_messages.isEmpty) {
        print('ChatScreen: _markMessagesAsRead - Messages list is empty, skipping');
        return;
      }
      
      if (_currentUser == null) {
        print('ChatScreen: _markMessagesAsRead - Current user is null, skipping');
        return;
      }
      
      // Находим последнее непрочитанное сообщение от собеседника
      Message? lastUnreadMessage;
      for (int i = _messages.length - 1; i >= 0; i--) {
        final msg = _messages[i];
        print('ChatScreen: Checking message ${msg.id.substring(0, 8)}... - sender: ${msg.senderId.substring(0, 8)}, isRead: ${msg.isRead}, isMine: ${msg.senderId == _currentUser!.id}');
        if (msg.senderId != _currentUser!.id && !msg.isRead) {
          lastUnreadMessage = msg;
          break;
        }
      }
      
      if (lastUnreadMessage == null) {
        print('ChatScreen: _markMessagesAsRead - No unread messages found');
        return;
      }
      
      print('ChatScreen: _markMessagesAsRead - Found unread message: ${lastUnreadMessage.id.substring(0, 8)}...');
      
      {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken == null) return;
        
        _apiService.setAccessToken(accessToken);
        
        try {
          print('ChatScreen: Calling API to mark message ${lastUnreadMessage.id.substring(0, 8)}... as read');
          await _apiService.markMessageAsRead(widget.chat.id, lastUnreadMessage.id);
          print('ChatScreen: API call successful - messages marked as read');
          
          // Обновляем локально статус всех непрочитанных сообщений до этого момента
          setState(() {
            _messages = _messages.map((msg) {
              if (msg.senderId != _currentUser!.id && !msg.isRead &&
                  (msg.createdAt.isBefore(lastUnreadMessage!.createdAt.add(const Duration(seconds: 1))) || 
                   msg.id == lastUnreadMessage.id)) {
                return msg.copyWith(isRead: true, readAt: DateTime.now());
              }
              return msg;
            }).toList();
          });
          
          // Принудительно обновляем данные через API чтобы получить свежие статусы для всех сообщений
          // Это важно чтобы отправитель увидел обновленный статус "Прочитано"
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!mounted) return;
            
            try {
              final prefs = await SharedPreferences.getInstance();
              final accessToken = prefs.getString('access_token');
              if (accessToken == null || !mounted) return;

              _apiService.setAccessToken(accessToken);
              final result = await _apiService.getMessages(widget.chat.id, page: 1, limit: 50);
              
              if (mounted && result['messages'] != null) {
                final updatedMessages = result['messages'] as List<Message>;
                
                print('ChatScreen: Force refresh after mark as read - Got ${updatedMessages.length} messages from API');
                
                // Создаем Map для быстрого поиска
                final messageMap = <String, Message>{};
                for (var msg in updatedMessages) {
                  messageMap[msg.id] = msg;
                }
                
                // Обновляем только статусы существующих сообщений
                bool hasStatusUpdates = false;
                final refreshedMessages = _messages.map((msg) {
                  final updated = messageMap[msg.id];
                  if (updated != null) {
                    // Обновляем если статус или readAt изменился
                    if (msg.isRead != updated.isRead || msg.readAt != updated.readAt) {
                      hasStatusUpdates = true;
                      print('ChatScreen: Force refresh - Message ${msg.id.substring(0, 8)}... - isRead: ${msg.isRead} -> ${updated.isRead}');
                      // Сохраняем replyTo из старого сообщения, если в новом его нет
                      final preservedReplyTo = updated.replyTo ?? msg.replyTo;
                      return updated.copyWith(replyTo: preservedReplyTo);
                    }
                  }
                  return msg;
                }).toList();
                
                if (hasStatusUpdates && mounted) {
                  setState(() {
                    _messages = refreshedMessages;
                  });
                  print('ChatScreen: Force refreshed message read statuses successfully');
                }
              }
            } catch (e) {
              print('ChatScreen: Error force refreshing messages: $e');
            }
          });
        } catch (e) {
          print('ChatScreen: Error marking messages as read: $e');
        }
      }
    } catch (e) {
      print('ChatScreen: Error in _markMessagesAsRead: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _messagesPollTimer?.cancel();
    _statusPollTimer?.cancel();
    // БАГ FIX 3: Останавливаем воспроизведение перед dispose чтобы избежать утечки памяти
    _previewAudioPlayer.stop();
    _previewAudioPlayer.dispose();
    super.dispose();
  }

  // Загрузить статус пользователя
  Future<void> _loadUserStatus() async {
    if (widget.chat.otherUser == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      final onlineStatusProvider = context.read<OnlineStatusProvider>();
      final status = await onlineStatusProvider.getUserStatus(
        widget.chat.otherUser!.id,
        accessToken,
      );

      if (mounted) {
        setState(() {
          _otherUserStatus = status;
        });
      }
    } catch (e) {
      print('Error loading user status: $e');
    }
  }

  // Запустить периодическое обновление статуса (каждые 30 секунд)
  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _loadUserStatus();
    });
  }

  Future<void> _loadCurrentUser() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser != null) {
      setState(() {
        _currentUser = authProvider.currentUser;
      });
    }
  }

  Future<void> _loadMessages({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _messages.clear();
        _hasMore = true;
        _isLoading = true;
      });
      
      // При refresh загружаем сразу с сервера
    } else if (!_hasMore || _isLoadingMore) {
      return;
    }

    // ПРИ ПЕРВОЙ ЗАГРУЗКЕ: Сначала показываем кеш для мгновенного отображения
    if (!refresh && _messages.isEmpty && !_isLoadingMore) {
      try {
        // БАГ FIX: Загружаем ВСЕ кешированные сообщения и берем последние 15
        final cachedMessages = await _cacheService.getCachedMessages(
          widget.chat.id,
          // Не ограничиваем лимитом, берем все из кеша
        );
        
        if (cachedMessages.isNotEmpty && mounted) {
          // Сортируем кешированные сообщения
          final sortedCached = List<Message>.from(cachedMessages);
          sortedCached.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          
          // БАГ FIX: Берем только последние 15 (самые новые) для мгновенного показа
          final recentCached = sortedCached.length > 15 
              ? sortedCached.sublist(sortedCached.length - 15)
              : sortedCached;
          
          setState(() {
            _messages = recentCached;
            _isLoading = false; // Показываем кешированные сразу
          });
          
          print('ChatScreen: Loaded ${recentCached.length} recent messages from cache (total cached: ${cachedMessages.length})');
          
          // Затем обновляем с сервера в фоне
          _loadMessagesFromServer();
          return;
        }
      } catch (e) {
        print('ChatScreen: Error loading from cache: $e');
        // Продолжаем загрузку с сервера
      }
    }
    
    // Загружаем с сервера
    _loadMessagesFromServer();
  }
  
  Future<void> _loadMessagesFromServer() async {
    // БАГ FIX: Определяем, загружаем ли мы после кеша (сообщения уже есть, но это первая страница)
    final isLoadingAfterCache = _currentPage == 1 && _messages.isNotEmpty;
    final refresh = _currentPage == 1 && _messages.isEmpty;

    try {
      setState(() {
        if (!refresh) {
          _isLoadingMore = true;
        } else {
          _isLoading = true;
        }
      });

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
        return;
      }

      _apiService.setAccessToken(accessToken);
      final result = await _apiService.getMessages(
        widget.chat.id,
        page: _currentPage,
        limit: 15, // Загружаем по 15 сообщений за раз
      );

      if (mounted) {
        final newMessages = result['messages'] as List<Message>;
        
        // Получаем ID всех сообщений из кеша
        final cachedIds = await _cacheService.getCachedMessageIds(widget.chat.id);
        
        // Фильтруем: оставляем только те сообщения, которых нет в кеше
        final messagesToCache = newMessages.where((m) => !cachedIds.contains(m.id)).toList();
        
        // Сохраняем в кеш только новые сообщения
        if (messagesToCache.isNotEmpty) {
          await _cacheService.saveMessages(widget.chat.id, messagesToCache);
          print('ChatScreen: Saved ${messagesToCache.length} new messages to cache (${newMessages.length - messagesToCache.length} already cached)');
        } else {
          print('ChatScreen: All ${newMessages.length} messages already in cache, skipping save');
        }
        
        // Получаем ID текущих сообщений в UI для дедупликации
        final existingIds = _messages.map((m) => m.id).toSet();
        
        // Фильтруем: оставляем только те сообщения, которых нет в UI
        final uniqueNewMessages = newMessages.where((m) => !existingIds.contains(m.id)).toList();
        
        // Логирование для отладки thumbnail в сообщениях
        for (final msg in uniqueNewMessages) {
          if (msg.messageType == 'video') {
            print('ChatScreen: Loading message ${msg.id.substring(0, 8)}... - thumbnailUrl: ${msg.thumbnailUrl}, mediaUrl: ${msg.mediaUrl?.substring(0, 20)}...');
          }
        }
        
        if (uniqueNewMessages.isNotEmpty || newMessages.isNotEmpty || isLoadingAfterCache) {
          // Сохраняем состояние скролла перед добавлением сообщений
          double? oldScrollOffset;
          double? oldMaxScrollExtent;
          int oldItemCount = _messages.length;
          
          if (_scrollController.hasClients && !refresh) {
            final scrollPosition = _scrollController.position;
            oldScrollOffset = scrollPosition.pixels;
            oldMaxScrollExtent = scrollPosition.maxScrollExtent;
          }
          
          // БАГ FIX: Батчинг обновлений - собираем все изменения и применяем за один раз
          // Это предотвращает множественные перерисовки и "дергание" экрана
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            
            // БАГ FIX: Используем только один setState для всех изменений
          setState(() {
            if (refresh) {
              // При refresh - это последние сообщения, заменяем весь список
              _messages = uniqueNewMessages;
              } else if (isLoadingAfterCache) {
                // БАГ FIX: При загрузке после кеша - объединяем с кешем и обновляем
                // Создаем Map для быстрого объединения
                final messageMap = <String, Message>{};
                
                // Сначала добавляем кешированные
                for (var msg in _messages) {
                  messageMap[msg.id] = msg;
                }
                
                // Затем добавляем/обновляем серверными (они приоритетнее)
                for (var msg in newMessages) {
                  messageMap[msg.id] = msg;
                }
                
                // Конвертируем обратно в список
                _messages = messageMap.values.toList();
            } else {
              // При прокрутке вверх - это старые сообщения, добавляем в начало
              _messages = [...uniqueNewMessages, ..._messages];
            }
            
            // ВАЖНО: Всегда сортируем после объединения
            _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              
              // БАГ FIX 7: Виртуализация - ограничиваем количество сообщений в памяти
              if (_messages.length > MAX_MESSAGES_IN_MEMORY) {
                print('ChatScreen: Memory optimization - limiting to $MAX_MESSAGES_IN_MEMORY messages (had ${_messages.length})');
                // Удаляем старые сообщения из памяти (они остаются в кеше)
                _messages = _messages.sublist(_messages.length - MAX_MESSAGES_IN_MEMORY);
              }
            
            _currentPage++;
            _hasMore = newMessages.length >= 15;
            _isLoading = false;
            _isLoadingMore = false;
          });
          });
          
          // БАГ FIX: Восстанавливаем позицию скролла правильно - сообщения добавляются вверх, позиция не меняется
          if (!refresh && uniqueNewMessages.isNotEmpty && oldScrollOffset != null && oldMaxScrollExtent != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scrollController.hasClients) return;
              
              final scrollPosition = _scrollController.position;
              final newMaxScrollExtent = scrollPosition.maxScrollExtent;
              
              // Если maxScrollExtent не изменился, позиция не должна меняться
              if (oldMaxScrollExtent != null && oldScrollOffset != null && newMaxScrollExtent == oldMaxScrollExtent) {
                // Просто восстанавливаем старую позицию
                _scrollController.jumpTo(oldScrollOffset.clamp(0.0, newMaxScrollExtent));
                return;
              }
              
              // Вычисляем относительную позицию скролла (0.0 - 1.0)
              if (oldMaxScrollExtent == null || oldScrollOffset == null || oldMaxScrollExtent <= 0) {
                return; // Не можем восстановить позицию без данных
              }
              
              final oldScrollRatio = oldScrollOffset / oldMaxScrollExtent;
              
              // Применяем ту же относительную позицию к новому maxScrollExtent
              // Это сохраняет визуальную позицию пользователя
              final newScrollOffset = newMaxScrollExtent * oldScrollRatio;
                
                // Прыгаем на новую позицию без анимации
                _scrollController.jumpTo(
                newScrollOffset.clamp(0.0, newMaxScrollExtent)
                );
                
              print('ChatScreen: Restored scroll position - old ratio: ${oldScrollRatio.toStringAsFixed(3)}, new offset: ${newScrollOffset.toStringAsFixed(0)}, added: ${_messages.length - oldItemCount} messages');
            });
          }
          
          if (uniqueNewMessages.length < newMessages.length) {
            print('ChatScreen: Skipped ${newMessages.length - uniqueNewMessages.length} duplicate messages');
          }
        } else {
          // Все сообщения уже есть в UI
          setState(() {
            _currentPage++;
            _hasMore = newMessages.length >= 15;
            _isLoading = false;
            _isLoadingMore = false;
          });
          print('ChatScreen: All ${newMessages.length} messages already in UI, skipping update');
        }

            // Помечаем сообщения как прочитанные после загрузки
        if (refresh && _messages.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
              Future.delayed(const Duration(milliseconds: 500), () {
              print('ChatScreen: Calling _markMessagesAsRead (refresh: $refresh)');
                _markMessagesAsRead();
              });
          });
        }
      }
    } catch (e) {
      print('Error loading messages from server: $e');
      // При ошибке используем кеш, если список пуст
      if (_messages.isEmpty) {
        try {
          final cachedMessages = await _cacheService.getCachedMessages(widget.chat.id, limit: 15);
          if (cachedMessages.isNotEmpty && mounted) {
            setState(() {
              // Заменяем весь список кешированными сообщениями (не добавляем к существующим)
              _messages = cachedMessages;
              // Убеждаемся, что кеш отсортирован
              _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              _isLoading = false;
            });
            print('ChatScreen: Using ${cachedMessages.length} cached messages due to error');
          } else {
            setState(() {
              _isLoading = false;
            });
          }
        } catch (cacheError) {
          print('ChatScreen: Error loading from cache: $cacheError');
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        
        AppNotification.showError(context, 'Failed to load messages: $e');
      }
    }
  }

  void _onScroll() {
    // Убираем фокус с поля ввода при скролле
    _messageFocusNode.unfocus();
    
    // При reverse: true:
    // - позиция 0 = низ (последние сообщения)
    // - maxScrollExtent = верх (первые сообщения)
    if (_scrollController.hasClients) {
      final currentScroll = _scrollController.position.pixels;
      final maxScroll = _scrollController.position.maxScrollExtent;
      
      // Загрузка старых сообщений при прокрутке вверх (когда близко к верху списка)
      // При reverse: true, верх - это maxScrollExtent
      if (currentScroll >= (maxScroll - 200) && _hasMore && !_isLoadingMore) {
      _loadMessages();
    }
    
    // Показываем/скрываем кнопку прокрутки вниз
      // При reverse: true, мы внизу когда currentScroll == 0
      // Показываем кнопку, если мы не внизу (currentScroll > 200)
      final shouldShow = maxScroll > 0 && currentScroll > 200;
      
      if (shouldShow != _showScrollToBottom) {
        setState(() {
          _showScrollToBottom = shouldShow;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // При reverse: true, прокрутка вниз = позиция 0 (последние сообщения)
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Скролл к конкретному сообщению по ID
  void _scrollToMessage(String messageId) {
    if (!_scrollController.hasClients) return;
    
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) {
      // Сообщение не найдено в текущем списке, возможно нужно загрузить больше
      AppNotification.showError(context, 'Message not found');
      return;
    }
    
    // При reverse: true, индекс 0 = внизу, больший индекс = выше
    // Позиция скролла: 0 = внизу, maxScrollExtent = вверху
    // Нужно вычислить позицию для сообщения с индексом messageIndex
    
    // Используем приблизительную высоту элемента
    final estimatedItemHeight = 80.0;
    final itemPositionFromTop = messageIndex * estimatedItemHeight;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    
    // Позиция скролла должна быть такой, чтобы элемент был виден
    // viewportTop = maxScrollExtent - scrollOffset
    // Мы хотим, чтобы элемент был в верхней части viewport
    final targetScrollOffset = maxScrollExtent - itemPositionFromTop;
    
    _scrollController.animateTo(
      targetScrollOffset.clamp(0.0, maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // Красивый скелетон загрузки вместо прогресс-бара
  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      itemCount: 5, // Показываем 5 скелетонов сообщений
      itemBuilder: (context, index) {
        // Чередуем сообщения слева и справа для реалистичности
        final isOwnMessage = index % 2 == 0;
        final isImageMessage = index == 2 || index == 4; // Некоторые сообщения с изображениями
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isOwnMessage) ...[
                // Аватар слева (только для входящих)
                Shimmer.fromColors(
                  baseColor: const Color(0xFF262626),
                  highlightColor: const Color(0xFF3A3A3A),
                  period: const Duration(milliseconds: 1200),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Сообщение или изображение
              if (isImageMessage)
                // Скелетон изображения
                Shimmer.fromColors(
                  baseColor: const Color(0xFF262626),
                  highlightColor: const Color(0xFF3A3A3A),
                  period: const Duration(milliseconds: 1200),
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(24),
                        topRight: const Radius.circular(24),
                        bottomLeft: Radius.circular(isOwnMessage ? 24 : 6),
                        bottomRight: Radius.circular(isOwnMessage ? 6 : 24),
                      ),
                    ),
                  ),
                )
              else
                // Скелетон текстового сообщения
                Shimmer.fromColors(
                  baseColor: const Color(0xFF262626),
                  highlightColor: const Color(0xFF3A3A3A),
                  period: const Duration(milliseconds: 1200),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isOwnMessage ? const Color(0xFF0095F6) : const Color(0xFF262626),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(24),
                        topRight: const Radius.circular(24),
                        bottomLeft: Radius.circular(isOwnMessage ? 24 : 6),
                        bottomRight: Radius.circular(isOwnMessage ? 6 : 24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Случайная ширина для текста
                        Container(
                          width: (MediaQuery.of(context).size.width * 0.4) + (index * 20.0),
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        if (index % 3 == 0) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: (MediaQuery.of(context).size.width * 0.3) + (index * 15.0),
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    // Сохраняем replyToId перед очисткой
    final replyToId = _replyingToMessage?.id;
    
    // Очищаем поле ввода и ответ
    _messageController.clear();
    final replyingToMessage = _replyingToMessage;
    setState(() {
      _replyingToMessage = null;
    });

    // Создаем временное сообщение для оптимистичного обновления UI
    final tempMessageId = DateTime.now().millisecondsSinceEpoch.toString();
    final tempMessage = Message(
      id: tempMessageId,
      chatId: widget.chat.id,
      senderId: _currentUser?.id ?? '',
      content: content,
      isRead: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sender: _currentUser,
      replyToId: replyToId,
      replyTo: replyingToMessage,
    );

    // ИСПРАВЛЕНИЕ 1: Добавляем временное сообщение в конец списка с минимальным рендерингом
    if (mounted) {
        setState(() {
          _isSending = true;
          _sendingMessageId = tempMessageId;
          // Добавляем временное сообщение в конец (уже отсортировано по времени)
          _messages.add(tempMessage);
        // Сортируем только если нужно
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
      // Скроллим после обновления UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
      _scrollToBottom();
        }
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        // Удаляем временное сообщение и возвращаем текст
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
          setState(() {
            _messages.removeWhere((m) => m.id == tempMessageId);
            _isSending = false;
            _sendingMessageId = null;
          });
          _messageController.text = content;
          });
        }
        return;
      }

      _apiService.setAccessToken(accessToken);
      final message = await _apiService.sendMessage(widget.chat.id, content, replyToId: replyToId);

      // Сохраняем в кеш асинхронно (не блокируем UI)
      _cacheService.addMessage(widget.chat.id, message);

      // ИСПРАВЛЕНИЕ 1: Заменяем временное сообщение на реальное с минимальным рендерингом
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
        // Оптимизация: обновляем только нужный элемент без полного перерендера
          final index = _messages.indexWhere((m) => m.id == tempMessageId);
          if (index != -1) {
              // Просто заменяем элемент без пересортировки (уже в правильной позиции)
          setState(() {
            _messages[index] = message;
            _isSending = false;
            _sendingMessageId = null;
          });
          } else {
            // Если временное сообщение не найдено, добавляем в конец
          setState(() {
            _messages.add(message);
            _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _isSending = false;
          _sendingMessageId = null;
        });
        }
        });
      }
    } catch (e) {
      print('Error sending message: $e');
      
      // Удаляем временное сообщение и возвращаем текст
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
        setState(() {
          _messages.removeWhere((m) => m.id == tempMessageId);
          _isSending = false;
          _sendingMessageId = null;
        });
        _messageController.text = content;
        
        AppNotification.showError(context, 'Failed to send message: $e');
        });
      }
    }
  }

  // Методы для воспроизведения превью голосового сообщения
  Future<void> _startPreviewPlayback(String path) async {
    try {
      setState(() {
        _isPlayingPreview = true;
      });
      
      await _previewAudioPlayer.play(DeviceFileSource(path));
      
      // Слушаем окончание воспроизведения
      _previewAudioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlayingPreview = false;
          });
        }
      });
    } catch (e) {
      print('Error playing preview: $e');
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
        });
      }
    }
  }

  Future<void> _stopPreviewPlayback() async {
    try {
      await _previewAudioPlayer.stop();
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
        });
      }
    } catch (e) {
      print('Error stopping preview: $e');
    }
  }

  PreferredSizeWidget _buildBlurAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: widget.chat.isDirect && widget.chat.otherUser != null
                    ? InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ChatProfileScreen(chat: widget.chat),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                SafeAvatar(
                                  imageUrl: widget.chat.displayAvatar,
                                  radius: 18,
                                ),
                                // Зеленый индикатор онлайн
                                if (_otherUserStatus?['is_online'] == true)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4CAF50),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.black,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.chat.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _otherUserStatus?['status_text'] ?? 'loading...',
                                    style: TextStyle(
                                      color: _otherUserStatus?['is_online'] == true
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFF8E8E8E),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          SafeAvatar(
                            imageUrl: widget.chat.displayAvatar,
                            radius: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.chat.displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Убираем фокус с поля ввода при нажатии вне его
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: true,
      appBar: _buildBlurAppBar(),
      body: SafeArea(
        bottom: true,
        child: Column(
        children: [
          // Messages list
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? _buildLoadingSkeleton()
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              EvaIcons.messageCircleOutline,
                              size: 64,
                              color: Color(0xFF8E8E8E),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No messages yet',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start the conversation',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            reverse: true, // Новые сообщения внизу
                            padding: EdgeInsets.only(
                              top: 16,
                              bottom: _replyingToMessage != null ? 80 : 16, // Добавляем padding если есть reply preview
                            ),
                            itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                            // Оптимизация производительности
                            cacheExtent: 1000, // Кешируем элементы вне видимой области
                            addAutomaticKeepAlives: false, // Не сохраняем состояние элементов
                            addRepaintBoundaries: true, // Автоматические границы перерисовки
                            // Для лучшей виртуализации используем примерную высоту элемента
                            // Это помогает ListView лучше планировать рендеринг
                            key: const PageStorageKey('chat_messages'), // Сохраняем позицию скролла
                            itemBuilder: (context, index) {
                              // Индикатор загрузки старых сообщений показываем в конце списка (вверху при reverse: true)
                              if (index == _messages.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF0095F6),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }

                              // При reverse: true, индекс 0 - это последнее сообщение (самое новое)
                              // Поэтому берем сообщения в обратном порядке
                              final reversedIndex = _messages.length - 1 - index;
                              final message = _messages[reversedIndex];
                              // Определяем, нужно ли показывать статус для этого сообщения
                              final shouldShowStatus = _shouldShowMessageStatus(reversedIndex);
                              
                              // Используем RepaintBoundary для изоляции перерисовки каждого элемента
                              // УБРАЛИ LazyMediaLoader отсюда - он теперь только для медиа внутри сообщений
                              // Анимация появления сообщений
                              return RepaintBoundary(
                                key: ValueKey(message.id),
                                        child: _buildMessageItem(
                                          message, 
                                          showStatus: shouldShowStatus,
                                ),
                              );
                            },
                          ),
                          // Кнопка прокрутки вниз к новым сообщениям
                          if (_showScrollToBottom && _messages.isNotEmpty)
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              bottom: 16,
                              right: 16,
                              child: Material(
                                color: const Color(0xFF0095F6),
                                borderRadius: BorderRadius.circular(28),
                                elevation: 4,
                                child: InkWell(
                                  onTap: _scrollToBottom,
                                  borderRadius: BorderRadius.circular(28),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    padding: const EdgeInsets.all(8),
                                    child: const Icon(
                                      EvaIcons.arrowDownwardOutline,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Reply preview (если есть сообщение для ответа) - positioned поверх сообщений
                          if (_replyingToMessage != null)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 8,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          EvaIcons.cornerDownRight,
                                          color: Color(0xFF0095F6),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Reply to: ${_replyingToMessage!.sender?.username ?? 'User'}',
                                                style: const TextStyle(
                                                  color: Color(0xFF0095F6),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _replyingToMessage!.content ?? 
                                                (_replyingToMessage!.messageType == 'image' ? 'Photo' :
                                                 _replyingToMessage!.messageType == 'video' ? 'Video' :
                                                 _replyingToMessage!.messageType == 'voice' ? 'Voice message' : 'Message'),
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.7),
                                                  fontSize: 11,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _replyingToMessage = null;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              EvaIcons.close,
                                              color: Colors.white70,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
          // Message input container с иконкой замочка
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Основной контейнер (расширяется при многострочном вводе)
              Container(
                margin: const EdgeInsets.all(8),
                constraints: const BoxConstraints(
                  minHeight: 50, // Минимальная высота
                  maxHeight: 150, // Максимальная высота (примерно 5-6 строк)
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: const Color(0xFF3A3A3A),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center, // Центрирование всех элементов
                  children: [
                  // Плавный переход между VoiceRecorderWidget и полем ввода
                    Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        // Анимация slide + fade для отмены
                        if (_isCancelling) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: Offset.zero,
                              end: const Offset(-1.0, 0.0), // Сдвиг влево
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOut,
                            )),
                            child: FadeTransition(
                              opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
                                CurvedAnimation(parent: animation, curve: Curves.easeOut),
                              ),
                              child: child,
                            ),
                          );
                        }
                        // Обычная fade анимация для появления
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.1, 0.0),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOut,
                            )),
                            child: child,
                          ),
                        );
                      },
                      child: _isRecordingVoice
                          ? VoiceRecorderWidget(
                              key: const ValueKey('voice_recorder'),
                        controller: _voiceRecorderController,
                        onSend: (path, duration) async {
                          try {
                            final totalStartTime = DateTime.now();
                            final safeDuration = duration > 0 ? duration : 1;
                            print('🚀 [ChatScreen] Начало процесса отправки голосового сообщения');
                            print('🚀 [ChatScreen] Файл: $path, длительность: $duration сек (безопасная: $safeDuration)');
                            
                            // Шаг 1: Загрузка файла
                            print('🚀 [ChatScreen] Шаг 1/2: Загрузка файла на сервер...');
                            final uploadResult = await _apiService.uploadVoiceMessage(
                              chatId: widget.chat.id,
                              filePath: path,
                              duration: safeDuration,
                            );
                            
                            print('🚀 [ChatScreen] ✅ Шаг 1 завершен - файл загружен');
                            print('🚀 [ChatScreen] MediaUrl получен: ${uploadResult['mediaUrl']}');
                            
                            // Шаг 2: Отправка сообщения
                            print('🚀 [ChatScreen] Шаг 2/2: Создание сообщения в БД...');
                            final message = await _apiService.sendVoiceMessage(
                              chatId: widget.chat.id,
                              mediaUrl: uploadResult['mediaUrl'],
                              duration: uploadResult['mediaDuration'] ?? safeDuration,
                              size: uploadResult['mediaSize'],
                            );
                            
                            final totalEndTime = DateTime.now();
                            final totalDuration = totalEndTime.difference(totalStartTime).inMilliseconds;
                            
                            print('🚀 [ChatScreen] ✅ Шаг 2 завершен - сообщение создано');
                            print('🚀 [ChatScreen] ✅ ВСЕГО: Голосовое сообщение отправлено успешно!');
                            print('🚀 [ChatScreen] ID сообщения: ${message.id}');
                            print('🚀 [ChatScreen] Общее время отправки: ${totalDuration}ms (${(totalDuration / 1000).toStringAsFixed(2)} сек)');
                            print('🚀 [ChatScreen] Добавление сообщения в локальный список...');
                            
                            // Сохраняем в кеш
                            await _cacheService.addMessage(widget.chat.id, message);
                            
                            // Добавляем сообщение локально в конец списка
                            if (mounted) {
                              setState(() {
                                _messages.add(message);
                                // Сортируем по времени (старые -> новые)
                                _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                                _isRecordingVoice = false;
                                _voiceLocked = false;
                                _voiceCancelled = false;
                              });
                              _scrollToBottom();
                              print('🚀 [ChatScreen] Сообщение добавлено в UI, всего сообщений: ${_messages.length}');
                              print('🚀 [ChatScreen] Ожидание подтверждения через polling (проверка каждые 2 сек)...');
                            }
                          } catch (e) {
                            print('🚀 [ChatScreen] ❌ ОШИБКА при отправке голосового сообщения: $e');
                            if (mounted) {
                              AppNotification.showError(context, 'Failed to send voice message: $e');
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isRecordingVoice = false;
                                _voiceLocked = false;
                                _voiceCancelled = false;
                              });
                            }
                          }
                        },
                        onCancel: () {
                          // Анимация отмены уже запущена, просто сбрасываем состояние
                          setState(() {
                            _isRecordingVoice = false;
                            _voiceLocked = false;
                            _voiceCancelled = false;
                            _isCancelling = false;
                          });
                        },
                    )
                          : Row(
                              key: const ValueKey('message_input'),
                              children: [
                    // Plus button (left) with menu
                    Builder(
                      builder: (buttonContext) => Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            // Убираем фокус с поля ввода перед показом меню
                            _messageFocusNode.unfocus();
                            _showAttachmentMenu(buttonContext);
                          },
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(30),
                            bottomLeft: Radius.circular(30),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: const Icon(
                              EvaIcons.plusCircle,
                              color: Color(0xFF0095F6),
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Message input field
                    Expanded(
                      child: Container(
                        color: const Color(0xFF262626), // Тот же цвет что и контейнер
                        child: TextField(
                          controller: _messageController,
                          focusNode: _messageFocusNode,
                          onChanged: (text) {
                            // Дополнительный вызов для надежности
                            _onTextChanged();
                          },
                          decoration: const InputDecoration(
                            hintText: 'Message...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            hintStyle: TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: Color(0xFF262626), // Тот же цвет что и контейнер
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          minLines: 1, // Минимум 1 строка
                          maxLines: 5, // Максимум 5 строк (после этого появится скролл внутри TextField)
                          textInputAction: TextInputAction.newline, // Enter создает новую строку
                          keyboardType: TextInputType.multiline, // Многострочный ввод
                          onSubmitted: (_) {
                            // При нажатии Enter создается новая строка
                            // Отправка происходит только через кнопку отправки
                          },
                        ),
                      ),
                    ),
                  ],
                            ),
                          ),
                  ),
                  // Кнопка Стоп/Cancel слева от микрофона (в locked режиме)
                  if (_isRecordingVoice && _voiceLocked)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                              CurvedAnimation(parent: animation, curve: Curves.easeOut),
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: _AnimatedStopCancelButton(
                        isStopped: _voiceRecorderController.isStopped,
                        onTap: () async {
                          if (_voiceRecorderController.isStopped) {
                            // Если остановлено - отменяем с анимацией
                            print('ChatScreen: Cancelling stopped voice recording');
                            // Останавливаем воспроизведение, если оно активно
                            if (_isPlayingPreview) {
                              await _stopPreviewPlayback();
                            }
                            // Запускаем анимацию отмены
                            if (mounted) {
                              setState(() {
                                _isCancelling = true;
                              });
                            }
                            // Ждем завершения анимации, затем отменяем запись
                            await Future.delayed(const Duration(milliseconds: 300));
                            await _voiceRecorderController.cancelRecording();
                            if (mounted) {
                              setState(() {
                                _isRecordingVoice = false;
                                _voiceLocked = false;
                                _voiceCancelled = false;
                                _isCancelling = false;
                              });
                            }
                          } else {
                            // Если записывается - останавливаем
                            print('ChatScreen: Stopping voice recording (locked mode)');
                            await _voiceRecorderController.stopRecording();
                            // Обновляем состояние для немедленного отображения изменений
                            if (mounted) {
                              setState(() {});
                            }
                          }
                        },
                      ),
                    ),
                  // Кнопка воспроизведения (только когда запись остановлена)
                  if (_isRecordingVoice && _voiceLocked && _voiceRecorderController.isStopped)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                              CurvedAnimation(parent: animation, curve: Curves.easeOut),
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: _PlayPreviewButton(
                        key: const ValueKey('play_preview'),
                        isPlaying: _isPlayingPreview,
                        onTap: () async {
                          final path = _voiceRecorderController.stoppedPath;
                          if (path == null) return;
                          
                          if (_isPlayingPreview) {
                            // Остановить воспроизведение
                            print('ChatScreen: Stopping preview playback');
                            await _stopPreviewPlayback();
                          } else {
                            // Начать воспроизведение
                            print('ChatScreen: Starting preview playback: $path');
                            await _startPreviewPlayback(path);
                          }
                        },
                      ),
                    ),
                  // Send button / Microphone button (right) - динамическая смена с анимацией
                  GestureDetector(
                    onLongPressStart: !_hasText
                        ? (details) {
                            print('ChatScreen: Long press start - starting recorder');
                            _recordStartPosition = details.globalPosition;
                            _voiceLocked = false;
                            _voiceCancelled = false;
                            setState(() {
                              _isRecordingVoice = true;
                            });
                          }
                        : null,
                    onLongPressMoveUpdate: !_hasText
                        ? (details) async {
                            if (_recordStartPosition == null || _voiceCancelled) return;
                            final dx = details.globalPosition.dx - _recordStartPosition!.dx;
                            final dy = details.globalPosition.dy - _recordStartPosition!.dy;

                            if (!_voiceLocked && dy < -_lockDragThreshold) {
                              setState(() {
                                _voiceLocked = true;
                                _showLockAnimation = true;
                              });
                              print('ChatScreen: Voice recording locked');
                              _voiceRecorderController.lockRecording();
                              // Скрыть анимацию через 600ms (увеличено для более заметной анимации)
                              Future.delayed(const Duration(milliseconds: 600), () {
                                if (mounted) {
                                  setState(() {
                                    _showLockAnimation = false;
                                  });
                                }
                              });
                            } else if (!_voiceLocked && !_voiceCancelled && dx < -_cancelDragThreshold) {
                              _voiceCancelled = true;
                              print('ChatScreen: Voice recording cancelled via swipe');
                              _recordStartPosition = null;
                              // Запускаем анимацию отмены
                              if (mounted) {
                                setState(() {
                                  _isCancelling = true;
                                });
                              }
                              // Ждем завершения анимации, затем отменяем запись
                              await Future.delayed(const Duration(milliseconds: 300));
                              await _voiceRecorderController.cancelRecording();
                              if (mounted) {
                                setState(() {
                                  _isRecordingVoice = false;
                                  _isCancelling = false;
                                });
                              }
                            }
                          }
                        : null,
                    onLongPressEnd: !_hasText
                        ? (details) async {
                            final wasCancelled = _voiceCancelled;
                            final wasLocked = _voiceLocked;
                            _recordStartPosition = null;

                            // Если отменено - сбрасываем флаги и выходим
                            if (wasCancelled) {
                              print('ChatScreen: Long press end ignored (cancelled)');
                              if (mounted) {
                                setState(() {
                                  _voiceCancelled = false;
                                  _voiceLocked = false;
                                });
                              }
                              return;
                            }

                            // Если заблокировано - не отправляем, пользователь сам нажмет Send
                            if (wasLocked) {
                              print('ChatScreen: Long press end while locked - awaiting user action');
                              return;
                            }

                            // Обычный режим: отпустил → сразу отправляем
                            print('ChatScreen: Long press end - sending voice message immediately');
                            await _voiceRecorderController.stopAndSendImmediate();
                            if (mounted) {
                              setState(() {
                                _isRecordingVoice = false;
                                _voiceLocked = false;
                                _voiceCancelled = false;
                              });
                            }
                          }
                        : null,
                    onLongPressCancel: !_hasText
                        ? () async {
                            print('ChatScreen: Long press cancelled');
                            _recordStartPosition = null;
                            // Если запись заблокирована (locked режим), не отменяем запись
                            // Пользователь может отправить её позже через кнопку
                            if (!_voiceCancelled && !_voiceLocked) {
                              print('ChatScreen: Cancelling recording (not locked)');
                              await _voiceRecorderController.cancelRecording();
                              if (mounted) {
                                setState(() {
                                  _isRecordingVoice = false;
                                  _voiceLocked = false;
                                  _voiceCancelled = false;
                                });
                              }
                            } else if (_voiceLocked) {
                              print('ChatScreen: Long press cancelled but recording is locked - keeping recording active');
                            }
                          }
                        : null,
                    onTap: _hasText
                        ? (_isSending ? null : _sendMessage)
                        : (_isRecordingVoice && _voiceLocked)
                            ? () async {
                                // Отправка голосового сообщения в locked режиме
                                // Останавливаем воспроизведение, если оно активно
                                if (_isPlayingPreview) {
                                  await _stopPreviewPlayback();
                                }
                                // Если остановлено - отправляем остановленное, иначе останавливаем и отправляем
                                print('ChatScreen: Sending voice message in locked mode (stopped: ${_voiceRecorderController.isStopped})');
                                await _voiceRecorderController.stopAndSendImmediate();
                                if (mounted) {
                                  setState(() {
                                    _isRecordingVoice = false;
                                    _voiceLocked = false;
                                    _voiceCancelled = false;
                                  });
                                }
                              }
                            : () {
                                print('ChatScreen: Short tap on microphone');
                                AppNotification.showInfo(
                                  context,
                                  'Hold to record voice message',
                                  duration: const Duration(seconds: 2),
                                );
                              },
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (_isSending || _hasText)
                              ? const Color(0xFF0095F6)
                              : const Color(0xFF0095F6).withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (Widget child, Animation<double> animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                                        CurvedAnimation(parent: animation, curve: Curves.easeOut),
                                      ),
                                      child: child,
                                    ),
                                  );
                                },
                                child: _hasText
                                    ? const Icon(
                                        EvaIcons.arrowCircleUp,
                                        key: ValueKey('send'),
                                        color: Colors.white,
                                        size: 24,
                                    )
                                  : (_isRecordingVoice && _voiceLocked && _voiceRecorderController.isStopped)
                                      ? const Icon(
                                          EvaIcons.arrowCircleUp,
                                          key: ValueKey('send_stopped_voice'),
                                        color: Colors.white,
                                        size: 24,
                                      )
                                    : (_isRecordingVoice && _voiceLocked)
                                        ? const Icon(
                                            EvaIcons.arrowCircleUp,
                                          key: ValueKey('send_locked'),
                                            color: Colors.white,
                                            size: 24,
                                          )
                                        : const Icon(
                                            EvaIcons.mic,
                                            key: ValueKey('mic'),
                                            color: Colors.white,
                                            size: 22,
                                          ),
                              ),
                      ),
                    ),
                  ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              // Иконка замочка сверху над кнопкой микрофона (только при записи и не locked)
              if (_isRecordingVoice && !_voiceLocked)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  right: 20, // Над кнопкой микрофона
                  bottom: 70, // Выше контейнера
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: 1.0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF262626).withOpacity(0.9),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF3A3A3A),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        EvaIcons.lock,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              // Анимация закрепления (замочек летит вниз с эффектом)
              if (_isRecordingVoice && _showLockAnimation)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Positioned(
                  right: 20,
                      bottom: 8 + (1 - value) * 100, // Движение вниз
                      child: Opacity(
                        opacity: 1.0 - value, // Исчезает
                        child: Transform.scale(
                          scale: 1.0 + value * 0.3, // Увеличивается
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.9),
                        shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4CAF50).withOpacity(0.5),
                                  blurRadius: 10 * value,
                                  spreadRadius: 5 * value,
                                ),
                              ],
                        border: Border.all(
                          color: const Color(0xFF4CAF50),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        EvaIcons.lock,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
          ),
        ),
      ),
    );
  }

  // Получает информацию о статусе для группы сообщений
  Map<String, dynamic>? _getGroupStatusInfo(int messageIndex) {
    if (_currentUser == null || messageIndex < 0 || messageIndex >= _messages.length) return null;
    
    final currentMessage = _messages[messageIndex];
    final isOwnMessage = currentMessage.senderId == _currentUser!.id;
    if (!isOwnMessage) return null;
    
    // Находим начало и конец группы
    int groupStart = messageIndex;
    int groupEnd = messageIndex;
    
    // Идем назад, чтобы найти начало группы
    for (int i = messageIndex - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.senderId != currentMessage.senderId) break;
      
      final timeDiff = currentMessage.createdAt.difference(msg.createdAt);
      if (timeDiff.inMinutes > 2) break;
      
      groupStart = i;
    }
    
    // Идем вперед, чтобы найти конец группы
    for (int i = messageIndex + 1; i < _messages.length; i++) {
      final msg = _messages[i];
      if (msg.senderId != currentMessage.senderId) break;
      
      final timeDiff = msg.createdAt.difference(currentMessage.createdAt);
      if (timeDiff.inMinutes > 2) break;
      
      groupEnd = i;
    }
    
    // Находим последнее прочитанное сообщение в группе
    int? lastReadIndex;
    for (int i = groupEnd; i >= groupStart; i--) {
      final msg = _messages[i];
      if (msg.senderId == _currentUser!.id && msg.isRead) {
        lastReadIndex = i;
        break;
      }
    }
    
    // Находим последнее непрочитанное сообщение в группе (после прочитанных)
    int? lastUnreadIndex;
    if (lastReadIndex != null) {
      for (int i = lastReadIndex + 1; i <= groupEnd; i++) {
        final msg = _messages[i];
        if (msg.senderId == _currentUser!.id && !msg.isRead) {
          lastUnreadIndex = i;
        }
      }
    } else {
      // Если нет прочитанных, ищем последнее непрочитанное
      for (int i = groupEnd; i >= groupStart; i--) {
      final msg = _messages[i];
      if (msg.senderId == _currentUser!.id && !msg.isRead) {
        lastUnreadIndex = i;
        break;
      }
    }
    }
    
    // Определяем, какой статус показывать
    bool showStatus = false;
    bool isSending = false;
    bool isRead = false;
    
    // Приоритет 1: Если есть непрочитанные после прочитанных, показываем статус у последнего непрочитанного
    if (lastUnreadIndex != null && lastReadIndex != null && lastUnreadIndex > lastReadIndex) {
      if (messageIndex == lastUnreadIndex) {
        showStatus = true;
        isSending = _messages[lastUnreadIndex].id == _sendingMessageId;
        isRead = false;
      }
    }
    // Приоритет 2: Если есть только прочитанные (или все прочитаны), показываем статус у последнего прочитанного
    else if (lastReadIndex != null && (lastUnreadIndex == null || lastUnreadIndex < lastReadIndex)) {
      if (messageIndex == lastReadIndex) {
        showStatus = true;
        isSending = _messages[lastReadIndex].id == _sendingMessageId;
        isRead = true;
    }
    }
    // Приоритет 3: Если все непрочитанные, показываем статус у последнего в группе
    else if (lastUnreadIndex != null && lastReadIndex == null) {
      if (messageIndex == groupEnd) {
        showStatus = true;
        isSending = _messages[groupEnd].id == _sendingMessageId;
        isRead = false;
      }
    }
    
    return {
      'showStatus': showStatus,
      'isSending': isSending,
      'isRead': isRead,
    };
  }

  bool _shouldShowMessageStatus(int messageIndex) {
    final statusInfo = _getGroupStatusInfo(messageIndex);
    return statusInfo?['showStatus'] ?? false;
  }

  // Определяем позицию сообщения в группе для визуальной группировки
  // Возвращает: 'single', 'first', 'middle', 'last'
  String _getMessagePositionInGroup(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _messages.length) {
      return 'single';
    }
    
    final currentMessage = _messages[messageIndex];
    
    // Проверяем предыдущее сообщение (по времени, не по индексу)
    Message? prevMessage;
    if (messageIndex > 0) {
      prevMessage = _messages[messageIndex - 1];
    }
    
    // Проверяем следующее сообщение (по времени, не по индексу)
    Message? nextMessage;
    if (messageIndex < _messages.length - 1) {
      nextMessage = _messages[messageIndex + 1];
    }
    
    // Проверяем, от того же отправителя ли предыдущее сообщение
    final hasPrevFromSameSender = prevMessage != null && 
                                   prevMessage.senderId == currentMessage.senderId &&
                                   currentMessage.createdAt.difference(prevMessage.createdAt).inMinutes < 2; // В пределах 2 минут
    
    // Проверяем, от того же отправителя ли следующее сообщение
    final hasNextFromSameSender = nextMessage != null && 
                                   nextMessage.senderId == currentMessage.senderId &&
                                   nextMessage.createdAt.difference(currentMessage.createdAt).inMinutes < 2; // В пределах 2 минут
    
    if (hasPrevFromSameSender && hasNextFromSameSender) {
      return 'middle'; // Середина группы
    } else if (hasPrevFromSameSender && !hasNextFromSameSender) {
      return 'last'; // Последнее в группе
    } else if (!hasPrevFromSameSender && hasNextFromSameSender) {
      return 'first'; // Первое в группе
    } else {
      return 'single'; // Одиночное сообщение
    }
  }

  // Возвращает BorderRadius в зависимости от позиции в группе
  BorderRadius _getMessageBorderRadius(bool isOwnMessage, String positionInGroup) {
    const double normalRadius = 24.0;
    const double tightRadius = 6.0;
    
    switch (positionInGroup) {
      case 'single':
        // Одиночное сообщение - все углы скруглены, кроме одного
        return BorderRadius.only(
          topLeft: const Radius.circular(normalRadius),
          topRight: const Radius.circular(normalRadius),
          bottomLeft: Radius.circular(isOwnMessage ? normalRadius : tightRadius),
          bottomRight: Radius.circular(isOwnMessage ? tightRadius : normalRadius),
        );
      
      case 'first':
        // Первое в группе - все углы скруглены, кроме нижнего угла со стороны отправителя
        return BorderRadius.only(
          topLeft: const Radius.circular(normalRadius),
          topRight: const Radius.circular(normalRadius),
          bottomLeft: Radius.circular(isOwnMessage ? normalRadius : tightRadius),
          bottomRight: Radius.circular(isOwnMessage ? tightRadius : normalRadius),
        );
      
      case 'middle':
        // Середина группы - все углы скруглены одинаково, кроме углов со стороны отправителя
        return BorderRadius.only(
          topLeft: Radius.circular(isOwnMessage ? normalRadius : tightRadius),
          topRight: Radius.circular(isOwnMessage ? tightRadius : normalRadius),
          bottomLeft: Radius.circular(isOwnMessage ? normalRadius : tightRadius),
          bottomRight: Radius.circular(isOwnMessage ? tightRadius : normalRadius),
        );
      
      case 'last':
        // Последнее в группе - все углы скруглены, кроме верхнего угла со стороны отправителя
        return BorderRadius.only(
          topLeft: Radius.circular(isOwnMessage ? normalRadius : tightRadius),
          topRight: Radius.circular(isOwnMessage ? tightRadius : normalRadius),
          bottomLeft: const Radius.circular(normalRadius),
          bottomRight: const Radius.circular(normalRadius),
        );
      
      default:
        // Fallback - обычное скругление
        return BorderRadius.only(
          topLeft: const Radius.circular(normalRadius),
          topRight: const Radius.circular(normalRadius),
          bottomLeft: Radius.circular(isOwnMessage ? normalRadius : tightRadius),
          bottomRight: Radius.circular(isOwnMessage ? tightRadius : normalRadius),
        );
    }
  }

  Widget _buildMessageItem(Message message, {required bool showStatus, Key? key}) {
    final isOwnMessage = _currentUser != null && message.senderId == _currentUser!.id;
    
    // Проверяем, удалено ли сообщение
    final isDeleted = message.deletedAt != null;
    
    // Определяем, как отображать удаленное сообщение:
    // - Если сообщение удалено и это моё сообщение - показываем "Вы удалили"
    // - Если сообщение удалено и это не моё сообщение - показываем "Собеседник удалил"
    // isDeletedByOther - сообщение удалено собеседником (не мной), используется для отображения
    final isDeletedByOther = isDeleted && !isOwnMessage;
    
    if (isDeletedByOther) {
      print('🗑️ [ChatScreen] Сообщение ${message.id.substring(0, 8)}... удалено другим пользователем - показываем с текстом');
      print('🗑️ [ChatScreen] deletedAt: ${message.deletedAt}, deletedByIds: ${message.deletedByIds}, isOwnMessage: $isOwnMessage');
    }
    
    // Получаем информацию о статусе для группы
    final messageIndex = _messages.indexWhere((m) => m.id == message.id);
    final statusInfo = messageIndex >= 0 ? _getGroupStatusInfo(messageIndex) : null;
    final isSending = statusInfo?['isSending'] ?? (message.id == _sendingMessageId);
    
    // Получаем или создаем ValueNotifier для смещения этого сообщения
    final offsetNotifier = _messageSwipeOffsets.putIfAbsent(message.id, () => ValueNotifier<double>(0.0));
    
    // Получаем позицию в группе для визуальной группировки
    final positionInGroup = _getMessagePositionInGroup(messageIndex);
    
    // Уменьшаем padding между сообщениями в группе
    final verticalPadding = (positionInGroup == 'middle' || positionInGroup == 'last') ? 2.0 : 4.0;
    
    return Padding(
      key: key ?? ValueKey(message.id), // Используем key для правильного отслеживания
        padding: EdgeInsets.only(left: 16, right: 16, top: verticalPadding, bottom: verticalPadding),
        child: ValueListenableBuilder<double>(
          valueListenable: offsetNotifier,
          builder: (context, currentOffset, child) {
            return Stack(
              children: [
                // Индикатор ответа при свайпе (показывается за сообщением)
                if (currentOffset.abs() > 20)
                  Positioned.fill(
                    child: Align(
                      alignment: isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: isOwnMessage ? 0 : 20,
                          right: isOwnMessage ? 20 : 0,
                        ),
                        child: Opacity(
                          opacity: (currentOffset.abs() / 100.0).clamp(0.0, 1.0),
                          child: const Icon(
                            EvaIcons.cornerDownRight,
                            color: Color(0xFF0095F6),
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  // Отключаем свайп для удаленных сообщений
                  onHorizontalDragUpdate: message.deletedAt == null ? (details) {
                    // Ограничиваем смещение в зависимости от направления
                    double newOffset = currentOffset + details.delta.dx;
                    
                    if (!isOwnMessage) {
                      // Для входящих сообщений - только вправо (положительное значение)
                      newOffset = newOffset.clamp(0.0, 100.0);
                    } else {
                      // Для исходящих сообщений - только влево (отрицательное значение)
                      newOffset = newOffset.clamp(-100.0, 0.0);
                    }
                    
                    // Обновляем через ValueNotifier без setState - это не вызывает полную перерисовку
                    offsetNotifier.value = newOffset;
                  } : null,
                  onHorizontalDragEnd: message.deletedAt == null ? (details) {
                    // Более чувствительный свайп: проверяем и по скорости, и по смещению
                    final velocityThreshold = 15.0; // Уменьшенный порог скорости
                    final offsetThreshold = 40.0; // Порог смещения (если свайпнули достаточно далеко)
                    
                    // Проверяем по скорости (быстрый свайп)
                    final hasFastSwipe = (!isOwnMessage && details.primaryVelocity != null && details.primaryVelocity! > velocityThreshold) ||
                                       (isOwnMessage && details.primaryVelocity != null && details.primaryVelocity! < -velocityThreshold);
                    
                    // Проверяем по смещению (медленный, но длинный свайп)
                    final hasLongSwipe = (!isOwnMessage && currentOffset > offsetThreshold) ||
                                       (isOwnMessage && currentOffset < -offsetThreshold);
                    
                    final shouldReply = hasFastSwipe || hasLongSwipe;
                    
                    if (shouldReply) {
                      // Устанавливаем сообщение для ответа
                      setState(() {
                        _replyingToMessage = message;
                      });
                      // Убираем фокус с поля ввода
                      _messageFocusNode.unfocus();
                      // Плавно возвращаем сообщение обратно через анимацию
                      _animateOffsetToZero(offsetNotifier, currentOffset);
                    } else {
                      // Плавно возвращаем сообщение обратно
                      _animateOffsetToZero(offsetNotifier, currentOffset);
                    }
                  } : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    transform: Matrix4.translationValues(currentOffset, 0, 0),
                    child: Opacity(
                      // Добавляем визуальную обратную связь - небольшое изменение прозрачности при свайпе
                      opacity: currentOffset.abs() > 10 ? 0.85 : 1.0,
        child: Row(
        mainAxisAlignment: isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOwnMessage) ...[
            SafeAvatar(
              imageUrl: message.sender?.avatarUrl,
              radius: 16,
              backgroundColor: const Color(0xFF262626),
              fallbackIcon: EvaIcons.personOutline,
              iconColor: Colors.white,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: _buildMessageWithContextMenu(
              message: message,
              isOwnMessage: isOwnMessage,
              isSending: isSending,
              isDeletedByOther: isDeletedByOther,
                              positionInGroup: _getMessagePositionInGroup(messageIndex),
            ),
          ),
          if (isOwnMessage) const SizedBox(width: 8),
        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
      ),
    );
  }

  // Плавная анимация возврата сообщения в исходное положение
  void _animateOffsetToZero(ValueNotifier<double> offsetNotifier, double currentOffset) {
    if (currentOffset == 0.0) return;
    
    final startTime = DateTime.now().millisecondsSinceEpoch;
    const duration = 300; // миллисекунды
    
    void animate() {
      if (!mounted) return;
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - startTime;
      
      if (elapsed >= duration) {
        if (mounted) {
          offsetNotifier.value = 0.0;
        }
        return;
      }
      
      final progress = elapsed / duration;
      final curveValue = Curves.easeOut.transform(progress);
      final newOffset = currentOffset * (1 - curveValue);
      
      if (mounted) {
        offsetNotifier.value = newOffset;
        Future.delayed(const Duration(milliseconds: 16), animate); // ~60 FPS
      }
    }
    
    animate();
  }

  String _formatMessageTime(DateTime dateTime) {
    // ИСПРАВЛЕНИЕ 2: Конвертируем UTC время с сервера в локальное время пользователя
    final localTime = dateTime.toLocal();
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Копировать текст сообщения в буфер обмена
  Future<void> _copyMessageText(Message message) async {
    if (message.content != null && message.content!.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: message.content!));
      if (mounted) {
        AppNotification.showSuccess(context, 'Message copied', duration: const Duration(seconds: 1));
      }
    }
  }

  // Удалить сообщение
  Future<void> _deleteMessage(Message message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      final updatedMessage = await _apiService.deleteMessage(widget.chat.id, message.id);

      // Обновляем сообщение в списке с данными с сервера
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = updatedMessage;
          }
        });
      }
    } catch (e) {
      print('Error deleting message: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to delete message: $e');
      }
    }
  }

  // Переключить лайк на сообщении
  Future<void> _toggleMessageLike(Message message) async {
    // Убираем фокус с поля ввода при лайке
    _messageFocusNode.unfocus();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      
      // Вызываем API метод для лайка/анлайка сообщения
      final updatedMessage = await _apiService.toggleMessageLike(widget.chat.id, message.id);
      
      // Обновляем сообщение в списке
      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = updatedMessage;
          }
        });
      }
    } catch (e) {
      print('Error toggling message like: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to like message: $e', duration: const Duration(seconds: 1));
      }
    }
  }

  // Выбрать и отправить фото
  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      if (mounted) {
        // Показываем индикатор загрузки
        AppNotification.showLoading(context, 'Loading photo...');
      }

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      // Получаем userId текущего пользователя
      if (_currentUser == null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        _currentUser = authProvider.currentUser;
      }
      if (_currentUser == null) return;
      final userId = _currentUser!.id;

      _apiService.setAccessToken(accessToken);

      // Читаем фото как байты
      final imageFile = File(image.path);
      final imageBytes = await imageFile.readAsBytes();
      final fileExtension = image.path.split('.').last.toLowerCase();
      
      print('ChatScreen: Image file size: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)}MB');

      // Загружаем фото напрямую в Supabase Storage
      String mediaUrl;
      try {
        mediaUrl = await SupabaseStorageService.uploadChatMedia(
          fileBytes: imageBytes,
          userId: userId,
          chatId: widget.chat.id,
          fileExtension: fileExtension,
          accessToken: accessToken,
          mediaType: 'image',
        );
        print('ChatScreen: Image uploaded to Supabase Storage: $mediaUrl');
      } catch (e) {
        print('ChatScreen: Error uploading image to Supabase: $e');
        rethrow;
      }

      // Отправляем сообщение
      final message = await _apiService.sendImageMessage(
        chatId: widget.chat.id,
        mediaUrl: mediaUrl,
      );

      // Сохраняем в кеш
      await _cacheService.addMessage(widget.chat.id, message);

      // Добавляем сообщение в список
      if (mounted) {
        setState(() {
          _messages.add(message);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
      }
    } catch (e) {
      print('Error picking and sending image: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to send photo: $e');
      }
    }
  }

  // Создать thumbnail из видео
  Future<Uint8List?> _generateVideoThumbnail(String videoPath) async {
    try {
      print('ChatScreen: Generating thumbnail from video: $videoPath');
      
      // Получаем длительность видео для выбора случайного кадра
      VideoPlayerController? tempController;
      Duration? videoDuration;
      
      try {
        if (kIsWeb) {
          // Для веб используем blob URL напрямую
          tempController = VideoPlayerController.networkUrl(Uri.parse(videoPath));
        } else {
          // Для мобильных платформ используем файл
          tempController = VideoPlayerController.file(File(videoPath));
        }
        
        await tempController.initialize();
        videoDuration = tempController.value.duration;
        await tempController.dispose();
      } catch (e) {
        print('ChatScreen: Error getting video duration: $e');
        // Если не удалось получить длительность, используем 1 секунду
        videoDuration = const Duration(seconds: 1);
      }

      // Выбираем случайное время (от 10% до 90% длительности, минимум 1 секунда)
      final maxTime = videoDuration.inMilliseconds;
      final minTime = (maxTime * 0.1).round();
      final maxTimeForRandom = (maxTime * 0.9).round();
      final randomTime = minTime + Random().nextInt(maxTimeForRandom - minTime);
      
      print('ChatScreen: Video duration: ${videoDuration.inSeconds}s');
      print('ChatScreen: Random time selected: ${randomTime}ms');

      // Генерируем thumbnail
      String? thumbnailPath;
      
      if (kIsWeb) {
        // Для веб платформы создаем временный файл из blob URL или файла
        try {
          Uint8List videoBytes;
          if (videoPath.startsWith('blob:')) {
            // Загружаем blob URL как байты
            final response = await http.get(Uri.parse(videoPath));
            videoBytes = response.bodyBytes;
          } else {
            // Читаем файл как байты
            final videoFile = File(videoPath);
            videoBytes = await videoFile.readAsBytes();
          }
          
          final tempDir = await getTemporaryDirectory();
          final tempVideoFile = File('${tempDir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
          await tempVideoFile.writeAsBytes(videoBytes);
          
          thumbnailPath = await VideoThumbnail.thumbnailFile(
            video: tempVideoFile.path,
            imageFormat: ImageFormat.JPEG,
            timeMs: randomTime,
            quality: 75,
          );
          
          // Удаляем временный файл
          await tempVideoFile.delete();
        } catch (e) {
          print('ChatScreen: Error processing video for thumbnail on web: $e');
          return null;
        }
      } else {
        // Для мобильных платформ
        thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: randomTime,
          quality: 75,
        );
      }

      if (thumbnailPath == null) {
        print('ChatScreen: Failed to generate thumbnail');
        return null;
      }

      print('ChatScreen: Thumbnail generated at: $thumbnailPath');
      
      // Читаем thumbnail как байты
      final thumbnailFile = File(thumbnailPath);
      final thumbnailBytes = await thumbnailFile.readAsBytes();
      
      // Удаляем временный файл thumbnail
      await thumbnailFile.delete();
      
      print('ChatScreen: Thumbnail size: ${thumbnailBytes.length} bytes');
      return thumbnailBytes;
    } catch (e) {
      print('ChatScreen: Error generating thumbnail: $e');
      return null;
    }
  }

  // Выбрать и отправить видео
  Future<void> _pickAndSendVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video == null) return;

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      // Получаем userId текущего пользователя
      if (_currentUser == null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        _currentUser = authProvider.currentUser;
      }
      if (_currentUser == null) return;
      final userId = _currentUser!.id;

      _apiService.setAccessToken(accessToken);

      // Читаем видео как байты
      final videoFile = File(video.path);
      final videoBytes = await videoFile.readAsBytes();
      final fileSize = videoBytes.length;
      
      print('ChatScreen: Video file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

      // Получаем расширение файла
      final fileExtension = video.path.split('.').last.toLowerCase();
      
      // Получаем длительность видео
      int? duration;
      try {
        final videoController = VideoPlayerController.file(videoFile);
        await videoController.initialize();
        duration = videoController.value.duration.inSeconds;
        await videoController.dispose();
      } catch (e) {
        print('Error getting video duration: $e');
      }

      // Генерируем thumbnail для видео
      Uint8List? thumbnailBytes;
      try {
        thumbnailBytes = await _generateVideoThumbnail(video.path);
      } catch (e) {
        print('Error generating thumbnail: $e');
        // Продолжаем без thumbnail
      }

      // Создаем временное сообщение с thumbnail для отображения прогресса
      final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final tempMessage = Message(
        id: tempMessageId,
        chatId: widget.chat.id,
        senderId: userId,
        messageType: 'video',
        mediaUrl: null, // Будет установлено после загрузки
        thumbnailUrl: null, // Будет установлено после загрузки
        mediaDuration: duration,
        mediaSize: fileSize,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sender: _currentUser,
      );

      // Сохраняем thumbnail локально для временного сообщения
      String? localThumbnailPath;
      if (thumbnailBytes != null) {
        final tempDir = await getTemporaryDirectory();
        localThumbnailPath = '${tempDir.path}/thumb_$tempMessageId.jpg';
        await File(localThumbnailPath).writeAsBytes(thumbnailBytes);
        _localThumbnailPaths[tempMessageId] = localThumbnailPath;
      }

      // Добавляем временное сообщение в список
      if (mounted) {
        setState(() {
          _messages.add(tempMessage);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _sendingMessageId = tempMessageId;
          _uploadProgress[tempMessageId] = 0.0;
        });
        _scrollToBottom();
      }

      // Функция для обновления прогресса
      void updateProgress(double progress) {
        if (mounted && _uploadProgress[tempMessageId] != null) {
          setState(() {
            _uploadProgress[tempMessageId] = progress.clamp(0.0, 1.0);
          });
        }
      }

      // Загружаем видео напрямую в Supabase Storage с отслеживанием прогресса
      String mediaUrl;
      try {
        updateProgress(0.1); // 10% - начало загрузки видео
        mediaUrl = await SupabaseStorageService.uploadChatMedia(
          fileBytes: videoBytes,
          userId: userId,
          chatId: widget.chat.id,
          fileExtension: fileExtension,
          accessToken: accessToken,
          mediaType: 'video',
        );
        updateProgress(0.7); // 70% - видео загружено
        print('ChatScreen: Video uploaded to Supabase Storage: $mediaUrl');
      } catch (e) {
        // Удаляем временное сообщение при ошибке
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.id == tempMessageId);
            _uploadProgress.remove(tempMessageId);
            final thumbnailPathToRemove = _localThumbnailPaths.remove(tempMessageId);
            _sendingMessageId = null;
            
            // Удаляем временный thumbnail файл
            if (thumbnailPathToRemove != null) {
              try {
                File(thumbnailPathToRemove).delete();
              } catch (fileError) {
                print('Error deleting temp thumbnail: $fileError');
              }
            }
          });
        }
        print('ChatScreen: Error uploading video to Supabase: $e');
        rethrow;
      }

      // Загружаем thumbnail если он был сгенерирован
      String? thumbnailUrl;
      if (thumbnailBytes != null) {
        try {
          updateProgress(0.8); // 80% - начало загрузки thumbnail
          thumbnailUrl = await SupabaseStorageService.uploadChatMedia(
            fileBytes: thumbnailBytes,
            userId: userId,
            chatId: widget.chat.id,
            fileExtension: 'jpg',
            accessToken: accessToken,
            mediaType: 'image',
          );
          updateProgress(0.9); // 90% - thumbnail загружен
          print('ChatScreen: Thumbnail uploaded to Supabase Storage: $thumbnailUrl');
        } catch (e) {
          print('ChatScreen: Error uploading thumbnail: $e');
          // Продолжаем без thumbnail
        }
      }

      // Отправляем сообщение
      updateProgress(0.95); // 95% - отправка сообщения
      final message = await _apiService.sendVideoChatMessage(
        chatId: widget.chat.id,
        mediaUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
        duration: duration,
        size: fileSize,
      );

      // Заменяем временное сообщение на реальное
      if (mounted) {
          setState(() {
            final index = _messages.indexWhere((m) => m.id == tempMessageId);
            if (index != -1) {
              _messages[index] = message;
              // Если thumbnailUrl есть, удаляем локальный thumbnail, иначе оставляем его
              if (message.thumbnailUrl != null && message.thumbnailUrl!.isNotEmpty && localThumbnailPath != null) {
                print('ChatScreen: Thumbnail URL received (${message.thumbnailUrl?.substring(0, 20)}...), removing local thumbnail');
                _localThumbnailPaths.remove(tempMessageId);
                // Удаляем временный thumbnail файл только если thumbnailUrl загружен
                File(localThumbnailPath).delete().then((_) {
                  print('ChatScreen: Local thumbnail file deleted');
                }).catchError((e) {
                  print('Error deleting temp thumbnail: $e');
                });
              } else if ((message.thumbnailUrl == null || message.thumbnailUrl!.isEmpty) && localThumbnailPath != null) {
                // Оставляем локальный thumbnail если thumbnailUrl не загружен
                print('ChatScreen: No thumbnail URL received, keeping local thumbnail path for message ${message.id}');
                _localThumbnailPaths[message.id] = localThumbnailPath;
                _localThumbnailPaths.remove(tempMessageId); // Удаляем старый ID
              }
            } else {
              _messages.add(message);
              _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            }
            _uploadProgress.remove(tempMessageId);
            _sendingMessageId = null;
          });
        _scrollToBottom();
      }
    } catch (e) {
      print('Error picking and sending video: $e');
      if (mounted) {
        String errorMessage = 'Failed to send video';
        
        // Показываем более понятное сообщение об ошибке
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('too large') || errorStr.contains('413') || errorStr.contains('entity too large') || errorStr.contains('exceeds maximum')) {
          errorMessage = 'Video is too large. Please select a file smaller than 50MB.';
        } else if (errorStr.contains('network') || errorStr.contains('connection')) {
          errorMessage = 'Network error. Check your internet connection.';
        } else {
          errorMessage = 'Failed to send video: ${e.toString().replaceAll('Exception: ', '')}';
        }
        
        AppNotification.showError(context, errorMessage, duration: const Duration(seconds: 4));
      }
    }
  }

  // Открыть камеру
  Future<void> _openCamera() async {
    try {
      // Используем ImagePicker с камерой для фото
      // Для видео можно использовать CameraScreen, но пока используем ImagePicker
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (photo == null) return;

      // Отправляем фото так же, как из галереи
      await _sendImageFromFile(photo.path);
    } catch (e) {
      print('Error opening camera: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to open camera: $e');
      }
    }
  }

  // Отправить фото из файла (вспомогательный метод)
  Future<void> _sendImageFromFile(String filePath) async {
    try {
      if (mounted) {
        AppNotification.showLoading(context, 'Loading photo...');
      }

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      // Получаем userId текущего пользователя
      if (_currentUser == null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        _currentUser = authProvider.currentUser;
      }
      if (_currentUser == null) return;
      final userId = _currentUser!.id;

      _apiService.setAccessToken(accessToken);

      // Читаем фото как байты
      final imageFile = File(filePath);
      final imageBytes = await imageFile.readAsBytes();
      final fileExtension = filePath.split('.').last.toLowerCase();
      
      print('ChatScreen: Image file size: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)}MB');

      // Загружаем фото напрямую в Supabase Storage
      String mediaUrl;
      try {
        mediaUrl = await SupabaseStorageService.uploadChatMedia(
          fileBytes: imageBytes,
          userId: userId,
          chatId: widget.chat.id,
          fileExtension: fileExtension,
          accessToken: accessToken,
          mediaType: 'image',
        );
        print('ChatScreen: Image uploaded to Supabase Storage: $mediaUrl');
      } catch (e) {
        print('ChatScreen: Error uploading image to Supabase: $e');
        rethrow;
      }

      // Отправляем сообщение
      final message = await _apiService.sendImageMessage(
        chatId: widget.chat.id,
        mediaUrl: mediaUrl,
      );

      // Сохраняем в кеш
      await _cacheService.addMessage(widget.chat.id, message);

      // Добавляем сообщение в список
      if (mounted) {
        setState(() {
          _messages.add(message);
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });
        _scrollToBottom();
      }
    } catch (e) {
      print('Error sending image from file: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to send photo: $e');
      }
    }
  }

  // Редактировать сообщение
  Future<void> _editMessage(Message message) async {
    if (message.content == null || message.content!.isEmpty) return;

    final TextEditingController editController = TextEditingController(text: message.content);
    
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: const Text('Edit message'),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: CupertinoTextField(
              controller: editController,
              placeholder: 'Enter text...',
              maxLines: 5,
              minLines: 1,
              autofocus: true,
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              onPressed: () async {
                final newContent = editController.text.trim();
                if (newContent.isEmpty) {
                  Navigator.pop(context);
                  return;
                }

                Navigator.pop(context);

                try {
                  final prefs = await SharedPreferences.getInstance();
                  final accessToken = prefs.getString('access_token');
                  if (accessToken == null) return;

                  _apiService.setAccessToken(accessToken);
                  
                  // TODO: Реализовать API метод для редактирования сообщения
                  // await _apiService.updateMessage(widget.chat.id, message.id, newContent);
                  
                  // Временно обновляем локально
                  if (mounted) {
                    setState(() {
                      final index = _messages.indexWhere((m) => m.id == message.id);
                      if (index != -1) {
                        // Создаем новый объект Message с обновленным content
                        final oldMessage = _messages[index];
                        _messages[index] = Message(
                          id: oldMessage.id,
                          chatId: oldMessage.chatId,
                          senderId: oldMessage.senderId,
                          content: newContent,
                          messageType: oldMessage.messageType,
                          mediaUrl: oldMessage.mediaUrl,
                          thumbnailUrl: oldMessage.thumbnailUrl,
                          postId: oldMessage.postId,
                          mediaDuration: oldMessage.mediaDuration,
                          mediaSize: oldMessage.mediaSize,
                          isRead: oldMessage.isRead,
                          readAt: oldMessage.readAt,
                          createdAt: oldMessage.createdAt,
                          updatedAt: DateTime.now(),
                          sender: oldMessage.sender,
                        );
                      }
                    });
                  }

                  AppNotification.showSuccess(context, 'Message edited', duration: const Duration(seconds: 1));
                } catch (e) {
                  print('Error editing message: $e');
                  if (mounted) {
                    AppNotification.showError(context, 'Failed to edit message: $e');
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Построить сообщение с контекстным меню
  Widget _buildMessageWithContextMenu({
    required Message message,
    required bool isOwnMessage,
    required bool isSending,
    required bool isDeletedByOther,
    required String positionInGroup,
  }) {
    // Собираем список действий
    final List<CupertinoContextMenuAction> actions = [];
    
    // Copy (for all text messages)
    if (message.messageType == 'text' && message.content != null && message.content!.isNotEmpty) {
      actions.add(
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _copyMessageText(message);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                EvaIcons.copy,
                size: 20,
                color: CupertinoColors.label.resolveFrom(context),
              ),
              const SizedBox(width: 12),
              DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.0,
                ),
                child: const Text('Copy'),
              ),
            ],
          ),
        ),
      );
    }
    
    // Edit (only for own text messages)
    if (isOwnMessage && message.messageType == 'text' && message.content != null && message.content!.isNotEmpty) {
      actions.add(
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _editMessage(message);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                EvaIcons.editOutline,
                size: 20,
                color: CupertinoColors.label.resolveFrom(context),
              ),
              const SizedBox(width: 12),
              DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.0,
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
        ),
      );
    }
    
    // Reply (для всех сообщений, кроме удаленных)
    final isDeleted = message.deletedAt != null;
    if (!isDeleted) {
      actions.add(
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            setState(() {
              _replyingToMessage = message;
            });
            // Убираем фокус с поля ввода
            _messageFocusNode.unfocus();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                EvaIcons.cornerDownRight,
                size: 20,
                color: CupertinoColors.label.resolveFrom(context),
              ),
              const SizedBox(width: 12),
              DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.0,
                ),
                child: const Text('Reply'),
              ),
            ],
          ),
        ),
      );
    }
    
    // Delete (only for own messages) - для всех типов сообщений включая голосовые, но не для удаленных
    if (isOwnMessage && !isDeleted) {
      actions.add(
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _deleteMessage(message);
          },
          isDestructiveAction: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                EvaIcons.trash2Outline,
                size: 20,
                color: CupertinoColors.destructiveRed.resolveFrom(context),
              ),
              const SizedBox(width: 12),
              DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.0,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      );
    }
    
    final messageContent = _buildMessageContent(message, isOwnMessage, isSending, isDeletedByOther, positionInGroup);
    
    // Если есть действия, оборачиваем в CupertinoContextMenu, иначе просто возвращаем контент
    // Для удаленных сообщений не показываем контекстное меню
    if (actions.isEmpty || isDeleted) {
      if (isDeleted) {
        // Для удаленных сообщений не добавляем обработчик двойного тапа и контекстное меню
        return messageContent;
      }
      return GestureDetector(
        onDoubleTap: () {
          _toggleMessageLike(message);
        },
        child: messageContent,
      );
    }
    
    // Для сообщений с действиями (контекстное меню)
    if (isDeleted) {
      // Для удаленных сообщений не добавляем обработчик двойного тапа
      return CupertinoContextMenu(
        actions: actions,
        child: messageContent,
      );
    }
    
    return GestureDetector(
      onDoubleTap: () {
        _toggleMessageLike(message);
      },
      child: CupertinoContextMenu(
        actions: actions,
        child: messageContent,
      ),
    );
  }

  // Построить изображение сообщения
  Widget _buildImageMessage(Message message) {
    // БАГ FIX: Определяем, нужно ли загружать полное изображение (последние 30 сообщений)
    // Для старых сообщений показываем только placeholder или уменьшенную версию
    final messageIndex = _messages.indexWhere((m) => m.id == message.id);
    final shouldLoadNow = messageIndex >= _messages.length - 30;
    // Если сообщение было разблокировано пользователем, загружаем его
    final isUnlocked = _unlockedMessages.contains(message.id);
    final isOldMessage = !shouldLoadNow && !isUnlocked;
    
    // Контейнер с изображением
    final imageWidget = GestureDetector(
      onTap: message.mediaUrl != null
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => FullScreenImageViewer(
                    imageUrl: message.mediaUrl!,
                    chatId: widget.chat.id,
                    postId: null,
                  ),
                ),
              );
            }
          : null,
      child: Container(
        // ВАЖНО: Квадратные фиксированные размеры для резервирования места
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black, // Фон для резервирования места
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: message.mediaUrl != null
              ? (isOldMessage
                  // БАГ FIX: Для старых сообщений показываем только placeholder с иконкой (не загружаем полное изображение)
                  ? GestureDetector(
                      onTap: () {
                        // При нажатии загружаем полное изображение
                        if (mounted) {
                          setState(() {
                            // Добавляем сообщение в список разблокированных
                            _unlockedMessages.add(message.id);
                          });
                        }
                      },
                      child: Container(
                        width: 250,
                        height: 250,
                        color: const Color(0xFF262626),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              EvaIcons.imageOutline,
                              color: Colors.white54,
                              size: 48,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to load',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : CachedNetworkImageWithSignedUrl(
                  imageUrl: message.mediaUrl!,
                  chatId: widget.chat.id,
                  postId: null,
                  fit: BoxFit.cover, // Заполняем квадрат и обрезаем лишнее
                  width: 250,
                  height: 250,
                  placeholder: (context) => Container(
                    width: 250,
                    height: 250,
                    color: const Color(0xFF262626),
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) {
                        // БАГ FIX 6: Добавляем retry кнопку для загрузки изображений
                    return Container(
                      width: 250,
                      height: 250,
                      color: const Color(0xFF262626),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                        EvaIcons.imageOutline,
                                color: Colors.white54,
                        size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Failed to load',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  // Перезагружаем виджет для retry
                                  if (mounted) {
                                    setState(() {});
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0095F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Retry',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                      ),
                    );
                  },
                    ))
              : Container(
                  width: 250,
                  height: 250,
                  color: const Color(0xFF262626),
                  child: const Icon(
                    EvaIcons.imageOutline,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
        ),
      ),
    );
    
    // Для последних 30 сообщений или разблокированных рендерим напрямую без LazyMediaLoader
    if (shouldLoadNow || isUnlocked) {
      return imageWidget;
    }
    
    // Для остальных используем LazyMediaLoader
    // БАГ FIX: Передаем размеры чтобы placeholder не был сплюснутым
    return LazyMediaLoader(
      preloadDistance: 1000,
      width: 250,
      height: 250,
      onVisible: () {
        // При появлении в viewport разблокируем сообщение
        if (mounted && !_unlockedMessages.contains(message.id)) {
          setState(() {
            _unlockedMessages.add(message.id);
          });
        }
      },
      child: imageWidget,
    );
  }

  // БАГ FIX 1: Построить shared post сообщение (видео пост из Shorts) - улучшенный дизайн
  Widget _buildSharedPostMessage(Message message) {
    return GestureDetector(
      onTap: () {
        if (message.postId != null) {
          _openShortsWithPost(message.postId!);
        }
      },
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF3A3A3A).withOpacity(0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Превью поста (видео/фото) - более красивое
            if (message.thumbnailUrl != null && message.thumbnailUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImageWithSignedUrl(
                        imageUrl: message.thumbnailUrl!,
                        postId: message.postId,
                        fit: BoxFit.cover,
                        placeholder: (context) => Container(
                          color: const Color(0xFF1C1C1C),
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFF1C1C1C),
                          child: const Icon(
                            EvaIcons.videoOutline,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      // Красивый градиентный overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.4),
                            ],
                          ),
                        ),
                      ),
                      // Иконка воспроизведения с эффектом
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              EvaIcons.playCircleOutline,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Информация о посте - улучшенный дизайн
            Container(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок с иконкой
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0095F6).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          EvaIcons.videoOutline,
                          size: 14,
                          color: Color(0xFF0095F6),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Shared Post',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Кнопка просмотра - более красивая
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0095F6),
                          Color(0xFF0085E6),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0095F6).withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          EvaIcons.playCircleOutline,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'View Post',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Построить видео сообщение
  Widget _buildVideoMessage(Message message) {
    final uploadProgress = _uploadProgress[message.id];
    final isUploading = uploadProgress != null && uploadProgress < 1.0;
    final localThumbnailPath = _localThumbnailPaths[message.id];
    
    // БАГ FIX: Определяем, нужно ли загружать полное видео (последние 30 сообщений)
    // Для старых сообщений показываем только thumbnail (не загружаем полное видео)
    final messageIndex = _messages.indexWhere((m) => m.id == message.id);
    final shouldLoadNow = messageIndex >= _messages.length - 30;
    // Если сообщение было разблокировано пользователем, загружаем его
    final isUnlocked = _unlockedMessages.contains(message.id);
    
    // Создаем виджет видео
    final videoWidget = GestureDetector(
      onTap: isUploading ? null : () {
        if (message.postId != null) {
          _openShortsWithPost(message.postId!);
        } else if (message.mediaUrl != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FullScreenVideoViewer(
                videoUrl: message.mediaUrl!,
                chatId: widget.chat.id,
                postId: null,
                thumbnailUrl: message.thumbnailUrl,
              ),
            ),
          );
        }
      },
      child: Container(
        width: 150,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: localThumbnailPath != null
                  ? Image.file(
                      File(localThumbnailPath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        print('ChatScreen: Error loading local thumbnail: $error');
                        return Container(
                          color: const Color(0xFF262626),
                          child: const Icon(
                            EvaIcons.videoOutline,
                            color: Colors.white,
                            size: 32,
                          ),
                        );
                      },
                    )
                  : (message.thumbnailUrl != null && message.thumbnailUrl!.isNotEmpty)
                      ? CachedNetworkImageWithSignedUrl(
                          imageUrl: message.thumbnailUrl!,
                          chatId: widget.chat.id,
                          postId: message.postId,
                          fit: BoxFit.cover,
                          width: 150, // Фиксированные размеры для резервирования места
                          height: 200,
                          placeholder: (context) => Container(
                            width: 150,
                            height: 200,
                            color: const Color(0xFF262626),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) {
                            print('ChatScreen: Error loading thumbnail from URL: $url, error: $error');
                            return Container(
                              width: 150,
                              height: 200,
                              color: const Color(0xFF262626),
                              child: const Icon(
                                EvaIcons.videoOutline,
                                color: Colors.white,
                                size: 32,
                              ),
                            );
                          },
                        )
                      : Container(
                          width: 150,
                          height: 200,
                          color: const Color(0xFF262626),
                          child: const Icon(
                            EvaIcons.videoOutline,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
            ),
            if (!isUploading)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withOpacity(0.3),
                ),
                child: const Center(
                  child: Icon(
                    EvaIcons.playCircleOutline,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            if (isUploading)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withOpacity(0.6),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          value: uploadProgress,
                          strokeWidth: 4,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${(uploadProgress * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    
    // Для последних 30 сообщений или разблокированных рендерим напрямую без LazyMediaLoader
    if (shouldLoadNow || isUnlocked) {
      return videoWidget;
    }
    
    // Для остальных используем LazyMediaLoader
    // БАГ FIX: Передаем размеры чтобы placeholder не был сплюснутым
    return LazyMediaLoader(
      preloadDistance: 1000,
      width: 150,
      height: 200,
      onVisible: () {
        // При появлении в viewport разблокируем сообщение
        if (mounted && !_unlockedMessages.contains(message.id)) {
          setState(() {
            _unlockedMessages.add(message.id);
          });
        }
      },
      child: videoWidget,
    );
  }

  // Построить содержимое сообщения (без контекстного меню, используется внутри)
  Widget _buildMessageContent(Message message, bool isOwnMessage, bool isSending, bool isDeletedByOther, String positionInGroup) {
    // Если сообщение удалено, показываем специальный текст
    final isDeleted = message.deletedAt != null;
    
    if (isDeleted) {
      // БАГ FIX 5: Показываем иконку типа удаленного сообщения
      IconData messageIcon;
      switch (message.messageType) {
        case 'image':
          messageIcon = EvaIcons.imageOutline;
          break;
        case 'video':
          messageIcon = EvaIcons.videoOutline;
          break;
        case 'voice':
          messageIcon = EvaIcons.mic;
          break;
        default:
          messageIcon = EvaIcons.messageCircleOutline;
      }
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: _getMessageBorderRadius(isOwnMessage, positionInGroup),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              messageIcon,
              size: 14,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(width: 6),
            Text(
              isOwnMessage ? 'You deleted this message' : 'Your interlocutor deleted this message',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
              crossAxisAlignment: isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // ВАЖНО: используем min вместо max
              children: [
            // Индикатор ответа на сообщение (не показываем для удаленных сообщений)
            if (message.replyToId != null && message.deletedAt == null) ...[
              // Отладочное логирование
              Builder(
                builder: (context) {
                  if (message.replyTo == null) {
                    print('ChatScreen: Message ${message.id.substring(0, 8)}... has replyToId ${message.replyToId?.substring(0, 8)} but replyTo is null');
                  }
                  return const SizedBox.shrink();
                },
              ),
              GestureDetector(
                onTap: () {
                  _scrollToMessage(message.replyToId!);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      constraints: const BoxConstraints(
                        maxWidth: 200, // Ограничиваем максимальную ширину
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              EvaIcons.cornerDownRight,
                              size: 14,
                              color: Color(0xFF0095F6),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: message.replyTo != null
                                  ? message.replyTo!.deletedAt != null
                                      ? const Text(
                                          'Deleted message',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 9,
                                            fontStyle: FontStyle.italic,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : RichText(
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: message.replyTo!.sender?.username ?? 'User',
                                                style: const TextStyle(
                                                  color: Color(0xFF0095F6),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              TextSpan(
                                                text: ' ${message.replyTo!.content ?? 
                                                  (message.replyTo!.messageType == 'image' ? 'Photo' :
                                                   message.replyTo!.messageType == 'video' ? 'Video' :
                                                   message.replyTo!.messageType == 'voice' ? 'Voice message' : 'Message')}',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.7),
                                                  fontSize: 9,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                  : const Text(
                                      'Reply to message',
                                      style: TextStyle(
                                        color: Color(0xFF0095F6),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            // БАГ FIX 1: Для shared posts (видео с postId)
            if (message.messageType == 'video' && message.postId != null)
              _buildSharedPostMessage(message),
            // Для фото сообщений
            if (message.messageType == 'image')
              _buildImageMessage(message),
            // Для видео сообщений (обычные видео без postId)
            if (message.messageType == 'video' && message.postId == null)
              _buildVideoMessage(message),
            // Для остальных типов сообщений (текст, голос)
            if (message.messageType != 'image' && message.messageType != 'video')
                // ВАЖНО: Ограничиваем ширину контейнера, чтобы избежать проблем с constraints в CupertinoContextMenu
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75, // Максимум 75% ширины экрана
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: message.messageType == 'voice'
                          ? (isOwnMessage ? const Color(0xFF0095F6) : const Color(0xFF262626))
                          : (isOwnMessage ? const Color(0xFF0095F6) : const Color(0xFF262626)),
                      borderRadius: _getMessageBorderRadius(isOwnMessage, positionInGroup),
                    ),
                    child: Builder(
                      builder: (context) {
                        if (message.messageType == 'voice') {
                          return VoiceMessagePlayer(
                            mediaPath: message.mediaUrl,
                            chatId: widget.chat.id,
                            duration: message.mediaDuration ?? 0,
                            isOwnMessage: isOwnMessage,
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Текст сообщения
                              DefaultTextStyle(
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.2,
                                ),
                                child: Text(
                                  message.content ?? '',
                                  softWrap: true,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Время отправки
                              DefaultTextStyle(
                                style: TextStyle(
                                  color: isOwnMessage
                                      ? Colors.white70
                                      : const Color(0xFF8E8E8E),
                                  fontSize: 11,
                                  height: 1.0,
                                ),
                                child: Text(
                                  _formatMessageTime(message.createdAt),
                                ),
                              ),
                            ],
                          );
                        }
                      },
                    ),
                  ),
                ),
            // Время отправки для голосовых, видео и фото сообщений - под bubble
            if (message.messageType == 'voice' || message.messageType == 'video' || message.messageType == 'image') ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: EdgeInsets.only(
                      right: isOwnMessage ? 4 : 0,
                      left: isOwnMessage ? 0 : 4,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75, // Ограничиваем ширину
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSending) ...[
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          DefaultTextStyle(
                            style: TextStyle(
                              color: isOwnMessage
                                  ? Colors.white70
                                  : const Color(0xFF8E8E8E),
                              fontSize: 11,
                              height: 1.0,
                            ),
                            child: Text(
                              _formatMessageTime(message.createdAt),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
            // Статус сообщения (отправка/отправлено/прочитано) - под сообщением
            // Используем отдельный виджет для статуса, чтобы обновлялся только он
            // Показываем статус только если это последнее сообщение в группе
            Builder(
              builder: (context) {
                final messageIndex = _messages.indexWhere((m) => m.id == message.id);
                final statusInfo = messageIndex >= 0 ? _getGroupStatusInfo(messageIndex) : null;
                final actualShowStatus = statusInfo?['showStatus'] ?? false;
                final statusIsRead = statusInfo?['isRead'] ?? message.isRead;
                
                // Показываем статус для всех типов сообщений кроме видео
                if (isOwnMessage && actualShowStatus && message.messageType != 'video') {
                  return _MessageStatusWidget(
                    messageId: message.id,
                    isSending: isSending,
                    isRead: statusIsRead,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        // Иконка лайка - слева для исходящих, справа для входящих
        Positioned(
          left: isOwnMessage ? -32 : null,
          right: isOwnMessage ? null : -32,
          top: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(
                scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.elasticOut,
                  ),
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            child: message.isLiked
                ? const Icon(
                    EvaIcons.heart,
                    key: ValueKey('liked'),
                    color: Colors.red,
                    size: 24,
                  )
                : const SizedBox.shrink(key: ValueKey('not_liked')),
                    ),
                  ),
              ],
    );
  }

  // Открыть Shorts с конкретным постом
  Future<void> _openShortsWithPost(String postId) async {
    try {
      // Получаем пост из провайдера
      final postsProvider = Provider.of<PostsProvider>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      // Ищем пост в загруженных постах
      Post? targetPost;
      final allPosts = [...postsProvider.feedPosts, ...postsProvider.videoPosts];
      try {
        targetPost = allPosts.firstWhere(
          (post) => post.id == postId,
        );
      } catch (e) {
        // Пост не найден, загружаем видео посты
        if (accessToken != null) {
          await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);
          final allPostsAfter = [...postsProvider.feedPosts, ...postsProvider.videoPosts];
          try {
            targetPost = allPostsAfter.firstWhere(
              (post) => post.id == postId,
    );
          } catch (e2) {
            // Если пост все еще не найден, создаем временный пост из данных сообщения
            print('ChatScreen: Post not found in provider, creating temporary post');
            // Попробуем найти сообщение с этим postId
            final message = _messages.firstWhere(
              (msg) => msg.postId == postId,
              orElse: () => throw Exception('Message not found'),
            );
            
            // Создаем временный пост из данных сообщения
            targetPost = Post(
              id: postId,
              userId: message.senderId,
              caption: '',
              mediaUrl: message.mediaUrl ?? '',
              mediaType: 'video',
              thumbnailUrl: message.thumbnailUrl,
              createdAt: message.createdAt,
              updatedAt: message.createdAt,
              likesCount: 0,
              commentsCount: 0,
              mentions: [],
              hashtags: [],
              isLiked: false,
              isSaved: false,
    );
  }
        } else {
          throw Exception('Post not found and no access token');
        }
      }
      
      // Переключаемся на Shorts в MainScreen
      if (mounted) {
        // Используем глобальный ключ для доступа к MainScreenState
        final mainScreenState = MainScreen.globalKey.currentState;
        
        if (mainScreenState != null) {
          print('ChatScreen: Opening Shorts with post ${targetPost.id}');
          
          // Сначала переключаемся на Shorts в MainScreen
          mainScreenState.switchToShortsWithPost(targetPost);
          
          // Ждем немного, чтобы переключение произошло
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Закрываем ChatScreen
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          
          // Ждем закрытия ChatScreen
          await Future.delayed(const Duration(milliseconds: 200));
          
          // Если ChatsListScreen открыт поверх MainScreen, закрываем его тоже
          // Используем rootNavigator для проверки и закрытия
          final rootNavigator = Navigator.of(context, rootNavigator: true);
          
          // Закрываем ChatsListScreen если он открыт (но не MainScreen)
          // Проверяем, что можем закрыть еще один экран (ChatsListScreen)
          if (rootNavigator.canPop()) {
            // Проверяем, что следующий экран не MainScreen
            // Если это не MainScreen, закрываем его
            rootNavigator.pop();
            print('ChatScreen: Closed ChatsListScreen, Shorts should now be visible');
          }
        } else {
          print('ChatScreen: MainScreenState not found, closing ChatScreen normally');
          // Если MainScreenState не найден, просто закрываем ChatScreen
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      }
    } catch (e) {
      print('ChatScreen: Error opening Shorts with post: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to open video: $e');
      }
    }
  }

  // Показать меню для прикрепления файлов (Cupertino стиль с блюром)
  void _showAttachmentMenu(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);
    
    showCupertinoModalPopup(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (BuildContext context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Stack(
          children: [
            Positioned(
              left: 16,
              bottom: MediaQuery.of(context).size.height - buttonPosition.dy + 8,
              child: Container(
                width: 200, // Ограничиваем ширину
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey6.darkColor.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Photo
                          CupertinoContextMenuAction(
                            onPressed: () {
                              Navigator.pop(context);
                              _pickAndSendImage();
                            },
                            child: Row(
                              children: [
                                Icon(
                                  EvaIcons.image,
                                  size: 20,
                                  color: CupertinoColors.label.resolveFrom(context),
                                ),
                                const SizedBox(width: 12),
                                const Text('Photo'),
                              ],
                            ),
                          ),
                          // Video
                          CupertinoContextMenuAction(
                            onPressed: () {
                              Navigator.pop(context);
                              _pickAndSendVideo();
                            },
                            child: Row(
                              children: [
                                Icon(
                                  EvaIcons.video,
                                  size: 20,
                                  color: CupertinoColors.label.resolveFrom(context),
                                ),
                                const SizedBox(width: 12),
                                const Text('Video'),
                              ],
                            ),
                          ),
                          // Sticker
                          CupertinoContextMenuAction(
                            onPressed: () {
                              Navigator.pop(context);
                              // TODO: Implement sticker picker
                              AppNotification.showInfo(context, 'Sticker picker coming soon!');
                            },
                            child: Row(
                              children: [
                                Icon(
                                  EvaIcons.heart,
                                  size: 20,
                                  color: CupertinoColors.label.resolveFrom(context),
                                ),
                                const SizedBox(width: 12),
                                const Text('Sticker'),
                              ],
                            ),
                          ),
                          // Camera
                          CupertinoContextMenuAction(
                            onPressed: () {
                              Navigator.pop(context);
                              _openCamera();
                            },
                            child: Row(
                              children: [
                                Icon(
                                  EvaIcons.camera,
                                  size: 20,
                                  color: CupertinoColors.label.resolveFrom(context),
                                ),
                                const SizedBox(width: 12),
                                const Text('Camera'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Виджет для анимированной кнопки Stop/Cancel
class _AnimatedStopCancelButton extends StatefulWidget {
  final bool isStopped;
  final VoidCallback onTap;

  const _AnimatedStopCancelButton({
    required this.isStopped,
    required this.onTap,
  });

  @override
  State<_AnimatedStopCancelButton> createState() => _AnimatedStopCancelButtonState();
}

class _AnimatedStopCancelButtonState extends State<_AnimatedStopCancelButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.only(right: 8),
              height: 36, // Фиксированная высота для центрирования
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: widget.isStopped
                    ? Colors.redAccent.withOpacity(0.8)
                    : Colors.orange.withOpacity(0.8),
                borderRadius: BorderRadius.circular(18),
                boxShadow: _isPressed
                    ? [
                        BoxShadow(
                          color: (widget.isStopped ? Colors.redAccent : Colors.orange)
                              .withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOut),
                      ),
                      child: child,
                    ),
                  );
                },
                child: Row(
                  key: ValueKey(widget.isStopped ? 'cancel' : 'stop'),
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.isStopped ? EvaIcons.closeCircle : EvaIcons.stopCircle,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.isStopped ? 'Cancel' : 'Stop',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Кнопка воспроизведения превью голосового сообщения
class _PlayPreviewButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPreviewButton({
    super.key,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  State<_PlayPreviewButton> createState() => _PlayPreviewButtonState();
}

class _PlayPreviewButtonState extends State<_PlayPreviewButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0095F6).withOpacity(0.8),
                shape: BoxShape.circle,
                boxShadow: _isPressed
                    ? [
                        BoxShadow(
                          color: const Color(0xFF0095F6).withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOut),
                      ),
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  widget.isPlaying ? EvaIcons.pauseCircle : EvaIcons.playCircle,
                  key: ValueKey(widget.isPlaying ? 'pause' : 'play'),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Отдельный виджет для статуса сообщения, чтобы обновлялся только он
class _MessageStatusWidget extends StatefulWidget {
  final String messageId;
  final bool isSending;
  final bool isRead;

  const _MessageStatusWidget({
    required this.messageId,
    required this.isSending,
    required this.isRead,
  });

  @override
  State<_MessageStatusWidget> createState() => _MessageStatusWidgetState();
}

class _MessageStatusWidgetState extends State<_MessageStatusWidget> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 4),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Color(0xFF8E8E8E),
          fontSize: 10,
          height: 1.0,
        ),
        child: Text(
          widget.isSending 
              ? 'Sending' 
              : (widget.isRead ? 'Read' : 'Sent'),
          key: ValueKey('${widget.isSending}_${widget.isRead}'), // Key для правильного обновления
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(_MessageStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Обновляем только если изменился статус
    if (oldWidget.isSending != widget.isSending || 
        oldWidget.isRead != widget.isRead) {
      // Принудительно обновляем только этот виджет
      setState(() {});
    }
  }
}

