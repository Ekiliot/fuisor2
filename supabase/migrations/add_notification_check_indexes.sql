-- ==============================================
-- Optimization Indexes for Notification Check Endpoint
-- ==============================================
-- Creates composite indexes to optimize the /api/notifications/check endpoint
-- which queries posts and stories by user_id and created_at

-- ==============================================
-- 1. Index for posts from following (non-stories)
-- ==============================================
-- Optimizes queries that fetch recent posts from followed users
-- WHERE expires_at IS NULL (not stories)
-- ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_posts_user_id_created_at_no_stories
  ON posts(user_id, created_at DESC)
  WHERE expires_at IS NULL;

-- ==============================================
-- 2. Index for stories from following
-- ==============================================
-- Optimizes queries that fetch recent stories from followed users
-- WHERE expires_at IS NOT NULL (only stories)
-- AND expires_at > NOW() (not expired)
-- ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_posts_user_id_stories_expires_at
  ON posts(user_id, expires_at DESC, created_at DESC)
  WHERE expires_at IS NOT NULL;

-- ==============================================
-- 3. Index for messages by chat and creation time
-- ==============================================
-- Optimizes fetching the last message for each chat
CREATE INDEX IF NOT EXISTS idx_messages_chat_id_created_at
  ON messages(chat_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- ==============================================
-- 4. Index for notifications by user and read status
-- ==============================================
-- This index might already exist, but we ensure it's optimal
-- for queries filtering by is_read = false
DROP INDEX IF EXISTS idx_notifications_is_read;
CREATE INDEX IF NOT EXISTS idx_notifications_user_id_unread_created_at
  ON notifications(user_id, created_at DESC)
  WHERE is_read = false;

-- ==============================================
-- 5. Comments
-- ==============================================
COMMENT ON INDEX idx_posts_user_id_created_at_no_stories IS 
  'Optimizes fetching recent posts from followed users for background notification checks';

COMMENT ON INDEX idx_posts_user_id_stories_expires_at IS 
  'Optimizes fetching active stories from followed users for background notification checks';

COMMENT ON INDEX idx_messages_chat_id_created_at IS 
  'Optimizes fetching the last message for each chat';

COMMENT ON INDEX idx_notifications_user_id_unread_created_at IS 
  'Optimizes fetching unread notifications ordered by creation time';

