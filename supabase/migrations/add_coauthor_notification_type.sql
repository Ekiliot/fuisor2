-- Migration: Add 'coauthor' notification type
-- Allows notifications when user is tagged as coauthor

-- Drop the existing check constraint
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Add the new check constraint with 'coauthor' type
-- Including all existing types from previous migrations
ALTER TABLE notifications 
ADD CONSTRAINT notifications_type_check 
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
  'coauthor'
));

-- Add comment
COMMENT ON COLUMN notifications.type IS 'Type of notification: like, comment, comment_like, comment_reply, comment_mention, follow, mention, new_post, new_story, coauthor';

