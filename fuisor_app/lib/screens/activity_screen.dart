import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../widgets/animated_app_bar_title.dart';
import 'package:provider/provider.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import '../providers/notifications_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../widgets/safe_avatar.dart';
import '../screens/profile_screen.dart';
import '../screens/comments_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // Load notifications on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      context.read<NotificationsProvider>().loadNotifications(refresh: true, authProvider: authProvider);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final notificationsProvider = context.read<NotificationsProvider>();
      final authProvider = context.read<AuthProvider>();
      if (!notificationsProvider.isLoading && notificationsProvider.hasMoreNotifications) {
        notificationsProvider.loadMoreNotifications(authProvider: authProvider);
      }
    }
  }

  Future<void> _onRefresh() async {
    final authProvider = context.read<AuthProvider>();
    await context.read<NotificationsProvider>().loadNotifications(refresh: true, authProvider: authProvider);
    _refreshController.refreshCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        title: const AnimatedAppBarTitle(
          text: 'Activity',
        ),
        actions: [
          Consumer<NotificationsProvider>(
            builder: (context, notificationsProvider, child) {
              if (notificationsProvider.unreadCount > 0) {
                return IconButton(
                  icon: const Icon(EvaIcons.checkmarkCircle2Outline),
                  onPressed: () {
                    final authProvider = context.read<AuthProvider>();
                    notificationsProvider.markAllAsRead(authProvider: authProvider);
                  },
                  tooltip: 'Mark all as read',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<NotificationsProvider>(
        builder: (context, notificationsProvider, child) {
          if (notificationsProvider.isInitialLoading) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            );
          }

          if (notificationsProvider.notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    EvaIcons.heartOutline,
                    size: 80,
                    color: Color(0xFF8E8E8E),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'When someone likes or comments on your posts,\nyou\'ll see them here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8E8E8E),
                    ),
                  ),
                ],
              ),
            );
          }

          return SmartRefresher(
            controller: _refreshController,
            enablePullDown: true,
            onRefresh: _onRefresh,
            header: const WaterDropHeader(
              waterDropColor: Color(0xFF0095F6),
              complete: SizedBox.shrink(),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: notificationsProvider.notifications.length +
                  (notificationsProvider.isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == notificationsProvider.notifications.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0095F6),
                      ),
                    ),
                  );
                }

                final notification = notificationsProvider.notifications[index];
                return _buildNotificationItem(notification, notificationsProvider);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationItem(NotificationModel notification, NotificationsProvider provider) {
    String message = '';
    IconData icon = EvaIcons.heartOutline;
    Color iconColor = const Color(0xFFED4956);

    switch (notification.type) {
      case 'like':
        message = 'liked your post';
        icon = EvaIcons.heart;
        iconColor = const Color(0xFFED4956);
        break;
      case 'comment':
        message = 'commented: ${notification.comment?.content ?? ""}';
        icon = EvaIcons.messageCircleOutline;
        iconColor = const Color(0xFF0095F6);
        break;
      case 'comment_reply':
        message = 'replied to your comment: ${notification.comment?.content ?? ""}';
        icon = EvaIcons.cornerUpLeftOutline;
        iconColor = const Color(0xFF0095F6);
        break;
      case 'comment_like':
        message = 'liked your comment';
        icon = EvaIcons.heart;
        iconColor = const Color(0xFFED4956);
        break;
      case 'comment_mention':
        // Show that they were mentioned in a comment on a post
        // Post thumbnail will be displayed if available
        message = 'mentioned you in a comment on their post';
        icon = EvaIcons.atOutline;
        iconColor = const Color(0xFF0095F6);
        break;
      case 'follow':
        message = 'started following you';
        icon = EvaIcons.personAddOutline;
        iconColor = const Color(0xFF0095F6);
        break;
      case 'mention':
        message = 'mentioned you in a post';
        icon = EvaIcons.atOutline;
        iconColor = const Color(0xFF0095F6);
        break;
      case 'new_post':
        message = 'posted something new';
        icon = EvaIcons.imageOutline;
        iconColor = const Color(0xFF0095F6);
        break;
      case 'new_story':
        message = 'posted a story';
        icon = EvaIcons.playCircleOutline;
        iconColor = const Color(0xFF0095F6);
        break;
      default:
        message = 'has a new notification';
        icon = EvaIcons.bellOutline;
        iconColor = const Color(0xFF0095F6);
        break;
    }

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: const Color(0xFFED4956),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(
          EvaIcons.trash2Outline,
          color: Colors.white,
        ),
      ),
      onDismissed: (direction) {
        final authProvider = context.read<AuthProvider>();
        provider.deleteNotification(notification.id, authProvider: authProvider);
      },
      child: InkWell(
        onTap: () {
          if (!notification.isRead) {
            final authProvider = context.read<AuthProvider>();
            provider.markAsRead(notification.id, authProvider: authProvider);
          }
          
          // Navigate based on notification type
          switch (notification.type) {
            case 'follow':
              // Navigate to actor's profile
              if (notification.actor != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(userId: notification.actor!.id),
                  ),
                );
              }
              break;
            case 'like':
            case 'comment':
            case 'comment_reply':
            case 'comment_like':
            case 'comment_mention':
            case 'mention':
            case 'new_post':
            case 'new_story':
              // Navigate to post comments or post view
              if (notification.postId != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CommentsScreen(
                      postId: notification.postId!,
                    ),
                  ),
                );
              }
              break;
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: notification.isRead ? Colors.transparent : const Color(0xFF0F0F0F),
          ),
          child: Row(
            children: [
              // Actor avatar
              SafeAvatar(
                imageUrl: notification.actor?.avatarUrl,
                radius: 20,
              ),
              const SizedBox(width: 12),
              
              // Notification content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                        children: [
                          TextSpan(
                            text: notification.actor?.username ?? 'Someone',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: ' $message',
                            style: const TextStyle(color: Color(0xFFB0B0B0)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          timeago.format(notification.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8E8E8E),
                          ),
                        ),
                        // Show post caption preview for comment_mention if available
                        if (notification.type == 'comment_mention' && 
                            notification.post != null &&
                            notification.post!.caption != null &&
                            notification.post!.caption!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '• ${notification.post!.caption!.length > 30 ? notification.post!.caption!.substring(0, 30) + '...' : notification.post!.caption!}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E8E8E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Notification icon or post thumbnail
              if (notification.post != null && notification.post!.mediaUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      notification.post!.mediaUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 44,
                          height: 44,
                          color: const Color(0xFF262626),
                          child: Icon(
                            icon,
                            color: iconColor,
                            size: 20,
                          ),
                        );
                      },
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
