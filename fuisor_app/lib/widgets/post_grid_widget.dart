import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../models/user.dart';
import '../screens/post_detail_screen.dart';

class PostGridWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // Показываем пустое состояние только если список пуст И не идет загрузка
    if (posts.isEmpty && !isLoading) {
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
        final itemCount = posts.length + (hasMorePosts && isLoading ? 1 : 0);
        final calculatedHeight = _calculateGridHeight(itemCount, itemHeight);
        
        // Используем AnimatedSize для плавного изменения высоты
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: SizedBox(
            height: calculatedHeight,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(), // Отключаем скролл GridView
              padding: const EdgeInsets.all(1),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 1,
                mainAxisSpacing: 1,
                childAspectRatio: 1, // Строго квадратные элементы
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index == posts.length) {
                  // Показать индикатор загрузки в конце
                  return Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0095F6),
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }

                final post = posts[index];
                return GestureDetector(
                  onTap: () {
                    // Навигация к детальному экрану поста
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => PostDetailScreen(
                          initialPostId: post.id,
                          initialPosts: posts,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    color: Colors.grey[800],
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Post image/video
                        if (post.mediaType == 'video')
                          Container(
                            color: Colors.black,
                            child: const Center(
                              child: Icon(
                                EvaIcons.playCircleOutline,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
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
    double totalHeight = (rows * itemHeight) + ((rows - 1) * 1) + 2; // +2 для padding
    
    return totalHeight;
  }
}
