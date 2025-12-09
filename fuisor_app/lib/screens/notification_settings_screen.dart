import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/animated_app_bar_title.dart';
import '../services/api_service.dart';
import '../widgets/app_notification.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  bool _isSaving = false;

  // Notification preferences
  bool mentionEnabled = true;
  bool commentMentionEnabled = true;
  bool newPostEnabled = true;
  bool newStoryEnabled = true;
  bool followEnabled = true;
  bool likeEnabled = true;
  bool commentEnabled = true;
  bool commentReplyEnabled = true;
  bool commentLikeEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        setState(() => _isLoading = false);
        return;
      }

      _apiService.setAccessToken(accessToken);
      
      // Load preferences from API
      final response = await _apiService.getNotificationPreferences();
      
      setState(() {
        mentionEnabled = response['mention_enabled'] ?? true;
        commentMentionEnabled = response['comment_mention_enabled'] ?? true;
        newPostEnabled = response['new_post_enabled'] ?? true;
        newStoryEnabled = response['new_story_enabled'] ?? true;
        followEnabled = response['follow_enabled'] ?? true;
        likeEnabled = response['like_enabled'] ?? true;
        commentEnabled = response['comment_enabled'] ?? true;
        commentReplyEnabled = response['comment_reply_enabled'] ?? true;
        commentLikeEnabled = response['comment_like_enabled'] ?? true;
        _isLoading = false;
      });
    } catch (e) {
      print('NotificationSettingsScreen: Error loading preferences: $e');
      // При ошибке используем значения по умолчанию (все true)
      // Не показываем ошибку пользователю, так как значения по умолчанию уже установлены
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePreference(String key, bool value) async {
    if (_isSaving) return;

    // Optimistically update UI
    setState(() {
      switch (key) {
        case 'mention_enabled':
          mentionEnabled = value;
          break;
        case 'comment_mention_enabled':
          commentMentionEnabled = value;
          break;
        case 'new_post_enabled':
          newPostEnabled = value;
          break;
        case 'new_story_enabled':
          newStoryEnabled = value;
          break;
        case 'follow_enabled':
          followEnabled = value;
          break;
        case 'like_enabled':
          likeEnabled = value;
          break;
        case 'comment_enabled':
          commentEnabled = value;
          break;
        case 'comment_reply_enabled':
          commentReplyEnabled = value;
          break;
        case 'comment_like_enabled':
          commentLikeEnabled = value;
          break;
      }
      _isSaving = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        throw Exception('No access token');
      }

      _apiService.setAccessToken(accessToken);
      await _apiService.updateNotificationPreferences({key: value});

      setState(() => _isSaving = false);
    } catch (e) {
      print('NotificationSettingsScreen: Error updating preference: $e');
      
      // Revert change on error
      setState(() {
        switch (key) {
          case 'mention_enabled':
            mentionEnabled = !value;
            break;
          case 'comment_mention_enabled':
            commentMentionEnabled = !value;
            break;
          case 'new_post_enabled':
            newPostEnabled = !value;
            break;
          case 'new_story_enabled':
            newStoryEnabled = !value;
            break;
          case 'follow_enabled':
            followEnabled = !value;
            break;
          case 'like_enabled':
            likeEnabled = !value;
            break;
          case 'comment_enabled':
            commentEnabled = !value;
            break;
          case 'comment_reply_enabled':
            commentReplyEnabled = !value;
            break;
          case 'comment_like_enabled':
            commentLikeEnabled = !value;
            break;
        }
        _isSaving = false;
      });

      if (mounted) {
        AppNotification.showError(context, 'Error updating preference: ${e.toString()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const AnimatedAppBarTitle(
          text: 'Notifications',
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            )
          : ListView(
              children: [
                const SizedBox(height: 8),
                _buildSwitchTile(
                  icon: EvaIcons.atOutline,
                  title: 'Mentions in posts',
                  subtitle: 'When someone mentions you in a post',
                  value: mentionEnabled,
                  onChanged: (v) => _updatePreference('mention_enabled', v),
                ),
                _buildSwitchTile(
                  icon: EvaIcons.messageCircleOutline,
                  title: 'Mentions in comments',
                  subtitle: 'When someone mentions you in a comment',
                  value: commentMentionEnabled,
                  onChanged: (v) => _updatePreference('comment_mention_enabled', v),
                ),
                const Divider(color: Color(0xFF262626), height: 1, thickness: 0.5),
                _buildSwitchTile(
                  icon: EvaIcons.imageOutline,
                  title: 'New posts',
                  subtitle: 'When people you follow post',
                  value: newPostEnabled,
                  onChanged: (v) => _updatePreference('new_post_enabled', v),
                ),
                _buildSwitchTile(
                  icon: EvaIcons.playCircleOutline,
                  title: 'New stories',
                  subtitle: 'When people you follow post stories',
                  value: newStoryEnabled,
                  onChanged: (v) => _updatePreference('new_story_enabled', v),
                ),
                const Divider(color: Color(0xFF262626), height: 1, thickness: 0.5),
                _buildSwitchTile(
                  icon: EvaIcons.personAddOutline,
                  title: 'Follows',
                  subtitle: 'When someone follows you',
                  value: followEnabled,
                  onChanged: (v) => _updatePreference('follow_enabled', v),
                ),
                const Divider(color: Color(0xFF262626), height: 1, thickness: 0.5),
                _buildSwitchTile(
                  icon: EvaIcons.heartOutline,
                  title: 'Likes',
                  subtitle: 'When someone likes your post',
                  value: likeEnabled,
                  onChanged: (v) => _updatePreference('like_enabled', v),
                ),
                _buildSwitchTile(
                  icon: EvaIcons.messageCircleOutline,
                  title: 'Comments',
                  subtitle: 'When someone comments on your post',
                  value: commentEnabled,
                  onChanged: (v) => _updatePreference('comment_enabled', v),
                ),
                _buildSwitchTile(
                  icon: EvaIcons.cornerUpLeftOutline,
                  title: 'Comment replies',
                  subtitle: 'When someone replies to your comment',
                  value: commentReplyEnabled,
                  onChanged: (v) => _updatePreference('comment_reply_enabled', v),
                ),
                _buildSwitchTile(
                  icon: EvaIcons.heartOutline,
                  title: 'Comment likes',
                  subtitle: 'When someone likes your comment',
                  value: commentLikeEnabled,
                  onChanged: (v) => _updatePreference('comment_like_enabled', v),
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      color: const Color(0xFF0F0F0F),
      child: ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 12),
        ),
        trailing: CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF0095F6),
        ),
      ),
    );
  }
}

