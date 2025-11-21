import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user.dart';
import '../providers/posts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/safe_avatar.dart';
import '../utils/hashtag_utils.dart';
import '../widgets/hashtag_text.dart';
import '../widgets/animated_app_bar_title.dart';
import 'hashtag_screen.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  final Post? post;

  const CommentsScreen({
    super.key,
    required this.postId,
    this.post,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
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
  bool _isHeaderCollapsed = false;

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

    // Check if header should be collapsed
    // Only collapse when scrolling down, never auto-expand
    final offset = _scrollController.offset;
    
    if (offset > 50 && !_isHeaderCollapsed) {
      setState(() {
        _isHeaderCollapsed = true;
      });
    }

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
      final result = await postsProvider.loadComments(widget.postId, page: _currentPage);
      
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
      final postsProvider = context.read<PostsProvider>();
      final result = await postsProvider.loadComments(
        widget.postId,
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
      // Check if editing or adding new comment
      if (_editingCommentId != null && _editingComment != null) {
        // Editing existing comment
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          _apiService.setAccessToken(accessToken);
          final updatedComment = await _apiService.updateComment(
            widget.postId,
            _editingCommentId!,
            content,
          );

          // Update comment in local state
          setState(() {
            final index = _comments.indexWhere((c) => c.id == _editingCommentId);
            if (index != -1) {
              _comments[index] = updatedComment.copyWith(
                replies: _editingComment!.replies,
                isLiked: _editingComment!.isLiked,
                isDisliked: _editingComment!.isDisliked,
                likesCount: _editingComment!.likesCount,
                dislikesCount: _editingComment!.dislikesCount,
              );
            } else {
              // Check in replies
              for (var c in _comments) {
                if (c.replies != null) {
                  final replyIndex = c.replies!.indexWhere((r) => r.id == _editingCommentId);
                  if (replyIndex != -1) {
                    c.replies![replyIndex] = updatedComment.copyWith(
                      isLiked: _editingComment!.isLiked,
                      isDisliked: _editingComment!.isDisliked,
                      likesCount: _editingComment!.likesCount,
                      dislikesCount: _editingComment!.dislikesCount,
                    );
                  }
                }
              }
            }
            _editingCommentId = null;
            _editingComment = null;
          });

          _commentController.clear();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Comment updated successfully'),
                backgroundColor: Color(0xFF0095F6),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        // Adding new comment
        final postsProvider = context.read<PostsProvider>();
        await postsProvider.addComment(
          widget.postId,
          content,
          parentCommentId: _replyingToCommentId,
        );

        _commentController.clear();
        setState(() {
          _replyingToCommentId = null;
          _replyingToUsername = null;
        });

        // Reload comments to show the new one
        _loadComments(refresh: true);
      }
    } catch (e) {
      print('Error adding/editing comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editingCommentId != null 
                ? 'Failed to update comment: $e'
                : 'Failed to add comment: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _replyToComment(String commentId, String username) {
    // Cancel any active edit
    _cancelEdit();
    
    setState(() {
      _replyingToCommentId = commentId;
      _replyingToUsername = username;
    });
    _commentController.text = '@$username ';
    // Request focus after a short delay to ensure the widget is built
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
          // Post Preview Header (collapsible)
          if (widget.post != null)
            _buildPostPreview(widget.post!),

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
                              EvaIcons.messageCircleOutline,
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
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          // Detect overscroll at the top (pull down when already at top)
                          if (notification is OverscrollNotification) {
                            if (notification.overscroll < -20 && _isHeaderCollapsed) {
                              // Pulling down from the top = expand header
                              setState(() {
                                _isHeaderCollapsed = false;
                              });
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
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
                            return _buildCommentItem(comment, currentUser);
                          },
                        ),
                      ),
          ),

          // Reply/Edit indicator
          if (_replyingToCommentId != null || _editingCommentId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF121212),
                border: Border(
                  top: BorderSide(color: Color(0xFF262626), width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _editingCommentId != null
                          ? 'Edit comment'
                          : 'Replying to @$_replyingToUsername',
                      style: const TextStyle(
                        color: Color(0xFF0095F6),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(EvaIcons.close, color: Colors.white, size: 20),
                    onPressed: () {
                      _cancelReply();
                      _cancelEdit();
                    },
                  ),
                ],
              ),
            ),

          // Comment Input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF000000),
              border: Border(
                top: BorderSide(color: Color(0xFF262626), width: 0.5),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // User avatar
                  if (currentUser != null)
                    SafeAvatar(
                      imageUrl: currentUser.avatarUrl,
                      radius: 20,
                      backgroundColor: const Color(0xFF262626),
                      fallbackIcon: EvaIcons.personOutline,
                      iconColor: Colors.white,
                    ),
                  const SizedBox(width: 12),
                  // Comment input field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF262626),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: const Color(0xFF404040),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              focusNode: _commentFocusNode,
                              decoration: InputDecoration(
                                hintText: _editingCommentId != null 
                                    ? 'Edit your comment...' 
                                    : 'Add a comment...',
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                hintStyle: const TextStyle(
                                  color: Color(0xFF8E8E8E),
                                  fontSize: 14,
                                ),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              maxLines: null,
                              textInputAction: TextInputAction.newline,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              EvaIcons.paperPlaneOutline,
                              color: Color(0xFF0095F6),
                              size: 24,
                            ),
                            onPressed: _addComment,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(Comment comment, User? currentUser) {
    final isOwnComment = currentUser != null && comment.userId == currentUser.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              SafeAvatar(
                imageUrl: comment.user?.avatarUrl,
                radius: 18,
                backgroundColor: const Color(0xFF262626),
                fallbackIcon: EvaIcons.personOutline,
                iconColor: Colors.white,
              ),
              const SizedBox(width: 12),
              // Comment content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.user?.username ?? 'Unknown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTimeAgo(comment.createdAt),
                          style: const TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: HashtagUtils.parseTextWithHashtags(
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
                          onHashtagTap: _navigateToHashtag,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Like/Dislike buttons and Reply button
                    Row(
                      children: [
                        // Like button
                        GestureDetector(
                          onTap: () => _toggleCommentLike(comment),
                          child: Row(
                            children: [
                              Icon(
                                EvaIcons.arrowUpward,
                                size: 16,
                                color: comment.isLiked 
                                    ? Colors.green 
                                    : const Color(0xFF8E8E8E),
                              ),
                              if (comment.likesCount > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  comment.likesCount.toString(),
                                  style: TextStyle(
                                    color: comment.isLiked 
                                        ? Colors.green 
                                        : const Color(0xFF8E8E8E),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Dislike button
                        GestureDetector(
                          onTap: () => _toggleCommentDislike(comment),
                          child: Row(
                            children: [
                              Icon(
                                EvaIcons.arrowDownward,
                                size: 16,
                                color: comment.isDisliked 
                                    ? Colors.red 
                                    : const Color(0xFF8E8E8E),
                              ),
                              if (comment.dislikesCount > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  comment.dislikesCount.toString(),
                                  style: TextStyle(
                                    color: comment.isDisliked 
                                        ? Colors.red 
                                        : const Color(0xFF8E8E8E),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Reply button
                        GestureDetector(
                          onTap: () => _replyToComment(
                            comment.id,
                            comment.user?.username ?? 'Unknown',
                          ),
                          child: Row(
                            children: [
                              Icon(
                                EvaIcons.messageCircleOutline,
                                size: 14,
                                color: const Color(0xFF8E8E8E),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Reply',
                                style: TextStyle(
                                  color: Color(0xFF8E8E8E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Menu button (three dots)
              PopupMenuButton<String>(
                icon: const Icon(
                  EvaIcons.moreHorizontal,
                  size: 18,
                  color: Color(0xFF8E8E8E),
                ),
                onSelected: (value) async {
                  if (value == 'edit') {
                    _editComment(comment);
                  } else if (value == 'delete') {
                    _deleteComment(comment.id);
                  } else if (value == 'report') {
                    _reportComment(comment);
                  }
                },
                itemBuilder: (context) {
                  if (isOwnComment) {
                    return [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(EvaIcons.editOutline, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Edit', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(EvaIcons.trashOutline, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ];
                  } else {
                    return [
                      const PopupMenuItem<String>(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(EvaIcons.flagOutline, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Report', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ];
                  }
                },
              ),
            ],
          ),
          // Replies
          if (comment.replies != null && comment.replies!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 12),
              child: Column(
                children: comment.replies!
                    .map((reply) => _buildReplyItem(reply, currentUser))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(Comment reply, User? currentUser) {
    final isOwnReply = currentUser != null && reply.userId == currentUser.id;

    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          SafeAvatar(
            imageUrl: reply.user?.avatarUrl,
            radius: 14,
            backgroundColor: const Color(0xFF262626),
            fallbackIcon: EvaIcons.personOutline,
            iconColor: Colors.white,
          ),
          const SizedBox(width: 8),
          // Reply content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      reply.user?.username ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatTimeAgo(reply.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF8E8E8E),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                HashtagText(
                  text: reply.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  hashtagStyle: const TextStyle(
                    color: Color(0xFF0095F6),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  onHashtagTap: _navigateToHashtag,
                ),
                const SizedBox(height: 6),
                // Reply button
                GestureDetector(
                  onTap: () => _replyToComment(
                    reply.parentCommentId ?? reply.id,
                    reply.user?.username ?? 'Unknown',
                  ),
                  child: const Text(
                    'Reply',
                    style: TextStyle(
                      color: Color(0xFF8E8E8E),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Menu button (three dots) for replies
          PopupMenuButton<String>(
            icon: const Icon(
              EvaIcons.moreHorizontal,
              size: 16,
              color: Color(0xFF8E8E8E),
            ),
            onSelected: (value) async {
              if (value == 'edit') {
                _editComment(reply);
              } else if (value == 'delete') {
                _deleteComment(reply.id);
              } else if (value == 'report') {
                _reportComment(reply);
              }
            },
            itemBuilder: (context) {
              if (isOwnReply) {
                return [
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(EvaIcons.editOutline, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text('Edit', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(EvaIcons.trashOutline, color: Colors.red, size: 16),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ],
                    ),
                  ),
                ];
              } else {
                return [
                  const PopupMenuItem<String>(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(EvaIcons.flagOutline, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text('Report', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ];
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPostPreview(Post post) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        final dragDistance = details.primaryVelocity ?? 0;
        
        // If swiping down fast (positive velocity) or dragged down enough
        if (dragDistance > 300 && !_isHeaderCollapsed) {
          // Swipe down = collapse
          setState(() {
            _isHeaderCollapsed = true;
          });
        } 
        // If swiping up fast (negative velocity) or dragged up enough
        else if (dragDistance < -300 && _isHeaderCollapsed) {
          // Swipe up = expand
          setState(() {
            _isHeaderCollapsed = false;
          });
        }
      },
      onTap: () {
        // Tap to toggle collapsed state
        setState(() {
          _isHeaderCollapsed = !_isHeaderCollapsed;
        });
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF000000),
          border: Border(
            bottom: BorderSide(color: Color(0xFF262626), width: 0.5),
          ),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _isHeaderCollapsed 
                ? _buildCollapsedHeader(post)
                : _buildExpandedHeader(post),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedHeader(Post post) {
    return Row(
      children: [
        // Small media thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 50,
            height: 50,
            child: post.mediaType == 'video'
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(
                        EvaIcons.playCircleOutline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  )
                : Image.network(
                    post.mediaUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        EvaIcons.imageOutline,
                        color: Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        // Caption and likes
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.caption.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: HashtagUtils.parseTextWithHashtags(
                      post.caption,
                      defaultStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      hashtagStyle: const TextStyle(
                        color: Color(0xFF0095F6),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      onHashtagTap: _navigateToHashtag,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              Text(
                '${post.likesCount} ${post.likesCount == 1 ? 'like' : 'likes'}',
                style: const TextStyle(
                  color: Color(0xFF8E8E8E),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedHeader(Post post) {
    // Extract hashtags from caption
    final hashtags = _extractHashtags(post.caption);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User info
        Row(
          children: [
            SafeAvatar(
              imageUrl: post.user?.avatarUrl,
              radius: 16,
              backgroundColor: const Color(0xFF262626),
              fallbackIcon: EvaIcons.personOutline,
              iconColor: Colors.white,
            ),
            const SizedBox(width: 10),
            Text(
              post.user?.username ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              _formatTimeAgo(post.createdAt),
              style: const TextStyle(
                color: Color(0xFF8E8E8E),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Media
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: post.mediaType == 'video'
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(
                        EvaIcons.playCircleOutline,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  )
                : Image.network(
                    post.mediaUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        EvaIcons.imageOutline,
                        color: Colors.grey,
                        size: 48,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        // Likes
        Text(
          '${post.likesCount} ${post.likesCount == 1 ? 'like' : 'likes'}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Caption
        if (post.caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: _buildCaptionWithHashtags(post.caption),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
        // Hashtags
        if (hashtags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: hashtags.map((tag) => Text(
              tag,
              style: const TextStyle(
                color: Color(0xFF0095F6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            )).toList(),
          ),
        ],
      ],
    );
  }

  List<String> _extractHashtags(String text) {
    final regex = RegExp(r'#[а-яёА-ЯЁa-zA-Z0-9_]+');
    final matches = regex.allMatches(text);
    return matches.map((m) => m.group(0)!).toList();
  }

  List<TextSpan> _buildCaptionWithHashtags(String caption) {
    return HashtagUtils.parseTextWithHashtags(
      caption,
      defaultStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
      ),
      hashtagStyle: const TextStyle(
        color: Color(0xFF0095F6),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      onHashtagTap: _navigateToHashtag,
    );
  }

  void _navigateToHashtag(String hashtag) {
    print('CommentsScreen: Navigating to hashtag: $hashtag');
    print('CommentsScreen: Context is mounted: ${mounted}');
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HashtagScreen(hashtag: hashtag),
        ),
      );
      print('CommentsScreen: Navigation completed');
    } catch (e) {
      print('CommentsScreen: Navigation error: $e');
    }
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

  Future<void> _deleteComment(String commentId) async {
    try {
      // Show confirmation dialog
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
        // Delete comment via API
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          _apiService.setAccessToken(accessToken);
          await _apiService.deleteComment(widget.postId, commentId);
          
          // Remove comment from local state
          setState(() {
            _comments.removeWhere((c) => c.id == commentId);
            // Also remove from replies
            for (var comment in _comments) {
              comment.replies?.removeWhere((r) => r.id == commentId);
            }
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Comment deleted successfully'),
                backgroundColor: Color(0xFF0095F6),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error deleting comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete comment: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _editComment(Comment comment) {
    // Cancel any active reply
    _cancelReply();
    
    // Set edit mode
    setState(() {
      _editingCommentId = comment.id;
      _editingComment = comment;
      _commentController.text = comment.content;
    });
    
    // Request focus after a short delay to ensure the widget is built
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _commentFocusNode.requestFocus();
      }
    });
  }

  Future<void> _reportComment(Comment comment) async {
    try {
      final reasons = [
        'Spam',
        'Harassment or bullying',
        'False information',
        'Hate speech',
        'Violence',
        'Other'
      ];

      final selectedReason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: const Text(
            'Report Comment',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: reasons.map((reason) {
                return ListTile(
                  title: Text(
                    reason,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(context).pop(reason),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF8E8E8E)),
              ),
            ),
          ],
        ),
      );

      if (selectedReason != null) {
        // TODO: Implement report API endpoint
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Comment reported: $selectedReason'),
              backgroundColor: const Color(0xFF0095F6),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('Error reporting comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to report comment: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _toggleCommentLike(Comment comment) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }
      
      print('Toggling like for comment: ${comment.id}');
      print('Current state - isLiked: ${comment.isLiked}, likesCount: ${comment.likesCount}');
      
      final result = await _apiService.likeComment(widget.postId, comment.id);
      
      print('API response: $result');
      print('Response type: ${result.runtimeType}');
      
      // Update comment in local state
      setState(() {
        final index = _comments.indexWhere((c) => c.id == comment.id);
        if (index != -1) {
          // Create updated comment with new like status
          var updatedComment = comment.copyWith(
            isLiked: result['isLiked'] == true,
            isDisliked: result['isDisliked'] == true,
          );
          
          // Update likes count based on the change
          if (result['isLiked'] == true && !comment.isLiked) {
            // User liked the comment
            updatedComment = updatedComment.copyWith(
              likesCount: comment.likesCount + 1,
            );
            print('Added like, new count: ${updatedComment.likesCount}');
          } else if (result['isLiked'] == false && comment.isLiked) {
            // User unliked the comment
            updatedComment = updatedComment.copyWith(
              likesCount: comment.likesCount - 1,
            );
            print('Removed like, new count: ${updatedComment.likesCount}');
          }
          
          // Update dislikes count if user switched from dislike to like
          if (result['isDisliked'] == false && comment.isDisliked) {
            updatedComment = updatedComment.copyWith(
              dislikesCount: comment.dislikesCount - 1,
            );
            print('Removed dislike due to like, new dislike count: ${updatedComment.dislikesCount}');
          }
          
          // Update replies if they exist
          if (comment.replies != null && comment.replies!.isNotEmpty) {
            updatedComment = updatedComment.copyWith(replies: comment.replies);
          }
          
          _comments[index] = updatedComment;
          print('Updated comment state - isLiked: ${updatedComment.isLiked}, likesCount: ${updatedComment.likesCount}');
        }
      });
    } catch (e) {
      print('Error toggling comment like: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to like comment: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleCommentDislike(Comment comment) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }
      
      print('Toggling dislike for comment: ${comment.id}');
      print('Current state - isDisliked: ${comment.isDisliked}, dislikesCount: ${comment.dislikesCount}');
      
      final result = await _apiService.dislikeComment(widget.postId, comment.id);
      
      print('API response: $result');
      print('Response type: ${result.runtimeType}');
      
      // Update comment in local state
      setState(() {
        final index = _comments.indexWhere((c) => c.id == comment.id);
        if (index != -1) {
          // Create updated comment with new dislike status
          var updatedComment = comment.copyWith(
            isLiked: result['isLiked'] == true,
            isDisliked: result['isDisliked'] == true,
          );
          
          // Update dislikes count based on the change
          if (result['isDisliked'] == true && !comment.isDisliked) {
            // User disliked the comment
            updatedComment = updatedComment.copyWith(
              dislikesCount: comment.dislikesCount + 1,
            );
            print('Added dislike, new count: ${updatedComment.dislikesCount}');
          } else if (result['isDisliked'] == false && comment.isDisliked) {
            // User undisliked the comment
            updatedComment = updatedComment.copyWith(
              dislikesCount: comment.dislikesCount - 1,
            );
            print('Removed dislike, new count: ${updatedComment.dislikesCount}');
          }
          
          // Update likes count if user switched from like to dislike
          if (result['isLiked'] == false && comment.isLiked) {
            updatedComment = updatedComment.copyWith(
              likesCount: comment.likesCount - 1,
            );
            print('Removed like due to dislike, new like count: ${updatedComment.likesCount}');
          }
          
          // Update replies if they exist
          if (comment.replies != null && comment.replies!.isNotEmpty) {
            updatedComment = updatedComment.copyWith(replies: comment.replies);
          }
          
          _comments[index] = updatedComment;
          print('Updated comment state - isDisliked: ${updatedComment.isDisliked}, dislikesCount: ${updatedComment.dislikesCount}');
        }
      });
    } catch (e) {
      print('Error toggling comment dislike: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to dislike comment: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

