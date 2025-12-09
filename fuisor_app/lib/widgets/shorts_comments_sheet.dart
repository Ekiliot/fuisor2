import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../providers/posts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/safe_avatar.dart';
import '../utils/hashtag_utils.dart';
import '../screens/hashtag_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/username_error_notification.dart';
import '../widgets/app_notification.dart';

class ShortsCommentsSheet extends StatefulWidget {
  final String postId;
  final Post post;
  final VoidCallback? onCommentAdded;

  const ShortsCommentsSheet({
    super.key,
    required this.postId,
    required this.post,
    this.onCommentAdded,
  });

  @override
  State<ShortsCommentsSheet> createState() => _ShortsCommentsSheetState();
}

class _ShortsCommentsSheetState extends State<ShortsCommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commentFocusNode = FocusNode();
  final ApiService _apiService = ApiService();
  List<Comment> _comments = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreComments = true;
  int _currentPage = 1;
  String? _replyingToCommentId;
  String? _replyingToUsername;
  String? _editingCommentId;
  Set<String> _newCommentIds = {}; // Для отслеживания новых комментариев для анимации
  OverlayEntry? _usernameErrorOverlay;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _commentFocusNode.dispose();
    _hideUsernameErrorNotification();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // Load more comments
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreComments();
    }
  }

  Future<void> _loadComments({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _hasMoreComments = true;
        _comments.clear();
        _isLoading = true;
      });
    }

    try {
      final postsProvider = context.read<PostsProvider>();
      
      // Проверяем, есть ли закэшированные комментарии
      final cachedComments = postsProvider.getCachedComments(widget.postId);
      if (cachedComments != null && !refresh && _currentPage == 1) {
        // Используем кэшированные комментарии
        print('ShortsCommentsSheet: Используем закэшированные комментарии: ${cachedComments.length}');
        setState(() {
          _comments = cachedComments;
          _hasMoreComments = true; // Могут быть еще комментарии
          _isLoading = false;
        });
        return;
      }

      // Загружаем комментарии из API
      final result = await postsProvider.loadComments(widget.postId, page: _currentPage);
      
      final totalComments = result['total'] as int? ?? 0;
      final loadedComments = result['comments'] as List<Comment>;
      
      print('ShortsCommentsSheet: Загружено комментариев: ${loadedComments.length}, total из API: $totalComments');
      
      setState(() {
        _comments = loadedComments;
        _hasMoreComments = result['page'] < result['totalPages'];
        _isLoading = false;
      });
      
      // Обновляем счетчик комментариев в посте на основе total из API (после setState)
      // Устанавливаем точное значение счетчика из API
      postsProvider.setPostCommentsCount(widget.postId, totalComments);
      print('ShortsCommentsSheet: Счетчик комментариев обновлен до: $totalComments');
    } catch (e) {
      print('Error loading comments: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMore || !_hasMoreComments) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      _currentPage++;
      final postsProvider = context.read<PostsProvider>();
      final result = await postsProvider.loadComments(widget.postId, page: _currentPage);
      
      setState(() {
        _comments.addAll(result['comments'] as List<Comment>);
        _hasMoreComments = result['page'] < result['totalPages'];
        _isLoadingMore = false;
      });
    } catch (e) {
      print('Error loading more comments: $e');
      setState(() {
        _isLoadingMore = false;
        _currentPage--; // Revert page increment on error
      });
    }
  }

  Future<void> _addOrEditComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        if (mounted) {
          AppNotification.showError(context, 'Please log in to comment');
        }
        return;
      }

      _apiService.setAccessToken(accessToken);
      final authProvider = context.read<AuthProvider>();

      if (_editingCommentId != null) {
        // Edit existing comment
        await _apiService.updateComment(
          widget.postId,
          _editingCommentId!,
          content,
        );

        setState(() {
          final index = _comments.indexWhere((c) => c.id == _editingCommentId);
          if (index != -1) {
            _comments[index] = _comments[index].copyWith(content: content);
          }
          _editingCommentId = null;
        });
      } else {
        // Add new comment
        final newComment = await _apiService.addComment(
          widget.postId,
          content,
          parentCommentId: _replyingToCommentId,
        );

        _commentController.clear();
        
        final replyingToId = _replyingToCommentId;
        final currentUser = authProvider.currentUser;
        Comment? createdComment;
        
        setState(() {
          if (replyingToId != null) {
            // Это ответ на комментарий - добавляем в replies
            final parentIndex = _comments.indexWhere((c) => c.id == replyingToId);
            if (parentIndex != -1) {
              final parentComment = _comments[parentIndex];
              final updatedReplies = List<Comment>.from(parentComment.replies ?? []);
              
              // Преобразуем Comment из post.dart в Comment из user.dart
              final replyComment = Comment(
                id: newComment.id,
                postId: widget.postId,
                userId: newComment.userId,
                content: newComment.content,
                parentCommentId: newComment.parentCommentId,
                createdAt: newComment.createdAt,
                user: currentUser,
                likesCount: 0,
                dislikesCount: 0,
                isLiked: false,
                isDisliked: false,
              );
              
              updatedReplies.add(replyComment);
              createdComment = replyComment;
              _comments[parentIndex] = parentComment.copyWith(replies: updatedReplies);
              // Добавляем ID нового ответа для анимации
              _newCommentIds.add(replyComment.id);
              // Убираем из списка новых через 500ms (после завершения анимации)
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  setState(() {
                    _newCommentIds.remove(replyComment.id);
                  });
                }
              });
            }
          } else {
            // Это обычный комментарий - добавляем в начало списка
            final comment = Comment(
              id: newComment.id,
              postId: widget.postId,
              userId: newComment.userId,
              content: newComment.content,
              parentCommentId: newComment.parentCommentId,
              createdAt: newComment.createdAt,
              user: currentUser,
              likesCount: 0,
              dislikesCount: 0,
              isLiked: false,
              isDisliked: false,
            );
            createdComment = comment;
            _comments.insert(0, comment);
            // Добавляем ID нового комментария для анимации
            _newCommentIds.add(comment.id);
            // Убираем из списка новых через 1 секунду (после завершения анимации)
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  _newCommentIds.remove(comment.id);
                });
              }
            });
          }
          
          _replyingToCommentId = null;
          _replyingToUsername = null;
        });

        // Обновляем счетчик комментариев в посте (для обычных комментариев и ответов)
        print('ShortsCommentsSheet: Комментарий добавлен, обновляем счетчик');
        if (widget.onCommentAdded != null) {
          widget.onCommentAdded!();
        }
        // Также обновляем через provider напрямую (ответы тоже считаются как комментарии)
        final postsProvider = context.read<PostsProvider>();
        postsProvider.updatePostCommentsCount(widget.postId, 1);
        
        // Обновляем кэш комментариев
        if (createdComment != null) {
          await postsProvider.updateCommentsCache(widget.postId, createdComment!, parentCommentId: replyingToId);
        }
        
        print('ShortsCommentsSheet: Счетчик комментариев увеличен на 1 (включая ответы)');
        
        // Прокручиваем к новому комментарию (только для обычных комментариев)
        if (replyingToId == null && _comments.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } catch (e) {
      print('Error adding/editing comment: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          _editingCommentId != null 
              ? 'Failed to update comment: $e'
              : 'Failed to add comment: $e',
        );
      }
    }
  }

  void _replyToComment(String commentId, String username) {
    _cancelEdit();
    
    setState(() {
      _replyingToCommentId = commentId;
      _replyingToUsername = username;
    });
    _commentController.text = '@$username ';
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _commentFocusNode.requestFocus();
      }
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToUsername = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingCommentId = null;
      _commentController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, // Увеличена высота модального окна
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
      child: SafeArea(
        top: false,
        child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text(
                  'Comments',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(EvaIcons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          
          const Divider(
            color: Color(0xFF404040),
            height: 1,
            thickness: 0.5,
          ),

          // Comments List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0095F6),
                    ),
                  )
                : _comments.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              EvaIcons.messageCircle,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No comments yet',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Be the first to comment!',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _comments.length + (_hasMoreComments ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _comments.length) {
                            return _isLoadingMore
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF0095F6),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink();
                          }

                          final comment = _comments[index];
                          final isOwnComment = currentUser?.id == comment.userId;
                          final isNewComment = _newCommentIds.contains(comment.id);

                          // Анимируем только новые комментарии
                          if (isNewComment) {
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 30 * (1 - value)),
                                    child: Transform.scale(
                                      scale: 0.9 + (0.1 * value),
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              child: _buildCommentItem(comment, isOwnComment),
                            );
                          } else {
                            return _buildCommentItem(comment, isOwnComment);
                          }
                        },
                      ),
          ),

          // Reply indicator
          if (_replyingToCommentId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF262626),
              child: Row(
                children: [
                  Icon(
                    EvaIcons.arrowBack,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Replying to $_replyingToUsername',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _cancelReply,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color(0xFF0095F6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Edit indicator
          if (_editingCommentId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF262626),
              child: Row(
                children: [
                  Icon(
                    EvaIcons.edit,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Editing comment',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _cancelEdit,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color(0xFF0095F6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Comment input - поднимается с клавиатурой
          AnimatedPadding(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF262626),
              border: Border(
                top: BorderSide(
                  color: Color(0xFF404040),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  if (currentUser?.avatarUrl != null)
                    SafeAvatar(
                      imageUrl: currentUser!.avatarUrl,
                      radius: 18,
                      backgroundColor: const Color(0xFF404040),
                      fallbackIcon: EvaIcons.person,
                      iconColor: Colors.white,
                    )
                  else
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF404040),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        EvaIcons.person,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      focusNode: _commentFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _replyingToCommentId != null
                            ? 'Reply to $_replyingToUsername...'
                            : _editingCommentId != null
                                ? 'Edit your comment...'
                                : 'Add a comment...',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _addOrEditComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      EvaIcons.paperPlane,
                      color: _commentController.text.trim().isNotEmpty
                          ? const Color(0xFF0095F6)
                          : Colors.grey[600],
                    ),
                    onPressed: _commentController.text.trim().isNotEmpty
                        ? _addOrEditComment
                        : null,
                  ),
                ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildCommentItem(Comment comment, bool isOwnComment) {
    final authProvider = context.watch<AuthProvider>();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeAvatar(
            imageUrl: comment.user?.avatarUrl,
            radius: 18,
            backgroundColor: const Color(0xFF404040),
            fallbackIcon: EvaIcons.person,
            iconColor: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.user?.username ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _formatTimeAgo(comment.createdAt),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: HashtagUtils.parseTextWithHashtagsAndUsernames(
                      comment.content,
                      defaultStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  hashtagStyle: const TextStyle(
                    color: Color(0xFF0095F6),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      usernameStyle: const TextStyle(
                        color: Color(0xFF0095F6),
                        fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  onHashtagTap: _navigateToHashtag,
                      onUsernameTap: _navigateToUserByUsername,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildAnimatedLikeButton(
                      comment: comment,
                      onTap: () => _likeComment(comment),
                    ),
                    const SizedBox(width: 16),
                    _buildActionButton(
                      icon: EvaIcons.messageCircle,
                      label: 'Reply',
                      color: Colors.grey[400],
                      onTap: () => _replyToComment(
                        comment.id,
                        comment.user?.username ?? 'Unknown',
                      ),
                    ),
                    if (isOwnComment) ...[
                      const SizedBox(width: 16),
                      _buildActionButton(
                        icon: EvaIcons.edit,
                        label: 'Edit',
                        color: Colors.grey[400],
                        onTap: () => _editComment(comment),
                      ),
                      const SizedBox(width: 16),
                      _buildActionButton(
                        icon: EvaIcons.trash,
                        label: 'Delete',
                        color: Colors.red,
                        onTap: () => _deleteComment(comment.id),
                      ),
                    ],
                  ],
                ),
                // Replies
                if (comment.replies != null && comment.replies!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...comment.replies!.map((reply) {
                    final isNewReply = _newCommentIds.contains(reply.id);
                    final replyWidget = Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            SafeAvatar(
                              imageUrl: reply.user?.avatarUrl,
                              radius: 16,
                              backgroundColor: const Color(0xFF404040),
                              fallbackIcon: EvaIcons.person,
                              iconColor: Colors.white,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          reply.user?.username ?? 'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatTimeAgo(reply.createdAt),
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text.rich(
                                    TextSpan(
                                      children: HashtagUtils.parseTextWithHashtagsAndUsernames(
                                        reply.content,
                                        defaultStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    hashtagStyle: const TextStyle(
                                      color: Color(0xFF0095F6),
                                      fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        usernameStyle: const TextStyle(
                                          color: Color(0xFF0095F6),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                    ),
                                    onHashtagTap: _navigateToHashtag,
                                        onUsernameTap: _navigateToUserByUsername,
                                      ),
                                    ),
                                  ),
                                  // Убрали лайки для ответов - только удаление для своих ответов
                                  if (authProvider.currentUser?.id == reply.userId) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        _buildActionButton(
                                          icon: EvaIcons.trash,
                                          label: 'Delete',
                                          color: Colors.red,
                                          onTap: () => _deleteReply(comment, reply),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    
                    // Анимируем только новые ответы
                    if (isNewReply) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: Transform.scale(
                                scale: 0.95 + (0.05 * value),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: replyWidget,
                      );
                    } else {
                      return replyWidget;
                    }
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    final effectiveColor = color ?? Colors.grey[400]!;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: effectiveColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: effectiveColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Анимированная кнопка лайка с плавным изменением счетчика
  Widget _buildAnimatedLikeButton({
    required Comment comment,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            EvaIcons.heart,
            size: 16,
            color: comment.isLiked ? Colors.red : Colors.grey[400],
          ),
          const SizedBox(width: 4),
          // Анимированный счетчик лайков
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(
                scale: Tween<double>(
                  begin: 1.2,
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
            child: Text(
              comment.likesCount > 0
                  ? '${comment.likesCount}'
                  : 'Like',
              key: ValueKey<int>(comment.likesCount),
              style: TextStyle(
                color: comment.isLiked ? Colors.red : Colors.grey[400],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _likeComment(Comment comment) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      final result = await _apiService.likeComment(widget.postId, comment.id);

      setState(() {
        final index = _comments.indexWhere((c) => c.id == comment.id);
        if (index != -1) {
          _comments[index] = _comments[index].copyWith(
            isLiked: result['isLiked'] == true,
            isDisliked: result['isDisliked'] == false,
            likesCount: result['isLiked'] == true && !comment.isLiked
                ? comment.likesCount + 1
                : result['isLiked'] == false && comment.isLiked
                    ? comment.likesCount - 1
                    : comment.likesCount,
          );
        }
      });
    } catch (e) {
      print('Error liking comment: $e');
    }
  }


  void _editComment(Comment comment) {
    _cancelReply();
    setState(() {
      _editingCommentId = comment.id;
      _commentController.text = comment.content;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _commentFocusNode.requestFocus();
      }
    });
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: const Text(
            'Delete Comment',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Are you sure you want to delete this comment?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF0095F6)),
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

      if (confirm == true) {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          _apiService.setAccessToken(accessToken);
          await _apiService.deleteComment(widget.postId, commentId);
          
          setState(() {
            _comments.removeWhere((c) => c.id == commentId);
          });

          if (mounted) {
            AppNotification.showSuccess(
              context,
              'Comment deleted successfully',
            );
          }
        }
      }
    } catch (e) {
      print('Error deleting comment: $e');
    }
  }

  Future<void> _deleteReply(Comment parentComment, Comment reply) async {
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: const Text(
            'Delete Reply',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Are you sure you want to delete this reply?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF0095F6)),
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

      if (confirm == true) {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          _apiService.setAccessToken(accessToken);
          await _apiService.deleteComment(widget.postId, reply.id);
          
          setState(() {
            final parentIndex = _comments.indexWhere((c) => c.id == parentComment.id);
            if (parentIndex != -1) {
              final updatedReplies = List<Comment>.from(_comments[parentIndex].replies!);
              updatedReplies.removeWhere((r) => r.id == reply.id);
              _comments[parentIndex] = _comments[parentIndex].copyWith(
                replies: updatedReplies,
              );
            }
          });

          if (mounted) {
            AppNotification.showSuccess(
              context,
              'Reply deleted successfully',
            );
          }
        }
      }
    } catch (e) {
      print('Error deleting reply: $e');
    }
  }

  void _navigateToHashtag(String hashtag) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HashtagScreen(hashtag: hashtag),
      ),
    );
  }

  Future<void> _navigateToUserByUsername(String username) async {
    print('ShortsCommentsSheet: Navigating to user by username: $username');
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
      _apiService.setAccessToken(accessToken);
      
      final user = await _apiService.getUserByUsername(username);
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: user.id),
          ),
        );
      }
    } catch (e) {
      print('ShortsCommentsSheet: Error navigating to user: $e');
      if (mounted) {
        _showUsernameErrorNotification();
      }
    }
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
    _usernameErrorOverlay?.remove();
    _usernameErrorOverlay = null;
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '${years}y';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo';
    } else if (difference.inDays > 0) {
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

