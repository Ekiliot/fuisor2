# Имплементация голосовых сообщений - Руководство

## ✅ Что уже сделано:

### Backend:
1. **SQL миграции созданы**:
   - `supabase/migrations/add_voice_messages.sql` - добавляет поля для медиа в таблицу `messages`
   - `supabase/setup_dm_media_bucket.sql` - создает bucket `dm_media` с RLS политиками

2. **API эндпоинты**:
   - `POST /api/messages/chats/:chatId/upload` - загрузка медиафайлов
   - `POST /api/messages/chats/:chatId/messages` - обновлен для поддержки медиа-сообщений

3. **Зависимости добавлены** в `pubspec.yaml`:
   - `record: ^5.0.4` - запись аудио
   - `audioplayers: ^5.2.1` - воспроизведение
   - `path_provider: ^2.1.1` - пути к файлам
   - `permission_handler: ^11.0.1` - разрешения

### Frontend:
4. **Виджеты созданы**:
   - `fuisor_app/lib/widgets/voice_recorder_widget.dart` - запись голоса
   - `fuisor_app/lib/widgets/voice_message_player.dart` - воспроизведение

## 🔨 Что нужно доработать:

### 1. Запустить SQL миграции в Supabase:
```sql
-- В Supabase SQL Editor выполните:
-- 1. supabase/migrations/add_voice_messages.sql
-- 2. supabase/setup_dm_media_bucket.sql
```

### 2. Добавить методы в `ApiService` (`fuisor_app/lib/services/api_service.dart`):
```dart
// Upload voice message
Future<Map<String, dynamic>> uploadVoiceMessage({
  required String chatId,
  required String filePath,
  required int duration,
}) async {
  try {
    final file = File(filePath);
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/messages/chats/$chatId/upload'),
    );
    
    request.headers['Authorization'] = 'Bearer $_accessToken';
    request.fields['messageType'] = 'voice';
    request.fields['duration'] = duration.toString();
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      filename: 'voice.m4a',
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to upload voice message');
    }
  } catch (e) {
    throw Exception('Failed to upload voice message: $e');
  }
}

// Send voice message
Future<Message> sendVoiceMessage({
  required String chatId,
  required String mediaUrl,
  required int duration,
  required int size,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/messages/chats/$chatId/messages'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_accessToken',
    },
    body: json.encode({
      'messageType': 'voice',
      'mediaUrl': mediaUrl,
      'mediaDuration': duration,
      'mediaSize': size,
    }),
  );

  if (response.statusCode == 201) {
    final data = json.decode(response.body);
    return Message.fromJson(data['message']);
  } else {
    throw Exception('Failed to send voice message');
  }
}
```

### 3. Обновить модель `Message` (`fuisor_app/lib/models/message.dart`):
```dart
class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String? content;
  final String messageType; // 'text', 'voice', 'image', 'video'
  final String? mediaUrl;
  final int? mediaDuration;
  final int? mediaSize;
  bool isRead;
  final DateTime? readAt;
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
    this.mediaDuration,
    this.mediaSize,
    required this.isRead,
    this.readAt,
    required this.createdAt,
    required this.updatedAt,
    this.sender,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      chatId: json['chat_id'],
      senderId: json['sender_id'],
      content: json['content'],
      messageType: json['message_type'] ?? 'text',
      mediaUrl: json['media_url'],
      mediaDuration: json['media_duration'],
      mediaSize: json['media_size'],
      isRead: json['is_read'] ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      sender: json['sender'] != null ? User.fromJson(json['sender']) : null,
    );
  }
}
```

### 4. Интегрировать в `ChatScreen`:

#### 4.1. Добавить обработчик долгого нажатия на микрофон:
```dart
// В _buildMessageInput(), заменить кнопку микрофона:
GestureDetector(
  onLongPressStart: (details) {
    // Начать запись
    setState(() {
      _isRecordingVoice = true;
    });
  },
  onTap: !_hasText ? () {
    // Show info
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hold to record voice message'),
        duration: Duration(seconds: 2),
      ),
    );
  } : null,
  child: // ... existing icon button
)
```

#### 4.2. Добавить VoiceRecorderWidget в build():
```dart
// После Stack с messages
if (_isRecordingVoice)
  VoiceRecorderWidget(
    onSend: (path, duration) async {
      // Upload and send
      try {
        final uploadResult = await _apiService.uploadVoiceMessage(
          chatId: widget.chat.id,
          filePath: path,
          duration: duration,
        );
        
        await _apiService.sendVoiceMessage(
          chatId: widget.chat.id,
          mediaUrl: uploadResult['mediaUrl'],
          duration: uploadResult['mediaDuration'],
          size: uploadResult['mediaSize'],
        );
        
        _loadMessages(refresh: true);
      } catch (e) {
        print('Error sending voice: $e');
      } finally {
        setState(() {
          _isRecordingVoice = false;
        });
      }
    },
    onCancel: () {
      setState(() {
        _isRecordingVoice = false;
      });
    },
  ),
```

#### 4.3. Обновить _buildMessageItem для отображения голосовых:
```dart
Widget _buildMessageItem(Message message, int index) {
  // ... existing code
  
  // В Container с message.content, заменить на:
  Container(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width * 0.75,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: isOwnMessage ? const Color(0xFF0095F6) : const Color(0xFF262626),
      borderRadius: BorderRadius.circular(20),
    ),
    child: message.messageType == 'voice'
        ? VoiceMessagePlayer(
            audioUrl: message.mediaUrl!,
            duration: message.mediaDuration!,
            isOwnMessage: isOwnMessage,
          )
        : Text(
            message.content ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
  ),
```

### 5. Добавить разрешения:

#### Android (`fuisor_app/android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

#### iOS (`fuisor_app/ios/Runner/Info.plist`):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone to record voice messages</string>
```

### 6. Установить зависимости:
```bash
cd fuisor_app
flutter pub get
```

### 7. Перезапустить сервер Node.js

## 🎯 Функционал:

✅ **Запись голоса** - долгое нажатие на микрофон
✅ **Визуализация** - анимированная waveform во время записи  
✅ **Отправка** - отпустить кнопку
✅ **Hands-free режим** - свайп вверх к замочку
✅ **Отмена** - свайп влево
✅ **Воспроизведение** - плеер с прогрессом
✅ **Безопасность** - RLS политики для приватного bucket

## ⚠️ Важно:
- Для production нужно реализовать получение signed URLs из бэкенда
- Добавить обработку ошибок и loading states
- Протестировать на реальных устройствах (разрешения)

