import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../models/user.dart';
import '../widgets/safe_avatar.dart';
import '../screens/edit_post_screen.dart';
import '../screens/comments_screen.dart';
import '../screens/hashtag_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/posts_provider.dart';
import '../services/api_service.dart';
import 'hashtag_text.dart';
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

class _PostCardState extends State<PostCard> {
  bool _isLiked = false;
  bool _isSaved = false;
  bool _showComments = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _isSaved = widget.post.isSaved;
  }

  @override
  void dispose() {
    _commentController.dispose();
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
      margin: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SafeAvatar(
                  imageUrl: widget.post.user?.avatarUrl,
                  radius: 18,
                  backgroundColor: const Color(0xFF262626),
                  fallbackIcon: EvaIcons.personOutline,
                  iconColor: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.post.user?.name ?? widget.post.user?.username ?? 'Unknown',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '@${widget.post.user?.username ?? 'unknown'}',
                        style: const TextStyle(
                          color: Color(0xFF8E8E8E),
                          fontSize: 12,
                        ),
                      ),
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

          // Media
          AspectRatio(
            aspectRatio: 1,
            child: widget.post.mediaType == 'video'
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(
                        EvaIcons.playCircleOutline,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: widget.post.mediaUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
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

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isLiked = !_isLiked;
                        });
                        widget.onLike();
                      },
                      child: Icon(
                        _isLiked ? EvaIcons.heart : EvaIcons.heartOutline,
                        color: _isLiked ? Colors.red : Colors.white,
                        size: 28,
                      ),
                    ),
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
                        );
                      },
                      child: const Icon(
                        EvaIcons.messageCircleOutline,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
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

                // Likes count
                if (widget.post.likesCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${widget.post.likesCount} ${widget.post.likesCount == 1 ? 'like' : 'likes'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),

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
                          child: HashtagText(
                            text: widget.post.caption,
                            style: const TextStyle(color: Colors.white),
                            hashtagStyle: const TextStyle(
                              color: Color(0xFF0095F6),
                              fontWeight: FontWeight.w600,
                            ),
                            onHashtagTap: _navigateToHashtag,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Comments count
                if (widget.post.commentsCount > 0)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showComments = !_showComments;
                      });
                    },
                    child: Text(
                      'View all ${widget.post.commentsCount} comments',
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
                                child: HashtagText(
                                  text: comment.content,
                                  style: const TextStyle(color: Colors.white),
                                  hashtagStyle: const TextStyle(
                                    color: Color(0xFF0095F6),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  onHashtagTap: _navigateToHashtag,
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
                      // Rounded comment input field matching AnimatedTextField style
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A), // Same as AnimatedTextField
                            borderRadius: BorderRadius.circular(20), // Same as AnimatedTextField
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.3), // Same as AnimatedTextField enabledBorder
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: _commentController,
                            decoration: const InputDecoration(
                              hintText: 'Add a comment...',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, // Reduced padding
                                vertical: 12, // Reduced padding
                              ),
                              hintStyle: TextStyle(
                                color: Color(0xFF8E8E8E),
                                fontSize: 14,
                              ),
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                widget.onComment(value.trim(), null);
                                _commentController.clear(); // Clear the field after submitting
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Send button
                      GestureDetector(
                        onTap: () {
                          final value = _commentController.text.trim();
                          if (value.isNotEmpty) {
                            widget.onComment(value, null);
                            _commentController.clear();
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0095F6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            EvaIcons.paperPlaneOutline,
                            color: Colors.white,
                            size: 20,
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
