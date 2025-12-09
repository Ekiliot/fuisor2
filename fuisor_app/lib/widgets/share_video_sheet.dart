import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../widgets/safe_avatar.dart';
import '../widgets/app_notification.dart';

class ShareVideoSheet extends StatefulWidget {
  final Post post; // Видео пост для отправки

  const ShareVideoSheet({
    Key? key,
    required this.post,
  }) : super(key: key);

  @override
  State<ShareVideoSheet> createState() => _ShareVideoSheetState();
}

class _ShareVideoSheetState extends State<ShareVideoSheet> {
  final ApiService _apiService = ApiService();
  List<Chat> _chats = [];
  bool _isLoading = true;
  String? _selectedUserId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        throw Exception('No access token');
      }

      _apiService.setAccessToken(accessToken);
      final chats = await _apiService.getChats(includeArchived: false);

      setState(() {
        _chats = chats;
        _isLoading = false;
      });
    } catch (e) {
      print('ShareVideoSheet: Error loading chats: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppNotification.showError(
          context,
          'Failed to load chats: $e',
        );
      }
    }
  }

  Future<void> _sendVideo() async {
    if (_selectedUserId == null) {
      AppNotification.showError(
        context,
        'Please select a user',
      );
      return;
    }

    try {
      setState(() {
        _isSending = true;
      });

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        throw Exception('No access token');
      }

      _apiService.setAccessToken(accessToken);

      // Создаем или получаем чат с выбранным пользователем
      final chat = await _apiService.createChat(_selectedUserId!);

      // Отправляем видео через сообщение
      await _apiService.sendVideoMessage(
        chatId: chat.id,
        postId: widget.post.id,
        mediaUrl: widget.post.mediaUrl,
        thumbnailUrl: widget.post.thumbnailUrl ?? widget.post.mediaUrl,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Возвращаем true для успешной отправки
        AppNotification.showSuccess(
          context,
          'Post sent successfully!',
        );
      }
    } catch (e) {
      print('ShareVideoSheet: Error sending post: $e');
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        AppNotification.showError(
          context,
          'Failed to send post: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: 20),

            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Share Post',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Users list
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(
                  color: Color(0xFF0095F6),
                ),
              )
            else if (_chats.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No chats available',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _chats.length,
                  itemBuilder: (context, index) {
                    final chat = _chats[index];
                    final user = chat.otherUser;
                    if (user == null) return const SizedBox.shrink();

                    final isSelected = _selectedUserId == user.id;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedUserId = user.id;
                        });
                      },
                      child: Container(
                        width: 100,
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF0095F6)
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                  child: SafeAvatar(
                                    imageUrl: user.avatarUrl,
                                    radius: 40,
                                    backgroundColor: const Color(0xFF262626),
                                    fallbackIcon: EvaIcons.personOutline,
                                    iconColor: Colors.white,
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF0095F6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        EvaIcons.checkmark,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              user.username,
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF0095F6)
                                    : Colors.white,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 20),

            // Send button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSending || _selectedUserId == null
                      ? null
                      : _sendVideo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0095F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Send',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

