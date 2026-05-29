-- Migration: Add news notification types
-- Adds 'news_like' and 'news_comment' to notification types

-- Update notifications table constraint to include news notification types
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
    'new_story',
    'news_like',
    'news_comment'
  ));

-- Add news_id column to notifications table if it doesn't exist
ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS news_id UUID REFERENCES news(id) ON DELETE CASCADE;

-- Create index for news_id
CREATE INDEX IF NOT EXISTS idx_notifications_news_id ON notifications(news_id) WHERE news_id IS NOT NULL;

-- Add news notification preferences to notification_preferences table
ALTER TABLE notification_preferences 
ADD COLUMN IF NOT EXISTS news_like_enabled BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS news_comment_enabled BOOLEAN DEFAULT TRUE;

-- Update existing users to have news notification preferences enabled by default
UPDATE notification_preferences 
SET news_like_enabled = TRUE, news_comment_enabled = TRUE
WHERE news_like_enabled IS NULL OR news_comment_enabled IS NULL;

