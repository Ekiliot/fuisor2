import 'message.dart';
import 'user.dart';

// Прямой импорт User чтобы избежать циклических зависимостей

class Chat {
  final String id;
  final String type; // 'direct' or 'group'
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? otherUser; // Для direct чата - другой пользователь
  final List<ChatParticipant>? participants; // Для group чата
  final int unreadCount;
  final Message? lastMessage;
  final bool isArchived; // Архивирован ли чат для текущего пользователя
  final bool isPinned; // Закреплен ли чат

  Chat({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.otherUser,
    this.participants,
    this.unreadCount = 0,
    this.lastMessage,
    this.isArchived = false,
    this.isPinned = false,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    try {
      // Безопасная обработка дат
      DateTime createdAt;
      try {
        createdAt = DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String());
      } catch (e) {
        createdAt = DateTime.now();
      }

      DateTime updatedAt;
      if (json['updated_at'] != null) {
        try {
          updatedAt = DateTime.parse(json['updated_at']);
        } catch (e) {
          updatedAt = createdAt;
        }
      } else {
        updatedAt = createdAt;
      }

      // Безопасная обработка otherUser
      User? otherUser;
      if (json['otherUser'] != null && json['otherUser'] is Map) {
        try {
          // Используем fromProfileJson для участников чата (без email и счетчиков)
          final userData = json['otherUser'] as Map<String, dynamic>;
          // Проверяем наличие email - если есть, используем обычный fromJson
          if (userData['email'] != null) {
            otherUser = User.fromJson(userData);
          } else {
            // Используем безопасный парсинг для профилей без email
            otherUser = User(
              id: userData['id'] ?? '',
              username: userData['username'] ?? '',
              name: userData['name'] ?? '',
              email: '', // Email не требуется для участников чата
              avatarUrl: userData['avatar_url'],
              bio: userData['bio'],
              followersCount: 0,
              followingCount: 0,
              postsCount: 0,
              createdAt: userData['created_at'] != null
                  ? DateTime.parse(userData['created_at'])
                  : DateTime.now(),
            );
          }
        } catch (e) {
          print('Error parsing otherUser in Chat.fromJson: $e');
          print('otherUser data: ${json['otherUser']}');
          otherUser = null;
        }
      }

      // Безопасная обработка participants
      List<ChatParticipant>? participants;
      if (json['participants'] != null && json['participants'] is List) {
        try {
          participants = (json['participants'] as List)
              .map((p) => ChatParticipant.fromJson(p))
              .toList();
        } catch (e) {
          print('Error parsing participants in Chat.fromJson: $e');
          participants = null;
        }
      }

      // Безопасная обработка lastMessage
      Message? lastMessage;
      if (json['lastMessage'] != null && json['lastMessage'] is Map) {
        try {
          lastMessage = Message.fromJson(json['lastMessage']);
        } catch (e) {
          print('Error parsing lastMessage in Chat.fromJson: $e');
          lastMessage = null;
        }
      }

      return Chat(
        id: json['id'] ?? '',
        type: json['type'] ?? 'direct',
        createdAt: createdAt,
        updatedAt: updatedAt,
        otherUser: otherUser,
        participants: participants,
        unreadCount: json['unreadCount'] ?? 0,
        lastMessage: lastMessage,
        isArchived: json['isArchived'] ?? false,
        isPinned: json['isPinned'] ?? false,
      );
    } catch (e) {
      print('Error in Chat.fromJson: $e');
      print('JSON data: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'otherUser': otherUser?.toJson(),
      'participants': participants?.map((p) => p.toJson()).toList(),
      'unreadCount': unreadCount,
      'lastMessage': lastMessage?.toJson(),
      'isArchived': isArchived,
      'isPinned': isPinned,
    };
  }

  bool get isDirect => type == 'direct';
  bool get isGroup => type == 'group';
  
  String get displayName {
    if (isDirect && otherUser != null) {
      return otherUser!.name.isNotEmpty ? otherUser!.name : otherUser!.username;
    }
    // Для групповых чатов можно добавить имя группы позже
    return 'Group Chat';
  }

  String? get displayAvatar {
    if (isDirect && otherUser != null) {
      return otherUser!.avatarUrl;
    }
    return null;
  }
}

class ChatParticipant {
  final User user;
  final int unreadCount;
  final DateTime? lastReadAt;

  ChatParticipant({
    required this.user,
    this.unreadCount = 0,
    this.lastReadAt,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    try {
      // Безопасный парсинг User для участников чата
      User user;
      if (json['user'] != null && json['user'] is Map) {
        final userData = json['user'] as Map<String, dynamic>;
        // Если есть email, используем обычный fromJson, иначе создаем без него
        if (userData['email'] != null) {
          user = User.fromJson(userData);
        } else {
          user = User(
            id: userData['id'] ?? '',
            username: userData['username'] ?? '',
            name: userData['name'] ?? '',
            email: '',
            avatarUrl: userData['avatar_url'],
            bio: userData['bio'],
            followersCount: 0,
            followingCount: 0,
            postsCount: 0,
            createdAt: userData['created_at'] != null
                ? DateTime.parse(userData['created_at'])
                : DateTime.now(),
          );
        }
      } else {
        throw Exception('User data is missing or invalid');
      }

      return ChatParticipant(
        user: user,
        unreadCount: json['unreadCount'] ?? 0,
        lastReadAt: json['lastReadAt'] != null ? DateTime.parse(json['lastReadAt']) : null,
      );
    } catch (e) {
      print('Error parsing ChatParticipant.fromJson: $e');
      print('JSON data: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'unreadCount': unreadCount,
      'lastReadAt': lastReadAt?.toIso8601String(),
    };
  }
}

