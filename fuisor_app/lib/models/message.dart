import 'user.dart';

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String? content;
  final String messageType; // 'text', 'voice', 'image', 'video'
  final String? mediaUrl;
  final String? thumbnailUrl; // для видео сообщений
  final String? postId; // ID поста для видео сообщений (Shorts)
  final int? mediaDuration; // in seconds for voice/video
  final int? mediaSize; // in bytes
  bool isRead;
  DateTime? readAt;
  bool isLiked;
  final DateTime? deletedAt;
  final List<String>? deletedByIds;
  final String? replyToId; // ID сообщения, на которое отвечают
  final Message? replyTo; // Само сообщение, на которое отвечают (для предпросмотра)
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? sender;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.content,
    this.messageType = 'text',
    this.mediaUrl,
    this.thumbnailUrl,
    this.postId,
    this.mediaDuration,
    this.mediaSize,
    this.isRead = false,
    this.readAt,
    this.isLiked = false,
    this.deletedAt,
    this.deletedByIds,
    this.replyToId,
    this.replyTo,
    required this.createdAt,
    required this.updatedAt,
    this.sender,
  });
  
  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? content,
    String? messageType,
    String? mediaUrl,
    String? thumbnailUrl,
    String? postId,
    int? mediaDuration,
    int? mediaSize,
    bool? isRead,
    DateTime? readAt,
    bool? isLiked,
    DateTime? deletedAt,
    List<String>? deletedByIds,
    String? replyToId,
    Message? replyTo,
    DateTime? createdAt,
    DateTime? updatedAt,
    User? sender,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      postId: postId ?? this.postId,
      mediaDuration: mediaDuration ?? this.mediaDuration,
      mediaSize: mediaSize ?? this.mediaSize,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      isLiked: isLiked ?? this.isLiked,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedByIds: deletedByIds ?? this.deletedByIds,
      replyToId: replyToId ?? this.replyToId,
      replyTo: replyTo ?? this.replyTo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sender: sender ?? this.sender,
    );
  }

  // Безопасный парсинг reply_to - может быть Map, List или null
  static Message? _parseReplyTo(dynamic replyToData) {
    if (replyToData == null) return null;
    
    Map<String, dynamic>? replyToMap;
    
    // Если это массив (пустой или с элементами)
    if (replyToData is List) {
      // Если массив не пустой и первый элемент - это Map, используем его
      if (replyToData.isNotEmpty && replyToData[0] is Map<String, dynamic>) {
        replyToMap = replyToData[0] as Map<String, dynamic>;
      } else {
        // Пустой массив или неверный формат
        return null;
      }
    } else if (replyToData is Map<String, dynamic>) {
      // Если это Map, используем напрямую
      replyToMap = replyToData;
    } else {
      return null;
    }
    
    // Безопасно парсим reply_to - может быть неполным (только для предпросмотра)
    try {
      // Минимально необходимые поля для reply_to (только id)
      if (replyToMap['id'] == null) {
        return null;
      }
      
      // Используем значения по умолчанию для отсутствующих полей
      final now = DateTime.now();
      
      return Message(
        id: replyToMap['id'] as String,
        chatId: replyToMap['chat_id'] as String? ?? '', // Может отсутствовать в relation
        senderId: replyToMap['sender_id'] as String? ?? 
                  (replyToMap['sender'] != null && replyToMap['sender'] is Map 
                      ? (replyToMap['sender'] as Map)['id'] as String? 
                      : null) ?? '', // Пытаемся взять из sender
        content: replyToMap['content'] as String?,
        messageType: replyToMap['message_type'] as String? ?? 'text',
        mediaUrl: replyToMap['media_url'] as String?,
        thumbnailUrl: replyToMap['thumbnail_url'] as String?,
        postId: replyToMap['post_id'] as String?,
        mediaDuration: replyToMap['media_duration'] as int?,
        mediaSize: replyToMap['media_size'] as int?,
        isRead: replyToMap['is_read'] as bool? ?? false,
        readAt: replyToMap['read_at'] != null && replyToMap['read_at'] is String
            ? DateTime.tryParse(replyToMap['read_at'] as String)
            : null,
        isLiked: replyToMap['is_liked'] as bool? ?? false,
        deletedAt: replyToMap['deleted_at'] != null && replyToMap['deleted_at'] is String
            ? DateTime.tryParse(replyToMap['deleted_at'] as String)
            : null,
        deletedByIds: replyToMap['deleted_by_ids'] != null && replyToMap['deleted_by_ids'] is List
            ? List<String>.from(replyToMap['deleted_by_ids'] as List)
            : null,
        replyToId: replyToMap['reply_to_id'] as String?,
        replyTo: null, // Не парсим вложенные reply_to чтобы избежать рекурсии
        createdAt: replyToMap['created_at'] != null && replyToMap['created_at'] is String
            ? (DateTime.tryParse(replyToMap['created_at'] as String) ?? now)
            : now,
        updatedAt: replyToMap['updated_at'] != null && replyToMap['updated_at'] is String
            ? (DateTime.tryParse(replyToMap['updated_at'] as String) ?? now)
            : (replyToMap['created_at'] != null && replyToMap['created_at'] is String
                ? (DateTime.tryParse(replyToMap['created_at'] as String) ?? now)
                : now),
        sender: replyToMap['sender'] != null && replyToMap['sender'] is Map<String, dynamic>
            ? User.fromJson(replyToMap['sender'] as Map<String, dynamic>)
            : null,
      );
    } catch (e) {
      print('Message: Error parsing reply_to: $e');
      print('Message: reply_to data: $replyToMap');
      return null;
    }
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      chatId: json['chat_id'],
      senderId: json['sender_id'],
      content: json['content'],
      messageType: json['message_type'] ?? 'text',
      mediaUrl: json['media_url'],
      thumbnailUrl: json['thumbnail_url'],
      postId: json['post_id'],
      mediaDuration: json['media_duration'],
      mediaSize: json['media_size'],
      isRead: json['is_read'] ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      isLiked: json['is_liked'] ?? false,
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at']) : null,
      deletedByIds: json['deleted_by_ids'] != null ? List<String>.from(json['deleted_by_ids']) : null,
      replyToId: json['reply_to_id'],
      replyTo: _parseReplyTo(json['reply_to']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.parse(json['created_at']),
      sender: json['sender'] != null ? User.fromJson(json['sender']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'media_url': mediaUrl,
      'thumbnail_url': thumbnailUrl,
      'post_id': postId,
      'media_duration': mediaDuration,
      'media_size': mediaSize,
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'is_liked': isLiked,
      'deleted_at': deletedAt?.toIso8601String(),
      'deleted_by_ids': deletedByIds,
      'reply_to_id': replyToId,
      'reply_to': replyTo?.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sender': sender?.toJson(),
    };
  }
}

