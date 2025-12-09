import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/user.dart' show Post;
import '../services/api_service.dart';
import '../widgets/cached_network_image_with_signed_url.dart';
import '../widgets/shorts_comments_sheet.dart';
import '../widgets/app_notification.dart';

class GeoStoriesViewer extends StatefulWidget {
  final Post initialPost;
  final List<Post> posts;

  const GeoStoriesViewer({
    super.key,
    required this.initialPost,
    required this.posts,
  });

  @override
  State<GeoStoriesViewer> createState() => _GeoStoriesViewerState();
}

class _GeoStoriesViewerState extends State<GeoStoriesViewer>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late List<AnimationController> _progressControllers;
  late List<Animation<double>> _progressAnimations;
  int _currentStoryIndex = 0;
  bool _isPaused = false;
  VideoPlayerController? _videoController;
  Timer? _photoTimer;
  Map<String, bool> _likedPosts = {}; // Track liked posts
  Map<String, int> _likesCount = {}; // Track likes count
  bool _isLiking = false;

  @override
  void initState() {
    super.initState();
    // Находим индекс начального поста
    _currentStoryIndex = widget.posts.indexWhere(
      (post) => post.id == widget.initialPost.id,
    );
    if (_currentStoryIndex == -1) {
      _currentStoryIndex = 0;
    }

    _pageController = PageController(initialPage: _currentStoryIndex);

    // Инициализируем контроллеры прогресса для каждого стори
    _progressControllers = List.generate(
      widget.posts.length,
      (index) => AnimationController(
        duration: const Duration(seconds: 5), // 5 секунд для фото
        vsync: this,
      ),
    );

    _progressAnimations = _progressControllers.map((controller) {
      final animation = Tween<double>(begin: 0.0, end: 1.0).animate(controller);
      // Добавляем слушатель для автоматического перехода к следующему стори
      animation.addStatusListener((status) {
        if (status == AnimationStatus.completed && !_isPaused) {
          _nextStory();
        }
      });
      return animation;
    }).toList();

    // Инициализируем состояние лайков
    for (var post in widget.posts) {
      _likedPosts[post.id] = post.isLiked;
      _likesCount[post.id] = post.likesCount;
    }

    // Загружаем первый стори
    _loadStory(_currentStoryIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _progressControllers) {
      controller.dispose();
    }
    _videoController?.dispose();
    _photoTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStory(int index) async {
    if (index < 0 || index >= widget.posts.length) {
      // Если индекс невалидный, закрываем viewer
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    try {
      final post = widget.posts[index];

      // Останавливаем предыдущий таймер/видео
      _photoTimer?.cancel();
      _videoController?.pause();
      _videoController?.dispose();
      _videoController = null;

      // Сбрасываем прогресс для всех сторис
      for (var controller in _progressControllers) {
        controller.reset();
      }

      setState(() {
        _currentStoryIndex = index;
        _isPaused = false;
      });

      if (post.mediaType == 'video') {
        // Загружаем видео
        await _loadVideo(post);
      } else {
        // Показываем фото на 5 секунд
        // Прогресс-бар автоматически перейдет к следующему стори через слушатель
        _progressControllers[index].forward();
      }
    } catch (e) {
      print('Error loading story: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка загрузки стори: $e',
        );
        // Переходим к следующему стори при ошибке
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _nextStory();
          }
        });
      }
    }
  }

  Future<void> _loadVideo(Post post) async {
    try {
      // Получаем signed URL для видео
      final apiService = ApiService();
      final accessToken = await _getAccessToken();
      if (accessToken != null) {
        apiService.setAccessToken(accessToken);
      }

      // Получаем signed URL для приватного видео
      final signedUrlData = await apiService.getPostMediaSignedUrl(
        mediaPath: post.mediaUrl,
        postId: post.id,
      );
      final videoUrl = signedUrlData['signedUrl'] ?? post.mediaUrl;
      
      print('GeoStoriesViewer: Loading video from: $videoUrl');
      
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _videoController!.initialize();

      if (mounted) {
        setState(() {});
        _videoController!.play();
        _videoController!.addListener(_onVideoEnd);
        
        // Запускаем прогресс-бар
        _progressControllers[_currentStoryIndex].duration = _videoController!.value.duration;
        _progressControllers[_currentStoryIndex].forward();
      }
    } catch (e) {
      print('Error loading video: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка загрузки видео: $e',
        );
        // Переходим к следующему стори при ошибке
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _nextStory();
          }
        });
      }
    }
  }

  void _onVideoEnd() {
    if (_videoController != null &&
        _videoController!.value.position >= _videoController!.value.duration) {
      _nextStory();
    }
  }

  void _nextStory() {
    if (!mounted) return;
    
    if (_currentStoryIndex < widget.posts.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Закрываем viewer если это последний стори
      // Останавливаем все анимации и таймеры перед закрытием
      _photoTimer?.cancel();
      _videoController?.pause();
      _videoController?.dispose();
      _videoController = null;
      for (var controller in _progressControllers) {
        controller.stop();
      }
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
      Navigator.of(context).pop();
        }
      });
    }
  }

  void _previousStory() {
    if (_currentStoryIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });

    if (_isPaused) {
      _progressControllers[_currentStoryIndex].stop();
      _videoController?.pause();
    } else {
      _progressControllers[_currentStoryIndex].forward();
      _videoController?.play();
    }
  }

  Future<String?> _getAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token');
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPost = widget.posts[_currentStoryIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header с прогресс-баром и информацией о пользователе
            Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                  // Прогресс-бар с одинаковым градиентом для каждой полоски
                    Row(
                      children: List.generate(
                        widget.posts.length,
                        (index) => Expanded(
                          child: Container(
                            margin: EdgeInsets.only(
                            right: index < widget.posts.length - 1 ? 3 : 0,
                            ),
                          height: 3,
                            decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                            ),
                            child: AnimatedBuilder(
                              animation: _progressAnimations[index],
                              builder: (context, child) {
                              final progress = index == _currentStoryIndex
                                      ? _progressAnimations[index].value
                                      : index < _currentStoryIndex
                                          ? 1.0
                                      : 0.0;
                              
                              return Stack(
                                children: [
                                  // Фон
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  // Прогресс с одинаковым градиентом для каждой полоски
                                  FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF00D4FF),
                                            Color(0xFF0099FF),
                                            Color(0xFF0066FF),
                                          ],
                                          stops: [0.0, 0.5, 1.0],
                                        ),
                                        borderRadius: BorderRadius.circular(2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF0099FF).withOpacity(0.5),
                                            blurRadius: 4,
                                            spreadRadius: 0.5,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),

                    // Заголовок с информацией о пользователе
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: currentPost.user?.avatarUrl != null
                              ? NetworkImage(currentPost.user!.avatarUrl!)
                              : null,
                          child: currentPost.user?.avatarUrl == null
                              ? const Icon(EvaIcons.personOutline, size: 16)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentPost.user?.username ?? 'Unknown',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _formatTime(currentPost.createdAt),
                                style: GoogleFonts.inter(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(EvaIcons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
            ),

            // Контент сторис (фото/видео) ниже header
            Expanded(
              child: Column(
                children: [
                  // Видео/фото сразу под header
                  Expanded(
                    child: GestureDetector(
                      onTapDown: (details) {
                        final screenWidth = MediaQuery.of(context).size.width;
                        final tapX = details.globalPosition.dx;

                        if (tapX < screenWidth / 3) {
                          // Тап слева - предыдущий стори
                          _previousStory();
                        } else if (tapX > screenWidth * 2 / 3) {
                          // Тап справа - следующий стори
                          _nextStory();
                        }
                      },
                      onLongPressStart: (_) {
                        // Длительное нажатие - пауза
                        _togglePause();
                      },
                      onLongPressEnd: (_) {
                        // Отпускание - продолжение
                        _togglePause();
                      },
                      onVerticalDragEnd: (details) {
                        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
                          // Свайп вниз - закрыть
                          Navigator.of(context).pop();
                        }
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          _loadStory(index);
                        },
                        itemCount: widget.posts.length,
                        itemBuilder: (context, index) {
                          final post = widget.posts[index];
                          return _buildStoryContent(post);
                        },
                      ),
                    ),
                  ),
                  
                  // Кнопки внизу справа (горизонтальный список)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Кнопка лайк
                        GestureDetector(
                          onTap: _isLiking ? null : _toggleLike,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _likedPosts[currentPost.id] == true
                                  ? EvaIcons.heart
                                  : EvaIcons.heartOutline,
                              color: _likedPosts[currentPost.id] == true
                                  ? const Color(0xFFED4956)
                                  : Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Кнопка комментариев
                        GestureDetector(
                          onTap: () => _openComments(currentPost),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              EvaIcons.messageCircleOutline,
                              color: Colors.white,
                              size: 24,
                            ),
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

  Future<void> _toggleLike() async {
    if (_isLiking) return;
    
    final currentPost = widget.posts[_currentStoryIndex];
    final isLiked = _likedPosts[currentPost.id] ?? false;
    
    setState(() {
      _isLiking = true;
      _likedPosts[currentPost.id] = !isLiked;
      _likesCount[currentPost.id] = (_likesCount[currentPost.id] ?? 0) + (isLiked ? -1 : 1);
    });

    try {
      final apiService = ApiService();
      final accessToken = await _getAccessToken();
      if (accessToken != null) {
        apiService.setAccessToken(accessToken);
      }

      final result = await apiService.likePost(currentPost.id);
      
      if (mounted) {
        setState(() {
          _likedPosts[currentPost.id] = result['isLiked'] ?? !isLiked;
          _likesCount[currentPost.id] = result['likesCount'] ?? _likesCount[currentPost.id] ?? 0;
          _isLiking = false;
        });
      }
    } catch (e) {
      print('Error toggling like: $e');
      if (mounted) {
        setState(() {
          _likedPosts[currentPost.id] = isLiked; // Revert on error
          _likesCount[currentPost.id] = (_likesCount[currentPost.id] ?? 0) - (isLiked ? 1 : -1);
          _isLiking = false;
        });
      }
    }
  }

  void _openComments(Post post) {
    // Ставим на паузу при открытии комментариев
    if (!_isPaused) {
      _togglePause();
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShortsCommentsSheet(
        postId: post.id,
        post: post,
        onCommentAdded: () {
          // Можно обновить счетчик комментариев если нужно
        },
      ),
    ).then((_) {
      // Продолжаем воспроизведение после закрытия комментариев
      if (_isPaused) {
        _togglePause();
      }
    });
  }

  Widget _buildStoryContent(Post post) {
    final screenSize = MediaQuery.of(context).size;
    const borderRadius = 20.0;
    
    if (post.mediaType == 'video') {
      if (_videoController != null &&
          _videoController!.value.isInitialized &&
          _currentStoryIndex == widget.posts.indexOf(post)) {
        // Используем реальный aspect ratio из видео
        final videoAspectRatio = _videoController!.value.aspectRatio;
        
        // Видео должно заполнять весь экран, но не выходить за края
        // Используем FittedBox с BoxFit.cover для заполнения экрана
        // ClipRRect обрежет все, что выходит за края экрана
        return ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                // Используем размеры, которые гарантируют заполнение экрана
                // Если видео шире экрана - используем большую ширину для заполнения по высоте
                // Если видео уже экрана - используем большую высоту для заполнения по ширине
                width: videoAspectRatio > (screenSize.width / screenSize.height)
                    ? screenSize.height * videoAspectRatio
                    : screenSize.width,
                height: videoAspectRatio > (screenSize.width / screenSize.height)
                    ? screenSize.height
                    : screenSize.width / videoAspectRatio,
            child: VideoPlayer(_videoController!),
              ),
            ),
          ),
        );
      } else {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
    } else {
      // Фото - используем CachedNetworkImageWithSignedUrl для получения signed URL
      // Заполняем весь экран с закругленными краями
      return ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
            child: CachedNetworkImageWithSignedUrl(
              imageUrl: post.mediaUrl,
              postId: post.id,
            width: screenSize.width,
            height: screenSize.height,
              fit: BoxFit.cover,
              placeholder: (context) => Container(
              width: screenSize.width,
              height: screenSize.height,
                color: Colors.black,
                child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (context, url, error) => Container(
              width: screenSize.width,
              height: screenSize.height,
                color: Colors.black,
                child: const Center(
              child: Icon(EvaIcons.imageOutline, color: Colors.white, size: 64),
              ),
            ),
          ),
        ),
      );
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'только что';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}м назад';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}ч назад';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}д назад';
    } else {
      return '${dateTime.day}.${dateTime.month}.${dateTime.year}';
    }
  }
}

