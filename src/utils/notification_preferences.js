import { supabaseAdmin } from '../config/supabase.js';

/**
 * Map notification types to preference column names
 */
const NOTIFICATION_TYPE_TO_PREFERENCE = {
  'mention': 'mention_enabled',
  'comment_mention': 'comment_mention_enabled',
  'new_post': 'new_post_enabled',
  'new_story': 'new_story_enabled',
  'follow': 'follow_enabled',
  'like': 'like_enabled',
  'comment': 'comment_enabled',
  'comment_reply': 'comment_reply_enabled',
  'comment_like': 'comment_like_enabled',
};

/**
 * Check if a notification type is enabled for a user
 * @param {string} userId - User ID
 * @param {string} notificationType - Type of notification
 * @returns {Promise<boolean>} - True if notification is enabled, false otherwise
 */
export async function isNotificationEnabled(userId, notificationType) {
  try {
    const preferenceColumn = NOTIFICATION_TYPE_TO_PREFERENCE[notificationType];
    
    if (!preferenceColumn) {
      // Unknown notification type - default to enabled
      console.warn(`[NotificationPreferences] Unknown notification type: ${notificationType}. Defaulting to enabled.`);
      return true;
    }

    // Get user's notification preferences
    const { data: preferences, error } = await supabaseAdmin
      .from('notification_preferences')
      .select(preferenceColumn)
      .eq('user_id', userId)
      .single();

    if (error) {
      // If preferences don't exist, create default ones
      if (error.code === 'PGRST116') {
        console.log(`[NotificationPreferences] Creating default preferences for user ${userId}`);
        await createDefaultPreferences(userId);
        // Default is enabled
        return true;
      }
      
      console.error(`[NotificationPreferences] Error checking preferences: ${error.message}`);
      // On error, default to enabled
      return true;
    }

    // If preferences exist, return the value (defaults to true if null)
    return preferences?.[preferenceColumn] !== false;
  } catch (error) {
    console.error(`[NotificationPreferences] Exception checking preferences: ${error.message}`);
    // On exception, default to enabled
    return true;
  }
}

/**
 * Create default notification preferences for a user
 * @param {string} userId - User ID
 */
async function createDefaultPreferences(userId) {
  try {
    const { error } = await supabaseAdmin
      .from('notification_preferences')
      .insert({
        user_id: userId,
        // All preferences default to true
      });

    if (error) {
      console.error(`[NotificationPreferences] Error creating default preferences: ${error.message}`);
    }
  } catch (error) {
    console.error(`[NotificationPreferences] Exception creating default preferences: ${error.message}`);
  }
}

/**
 * Get all notification preferences for a user
 * @param {string} userId - User ID
 * @returns {Promise<Object|null>} - User's notification preferences or null if error
 */
export async function getUserNotificationPreferences(userId) {
  try {
    const { data: preferences, error } = await supabaseAdmin
      .from('notification_preferences')
      .select('*')
      .eq('user_id', userId)
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        // Preferences don't exist, create default ones
        await createDefaultPreferences(userId);
        // Return default preferences
        return {
          user_id: userId,
          mention_enabled: true,
          comment_mention_enabled: true,
          new_post_enabled: true,
          new_story_enabled: true,
          follow_enabled: true,
          like_enabled: true,
          comment_enabled: true,
          comment_reply_enabled: true,
          comment_like_enabled: true,
        };
      }
      
      console.error(`[NotificationPreferences] Error getting preferences: ${error.message}`);
      return null;
    }

    return preferences;
  } catch (error) {
    console.error(`[NotificationPreferences] Exception getting preferences: ${error.message}`);
    return null;
  }
}

/**
 * Update notification preferences for a user
 * @param {string} userId - User ID
 * @param {Object} updates - Object with preference updates
 * @returns {Promise<boolean>} - True if successful, false otherwise
 */
export async function updateNotificationPreferences(userId, updates) {
  try {
    // Validate that all keys are valid preference columns
    const validColumns = Object.values(NOTIFICATION_TYPE_TO_PREFERENCE);
    const updateKeys = Object.keys(updates);
    
    const invalidKeys = updateKeys.filter(key => !validColumns.includes(key));
    if (invalidKeys.length > 0) {
      console.error(`[NotificationPreferences] Invalid preference keys: ${invalidKeys.join(', ')}`);
      return false;
    }

    // Ensure preferences exist
    const existingPrefs = await getUserNotificationPreferences(userId);
    if (!existingPrefs) {
      await createDefaultPreferences(userId);
    }

    // Update preferences
    const { error } = await supabaseAdmin
      .from('notification_preferences')
      .update({
        ...updates,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId);

    if (error) {
      console.error(`[NotificationPreferences] Error updating preferences: ${error.message}`);
      return false;
    }

    return true;
  } catch (error) {
    console.error(`[NotificationPreferences] Exception updating preferences: ${error.message}`);
    return false;
  }
}

