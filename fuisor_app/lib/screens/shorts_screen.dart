import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart' show Post;
import '../providers/posts_provider.dart';
import '../widgets/shorts_video_player.dart';
import '../widgets/shorts_comments_sheet.dart';
import '../widgets/share_video_sheet.dart';
import '../services/api_service.dart';
import '../services/video_cache_service.dart';
import '../services/video_preload_queue.dart';
import '../services/network_speed_detector.dart';

class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key});

  @override
  State<ShortsScreen> createState() => ShortsScreenState();
}

// Публичный класс состояния для доступа из MainScreen
class ShortsScreenState extends State<ShortsScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late TabController _tabController;
  int _currentIndex = 0;
  int _currentTabIndex = 1; // 0 = Following, 1 = Recommendations
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Set<int> _initializingVideos = {}; // Защита от параллельной инициализации
  final Map<int, int> _retryCounts = {}; // Счетчики попыток для retry
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  
  // Сервисы для кеширования и предзагрузки
  final VideoCacheService _videoCacheService = VideoCacheService();
  final VideoPreloadQueue _preloadQueue = VideoPreloadQueue();
  final NetworkSpeedDetector _networkSpeedDetector = NetworkSpeedDetector();
  
  // Отслеживание просмотренных видео
  final Set<String> _viewedPostIds = {};
  
  // Отслеживание, начата ли предзагрузка для текущего видео
  final Map<int, bool> _preloadStartedForIndex = {};
  
  // Максимальное количество контроллеров в памяти (для управления памятью)
  static const int _maxControllersInMemory = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize TabController with initial index 1 (Recommendations)
    _tabController = TabController(initialIndex: 1, length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Set initial tab to Recommendations
    _currentTabIndex = 1;
    
    // Загружаем очередь непросмотренных видео
    _loadUnviewedQueue();
    
    // Запускаем обработку очереди предзагрузки
    _processPreloadQueue();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _disposeAllControllers();
    _pageController.dispose();
    
    // Сохраняем непросмотренные видео перед закрытием
    _saveUnviewedVideos();
    
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    
    setState(() {
      _currentTabIndex = _tabController.index;
      // Останавливаем все видео при переключении вкладок
      pauseAllVideos();
      _disposeAllControllers();
      _initializingVideos.clear();
      _retryCounts.clear();
      _currentIndex = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });

    // ВАЖНО: Устанавливаем _isScreenVisible = true перед загрузкой видео
    // так как мы остаемся на экране Shorts, просто переключаем вкладки
    _isScreenVisible = true;

    // Загружаем соответствующие видео
    _loadVideosForCurrentTab();
  }

  Future<void> _loadVideosForCurrentTab() async {
    print('ShortsScreen: _loadVideosForCurrentTab called, tabIndex: $_currentTabIndex, isScreenVisible: $_isScreenVisible');
    final postsProvider = context.read<PostsProvider>();
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    
    if (_currentTabIndex == 0) {
      // Following
      print('ShortsScreen: Loading following video posts');
      await postsProvider.loadFollowingVideoPosts(refresh: true, accessToken: accessToken);
      print('ShortsScreen: Loaded ${postsProvider.followingVideoPosts.length} following video posts');
    } else {
      // Recommendations
      print('ShortsScreen: Loading recommended video posts');
      await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);
      print('ShortsScreen: Loaded ${postsProvider.videoPosts.length} recommended video posts');
    }
    
    // Инициализируем первое видео
    // ВАЖНО: Проверяем mounted и _isScreenVisible, но также убеждаемся, что данные загружены
    if (mounted && _isScreenVisible) {
      final videoPosts = _currentTabIndex == 0 
          ? postsProvider.followingVideoPosts 
          : postsProvider.videoPosts;
      
      print('ShortsScreen: Video posts count: ${videoPosts.length}, initializing first video');
      
      if (videoPosts.isNotEmpty) {
        // Используем addPostFrameCallback для гарантии, что UI обновлен
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted && _isScreenVisible) {
            print('ShortsScreen: Initializing video 0 in post-frame callback');
            await _initializeVideo(0, videoPosts[0], autoPlay: true);
          } else {
            print('ShortsScreen: Skipping video initialization in callback - mounted: $mounted, isScreenVisible: $_isScreenVisible');
          }
        });
      } else {
        print('ShortsScreen: No video posts available to initialize');
      }
    } else {
      print('ShortsScreen: Skipping video initialization - mounted: $mounted, isScreenVisible: $_isScreenVisible');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      pauseAllVideos();
    } else if (state == AppLifecycleState.resumed && _isScreenVisible) {
      resumeCurrentVideo();
    }
  }

  // Метод для остановки всех видео (при уходе с экрана)
  Future<void> pauseAllVideos() async {
    print('ShortsScreen: pauseAllVideos called');
    _isScreenVisible = false;
    for (var entry in _videoControllers.entries) {
      try {
        final controller = entry.value;
        if (controller.value.isInitialized) {
          await controller.setVolume(0);
          await controller.pause();
          print('ShortsScreen: Paused video ${entry.key}');
        }
      } catch (e) {
        print('Error pausing video ${entry.key}: $e');
      }
    }
  }

  // Метод для возобновления видео при возврате на экран
  Future<void> resumeCurrentVideo() async {
    if (!_isScreenVisible) return;
    
    final currentController = _videoControllers[_currentIndex];
    if (currentController != null && currentController.value.isInitialized) {
      try {
        await currentController.setVolume(1);
        await currentController.play();
        print('ShortsScreen: Resumed video $_currentIndex');
      } catch (e) {
        print('Error resuming video $_currentIndex: $e');
      }
    }
  }

  // Метод для обновления ленты при двойном нажатии
  Future<void> refreshFeed() async {
    // Останавливаем все видео перед очисткой
    await pauseAllVideos();

    // Очищаем контроллеры
    _disposeAllControllers();
    _initializingVideos.clear();
    _retryCounts.clear();

    // Сбрасываем индекс на начало
    _currentIndex = 0;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }

    // Обновляем посты для текущей вкладки
    final postsProvider = context.read<PostsProvider>();
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    
    if (_currentTabIndex == 0) {
      await postsProvider.loadFollowingVideoPosts(refresh: true, accessToken: accessToken);
    } else {
      await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);
    }

    // ВАЖНО: Устанавливаем _isScreenVisible = true, так как мы остаемся на экране Shorts
    _isScreenVisible = true;

    // Переинициализируем первое видео только если экран видим
    if (mounted && _isScreenVisible) {
      final videoPosts = _currentTabIndex == 0 
          ? postsProvider.followingVideoPosts 
          : postsProvider.videoPosts;
      
      if (videoPosts.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _initializeVideo(0, videoPosts[0], autoPlay: true);
        });
      }
    }
  }

  bool _isScreenVisible = false;

  // Method to navigate to a specific post (always opens in Recommendations tab)
  Future<void> navigateToPost(Post targetPost) async {
    print('ShortsScreen: Navigating to post: ${targetPost.id}');
    
    final postsProvider = context.read<PostsProvider>();
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    
    // Always load recommendations video posts
    if (postsProvider.videoPosts.isEmpty) {
      await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);
    }
    
    // Always search in Recommendations tab (index 1)
    int? foundIndex;
    int targetTabIndex = 1; // Always use Recommendations tab
    
    // Check Recommendations tab
      final recommendedIndex = postsProvider.videoPosts.indexWhere((p) => p.id == targetPost.id);
      if (recommendedIndex != -1) {
        foundIndex = recommendedIndex;
    }
    
    // If post not found in recommendations, just switch to recommendations tab
    if (foundIndex == null) {
      // Post not in recommendations, just switch to recommendations tab
      print('ShortsScreen: Post ${targetPost.id} not found in recommendations, opening recommendations tab');
      if (_currentTabIndex != 1) {
        _tabController.animateTo(1);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      setState(() {
        _currentTabIndex = 1;
        _currentIndex = 0;
        _isScreenVisible = true;
      });
      await initializeScreen();
      return;
    }
    
    if (mounted) {
      // Switch to Recommendations tab if not already there
      if (_currentTabIndex != targetTabIndex) {
        _tabController.animateTo(targetTabIndex);
        await Future.delayed(const Duration(milliseconds: 300)); // Wait for tab switch
      }
      
      // Set index and switch to the correct page
      setState(() {
        _currentIndex = foundIndex!;
        _currentTabIndex = targetTabIndex;
        _isScreenVisible = true;
      });
      
      // Switch to the correct page in PageController
      if (_pageController.hasClients) {
        await _pageController.animateToPage(
          foundIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      
      // Initialize and play video
      final videoPosts = postsProvider.videoPosts;
      
      if (foundIndex < videoPosts.length) {
        await _initializeVideo(foundIndex, videoPosts[foundIndex], autoPlay: true);
      }
    } else {
      print('ShortsScreen: Post ${targetPost.id} not found in video posts');
      // If post not found, just initialize screen
      await initializeScreen();
    }
  }

  // Метод для инициализации экрана при первом открытии
  Future<void> initializeScreen() async {
    // Устанавливаем флаг видимости экрана
    _isScreenVisible = true;
    
    // Проверяем, есть ли уже инициализированное видео для текущего индекса
    final currentController = _videoControllers[_currentIndex];
    if (currentController != null && currentController.value.isInitialized) {
      // Если видео уже инициализировано, просто возобновляем его
      await resumeCurrentVideo();
      return;
    }
    
    final postsProvider = context.read<PostsProvider>();
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    
    // Загружаем непросмотренные видео из очереди
    final unviewedPosts = await _preloadQueue.loadUnviewedQueue();
    
    // Загружаем видео для текущей вкладки
    if (_currentTabIndex == 0) {
      if (postsProvider.followingVideoPosts.isEmpty) {
        await postsProvider.loadFollowingVideoPosts(refresh: true, accessToken: accessToken);
      }
    } else {
      if (postsProvider.videoPosts.isEmpty) {
        await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);
      }
    }
    
    // Инициализируем первое видео только если посты уже загружены
    if (mounted && _isScreenVisible) {
      final videoPosts = _currentTabIndex == 0 
          ? postsProvider.followingVideoPosts 
          : postsProvider.videoPosts;
      
      if (videoPosts.isNotEmpty) {
        // Если есть непросмотренные видео, добавляем их в начало списка
        List<Post> finalVideoPosts = videoPosts;
        if (unviewedPosts.isNotEmpty) {
          // Находим непросмотренные видео в текущем списке и перемещаем их в начало
          final unviewedIds = unviewedPosts.map((p) => p.id).toSet();
          final unviewedInList = videoPosts.where((p) => unviewedIds.contains(p.id)).toList();
          final viewedInList = videoPosts.where((p) => !unviewedIds.contains(p.id)).toList();
          finalVideoPosts = [...unviewedInList, ...viewedInList];
        }
        
        // Предзагружаем следующее видео в кеш (если есть)
        if (finalVideoPosts.length > 1) {
          final nextPost = finalVideoPosts[1];
          try {
            final apiService = ApiService();
            apiService.setAccessToken(accessToken);
            final result = await apiService.getPostMediaSignedUrl(
              mediaPath: nextPost.mediaUrl,
              postId: nextPost.id,
            );
            final signedUrl = result['signedUrl']!;
            
            // Только предзагружаем в кеш, не инициализируем контроллер
            _videoCacheService.preloadVideo(nextPost.id, signedUrl).catchError((e) {
              print('ShortsScreen: Error preloading next video: $e');
            });
          } catch (e) {
            print('ShortsScreen: Error getting signed URL for initial preload: $e');
          }
        }
        
        // Инициализируем только текущее видео
        if (!_videoControllers.containsKey(_currentIndex)) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (_currentIndex < finalVideoPosts.length) {
              await _initializeVideo(_currentIndex, finalVideoPosts[_currentIndex], autoPlay: true);
            }
          });
        } else {
          // Если контроллер уже есть, просто возобновляем
          await resumeCurrentVideo();
        }
      }
    }
  }

  void _disposeAllControllers() {
    for (var controller in _videoControllers.values) {
      try {
        controller.pause();
        controller.setVolume(0);
        controller.dispose();
      } catch (e) {
        print('Error disposing controller: $e');
      }
    }
    _videoControllers.clear();
  }

  /// Инициализирует контроллер для видео из кеша (без автозапуска)
  /// Используется для предварительной инициализации следующих видео
  /// postId - уникальный идентификатор поста для проверки кеша
  Future<void> _initializeControllerFromCache(int index, String postId) async {
    // Проверяем, не инициализирован ли уже контроллер
    if (_videoControllers.containsKey(index)) {
      final existingController = _videoControllers[index]!;
      if (existingController.value.isInitialized) {
        print('ShortsScreen: Controller for video $index already initialized');
        return;
      }
    }

    // Проверяем, не инициализируется ли уже
    if (_initializingVideos.contains(index)) {
      print('ShortsScreen: Video $index is already initializing, skipping');
      return;
    }

    if (!mounted) return;

    _initializingVideos.add(index);
    print('ShortsScreen: Initializing controller from cache for video $index (post: $postId)');

    try {
      // Получаем кешированный файл по postId
      final cachedFile = await _videoCacheService.getCachedVideo(postId);
      if (cachedFile == null || !cachedFile.existsSync()) {
        print('ShortsScreen: Video $index (post: $postId) not in cache yet, cannot initialize controller');
        _initializingVideos.remove(index);
        return;
      }

      // Создаем и инициализируем контроллер
      final controller = VideoPlayerController.file(
        cachedFile,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
        ),
      );

      await controller.initialize();
      controller.setLooping(true);
      await controller.setVolume(0);
      await controller.pause();

      if (!mounted) {
        controller.dispose();
        _initializingVideos.remove(index);
        return;
      }

      // Проверяем еще раз, не был ли контроллер создан в другом месте
      if (!_videoControllers.containsKey(index)) {
        setState(() {
          _videoControllers[index] = controller;
        });
        print('ShortsScreen: Controller for video $index initialized from cache and ready');
      } else {
        controller.dispose();
        print('ShortsScreen: Controller for video $index was already created, disposing duplicate');
      }
    } catch (e) {
      print('ShortsScreen: Error initializing controller from cache for video $index: $e');
    } finally {
      _initializingVideos.remove(index);
    }
  }

  Future<void> _initializeVideo(int index, Post post, {bool autoPlay = false, int retryAttempt = 0}) async {
    // Защита от параллельной инициализации
    if (_initializingVideos.contains(index)) {
      print('ShortsScreen: Video $index is already initializing, skipping');
      return;
    }

    // Проверяем, не инициализирован ли уже контроллер
    if (_videoControllers.containsKey(index)) {
      final existingController = _videoControllers[index]!;
      if (existingController.value.isInitialized) {
        print('ShortsScreen: Video $index already initialized, using existing controller');
        // Если это текущее видео и нужно автозапустить
        if (autoPlay && index == _currentIndex && _isScreenVisible) {
          try {
            await existingController.seekTo(Duration.zero);
            await existingController.setVolume(1);
            await existingController.play();
            print('ShortsScreen: Playing already initialized video $index');
          } catch (e) {
            print('ShortsScreen: Error playing already initialized video $index: $e');
          }
        }
      return;
      }
    }

    // Не инициализируем видео, если экран не видим
    if (!_isScreenVisible) {
      print('ShortsScreen: Screen not visible, skipping initialization of video $index');
      return;
    }

    _initializingVideos.add(index);
    print('ShortsScreen: Starting initialization of video $index (attempt ${retryAttempt + 1})');

    try {
      // Получаем signed URL для видео
      String videoUrl = post.mediaUrl;
      if (post.mediaType == 'video') {
        try {
          final prefs = await SharedPreferences.getInstance();
          final accessToken = prefs.getString('access_token');
          if (accessToken != null) {
            final apiService = ApiService();
            apiService.setAccessToken(accessToken);
            
            // Получаем signed URL
            print('ShortsScreen: Getting signed URL for video $index (post: ${post.id})');
            final result = await apiService.getPostMediaSignedUrl(
              mediaPath: post.mediaUrl,
              postId: post.id, // Передаем postId
            );
            videoUrl = result['signedUrl']!;
            print('ShortsScreen: Got signed URL for video $index (post: ${post.id})');
          } else {
            print('ShortsScreen: No access token, using original URL');
          }
        } catch (e) {
          print('ShortsScreen: Error getting signed URL: $e, using original URL');
          // Продолжаем с оригинальным URL, если не удалось получить signed URL
        }
      }

      // Проверяем кеш перед загрузкой по postId
      final cachedFile = await _videoCacheService.getCachedVideo(post.id);
      late VideoPlayerController controller;
      
      if (cachedFile != null && cachedFile.existsSync()) {
        // Используем кешированный файл
        print('ShortsScreen: Using cached video for post ${post.id} (index: $index)');
        controller = VideoPlayerController.file(
          cachedFile,
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,
          ),
        );
      } else {
        // Если нет в кеше, проверяем, не загружается ли оно сейчас (предзагрузка)
        print('ShortsScreen: Video $index (post: ${post.id}) not in cache, checking if preload in progress...');
        
        // Даем небольшую задержку для завершения предзагрузки (если она идет)
        // Увеличиваем количество попыток и время ожидания для более надежной проверки
        bool foundInCache = false;
        for (int attempt = 0; attempt < 5; attempt++) {
          await Future.delayed(const Duration(milliseconds: 150));
          final cachedFileAfterWait = await _videoCacheService.getCachedVideo(post.id);
          if (cachedFileAfterWait != null && cachedFileAfterWait.existsSync()) {
            print('ShortsScreen: Video $index (post: ${post.id}) appeared in cache after wait (attempt ${attempt + 1})');
            controller = VideoPlayerController.file(
              cachedFileAfterWait,
              videoPlayerOptions: VideoPlayerOptions(
                mixWithOthers: false,
              ),
            );
            foundInCache = true;
            break;
          }
        }
        
        // Если все еще нет в кеше, загружаем из сети
        if (!foundInCache) {
          print('ShortsScreen: Loading video from network for post ${post.id} (index: $index)');
          controller = VideoPlayerController.networkUrl(
            Uri.parse(videoUrl),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
            ),
          );
          
          // Предзагружаем видео в кеш в фоне для следующего раза (используем postId)
          _videoCacheService.preloadVideo(post.id, videoUrl).catchError((e) {
            print('ShortsScreen: Error preloading video to cache: $e');
          });
        }
      }
      
      await controller.initialize();
      controller.setLooping(true);
      
      if (!mounted) {
        controller.dispose();
        _initializingVideos.remove(index);
        return;
      }

      setState(() {
        _videoControllers[index] = controller;
      });
      
      // Отмечаем видео как просмотренное
      _viewedPostIds.add(post.id);
      _preloadQueue.markAsViewed(post.id);
      
      // ВСЕГДА сначала ставим на паузу с выключенным звуком
      await controller.setVolume(0);
      await controller.pause();
      
      // Сбрасываем счетчик попыток при успехе
      _retryCounts.remove(index);
      
      // Автозапуск только если явно указано и это текущее видео
      // ИСПРАВЛЕНИЕ: Добавляем небольшую задержку для гарантии, что состояние обновилось
      if (autoPlay && index == _currentIndex && _isScreenVisible) {
        // Небольшая задержка для синхронизации состояния
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted && _isScreenVisible && index == _currentIndex) {
          await controller.seekTo(Duration.zero);
          await controller.setVolume(1);
          await controller.play();
          print('ShortsScreen: Video $index initialized and auto-playing (volume=1)');
          
          // ВАЖНО: Начинаем предзагрузку следующего видео через 0.5 секунды после начала просмотра
          // Это даст время для стабилизации текущего видео и начнет загрузку следующего заранее
          if (!_preloadStartedForIndex.containsKey(index) || !_preloadStartedForIndex[index]!) {
            _preloadStartedForIndex[index] = true;
            // Уменьшаем задержку до 0.5 секунды для более быстрой предзагрузки
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && _currentIndex == index && _isScreenVisible) {
                final postsProvider = context.read<PostsProvider>();
                final videoPosts = _currentTabIndex == 0 
                    ? postsProvider.followingVideoPosts 
                    : postsProvider.videoPosts;
                print('ShortsScreen: Starting background preload for next videos after video $index started playing');
                _preloadNextVideos(index, videoPosts).catchError((e) {
                  print('ShortsScreen: Error preloading next videos in background: $e');
                });
              }
            });
          }
        } else {
          print('ShortsScreen: Video $index initialized and paused (conditions changed)');
        }
      } else {
        print('ShortsScreen: Video $index initialized and paused');
      }
    } catch (e) {
      print('Error initializing video $index (attempt ${retryAttempt + 1}): $e');
      
      // Retry логика
      final currentRetryCount = _retryCounts[index] ?? 0;
      if (currentRetryCount < _maxRetries && _isScreenVisible) {
        _retryCounts[index] = currentRetryCount + 1;
        print('ShortsScreen: Retrying video $index initialization in ${_retryDelay.inSeconds}s (attempt ${currentRetryCount + 1}/$_maxRetries)');
        
        await Future.delayed(_retryDelay);
        if (mounted && _isScreenVisible) {
          await _initializeVideo(index, post, autoPlay: autoPlay, retryAttempt: currentRetryCount + 1);
        }
      } else {
        print('ShortsScreen: Failed to initialize video $index after $_maxRetries attempts');
        _retryCounts.remove(index);
      }
    } finally {
      _initializingVideos.remove(index);
    }
  }

  /// Очищает контроллеры для видео, которые далеко от текущего индекса
  /// Теперь удаляет все контроллеры, кроме предыдущего, текущего и следующего
  void _cleanupOldControllers(int currentIndex) {
    final controllersToRemove = <int>[];
    
    for (final entry in _videoControllers.entries) {
      final videoIndex = entry.key;
      
      // Оставляем только предыдущее (currentIndex - 1), текущее (currentIndex) и следующее (currentIndex + 1)
      if (videoIndex != currentIndex - 1 && 
          videoIndex != currentIndex && 
          videoIndex != currentIndex + 1) {
        controllersToRemove.add(videoIndex);
      }
    }
    
    // Удаляем старые контроллеры
    for (final indexToRemove in controllersToRemove) {
      final controller = _videoControllers[indexToRemove];
      if (controller != null) {
        try {
          controller.pause();
          controller.setVolume(0);
          controller.dispose();
          print('ShortsScreen: Disposed old controller for video $indexToRemove (not in range: ${currentIndex - 1}-${currentIndex + 1})');
        } catch (e) {
          print('ShortsScreen: Error disposing old controller: $e');
        }
      }
      _videoControllers.remove(indexToRemove);
      _initializingVideos.remove(indexToRemove);
      _retryCounts.remove(indexToRemove);
    }
    
    if (controllersToRemove.isNotEmpty) {
      print('ShortsScreen: Cleaned up ${controllersToRemove.length} old controllers');
    }
  }

  void _onPageChanged(int index) async {
    print('ShortsScreen: Page changed from $_currentIndex to $index');
    
    // ВАЖНО: Очищаем старые контроллеры перед инициализацией новых
    _cleanupOldControllers(index);
    
    // Останавливаем ВСЕ видео (включая текущее) с выключенным звуком и сбрасываем позицию
    for (var entry in _videoControllers.entries) {
      try {
        final controller = entry.value;
        if (controller.value.isInitialized) {
          // Сбрасываем позицию на начало для всех видео, кроме нового текущего
          if (entry.key != index) {
            await controller.seekTo(Duration.zero);
            print('ShortsScreen: Reset video ${entry.key} position to start');
          }
          
          if (controller.value.isPlaying) {
            await controller.setVolume(0);
            await controller.pause();
            print('ShortsScreen: Paused video ${entry.key} (was playing, volume=0)');
          } else {
            await controller.setVolume(0);
            print('ShortsScreen: Video ${entry.key} already paused, ensured volume=0');
          }
        }
      } catch (e) {
        print('Error pausing video ${entry.key}: $e');
      }
    }

    _currentIndex = index;

    // Очищаем флаг предзагрузки для предыдущего видео
    if (index > 0) {
      _preloadStartedForIndex.remove(index - 1);
    }

    final postsProvider = context.read<PostsProvider>();
    final videoPosts = _currentTabIndex == 0 
        ? postsProvider.followingVideoPosts 
        : postsProvider.videoPosts;
    
    // ВАЖНО: Сразу начинаем предзагрузку следующего видео (не ждем)
    // Это должно начаться параллельно с инициализацией текущего видео
    _preloadNextVideos(index, videoPosts).catchError((e) {
      print('ShortsScreen: Error preloading next videos: $e');
    });
    
    // Инициализируем предыдущее видео (если оно загружено в кеш)
    if (index > 0 && index - 1 < videoPosts.length) {
      final prevPost = videoPosts[index - 1];
      final isCached = await _videoCacheService.isVideoCached(prevPost.id);
      if (isCached && !_videoControllers.containsKey(index - 1)) {
        print('ShortsScreen: Initializing previous video ${index - 1} from cache');
        _initializeControllerFromCache(index - 1, prevPost.id).catchError((e) {
          print('ShortsScreen: Error initializing previous video: $e');
        });
      }
    }
    
    // Инициализируем текущее видео (если еще не инициализировано)
    if (_currentIndex < videoPosts.length) {
      final currentController = _videoControllers[_currentIndex];
      if (currentController == null || !currentController.value.isInitialized) {
        print('ShortsScreen: Initializing current video $_currentIndex');
        await _initializeVideo(_currentIndex, videoPosts[_currentIndex], autoPlay: true);
      }
    }
    
    // Инициализируем следующее видео (если оно загружено в кеш)
    if (index + 1 < videoPosts.length) {
      final nextPost = videoPosts[index + 1];
      final isCached = await _videoCacheService.isVideoCached(nextPost.id);
      if (isCached && !_videoControllers.containsKey(index + 1)) {
        print('ShortsScreen: Initializing next video ${index + 1} from cache');
        _initializeControllerFromCache(index + 1, nextPost.id).catchError((e) {
          print('ShortsScreen: Error initializing next video: $e');
        });
      }
    }

    // Запускаем только текущее видео с включенным звуком
    // ИСПРАВЛЕНИЕ: Добавляем проверку mounted и задержку для синхронизации
    final currentController = _videoControllers[_currentIndex];
    if (currentController != null && currentController.value.isInitialized && mounted) {
      try {
        // Проверяем, что видео действительно на паузе перед запуском
        if (currentController.value.isPlaying) {
          print('ShortsScreen: Video $_currentIndex is already playing, stopping first');
          await currentController.setVolume(0);
          await currentController.pause();
          // Небольшая задержка для гарантии остановки
          await Future.delayed(const Duration(milliseconds: 150));
        }
        // Сбрасываем позицию на начало, чтобы видео всегда начиналось с начала
        await currentController.seekTo(Duration.zero);
        print('ShortsScreen: Reset current video $_currentIndex position to start');
        // Включаем звук и запускаем
        // ИСПРАВЛЕНИЕ: Убеждаемся, что звук установлен перед play
        await currentController.setVolume(1);
        // Небольшая задержка перед play для гарантии установки звука
        await Future.delayed(const Duration(milliseconds: 50));
        await currentController.play();
        // Проверяем, что звук действительно включен после play
        await Future.delayed(const Duration(milliseconds: 100));
        if (currentController.value.volume != 1.0) {
          print('ShortsScreen: WARNING - Volume was reset, fixing...');
          await currentController.setVolume(1);
        }
        print('ShortsScreen: Playing video $_currentIndex (volume=${currentController.value.volume}, isPlaying: ${currentController.value.isPlaying})');
      } catch (e) {
        print('Error playing video ${_currentIndex}: $e');
      }
    } else if (currentController == null) {
      print('ShortsScreen: WARNING - Current controller is null for index $_currentIndex');
    } else if (!currentController.value.isInitialized) {
      print('ShortsScreen: WARNING - Current controller not initialized for index $_currentIndex');
    }

    // Автоподгрузка следующей страницы при приближении к концу
    final hasMore = _currentTabIndex == 0 
        ? postsProvider.hasMoreFollowingVideoPosts 
        : postsProvider.hasMoreVideoPosts;
    
    if (_currentIndex >= videoPosts.length - 3 && hasMore && !postsProvider.isLoading) {
      print('ShortsScreen: Approaching end (index: $_currentIndex, total: ${videoPosts.length}), loading more videos');
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (_currentTabIndex == 0) {
        await postsProvider.loadFollowingVideoPosts(refresh: false, accessToken: accessToken);
      } else {
        await postsProvider.loadVideoPosts(refresh: false, accessToken: accessToken);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false, // Видео не должно подниматься с клавиатурой
      body: Consumer<PostsProvider>(
        builder: (context, postsProvider, child) {
          final videoPosts = _currentTabIndex == 0 
              ? postsProvider.followingVideoPosts 
              : postsProvider.videoPosts;

          return Column(
            children: [
              // TabBar с SafeArea для защиты от системного трея
              SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF0095F6),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    onTap: (index) {
                      // Если нажали на уже активную вкладку, обновляем ленту
                      if (index == _currentTabIndex) {
                        refreshFeed();
                      }
                    },
                    tabs: const [
                      Tab(text: 'Following'),
                      Tab(text: 'Recommendations'),
                    ],
                  ),
                ),
              ),
              // Контент
              Expanded(
                child: _buildContent(postsProvider, videoPosts),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(PostsProvider postsProvider, List<Post> videoPosts) {
    if (postsProvider.isLoading && videoPosts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0095F6),
        ),
      );
    }

    // For "Following" tab show special message if no videos
    if (_currentTabIndex == 0 && videoPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              EvaIcons.video,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No videos from following',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Follow users to see their videos here',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                _tabController.animateTo(1);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0095F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Switch to Recommendations'),
            ),
          ],
        ),
      );
    }

    // For "Recommendations" tab show standard message if no videos
    if (_currentTabIndex == 1 && videoPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              EvaIcons.video,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No videos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload your first video!',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Первое видео уже инициализируется в initializeScreen(), не нужно здесь

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: videoPosts.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final post = videoPosts[index];
        
        // УБРАЛИ инициализацию из itemBuilder - она теперь только в _onPageChanged
        // Это предотвращает множественную инициализацию

        return ShortsVideoPlayer(
          post: post,
          videoController: _videoControllers[index],
          isPlaying: index == _currentIndex && _isScreenVisible,
          onLike: () => postsProvider.likePost(post.id),
          onComment: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true, // Для контроля высоты
              useSafeArea: true,
              builder: (context) => Align(
                alignment: Alignment.bottomCenter,
                child: ShortsCommentsSheet(
                  postId: post.id,
                  post: post,
                  onCommentAdded: () {
                    postsProvider.updatePostCommentsCount(post.id, 1);
                  },
                ),
              ),
            );
          },
          onShare: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (context) => ShareVideoSheet(
                post: post,
              ),
            );
          },
        );
      },
    );
  }

  /// Умная предзагрузка следующих видео
  /// Теперь только загружает в кеш, НЕ инициализирует контроллеры
  Future<void> _preloadNextVideos(int currentIndex, List<Post> videoPosts) async {
    if (currentIndex >= videoPosts.length) return;

    try {
      // Получаем текущее видео для определения размера
      final currentPost = videoPosts[currentIndex];
      final videoUrl = currentPost.mediaUrl;
      
      // Получаем signed URL для определения размера
      String signedUrl = videoUrl;
      try {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          final apiService = ApiService();
          apiService.setAccessToken(accessToken);
          // Для определения размера используем текущий пост
          final result = await apiService.getPostMediaSignedUrl(
            mediaPath: videoUrl,
            postId: currentPost.id,
          );
          signedUrl = result['signedUrl']!;
        }
      } catch (e) {
        print('ShortsScreen: Error getting signed URL for size check: $e');
      }

      // Определяем размер видео
      final videoSize = await _videoCacheService.getVideoSize(signedUrl);
      final networkSpeed = await _networkSpeedDetector.getCurrentSpeed();

      // Определяем сколько видео предзагружать
      int preloadCount = 1; // минимум следующее видео
      
      if (videoSize != null) {
        if (videoSize < 2 * 1024 * 1024) { // < 2MB
          preloadCount = networkSpeed == NetworkSpeed.fast ? 3 : 2;
        } else if (videoSize < 5 * 1024 * 1024) { // < 5MB
          preloadCount = networkSpeed == NetworkSpeed.fast ? 2 : 1;
        }
      } else {
        // Если не удалось определить размер, используем консервативный подход
        preloadCount = networkSpeed == NetworkSpeed.fast ? 2 : 1;
      }

      print('ShortsScreen: Preloading $preloadCount videos (size: ${videoSize != null ? "${videoSize ~/ 1024}KB" : "unknown"}, speed: $networkSpeed)');

      // Предзагружаем следующие видео (только в кеш, без инициализации контроллеров)
      for (int i = 1; i <= preloadCount; i++) {
        final nextIndex = currentIndex + i;
        if (nextIndex < videoPosts.length) {
          final nextPost = videoPosts[nextIndex];
          
          // Получаем signed URL для предзагрузки
          try {
            final prefs = await SharedPreferences.getInstance();
            final accessToken = prefs.getString('access_token');
            if (accessToken != null) {
              final apiService = ApiService();
              apiService.setAccessToken(accessToken);
              final result = await apiService.getPostMediaSignedUrl(
                mediaPath: nextPost.mediaUrl,
                postId: nextPost.id, // Передаем postId
              );
              final signedUrl = result['signedUrl']!;
              final returnedPostId = result['postId'] ?? nextPost.id;
              
              // Проверяем, не закешировано ли уже по postId
              final isCached = await _videoCacheService.isVideoCached(returnedPostId);
              
              if (!isCached) {
                // Только предзагружаем в кеш, НЕ инициализируем контроллер
                print('ShortsScreen: Preloading video $nextIndex (post: ${nextPost.id}) to cache (background, no controller init)');
                _videoCacheService.preloadVideo(nextPost.id, signedUrl, priority: i).catchError((e) {
                  print('ShortsScreen: Error preloading video $nextIndex: $e');
                });
              } else {
                print('ShortsScreen: Video $nextIndex (post: ${nextPost.id}) already cached');
              }
              
              // Добавляем в очередь предзагрузки для кеширования
              final priority = i == 1 ? Priority.high : Priority.medium;
              _preloadQueue.addVideo(nextPost, priority);
            }
          } catch (e) {
            print('ShortsScreen: Error getting signed URL for preload: $e');
          }
        }
      }
    } catch (e) {
      print('ShortsScreen: Error in _preloadNextVideos: $e');
    }
  }

  /// Обработка очереди предзагрузки в фоне
  Future<void> _processPreloadQueue() async {
    if (_preloadQueue.isProcessing) return;
    
    _preloadQueue.setProcessing(true);
    
    while (_preloadQueue.getQueueSize() > 0 && _isScreenVisible) {
      final queuedVideo = _preloadQueue.getNextVideo();
      if (queuedVideo == null) break;
      
      try {
        // Получаем signed URL
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          final apiService = ApiService();
          apiService.setAccessToken(accessToken);
          final result = await apiService.getPostMediaSignedUrl(
            mediaPath: queuedVideo.post.mediaUrl,
            postId: queuedVideo.post.id, // Передаем postId
          );
          final signedUrl = result['signedUrl']!;
          
          // Предзагружаем в кеш (используем postId)
          await _videoCacheService.preloadVideo(queuedVideo.post.id, signedUrl);
          print('ShortsScreen: Preloaded video from queue: ${queuedVideo.post.id}');
        }
      } catch (e) {
        print('ShortsScreen: Error processing preload queue: $e');
      }
      
      // Небольшая задержка между загрузками
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    _preloadQueue.setProcessing(false);
  }

  /// Загрузить непросмотренные видео из очереди
  Future<void> _loadUnviewedQueue() async {
    try {
      final unviewedPosts = await _preloadQueue.loadUnviewedQueue();
      if (unviewedPosts.isEmpty) return;
      
      print('ShortsScreen: Loaded ${unviewedPosts.length} unviewed videos');
      
      // Добавляем непросмотренные видео в очередь с высоким приоритетом
      for (final post in unviewedPosts) {
        _preloadQueue.addVideo(post, Priority.low, isUnviewed: true);
      }
      
      // Предзагружаем первые 2-3 непросмотренных видео
      final networkSpeed = await _networkSpeedDetector.getCurrentSpeed();
      final preloadCount = networkSpeed == NetworkSpeed.fast ? 3 : 2;
      
      // Получаем список всех видео для определения индексов
      final postsProvider = context.read<PostsProvider>();
      final videoPosts = _currentTabIndex == 0 
          ? postsProvider.followingVideoPosts 
          : postsProvider.videoPosts;
      
      for (int i = 0; i < preloadCount && i < unviewedPosts.length; i++) {
        final post = unviewedPosts[i];
        try {
          final prefs = await SharedPreferences.getInstance();
          final accessToken = prefs.getString('access_token');
          if (accessToken != null) {
            final apiService = ApiService();
            apiService.setAccessToken(accessToken);
            final result = await apiService.getPostMediaSignedUrl(
              mediaPath: post.mediaUrl,
              postId: post.id, // Передаем postId
            );
            final signedUrl = result['signedUrl']!;
            final returnedPostId = result['postId'] ?? post.id;
            
            // Находим индекс видео в списке
            final postIndex = videoPosts.indexWhere((p) => p.id == post.id);
            if (postIndex != -1) {
              // Проверяем, не закешировано ли уже по postId
              final isCached = await _videoCacheService.isVideoCached(returnedPostId);
              if (isCached) {
                // Если уже в кеше, сразу инициализируем контроллер
                if (mounted && !_videoControllers.containsKey(postIndex)) {
                  _initializeControllerFromCache(postIndex, post.id).catchError((e) {
                    print('ShortsScreen: Error initializing controller for cached unviewed video: $e');
                  });
                }
              } else {
                // Если не в кеше, предзагружаем и затем инициализируем (используем postId)
                _videoCacheService.preloadVideo(post.id, signedUrl).then((_) async {
                  if (mounted && !_videoControllers.containsKey(postIndex)) {
                    await _initializeControllerFromCache(postIndex, post.id);
                  }
                }).catchError((e) {
                  print('ShortsScreen: Error preloading unviewed video: $e');
                });
              }
            }
          }
        } catch (e) {
          print('ShortsScreen: Error getting signed URL for unviewed video: $e');
        }
      }
    } catch (e) {
      print('ShortsScreen: Error loading unviewed queue: $e');
    }
  }

  /// Сохранить непросмотренные видео
  Future<void> _saveUnviewedVideos() async {
    try {
      final postsProvider = context.read<PostsProvider>();
      final videoPosts = _currentTabIndex == 0 
          ? postsProvider.followingVideoPosts 
          : postsProvider.videoPosts;
      
      // Находим непросмотренные видео
      final unviewedPosts = videoPosts
          .where((post) => !_viewedPostIds.contains(post.id))
          .toList();
      
      if (unviewedPosts.isNotEmpty) {
        await _preloadQueue.saveUnviewedQueue(unviewedPosts);
        print('ShortsScreen: Saved ${unviewedPosts.length} unviewed videos');
      }
    } catch (e) {
      print('ShortsScreen: Error saving unviewed videos: $e');
    }
  }
}
