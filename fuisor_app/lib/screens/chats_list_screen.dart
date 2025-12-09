import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:pretty_animated_text/pretty_animated_text.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../models/chat.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/message_cache_service.dart';
import '../widgets/safe_avatar.dart';
import '../providers/auth_provider.dart';
import '../providers/online_status_provider.dart';
import '../widgets/app_notification.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<Chat> _allChats = []; // Все чаты (включая архивированные) - для кеша
  List<Chat> _chats = []; // Текущие чаты (отфильтрованные по режиму архива)
  List<Chat> _filteredChats = [];
  List<User> _storyUsers = []; // Пользователи для сторисов
  bool _isLoading = true;
  bool _showArchived = false; // Показывать архивированные чаты
  final Map<String, Map<String, dynamic>> _userStatuses = {}; // Кэш статусов
  
  // Ключи для кэширования
  static const String _cachedChatsKey = 'cached_chats';
  static const String _cachedChatsTimestampKey = 'cached_chats_timestamp';
  
  // Timer для debounce поиска
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadCachedChatsFirst(); // Сначала загружаем из кэша
    _loadChats(); // Затем обновляем с API
  }

  Future<void> _loadUserStatuses() async {
    try {
      debugPrint('ChatsListScreen: Loading user statuses for ${_chats.length} chats');
      
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        debugPrint('ChatsListScreen: No access token found');
        return;
      }

      final onlineStatusProvider = context.read<OnlineStatusProvider>();
      
      // Сначала проверяем кэш, затем загружаем только отсутствующие статусы параллельно
      final Map<String, Map<String, dynamic>> newStatuses = {};
      final List<Future<void>> loadFutures = [];
      
      for (final chat in _chats) {
        if (chat.otherUser != null) {
          final userId = chat.otherUser!.id;
          
          // Проверяем кэш провайдера
          final cachedStatus = onlineStatusProvider.getCachedStatus(userId);
          if (cachedStatus != null) {
            // Используем закэшированный статус
            newStatuses[userId] = cachedStatus;
            debugPrint('ChatsListScreen: Using cached status for ${chat.otherUser!.username}');
          } else {
            // Загружаем отсутствующий статус параллельно
            loadFutures.add(
              onlineStatusProvider.getUserStatus(userId, accessToken)
                .then((status) {
                  newStatuses[userId] = status;
                  debugPrint('ChatsListScreen: Loaded status for ${chat.otherUser!.username}: ${status['status_text']}');
                })
                .catchError((e) {
                  debugPrint('ChatsListScreen: Error loading status for $userId: $e');
                  // Используем fallback статус при ошибке
                  newStatuses[userId] = {
                    'is_online': false,
                    'status_text': 'long ago',
                  };
                })
            );
          }
        }
      }
      
      // Параллельная загрузка всех отсутствующих статусов
      if (loadFutures.isNotEmpty) {
        await Future.wait(loadFutures);
      }
      
      if (mounted) {
        setState(() {
          _userStatuses.addAll(newStatuses);
        });
      }
      
      debugPrint('ChatsListScreen: Loaded ${newStatuses.length} statuses (${newStatuses.length - loadFutures.length} from cache, ${loadFutures.length} from API)');
    } catch (e) {
      debugPrint('ChatsListScreen: Error loading user statuses: $e');
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Отменяем предыдущий таймер
    _searchDebounceTimer?.cancel();
    
    // Создаем новый таймер с задержкой 400ms
    _searchDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      _filterChats();
    });
  }
  
  // Сохранение чатов в кэш
  Future<void> _saveChatsToCache(List<Chat> chats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatsJson = chats.map((chat) => chat.toJson()).toList();
      await prefs.setString(_cachedChatsKey, jsonEncode(chatsJson));
      await prefs.setInt(_cachedChatsTimestampKey, DateTime.now().millisecondsSinceEpoch);
      debugPrint('ChatsListScreen: Saved ${chats.length} chats to cache');
    } catch (e) {
      debugPrint('ChatsListScreen: Error saving chats to cache: $e');
    }
  }

  // Загрузка чатов из кэша
  Future<List<Chat>> _loadChatsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedChatsJson = prefs.getString(_cachedChatsKey);
      
      if (cachedChatsJson == null) {
        return [];
      }
      
      // Проверяем, не устарел ли кэш (не старше 1 часа)
      final timestamp = prefs.getInt(_cachedChatsTimestampKey);
      if (timestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        const oneHour = 60 * 60 * 1000; // 1 час в миллисекундах
        if (cacheAge > oneHour) {
          debugPrint('ChatsListScreen: Cache is too old, ignoring');
          return [];
        }
      }
      
      final List<dynamic> chatsData = jsonDecode(cachedChatsJson);
      final cachedChats = chatsData.map((json) => Chat.fromJson(json)).toList();
      debugPrint('ChatsListScreen: Loaded ${cachedChats.length} chats from cache');
      return cachedChats;
    } catch (e) {
      debugPrint('ChatsListScreen: Error loading chats from cache: $e');
      return [];
    }
  }
  
  // Сортировка чатов: закрепленные сверху, затем непрочитанные, затем по дате обновления
  void _sortChats() {
    _chats.sort((a, b) {
      // Сначала закрепленные
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      // Затем непрочитанные
      if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
      if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
      // Затем по дате обновления (новые сверху)
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  // Загрузка кэшированных чатов при инициализации
  Future<void> _loadCachedChatsFirst() async {
    final cachedChats = await _loadChatsFromCache();
    if (cachedChats.isNotEmpty && mounted) {
      // Сохраняем все чаты в _allChats
      _allChats = cachedChats;
      
      // Фильтруем кэшированные чаты по режиму архива
      _updateChatsFromAll();
      
      // Для Stories всегда используем все неархивированные чаты из кэша
      final allNonArchivedChats = cachedChats
          .where((chat) => !chat.isArchived)
          .toList();
      
      // Показываем данные даже если список чатов пустой (для Stories)
      setState(() {
        _sortChats(); // Сортируем кэшированные чаты
        _filteredChats = List.from(_chats);
        // Собираем пользователей для сторисов из всех неархивированных чатов
        _storyUsers = allNonArchivedChats
            .where((chat) => chat.isDirect && chat.otherUser != null)
            .map((chat) => chat.otherUser!)
            .toList();
        _isLoading = false; // Показываем кэшированные данные сразу
      });
      
      // Загружаем статусы для кэшированных чатов (если есть чаты)
      if (_chats.isNotEmpty) {
        _loadUserStatuses();
        // Синхронизируем сообщения в фоне
        _syncMessagesInBackground();
      }
    }
  }

  // Синхронизация сообщений для всех чатов в фоне
  Future<void> _syncMessagesInBackground() async {
    try {
      final cacheService = MessageCacheService();
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) return;
      
      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      
      // Синхронизируем для каждого чата (только последние сообщения)
      for (final chat in _allChats) {
        try {
          // Получаем метаданные кеша
          final metadata = await cacheService.getCacheMetadata(chat.id);
          
          // Если кеш свежий (менее 5 минут), пропускаем
          if (metadata != null) {
            final age = DateTime.now().difference(metadata.lastSyncTimestamp);
            if (age.inMinutes < 5) {
              continue; // Кеш свежий, пропускаем
            }
          }
          
          // Загружаем последние сообщения
          final result = await apiService.getMessages(chat.id, page: 1, limit: 15);
          final messages = result['messages'] as List<Message>;
          
          if (messages.isNotEmpty) {
            // Сохраняем в кеш
            await cacheService.saveMessages(chat.id, messages);
            print('ChatsListScreen: Synced ${messages.length} messages for chat ${chat.id.substring(0, 8)}...');
          }
        } catch (e) {
          print('ChatsListScreen: Error syncing messages for chat ${chat.id}: $e');
          // Продолжаем синхронизацию других чатов
        }
      }
      
      print('ChatsListScreen: Background sync completed');
    } catch (e) {
      print('ChatsListScreen: Error in background sync: $e');
    }
  }

  // Обновление _chats из _allChats на основе _showArchived
  void _updateChatsFromAll() {
    _chats = _allChats
        .where((chat) => _showArchived ? chat.isArchived : !chat.isArchived)
        .toList();
    _sortChats();
  }

  void _filterChats() {
    final query = _searchController.text.toLowerCase().trim();
    
    if (query.isEmpty) {
      setState(() {
        _filteredChats = _chats;
      });
      return;
    }

    setState(() {
      _filteredChats = _chats.where((chat) {
        if (chat.isDirect && chat.otherUser != null) {
          final otherUser = chat.otherUser!;
          final name = otherUser.name.toLowerCase();
          final username = otherUser.username.toLowerCase();
          return name.contains(query) || username.contains(query);
        }
        return false;
      }).toList();
    });
  }

  Future<void> _loadChats({bool refresh = false}) async {
    if (refresh) {
      // При обновлении не показываем loading для всего экрана
    } else {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      _apiService.setAccessToken(accessToken);
      
      // Всегда загружаем все чаты (включая архивированные) для кеша
      final allChats = await _apiService.getChats(includeArchived: true);
      
      if (mounted) {
        // Сохраняем все чаты в _allChats
        _allChats = allChats;
        
        // Обновляем текущие чаты на основе режима архива
        _updateChatsFromAll();
        
        // Фильтруем по поисковому запросу
        _filterChats();
        
        // Для Stories всегда используем все неархивированные чаты
        final allNonArchivedChats = allChats
            .where((chat) => !chat.isArchived)
            .toList();
        
        setState(() {
          // Собираем пользователей для Stories из всех неархивированных чатов
          _storyUsers = allNonArchivedChats
              .where((chat) => chat.isDirect && chat.otherUser != null)
              .map((chat) => chat.otherUser!)
              .toList();
          
          _isLoading = false;
        });
        
        // Сохраняем все чаты в кэш
        _saveChatsToCache(allChats);
        
        // Загружаем статусы пользователей после загрузки чатов
        _loadUserStatuses();
      }
    } catch (e) {
      debugPrint('Error loading chats: $e');
      
      // FALLBACK: Используем кеш при ошибке, если список пуст
      if (_chats.isEmpty) {
        try {
          final cachedChats = await _loadChatsFromCache();
          if (cachedChats.isNotEmpty && mounted) {
            setState(() {
              _allChats = cachedChats;
              _updateChatsFromAll();
              _filterChats();
              
              // Для Stories используем неархивированные чаты
              final allNonArchivedChats = cachedChats
                  .where((chat) => !chat.isArchived)
                  .toList();
              _storyUsers = allNonArchivedChats
                  .where((chat) => chat.isDirect && chat.otherUser != null)
                  .map((chat) => chat.otherUser!)
                  .toList();
              
              _isLoading = false;
            });
            
            debugPrint('ChatsListScreen: Using ${cachedChats.length} cached chats due to error');
            
            // Загружаем статусы для кешированных чатов
            if (_chats.isNotEmpty) {
              _loadUserStatuses();
            }
            
            // Показываем информационное сообщение
            if (mounted) {
              AppNotification.showInfo(
                context,
                'Showing cached chats. Pull to refresh.',
                duration: const Duration(seconds: 3),
              );
            }
            return; // Успешно загрузили из кеша
          }
        } catch (cacheError) {
          debugPrint('ChatsListScreen: Error loading from cache: $cacheError');
        }
      }
      
      // Если кеш не помог, показываем ошибку
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        AppNotification.showError(context, 'Failed to load chats: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: BlurText(
          key: ValueKey(_showArchived ? 'archived' : 'messages'),
          text: _showArchived ? 'Archived' : 'Messages',
          duration: const Duration(seconds: 1),
          type: AnimationType.word,
          textStyle: GoogleFonts.delaGothicOne(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadChats(refresh: true),
        color: const Color(0xFF0095F6),
        child: _isLoading && _chats.isEmpty
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF0095F6),
                ),
              )
            : Column(
                children: [
                  // Stories section - показываем всегда (используем кешированные неархивированные чаты)
                  _buildStoriesSection(),
                  
                  // Search bar
                  _buildSearchBar(),
                  
                  // Chats list
                  Expanded(
                    child: _filteredChats.isEmpty && !_isLoading
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
                                Text(
                                  _searchController.text.isEmpty
                                      ? (_showArchived 
                                          ? 'No archived chats'
                                          : 'No messages yet')
                                      : 'No chats found',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchController.text.isEmpty
                                      ? (_showArchived
                                          ? 'Archived chats will appear here'
                                          : 'Start a conversation')
                                      : 'Try different search terms',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (Widget child, Animation<double> animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.1),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOut,
                                  )),
                                  child: child,
                                ),
                              );
                            },
                            child: AnimationLimiter(
                              key: ValueKey(_showArchived ? 'archived' : 'regular'),
                              child: ListView.builder(
                                itemCount: _filteredChats.length,
                                itemBuilder: (context, index) {
                                  final chat = _filteredChats[index];
                                  return AnimationConfiguration.staggeredList(
                                    position: index,
                                    duration: const Duration(milliseconds: 375),
                                    child: SlideAnimation(
                                      verticalOffset: 50.0,
                                      child: FadeInAnimation(
                                        child: _buildSwipeableChatItem(chat),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  // Удаление чата
  Future<void> _deleteChat(Chat chat) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      // TODO: Добавить API метод для удаления чата
      // await _apiService.deleteChat(chat.id);
      
      // Пока делаем локальное удаление
      setState(() {
        _allChats.removeWhere((c) => c.id == chat.id);
        _updateChatsFromAll();
        _filterChats();
      });
      
      // Обновляем кэш
      _saveChatsToCache(_allChats);
      
      if (mounted) {
        AppNotification.showSuccess(context, 'Chat deleted');
      }
    } catch (e) {
      debugPrint('Error deleting chat: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to delete chat: $e');
      }
    }
  }

  // Архивирование чата
  Future<void> _archiveChat(Chat chat) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      
      // Архивируем через API
      await _apiService.archiveChat(chat.id, true);
      
      // Обновляем локально: обновляем статус архивирования
      setState(() {
        final index = _allChats.indexWhere((c) => c.id == chat.id);
        if (index != -1) {
          final updatedChat = Chat(
            id: chat.id,
            type: chat.type,
            createdAt: chat.createdAt,
            updatedAt: chat.updatedAt,
            otherUser: chat.otherUser,
            participants: chat.participants,
            unreadCount: chat.unreadCount,
            lastMessage: chat.lastMessage,
            isArchived: true,
            isPinned: chat.isPinned,
          );
          _allChats[index] = updatedChat;
          _updateChatsFromAll();
          _filterChats();
        }
      });
      
      // Обновляем кэш
      _saveChatsToCache(_allChats);
      
      if (mounted) {
        AppNotification.showSuccess(context, 'Chat archived');
      }
    } catch (e) {
      debugPrint('Error archiving chat: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to archive chat: $e');
      }
    }
  }

  // Разархивирование чата
  Future<void> _unarchiveChat(Chat chat) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      
      // Разархивируем через API
      await _apiService.archiveChat(chat.id, false);
      
      // Обновляем локально: обновляем статус архивирования
      setState(() {
        final index = _allChats.indexWhere((c) => c.id == chat.id);
        if (index != -1) {
          final updatedChat = Chat(
            id: chat.id,
            type: chat.type,
            createdAt: chat.createdAt,
            updatedAt: chat.updatedAt,
            otherUser: chat.otherUser,
            participants: chat.participants,
            unreadCount: chat.unreadCount,
            lastMessage: chat.lastMessage,
            isArchived: false,
            isPinned: chat.isPinned,
          );
          _allChats[index] = updatedChat;
          _updateChatsFromAll();
          _filterChats();
        }
      });
      
      // Обновляем кэш
      _saveChatsToCache(_allChats);
      
      if (mounted) {
        AppNotification.showSuccess(context, 'Chat unarchived');
      }
    } catch (e) {
      debugPrint('Error unarchiving chat: $e');
      if (mounted) {
        AppNotification.showError(context, 'Failed to unarchive chat: $e');
      }
    }
  }

  // Закрепление/открепление чата
  Future<void> _pinChat(Chat chat, bool isPinned) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      
      // Закрепляем через API
      await _apiService.pinChat(chat.id, isPinned);
      
      // Обновляем локально
      setState(() {
        final index = _allChats.indexWhere((c) => c.id == chat.id);
        if (index != -1) {
          final updatedChat = Chat(
            id: chat.id,
            type: chat.type,
            createdAt: chat.createdAt,
            updatedAt: chat.updatedAt,
            otherUser: chat.otherUser,
            participants: chat.participants,
            unreadCount: chat.unreadCount,
            lastMessage: chat.lastMessage,
            isArchived: chat.isArchived,
            isPinned: isPinned,
          );
          _allChats[index] = updatedChat;
          _updateChatsFromAll();
          _filterChats();
        }
      });
      
      // Обновляем кэш
      _saveChatsToCache(_allChats);
      
      if (mounted) {
        AppNotification.showSuccess(
          context,
          isPinned ? 'Chat pinned' : 'Chat unpinned',
        );
      }
    } catch (e) {
      debugPrint('Error pinning chat: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to ${chat.isPinned ? 'unpin' : 'pin'} chat: $e',
        );
      }
    }
  }

  // Swipeable chat item с действиями
  Widget _buildSwipeableChatItem(Chat chat) {
    return _SwipeableChatItem(
      chat: chat,
      onArchive: () => _archiveChat(chat),
      onUnarchive: () => _unarchiveChat(chat),
      onDelete: () => _deleteChat(chat),
      onPin: (isPinned) => _pinChat(chat, isPinned),
      onTap: () => _openChat(chat),
      child: _buildChatItem(chat),
    );
  }

  // Открытие чата
  Future<void> _openChat(Chat chat) async {
    // Сохраняем текущий unreadCount для сравнения
    final previousUnreadCount = chat.unreadCount;
    
    // Открываем экран чата
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(chat: chat),
      ),
    );
    
        // Оптимизированное обновление: обновляем только если нужно
        // Если вернулся результат с обновленным чатом, обновляем только его
        if (result != null && result is Chat) {
          // Обновляем конкретный чат в списке
          final index = _allChats.indexWhere((c) => c.id == result.id);
          if (index != -1) {
            setState(() {
              _allChats[index] = result;
              _updateChatsFromAll(); // Обновляем текущие чаты
              _filterChats();
            });
            // Обновляем кэш
            _saveChatsToCache(_allChats);
            // Обновляем статус пользователя если нужно
            if (result.otherUser != null && !_userStatuses.containsKey(result.otherUser!.id)) {
              _loadUserStatuses();
            }
          }
        } else {
          // Если результат не передан, обновляем только unreadCount локально
          // (предполагаем, что сообщения были прочитаны при открытии чата)
          if (previousUnreadCount > 0) {
            final index = _allChats.indexWhere((c) => c.id == chat.id);
            if (index != -1) {
              setState(() {
                // Создаем обновленный чат с нулевым unreadCount
                final updatedChat = Chat(
                  id: chat.id,
                  type: chat.type,
                  createdAt: chat.createdAt,
                  updatedAt: DateTime.now(), // Обновляем время
                  otherUser: chat.otherUser,
                  participants: chat.participants,
                  unreadCount: 0, // Сбрасываем счетчик непрочитанных
                  lastMessage: chat.lastMessage,
                  isArchived: chat.isArchived, // Сохраняем статус архивирования
                  isPinned: chat.isPinned, // Сохраняем статус закрепления
                );
                _allChats[index] = updatedChat;
                _updateChatsFromAll(); // Обновляем текущие чаты
                _filterChats();
              });
              // Обновляем кэш
              _saveChatsToCache(_allChats);
            }
          }
        }
  }

  Widget _buildChatItem(Chat chat) {
    final hasUnread = chat.unreadCount > 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF262626),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar с индикаторами
          Stack(
              children: [
                SafeAvatar(
                  imageUrl: chat.displayAvatar,
                  radius: 28,
                ),
                // Индикатор непрочитанных сообщений (вверху справа)
                if (hasUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0095F6),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          chat.unreadCount > 9 ? '9+' : chat.unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                // Индикатор онлайн (внизу справа) - показываем только если нет непрочитанных
                if (!hasUnread && 
                    chat.otherUser != null && 
                    _userStatuses[chat.otherUser!.id]?['is_online'] == true)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
          ),
          const SizedBox(width: 12),
          
          // Chat info
          Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Иконка закрепления
                      if (chat.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            EvaIcons.pin,
                            size: 14,
                            color: const Color(0xFF0095F6),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          chat.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Компактный статус-бейдж только для онлайн (показываем только если есть место)
                      if (chat.otherUser != null && 
                          _userStatuses[chat.otherUser!.id] != null &&
                          _userStatuses[chat.otherUser!.id]!['is_online'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'online',
                            style: const TextStyle(
                              color: Color(0xFF4CAF50),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      if (chat.lastMessage != null)
                        Text(
                          _formatTime(chat.lastMessage!.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUnread ? const Color(0xFF0095F6) : const Color(0xFF8E8E8E),
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (chat.lastMessage != null)
                    Builder(
                      builder: (context) {
                        final authProvider = context.read<AuthProvider>();
                        final currentUserId = authProvider.currentUser?.id;
                        final isOwnMessage = currentUserId != null && 
                                            chat.lastMessage!.senderId == currentUserId;
                        final content = chat.lastMessage!.content ?? 'Voice message';
                        
                        return Text(
                          isOwnMessage 
                              ? 'You: $content'
                              : content,
                          style: TextStyle(
                            fontSize: 14,
                            color: hasUnread ? Colors.white : const Color(0xFF8E8E8E),
                            fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    )
                  else
                    Text(
                      'No messages yet',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoriesSection() {
    // Показываем Stories даже если список пустой (показываем только кнопку "Your Story")
    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _storyUsers.length > 10 ? 11 : _storyUsers.length + 1, // Ограничиваем до 10 + кнопка добавления
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildAddStoryItem();
          }
          final userIndex = index - 1;
          if (userIndex < _storyUsers.length) {
            return _buildStoryItem(_storyUsers[userIndex]);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildAddStoryItem() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final currentUser = authProvider.currentUser;
        return GestureDetector(
          onTap: () {
            if (currentUser != null) {
              // Передаем null вместо userId, чтобы показать свой профиль
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(userId: null),
                ),
              );
            }
          },
          child: Container(
            width: 70,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF262626),
                          width: 2,
                        ),
                      ),
                      child: SafeAvatar(
                        imageUrl: currentUser?.avatarUrl,
                        radius: 28,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color(0xFF0095F6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          EvaIcons.plus,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your Story',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStoryItem(User user) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: user.id),
          ),
        );
      },
      child: Container(
        width: 70,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF833AB4),
                    Color(0xFFE1306C),
                    Color(0xFFFD1D1D),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF000000),
                ),
                padding: const EdgeInsets.all(2),
                child: SafeAvatar(
                  imageUrl: user.avatarUrl,
                  radius: 28,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user.name.isNotEmpty ? user.name : user.username,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {}); // Обновляем state для обновления suffixIcon
              },
              decoration: InputDecoration(
                hintText: _showArchived ? 'Search archived chats' : 'Search by name or username',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(
                  EvaIcons.searchOutline,
                  color: Color(0xFF8E8E8E),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          EvaIcons.closeCircle,
                          color: Color(0xFF8E8E8E),
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {}); // Обновляем state после очистки
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF262626),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Кнопка архива с анимацией
          GestureDetector(
            onTap: () {
              setState(() {
                _showArchived = !_showArchived;
                _searchController.clear(); // Очищаем поиск при переключении
                // Обновляем чаты из кеша без перезагрузки
                _updateChatsFromAll();
                _filterChats();
              });
              // Обновляем данные в фоне (без показа loading)
              _loadChats(refresh: true);
            },
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              tween: Tween(begin: 0.0, end: _showArchived ? 1.0 : 0.0),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      const Color(0xFF262626),
                      const Color(0xFF0095F6).withOpacity(0.2),
                      value,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Color.lerp(
                        Colors.transparent,
                        const Color(0xFF0095F6),
                        value,
                      ) ?? Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Transform.scale(
                    scale: 1.0 + (value * 0.1), // Легкое увеличение при активации
                    child: Transform.rotate(
                      angle: value * 0.5, // Легкое вращение
                      child: Icon(
                        EvaIcons.archiveOutline,
                        color: Color.lerp(
                          const Color(0xFF8E8E8E),
                          const Color(0xFF0095F6),
                          value,
                        ),
                        size: 24,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      // Сегодня - показываем только время
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // Неделя
      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[dateTime.weekday - 1];
    } else {
      // Старые - дата
      return '${dateTime.day}/${dateTime.month}';
    }
  }
}

// Кастомный swipeable виджет с кнопками действий
class _SwipeableChatItem extends StatefulWidget {
  final Chat chat;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;
  final VoidCallback onDelete;
  final Function(bool) onPin;
  final Widget child;
  final VoidCallback? onTap; // Callback для тапа на чат

  const _SwipeableChatItem({
    required this.chat,
    required this.onArchive,
    required this.onUnarchive,
    required this.onDelete,
    required this.onPin,
    required this.child,
    this.onTap,
  });

  @override
  State<_SwipeableChatItem> createState() => _SwipeableChatItemState();
}

class _SwipeableChatItemState extends State<_SwipeableChatItem> with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  static const double _actionThreshold = 120.0; // Порог для полного свайпа (выполнение действия)
  static const double _buttonWidth = 80.0; // Ширина одной кнопки
  static const double _showButtonsThreshold = 20.0; // Порог для показа кнопок
  late AnimationController _animationController;
  late Animation<double> _animation;
  VoidCallback? _animationListener;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    if (_animationListener != null) {
      _animation.removeListener(_animationListener!);
      _animationListener = null;
    }
    _animationController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    // Останавливаем анимацию если она активна
    if (_animationController.isAnimating) {
      _animationController.stop();
      if (_animationListener != null) {
        _animation.removeListener(_animationListener!);
        _animationListener = null;
      }
    }
    
    setState(() {
      final delta = details.primaryDelta ?? 0;
      _dragOffset += delta;
      
      // Ограничиваем диапазон свайпа с плавным сопротивлением на границах
      if (_dragOffset > 0) {
        // Свайп вправо - показываем кнопку удаления
        if (_dragOffset > _buttonWidth) {
          // Плавное сопротивление при превышении максимума
          final excess = _dragOffset - _buttonWidth;
          _dragOffset = _buttonWidth + excess * 0.3;
        } else {
          _dragOffset = _dragOffset.clamp(0.0, _buttonWidth);
        }
      } else {
        // Свайп влево - показываем кнопки архива и закрепления
        final maxLeft = -_buttonWidth * 2;
        if (_dragOffset < maxLeft) {
          // Плавное сопротивление при превышении максимума
          final excess = _dragOffset - maxLeft;
          _dragOffset = maxLeft + excess * 0.3;
        } else {
          _dragOffset = _dragOffset.clamp(maxLeft, 0.0);
        }
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    // Останавливаем анимацию если она активна
    if (_animationController.isAnimating) {
      _animationController.stop();
      if (_animationListener != null) {
        _animation.removeListener(_animationListener!);
        _animationListener = null;
      }
    }
    
    final absOffset = _dragOffset.abs();
    final velocity = details.velocity.pixelsPerSecond.dx;
    
    if (_dragOffset < 0) {
      // Свайп влево - всегда открываем кнопки (закрепляем в открытом состоянии)
      if (absOffset >= _showButtonsThreshold || velocity < -200) {
        // Показываем обе кнопки слева и закрепляем элемент
        _animateToPosition(-_buttonWidth * 2);
      } else {
        // Очень легкий свайп - возвращаем в исходное положение
        _resetPosition();
      }
    } else if (_dragOffset > 0) {
      // Свайп вправо - удаление с подтверждением при полном свайпе
      if (absOffset >= _actionThreshold || velocity > 200) {
        // Полный свайп вправо → Удалить с подтверждением
        _resetPosition();
        _confirmAndDelete();
      } else if (absOffset >= _showButtonsThreshold) {
        // Легкий свайп - показываем кнопку удаления
        _animateToPosition(_buttonWidth);
      } else {
        // Очень легкий свайп - возвращаем в исходное положение
        _resetPosition();
      }
    } else {
      // Нет свайпа - возвращаем в исходное положение
      _resetPosition();
    }
  }

  void _resetPosition() {
    _animateToPosition(0.0);
  }

  void _animateToPosition(double target) {
    // Останавливаем предыдущую анимацию если она активна
    if (_animationController.isAnimating) {
      _animationController.stop();
    }
    
    // Удаляем старый listener если есть
    if (_animationListener != null) {
      _animation.removeListener(_animationListener!);
      _animationListener = null;
    }
    
    final startOffset = _dragOffset;
    final distance = (target - startOffset).abs();
    
    // Адаптивная длительность в зависимости от расстояния
    final duration = (distance / _buttonWidth * 300).clamp(150.0, 400.0);
    
    _animationController.duration = Duration(milliseconds: duration.toInt());
    _animationController.reset();
    
    _animation = Tween<double>(
      begin: startOffset,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    // Создаем новый listener
    _animationListener = () {
      if (mounted) {
        setState(() {
          _dragOffset = _animation.value;
        });
      }
    };
    
    _animation.addListener(_animationListener!);
    
    _animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        if (_animationListener != null) {
          _animation.removeListener(_animationListener!);
          _animationListener = null;
        }
      }
    });
    
    _animationController.forward();
  }

  Future<void> _confirmAndDelete() async {
    _resetPosition();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        title: const Text(
          'Delete chat?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This chat will be permanently deleted. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;

    if (confirmed) {
      widget.onDelete();
    }
  }


  void _onArchiveTap() {
    _resetPosition();
    if (widget.chat.isArchived) {
      widget.onUnarchive();
    } else {
      widget.onArchive();
    }
  }

  void _onPinTap() {
    _resetPosition();
    widget.onPin(!widget.chat.isPinned);
  }

  void _onDeleteTap() {
    _resetPosition();
    _confirmAndDelete();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Stack(
        children: [
          // Фон с кнопками действий (внизу)
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Кнопки слева (при свайпе влево) - фиксированы на месте
                if (_dragOffset < 0)
                  Expanded(
                    child: Container(
                      color: const Color(0xFF262626),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Кнопка закрепления
                          GestureDetector(
                            onTap: _onPinTap,
                            child: Container(
                              width: _buttonWidth,
                              color: widget.chat.isPinned
                                  ? const Color(0xFF0095F6).withOpacity(0.3)
                                  : const Color(0xFF262626),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.chat.isPinned
                                        ? EvaIcons.pin
                                        : EvaIcons.pinOutline,
                                    color: widget.chat.isPinned
                                        ? const Color(0xFF0095F6)
                                        : Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.chat.isPinned ? 'Unpin' : 'Pin',
                                    style: TextStyle(
                                      color: widget.chat.isPinned
                                          ? const Color(0xFF0095F6)
                                          : Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Кнопка архива
                          GestureDetector(
                            onTap: _onArchiveTap,
                            child: Container(
                              width: _buttonWidth,
                              color: const Color(0xFF8E8E8E).withOpacity(0.8),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.chat.isArchived
                                        ? EvaIcons.archive
                                        : EvaIcons.archiveOutline,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.chat.isArchived ? 'Unarchive' : 'Archive',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
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
                  ),
                // Кнопка справа (при свайпе вправо) - фиксирована на месте
                if (_dragOffset > 0)
                  Container(
                    width: _buttonWidth,
                    color: Colors.red.withOpacity(0.8),
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: _onDeleteTap,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            EvaIcons.trash2Outline,
                            color: Colors.white,
                            size: 24,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
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
          // Основной контент чата (сверху, поверх кнопок)
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Container(
              color: Colors.black, // Непрозрачный фон, чтобы кнопки не просвечивали
              child: GestureDetector(
                onTap: () {
                  // Закрываем кнопки при тапе на чат
                  if (_dragOffset != 0) {
                    _resetPosition();
                  } else if (widget.onTap != null) {
                    widget.onTap!();
                  }
                },
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

