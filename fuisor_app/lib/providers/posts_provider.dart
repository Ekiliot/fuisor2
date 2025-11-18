import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/user.dart' show Post, Comment;
import '../services/api_service.dart';

class PostsProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<Post> _posts = [];
  List<Post> _feedPosts = [];
  List<Post> _videoPosts = [];
  List<Post> _hashtagPosts = [];
  List<Post> _mentionedPosts = [];
  List<Post> _userPosts = [];
  // Кэш комментариев для постов: postId -> List<Comment>
  final Map<String, List<Comment>> _commentsCache = {};
  bool _isLoading = false;
  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  bool _isLoadingFeed = false; // Защита от параллельных запросов
  bool _isRefreshingUserPosts = false;
  bool _isLoadingUserPosts = false; // Защита от параллельных запросов для userPosts
  String? _error;
  int _currentPage = 1;
  int _currentVideoPage = 1;
  int _currentUserPage = 1;
  bool _hasMorePosts = true;
  bool _hasMoreVideoPosts = true;
  bool _hasMoreUserPosts = true;

  List<Post> get posts => _posts;
  List<Post> get feedPosts => _feedPosts;
  List<Post> get videoPosts => _videoPosts;
  List<Post> get hashtagPosts => _hashtagPosts;
  List<Post> get mentionedPosts => _mentionedPosts;
  List<Post> get userPosts => _userPosts;
  bool get isLoading => _isLoading;
  bool get isInitialLoading => _isInitialLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isRefreshingUserPosts => _isRefreshingUserPosts;
  String? get error => _error;
  bool get hasMorePosts => _hasMorePosts;
  bool get hasMoreVideoPosts => _hasMoreVideoPosts;
  bool get hasMoreUserPosts => _hasMoreUserPosts;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  Future<void> loadPosts({bool refresh = false}) async {
    try {
      if (refresh) {
        _currentPage = 1;
        _hasMorePosts = true;
        _posts.clear();
      }

      _setLoading(true);
      _setError(null);

      final newPosts = await _apiService.getPosts(
        page: _currentPage,
        limit: 10,
      );

      if (refresh) {
        _posts = newPosts;
      } else {
        _posts.addAll(newPosts);
      }

      _hasMorePosts = newPosts.length == 10;
      _currentPage++;

      _setLoading(false);
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
    }
  }

  Future<void> loadFeed({bool refresh = false, String? accessToken}) async {
    // Защита от параллельных запросов
    if (_isLoadingFeed) {
      print('PostsProvider: Feed is already loading, skipping...');
      return;
    }

    // Сохраняем старые данные для восстановления при ошибке
    List<Post>? oldPosts;
    if (refresh) {
      oldPosts = List.from(_feedPosts); // Сохраняем копию старых данных
      _currentPage = 1;
      _hasMorePosts = true;
      _isRefreshing = true;
      // НЕ очищаем _feedPosts здесь - очистим только после успешной загрузки
      _isInitialLoading = false; // Не первая загрузка при refresh
      notifyListeners(); // Уведомляем о начале refresh
    }

    _isLoadingFeed = true;
    _setLoading(true);
    _setError(null);

    try {
      // Устанавливаем токен перед запросом
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      final newPosts = await _apiService.getFeed(
        page: _currentPage,
        limit: 10,
      );

      // Только после успешной загрузки обновляем список
      if (refresh) {
        _feedPosts = newPosts; // Заменяем только после успешной загрузки
        _isRefreshing = false;
      } else {
        _feedPosts.addAll(newPosts);
      }

      _hasMorePosts = newPosts.length == 10;
      _currentPage++;

      _isInitialLoading = false; // Первая загрузка завершена
      _setLoading(false);
    } catch (e) {
      // При ошибке загрузки дополнительных страниц - просто останавливаем загрузку
      if (!refresh) {
        _hasMorePosts = false; // Больше нет постов для загрузки
        print('PostsProvider: No more posts to load, stopping pagination');
      } else {
        // При ошибке refresh восстанавливаем старые данные
        if (oldPosts != null) {
          _feedPosts = oldPosts; // Восстанавливаем старые данные
          print('PostsProvider: Refresh failed, restored old posts');
        } else {
          // Если это первая загрузка и нет старых данных
          _feedPosts = [];
        }
        _isRefreshing = false;
        _setError(e.toString());
      }
      _isInitialLoading = false;
      _setLoading(false);
    } finally {
      _isLoadingFeed = false;
    }
  }

  Future<void> loadVideoPosts({bool refresh = false, String? accessToken}) async {
    try {
      if (refresh) {
        _currentVideoPage = 1;
        _hasMoreVideoPosts = true;
        _videoPosts.clear();
      }

      _setLoading(true);
      _setError(null);

      // Устанавливаем токен перед запросом
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      final newVideoPosts = await _apiService.getVideoPosts(
        page: _currentVideoPage,
        limit: 10,
      );

      // Предзагружаем комментарии для всех постов в фоне (не блокируем основной поток)
      _preloadCommentsForPosts(newVideoPosts);

      if (refresh) {
        _videoPosts = newVideoPosts;
      } else {
        _videoPosts.addAll(newVideoPosts);
      }

      _hasMoreVideoPosts = newVideoPosts.length == 10;
      _currentVideoPage++;

      _setLoading(false);
    } catch (e) {
      if (!refresh) {
        _hasMoreVideoPosts = false;
        print('PostsProvider: No more video posts to load');
      } else {
        _videoPosts = [];
        _setError(e.toString());
      }
      _setLoading(false);
    }
  }

  Future<void> loadHashtagPosts(String hashtag, {bool refresh = false}) async {
    try {
      if (refresh) {
        _currentPage = 1;
        _hasMorePosts = true;
        _hashtagPosts.clear();
      }

      _setLoading(true);
      _setError(null);

      final newPosts = await _apiService.getPostsByHashtag(
        hashtag,
        page: _currentPage,
        limit: 10,
      );

      if (refresh) {
        _hashtagPosts = newPosts;
      } else {
        _hashtagPosts.addAll(newPosts);
      }

      _hasMorePosts = newPosts.length == 10;
      _currentPage++;

      _setLoading(false);
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
    }
  }

  Future<void> loadMentionedPosts({bool refresh = false}) async {
    try {
      if (refresh) {
        _currentPage = 1;
        _hasMorePosts = true;
        _mentionedPosts.clear();
      }

      _setLoading(true);
      _setError(null);

      final newPosts = await _apiService.getMentionedPosts(
        page: _currentPage,
        limit: 10,
      );

      if (refresh) {
        _mentionedPosts = newPosts;
      } else {
        _mentionedPosts.addAll(newPosts);
      }

      _hasMorePosts = newPosts.length == 10;
      _currentPage++;

      _setLoading(false);
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
    }
  }

  Future<void> likePost(String postId) async {
    try {
      print('PostsProvider: Liking post $postId');
      final result = await _apiService.likePost(postId);
      print('PostsProvider: Post liked successfully');
      print('PostsProvider: Server returned isLiked: ${result['isLiked']}, likesCount: ${result['likesCount']}');
      
      // Update local state in all lists with data from server
      _updatePostLikeStatus(_posts, postId, result['isLiked'], result['likesCount']);
      _updatePostLikeStatus(_feedPosts, postId, result['isLiked'], result['likesCount']);
      _updatePostLikeStatus(_userPosts, postId, result['isLiked'], result['likesCount']);
      _updatePostLikeStatus(_hashtagPosts, postId, result['isLiked'], result['likesCount']);
      _updatePostLikeStatus(_mentionedPosts, postId, result['isLiked'], result['likesCount']);
      _updatePostLikeStatus(_videoPosts, postId, result['isLiked'], result['likesCount']);
      
      notifyListeners();
      print('PostsProvider: Post state updated, listeners notified');
    } catch (e) {
      print('PostsProvider: Error liking post: $e');
      _setError(e.toString());
    }
  }

  void _updatePostLikeStatus(List<Post> list, String postId, bool isLiked, int likesCount) {
    final postIndex = list.indexWhere((p) => p.id == postId);
    if (postIndex != -1) {
      final post = list[postIndex];
      list[postIndex] = Post(
        id: post.id,
        userId: post.userId,
        caption: post.caption,
        mediaUrl: post.mediaUrl,
        mediaType: post.mediaType,
        likesCount: likesCount, // Используем актуальный счетчик с сервера
        commentsCount: post.commentsCount,
        mentions: post.mentions,
        hashtags: post.hashtags,
        createdAt: post.createdAt,
        updatedAt: post.updatedAt,
        user: post.user,
        comments: post.comments,
        isLiked: isLiked, // Используем актуальный статус с сервера
      );
      print('PostsProvider: Updated post $postId - isLiked: $isLiked, likesCount: $likesCount');
    }
  }

  // Обновить счетчик комментариев в посте
  void updatePostCommentsCount(String postId, int delta) {
    _updatePostCommentsCountInList(_posts, postId, delta);
    _updatePostCommentsCountInList(_feedPosts, postId, delta);
    _updatePostCommentsCountInList(_userPosts, postId, delta);
    _updatePostCommentsCountInList(_hashtagPosts, postId, delta);
    _updatePostCommentsCountInList(_mentionedPosts, postId, delta);
    _updatePostCommentsCountInList(_videoPosts, postId, delta);
    notifyListeners();
  }

  void _updatePostCommentsCountInList(List<Post> list, String postId, int delta) {
    final postIndex = list.indexWhere((p) => p.id == postId);
    if (postIndex != -1) {
      final post = list[postIndex];
      final newCount = (post.commentsCount + delta).clamp(0, double.infinity).toInt();
      list[postIndex] = post.copyWith(
        commentsCount: newCount,
      );
    }
  }

  // Установить точное значение счетчика комментариев
  void setPostCommentsCount(String postId, int count) {
    _setPostCommentsCountInList(_posts, postId, count);
    _setPostCommentsCountInList(_feedPosts, postId, count);
    _setPostCommentsCountInList(_userPosts, postId, count);
    _setPostCommentsCountInList(_hashtagPosts, postId, count);
    _setPostCommentsCountInList(_mentionedPosts, postId, count);
    _setPostCommentsCountInList(_videoPosts, postId, count);
    notifyListeners();
  }

  void _setPostCommentsCountInList(List<Post> list, String postId, int count) {
    final postIndex = list.indexWhere((p) => p.id == postId);
    if (postIndex != -1) {
      final post = list[postIndex];
      list[postIndex] = post.copyWith(
        commentsCount: count.clamp(0, double.infinity).toInt(),
      );
    }
  }

  Future<Map<String, dynamic>> loadComments(String postId, {int page = 1, int limit = 20}) async {
    try {
      // Если комментарии уже закэшированы для первой страницы, используем их
      if (page == 1 && _commentsCache.containsKey(postId)) {
        final cachedComments = _commentsCache[postId]!;
        return {
          'comments': cachedComments,
          'total': cachedComments.length,
          'page': 1,
          'totalPages': 1,
        };
      }

      _setLoading(true);
      _setError(null);
      
      final result = await _apiService.getComments(postId, page: page, limit: limit);
      
      // Проверяем, что result содержит comments
      if (result['comments'] != null) {
        // Кэшируем комментарии для первой страницы
        if (page == 1) {
          final comments = result['comments'] as List<Comment>? ?? <Comment>[];
          _commentsCache[postId] = comments;
        }
      } else {
        // Если результат пустой, сохраняем пустой список
        if (page == 1) {
          _commentsCache[postId] = <Comment>[];
        }
      }
      
      _setLoading(false);
      return result;
    } catch (e) {
      _setLoading(false);
      _setError(e.toString());
      rethrow;
    }
  }

  // Предзагрузка комментариев для списка постов
  Future<void> _preloadCommentsForPosts(List<Post> posts) async {
    // Загружаем комментарии для всех постов параллельно
    final futures = posts.map((post) async {
      try {
        // Загружаем только первую страницу комментариев
        final result = await _apiService.getComments(post.id, page: 1, limit: 20);
        
        // Получаем total из результата (даже если comments null)
        final totalComments = result['total'] as int? ?? 0;
        
        // Проверяем, что result содержит comments
        if (result['comments'] != null) {
          final comments = result['comments'] as List<Comment>? ?? <Comment>[];
          _commentsCache[post.id] = comments;
          
          // Обновляем счетчик комментариев в посте на основе total из API
          setPostCommentsCount(post.id, totalComments);
          print('PostsProvider: Предзагружено ${comments.length} комментариев для поста ${post.id}, total: $totalComments');
        } else {
          // Если комментариев нет, сохраняем пустой список и обновляем счетчик
          _commentsCache[post.id] = <Comment>[];
          setPostCommentsCount(post.id, totalComments);
          print('PostsProvider: Нет комментариев для поста ${post.id}, total: $totalComments');
        }
      } catch (e) {
        print('PostsProvider: Ошибка предзагрузки комментариев для поста ${post.id}: $e');
        // Не критично, просто пропускаем - не добавляем в кэш при ошибке
      }
    });

    // Выполняем параллельно, но не ждем завершения всех
    Future.wait(futures, eagerError: false);
  }

  // Обновить кэш комментариев после добавления нового комментария
  void updateCommentsCache(String postId, Comment newComment, {String? parentCommentId}) {
    if (!_commentsCache.containsKey(postId)) {
      _commentsCache[postId] = [];
    }

    if (parentCommentId != null) {
      // Это ответ на комментарий - добавляем в replies
      final comments = _commentsCache[postId]!;
      final parentIndex = comments.indexWhere((c) => c.id == parentCommentId);
      if (parentIndex != -1) {
        final parentComment = comments[parentIndex];
        final updatedReplies = List<Comment>.from(parentComment.replies ?? []);
        updatedReplies.add(newComment);
        comments[parentIndex] = parentComment.copyWith(replies: updatedReplies);
      }
    } else {
      // Это обычный комментарий - добавляем в начало
      _commentsCache[postId]!.insert(0, newComment);
    }
  }

  // Очистить кэш комментариев для поста
  void clearCommentsCache(String postId) {
    _commentsCache.remove(postId);
  }

  // Получить закэшированные комментарии для поста
  List<Comment>? getCachedComments(String postId) {
    return _commentsCache[postId];
  }

  Future<void> addComment(String postId, String content, {String? parentCommentId}) async {
    try {
      final comment = await _apiService.addComment(postId, content, parentCommentId: parentCommentId);
      
      // Update local state
      final postIndex = _posts.indexWhere((p) => p.id == postId);
      if (postIndex != -1) {
        final post = _posts[postIndex];
        final updatedComments = List<Comment>.from(post.comments ?? []);
        updatedComments.add(comment);
        
        _posts[postIndex] = Post(
          id: post.id,
          userId: post.userId,
          caption: post.caption,
          mediaUrl: post.mediaUrl,
          mediaType: post.mediaType,
          likesCount: post.likesCount,
          commentsCount: post.commentsCount + 1,
          mentions: post.mentions,
          hashtags: post.hashtags,
          createdAt: post.createdAt,
          updatedAt: post.updatedAt,
          user: post.user,
          comments: updatedComments,
          isLiked: post.isLiked,
        );
        notifyListeners();
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Создать новый пост
  Future<void> createPost({
    required String caption,
    required Uint8List? mediaBytes,
    required String mediaFileName,
    required String mediaType,
    List<String>? mentions,
    List<String>? hashtags,
    String? accessToken, // Добавляем токен как параметр
  }) async {
    try {
      print('PostsProvider: createPost called');
      print('PostsProvider: Caption length: ${caption.length}');
      print('PostsProvider: Media type: $mediaType');
      print('PostsProvider: Media filename: $mediaFileName');
      print('PostsProvider: Media bytes: ${mediaBytes != null ? "${mediaBytes.length} bytes" : "NULL"}');
      print('PostsProvider: Access token: ${accessToken != null ? "Present" : "Missing"}');
      
      _setLoading(true);
      _setError(null);

      print('PostsProvider: Setting loading state to true');

      // Устанавливаем токен перед запросом
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
        print('PostsProvider: Token set in ApiService');
      } else {
        print('PostsProvider: WARNING - No access token provided!');
      }

      print('PostsProvider: Calling ApiService.createPost...');
      final newPost = await _apiService.createPost(
        caption: caption,
        mediaBytes: mediaBytes,
        mediaFileName: mediaFileName,
        mediaType: mediaType,
        mentions: mentions,
        hashtags: hashtags,
      );

      print('PostsProvider: Post created successfully, adding to lists...');
      // Добавляем новый пост в начало списка
      _posts.insert(0, newPost);
      _feedPosts.insert(0, newPost);
      
      // Обновляем счетчик постов
      _currentPage = 1;
      _hasMorePosts = true;

      print('PostsProvider: Notifying listeners...');
      notifyListeners();

      _setLoading(false);
      print('PostsProvider: Loading state set to false');
    } catch (e, stackTrace) {
      print('PostsProvider: ERROR creating post: $e');
      print('PostsProvider: Stack trace: $stackTrace');
      _setError(e.toString());
      _setLoading(false);
      rethrow;
    }
  }

  Future<void> updatePost({
    required String postId,
    required String caption,
    required String accessToken,
  }) async {
    try {
      print('PostsProvider: Updating post with access token check...');
      _apiService.setAccessToken(accessToken);
      
      _setLoading(true);
      _setError(null);

      final updatedPost = await _apiService.updatePost(
        postId: postId,
        caption: caption,
      );

      // Update in all lists
      _updatePostInList(_posts, updatedPost);
      _updatePostInList(_feedPosts, updatedPost);
      _updatePostInList(_hashtagPosts, updatedPost);
      _updatePostInList(_mentionedPosts, updatedPost);

      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  void _updatePostInList(List<Post> list, Post updatedPost) {
    final index = list.indexWhere((post) => post.id == updatedPost.id);
    if (index != -1) {
      list[index] = updatedPost;
    }
  }

  Future<void> loadUserPosts({
    required String userId,
    bool refresh = false,
    String? accessToken,
  }) async {
    // Защита от параллельных запросов
    if (_isLoadingUserPosts) {
      print('PostsProvider: User posts are already loading, skipping...');
      return;
    }

    // Сохраняем старые данные для восстановления при ошибке
    List<Post>? oldPosts;
    if (refresh) {
      oldPosts = List.from(_userPosts); // Сохраняем копию старых данных
      _currentUserPage = 1;
      _hasMoreUserPosts = true;
      _isRefreshingUserPosts = true;
      // НЕ очищаем _userPosts здесь - очистим только после успешной загрузки
      notifyListeners(); // Уведомляем о начале refresh
    }

    if (!_hasMoreUserPosts && !refresh) {
      print('PostsProvider: No more user posts to load');
      return;
    }

    _isLoadingUserPosts = true;
    print('PostsProvider: Loading user posts for user: $userId');
    print('PostsProvider: Page: $_currentUserPage');

    try {
      // Устанавливаем токен перед запросом
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      _setLoading(true);
      _setError(null);

      final response = await _apiService.getUserPosts(
        userId,
        page: _currentUserPage,
        limit: 20,
      );

      // Только после успешной загрузки обновляем список
      if (response.isNotEmpty) {
        if (refresh) {
          _userPosts = response; // Заменяем только после успешной загрузки
          _isRefreshingUserPosts = false;
        } else {
          _userPosts.addAll(response);
        }
        _currentUserPage++;
        
        // Если получили меньше постов чем лимит, значит больше нет
        if (response.length < 20) {
          _hasMoreUserPosts = false;
        }
      } else {
        if (refresh) {
          _userPosts = []; // Пустой список только после успешной загрузки
          _isRefreshingUserPosts = false;
        }
        _hasMoreUserPosts = false;
      }

      print('PostsProvider: Loaded ${response.length} user posts');
      print('PostsProvider: Total user posts: ${_userPosts.length}');
      _setLoading(false);
    } catch (e) {
      print('PostsProvider: Error loading user posts: $e');
      // При ошибке refresh восстанавливаем старые данные
      if (refresh && oldPosts != null) {
        _userPosts = oldPosts; // Восстанавливаем старые данные
        print('PostsProvider: User posts refresh failed, restored old posts');
      }
      _isRefreshingUserPosts = false;
      _setError(e.toString());
      _setLoading(false);
    } finally {
      _isLoadingUserPosts = false;
    }
  }

  // Загрузить дополнительные посты для детального экрана
  Future<void> loadMoreFeedPosts({
    required int page,
    required int limit,
    required String accessToken,
  }) async {
    try {
      print('PostsProvider: Loading more feed posts...');
      print('PostsProvider: Page: $page, Limit: $limit');

      // Устанавливаем токен перед запросом
      _apiService.setAccessToken(accessToken);

      _setLoading(true);
      _setError(null);

      final response = await _apiService.getFeed(
        page: page,
        limit: limit,
      );

      if (response.isNotEmpty) {
        _feedPosts.addAll(response);
        _currentPage = page;
        
        // Если получили меньше постов чем лимит, значит больше нет
        if (response.length < limit) {
          _hasMorePosts = false;
        }
      } else {
        _hasMorePosts = false;
      }

      print('PostsProvider: Loaded ${response.length} more feed posts');
      print('PostsProvider: Total feed posts: ${_feedPosts.length}');
    } catch (e) {
      print('PostsProvider: Error loading more feed posts: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deletePost(String postId, {String? accessToken}) async {
    try {
      print('PostsProvider: Deleting post $postId');
      
      // Устанавливаем токен перед запросом
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      _setLoading(true);
      _setError(null);

      await _apiService.deletePost(postId);

      // Удаляем пост из всех списков
      _posts.removeWhere((post) => post.id == postId);
      _feedPosts.removeWhere((post) => post.id == postId);
      _hashtagPosts.removeWhere((post) => post.id == postId);
      _mentionedPosts.removeWhere((post) => post.id == postId);
      _userPosts.removeWhere((post) => post.id == postId);

      _setLoading(false);
      notifyListeners();
      
      print('PostsProvider: Post deleted successfully');
    } catch (e) {
      print('PostsProvider: Error deleting post: $e');
      _setError(e.toString());
      _setLoading(false);
      rethrow;
    }
  }

  void clearError() {
    _setError(null);
  }
}
