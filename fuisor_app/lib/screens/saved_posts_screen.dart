import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../widgets/post_grid_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> with AutomaticKeepAliveClientMixin {
  List<Post> _savedPosts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final ApiService _apiService = ApiService();
  bool _hasLoaded = false; // Флаг, чтобы не загружать дважды

  @override
  bool get wantKeepAlive => true; // Сохраняем состояние при переключении вкладок

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Загружаем только если данных еще нет
      if (!_hasLoaded && _savedPosts.isEmpty) {
        _loadSavedPosts(refresh: true);
        _hasLoaded = true;
      }
    });
  }

  // Публичный метод для загрузки извне
  Future<void> loadSavedPosts({bool refresh = false}) async {
    // Если данные уже есть и не требуется обновление, не загружаем
    if (!refresh && _savedPosts.isNotEmpty) {
      return;
    }
    if (!_hasLoaded || refresh) {
      _hasLoaded = true;
      await _loadSavedPosts(refresh: refresh);
    }
  }

  Future<void> _loadSavedPosts({bool refresh = false}) async {
    if (!refresh && !_hasMore) return;
    if (_isLoading) return;

    setState(() {
      if (refresh) {
        _currentPage = 1;
        _savedPosts.clear();
        _hasMore = true;
      }
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      _apiService.setAccessToken(accessToken);

      final result = await _apiService.getSavedPosts(
        page: _currentPage,
        limit: 20,
      );

      if (mounted) {
        final newPosts = (result['posts'] as List? ?? [])
            .map((json) => Post.fromJson(json))
            .toList();

        setState(() {
          if (refresh) {
            _savedPosts = newPosts;
          } else {
            _savedPosts.addAll(newPosts);
          }
          _currentPage++;
          _hasMore = result['page'] < result['totalPages'];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading saved posts: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Требуется для AutomaticKeepAliveClientMixin
    // Работаем так же, как вкладка с постами - просто возвращаем PostGridWidget
    // PostGridWidget сам обрабатывает пустое состояние и загрузку
    return PostGridWidget(
                      posts: _savedPosts,
                      isLoading: _isLoading,
                      hasMorePosts: _hasMore,
                      onLoadMore: () => _loadSavedPosts(),
    );
  }
}

