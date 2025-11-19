import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart' show Post;
import '../providers/posts_provider.dart';
import '../widgets/shorts_video_player.dart';
import '../widgets/shorts_comments_sheet.dart';

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
  int _currentTabIndex = 0; // 0 = Подписки, 1 = Рекомендации
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Set<int> _initializingVideos = {}; // Защита от параллельной инициализации
  final Map<int, int> _retryCounts = {}; // Счетчики попыток для retry
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Инициализируем TabController с начальным индексом 0 (Подписки)
    _tabController = TabController(initialIndex: 0, length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Устанавливаем начальную вкладку на Подписки
    _currentTabIndex = 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _disposeAllControllers();
    _pageController.dispose();
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
      // Подписки
      print('ShortsScreen: Loading following video posts');
      await postsProvider.loadFollowingVideoPosts(refresh: true, accessToken: accessToken);
      print('ShortsScreen: Loaded ${postsProvider.followingVideoPosts.length} following video posts');
    } else {
      // Рекомендации
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

  // Метод для навигации к конкретному посту
  Future<void> navigateToPost(Post targetPost) async {
    print('ShortsScreen: Navigating to post: ${targetPost.id}');
    
    final postsProvider = context.read<PostsProvider>();
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    
    // Загружаем видео посты, если они еще не загружены
    if (postsProvider.followingVideoPosts.isEmpty) {
      await postsProvider.loadFollowingVideoPosts(refresh: true, accessToken: accessToken);
    }
    if (postsProvider.videoPosts.isEmpty) {
      await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);
    }
    
    // Ищем пост в обеих вкладках
    int? foundIndex;
    int targetTabIndex = 0;
    
    // Проверяем вкладку "Подписки"
    final followingIndex = postsProvider.followingVideoPosts.indexWhere((p) => p.id == targetPost.id);
    if (followingIndex != -1) {
      foundIndex = followingIndex;
      targetTabIndex = 0;
    } else {
      // Проверяем вкладку "Рекомендации"
      final recommendedIndex = postsProvider.videoPosts.indexWhere((p) => p.id == targetPost.id);
      if (recommendedIndex != -1) {
        foundIndex = recommendedIndex;
        targetTabIndex = 1;
      }
    }
    
    if (foundIndex != null && mounted) {
      // Переключаемся на нужную вкладку
      if (_currentTabIndex != targetTabIndex) {
        _tabController.animateTo(targetTabIndex);
        await Future.delayed(const Duration(milliseconds: 300)); // Ждем переключения вкладки
      }
      
      // Устанавливаем индекс и переключаемся на нужную страницу
      setState(() {
        _currentIndex = foundIndex!;
        _currentTabIndex = targetTabIndex;
        _isScreenVisible = true;
      });
      
      // Переключаемся на нужную страницу в PageController
      if (_pageController.hasClients) {
        await _pageController.animateToPage(
          foundIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      
      // Инициализируем и запускаем видео
      final videoPosts = targetTabIndex == 0 
          ? postsProvider.followingVideoPosts 
          : postsProvider.videoPosts;
      
      if (foundIndex < videoPosts.length) {
        await _initializeVideo(foundIndex, videoPosts[foundIndex], autoPlay: true);
      }
    } else {
      print('ShortsScreen: Post ${targetPost.id} not found in video posts');
      // Если пост не найден, просто инициализируем экран
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
        // Проверяем, нужно ли инициализировать видео для текущего индекса
        if (!_videoControllers.containsKey(_currentIndex)) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (_currentIndex < videoPosts.length) {
              await _initializeVideo(_currentIndex, videoPosts[_currentIndex], autoPlay: true);
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

  Future<void> _initializeVideo(int index, Post post, {bool autoPlay = false, int retryAttempt = 0}) async {
    // Защита от параллельной инициализации
    if (_initializingVideos.contains(index)) {
      print('ShortsScreen: Video $index is already initializing, skipping');
      return;
    }

    if (_videoControllers.containsKey(index)) {
      print('ShortsScreen: Video $index already initialized, skipping');
      return;
    }

    // Не инициализируем видео, если экран не видим
    if (!_isScreenVisible) {
      print('ShortsScreen: Screen not visible, skipping initialization of video $index');
      return;
    }

    _initializingVideos.add(index);
    print('ShortsScreen: Starting initialization of video $index (attempt ${retryAttempt + 1})');

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(post.mediaUrl),
      );
      
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

  void _onPageChanged(int index) async {
    print('ShortsScreen: Page changed from $_currentIndex to $index');
    
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

    // Предзагружаем текущее видео, если оно еще не инициализировано
    final postsProvider = context.read<PostsProvider>();
    final videoPosts = _currentTabIndex == 0 
        ? postsProvider.followingVideoPosts 
        : postsProvider.videoPosts;
    
    if (_currentIndex < videoPosts.length && !_videoControllers.containsKey(_currentIndex)) {
      print('ShortsScreen: Initializing current video $_currentIndex');
      await _initializeVideo(_currentIndex, videoPosts[_currentIndex]);
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

    // Предзагружаем соседние видео (они будут на паузе с выключенным звуком)
    if (_currentIndex + 1 < videoPosts.length && !_videoControllers.containsKey(_currentIndex + 1)) {
      _initializeVideo(_currentIndex + 1, videoPosts[_currentIndex + 1]);
    }
    if (_currentIndex - 1 >= 0 && !_videoControllers.containsKey(_currentIndex - 1)) {
      _initializeVideo(_currentIndex - 1, videoPosts[_currentIndex - 1]);
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
                      Tab(text: 'Подписки'),
                      Tab(text: 'Рекомендации'),
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

    // Для вкладки "Подписки" показываем специальное сообщение, если видео нет
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
              'Нет видео от подписок',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Подпишитесь на пользователей, чтобы видеть их видео здесь',
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
              child: const Text('Переключиться на рекомендации'),
            ),
          ],
        ),
      );
    }

    // Для вкладки "Рекомендации" показываем стандартное сообщение, если видео нет
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
              'Нет видео',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Загрузите свое первое видео!',
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
            // TODO: Поделиться видео
          },
        );
      },
    );
  }
}
