-- Migration: Add 'coauthor' notification type
-- Allows notifications when user is tagged as coauthor

-- Drop the existing check constraint
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Add the new check constraint with 'coauthor' type
ALTER TABLE notifications 
ADD CONSTRAINT notifications_type_check 
CHECK (type IN ('like', 'comment', 'comment_like', 'follow', 'mention', 'coauthor'));

-- Add comment
COMMENT ON COLUMN notifications.type IS 'Type of notification: like, comment, comment_like, follow, mention, coauthor';

