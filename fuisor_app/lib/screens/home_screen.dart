import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/posts_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/post_card.dart';
import '../widgets/stories_widget.dart';
import '../widgets/skeleton_post_card.dart';
import 'activity_screen.dart';
import 'chats_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  double? _savedScrollPosition; // Сохранение позиции скролла при refresh

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final accessToken = await _getAccessTokenFromAuthProvider();
      context.read<PostsProvider>().loadFeed(refresh: true, accessToken: accessToken);
      
      // Load notifications to update unread count
      final authProvider = context.read<AuthProvider>();
      context.read<NotificationsProvider>().loadNotifications(refresh: true, authProvider: authProvider);
    });
    
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  void _onScroll() async {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final postsProvider = context.read<PostsProvider>();
      // Проверяем, есть ли еще посты для загрузки
      if (postsProvider.hasMorePosts && !postsProvider.isLoading) {
        final accessToken = await _getAccessTokenFromAuthProvider();
        postsProvider.loadFeed(accessToken: accessToken);
      }
    }
  }

  Future<void> _onRefresh() async {
    try {
      // Сохраняем позицию скролла перед refresh
      if (_scrollController.hasClients) {
        _savedScrollPosition = _scrollController.position.pixels;
      }
      
      final postsProvider = context.read<PostsProvider>();
      final accessToken = await _getAccessTokenFromAuthProvider();
      await postsProvider.loadFeed(refresh: true, accessToken: accessToken);
      
      if (mounted) {
        _refreshController.refreshCompleted();
        
        // Восстанавливаем позицию скролла после обновления UI
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && 
              _scrollController.hasClients && 
              _savedScrollPosition != null &&
              _savedScrollPosition! > 0) {
            // Плавно прокручиваем к сохраненной позиции
            _scrollController.animateTo(
              _savedScrollPosition!,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feed updated!'),
            backgroundColor: Color(0xFF0095F6),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _refreshController.refreshFailed();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update feed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Получить токен из AuthProvider
  Future<String?> _getAccessTokenFromAuthProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token');
    } catch (e) {
      print('Error getting access token: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Fuisor',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Messages icon
          IconButton(
            icon: const Icon(EvaIcons.paperPlaneOutline, size: 28),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ChatsListScreen(),
                ),
              );
            },
          ),
          Consumer<NotificationsProvider>(
            builder: (context, notificationsProvider, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(EvaIcons.heartOutline, size: 28),
                    onPressed: () async {
                      final authProvider = context.read<AuthProvider>();
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ActivityScreen(),
                        ),
                      );
                      // Refresh notifications count when returning from Activity screen
                      context.read<NotificationsProvider>().loadNotifications(refresh: true, authProvider: authProvider);
                    },
                  ),
                  if (notificationsProvider.unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFED4956),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          notificationsProvider.unreadCount > 99 
                              ? '99+' 
                              : notificationsProvider.unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Selector<PostsProvider, Map<String, dynamic>>(
        selector: (_, provider) => {
          'feedPosts': provider.feedPosts,
          'isInitialLoading': provider.isInitialLoading,
          'isLoading': provider.isLoading,
          'isRefreshing': provider.isRefreshing,
          'error': provider.error,
        },
        shouldRebuild: (prev, next) {
          // Перестраиваем только если изменились важные данные
          return prev['feedPosts'] != next['feedPosts'] ||
                 prev['isInitialLoading'] != next['isInitialLoading'] ||
                 prev['isLoading'] != next['isLoading'] ||
                 prev['isRefreshing'] != next['isRefreshing'] ||
                 prev['error'] != next['error'];
        },
        builder: (context, data, child) {
          final feedPosts = data['feedPosts'] as List;
          final isInitialLoading = data['isInitialLoading'] as bool;
          final isLoading = data['isLoading'] as bool;
          final isRefreshing = data['isRefreshing'] as bool;
          final error = data['error'] as String?;
          
          // Показываем скелетон только при ПЕРВОЙ загрузке И пустом списке
          if (isInitialLoading && feedPosts.isEmpty) {
            return ListView.builder(
              itemCount: 3, // Показываем 3 скелетона
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const StoriesWidget();
                }
                return const ShimmerSkeletonPostCard();
              },
            );
          }

          // При ошибке показываем пустой экран с инструкцией pull-to-refresh
          // Только если не идет загрузка и список пустой
          if (error != null && feedPosts.isEmpty && !isLoading && !isRefreshing) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    EvaIcons.refreshOutline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Пустой список (только если не идет загрузка)
          if (feedPosts.isEmpty && !isLoading && !isRefreshing) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    EvaIcons.refreshOutline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No posts yet',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Основной контент - показываем даже если идет загрузка (для плавности)
          final postsProvider = context.read<PostsProvider>();
          return SmartRefresher(
            controller: _refreshController,
            onRefresh: _onRefresh,
            enablePullDown: true,
            enablePullUp: false,
            header: const WaterDropHeader(
              waterDropColor: Color(0xFF0095F6),
              complete: Icon(
                EvaIcons.checkmarkCircle,
                color: Color(0xFF0095F6),
                size: 20,
              ),
              failed: Icon(
                EvaIcons.closeCircle,
                color: Colors.red,
                size: 20,
              ),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: feedPosts.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const StoriesWidget();
                }
                
                final postIndex = index - 1;
                if (postIndex >= feedPosts.length) {
                  return isLoading && !isRefreshing
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

                return PostCard(
                  post: feedPosts[postIndex],
                  onLike: () => postsProvider.likePost(
                    feedPosts[postIndex].id,
                  ),
                  onComment: (content, parentCommentId) =>
                      postsProvider.addComment(
                    feedPosts[postIndex].id,
                    content,
                    parentCommentId: parentCommentId,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
