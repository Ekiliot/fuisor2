import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/media_cache_service.dart';
import '../services/signed_url_cache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PostsProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final CacheService _cacheService = CacheService();
  List<Post> _posts = [];
  List<Post> _feedPosts = [];
  List<Post> _videoPosts = [];
  List<Post> _followingVideoPosts = [];
  List<Post> _hashtagPosts = [];
  List<Post> _mentionedPosts = [];
  List<Post> _userPosts = [];
  String? _currentUserPostsUserId; // Отслеживаем, для какого пользователя загружены посты
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
  int _currentFollowingVideoPage = 1;
  int _currentUserPage = 1;
  bool _hasMorePosts = true;
  bool _hasMoreVideoPosts = true;
  bool _hasMoreFollowingVideoPosts = true;
  bool _hasMoreUserPosts = true;

  List<Post> get posts => _posts;
  List<Post> get feedPosts => _feedPosts;
  List<Post> get videoPosts => _videoPosts;
  List<Post> get followingVideoPosts => _followingVideoPosts;
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
  bool get hasMoreFollowingVideoPosts => _hasMoreFollowingVideoPosts;
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
    } else {
      // При первой загрузке или загрузке следующей страницы - проверяем кеш
      if (_feedPosts.isEmpty && _isInitialLoading) {
        final cachedFeed = _cacheService.getCachedFeed();
        if (cachedFeed != null && _cacheService.isFeedCacheValid()) {
          _feedPosts = cachedFeed;
          _isInitialLoading = false;
          notifyListeners();
          print('PostsProvider: Loaded feed from cache (${cachedFeed.length} posts)');
        }
      }
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
        // При refresh очищаем кеш изображений для всех старых постов перед заменой
        // Это предотвращает показ старых изображений для новых постов
        // При refresh очищаем кеш изображений для всех старых постов перед заменой
        // Это предотвращает показ старых изображений для новых постов
        for (final oldPost in _feedPosts) {
          final mediaUrl = oldPost.mediaUrl;
          if (mediaUrl.isNotEmpty) {
            // Очищаем кеш CachedNetworkImage для медиа
            try {
              await CachedNetworkImage.evictFromCache(
                'post_${oldPost.id}_$mediaUrl\_${mediaUrl.hashCode}',
              );
            } catch (e) {
              print('PostsProvider: Error evicting media cache for post ${oldPost.id}: $e');
            }
            // Инвалидируем signed URL кеш
            try {
              final signedUrlCache = SignedUrlCacheService();
              signedUrlCache.invalidate(
                path: mediaUrl,
                postId: oldPost.id,
              );
            } catch (e) {
              print('PostsProvider: Error invalidating signed URL cache for post ${oldPost.id}: $e');
            }
          }
          final thumbnailUrl = oldPost.thumbnailUrl;
          if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
            // Очищаем кеш CachedNetworkImage для thumbnail
            try {
              await CachedNetworkImage.evictFromCache(
                'post_${oldPost.id}_$thumbnailUrl\_${thumbnailUrl.hashCode}',
              );
            } catch (e) {
              print('PostsProvider: Error evicting thumbnail cache for post ${oldPost.id}: $e');
            }
            // Инвалидируем signed URL кеш
            try {
              final signedUrlCache = SignedUrlCacheService();
              signedUrlCache.invalidate(
                path: thumbnailUrl,
                postId: oldPost.id,
              );
            } catch (e) {
              print('PostsProvider: Error invalidating signed URL cache for thumbnail ${oldPost.id}: $e');
            }
          }
        }
        
        _feedPosts = newPosts; // Заменяем только после успешной загрузки
        _isRefreshing = false;
        // Кешируем обновленный feed
        await _cacheService.cacheFeed(newPosts);
        // Предзагружаем медиа для новых постов
        final mediaCache = MediaCacheService();
        await mediaCache.preloadPostsMedia(newPosts);
      } else {
        _feedPosts.addAll(newPosts);
        // Обновляем кеш при загрузке новых постов
        await _cacheService.cacheFeed(_feedPosts);
        // Предзагружаем медиа для новых постов
        final mediaCache = MediaCacheService();
        await mediaCache.preloadPostsMedia(newPosts);
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
        // При ошибке refresh восстанавливаем старые данные или кеш
        if (oldPosts != null && oldPosts.isNotEmpty) {
          _feedPosts = oldPosts; // Восстанавливаем старые данные
          print('PostsProvider: Refresh failed, restored old posts');
        } else {
          // Если нет старых данных, пытаемся загрузить из кеша
          final cachedFeed = _cacheService.getCachedFeed();
          if (cachedFeed != null) {
            _feedPosts = cachedFeed;
            print('PostsProvider: Refresh failed, loaded from cache');
          } else {
            _feedPosts = [];
          }
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

  Future<void> loadVideoPosts({bool refresh = false, String? accessToken, int retryAttempt = 0}) async {
    const int maxRetries = 3;
    const Duration retryDelay = Duration(seconds: 2);

    try {
      if (refresh) {
        _currentVideoPage = 1;
        _hasMoreVideoPosts = true;
        _videoPosts.clear();
      } else {
        // При первой загрузке проверяем кеш
        if (_videoPosts.isEmpty) {
          final cachedVideoPosts = _cacheService.getCachedVideoPosts();
          if (cachedVideoPosts != null) {
            _videoPosts = cachedVideoPosts;
            notifyListeners();
            print('PostsProvider: Loaded video posts from cache (${cachedVideoPosts.length} posts)');
          }
        }
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
        // Кешируем обновленные видео посты
        await _cacheService.cacheVideoPosts(newVideoPosts);
        // Предзагружаем медиа для новых видео постов
        final mediaCache = MediaCacheService();
        await mediaCache.preloadPostsMedia(newVideoPosts);
      } else {
        _videoPosts.addAll(newVideoPosts);
        // Обновляем кеш
        await _cacheService.cacheVideoPosts(_videoPosts);
        // Предзагружаем медиа для новых видео постов
        final mediaCache = MediaCacheService();
        await mediaCache.preloadPostsMedia(newVideoPosts);
      }

      _hasMoreVideoPosts = newVideoPosts.length == 10;
      _currentVideoPage++;

      _setLoading(false);
    } catch (e) {
      print('PostsProvider: Error loading video posts (attempt ${retryAttempt + 1}): $e');
      
      // Retry логика (только для не-refresh запросов)
      if (retryAttempt < maxRetries && !refresh) {
        print('PostsProvider: Retrying video posts load in ${retryDelay.inSeconds}s... (attempt ${retryAttempt + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
        await loadVideoPosts(refresh: refresh, accessToken: accessToken, retryAttempt: retryAttempt + 1);
        return;
      }

      if (!refresh) {
        _hasMoreVideoPosts = false;
        print('PostsProvider: No more video posts to load after ${retryAttempt + 1} attempts');
        // При ошибке используем кеш, если есть
        if (_videoPosts.isEmpty) {
          final cachedVideoPosts = _cacheService.getCachedVideoPosts();
          if (cachedVideoPosts != null) {
            _videoPosts = cachedVideoPosts;
            notifyListeners();
          }
        }
      } else {
        // При ошибке refresh пытаемся загрузить из кеша
        final cachedVideoPosts = _cacheService.getCachedVideoPosts();
        if (cachedVideoPosts != null) {
          _videoPosts = cachedVideoPosts;
        } else {
          _videoPosts = [];
        }
        _setError(e.toString());
      }
      _setLoading(false);
    }
  }

  Future<void> loadFollowingVideoPosts({bool refresh = false, String? accessToken, int retryAttempt = 0}) async {
    const int maxRetries = 3;
    const Duration retryDelay = Duration(seconds: 2);

    try {
      if (refresh) {
        _currentFollowingVideoPage = 1;
        _hasMoreFollowingVideoPosts = true;
        _followingVideoPosts.clear();
      }

      _setLoading(true);
      _setError(null);

      // Устанавливаем токен перед запросом
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }

      final newVideoPosts = await _apiService.getFollowingVideoPosts(
        page: _currentFollowingVideoPage,
        limit: 10,
      );

      // Предзагружаем комментарии для всех постов в фоне
      _preloadCommentsForPosts(newVideoPosts);

      if (refresh) {
        _followingVideoPosts = newVideoPosts;
      } else {
        _followingVideoPosts.addAll(newVideoPosts);
      }

      _hasMoreFollowingVideoPosts = newVideoPosts.length == 10;
      _currentFollowingVideoPage++;

      _setLoading(false);
    } catch (e) {
      print('PostsProvider: Error loading following video posts (attempt ${retryAttempt + 1}): $e');
      
      // Retry логика (только для не-refresh запросов)
      if (retryAttempt < maxRetries && !refresh) {
        print('PostsProvider: Retrying following video posts load in ${retryDelay.inSeconds}s... (attempt ${retryAttempt + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
        await loadFollowingVideoPosts(refresh: refresh, accessToken: accessToken, retryAttempt: retryAttempt + 1);
        return;
      }

      if (!refresh) {
        _hasMoreFollowingVideoPosts = false;
        print('PostsProvider: No more following video posts to load after ${retryAttempt + 1} attempts');
      } else {
        _followingVideoPosts = [];
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
      } else {
        // При первой загрузке проверяем кеш
        if (_hashtagPosts.isEmpty) {
          final cachedHashtagPosts = _cacheService.getCachedHashtagPosts(hashtag);
          if (cachedHashtagPosts != null) {
            _hashtagPosts = cachedHashtagPosts;
            notifyListeners();
            print('PostsProvider: Loaded hashtag posts from cache (${cachedHashtagPosts.length} posts)');
          }
        }
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
        // Кешируем обновленные посты по хештегу
        await _cacheService.cacheHashtagPosts(hashtag, newPosts);
        // Предзагружаем медиа для новых постов
        final mediaCache = MediaCacheService();
        await mediaCache.preloadPostsMedia(newPosts);
      } else {
        _hashtagPosts.addAll(newPosts);
        // Обновляем кеш
        await _cacheService.cacheHashtagPosts(hashtag, _hashtagPosts);
        // Предзагружаем медиа для новых постов
        final mediaCache = MediaCacheService();
        await mediaCache.preloadPostsMedia(newPosts);
      }

      _hasMorePosts = newPosts.length == 10;
      _currentPage++;

      _setLoading(false);
    } catch (e) {
      // При ошибке используем кеш, если есть
      if (_hashtagPosts.isEmpty) {
        final cachedHashtagPosts = _cacheService.getCachedHashtagPosts(hashtag);
        if (cachedHashtagPosts != null) {
          _hashtagPosts = cachedHashtagPosts;
          notifyListeners();
        }
      }
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
      _updatePostLikeStatus(_followingVideoPosts, postId, result['isLiked'], result['likesCount']);
      
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
      list[postIndex] = post.copyWith(
        likesCount: likesCount, // Используем актуальный счетчик с сервера
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
    _updatePostCommentsCountInList(_followingVideoPosts, postId, delta);
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
    _setPostCommentsCountInList(_followingVideoPosts, postId, count);
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
      // Если комментарии уже закэшированы в памяти для первой страницы, используем их
      if (page == 1 && _commentsCache.containsKey(postId)) {
        final cachedComments = _commentsCache[postId]!;
        return {
          'comments': cachedComments,
          'total': cachedComments.length,
          'page': 1,
          'totalPages': 1,
        };
      }

      // Проверяем кеш на диске для первой страницы
      if (page == 1) {
        final cachedComments = _cacheService.getCachedComments(postId);
        if (cachedComments != null && _cacheService.isCommentsCacheValid(postId)) {
          // Загружаем в память для быстрого доступа
          _commentsCache[postId] = cachedComments;
          return {
            'comments': cachedComments,
            'total': cachedComments.length,
            'page': 1,
            'totalPages': 1,
          };
        }
      }

      _setLoading(true);
      _setError(null);
      
      final result = await _apiService.getComments(postId, page: page, limit: limit);
      
      // Проверяем, что result содержит comments
      if (result['comments'] != null) {
        // Кэшируем комментарии для первой страницы (в память и на диск)
        if (page == 1) {
          final comments = result['comments'] as List<Comment>? ?? <Comment>[];
          _commentsCache[postId] = comments;
          // Сохраняем в кеш на диске
          await _cacheService.cacheComments(postId, comments);
        }
      } else {
        // Если результат пустой, сохраняем пустой список
        if (page == 1) {
          _commentsCache[postId] = <Comment>[];
          await _cacheService.cacheComments(postId, []);
        }
      }
      
      _setLoading(false);
      return result;
    } catch (e) {
      // При ошибке пытаемся использовать кеш
      if (page == 1) {
        final cachedComments = _cacheService.getCachedComments(postId);
        if (cachedComments != null) {
          _commentsCache[postId] = cachedComments;
          _setLoading(false);
          return {
            'comments': cachedComments,
            'total': cachedComments.length,
            'page': 1,
            'totalPages': 1,
          };
        }
      }
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
  Future<void> updateCommentsCache(String postId, Comment newComment, {String? parentCommentId}) async {
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
    
    // Обновляем кеш на диске
    await _cacheService.cacheComments(postId, _commentsCache[postId]!);
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
        
        _posts[postIndex] = post.copyWith(
          commentsCount: post.commentsCount + 1,
          comments: updatedComments,
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
    required String mediaUrl,
    required String mediaType,
    String? thumbnailUrl,
    List<String>? mentions,
    List<String>? hashtags,
    String? accessToken, // Добавляем токен как параметр
    double? latitude, // Геолокация для geo-posts
    double? longitude, // Геолокация для geo-posts
    String? visibility, // Видимость поста: 'public', 'friends', 'private'
    int? expiresInHours, // Время жизни поста в часах: 12, 24, 48
    User? currentUser, // Данные текущего пользователя для заполнения поста
    String? coauthor, // Coauthor user ID
    String? externalLinkUrl, // External link URL
    String? externalLinkText, // External link button text
    String? city, // City name
    String? district, // District/neighborhood
    String? street, // Street name
    String? address, // Specific address
    String? country, // Country name
    String? locationVisibility, // What to show: comma-separated values
  }) async {
    try {
      print('PostsProvider: createPost called');
      print('PostsProvider: Caption length: ${caption.length}');
      print('PostsProvider: Media type: $mediaType');
      print('PostsProvider: Media URL: $mediaUrl');
      print('PostsProvider: Thumbnail URL: ${thumbnailUrl ?? "None"}');
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
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl,
        mentions: mentions,
        hashtags: hashtags,
        latitude: latitude,
        longitude: longitude,
        visibility: visibility,
        expiresInHours: expiresInHours,
        coauthor: coauthor,
        externalLinkUrl: externalLinkUrl,
        externalLinkText: externalLinkText,
        city: city,
        district: district,
        street: street,
        address: address,
        country: country,
        locationVisibility: locationVisibility,
      );

      print('PostsProvider: Post created successfully, adding to lists...');
      
      // Если у поста нет данных пользователя и они переданы через параметр, добавляем их
      Post postToAdd = newPost;
      if ((newPost.user == null || newPost.user!.username.isEmpty) && currentUser != null) {
        print('PostsProvider: Adding current user data to post');
        postToAdd = Post(
          id: newPost.id,
          userId: newPost.userId,
          caption: newPost.caption,
          mediaUrl: newPost.mediaUrl,
          mediaType: newPost.mediaType,
          thumbnailUrl: newPost.thumbnailUrl,
          likesCount: newPost.likesCount,
          commentsCount: newPost.commentsCount,
          mentions: newPost.mentions,
          hashtags: newPost.hashtags,
          createdAt: newPost.createdAt,
          updatedAt: newPost.updatedAt,
          user: currentUser, // Добавляем данные текущего пользователя
          comments: newPost.comments,
          isLiked: newPost.isLiked,
          isSaved: newPost.isSaved,
          latitude: newPost.latitude,
          longitude: newPost.longitude,
          visibility: newPost.visibility,
          expiresAt: newPost.expiresAt,
          coauthor: newPost.coauthor,
          externalLinkUrl: newPost.externalLinkUrl,
          externalLinkText: newPost.externalLinkText,
          city: newPost.city,
          district: newPost.district,
          street: newPost.street,
          address: newPost.address,
          country: newPost.country,
          locationVisibility: newPost.locationVisibility,
        );
      }
      
      // Инвалидируем кэш для медиа нового поста, чтобы избежать показа старых изображений
      final signedUrlCache = SignedUrlCacheService();
      signedUrlCache.invalidate(
        path: postToAdd.mediaUrl,
        postId: postToAdd.id,
      );
      // Также инвалидируем thumbnail если есть
      if (postToAdd.thumbnailUrl != null && postToAdd.thumbnailUrl!.isNotEmpty) {
        signedUrlCache.invalidate(
          path: postToAdd.thumbnailUrl!,
          postId: postToAdd.id,
        );
      }
      
      // Очищаем кэш CachedNetworkImage для этого поста, чтобы избежать показа старых изображений
      // Очищаем по cacheKey, который будет использоваться для этого поста
      try {
        final mediaCacheKey = 'post_${postToAdd.id}_${postToAdd.mediaUrl}_${postToAdd.mediaUrl.hashCode}';
        await CachedNetworkImage.evictFromCache(mediaCacheKey);
        
        if (postToAdd.thumbnailUrl != null && postToAdd.thumbnailUrl!.isNotEmpty) {
          final thumbCacheKey = 'post_${postToAdd.id}_${postToAdd.thumbnailUrl}_${postToAdd.thumbnailUrl.hashCode}';
          await CachedNetworkImage.evictFromCache(thumbCacheKey);
        }
        
        print('PostsProvider: Кэш CachedNetworkImage очищен для нового поста ${postToAdd.id}');
      } catch (e) {
        print('PostsProvider: Ошибка очистки кэша CachedNetworkImage: $e');
      }
      
      print('PostsProvider: Кэш signed URL инвалидирован для нового поста ${postToAdd.id}');
      
      // Добавляем новый пост в начало списка
      _posts.insert(0, postToAdd);
      _feedPosts.insert(0, postToAdd);
      
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
    String? coauthor,
    String? externalLinkUrl,
    String? externalLinkText,
    String? city,
    String? district,
    String? street,
    String? address,
    String? country,
    String? locationVisibility,
  }) async {
    try {
      print('PostsProvider: Updating post with access token check...');
      _apiService.setAccessToken(accessToken);
      
      _setLoading(true);
      _setError(null);

      final updatedPost = await _apiService.updatePost(
        postId: postId,
        caption: caption,
        coauthor: coauthor,
        externalLinkUrl: externalLinkUrl,
        externalLinkText: externalLinkText,
        city: city,
        district: district,
        street: street,
        address: address,
        country: country,
        locationVisibility: locationVisibility,
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

    // ВАЖНО: Если переключились на другого пользователя, очищаем список постов
    if (_currentUserPostsUserId != null && _currentUserPostsUserId != userId) {
      print('PostsProvider: User changed from $_currentUserPostsUserId to $userId, clearing posts');
      _userPosts.clear();
      _currentUserPage = 1;
      _hasMoreUserPosts = true;
      _currentUserPostsUserId = userId;
    } else if (_currentUserPostsUserId == null) {
      _currentUserPostsUserId = userId;
    }

    // Сохраняем старые данные для восстановления при ошибке
    List<Post>? oldPosts;
    if (refresh) {
      oldPosts = List.from(_userPosts); // Сохраняем копию старых данных
      _currentUserPage = 1;
      _hasMoreUserPosts = true;
      _isRefreshingUserPosts = true;
      // Очищаем список только если userId совпадает (refresh для того же пользователя)
      if (_currentUserPostsUserId == userId) {
        // НЕ очищаем _userPosts здесь - очистим только после успешной загрузки
      }
      notifyListeners(); // Уведомляем о начале refresh
    } else {
      // При первой загрузке проверяем кеш только если список пуст И userId совпадает
      if (_userPosts.isEmpty && _currentUserPostsUserId == userId) {
        final cachedUserPosts = _cacheService.getCachedUserPosts(userId);
        if (cachedUserPosts != null) {
          // ВАЖНО: Фильтруем кешированные посты - оставляем только те, которые принадлежат правильному пользователю
          final filteredCachedPosts = cachedUserPosts.where((post) => post.userId == userId).toList();
          if (filteredCachedPosts.length != cachedUserPosts.length) {
            print('PostsProvider: Filtered out ${cachedUserPosts.length - filteredCachedPosts.length} invalid posts from cache');
            // Обновляем кеш с отфильтрованными постами
            await _cacheService.cacheUserPosts(userId, filteredCachedPosts);
          }
          _userPosts = filteredCachedPosts;
          notifyListeners();
          print('PostsProvider: Loaded ${filteredCachedPosts.length} user posts from cache');
        }
      }
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

      // ВАЖНО: Проверяем, что userId не изменился во время загрузки
      if (_currentUserPostsUserId != userId) {
        print('PostsProvider: User changed during load, ignoring response');
        return;
      }

      // ВАЖНО: Фильтруем посты - оставляем только те, которые принадлежат правильному пользователю
      final filteredResponse = response.where((post) {
        final postUserId = post.userId;
        if (postUserId != userId) {
          print('PostsProvider: WARNING - Post ${post.id} belongs to user $postUserId, but we requested posts for $userId. Filtering out.');
          return false;
        }
        return true;
      }).toList();

      if (filteredResponse.length != response.length) {
        print('PostsProvider: Filtered out ${response.length - filteredResponse.length} posts that don\'t belong to user $userId');
      }

      // Только после успешной загрузки обновляем список
      if (filteredResponse.isNotEmpty) {
        if (refresh) {
          _userPosts = filteredResponse; // Заменяем только после успешной загрузки
          _isRefreshingUserPosts = false;
          // Кешируем обновленные посты пользователя
          await _cacheService.cacheUserPosts(userId, filteredResponse);
          // Предзагружаем медиа для новых постов
          final mediaCache = MediaCacheService();
          await mediaCache.preloadPostsMedia(filteredResponse);
        } else {
          // Проверяем, что добавляем посты для правильного пользователя
          if (_currentUserPostsUserId == userId) {
            _userPosts.addAll(filteredResponse);
            // Обновляем кеш
            await _cacheService.cacheUserPosts(userId, _userPosts);
            // Предзагружаем медиа для новых постов
            final mediaCache = MediaCacheService();
            await mediaCache.preloadPostsMedia(filteredResponse);
          } else {
            print('PostsProvider: User changed, not adding posts');
            return;
          }
        }
        _currentUserPage++;
        
        // Если получили меньше постов чем лимит, значит больше нет
        if (filteredResponse.length < 20) {
          _hasMoreUserPosts = false;
        }
      } else {
        if (refresh && _currentUserPostsUserId == userId) {
          _userPosts = []; // Пустой список только после успешной загрузки
          _isRefreshingUserPosts = false;
          // Кешируем пустой список
          await _cacheService.cacheUserPosts(userId, []);
        }
        _hasMoreUserPosts = false;
      }

      print('PostsProvider: Loaded ${filteredResponse.length} user posts (filtered from ${response.length})');
      print('PostsProvider: Total user posts: ${_userPosts.length}');
      
      // Дополнительная проверка - убеждаемся, что все посты принадлежат правильному пользователю
      final invalidPosts = _userPosts.where((post) => post.userId != userId).toList();
      if (invalidPosts.isNotEmpty) {
        print('PostsProvider: ERROR - Found ${invalidPosts.length} posts that don\'t belong to user $userId. Removing them.');
        _userPosts.removeWhere((post) => post.userId != userId);
        await _cacheService.cacheUserPosts(userId, _userPosts);
      }
      _setLoading(false);
    } catch (e) {
      print('PostsProvider: Error loading user posts: $e');
      // При ошибке refresh восстанавливаем старые данные или кеш
      if (refresh) {
        if (oldPosts != null && oldPosts.isNotEmpty) {
          _userPosts = oldPosts; // Восстанавливаем старые данные
          print('PostsProvider: User posts refresh failed, restored old posts');
        } else {
          // Если нет старых данных, пытаемся загрузить из кеша
          final cachedUserPosts = _cacheService.getCachedUserPosts(userId);
          if (cachedUserPosts != null) {
            // ВАЖНО: Фильтруем кешированные посты
            final filteredCachedPosts = cachedUserPosts.where((post) => post.userId == userId).toList();
            if (filteredCachedPosts.length != cachedUserPosts.length) {
              print('PostsProvider: Filtered out ${cachedUserPosts.length - filteredCachedPosts.length} invalid posts from cache');
              await _cacheService.cacheUserPosts(userId, filteredCachedPosts);
            }
            _userPosts = filteredCachedPosts;
            print('PostsProvider: User posts refresh failed, loaded ${filteredCachedPosts.length} posts from cache');
          } else {
            _userPosts = [];
          }
        }
      } else {
        // При ошибке загрузки следующей страницы используем кеш, если список пуст
        if (_userPosts.isEmpty) {
          final cachedUserPosts = _cacheService.getCachedUserPosts(userId);
          if (cachedUserPosts != null) {
            // ВАЖНО: Фильтруем кешированные посты
            final filteredCachedPosts = cachedUserPosts.where((post) => post.userId == userId).toList();
            if (filteredCachedPosts.length != cachedUserPosts.length) {
              print('PostsProvider: Filtered out ${cachedUserPosts.length - filteredCachedPosts.length} invalid posts from cache');
              await _cacheService.cacheUserPosts(userId, filteredCachedPosts);
            }
            _userPosts = filteredCachedPosts;
            notifyListeners();
          }
        }
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
      _followingVideoPosts.removeWhere((post) => post.id == postId);

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
