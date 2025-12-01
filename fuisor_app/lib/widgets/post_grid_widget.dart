import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../screens/post_detail_screen.dart';
import '../screens/comments_screen.dart';
import '../screens/main_screen.dart';
import '../services/api_service.dart';
import 'cached_network_image_with_signed_url.dart';

class PostGridWidget extends StatefulWidget {
  final List<Post> posts;
  final VoidCallback? onLoadMore;
  final bool isLoading;
  final bool hasMorePosts;

  const PostGridWidget({
    Key? key,
    required this.posts,
    this.onLoadMore,
    this.isLoading = false,
    this.hasMorePosts = true,
  }) : super(key: key);

  @override
  State<PostGridWidget> createState() => _PostGridWidgetState();
}

class _PostGridWidgetState extends State<PostGridWidget> {
  // Кеш для состояний лайков и закладок
  final Map<String, bool> _likedPosts = {};
  final Map<String, bool> _savedPosts = {};

  // Инициализация состояний из постов
  void _initializeStates() {
    for (final post in widget.posts) {
      _likedPosts[post.id] = post.isLiked;
      _savedPosts[post.id] = post.isSaved;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeStates();
  }

  @override
  void didUpdateWidget(PostGridWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posts != widget.posts) {
      _initializeStates();
    }
  }

  Future<void> _toggleLike(Post post) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to like posts'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      
      // Optimistically update UI
      final currentLiked = _likedPosts[post.id] ?? post.isLiked;
      setState(() {
        _likedPosts[post.id] = !currentLiked;
      });

      // Call API
      final result = await apiService.likePost(post.id);
      
      // Update state with actual result
      if (mounted) {
        setState(() {
          _likedPosts[post.id] = result['isLiked'] ?? !currentLiked;
        });
      }
    } catch (e) {
      print('Error toggling like: $e');
      // Revert optimistic update
      if (mounted) {
        setState(() {
          _likedPosts[post.id] = post.isLiked;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to like post: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleSave(Post post) async {
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
      final currentSaved = _savedPosts[post.id] ?? post.isSaved;
      final newSavedState = !currentSaved;
      setState(() {
        _savedPosts[post.id] = newSavedState;
      });

      // Call API
      final saved = newSavedState
          ? await apiService.savePost(post.id)
          : await apiService.unsavePost(post.id);
      
      // Update state with actual result
      if (mounted) {
        setState(() {
          _savedPosts[post.id] = saved;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved ? 'Post saved' : 'Post unsaved'),
            backgroundColor: const Color(0xFF0095F6),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('Error toggling save: $e');
      // Revert optimistic update
      if (mounted) {
        setState(() {
          _savedPosts[post.id] = post.isSaved;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${_savedPosts[post.id] ?? post.isSaved ? "unsave" : "save"} post: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openComments(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CommentsScreen(
          postId: post.id,
          post: post,
        ),
      ),
    );
  }

  void _showPostContextMenu(BuildContext context, Post post, bool isLiked, bool isSaved) {
    final screenWidth = MediaQuery.of(context).size.width;
    final mediaSize = screenWidth * 0.8; // 80% ширины экрана для квадратного превью
    
    showCupertinoModalPopup(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (BuildContext context) => Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Превью изображения поста над модальным окном
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 200, // Высота модального окна + отступ
            child: Container(
              width: mediaSize,
              height: mediaSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: post.mediaType == 'video'
                    ? (post.thumbnailUrl != null && post.thumbnailUrl!.isNotEmpty
                        ? CachedNetworkImageWithSignedUrl(
                            imageUrl: post.thumbnailUrl!,
                            postId: post.id,
                            fit: BoxFit.cover,
                            placeholder: (context) => Container(
                              color: Colors.grey[800],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF0095F6),
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[800],
                              child: const Center(
                                child: Icon(
                                  EvaIcons.videoOutline,
                                  color: Colors.grey,
                                  size: 48,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.grey[800],
                            child: const Center(
                              child: Icon(
                                EvaIcons.videoOutline,
                                color: Colors.grey,
                                size: 48,
                              ),
                            ),
                          ))
                    : CachedNetworkImageWithSignedUrl(
                        imageUrl: post.mediaUrl,
                        postId: post.id,
                        fit: BoxFit.cover,
                        placeholder: (context) => Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF0095F6),
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: Icon(
                              EvaIcons.imageOutline,
                              color: Colors.grey,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          // Модальное окно с действиями
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 16,
                right: 16,
              ),
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
                    // Like action
                    CupertinoContextMenuAction(
                      onPressed: () {
                        Navigator.pop(context);
                        _toggleLike(post);
                      },
                      child: Row(
                        children: [
                          Icon(
                            isLiked ? EvaIcons.heart : EvaIcons.heartOutline,
                            size: 20,
                            color: isLiked ? Colors.red : CupertinoColors.label.resolveFrom(context),
                          ),
                          const SizedBox(width: 12),
                          DefaultTextStyle(
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.0,
                            ),
                            child: Text(isLiked ? 'Unlike' : 'Like'),
                          ),
                        ],
                      ),
                    ),
                    // Comment action
                    CupertinoContextMenuAction(
                      onPressed: () {
                        Navigator.pop(context);
                        _openComments(post);
                      },
                      child: Row(
                        children: [
                          Icon(
                            EvaIcons.messageCircleOutline,
                            size: 20,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                          const SizedBox(width: 12),
                          DefaultTextStyle(
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.0,
                            ),
                            child: const Text('Comment'),
                          ),
                        ],
                      ),
                    ),
                    // Bookmark action
                    CupertinoContextMenuAction(
                      onPressed: () {
                        Navigator.pop(context);
                        _toggleSave(post);
                      },
                      child: Row(
                        children: [
                          Icon(
                            isSaved ? EvaIcons.bookmark : EvaIcons.bookmarkOutline,
                            size: 20,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                          const SizedBox(width: 12),
                          DefaultTextStyle(
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.0,
                            ),
                            child: Text(isSaved ? 'Unsave' : 'Save'),
                          ),
                        ],
                      ),
                    ),
                    // Open in Shorts action (only for video posts)
                    if (post.mediaType == 'video')
                      CupertinoContextMenuAction(
                        onPressed: () {
                          Navigator.pop(context);
                          _openInShorts(post);
                        },
                        child: Row(
                          children: [
                            Icon(
                              EvaIcons.playCircleOutline,
                              size: 20,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                            const SizedBox(width: 12),
                            DefaultTextStyle(
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.0,
                              ),
                              child: const Text('Open in Shorts'),
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
        ],
      ),
    );
  }

  void _openInShorts(Post post) {
    try {
      // Используем глобальный ключ для доступа к MainScreenState
      final mainScreenState = MainScreen.globalKey.currentState;
      
      if (mainScreenState != null) {
        print('PostGridWidget: Opening Shorts with post ${post.id}');
        mainScreenState.switchToShortsWithPost(post);
        
        // Закрываем текущий экран, если это возможно (например, ProfileScreen)
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        print('PostGridWidget: MainScreenState not found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open Shorts'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('PostGridWidget: Error opening Shorts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open Shorts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Показываем пустое состояние только если список пуст И не идет загрузка
    if (widget.posts.isEmpty && !widget.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              EvaIcons.imageOutline,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No posts yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Share your first post!',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = (width - 2) / 3; // 3 колонки, 2px spacing (1px * 2)
        final itemHeight = itemWidth; // Квадратные элементы
        
        // Вычисляем высоту с учетом индикатора загрузки
        final itemCount = widget.posts.length + (widget.hasMorePosts && widget.isLoading ? 1 : 0);
        final calculatedHeight = _calculateGridHeight(itemCount, itemHeight);
        
        // Используем AnimatedSize для плавного изменения высоты
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: SizedBox(
            height: calculatedHeight,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(), // Отключаем скролл GridView
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: 1, // Строго квадратные элементы
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index == widget.posts.length) {
                  // Показать индикатор загрузки в конце
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 0.5,
                      ),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0095F6),
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }

                final post = widget.posts[index];
                final isLiked = _likedPosts[post.id] ?? post.isLiked;
                final isSaved = _savedPosts[post.id] ?? post.isSaved;
                
                // Используем LayoutBuilder для получения ограничений от GridView
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.maxWidth; // Квадратный элемент
                
                final postContent = Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      // Навигация к детальному экрану поста
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => PostDetailScreen(
                            initialPostId: post.id,
                            initialPosts: widget.posts,
                          ),
                        ),
                      );
                    },
                    onLongPress: () {
                      _showPostContextMenu(context, post, isLiked, isSaved);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                        // Post image/video
                        if (post.mediaType == 'video')
                          // Используем thumbnailUrl для видео, как в post_card.dart
                          post.thumbnailUrl != null && post.thumbnailUrl!.isNotEmpty
                              ? CachedNetworkImageWithSignedUrl(
                                  imageUrl: post.thumbnailUrl!,
                                  postId: post.id, // Передаем postId для уникального ключа кеша
                            fit: BoxFit.cover,
                                  placeholder: (context) => Container(
                                    color: Colors.grey[800],
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF0095F6),
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[800],
                                    child: const Center(
                                      child: Icon(
                                        EvaIcons.videoOutline,
                                        color: Colors.grey,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey[800],
                                  child: const Center(
                                    child: Icon(
                                      EvaIcons.videoOutline,
                                      color: Colors.grey,
                                      size: 32,
                                    ),
                                  ),
                          )
                        else
                          CachedNetworkImageWithSignedUrl(
                            imageUrl: post.mediaUrl,
                            postId: post.id,
                            fit: BoxFit.cover,
                            placeholder: (context) => Container(
                              color: Colors.grey[800],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF0095F6),
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[800],
                              child: const Center(
                                child: Icon(
                                  EvaIcons.imageOutline,
                                  color: Colors.grey,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                        
                            // Gradient overlay для лучшей видимости индикаторов
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.3),
                                    ],
                                    stops: const [0.6, 1.0],
                                  ),
                                ),
                              ),
                            ),
                            
                            // Video play indicator
                            if (post.mediaType == 'video')
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.4),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    EvaIcons.playCircleOutline,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            
                            // Likes indicator
                            if (post.likesCount > 0)
                              Positioned(
                                bottom: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.2),
                                      width: 0.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isLiked ? EvaIcons.heart : EvaIcons.heartOutline,
                                        color: isLiked ? Colors.red : Colors.white,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 4),
                                      DefaultTextStyle(
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          height: 1.0,
                                        ),
                                        child: Text(
                                          '${post.likesCount}',
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
                  ),
                );
                
                    return SizedBox(
                      width: size,
                      height: size,
                      child: postContent,
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  double _calculateGridHeight(int itemCount, double itemHeight) {
    if (itemCount == 0) return 200; // Минимальная высота для пустого состояния
    
    const int crossAxisCount = 3;
    
    // Вычисляем количество строк
    int rows = (itemCount / crossAxisCount).ceil();
    
    // Добавляем отступы: высота элементов + spacing между строками
    double totalHeight = (rows * itemHeight) + ((rows - 1) * 2) + 4; // +4 для padding (2px * 2)
    
    return totalHeight;
  }
}
