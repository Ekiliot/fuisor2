import express from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { sendNotificationForEvent } from '../utils/fcm_service.js';
import { isNotificationEnabled } from '../utils/notification_preferences.js';

const router = express.Router();

// Get user notifications
router.get('/', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;

    // Get notifications with actor profile info
    const { data: notifications, error } = await supabaseAdmin
      .from('notifications')
      .select(`
        id,
        type,
        post_id,
        comment_id,
        is_read,
        created_at,
        actor:actor_id (
          id,
          username,
          name,
          avatar_url
        ),
        post:post_id (
          id,
          media_url,
          media_type,
          caption
        ),
        comment:comment_id (
          id,
          content
        )
      `)
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      console.error('Error fetching notifications:', error);
      return res.status(500).json({ error: error.message });
    }

    // Get total count
    const { count, error: countError } = await supabaseAdmin
      .from('notifications')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId);

    if (countError) {
      console.error('Error counting notifications:', countError);
      return res.status(500).json({ error: countError.message });
    }

    // Get unread count
    const { count: unreadCount, error: unreadError } = await supabaseAdmin
      .from('notifications')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('is_read', false);

    if (unreadError) {
      console.error('Error counting unread notifications:', unreadError);
      return res.status(500).json({ error: unreadError.message });
    }

    res.json({
      notifications,
      total: count,
      unreadCount,
      page,
      totalPages: Math.ceil(count / limit)
    });
  } catch (error) {
    console.error('Error fetching notifications:', error);
    res.status(500).json({ error: error.message });
  }
});

// Mark notification as read
router.put('/:notificationId/read', validateAuth, async (req, res) => {
  try {
    const notificationId = req.params.notificationId;
    const userId = req.user.id;

    const { data, error } = await supabaseAdmin
      .from('notifications')
      .update({ is_read: true, updated_at: new Date().toISOString() })
      .eq('id', notificationId)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) {
      console.error('Error marking notification as read:', error);
      return res.status(500).json({ error: error.message });
    }

    res.json(data);
  } catch (error) {
    console.error('Error marking notification as read:', error);
    res.status(500).json({ error: error.message });
  }
});

// Mark all notifications as read
router.put('/read-all', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    const { error } = await supabaseAdmin
      .from('notifications')
      .update({ is_read: true, updated_at: new Date().toISOString() })
      .eq('user_id', userId)
      .eq('is_read', false);

    if (error) {
      console.error('Error marking all notifications as read:', error);
      return res.status(500).json({ error: error.message });
    }

    res.json({ message: 'All notifications marked as read' });
  } catch (error) {
    console.error('Error marking all notifications as read:', error);
    res.status(500).json({ error: error.message });
  }
});

// Delete notification
router.delete('/:notificationId', validateAuth, async (req, res) => {
  try {
    const notificationId = req.params.notificationId;
    const userId = req.user.id;

    const { error } = await supabaseAdmin
      .from('notifications')
      .delete()
      .eq('id', notificationId)
      .eq('user_id', userId);

    if (error) {
      console.error('Error deleting notification:', error);
      return res.status(500).json({ error: error.message });
    }

    res.json({ message: 'Notification deleted successfully' });
  } catch (error) {
    console.error('Error deleting notification:', error);
    res.status(500).json({ error: error.message });
  }
});

// Check for new events (for background notification service)
router.get('/check', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const lastCheckTime = req.query.lastCheckTime;
    const limit = parseInt(req.query.limit) || 50;

    // Validate lastCheckTime if provided
    if (lastCheckTime && isNaN(Date.parse(lastCheckTime))) {
      return res.status(400).json({ error: 'Invalid lastCheckTime format. Must be ISO 8601 date string.' });
    }

    const defaultTimeRange = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    console.log('[Notifications Check] Starting check for user:', userId);
    console.log('[Notifications Check] Last check time:', lastCheckTime || 'Not provided (using 24h default)');

    // Execute all checks in parallel
    const [
      notificationsResult,
      messagesResult,
      postsResult,
      storiesResult
    ] = await Promise.all([
      // 1. Check for unread notifications
      (async () => {
        try {
          let query = supabaseAdmin
            .from('notifications')
            .select(`
              id,
              type,
              post_id,
              comment_id,
              is_read,
              created_at,
              actor:actor_id (
                id,
                username,
                name,
                avatar_url
              ),
              post:post_id (
                id,
                media_url,
                media_type,
                caption
              ),
              comment:comment_id (
                id,
                content
              )
            `)
            .eq('user_id', userId)
            .eq('is_read', false)
            .order('created_at', { ascending: false })
            .limit(limit);

          if (lastCheckTime) {
            query = query.gt('created_at', lastCheckTime);
          }

          const { data, error } = await query;
          
          if (error) {
            console.error('[Notifications Check] Error fetching notifications:', error);
            return { data: [], error };
          }

          console.log(`[Notifications Check] Found ${data?.length || 0} unread notifications`);
          return { data: data || [], error: null };
        } catch (error) {
          console.error('[Notifications Check] Exception in notifications check:', error);
          return { data: [], error };
        }
      })(),

      // 2. Check for chats with unread messages
      (async () => {
        try {
          // Get chats with unread messages
          const { data: participants, error: participantsError } = await supabaseAdmin
            .from('chat_participants')
            .select('chat_id, unread_count, last_read_at')
            .eq('user_id', userId)
            .gt('unread_count', 0);

          if (participantsError) {
            console.error('[Notifications Check] Error fetching participants:', participantsError);
            return { data: [], error: participantsError };
          }

          const chatIds = participants?.map(p => p.chat_id) || [];

          if (chatIds.length === 0) {
            console.log('[Notifications Check] No chats with unread messages');
            return { data: [], error: null };
          }

          // Get chat details with last message
          const { data: chats, error: chatsError } = await supabaseAdmin
            .from('chats')
            .select(`
              id,
              type,
              created_at,
              updated_at,
              participants:chat_participants(
                user_id,
                unread_count,
                user:profiles!user_id(
                  id,
                  username,
                  name,
                  avatar_url
                )
              )
            `)
            .in('id', chatIds);

          if (chatsError) {
            console.error('[Notifications Check] Error fetching chats:', chatsError);
            return { data: [], error: chatsError };
          }

          // Get last message for each chat
          const chatsWithMessages = await Promise.all(
            (chats || []).map(async (chat) => {
              const { data: lastMessage } = await supabaseAdmin
                .from('messages')
                .select(`
                  id,
                  chat_id,
                  content,
                  message_type,
                  sender_id,
                  is_read,
                  created_at,
                  sender:profiles!sender_id(
                    id,
                    username,
                    name,
                    avatar_url
                  )
                `)
                .eq('chat_id', chat.id)
                .is('deleted_at', null)
                .order('created_at', { ascending: false })
                .limit(1)
                .single();

              const myParticipant = chat.participants?.find(p => p.user_id === userId);
              const otherParticipant = chat.participants?.find(p => p.user_id !== userId);

              return {
                id: chat.id,
                type: chat.type,
                created_at: chat.created_at,
                updated_at: chat.updated_at,
                unread_count: myParticipant?.unread_count || 0,
                other_user: otherParticipant?.user || null,
                last_message: lastMessage || null
              };
            })
          );

          console.log(`[Notifications Check] Found ${chatsWithMessages.length} chats with unread messages`);
          return { data: chatsWithMessages, error: null };
        } catch (error) {
          console.error('[Notifications Check] Exception in messages check:', error);
          return { data: [], error };
        }
      })(),

      // 3. Check for new posts from following
      (async () => {
        try {
          // Get following users
          const { data: following, error: followingError } = await supabaseAdmin
            .from('follows')
            .select('following_id')
            .eq('follower_id', userId);

          if (followingError) {
            console.error('[Notifications Check] Error fetching following:', followingError);
            return { data: [], error: followingError };
          }

          const followingIds = following?.map(f => f.following_id) || [];

          if (followingIds.length === 0) {
            console.log('[Notifications Check] User is not following anyone');
            return { data: [], error: null };
          }

          // Get new posts from following
          const { data: posts, error: postsError } = await supabaseAdmin
            .from('posts')
            .select(`
              id,
              user_id,
              caption,
              media_url,
              media_type,
              thumbnail_url,
              created_at,
              user:profiles!user_id (
                id,
                username,
                name,
                avatar_url
              )
            `)
            .in('user_id', followingIds)
            .is('expires_at', null)  // Not stories
            .gt('created_at', lastCheckTime || defaultTimeRange)
            .order('created_at', { ascending: false })
            .limit(limit);

          if (postsError) {
            console.error('[Notifications Check] Error fetching posts:', postsError);
            return { data: [], error: postsError };
          }

          console.log(`[Notifications Check] Found ${posts?.length || 0} new posts from following`);
          return { data: posts || [], error: null };
        } catch (error) {
          console.error('[Notifications Check] Exception in posts check:', error);
          return { data: [], error };
        }
      })(),

      // 4. Check for new stories from following
      (async () => {
        try {
          // Get following users
          const { data: following, error: followingError } = await supabaseAdmin
            .from('follows')
            .select('following_id')
            .eq('follower_id', userId);

          if (followingError) {
            console.error('[Notifications Check] Error fetching following for stories:', followingError);
            return { data: [], error: followingError };
          }

          const followingIds = following?.map(f => f.following_id) || [];

          if (followingIds.length === 0) {
            console.log('[Notifications Check] User is not following anyone (stories)');
            return { data: [], error: null };
          }

          const now = new Date().toISOString();

          // Get new stories from following
          const { data: stories, error: storiesError } = await supabaseAdmin
            .from('posts')
            .select(`
              id,
              user_id,
              caption,
              media_url,
              media_type,
              thumbnail_url,
              expires_at,
              created_at,
              user:profiles!user_id (
                id,
                username,
                name,
                avatar_url
              )
            `)
            .in('user_id', followingIds)
            .not('expires_at', 'is', null)  // Only stories
            .gt('expires_at', now)  // Not expired
            .gt('created_at', lastCheckTime || defaultTimeRange)
            .order('created_at', { ascending: false })
            .limit(limit);

          if (storiesError) {
            console.error('[Notifications Check] Error fetching stories:', storiesError);
            return { data: [], error: storiesError };
          }

          console.log(`[Notifications Check] Found ${stories?.length || 0} new stories from following`);
          return { data: stories || [], error: null };
        } catch (error) {
          console.error('[Notifications Check] Exception in stories check:', error);
          return { data: [], error };
        }
      })()
    ]);

    // Build response with summary and details
    const notifications = notificationsResult.data || [];
    const messages = messagesResult.data || [];
    const posts = postsResult.data || [];
    const stories = storiesResult.data || [];

    const response = {
      summary: {
        notifications: notifications.length,
        messages: messages.length,
        posts: posts.length,
        stories: stories.length,
        total: notifications.length + messages.length + posts.length + stories.length
      },
      details: {
        notifications,
        messages,
        posts,
        stories
      },
      timestamp: new Date().toISOString()
    };

    console.log('[Notifications Check] Summary:', response.summary);

    res.json(response);
  } catch (error) {
    console.error('[Notifications Check] Error in check endpoint:', error);
    res.status(500).json({ error: error.message });
  }
});

// Create notification (helper function for other routes)
async function createNotification(userId, actorId, type, postId = null, commentId = null, options = {}) {
  try {
    // Don't create notification if user is notifying themselves
    if (userId === actorId) {
      return null;
    }

    // Check if this notification type is enabled for the user
    const isEnabled = await isNotificationEnabled(userId, type);
    if (!isEnabled) {
      console.log(`[Notification] Notification type "${type}" is disabled for user ${userId}. Skipping.`);
      return null;
    }

    const { data, error } = await supabaseAdmin
      .from('notifications')
      .insert({
        user_id: userId,
        actor_id: actorId,
        type,
        post_id: postId,
        comment_id: commentId,
        is_read: false
      })
      .select()
      .single();

    if (error) {
      console.error('Error creating notification:', error);
      return null;
    }

    // Отправляем FCM уведомление (не блокируем, если FCM недоступен)
    try {
      await sendNotificationForEvent(userId, actorId, type, {
        postId,
        commentId,
        ...options,
      });
    } catch (fcmError) {
      // Логируем ошибку, но не прерываем создание уведомления в БД
      console.error('[FCM] Error sending push notification:', fcmError.message);
    }

    return data;
  } catch (error) {
    console.error('Error creating notification:', error);
    return null;
  }
}

export { router, createNotification };

