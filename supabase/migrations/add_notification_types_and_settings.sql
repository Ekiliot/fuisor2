-- Migration: Add new notification types and notification settings table
-- This migration adds:
-- 1. New notification types: 'new_post', 'new_story', 'comment_reply', 'comment_mention'
-- 2. Table for comment mentions
-- 3. Table for notification preferences per user

-- Step 1: Update notifications table to allow new types
-- Remove the old constraint and add a new one with all notification types
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications ADD CONSTRAINT notifications_type_check 
  CHECK (type IN (
    'like', 
    'comment', 
    'comment_like', 
    'comment_reply',
    'comment_mention',
    'follow', 
    'mention',
    'new_post',
    'new_story'
  ));

-- Step 2: Create comment mentions table (for mentions in comments)
CREATE TABLE IF NOT EXISTS comment_mentions (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
  mentioned_user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(comment_id, mentioned_user_id)
);

-- Enable RLS on comment_mentions
ALTER TABLE comment_mentions ENABLE ROW LEVEL SECURITY;

-- Comment mentions policies
CREATE POLICY "Comment mentions are viewable by everyone."
  ON comment_mentions FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can create comment mentions."
  ON comment_mentions FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can delete mentions from their comments."
  ON comment_mentions FOR DELETE
  USING ( auth.uid() IN (
    SELECT user_id FROM comments WHERE id = comment_id
  ));

-- Create index for comment mentions
CREATE INDEX IF NOT EXISTS idx_comment_mentions_comment_id ON comment_mentions(comment_id);
CREATE INDEX IF NOT EXISTS idx_comment_mentions_mentioned_user_id ON comment_mentions(mentioned_user_id);

-- Step 3: Create notification preferences table
CREATE TABLE IF NOT EXISTS notification_preferences (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE UNIQUE NOT NULL,
  -- Notification type preferences (default true for all)
  mention_enabled BOOLEAN DEFAULT TRUE,
  comment_mention_enabled BOOLEAN DEFAULT TRUE,
  new_post_enabled BOOLEAN DEFAULT TRUE,
  new_story_enabled BOOLEAN DEFAULT TRUE,
  follow_enabled BOOLEAN DEFAULT TRUE,
  like_enabled BOOLEAN DEFAULT TRUE,
  comment_enabled BOOLEAN DEFAULT TRUE,
  comment_reply_enabled BOOLEAN DEFAULT TRUE,
  comment_like_enabled BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on notification_preferences
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- Notification preferences policies
CREATE POLICY "Users can view own notification preferences."
  ON notification_preferences FOR SELECT
  USING ( auth.uid() = user_id );

CREATE POLICY "Users can insert own notification preferences."
  ON notification_preferences FOR INSERT
  WITH CHECK ( auth.uid() = user_id );

CREATE POLICY "Users can update own notification preferences."
  ON notification_preferences FOR UPDATE
  USING ( auth.uid() = user_id );

-- Create index for notification preferences
CREATE INDEX IF NOT EXISTS idx_notification_preferences_user_id ON notification_preferences(user_id);

-- Step 4: Create function to automatically create default preferences for new users
CREATE OR REPLACE FUNCTION create_default_notification_preferences()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO notification_preferences (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically create preferences when a profile is created
DROP TRIGGER IF EXISTS on_profile_create_notification_prefs ON profiles;
CREATE TRIGGER on_profile_create_notification_prefs
  AFTER INSERT ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION create_default_notification_preferences();

-- Step 5: Create default preferences for existing users
INSERT INTO notification_preferences (user_id)
SELECT id FROM profiles
ON CONFLICT (user_id) DO NOTHING;

-- Add comment for documentation
COMMENT ON TABLE notification_preferences IS 'User preferences for different types of notifications';
COMMENT ON TABLE comment_mentions IS 'User mentions in comments (e.g., @username)';

