import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/news.dart';
import '../providers/news_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/safe_avatar.dart';
import '../widgets/animated_app_bar_title.dart';
import '../widgets/app_notification.dart';
import '../widgets/hashtag_text.dart';
import 'hashtag_screen.dart';
import 'profile_screen.dart';

class NewsCommentsScreen extends StatefulWidget {
  final String newsId;
  final News? news;

  const NewsCommentsScreen({
    super.key,
    required this.newsId,
    this.news,
  });

  @override
  State<NewsCommentsScreen> createState() => _NewsCommentsScreenState();
}

class _NewsCommentsScreenState extends State<NewsCommentsScreen> {
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
  Comment? _editingComment;

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
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

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
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      final newsProvider = context.read<NewsProvider>();
      
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }
      
      final result = await newsProvider.loadComments(widget.newsId, page: _currentPage);
      
      setState(() {
        _comments = result['comments'] as List<Comment>;
        _hasMoreComments = result['page'] < result['totalPages'];
        _isLoading = false;
      });
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
      final newsProvider = context.read<NewsProvider>();
      final result = await newsProvider.loadComments(
        widget.newsId,
        page: _currentPage + 1,
      );

      setState(() {
        _comments.addAll(result['comments'] as List<Comment>);
        _currentPage++;
        _hasMoreComments = result['page'] < result['totalPages'];
        _isLoadingMore = false;
      });
    } catch (e) {
      print('Error loading more comments: $e');
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _addComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    try {
      if (_editingCommentId != null && _editingComment != null) {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          _apiService.setAccessToken(accessToken);
          final updatedComment = await _apiService.updateNewsComment(
            widget.newsId,
            _editingCommentId!,
            content,
          );

          setState(() {
            final index = _comments.indexWhere((c) => c.id == _editingCommentId);
            if (index != -1) {
              _comments[index] = updatedComment.copyWith(
                replies: _editingComment!.replies,
              );
            }
            _editingCommentId = null;
            _editingComment = null;
          });

          _commentController.clear();
          if (mounted) {
            AppNotification.showSuccess(context, 'Comment updated successfully');
          }
        }
      } else {
        final newsProvider = context.read<NewsProvider>();
        await newsProvider.addComment(
          widget.newsId,
          content,
          parentCommentId: _replyingToCommentId,
        );

        _commentController.clear();
        setState(() {
          _replyingToCommentId = null;
          _replyingToUsername = null;
        });

        _loadComments(refresh: true);
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
      _editingComment = null;
      _commentController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBackOutline, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const AnimatedAppBarTitle(
          text: 'Comments',
        ),
      ),
      body: Column(
        children: [
          if (widget.news != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                border: Border(
                  bottom: BorderSide(color: const Color(0xFF262626)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.news!.coverImageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.news!.coverImageUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF262626),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(EvaIcons.fileTextOutline, color: Colors.white54),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.news!.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.news!.commentsCount} comments',
                          style: const TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0095F6),
                    ),
                  )
                : _comments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              EvaIcons.messageCircleOutline,
                              size: 64,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No comments yet',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadComments(refresh: true),
                        color: const Color(0xFF0095F6),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _comments.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _comments.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF0095F6),
                                  ),
                                ),
                              );
                            }

                            final comment = _comments[index];
                            return _buildCommentItem(comment, currentUser);
                          },
                        ),
                      ),
          ),
          if (currentUser != null) _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildCommentItem(Comment comment, User? currentUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(userId: comment.userId),
                  ),
                );
              },
              child: SafeAvatar(
                imageUrl: comment.user?.avatarUrl,
                radius: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileScreen(userId: comment.userId),
                            ),
                          );
                        },
                        child: Text(
                          comment.user?.username ?? 'Unknown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(comment.createdAt),
                        style: const TextStyle(
                          color: Color(0xFF8E8E8E),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  HashtagText(
                    text: comment.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    onHashtagTap: (hashtag) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => HashtagScreen(hashtag: hashtag),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (currentUser != null)
                        TextButton(
                          onPressed: () => _replyToComment(comment.id, comment.user?.username ?? 'user'),
                          child: const Text(
                            'Reply',
                            style: TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (currentUser?.id == comment.userId)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _editingCommentId = comment.id;
                              _editingComment = comment;
                              _commentController.text = comment.content;
                            });
                            _commentFocusNode.requestFocus();
                          },
                          child: const Text(
                            'Edit',
                            style: TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (comment.replies != null && comment.replies!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 44, top: 8),
            child: Column(
              children: comment.replies!.map((reply) => _buildCommentItem(reply, currentUser)).toList(),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(color: const Color(0xFF262626)),
        ),
      ),
      child: Column(
        children: [
          if (_replyingToUsername != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to @$_replyingToUsername',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(EvaIcons.close, size: 16, color: Colors.white54),
                    onPressed: _cancelReply,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          if (_editingCommentId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Editing comment',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(EvaIcons.close, size: 16, color: Colors.white54),
                    onPressed: _cancelEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _commentFocusNode,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _replyingToUsername != null
                        ? 'Reply to @$_replyingToUsername...'
                        : 'Add a comment...',
                    hintStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFF262626)),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF262626),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _addComment(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(EvaIcons.paperPlaneOutline, color: Color(0xFF0095F6)),
                onPressed: _addComment,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo';
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

