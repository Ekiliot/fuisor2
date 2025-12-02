import admin from 'firebase-admin';
import { supabaseAdmin } from '../config/supabase.js';

// Инициализация Firebase Admin (будет инициализирована при первом использовании)
let fcmInitialized = false;

/**
 * Инициализация Firebase Admin SDK
 */
function initializeFCM() {
  if (fcmInitialized) {
    return;
  }

  // Проверяем наличие переменных окружения
  const firebaseConfig = process.env.FIREBASE_ADMIN_CONFIG;
  
  if (!firebaseConfig) {
    console.warn('[FCM] FIREBASE_ADMIN_CONFIG not found. FCM notifications will be disabled.');
    console.warn('[FCM] To enable FCM, set FIREBASE_ADMIN_CONFIG environment variable with service account JSON.');
    return;
  }

  try {
    // Парсим конфигурацию из переменной окружения (JSON строка)
    const serviceAccount = typeof firebaseConfig === 'string' 
      ? JSON.parse(firebaseConfig)
      : firebaseConfig;

    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });

    fcmInitialized = true;
    console.log('[FCM] Firebase Admin initialized successfully');
  } catch (error) {
    console.error('[FCM] Error initializing Firebase Admin:', error.message);
    console.error('[FCM] Make sure FIREBASE_ADMIN_CONFIG contains valid JSON service account credentials');
  }
}

/**
 * Получить FCM токен пользователя из базы данных
 */
async function getUserFCMToken(userId) {
  try {
    const { data, error } = await supabaseAdmin
      .from('profiles')
      .select('fcm_token')
      .eq('id', userId)
      .single();

    if (error) {
      console.error(`[FCM] Error fetching FCM token for user ${userId}:`, error.message);
      return null;
    }

    return data?.fcm_token || null;
  } catch (error) {
    console.error(`[FCM] Error getting FCM token for user ${userId}:`, error.message);
    return null;
  }
}

/**
 * Получить информацию о пользователе (actor) для уведомления
 */
async function getActorInfo(actorId) {
  try {
    const { data, error } = await supabaseAdmin
      .from('profiles')
      .select('id, username, name, avatar_url')
      .eq('id', actorId)
      .single();

    if (error || !data) {
      return { name: 'Someone', username: 'someone' };
    }

    return {
      name: data.name || data.username || 'Someone',
      username: data.username || 'someone',
      avatarUrl: data.avatar_url,
    };
  } catch (error) {
    console.error(`[FCM] Error getting actor info for ${actorId}:`, error.message);
    return { name: 'Someone', username: 'someone' };
  }
}

/**
 * Отправить FCM уведомление
 */
async function sendFCMNotification(userId, title, body, data = {}) {
  // Инициализируем FCM при первом использовании
  if (!fcmInitialized) {
    initializeFCM();
  }

  if (!fcmInitialized) {
    console.log(`[FCM] Skipping notification to user ${userId} - FCM not initialized`);
    return false;
  }

  try {
    // Получаем FCM токен пользователя
    const fcmToken = await getUserFCMToken(userId);
    
    if (!fcmToken) {
      console.log(`[FCM] User ${userId} has no FCM token registered`);
      return false;
    }

    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        // Все данные должны быть строками
        type: String(data.type || ''),
        timestamp: String(Date.now()),
      },
      token: fcmToken,
      // Android настройки
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'sonet_notifications',
        },
      },
      // APNS настройки (для iOS)
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log(`[FCM] Successfully sent notification to user ${userId}:`, response);
    return true;
  } catch (error) {
    console.error(`[FCM] Error sending notification to user ${userId}:`, error.message);
    
    // Если токен невалидный или устарел, удаляем его из БД
    if (error.code === 'messaging/invalid-registration-token' || 
        error.code === 'messaging/registration-token-not-registered') {
      console.log(`[FCM] Removing invalid FCM token for user ${userId}`);
      await supabaseAdmin
        .from('profiles')
        .update({ fcm_token: null })
        .eq('id', userId);
    }
    
    return false;
  }
}

/**
 * Отправить уведомление о новом событии
 */
async function sendNotificationForEvent(userId, actorId, type, options = {}) {
  try {
    // Получаем информацию об акторе (кто совершил действие)
    const actor = await getActorInfo(actorId);
    
    let title = '';
    let body = '';
    const data = {
      type: type,
      actor_id: actorId,
    };

    switch (type) {
      case 'like':
        title = `${actor.name} liked your post`;
        body = 'Tap to view';
        if (options.postId) {
          data.post_id = String(options.postId);
        }
        break;

      case 'comment':
        title = `${actor.name} commented on your post`;
        body = options.commentContent 
          ? (options.commentContent.length > 50 
              ? `${options.commentContent.substring(0, 50)}...`
              : options.commentContent)
          : 'Tap to view';
        if (options.postId) {
          data.post_id = String(options.postId);
        }
        if (options.commentId) {
          data.comment_id = String(options.commentId);
        }
        break;

      case 'follow':
        title = `${actor.name} started following you`;
        body = 'Tap to view profile';
        break;

      case 'mention':
        title = `${actor.name} mentioned you`;
        body = options.mentionContext || 'Tap to view';
        if (options.postId) {
          data.post_id = String(options.postId);
        }
        if (options.commentId) {
          data.comment_id = String(options.commentId);
        }
        break;

      case 'message':
        title = options.otherUserName || actor.name;
        body = options.messageContent 
          ? (options.messageContent.length > 50 
              ? `${options.messageContent.substring(0, 50)}...`
              : options.messageContent)
          : 'New message';
        if (options.chatId) {
          data.chat_id = String(options.chatId);
        }
        if (options.unreadCount) {
          data.unread_count = String(options.unreadCount);
        }
        break;

      case 'comment_like':
        title = `${actor.name} liked your comment`;
        body = 'Tap to view';
        if (options.postId) {
          data.post_id = String(options.postId);
        }
        if (options.commentId) {
          data.comment_id = String(options.commentId);
        }
        break;

      default:
        title = `New notification from ${actor.name}`;
        body = 'Tap to view';
    }

    return await sendFCMNotification(userId, title, body, data);
  } catch (error) {
    console.error(`[FCM] Error sending notification for event (${type}):`, error.message);
    return false;
  }
}

export {
  initializeFCM,
  sendFCMNotification,
  sendNotificationForEvent,
  getUserFCMToken,
};
