-- Add support for reply to messages
-- Add reply_to_id column to messages table

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL;

-- Create index for faster reply lookups
CREATE INDEX IF NOT EXISTS idx_messages_reply_to_id ON messages(reply_to_id) WHERE reply_to_id IS NOT NULL;

COMMENT ON COLUMN messages.reply_to_id IS 'ID of the message this message is replying to';

