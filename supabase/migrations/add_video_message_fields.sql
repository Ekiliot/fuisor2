-- Migration: Add video message fields to messages table
-- Adds support for sharing Shorts videos via direct messages

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS thumbnail_url TEXT,
ADD COLUMN IF NOT EXISTS post_id UUID REFERENCES posts(id) ON DELETE SET NULL;

-- Add index for post_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_messages_post_id ON messages(post_id) WHERE post_id IS NOT NULL;

