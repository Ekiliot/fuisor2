import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../models/user.dart';
import 'video_thumbnail.dart';

class RecommendedPostsGrid extends StatelessWidget {
  final List<Post> posts;
  final bool isLoading;

  const RecommendedPostsGrid({
    Key? key,
    required this.posts,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildLoadingGrid();
    }

    if (posts.isEmpty) {
      return _buildEmptyState();
    }

    return _buildPostsGrid();
  }

  Widget _buildLoadingGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemHeight = (width - 2) / 3; // 3 columns, 2px spacing
        
        return SizedBox(
          height: _calculateGridHeight(6, itemHeight), // Show 6 skeleton items
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(1),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
              childAspectRatio: 1,
            ),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Container(
                color: Colors.grey[800],
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0095F6),
                    strokeWidth: 2,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 200,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              EvaIcons.imageOutline,
              size: 48,
              color: Color(0xFF8E8E8E),
            ),
            SizedBox(height: 12),
            Text(
              'No recommended posts yet',
              style: TextStyle(
                color: Color(0xFF8E8E8E),
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Follow more users to see recommendations',
              style: TextStyle(
                color: Color(0xFF8E8E8E),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemHeight = (width - 2) / 3; // 3 columns, 2px spacing
        
        return SizedBox(
          height: _calculateGridHeight(posts.length, itemHeight),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(1),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
              childAspectRatio: 1,
            ),
            itemCount: posts.length,
            itemBuilder: (context, index) {
          final post = posts[index];
          return GestureDetector(
            onTap: () {
              // TODO: Navigate to post detail
              print('Tapped on recommended post: ${post.id}');
            },
            child: Container(
              color: Colors.grey[800],
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Post image/video
                  if (post.mediaType == 'video')
                    VideoThumbnail(
                      videoUrl: post.mediaUrl,
                      fit: BoxFit.cover,
                    )
                  else
                    CachedNetworkImage(
                      imageUrl: post.mediaUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
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
                  
                  // Video play indicator
                  if (post.mediaType == 'video')
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        EvaIcons.playCircleOutline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  
                  // Likes indicator
                  if (post.likesCount > 0)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              post.isLiked ? EvaIcons.heart : EvaIcons.heartOutline,
                              color: post.isLiked ? Colors.red : Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${post.likesCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
        );
      },
    );
  }

  double _calculateGridHeight(int itemCount, double itemHeight) {
    if (itemCount == 0) return 200; // Empty state height
    
    const int crossAxisCount = 3;
    
    // Calculate number of rows
    int rows = (itemCount / crossAxisCount).ceil();
    
    // Add spacing: item heights + spacing between rows + padding
    double totalHeight = (rows * itemHeight) + ((rows - 1) * 1) + 2; // +2 for padding
    
    return totalHeight;
  }
}
