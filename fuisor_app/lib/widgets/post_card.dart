import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'cached_network_image_with_signed_url.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
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
  
  // Локальные счетчики для анимации
  int _likesCount = 0;
  int _commentsCount = 0;
  
  // Контроллеры анимации для счетчиков
  late AnimationController _likesAnimationController;
  late AnimationController _commentsAnimationController;
  late Animation<double> _likesScaleAnimation;
  late Animation<double> _commentsScaleAnimation;

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
    super.dispose();
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to view profiles'),
              backgroundColor: Colors.red,
            ),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load user profile: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to save posts'),
              backgroundColor: Colors.red,
            ),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved 
                ? 'Post saved' 
                : 'Post unsaved'),
            backgroundColor: const Color(0xFF0095F6),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('Error toggling save: $e');
      // Revert optimistic update
      setState(() {
        _isSaved = !newSavedState;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${newSavedState ? "save" : "unsave"} post: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Square avatar with rounded corners
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: const Color(0xFF262626),
                    child: widget.post.user?.avatarUrl != null && widget.post.user!.avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.post.user!.avatarUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 48,
                              height: 48,
                              color: const Color(0xFF262626),
                              child: const Icon(
                                EvaIcons.personOutline,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 48,
                              height: 48,
                              color: const Color(0xFF262626),
                              child: const Icon(
                                EvaIcons.personOutline,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            EvaIcons.personOutline,
                            size: 24,
                            color: Colors.white,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name and username in the same row - clickable
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ProfileScreen(userId: widget.post.userId),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            // Name
                            if (widget.post.user?.name != null && widget.post.user!.name.isNotEmpty) ...[
                              Text(
                                widget.post.user!.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Middle dot
                              Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF8E8E8E),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            // Username
                            Text(
                              '@${widget.post.user?.username ?? 'unknown'}',
                              style: const TextStyle(
                                color: Color(0xFF8E8E8E),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _formatTimeAgo(widget.post.createdAt),
                            style: const TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 12,
                            ),
                          ),
                          if (widget.post.createdAt != widget.post.updatedAt) ...[
                            const SizedBox(width: 4),
                            const Text(
                              '• Изменено',
                              style: TextStyle(
                                color: Color(0xFF8E8E8E),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
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
                          builder: (context) => EditPostScreen(
                            postId: widget.post.id,
                            currentCaption: widget.post.caption,
                          ),
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Post deleted successfully'),
                                  backgroundColor: Color(0xFF0095F6),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to delete post: $e'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                              ),
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
                return ClipRRect(
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
                );
              },
                  ),
          ),

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
                    const Icon(
                      EvaIcons.paperPlaneOutline,
                      size: 28,
                      color: Colors.white,
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
