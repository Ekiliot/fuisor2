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
class ShortsScreenState extends State<ShortsScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Set<int> _initializingVideos = {}; // Защита от параллельной инициализации
  final Map<int, int> _retryCounts = {}; // Счетчики попыток для retry
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeAllControllers();
    _pageController.dispose();
    super.dispose();
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

    // Обновляем посты
    final postsProvider = context.read<PostsProvider>();
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);

    // ВАЖНО: Устанавливаем _isScreenVisible = true, так как мы остаемся на экране Shorts
    _isScreenVisible = true;

    // Переинициализируем первое видео только если экран видим
    if (mounted && _isScreenVisible && postsProvider.videoPosts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initializeVideo(0, postsProvider.videoPosts[0], autoPlay: true);
      });
    }
  }

  bool _isScreenVisible = false;

  // Метод для инициализации экрана при первом открытии
  Future<void> initializeScreen() async {
    if (_isScreenVisible) {
      // Если уже видим, просто возобновляем текущее видео
      await resumeCurrentVideo();
      return;
    }
    
    _isScreenVisible = true;
    
    final postsProvider = context.read<PostsProvider>();
    if (postsProvider.videoPosts.isEmpty) {
      // Получаем токен из SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);
    }
    
    // Инициализируем первое видео только если посты уже загружены
    if (mounted && postsProvider.videoPosts.isNotEmpty && !_videoControllers.containsKey(0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initializeVideo(0, postsProvider.videoPosts[0], autoPlay: true);
      });
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
      if (autoPlay && index == _currentIndex && _isScreenVisible) {
        await controller.setVolume(1);
        await controller.play();
        print('ShortsScreen: Video $index initialized and auto-playing (volume=1)');
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
    final videoPosts = postsProvider.videoPosts;
    
    if (_currentIndex < videoPosts.length && !_videoControllers.containsKey(_currentIndex)) {
      print('ShortsScreen: Initializing current video $_currentIndex');
      await _initializeVideo(_currentIndex, videoPosts[_currentIndex]);
    }

    // Запускаем только текущее видео с включенным звуком
    final currentController = _videoControllers[_currentIndex];
    if (currentController != null && currentController.value.isInitialized) {
      try {
        // Проверяем, что видео действительно на паузе перед запуском
        if (currentController.value.isPlaying) {
          print('ShortsScreen: Video $_currentIndex is already playing, stopping first');
          await currentController.setVolume(0);
          await currentController.pause();
          // Небольшая задержка для гарантии остановки
          await Future.delayed(const Duration(milliseconds: 100));
        }
        // Сбрасываем позицию на начало, чтобы видео всегда начиналось с начала
        await currentController.seekTo(Duration.zero);
        print('ShortsScreen: Reset current video $_currentIndex position to start');
        // Включаем звук и запускаем
        await currentController.setVolume(1);
        await currentController.play();
        print('ShortsScreen: Playing video $_currentIndex (volume=1, isPlaying: ${currentController.value.isPlaying})');
      } catch (e) {
        print('Error playing video ${_currentIndex}: $e');
      }
    }

    // Предзагружаем соседние видео (они будут на паузе с выключенным звуком)
    if (_currentIndex + 1 < videoPosts.length && !_videoControllers.containsKey(_currentIndex + 1)) {
      _initializeVideo(_currentIndex + 1, videoPosts[_currentIndex + 1]);
    }
    if (_currentIndex - 1 >= 0 && !_videoControllers.containsKey(_currentIndex - 1)) {
      _initializeVideo(_currentIndex - 1, videoPosts[_currentIndex - 1]);
    }

    // Автоподгрузка следующей страницы при приближении к концу
    if (_currentIndex >= videoPosts.length - 3 && postsProvider.hasMoreVideoPosts && !postsProvider.isLoading) {
      print('ShortsScreen: Approaching end (index: $_currentIndex, total: ${videoPosts.length}), loading more videos');
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      await postsProvider.loadVideoPosts(refresh: false, accessToken: accessToken);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<PostsProvider>(
        builder: (context, postsProvider, child) {
          final videoPosts = postsProvider.videoPosts;

          if (postsProvider.isLoading && videoPosts.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
          ),
            );
          }

          if (videoPosts.isEmpty) {
            return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
                  const Icon(
              EvaIcons.videoOutline,
              size: 64,
              color: Colors.grey,
            ),
                  const SizedBox(height: 16),
                  const Text(
                    'No videos yet',
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
                    isScrollControlled: true,
                    builder: (context) => ShortsCommentsSheet(
                      postId: post.id,
                      post: post,
                      onCommentAdded: () {
                        postsProvider.updatePostCommentsCount(post.id, 1);
                      },
                    ),
                  );
                },
                onShare: () {
                  // TODO: Поделиться видео
                },
              );
            },
          );
        },
      ),
    );
  }
}
