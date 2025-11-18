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
class ShortsScreenState extends State<ShortsScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  final Map<int, VideoPlayerController> _videoControllers = {};

  // Метод для остановки всех видео (при уходе с экрана)
  Future<void> pauseAllVideos() async {
    _isScreenVisible = false;
    for (var controller in _videoControllers.values) {
      try {
        await controller.setVolume(0);
        await controller.pause();
      } catch (e) {
        print('Error pausing video: $e');
      }
    }
  }

  // Метод для обновления ленты при двойном нажатии
  Future<void> refreshFeed() async {
    // Останавливаем все видео перед очисткой
    for (var controller in _videoControllers.values) {
      try {
        await controller.setVolume(0);
        await controller.pause();
      } catch (e) {
        print('Error pausing video in refreshFeed: $e');
      }
    }

    // Очищаем контроллеры
    _disposeAllControllers();

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

    // Переинициализируем первое видео только если экран видим
    if (mounted && _isScreenVisible && postsProvider.videoPosts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initializeVideo(0, postsProvider.videoPosts[0]);
        // Запускаем первое видео после инициализации
        final firstController = _videoControllers[0];
        if (firstController != null && _currentIndex == 0) {
          try {
            await firstController.setVolume(1);
            await firstController.play();
            print('ShortsScreen: Playing first video 0 after refresh (volume=1)');
          } catch (e) {
            print('Error playing first video after refresh: $e');
          }
        }
      });
    }
  }

  bool _isScreenVisible = false;

  @override
  void initState() {
    super.initState();
    // Не загружаем посты и не инициализируем видео в initState
    // Это будет сделано только когда экран станет видимым
  }

  // Метод для инициализации экрана при первом открытии
  Future<void> initializeScreen() async {
    if (_isScreenVisible) return; // Уже инициализирован
    
    _isScreenVisible = true;
    
    final postsProvider = context.read<PostsProvider>();
    if (postsProvider.videoPosts.isEmpty) {
      // Получаем токен из SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      await postsProvider.loadVideoPosts(refresh: true, accessToken: accessToken);
    }
    
    // Инициализируем первое видео только если посты уже загружены
    // Используем autoPlay=true для автоматического запуска первого видео
    if (mounted && postsProvider.videoPosts.isNotEmpty && !_videoControllers.containsKey(0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initializeVideo(0, postsProvider.videoPosts[0], autoPlay: true);
      });
    }
  }

  @override
  void dispose() {
    _disposeAllControllers();
    _pageController.dispose();
    super.dispose();
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

  Future<void> _initializeVideo(int index, Post post, {bool autoPlay = false}) async {
    if (_videoControllers.containsKey(index)) {
      print('ShortsScreen: Video $index already initialized, skipping');
      return; // Уже инициализирован
    }

    // Не инициализируем видео, если экран не видим
    if (!_isScreenVisible) {
      print('ShortsScreen: Screen not visible, skipping initialization of video $index');
      return;
    }

    print('ShortsScreen: Starting initialization of video $index');
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(post.mediaUrl),
      );
      
      await controller.initialize();
      controller.setLooping(true);
      
      if (mounted) {
        setState(() {
          _videoControllers[index] = controller;
        });
        
        // ВСЕГДА сначала ставим на паузу с выключенным звуком
        await controller.setVolume(0);
        await controller.pause();
        
        // Автозапуск только если явно указано и это текущее видео
        if (autoPlay && index == _currentIndex && _isScreenVisible) {
          await controller.setVolume(1);
          await controller.play();
          print('ShortsScreen: Video $index initialized and auto-playing (volume=1)');
        } else {
          print('ShortsScreen: Video $index initialized and paused (current is $_currentIndex, isPlaying: ${controller.value.isPlaying})');
        }
      }
    } catch (e) {
      print('Error initializing video $index: $e');
    }
  }

  void _onPageChanged(int index) async {
    print('ShortsScreen: Page changed from $_currentIndex to $index');
    
    // Останавливаем ВСЕ видео (включая текущее) с выключенным звуком
    for (var entry in _videoControllers.entries) {
      try {
        final controller = entry.value;
        // Выключаем звук и ставим на паузу, звук остается на 0
        if (controller.value.isPlaying) {
          await controller.setVolume(0);
          await controller.pause();
          print('ShortsScreen: Paused video ${entry.key} (was playing, volume=0)');
        } else {
          // Убеждаемся, что звук выключен даже если уже на паузе
          await controller.setVolume(0);
          print('ShortsScreen: Video ${entry.key} already paused, ensured volume=0');
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
    if (currentController != null) {
      try {
        // Проверяем, что видео действительно на паузе перед запуском
        if (currentController.value.isPlaying) {
          print('ShortsScreen: Video $_currentIndex is already playing, stopping first');
          await currentController.setVolume(0);
          await currentController.pause();
          // Небольшая задержка для гарантии остановки
          await Future.delayed(const Duration(milliseconds: 100));
        }
        // Включаем звук и запускаем
        await currentController.setVolume(1);
        await currentController.play();
        print('ShortsScreen: Playing video $_currentIndex (volume=1, isPlaying: ${currentController.value.isPlaying})');
      } catch (e) {
        print('Error playing video ${_currentIndex}: $e');
      }
    } else {
      print('ShortsScreen: Controller for video $_currentIndex is null after initialization attempt');
    }

    // Предзагружаем соседние видео (они будут на паузе с выключенным звуком)
    if (_currentIndex + 1 < videoPosts.length) {
      _initializeVideo(_currentIndex + 1, videoPosts[_currentIndex + 1]);
    }
    if (_currentIndex - 1 >= 0) {
      _initializeVideo(_currentIndex - 1, videoPosts[_currentIndex - 1]);
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
              
              // Инициализируем видео при необходимости, но только если экран видим
              // НЕ инициализируем видео 0 здесь - оно уже инициализируется в initializeScreen()
              if (_isScreenVisible && index != 0 && !_videoControllers.containsKey(index)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _initializeVideo(index, post);
                });
              }

              return ShortsVideoPlayer(
                post: post,
                videoController: _videoControllers[index],
                isPlaying: index == _currentIndex,
                onLike: () => postsProvider.likePost(post.id),
                onComment: () {
                  // Открыть модальное окно комментариев
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (context) => ShortsCommentsSheet(
                      postId: post.id,
                      post: post,
                      onCommentAdded: () {
                        // Обновляем счетчик комментариев в посте через provider
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
