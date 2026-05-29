import 'package:flutter/material.dart';
import '../models/news.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class NewsProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<News> _news = [];
  News? _currentNews;
  List<NewsCategory> _categories = [];
  Map<String, List<NewsSubcategory>> _subcategoriesByCategory = {};
  bool _isLoading = false;
  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMoreNews = true;
  String? _selectedCategoryId;
  bool _isLoadingCategories = false;

  List<News> get news => _news;
  News? get currentNews => _currentNews;
  List<NewsCategory> get categories => _categories;
  Map<String, List<NewsSubcategory>> get subcategoriesByCategory => _subcategoriesByCategory;
  bool get isLoading => _isLoading;
  bool get isInitialLoading => _isInitialLoading;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;
  bool get hasMoreNews => _hasMoreNews;
  String? get selectedCategoryId => _selectedCategoryId;
  bool get isLoadingCategories => _isLoadingCategories;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  Future<void> loadNewsFeed({bool refresh = false, String? categoryId, String? accessToken}) async {
    try {
      if (refresh) {
        _currentPage = 1;
        _hasMoreNews = true;
        _news.clear();
        _isRefreshing = true;
        _isInitialLoading = false;
        notifyListeners();
      }

      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      _setLoading(true);
      _setError(null);

      final result = await _apiService.getNewsFeed(
        page: _currentPage,
        limit: 10,
        categoryId: categoryId ?? _selectedCategoryId,
      );

      final newNews = result['news'] as List<News>;
      final totalPages = result['totalPages'] as int;

      if (refresh) {
        _news = newNews;
      } else {
        _news.addAll(newNews);
      }

      _hasMoreNews = _currentPage < totalPages;
      _currentPage++;

      _setLoading(false);
      _isRefreshing = false;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      _isRefreshing = false;
    }
  }

  Future<void> loadNews(String newsId, {String? accessToken}) async {
    try {
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      _setLoading(true);
      _setError(null);

      _currentNews = await _apiService.getNews(newsId);

      _setLoading(false);
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
    }
  }

  Future<News> createNews({
    required String title,
    required String content,
    required String categoryId,
    String? subcategoryId,
    String? coverImageUrl,
    List<String>? coauthors,
    String? externalLinkUrl,
    String? externalLinkText,
    String? accessToken,
  }) async {
    try {
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      _setLoading(true);
      _setError(null);

      final createdNews = await _apiService.createNews(
        title: title,
        content: content,
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        coverImageUrl: coverImageUrl,
        coauthors: coauthors,
        externalLinkUrl: externalLinkUrl,
        externalLinkText: externalLinkText,
      );

      // Add to feed at the beginning
      _news.insert(0, createdNews);

      _setLoading(false);
      notifyListeners();
      return createdNews;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      rethrow;
    }
  }

  Future<void> updateNews(
    String newsId, {
    String? title,
    String? content,
    String? categoryId,
    String? subcategoryId,
    String? coverImageUrl,
    List<String>? coauthors,
    String? externalLinkUrl,
    String? externalLinkText,
    bool? isPublished,
    String? accessToken,
  }) async {
    try {
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      _setLoading(true);
      _setError(null);

      final updatedNews = await _apiService.updateNews(
        newsId,
        title: title,
        content: content,
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        coverImageUrl: coverImageUrl,
        coauthors: coauthors,
        externalLinkUrl: externalLinkUrl,
        externalLinkText: externalLinkText,
        isPublished: isPublished,
      );

      // Update in feed
      final index = _news.indexWhere((n) => n.id == newsId);
      if (index != -1) {
        _news[index] = updatedNews;
      }

      // Update current news if it's the same
      if (_currentNews?.id == newsId) {
        _currentNews = updatedNews;
      }

      _setLoading(false);
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      rethrow;
    }
  }

  Future<void> deleteNews(String newsId, {String? accessToken}) async {
    try {
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      _setLoading(true);
      _setError(null);

      await _apiService.deleteNews(newsId);

      // Remove from feed
      _news.removeWhere((n) => n.id == newsId);

      // Clear current news if it's the same
      if (_currentNews?.id == newsId) {
        _currentNews = null;
      }

      _setLoading(false);
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      rethrow;
    }
  }

  Future<void> likeNews(String newsId, {String? accessToken}) async {
    try {
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      final result = await _apiService.likeNews(newsId);
      final isLiked = result['liked'] as bool;

      // Update in feed
      final index = _news.indexWhere((n) => n.id == newsId);
      if (index != -1) {
        _news[index] = _news[index].copyWith(
          isLiked: isLiked,
          likesCount: isLiked ? _news[index].likesCount + 1 : _news[index].likesCount - 1,
        );
      }

      // Update current news if it's the same
      if (_currentNews?.id == newsId) {
        _currentNews = _currentNews!.copyWith(
          isLiked: isLiked,
          likesCount: isLiked ? _currentNews!.likesCount + 1 : _currentNews!.likesCount - 1,
        );
      }

      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      rethrow;
    }
  }

  Future<void> loadCategories({String? accessToken}) async {
    if (_isLoadingCategories) return;

    try {
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      _isLoadingCategories = true;
      notifyListeners();

      final result = await _apiService.getNewsCategories();
      final categoriesData = result['categories'] as List;

      _categories = [];
      _subcategoriesByCategory = {};

      for (final item in categoriesData) {
        final category = item['category'] as NewsCategory;
        final subcategories = item['subcategories'] as List<NewsSubcategory>;

        _categories.add(category);
        _subcategoriesByCategory[category.id] = subcategories;
      }

      _isLoadingCategories = false;
      notifyListeners();
    } catch (e) {
      _isLoadingCategories = false;
      _setError(e.toString());
    }
  }

  void setSelectedCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    _currentPage = 1;
    _hasMoreNews = true;
    _news.clear();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    _news.clear();
    _currentNews = null;
    _currentPage = 1;
    _hasMoreNews = true;
    _selectedCategoryId = null;
    _error = null;
    _isInitialLoading = true;
    notifyListeners();
  }

  // News comments methods
  Future<Map<String, dynamic>> loadComments(String newsId, {int page = 1, int limit = 20}) async {
    try {
      _setLoading(true);
      _setError(null);
      
      final result = await _apiService.getNewsComments(newsId, page: page, limit: limit);
      
      _setLoading(false);
      return result;
    } catch (e) {
      _setLoading(false);
      _setError(e.toString());
      rethrow;
    }
  }

  Future<Comment> addComment(String newsId, String content, {String? parentCommentId}) async {
    try {
      _setLoading(true);
      _setError(null);
      
      final comment = await _apiService.addNewsComment(newsId, content, parentCommentId: parentCommentId);
      
      // Update comments count for current news
      if (_currentNews?.id == newsId) {
        _currentNews = _currentNews!.copyWith(
          commentsCount: (_currentNews!.commentsCount) + 1,
        );
      }
      
      // Update comments count in news list
      final newsIndex = _news.indexWhere((n) => n.id == newsId);
      if (newsIndex != -1) {
        final news = _news[newsIndex];
        _news[newsIndex] = news.copyWith(
          commentsCount: news.commentsCount + 1,
        );
      }
      
      _setLoading(false);
      notifyListeners();
      return comment;
    } catch (e) {
      _setLoading(false);
      _setError(e.toString());
      rethrow;
    }
  }

  Future<Comment> updateComment(String newsId, String commentId, String content) async {
    try {
      _setLoading(true);
      _setError(null);
      
      final comment = await _apiService.updateNewsComment(newsId, commentId, content);
      
      _setLoading(false);
      notifyListeners();
      return comment;
    } catch (e) {
      _setLoading(false);
      _setError(e.toString());
      rethrow;
    }
  }

  Future<void> deleteComment(String newsId, String commentId) async {
    try {
      _setLoading(true);
      _setError(null);
      
      await _apiService.deleteNewsComment(newsId, commentId);
      
      // Update comments count for current news
      if (_currentNews?.id == newsId) {
        _currentNews = _currentNews!.copyWith(
          commentsCount: (_currentNews!.commentsCount - 1).clamp(0, double.infinity).toInt(),
        );
      }
      
      // Update comments count in news list
      final newsIndex = _news.indexWhere((n) => n.id == newsId);
      if (newsIndex != -1) {
        final news = _news[newsIndex];
        _news[newsIndex] = news.copyWith(
          commentsCount: (news.commentsCount - 1).clamp(0, double.infinity).toInt(),
        );
      }
      
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setLoading(false);
      _setError(e.toString());
      rethrow;
    }
  }
}

