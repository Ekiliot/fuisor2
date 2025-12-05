import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'cached_network_image_with_signed_url.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user.dart';
import '../screens/edit_post_screen.dart';
import '../screens/comments_screen.dart';
import '../screens/hashtag_screen.dart';
import '../screens/main_screen.dart';
import '../screens/profile_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/posts_provider.dart';
import '../services/api_service.dart';
import '../utils/hashtag_utils.dart';
import '../widgets/username_error_notification.dart';
import '../widgets/app_notification.dart';
import '../widgets/share_video_sheet.dart';
import '../services/geocoding_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback onLike;
  final Function(String content, String? parentCommentId) onComment;

  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with TickerProviderStateMixin {
  bool _isLiked = false;
  bool _isSaved = false;
  bool _showComments = false;
  final TextEditingController _commentController = TextEditingController();
  OverlayEntry? _usernameErrorOverlay;
  
  // Локальные счетчики для анимации
  int _likesCount = 0;
  int _commentsCount = 0;
  
  // Контроллеры анимации для счетчиков
  late AnimationController _likesAnimationController;
  late AnimationController _commentsAnimationController;
  late Animation<double> _likesScaleAnimation;
  late Animation<double> _commentsScaleAnimation;
  
  // Анимация для аватарок соавторов
  late AnimationController _avatarSwapController;
  late Animation<double> _avatarScaleAnimation;
  late Animation<Offset> _avatarSlideAnimation;
  late Animation<double> _avatarOpacityAnimation;
  Timer? _avatarSwapTimer;
  bool _showAuthorFirst = true;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _isSaved = widget.post.isSaved;
    _likesCount = widget.post.likesCount;
    _commentsCount = widget.post.commentsCount;
    
    // Инициализация анимаций
    _likesAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _commentsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _likesScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _likesAnimationController,
      curve: Curves.elasticOut,
    ));
    
    _commentsScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _commentsAnimationController,
      curve: Curves.elasticOut,
    ));
    
    // Анимация для аватарок соавторов
    _avatarSwapController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    // Анимация смены мест: передняя уходит назад, задняя выходит вперед, затем возврат
    // Scale: 1.0 -> 0.85 -> 1.0 (передняя уменьшается, затем возвращается)
    _avatarScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.85)
          .chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.4,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 0.85)
          .chain(CurveTween(curve: Curves.linear)),
        weight: 0.2,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.4,
      ),
    ]).animate(_avatarSwapController);
    
    // Slide: (0,0) -> (10, 0) -> (0, 0) (сдвигается вправо, затем возвращается)
    _avatarSlideAnimation = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(10, 0),
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.4,
      ),
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: const Offset(10, 0),
          end: const Offset(10, 0),
        ).chain(CurveTween(curve: Curves.linear)),
        weight: 0.2,
      ),
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: const Offset(10, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.4,
      ),
    ]).animate(_avatarSwapController);
    
    // Opacity: 1.0 -> 0.6 -> 1.0 (тускнеет, затем возвращается)
    _avatarOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.6)
          .chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.4,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.6, end: 0.6)
          .chain(CurveTween(curve: Curves.linear)),
        weight: 0.2,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.6, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.4,
      ),
    ]).animate(_avatarSwapController);
    
    // Запускаем таймер смены аватарок только если есть соавтор
    if (widget.post.coauthor != null) {
      // Слушаем завершение анимации, чтобы изменить порядок только после завершения
      _avatarSwapController.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _showAuthorFirst = !_showAuthorFirst;
          });
          _avatarSwapController.reset();
        }
      });
      
      _avatarSwapTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted) {
          // Запускаем анимацию, порядок изменится после завершения
          _avatarSwapController.forward(from: 0.0);
        }
      });
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Синхронизируем счетчики с данными из виджета при обновлении
    if (oldWidget.post.likesCount != widget.post.likesCount) {
      _likesCount = widget.post.likesCount;
    }
    if (oldWidget.post.commentsCount != widget.post.commentsCount) {
      _commentsCount = widget.post.commentsCount;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _likesAnimationController.dispose();
    _commentsAnimationController.dispose();
    _avatarSwapController.dispose();
    _avatarSwapTimer?.cancel();
    _hideUsernameErrorNotification();
    super.dispose();
  }

  void _showUsernameErrorNotification() {
    // Если уведомление уже показывается, не создаем новое
    if (_usernameErrorOverlay != null) {
      return;
    }
    
    // Создаем overlay entry для показа уведомления сверху
    final overlay = Overlay.of(context);
    
    _usernameErrorOverlay = OverlayEntry(
      builder: (context) => UsernameErrorNotification(
        onDismiss: () {
          if (_usernameErrorOverlay != null && _usernameErrorOverlay!.mounted) {
            _usernameErrorOverlay!.remove();
            _usernameErrorOverlay = null;
          }
        },
      ),
    );
    
    overlay.insert(_usernameErrorOverlay!);
  }

  void _hideUsernameErrorNotification() {
    if (_usernameErrorOverlay != null && _usernameErrorOverlay!.mounted) {
      _usernameErrorOverlay!.remove();
      _usernameErrorOverlay = null;
    }
  }

  void _navigateToHashtag(String hashtag) {
    print('PostCard: Navigating to hashtag: $hashtag');
    print('PostCard: Context is mounted: ${mounted}');
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HashtagScreen(hashtag: hashtag),
        ),
      );
      print('PostCard: Navigation completed');
    } catch (e) {
      print('PostCard: Navigation error: $e');
    }
  }

  Future<void> _navigateToUserByUsername(String username) async {
    print('PostCard: Navigating to user by username: $username');
    try {
      // Get access token
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        if (mounted) {
          AppNotification.showError(context, 'Please login to view profiles');
        }
        return;
      }

      // Get user by username from API
      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      
      final user = await apiService.getUserByUsername(username);
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: user.id),
          ),
        );
      }
    } catch (e) {
      print('PostCard: Error navigating to user: $e');
      if (mounted) {
        _showUsernameErrorNotification();
      }
    }
  }

  void _navigateToShorts(Post post) {
    print('PostCard: Navigating to Shorts with post: ${post.id}');
    try {
      // Ищем MainScreenState в дереве виджетов
      final mainScreenState = context.findAncestorStateOfType<MainScreenState>();
      if (mainScreenState != null) {
        mainScreenState.switchToShortsWithPost(post);
      } else {
        print('PostCard: MainScreenState not found in widget tree');
      }
    } catch (e) {
      print('PostCard: Error navigating to Shorts: $e');
    }
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
          duration: const Duration(seconds: 1),
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
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<void> _openExternalLink(String url) async {
    try {
      // Убеждаемся, что URL имеет протокол
      String finalUrl = url.trim();
      if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
        finalUrl = 'https://$finalUrl';
      }
      
      final uri = Uri.parse(finalUrl);
      print('Opening URL: $finalUrl');
      
      // Пробуем открыть с externalApplication (открывает в браузере)
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (!launched) {
          // Если не получилось, пробуем platformDefault
          print('externalApplication failed, trying platformDefault');
          final launched2 = await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
          );
          
          if (!launched2 && mounted) {
            AppNotification.showError(
              context,
              'Could not open link. Please check if you have a browser installed.',
              duration: const Duration(seconds: 3),
            );
          }
        }
      } catch (e) {
        print('Error launching URL: $e');
        // Пробуем platformDefault как fallback
        try {
          await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
          );
        } catch (e2) {
          print('Error with platformDefault: $e2');
          if (mounted) {
            AppNotification.showError(
              context,
              'Failed to open link. Please try again.',
              duration: const Duration(seconds: 2),
            );
          }
        }
      }
    } catch (e) {
      print('Error parsing/opening link: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Invalid link format',
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
          ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar(s) - одна или две наложенные если есть соавтор
                _buildAvatars(),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      // Name and username in capsule
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262626),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _buildNamesSection(),
                      ),
                      const Spacer(),
                      // Time and edit icon
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTimeAgo(widget.post.createdAt),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          if (widget.post.createdAt != widget.post.updatedAt) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              EvaIcons.editOutline,
                              size: 14,
                              color: Colors.white,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(EvaIcons.moreHorizontal, size: 20, color: Colors.white),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (context) {
                            // Формируем LocationInfo из данных поста
                            LocationInfo? locationInfo;
                            if (widget.post.city != null || 
                                widget.post.district != null || 
                                widget.post.street != null || 
                                widget.post.address != null || 
                                widget.post.country != null) {
                              locationInfo = LocationInfo(
                                country: widget.post.country,
                                city: widget.post.city,
                                district: widget.post.district,
                                street: widget.post.street,
                                address: widget.post.address,
                              );
                            }
                            
                            // Формируем Set из location_visibility
                            Set<String>? locationVisibility;
                            if (widget.post.locationVisibility != null && 
                                widget.post.locationVisibility!.isNotEmpty) {
                              locationVisibility = widget.post.locationVisibility!
                                  .split(',')
                                  .where((e) => e.isNotEmpty)
                                  .toSet();
                            }
                            
                            return EditPostScreen(
                              postId: widget.post.id,
                              currentCaption: widget.post.caption,
                              currentCoauthor: widget.post.coauthor,
                              currentExternalLinkUrl: widget.post.externalLinkUrl,
                              currentExternalLinkText: widget.post.externalLinkText,
                              currentLocation: locationInfo,
                              currentLocationVisibility: locationVisibility,
                            );
                          },
                        ),
                      );
                      
                      if (result == true && mounted) {
                        // Post was updated, refresh the feed
                        final postsProvider = context.read<PostsProvider>();
                        final authProvider = context.read<AuthProvider>();
                        final accessToken = await authProvider.getAccessToken();
                        if (accessToken != null) {
                          await postsProvider.loadFeed(refresh: true, accessToken: accessToken);
                        }
                      }
                    } else if (value == 'delete') {
                      // Show confirmation dialog
                      final shouldDelete = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A1A),
                          title: const Text(
                            'Delete Post',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: const Text(
                            'Are you sure you want to delete this post? This action cannot be undone.',
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
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (shouldDelete == true && mounted) {
                        try {
                          final postsProvider = context.read<PostsProvider>();
                          final authProvider = context.read<AuthProvider>();
                          final accessToken = await authProvider.getAccessToken();
                          
                          if (accessToken != null) {
                            await postsProvider.deletePost(widget.post.id, accessToken: accessToken);
                            
                            if (mounted) {
                              AppNotification.showSuccess(context, 'Post deleted successfully');
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            AppNotification.showError(
                              context,
                              'Failed to delete post: $e',
                              duration: const Duration(seconds: 3),
                            );
                          }
                        }
                      }
                    }
                  },
                  itemBuilder: (context) {
                    final authProvider = context.read<AuthProvider>();
                    final isOwnPost = authProvider.currentUser?.id == widget.post.userId;
                    
                    return [
                      if (isOwnPost)
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(EvaIcons.editOutline, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Edit Post', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      if (isOwnPost)
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(EvaIcons.trashOutline, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete Post', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      if (!isOwnPost)
                        const PopupMenuItem<String>(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(EvaIcons.flagOutline, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Report', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                    ];
                  },
                ),
              ],
            ),
          ),

          // Media - строго 1:1
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: width,
                    height: width, // Строго 1:1
            child: widget.post.mediaType == 'video'
                        ? GestureDetector(
                            onTap: () {
                              // Переключаемся на Shorts с этим видео
                              _navigateToShorts(widget.post);
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Показываем thumbnail если есть, иначе placeholder
                                widget.post.thumbnailUrl != null && widget.post.thumbnailUrl!.isNotEmpty
                                        ? CachedNetworkImageWithSignedUrl(
                                            imageUrl: widget.post.thumbnailUrl!,
                                            postId: widget.post.id, // Передаем postId для уникального ключа кеша
                                        fit: BoxFit.cover,
                              width: width,
                              height: width,
                                        placeholder: (context) => Container(
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) => Container(
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: Icon(Icons.error),
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: Colors.black,
                                        child: const Center(
                                          child: Icon(
                                            EvaIcons.videoOutline,
                                            color: Colors.white,
                                            size: 48,
                                          ),
                                        ),
                                      ),
                                // Затемнение для лучшей видимости иконки play
                                Container(
                                  color: Colors.black.withOpacity(0.2),
                                ),
                                // Иконка play по центру
                                const Center(
                                  child: Icon(
                                    EvaIcons.playCircleOutline,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                ),
                              ],
                            ),
                          )
                : CachedNetworkImageWithSignedUrl(
                    imageUrl: widget.post.mediaUrl,
                    postId: widget.post.id,
                    fit: BoxFit.cover,
                            width: width,
                            height: width,
                    placeholder: (context) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.error),
                      ),
                      ),
                    ),
                          ),
                  ),
                );
              },
                  ),
          ),

          // Location (под медиа)
          if (widget.post.locationVisibility != null && 
              widget.post.locationVisibility!.isNotEmpty) ...[
            _buildLocationText(),
          ],

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isLiked = !_isLiked;
                          // Обновляем счетчик лайков
                          if (_isLiked) {
                            _likesCount++;
                          } else {
                            _likesCount = _likesCount > 0 ? _likesCount - 1 : 0;
                          }
                          // Запускаем анимацию
                          _likesAnimationController.forward(from: 0.0).then((_) {
                            _likesAnimationController.reverse();
                          });
                        });
                        widget.onLike();
                      },
                      child: Icon(
                        _isLiked ? EvaIcons.heart : EvaIcons.heartOutline,
                        color: _isLiked ? Colors.red : Colors.white,
                        size: 28,
                      ),
                    ),
                    // Анимированный счетчик лайков справа от иконки
                    if (_likesCount > 0) ...[
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: _likesScaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _likesScaleAnimation.value,
                            child: Text(
                              '$_likesCount',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CommentsScreen(
                              postId: widget.post.id,
                              post: widget.post,
                            ),
                          ),
                        ).then((_) {
                          // Обновляем счетчик комментариев после возврата
                          setState(() {
                            _commentsCount = widget.post.commentsCount;
                            _commentsAnimationController.forward(from: 0.0).then((_) {
                              _commentsAnimationController.reverse();
                            });
                          });
                        });
                      },
                      child: const Icon(
                        EvaIcons.messageCircleOutline,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                    // Анимированный счетчик комментариев справа от иконки
                    if (_commentsCount > 0) ...[
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: _commentsScaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _commentsScaleAnimation.value,
                            child: Text(
                              '$_commentsCount',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (context) => ShareVideoSheet(post: widget.post),
                        );
                      },
                      child: const Icon(
                      EvaIcons.paperPlaneOutline,
                      size: 28,
                      color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _toggleSave(),
                      child: Icon(
                        _isSaved 
                            ? EvaIcons.bookmark 
                            : EvaIcons.bookmarkOutline,
                        size: 28,
                        color: _isSaved 
                            ? const Color(0xFF0095F6)
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Caption
                if (widget.post.caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.post.user?.name ?? widget.post.user?.username ?? 'Unknown'} ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: HashtagUtils.parseTextWithHashtagsAndUsernames(
                                widget.post.caption,
                                defaultStyle: const TextStyle(color: Colors.white),
                                hashtagStyle: const TextStyle(
                                  color: Color(0xFF0095F6),
                                  fontWeight: FontWeight.w600,
                                ),
                                usernameStyle: const TextStyle(
                                  color: Color(0xFF0095F6),
                                  fontWeight: FontWeight.w600,
                                ),
                                onHashtagTap: _navigateToHashtag,
                                onUsernameTap: _navigateToUserByUsername,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // External link button
                if (widget.post.externalLinkUrl != null && widget.post.externalLinkUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, top: 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0095F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _openExternalLink(widget.post.externalLinkUrl!),
                        icon: const Icon(EvaIcons.externalLink, size: 18),
                        label: Text(
                          widget.post.externalLinkText ?? 'Link',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),

                // View all comments
                if (_commentsCount > 0)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showComments = !_showComments;
                      });
                    },
                    child: Text(
                      'View all $_commentsCount ${_commentsCount == 1 ? 'comment' : 'comments'}',
                      style: const TextStyle(
                        color: Color(0xFF8E8E8E),
                        fontSize: 14,
                      ),
                    ),
                  ),

                // Comments
                if (_showComments && widget.post.comments != null)
                  ...widget.post.comments!.take(3).map(
                        (comment) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${comment.user?.name ?? comment.user?.username ?? 'Unknown'} ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: HashtagUtils.parseTextWithHashtagsAndUsernames(
                                      comment.content,
                                      defaultStyle: const TextStyle(color: Colors.white),
                                      hashtagStyle: const TextStyle(
                                        color: Color(0xFF0095F6),
                                        fontWeight: FontWeight.w600,
                                      ),
                                      usernameStyle: const TextStyle(
                                        color: Color(0xFF0095F6),
                                        fontWeight: FontWeight.w600,
                                      ),
                                      onHashtagTap: _navigateToHashtag,
                                      onUsernameTap: _navigateToUserByUsername,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                // Add comment
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      // Comment input field matching search field in messages
                      Expanded(
                          child: TextField(
                            controller: _commentController,
                          style: const TextStyle(color: Colors.white),
                          onChanged: (value) {
                            setState(() {}); // Обновляем state для обновления кнопки
                          },
                          decoration: InputDecoration(
                              hintText: 'Add a comment...',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: const Color(0xFF262626),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                widget.onComment(value.trim(), null);
                                _commentController.clear(); // Clear the field after submitting
                              setState(() {}); // Обновляем state после очистки
                              // Обновляем счетчик комментариев и запускаем анимацию
                              setState(() {
                                _commentsCount++;
                                _commentsAnimationController.forward(from: 0.0).then((_) {
                                  _commentsAnimationController.reverse();
                                });
                              });
                              }
                            },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Square send button with fill icon (matching input field style)
                      GestureDetector(
                        onTap: () {
                          final value = _commentController.text.trim();
                          if (value.isNotEmpty) {
                            widget.onComment(value, null);
                            _commentController.clear();
                            setState(() {}); // Обновляем state после очистки
                            // Обновляем счетчик комментариев и запускаем анимацию
                            setState(() {
                              _commentsCount++;
                              _commentsAnimationController.forward(from: 0.0).then((_) {
                                _commentsAnimationController.reverse();
                              });
                            });
                          }
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0095F6),
                            borderRadius: BorderRadius.circular(12), // Квадратная с закругленными углами как поле ввода
                          ),
                          child: const Icon(
                            EvaIcons.paperPlane, // Fill иконка (залитая)
                            color: Colors.white,
                            size: 22,
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

  // Build overlapping avatars for author and coauthor
  Widget _buildAvatars() {
    if (widget.post.coauthor == null) {
      // Single avatar
      return _buildSingleAvatar(widget.post.user?.avatarUrl);
    }
    
    // Two overlapping avatars with card shuffle animation
    return AnimatedBuilder(
      animation: _avatarSwapController,
      builder: (context, child) {
        // Определяем, какая аватарка сейчас спереди (ДО смены, текущее состояние)
        final currentFrontAvatar = _showAuthorFirst ? widget.post.user?.avatarUrl : widget.post.coauthor?.avatarUrl;
        final currentBackAvatar = _showAuthorFirst ? widget.post.coauthor?.avatarUrl : widget.post.user?.avatarUrl;
        
        // Во время анимации: текущая передняя уходит назад, текущая задняя выходит вперед
        // После завершения анимации _showAuthorFirst изменится, и порядок зафиксируется
        
        // Анимации для аватарки, которая уходит назад (текущая передняя - слева)
        final goingBackScale = _avatarScaleAnimation.value; // 1.0 -> 0.85 -> 1.0
        final goingBackSlide = _avatarSlideAnimation.value; // (0,0) -> (10, 0) -> (0, 0)
        // Если аватарка отсутствует, всегда opacity = 1.0
        final goingBackOpacity = (currentFrontAvatar == null || currentFrontAvatar.isEmpty) 
            ? 1.0 
            : _avatarOpacityAnimation.value; // 1.0 -> 0.6 -> 1.0
        
        // Анимации для аватарки, которая выходит вперед (текущая задняя - справа) - инвертируем
        final comingForwardScale = 0.85 + (1.0 - _avatarScaleAnimation.value) * 0.15; // 0.85 -> 1.0 -> 0.85
        final comingForwardSlide = Offset(-_avatarSlideAnimation.value.dx, 0); // (0, 0) -> (-10, 0) -> (0, 0)
        // Если аватарка отсутствует, всегда opacity = 1.0
        final comingForwardOpacity = (currentBackAvatar == null || currentBackAvatar.isEmpty)
            ? 1.0
            : 0.6 + (1.0 - _avatarOpacityAnimation.value) * 0.4; // 0.6 -> 1.0 -> 0.6
        
        return SizedBox(
          width: 62,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Back avatar (справа) - ВСЕГДА внизу Stack (задний план)
              // Выходит вперед во время анимации
              Positioned(
                right: 0,
                child: Transform.translate(
                  offset: comingForwardSlide,
                  child: Transform.scale(
                    scale: comingForwardScale,
                    child: Opacity(
                      opacity: comingForwardOpacity,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3 * comingForwardOpacity),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildSingleAvatar(currentBackAvatar, size: 42),
                      ),
                    ),
                  ),
                ),
              ),
              // Front avatar (слева) - ВСЕГДА сверху Stack (передний план)
              // Уходит назад во время анимации
              Positioned(
                left: 0,
                child: Transform.translate(
                  offset: goingBackSlide,
                  child: Transform.scale(
                    scale: goingBackScale,
                    child: Opacity(
                      opacity: goingBackOpacity,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3 * goingBackOpacity),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildSingleAvatar(currentFrontAvatar),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  // Build location text based on location_visibility
  Widget _buildLocationText() {
    if (widget.post.locationVisibility == null || 
        widget.post.locationVisibility!.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibilityParts = widget.post.locationVisibility!.split(',');
    final locationParts = <String>[];

    for (final part in visibilityParts) {
      final trimmed = part.trim();
      switch (trimmed) {
        case 'country':
          if (widget.post.country != null && widget.post.country!.isNotEmpty) {
            locationParts.add(widget.post.country!);
          }
          break;
        case 'city':
          if (widget.post.city != null && widget.post.city!.isNotEmpty) {
            locationParts.add(widget.post.city!);
          }
          break;
        case 'district':
          if (widget.post.district != null && widget.post.district!.isNotEmpty) {
            locationParts.add(widget.post.district!);
          }
          break;
        case 'street':
          if (widget.post.street != null && widget.post.street!.isNotEmpty) {
            locationParts.add(widget.post.street!);
          }
          break;
        case 'address':
          if (widget.post.address != null && widget.post.address!.isNotEmpty) {
            locationParts.add(widget.post.address!);
          }
          break;
      }
    }

    if (locationParts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            EvaIcons.pinOutline,
            size: 16,
            color: Colors.white70,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              locationParts.join(', '),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleAvatar(String? avatarUrl, {double size = 48}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF262626),
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: size,
                  height: size,
                  color: const Color(0xFF262626),
                  child: Icon(
                    EvaIcons.personOutline,
                    size: size * 0.5,
                    color: Colors.white,
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: size,
                  height: size,
                  color: const Color(0xFF262626),
                  child: Icon(
                    EvaIcons.personOutline,
                    size: size * 0.5,
                    color: Colors.white,
                  ),
                ),
              )
            : Icon(
                EvaIcons.personOutline,
                size: size * 0.5,
                color: Colors.white,
              ),
      ),
    );
  }
  
  // Build names section in capsule
  Widget _buildNamesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Author name and username
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ProfileScreen(userId: widget.post.userId),
              ),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.post.user?.name != null && widget.post.user!.name.isNotEmpty) ...[
                Text(
                  widget.post.user!.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 3,
                  height: 3,
                  decoration: const BoxDecoration(
                    color: Colors.white54,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                '@${widget.post.user?.username ?? 'unknown'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        // Coauthor name and username (if exists)
        if (widget.post.coauthor != null) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(userId: widget.post.coauthor!.id),
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.post.coauthor!.name.isNotEmpty) ...[
                  Text(
                    widget.post.coauthor!.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF0095F6),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0095F6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  '@${widget.post.coauthor!.username}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF0095F6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }
}
