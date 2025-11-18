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

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  List<Post> _savedPosts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedPosts(refresh: true);
    });
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

