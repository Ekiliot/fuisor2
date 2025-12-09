import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart' show Post, LocationInfo;
import '../providers/posts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../screens/profile_screen.dart';
import '../screens/edit_post_screen.dart';
import '../widgets/app_notification.dart';
import '../widgets/cached_network_image_with_signed_url.dart';

class ShortsVideoPlayer extends StatefulWidget {
  final Post post;
  final VideoPlayerController? videoController;
  final bool isPlaying;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback? onCommentCountChanged;

  const ShortsVideoPlayer({
    super.key,
    required this.post,
    this.videoController,
    required this.isPlaying,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    this.onCommentCountChanged,
  });

  @override
  State<ShortsVideoPlayer> createState() => _ShortsVideoPlayerState();
}

class _ShortsVideoPlayerState extends State<ShortsVideoPlayer> {
  bool _isLiked = false;
  bool _isSaved = false;
  bool _showControls = false;
  bool _showHeartAnimation = false;
  DateTime? _lastTapTime;
  static const _doubleTapDelay = Duration(milliseconds: 300);
  bool _isDeleting = false;
  
  // Для отслеживания предыдущих значений счетчиков для анимации
  int _previousLikesCount = 0;
  int _previousCommentsCount = 0;
  
  // Состояние подписки
  bool? _isFollowing;
  bool _isMutualFollow = false; // Взаимная подписка
  bool _isCheckingFollowStatus = false;
  bool _isTogglingFollow = false;
  List<Offset> _heartParticles = []; // Частицы для анимации лайка
  
  // Для индикатора прогресса и перемотки
  bool _isDraggingProgress = false;
  double _progressValue = 0.0;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isProgressBarExpanded = false; // Состояние увеличения прогресс-бара
  
  // Для долгого нажатия (х2 скорость)
  bool _isLongPressing = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _isSaved = widget.post.isSaved;
    _previousLikesCount = widget.post.likesCount;
    _previousCommentsCount = widget.post.commentsCount;
    _checkFollowStatus();
    
    // Слушаем изменения позиции видео для обновления прогресса (только для видео)
    if (widget.post.mediaType == 'video') {
      widget.videoController?.addListener(_updateProgress);
      
      // Инициализируем длительность, если видео уже загружено
      if (widget.videoController != null && widget.videoController!.value.isInitialized) {
        _totalDuration = widget.videoController!.value.duration;
        _currentPosition = widget.videoController!.value.position;
        if (_totalDuration.inMilliseconds > 0) {
          _progressValue = _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
        }
      }
    }
  }
  
  @override
  void dispose() {
    // Удаляем listener только для видео
    if (widget.post.mediaType == 'video') {
      widget.videoController?.removeListener(_updateProgress);
    }
    super.dispose();
  }
  
  
  void _updateProgress() {
    if (widget.videoController != null && 
        widget.videoController!.value.isInitialized &&
        !_isDraggingProgress) {
      final position = widget.videoController!.value.position;
      final duration = widget.videoController!.value.duration;
      if (duration.inMilliseconds > 0) {
        setState(() {
          _currentPosition = position;
          _totalDuration = duration; // Всегда обновляем длительность
          _progressValue = position.inMilliseconds / duration.inMilliseconds;
        });
      }
    }
  }
  
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  String _formatTimeDisplay() {
    final current = _isDraggingProgress 
        ? Duration(milliseconds: (_progressValue * _totalDuration.inMilliseconds).round())
        : _currentPosition;
    return '${_formatDuration(current)}/${_formatDuration(_totalDuration)}';
  }
  
  Future<void> _checkFollowStatus() async {
    if (widget.post.user == null) return;
    
    try {
      // Получаем текущего пользователя из AuthProvider
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      final authorId = widget.post.userId; // ID автора поста
      final authorUserId = widget.post.user!.id; // ID из объекта user
      
      // Не показываем кнопку подписки для собственного профиля
      // Проверяем оба варианта: userId поста и user.id
      if (currentUser != null && 
          (currentUser.id == authorId || currentUser.id == authorUserId)) {
        setState(() {
          _isFollowing = null; // null означает, что кнопка не должна отображаться
        });
        print('ShortsVideoPlayer: Own video detected, hiding follow button');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        setState(() {
          _isFollowing = false;
        });
        return;
      }
      
      setState(() {
        _isCheckingFollowStatus = true;
      });
      
      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      // Используем authorUserId для проверки статуса подписки
      final isFollowing = await apiService.checkFollowStatus(authorUserId);
      
      // Проверяем взаимную подписку (подписан ли автор на текущего пользователя)
      bool isMutual = false;
      if (isFollowing && currentUser != null) {
        try {
          // Проверяем, подписан ли автор на текущего пользователя
          // Используем прямой HTTP запрос от имени автора (но это невозможно без его токена)
          // Вместо этого проверим через API, подписан ли текущий пользователь на автора
          // и наоборот - для этого нужен endpoint, который проверяет взаимную подписку
          // Пока упростим - проверим через существующий API
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('access_token');
          if (token != null) {
            // Проверяем обратное направление: подписан ли автор на текущего пользователя
            // Для этого нужно сделать запрос от имени автора, что невозможно
            // Поэтому используем упрощенный подход - проверяем через mutual followers endpoint
            final response = await http.get(
              Uri.parse('${ApiService.baseUrl}/users/mutual-followers'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            );
            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final mutualFollowers = data['mutualFollowers'] as List?;
              if (mutualFollowers != null) {
                isMutual = mutualFollowers.any((user) => user['id'] == authorUserId);
              }
            }
          }
        } catch (e) {
          print('Error checking mutual follow: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
          _isMutualFollow = isMutual;
          _isCheckingFollowStatus = false;
        });
      }
    } catch (e) {
      print('Error checking follow status: $e');
      if (mounted) {
        setState(() {
          _isFollowing = false;
          _isCheckingFollowStatus = false;
        });
      }
    }
  }
  
  Future<void> _toggleFollow() async {
    if (widget.post.user == null || _isTogglingFollow) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        if (mounted) {
          AppNotification.showError(context, 'Please login to follow users');
        }
        return;
      }
      
      setState(() {
        _isTogglingFollow = true;
      });
      
      final wasFollowing = _isFollowing ?? false;
      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      
      // Optimistically update UI
      setState(() {
        _isFollowing = !wasFollowing;
      });
      
      if (wasFollowing) {
        await apiService.unfollowUser(widget.post.user!.id);
      } else {
        await apiService.followUser(widget.post.user!.id);
      }
      
      if (mounted) {
        setState(() {
          _isTogglingFollow = false;
        });
      }
    } catch (e) {
      print('Error toggling follow: $e');
      // Revert optimistic update
      if (mounted) {
        setState(() {
          _isFollowing = !(_isFollowing ?? false);
          _isTogglingFollow = false;
        });
        AppNotification.showError(
          context,
          'Failed to ${_isFollowing == true ? "unfollow" : "follow"}: $e',
        );
      }
    }
  }

  @override
  void didUpdateWidget(ShortsVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Обновляем listener при изменении контроллера (только для видео)
    if (widget.post.mediaType == 'video') {
      if (oldWidget.videoController != widget.videoController) {
        oldWidget.videoController?.removeListener(_updateProgress);
        widget.videoController?.addListener(_updateProgress);
        
        // Обновляем длительность при изменении контроллера
        if (widget.videoController != null && widget.videoController!.value.isInitialized) {
          _totalDuration = widget.videoController!.value.duration;
          _currentPosition = widget.videoController!.value.position;
          if (_totalDuration.inMilliseconds > 0) {
            _progressValue = _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
          }
        }
      }
      
      // Обновляем состояние воспроизведения только для видео
      if (oldWidget.isPlaying != widget.isPlaying) {
        if (widget.isPlaying && widget.videoController != null) {
          // При воспроизведении включаем звук и запускаем
          widget.videoController!.setVolume(1);
          widget.videoController!.play();
        } else if (widget.videoController != null) {
          // При паузе выключаем звук и останавливаем, звук остается на 0
          widget.videoController!.setVolume(0);
          widget.videoController!.pause();
        }
      }
    }
  }

  void _togglePlayPause() async {
    if (widget.videoController == null) return;
    
    if (widget.videoController!.value.isPlaying) {
      // Останавливаем звук перед паузой и оставляем на 0
      await widget.videoController!.setVolume(0);
      await widget.videoController!.pause();
      // Звук остается на 0 пока видео на паузе
    } else {
      // При воспроизведении включаем звук и запускаем
      await widget.videoController!.setVolume(1);
      await widget.videoController!.play();
    }
  }

  void _handleDoubleTap() {
    print('ShortsVideoPlayer: Double tap detected - liking post ${widget.post.id}');
    print('ShortsVideoPlayer: Current like status: $_isLiked');
    
    // Переключаем лайк
    setState(() {
      _isLiked = !_isLiked;
      _showHeartAnimation = true;
      // Создаем частицы для анимации
      _heartParticles = List.generate(12, (index) {
        return Offset(
          (index % 2 == 0 ? 1 : -1) * 50 * (index / 12),
          -50 - (index * 10),
        );
      });
    });
    
    print('ShortsVideoPlayer: New like status: $_isLiked');
    print('ShortsVideoPlayer: Calling onLike callback');
    
    // Вызываем callback для обновления на сервере
    widget.onLike();
    
    // Анимация частиц
    _animateParticles();
    
    // Скрываем анимацию через 1 секунду
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _showHeartAnimation = false;
          _heartParticles = [];
        });
        print('ShortsVideoPlayer: Heart animation hidden');
      }
    });
  }
  
  void _animateParticles() {
    // Анимация частиц с помощью Ticker
    final ticker = Ticker((elapsed) {
      if (!mounted || _heartParticles.isEmpty) return;
      
      setState(() {
        _heartParticles = _heartParticles.map((particle) {
          return Offset(
            particle.dx * 0.95, // Замедление по X
            particle.dy - 2, // Движение вверх
          );
        }).toList();
      });
    });
    
    ticker.start();
    Future.delayed(const Duration(milliseconds: 800), () {
      ticker.stop();
      ticker.dispose();
    });
  }
  
  void _startLongPress() {
    // Долгое нажатие работает только для видео
    if (widget.post.mediaType != 'video' || 
        widget.videoController == null || 
        !widget.videoController!.value.isInitialized) return;
    
    setState(() {
      _isLongPressing = true;
    });
    
    // Устанавливаем скорость х2
    widget.videoController!.setPlaybackSpeed(2.0);
    print('ShortsVideoPlayer: Long press started - speed x2');
  }
  
  void _endLongPress() {
    // Долгое нажатие работает только для видео
    if (widget.post.mediaType != 'video' || 
        widget.videoController == null || 
        !widget.videoController!.value.isInitialized) return;
    
    setState(() {
      _isLongPressing = false;
    });
    
    // Возвращаем скорость х1
    widget.videoController!.setPlaybackSpeed(1.0);
    print('ShortsVideoPlayer: Long press ended - speed x1');
  }

  void _showPostOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Индикатор
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Опция редактирования
                ListTile(
                  leading: const Icon(
                    EvaIcons.edit,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Edit',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToEditPost(context);
                  },
                ),
                // Разделитель
                Divider(
                  color: Colors.grey[800],
                  height: 1,
                ),
                // Опция удаления
                ListTile(
                  leading: Icon(
                    EvaIcons.trash2,
                    color: Colors.red[400],
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(color: Colors.red[400]),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateToEditPost(BuildContext context) {
    // Создаем LocationInfo из данных поста, если есть
    LocationInfo? locationInfo;
    if (widget.post.country != null || widget.post.city != null) {
      locationInfo = LocationInfo(
        country: widget.post.country,
        city: widget.post.city,
        district: widget.post.district,
        street: widget.post.street,
        address: widget.post.address,
      );
    }

    // Парсим locationVisibility в Set<String>
    Set<String>? locationVisibility;
    if (widget.post.locationVisibility != null && widget.post.locationVisibility!.isNotEmpty) {
      locationVisibility = widget.post.locationVisibility!.split(',').map((e) => e.trim()).toSet();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditPostScreen(
          postId: widget.post.id,
          currentCaption: widget.post.caption,
          currentCoauthor: widget.post.coauthor,
          currentExternalLinkUrl: widget.post.externalLinkUrl,
          currentExternalLinkText: widget.post.externalLinkText,
          currentLocation: locationInfo,
          currentLocationVisibility: locationVisibility,
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Delete post?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This action cannot be undone. The post will be permanently deleted.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: _isDeleting ? null : () => _deletePost(context),
              child: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red,
                      ),
                    )
                  : const Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePost(BuildContext context) async {
    setState(() {
      _isDeleting = true;
    });

    try {
      final apiService = ApiService();
      await apiService.deletePost(widget.post.id);

      // Обновляем список постов через provider
      final postsProvider = Provider.of<PostsProvider>(context, listen: false);
      await postsProvider.deletePost(widget.post.id);

      if (mounted) {
        Navigator.pop(context); // Закрываем диалог подтверждения
        AppNotification.showSuccess(
          context,
          'Post deleted',
        );
      }
    } catch (e) {
      print('ShortsVideoPlayer: Error deleting post: $e');
      if (mounted) {
        Navigator.pop(context); // Закрываем диалог подтверждения
        AppNotification.showError(
          context,
          'Failed to delete post',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
  
  void _openProfile() async {
    // Используем userId напрямую из поста, так как user может быть null
    final userId = widget.post.userId;
    
    if (userId.isEmpty) {
      print('ShortsVideoPlayer: Cannot open profile - userId is empty');
      return;
    }
    
    print('ShortsVideoPlayer: Opening profile for userId: $userId');
    
    // Останавливаем видео перед навигацией
    if (widget.videoController != null && widget.videoController!.value.isInitialized) {
      try {
        await widget.videoController!.setVolume(0);
        await widget.videoController!.pause();
        print('ShortsVideoPlayer: Video paused before opening profile');
      } catch (e) {
        print('ShortsVideoPlayer: Error pausing video: $e');
      }
    }
    
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProfileScreen(userId: userId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.post.mediaType == 'video';
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // Видео или фото с обработкой тапов
        if (isVideo && widget.videoController != null &&
            widget.videoController!.value.isInitialized)
          // Видео
          Center(
            child: AspectRatio(
              aspectRatio: widget.videoController!.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(widget.videoController!),
                  // GestureDetector для обработки тапов, долгого нажатия и swipe
                  GestureDetector(
                    onTap: () {
                      final now = DateTime.now();
                      // Проверяем, был ли это двойной тап
                      if (_lastTapTime != null &&
                          now.difference(_lastTapTime!) < _doubleTapDelay) {
                        // Двойной тап - лайк
                        _handleDoubleTap();
                        _lastTapTime = null;
                      } else {
                        // Одинарный тап - пауза/play
                        _lastTapTime = now;
                        Future.delayed(_doubleTapDelay, () {
                          if (_lastTapTime == now && mounted) {
                            _togglePlayPause();
                            setState(() {
                              _showControls = true;
                            });
                            Future.delayed(const Duration(seconds: 3), () {
                              if (mounted) {
                                setState(() {
                                  _showControls = false;
                                });
                              }
                            });
                            _lastTapTime = null;
                          }
                        });
                      }
                    },
                    onLongPressStart: (details) {
                      // Долгое нажатие работает только для видео
                      if (widget.post.mediaType == 'video') {
                        // Определяем, нажатие на левой или правой стороне
                        final screenWidth = MediaQuery.of(context).size.width;
                        final tapX = details.globalPosition.dx;
                        
                        // Левая или правая сторона (первые 30% или последние 30% экрана)
                        if (tapX < screenWidth * 0.3 || tapX > screenWidth * 0.7) {
                          _startLongPress();
                        }
                      }
                    },
                    onLongPressEnd: (details) {
                      if (widget.post.mediaType == 'video') {
                        _endLongPress();
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      // Swipe справа налево (отрицательная скорость)
                      print('ShortsVideoPlayer: Horizontal drag ended, velocity: ${details.primaryVelocity}');
                      if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
                        print('ShortsVideoPlayer: Swipe detected, opening profile...');
                        print('ShortsVideoPlayer: Post userId: ${widget.post.userId}');
                        print('ShortsVideoPlayer: Post user: ${widget.post.user?.id}');
                        _openProfile();
                      }
                    },
                    behavior: HitTestBehavior.translucent,
                  ),
                ],
              ),
            ),
          )
        else if (!isVideo)
          // Фото
          GestureDetector(
            onTap: () {
              final now = DateTime.now();
              // Проверяем, был ли это двойной тап
              if (_lastTapTime != null &&
                  now.difference(_lastTapTime!) < _doubleTapDelay) {
                // Двойной тап - лайк
                _handleDoubleTap();
                _lastTapTime = null;
              } else {
                // Одинарный тап - показываем/скрываем контролы
                _lastTapTime = now;
                Future.delayed(_doubleTapDelay, () {
                  if (_lastTapTime == now && mounted) {
                    setState(() {
                      _showControls = !_showControls;
                    });
                    if (_showControls) {
                      Future.delayed(const Duration(seconds: 3), () {
                        if (mounted) {
                          setState(() {
                            _showControls = false;
                          });
                        }
                      });
                    }
                    _lastTapTime = null;
                  }
                });
              }
            },
            onHorizontalDragEnd: (details) {
              // Swipe справа налево (отрицательная скорость)
              if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
                _openProfile();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImageWithSignedUrl(
                  imageUrl: widget.post.mediaUrl,
                  postId: widget.post.id,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          )
        else
          // Загрузка видео
          GestureDetector(
            onTap: () {
              // Переключаем паузу/play при тапе на загрузке
              if (widget.videoController != null) {
                _togglePlayPause();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF0095F6),
                ),
              ),
            ),
          ),

          // Градиент снизу для читаемости текста
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Индикатор прогресса видео внизу экрана (только для видео)
          if (widget.post.mediaType == 'video' &&
              widget.videoController != null && 
              widget.videoController!.value.isInitialized)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Прогресс-бар с увеличенной областью для жестов
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                    onHorizontalDragStart: (details) {
                      if (widget.videoController == null || 
                          !widget.videoController!.value.isInitialized) return;
                      
                      setState(() {
                        _isDraggingProgress = true;
                        _isProgressBarExpanded = true; // Увеличиваем при начале перемотки
                      });
                      print('ShortsVideoPlayer: Drag start');
                    },
                    onHorizontalDragUpdate: (details) {
                      if (widget.videoController == null || 
                          !widget.videoController!.value.isInitialized) return;
                      
                      // Получаем актуальную длительность
                      final duration = widget.videoController!.value.duration;
                      if (duration.inMilliseconds <= 0) return;
                      
                      final screenWidth = MediaQuery.of(context).size.width;
                      const horizontalPadding = 16.0;
                      final progressBarWidth = screenWidth - (horizontalPadding * 2);
                      final dragX = (details.globalPosition.dx - horizontalPadding).clamp(0.0, progressBarWidth);
                      final newProgress = (dragX / progressBarWidth).clamp(0.0, 1.0);
                      
                      setState(() {
                        _progressValue = newProgress;
                        _totalDuration = duration; // Обновляем длительность
                        _currentPosition = Duration(
                          milliseconds: (_progressValue * duration.inMilliseconds).round(),
                        );
                      });
                    },
                    onHorizontalDragEnd: (details) async {
                      if (widget.videoController == null || 
                          !widget.videoController!.value.isInitialized) return;
                      
                      // Получаем актуальную длительность
                      final duration = widget.videoController!.value.duration;
                      if (duration.inMilliseconds <= 0) {
                        setState(() {
                          _isDraggingProgress = false;
                        });
                        return;
                      }
                      
                      final newPosition = Duration(
                        milliseconds: (_progressValue * duration.inMilliseconds).round(),
                      );
                      
                      try {
                        await widget.videoController!.seekTo(newPosition);
                        setState(() {
                          _currentPosition = newPosition;
                        });
                        print('ShortsVideoPlayer: Seeked to ${newPosition.inSeconds}s via drag');
                      } catch (e) {
                        print('ShortsVideoPlayer: Error seeking: $e');
                      }
                      
                      setState(() {
                        _isDraggingProgress = false;
                        _isProgressBarExpanded = false; // Уменьшаем сразу при отпускании
                      });
                    },
                    onTapDown: (details) async {
                      if (widget.videoController == null || 
                          !widget.videoController!.value.isInitialized) return;
                      
                      // Увеличиваем прогресс-бар при нажатии
                      setState(() {
                        _isProgressBarExpanded = true;
                      });
                      
                      // Получаем актуальную длительность
                      final duration = widget.videoController!.value.duration;
                      if (duration.inMilliseconds <= 0) return;
                      
                      final screenWidth = MediaQuery.of(context).size.width;
                      const horizontalPadding = 16.0;
                      final progressBarWidth = screenWidth - (horizontalPadding * 2);
                      final tapX = (details.globalPosition.dx - horizontalPadding).clamp(0.0, progressBarWidth);
                      final newProgress = (tapX / progressBarWidth).clamp(0.0, 1.0);
                      
                      final newPosition = Duration(
                        milliseconds: (newProgress * duration.inMilliseconds).round(),
                      );
                      
                      try {
                        await widget.videoController!.seekTo(newPosition);
                        setState(() {
                          _progressValue = newProgress;
                          _currentPosition = newPosition;
                          _totalDuration = duration; // Обновляем длительность
                        });
                        print('ShortsVideoPlayer: Seeked to ${newPosition.inSeconds}s via tap');
                      } catch (e) {
                        print('ShortsVideoPlayer: Error seeking on tap: $e');
                      }
                    },
                    onTapUp: (details) {
                      // Уменьшаем прогресс-бар при отпускании (если не в режиме перемотки)
                      if (!_isDraggingProgress) {
                        setState(() {
                          _isProgressBarExpanded = false;
                        });
                      }
                    },
                    onTapCancel: () {
                      // Уменьшаем прогресс-бар при отмене нажатия
                      if (!_isDraggingProgress) {
                        setState(() {
                          _isProgressBarExpanded = false;
                        });
                      }
                    },
                    child: Container(
                          // Увеличиваем область нажатия с помощью padding
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            // Увеличивается при удержании/перемотке, чуть шире базовый размер
                            height: (_isDraggingProgress || _isProgressBarExpanded) ? 10.0 : 4.0,
                      color: Colors.transparent,
                      child: Stack(
                              clipBehavior: Clip.none,
                        children: [
                          // Фон прогресс-бара (белый с прозрачностью, как в Stories)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular((_isDraggingProgress || _isProgressBarExpanded) ? 5.0 : 2.0), // Закругление увеличивается при увеличении
                            ),
                          ),
                          // Прогресс с однотонным цветом
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _progressValue,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0099FF),
                                      borderRadius: BorderRadius.circular((_isDraggingProgress || _isProgressBarExpanded) ? 5.0 : 2.0), // Закругление увеличивается при увеличении
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
                      ),
                    ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Информация о посте (справа)
          Positioned(
            right: 16,
            bottom: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Аватар автора с кнопкой подписки
                Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        // TODO: Перейти на профиль
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: widget.post.user?.avatarUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: widget.post.user!.avatarUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey[800],
                                    child: const Icon(
                                      EvaIcons.person,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[800],
                                    child: const Icon(
                                      EvaIcons.person,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey[800],
                                  child: const Icon(
                                    EvaIcons.person,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Лайк
                _AnimatedActionButton(
                  icon: EvaIcons.heart,
                  iconColor: _isLiked ? Colors.red : Colors.white,
                  count: widget.post.likesCount,
                  previousCount: _previousLikesCount,
                  formatCount: _formatCount,
                  onTap: () {
                    setState(() {
                      _isLiked = !_isLiked;
                      _previousLikesCount = widget.post.likesCount;
                    });
                    widget.onLike();
                  },
                ),
                const SizedBox(height: 16),

                // Комментарий
                Consumer<PostsProvider>(
                  builder: (context, postsProvider, child) {
                    // Получаем актуальный счетчик комментариев из provider
                    final videoPosts = postsProvider.videoPosts;
                    final postIndex = videoPosts.indexWhere((p) => p.id == widget.post.id);
                    final currentCommentsCount = postIndex != -1
                        ? videoPosts[postIndex].commentsCount
                        : widget.post.commentsCount;
                    
                    // Обновляем предыдущий счетчик для анимации, если изменился
                    if (currentCommentsCount != _previousCommentsCount && postIndex != -1) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _previousCommentsCount = currentCommentsCount;
                          });
                        }
                      });
                    }
                    
                    return _AnimatedActionButton(
                      icon: EvaIcons.messageCircle,
                      count: currentCommentsCount,
                      previousCount: _previousCommentsCount,
                      formatCount: _formatCount,
                      onTap: widget.onComment,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Закладки (сохранить)
                _ActionButton(
                  icon: EvaIcons.bookmark,
                  iconColor: _isSaved ? Colors.yellow : Colors.white,
                  label: '',
                  onTap: _toggleSave,
                ),
                const SizedBox(height: 16),

                // Поделиться
                _ActionButton(
                  icon: EvaIcons.paperPlane,
                  label: '',
                  onTap: widget.onShare,
                ),
                const SizedBox(height: 16),

                // Кнопка настроек (только для автора поста)
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    final currentUserId = authProvider.currentUser?.id;
                    final isAuthor = currentUserId != null && currentUserId == widget.post.userId;
                    
                    if (!isAuthor) {
                      return const SizedBox.shrink();
                    }
                    
                    return _ActionButton(
                      icon: EvaIcons.moreVertical,
                      label: '',
                      onTap: () => _showPostOptionsMenu(context),
                    );
                  },
                ),
              ],
            ),
          ),

          // Информация о посте (слева внизу)
          Positioned(
            left: 16,
            bottom: 80,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Имя пользователя и кнопка подписки
                if (widget.post.user?.username != null)
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // TODO: Перейти на профиль
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          '@${widget.post.user!.username}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Кнопка подписки
                      Consumer<AuthProvider>(
                        builder: (context, authProvider, child) {
                          final currentUserId = authProvider.currentUser?.id;
                          final authorId = widget.post.userId;
                          
                          // Не показываем кнопку для собственного профиля
                          if (currentUserId == null || currentUserId == authorId) {
                            return const SizedBox.shrink();
                          }
                          
                          // Показываем индикатор загрузки
                          if (_isCheckingFollowStatus) {
                            return const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            );
                          }
                          
                          // Определяем текст кнопки
                          String buttonText;
                          Color buttonColor;
                          if (_isFollowing == true) {
                            buttonText = _isMutualFollow ? 'Friends' : 'Following';
                            buttonColor = _isMutualFollow ? const Color(0xFF0095F6) : Colors.grey[700]!;
                          } else {
                            buttonText = 'Follow';
                            buttonColor = const Color(0xFF0095F6);
                          }
                          
                          return GestureDetector(
                            onTap: _isTogglingFollow ? null : _toggleFollow,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: buttonColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                buttonText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 8),

                // Подпись
                if (widget.post.caption.isNotEmpty)
                  Text(
                    widget.post.caption,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Анимация лайка в центре при двойном тапе с частицами
          if (_showHeartAnimation)
            Stack(
              children: [
                // Основное сердце
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: 1.0 - (value - 0.5).abs() * 2,
                          child: Icon(
                            EvaIcons.heart,
                            color: Colors.red,
                            size: 80 * value,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Частицы/конфетти
                ..._heartParticles.map((particle) {
                  return Positioned(
                    left: MediaQuery.of(context).size.width / 2 + particle.dx,
                    top: MediaQuery.of(context).size.height / 2 + particle.dy,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 1.0, end: 0.0),
                      duration: const Duration(milliseconds: 800),
                      builder: (context, opacity, child) {
                        return Opacity(
                          opacity: opacity,
                          child: Transform.rotate(
                            angle: particle.dx * 0.1,
                            child: Icon(
                              EvaIcons.heart,
                              color: Colors.red.withOpacity(0.7),
                              size: 16,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }).toList(),
              ],
            ),

          // Кнопка паузы/play по центру (если показываем контролы) - только для видео
          if (_showControls && widget.post.mediaType == 'video' && widget.videoController != null)
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.0,
                          end: 1.0,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                        ),
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    child: Icon(
                      widget.videoController!.value.isPlaying
                          ? EvaIcons.pauseCircle
                          : EvaIcons.playCircle,
                      key: ValueKey<bool>(widget.videoController!.value.isPlaying),
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),

          // Таймер в центре экрана при перемотке - только для видео
          if (widget.post.mediaType == 'video' &&
              widget.videoController != null && 
              widget.videoController!.value.isInitialized &&
              (_isDraggingProgress || _isProgressBarExpanded))
            AnimatedOpacity(
              opacity: (_isDraggingProgress || _isProgressBarExpanded) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatTimeDisplay(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

          // Индикатор скорости х2 при долгом нажатии с плавной анимацией (только для видео)
          if (widget.post.mediaType == 'video')
            AnimatedOpacity(
              opacity: _isLongPressing ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Center(
                child: AnimatedScale(
                  scale: _isLongPressing ? 1.0 : 0.8,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '2x',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _toggleSave() async {
    final newSavedState = !_isSaved;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        if (mounted) {
          AppNotification.showError(context, 'Please login to save posts');
        }
        return;
      }

      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      
      // Optimistically update UI
      setState(() {
        _isSaved = newSavedState;
      });

      // Call API
      final saved = newSavedState
          ? await apiService.savePost(widget.post.id)
          : await apiService.unsavePost(widget.post.id);

      // Update state with actual result
      setState(() {
        _isSaved = saved;
      });

      if (mounted) {
        AppNotification.showSuccess(
          context,
          saved ? 'Post saved' : 'Post unsaved',
        );
      }
    } catch (e) {
      print('Error toggling save: $e');
      // Revert optimistic update
      setState(() {
        _isSaved = !newSavedState;
      });
      
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to ${newSavedState ? "save" : "unsave"} post: $e',
        );
      }
    }
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

// Анимированная кнопка действия с плавной анимацией счетчика
class _AnimatedActionButton extends StatefulWidget {
  final IconData icon;
  final int count;
  final int previousCount;
  final String Function(int) formatCount;
  final VoidCallback onTap;
  final Color? iconColor;

  const _AnimatedActionButton({
    required this.icon,
    required this.count,
    required this.previousCount,
    required this.formatCount,
    required this.onTap,
    this.iconColor,
  });

  @override
  State<_AnimatedActionButton> createState() => _AnimatedActionButtonState();
}

class _AnimatedActionButtonState extends State<_AnimatedActionButton> {
  @override
  Widget build(BuildContext context) {
    final currentLabel = widget.formatCount(widget.count);
    final isIncreasing = widget.count > widget.previousCount;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.icon,
            color: widget.iconColor ?? Colors.white,
            size: 32,
          ),
          const SizedBox(height: 4),
          // Анимированный счетчик с плавным переходом чисел
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (Widget child, Animation<double> animation) {
              // Анимация масштаба и прозрачности
              return ScaleTransition(
                scale: Tween<double>(
                  begin: isIncreasing ? 1.2 : 0.8,
                  end: 1.0,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: isIncreasing ? Curves.elasticOut : Curves.easeOut,
                  ),
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0, isIncreasing ? -0.3 : 0.3),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOut,
                      ),
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: Text(
              currentLabel,
              key: ValueKey<String>(currentLabel),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Обычная кнопка действия (для кнопки "Поделиться" без счетчика)
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: iconColor ?? Colors.white,
            size: 32,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

