import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart' show Post;

enum Priority {
  high,    // Текущее + следующее видео
  medium,  // +2, +3
  low,     // Непросмотренные из предыдущей сессии
}

class QueuedVideo {
  final Post post;
  final Priority priority;
  final DateTime queuedAt;
  final bool isUnviewed; // из предыдущей сессии

  QueuedVideo({
    required this.post,
    required this.priority,
    required this.queuedAt,
    this.isUnviewed = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'post': post.toJson(),
      'priority': priority.toString(),
      'queuedAt': queuedAt.toIso8601String(),
      'isUnviewed': isUnviewed,
    };
  }

  factory QueuedVideo.fromJson(Map<String, dynamic> json) {
    return QueuedVideo(
      post: Post.fromJson(json['post']),
      priority: Priority.values.firstWhere(
        (p) => p.toString() == json['priority'],
        orElse: () => Priority.low,
      ),
      queuedAt: DateTime.parse(json['queuedAt']),
      isUnviewed: json['isUnviewed'] ?? false,
    );
  }
}

/// Сервис для управления очередью предзагрузки видео
class VideoPreloadQueue {
  static const String _queueKey = 'video_preload_queue';
  static const String _unviewedKey = 'unviewed_videos';
  
  final List<QueuedVideo> _queue = [];
  bool _isProcessing = false;

  /// Добавить видео в очередь
  void addVideo(Post post, Priority priority, {bool isUnviewed = false}) {
    // Проверяем, нет ли уже этого видео в очереди
    if (_queue.any((q) => q.post.id == post.id)) {
      return;
    }

    final queuedVideo = QueuedVideo(
      post: post,
      priority: priority,
      queuedAt: DateTime.now(),
      isUnviewed: isUnviewed,
    );

    _queue.add(queuedVideo);
    _sortQueue();
    print('VideoPreloadQueue: Added video ${post.id} with priority $priority');
  }

  /// Получить следующее видео из очереди
  QueuedVideo? getNextVideo() {
    if (_queue.isEmpty) return null;
    
    // Сначала возвращаем непросмотренные (если есть)
    final unviewed = _queue.where((q) => q.isUnviewed).toList();
    if (unviewed.isNotEmpty) {
      final video = unviewed.first;
      _queue.remove(video);
      return video;
    }
    
    // Затем по приоритету
    _sortQueue();
    final video = _queue.removeAt(0);
    return video;
  }

  /// Отметить видео как просмотренное
  void markAsViewed(String postId) {
    _queue.removeWhere((q) => q.post.id == postId);
    print('VideoPreloadQueue: Marked video $postId as viewed');
  }

  /// Сохранить непросмотренные видео
  Future<void> saveUnviewedQueue(List<Post> unviewedPosts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final postsJson = unviewedPosts.map((p) => p.toJson()).toList();
      await prefs.setString(_unviewedKey, jsonEncode(postsJson));
      print('VideoPreloadQueue: Saved ${unviewedPosts.length} unviewed videos');
    } catch (e) {
      print('VideoPreloadQueue: Error saving unviewed queue: $e');
    }
  }

  /// Загрузить непросмотренные видео
  Future<List<Post>> loadUnviewedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unviewedJson = prefs.getString(_unviewedKey);
      
      if (unviewedJson == null || unviewedJson.isEmpty) {
        return [];
      }

      final List<dynamic> postsList = jsonDecode(unviewedJson);
      final posts = postsList
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      
      print('VideoPreloadQueue: Loaded ${posts.length} unviewed videos');
      return posts;
    } catch (e) {
      print('VideoPreloadQueue: Error loading unviewed queue: $e');
      return [];
    }
  }

  /// Очистить очередь непросмотренных
  Future<void> clearUnviewedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_unviewedKey);
      print('VideoPreloadQueue: Cleared unviewed queue');
    } catch (e) {
      print('VideoPreloadQueue: Error clearing unviewed queue: $e');
    }
  }

  /// Сохранить текущую очередь
  Future<void> saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = _queue.map((q) => q.toJson()).toList();
      await prefs.setString(_queueKey, jsonEncode(queueJson));
      print('VideoPreloadQueue: Saved queue with ${_queue.length} videos');
    } catch (e) {
      print('VideoPreloadQueue: Error saving queue: $e');
    }
  }

  /// Загрузить сохраненную очередь
  Future<void> loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString(_queueKey);
      
      if (queueJson == null || queueJson.isEmpty) {
        return;
      }

      final List<dynamic> queueList = jsonDecode(queueJson);
      _queue.clear();
      _queue.addAll(
        queueList.map((json) => QueuedVideo.fromJson(json as Map<String, dynamic>)),
      );
      
      _sortQueue();
      print('VideoPreloadQueue: Loaded queue with ${_queue.length} videos');
    } catch (e) {
      print('VideoPreloadQueue: Error loading queue: $e');
    }
  }

  /// Очистить очередь
  void clearQueue() {
    _queue.clear();
    print('VideoPreloadQueue: Queue cleared');
  }

  /// Получить размер очереди
  int getQueueSize() => _queue.length;

  /// Проверить, обрабатывается ли очередь
  bool get isProcessing => _isProcessing;

  /// Установить флаг обработки
  void setProcessing(bool value) {
    _isProcessing = value;
  }

  /// Сортировать очередь по приоритету
  void _sortQueue() {
    _queue.sort((a, b) {
      // Сначала непросмотренные
      if (a.isUnviewed && !b.isUnviewed) return -1;
      if (!a.isUnviewed && b.isUnviewed) return 1;
      
      // Затем по приоритету
      final priorityOrder = {
        Priority.high: 0,
        Priority.medium: 1,
        Priority.low: 2,
      };
      
      final aPriority = priorityOrder[a.priority] ?? 2;
      final bPriority = priorityOrder[b.priority] ?? 2;
      
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
      
      // Если приоритет одинаковый, по времени добавления
      return a.queuedAt.compareTo(b.queuedAt);
    });
  }
}

