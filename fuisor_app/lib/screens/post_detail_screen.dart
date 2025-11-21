import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../providers/posts_provider.dart';
import '../widgets/post_card.dart';

class PostDetailScreen extends StatefulWidget {
  final String initialPostId;
  final List<Post> initialPosts;

  const PostDetailScreen({
    Key? key,
    required this.initialPostId,
    required this.initialPosts,
  }) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  int? _initialPostIndex;
  List<Post> _posts = [];
  String? _userId; // ID пользователя, чьи посты мы просматриваем

  @override
  void initState() {
    super.initState();
    
    // Инициализируем список постов из initialPosts
    _posts = List.from(widget.initialPosts);
    
    // Определяем userId из первого поста
    if (widget.initialPosts.isNotEmpty) {
      _userId = widget.initialPosts.first.userId;
      print('PostDetailScreen: Viewing posts for user: $_userId');
    }
    
    // Находим индекс начального поста
    _initialPostIndex = _posts.indexWhere(
      (post) => post.id == widget.initialPostId,
    );
    
    // Если пост не найден в начальном списке, добавляем его
    if (_initialPostIndex == -1) {
      _initialPostIndex = 0;
    }
    
    // Скроллим к нужному посту после загрузки
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_initialPostIndex != null && _initialPostIndex! < _posts.length) {
        _scrollToPost(_initialPostIndex!);
      }
    });
    
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMorePosts();
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMorePosts || _userId == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final postsProvider = context.read<PostsProvider>();
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');

      if (accessToken != null) {
        // Загружаем посты пользователя, а не из ленты
        await postsProvider.loadUserPosts(
          userId: _userId!,
          refresh: false,
          accessToken: accessToken,
        );
        
        // Обновляем список постов из provider
        final newPosts = postsProvider.userPosts;
        setState(() {
          _posts = newPosts;
          _hasMorePosts = postsProvider.hasMoreUserPosts;
        });
        
        print('PostDetailScreen: Loaded ${newPosts.length} user posts');
      }
    } catch (e) {
      print('PostDetailScreen: Error loading more posts: $e');
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  void _scrollToPost(int index) {
    if (index < _posts.length) {
      // Вычисляем примерную позицию поста
      final double itemHeight = MediaQuery.of(context).size.width + 200; // Примерная высота поста
      final double targetPosition = index * itemHeight;
      
      _scrollController.animateTo(
        targetPosition,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Posts',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(EvaIcons.shareOutline, color: Colors.white),
            onPressed: () {
              // TODO: Implement share functionality
            },
          ),
        ],
      ),
      body: Consumer<PostsProvider>(
        builder: (context, postsProvider, child) {
          // Если есть userId, синхронизируем с userPosts из provider
          if (_userId != null) {
            final providerUserPosts = postsProvider.userPosts;
            // Проверяем, что посты в provider принадлежат правильному пользователю
            if (providerUserPosts.isNotEmpty && 
                providerUserPosts.first.userId == _userId) {
              // Обновляем список, если в provider больше постов
              if (providerUserPosts.length > _posts.length) {
                _posts = providerUserPosts;
              }
            }
          }
          
          if (_posts.isEmpty) {
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
                    'No posts available',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            controller: _scrollController,
            itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _posts.length) {
                // Показать индикатор загрузки в конце
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0095F6),
                    ),
                  ),
                );
              }

              final post = _posts[index];
              return PostCard(
                post: post,
                onLike: () => postsProvider.likePost(post.id),
                onComment: (content, parentCommentId) => postsProvider.addComment(
                  post.id,
                  content,
                  parentCommentId: parentCommentId,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
