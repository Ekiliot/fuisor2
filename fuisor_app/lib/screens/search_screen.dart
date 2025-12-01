import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../providers/posts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../widgets/post_grid_widget.dart';
import '../widgets/safe_avatar.dart';
import '../widgets/animated_app_bar_title.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  
  List<User> _users = [];
  List<Post> _posts = [];
  List<dynamic> _hashtags = [];
  bool _hasSearched = false;
  String _searchQuery = '';
  
  // Timer для debounce поиска
  Timer? _searchDebounceTimer;
  String _currentSearchText = '';

  @override
  void initState() {
    super.initState();
    _setupApiService();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _setupApiService() async {
    final authProvider = context.read<AuthProvider>();
    final accessToken = await authProvider.getAccessToken();
    if (accessToken != null) {
      _apiService.setAccessToken(accessToken);
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Отменяем предыдущий таймер
    _searchDebounceTimer?.cancel();
    
    final query = _searchController.text.trim();
    _currentSearchText = query;
    
    // Обновляем только suffixIcon без перестроения всего экрана
    if (mounted) {
      setState(() {});
    }
    
    if (query.isEmpty) {
      // Очищаем результаты только если поле пустое
      setState(() {
        _users = [];
        _posts = [];
        _hashtags = [];
        _hasSearched = false;
        _searchQuery = '';
      });
      return;
    }
    
    // Создаем новый таймер с задержкой 500ms
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      // Проверяем, что текст не изменился за время задержки
      if (_currentSearchText == _searchController.text.trim()) {
        _performSearch(_currentSearchText);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _users = [];
          _posts = [];
          _hashtags = [];
          _hasSearched = false;
          _searchQuery = '';
        });
      }
      return;
    }

    // Сохраняем запрос, но НЕ очищаем предыдущие результаты
    // Предыдущие результаты остаются видимыми до получения новых
    if (mounted) {
      setState(() {
        _searchQuery = query;
        // НЕ устанавливаем _isSearching = true
        // НЕ очищаем предыдущие результаты
      });
    }

    try {
      final result = await _apiService.search(query);
      
      // Проверяем, что запрос все еще актуален (текст не изменился)
      if (mounted && _searchController.text.trim() == query) {
        setState(() {
          // Обновляем результаты только после получения новых данных
          // Старые результаты просто заменяются новыми
          _users = (result['users'] as List? ?? [])
              .map((json) => User.fromJson(json))
              .toList();
          _posts = (result['posts'] as List? ?? [])
              .map((json) => Post.fromJson(json))
              .toList();
          _hashtags = result['hashtags'] as List? ?? [];
          _hasSearched = true;
        });
      }
    } catch (e) {
      print('Error searching: $e');
      if (mounted && _searchController.text.trim() == query) {
        setState(() {
          _hasSearched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: RepaintBoundary(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withOpacity(0.1),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        title: const AnimatedAppBarTitle(
          text: 'Search',
        ),
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                // onChanged обрабатывается через listener, ничего не делаем здесь
              },
              decoration: InputDecoration(
                hintText: 'Search for users, posts and hashtags',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(
                  EvaIcons.searchOutline,
                  color: Color(0xFF8E8E8E),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          EvaIcons.closeCircle,
                          color: Color(0xFF8E8E8E),
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _users = [];
                            _posts = [];
                            _hashtags = [];
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF262626),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          
          // Search results or placeholder
          Expanded(
            child: _hasSearched
                ? _buildSearchResults()
                : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search placeholder
                  Container(
                    height: 200,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            EvaIcons.searchOutline,
                            size: 64,
                            color: Color(0xFF8E8E8E),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Search for users, posts and hashtags',
                            style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF8E8E8E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Recommended Posts Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recommended Posts',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Consumer<PostsProvider>(
                          builder: (context, postsProvider, child) {
                            return PostGridWidget(
                              posts: postsProvider.feedPosts.take(12).toList(), // Show first 12 posts as recommendations
                              isLoading: postsProvider.isLoading,
                              hasMorePosts: false,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_users.isEmpty && _posts.isEmpty && _hashtags.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              EvaIcons.searchOutline,
              size: 64,
              color: Color(0xFF8E8E8E),
            ),
            const SizedBox(height: 16),
            Text(
              'No results for "$_searchQuery"',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try searching for something else',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8E8E8E),
              ),
            ),
          ],
        ),
      );
    }

    int _currentPosition = 0;

    return AnimationLimiter(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Users
            if (_users.isNotEmpty) ...[
              AnimationConfiguration.staggeredList(
                position: _currentPosition++,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Users',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ...List.generate(_users.length, (index) {
                final user = _users[index];
                return AnimationConfiguration.staggeredList(
                  position: _currentPosition++,
                  duration: const Duration(milliseconds: 375),
                  child: SlideAnimation(
                    verticalOffset: 50.0,
                    child: FadeInAnimation(
                      child: ListTile(
                        leading: SafeAvatar(
                          imageUrl: user.avatarUrl,
                          radius: 20,
                        ),
                        title: Text(
                          user.username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: user.name.isNotEmpty
                            ? Text(
                                user.name,
                                style: const TextStyle(color: Color(0xFF8E8E8E)),
                              )
                            : null,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileScreen(userId: user.id),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              }),
              AnimationConfiguration.staggeredList(
                position: _currentPosition++,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: const Divider(color: Color(0xFF262626)),
                  ),
                ),
              ),
            ],

            // Posts
            if (_posts.isNotEmpty) ...[
              AnimationConfiguration.staggeredList(
                position: _currentPosition++,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Posts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimationConfiguration.staggeredList(
                position: _currentPosition++,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: PostGridWidget(
                        posts: _posts,
                        isLoading: false,
                        hasMorePosts: false,
                      ),
                    ),
                  ),
                ),
              ),
              AnimationConfiguration.staggeredList(
                position: _currentPosition++,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Column(
                      children: const [
                        SizedBox(height: 20),
                        Divider(color: Color(0xFF262626)),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Hashtags
            if (_hashtags.isNotEmpty) ...[
              AnimationConfiguration.staggeredList(
                position: _currentPosition++,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Hashtags',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ...List.generate(_hashtags.length, (index) {
                final hashtag = _hashtags[index];
                return AnimationConfiguration.staggeredList(
                  position: _currentPosition++,
                  duration: const Duration(milliseconds: 375),
                  child: SlideAnimation(
                    verticalOffset: 50.0,
                    child: FadeInAnimation(
                      child: ListTile(
                        leading: const Icon(
                          EvaIcons.hash,
                          color: Color(0xFF0095F6),
                        ),
                        title: Text(
                          '#${hashtag['name']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${hashtag['posts_count']} posts',
                          style: const TextStyle(color: Color(0xFF8E8E8E)),
                        ),
                        onTap: () {
                          // TODO: Navigate to hashtag posts
                          print('Navigate to hashtag: ${hashtag['name']}');
                        },
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
