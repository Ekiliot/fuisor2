-- Add support for voice messages and media in DM
-- Add columns to messages table for media support

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'voice', 'image', 'video', 'file')),
ADD COLUMN IF NOT EXISTS media_url TEXT,
ADD COLUMN IF NOT EXISTS media_duration INTEGER, -- Duration in seconds for voice/video
ADD COLUMN IF NOT EXISTS media_size INTEGER; -- File size in bytes

-- Create index for faster media queries
CREATE INDEX IF NOT EXISTS idx_messages_media_url ON messages(media_url) WHERE media_url IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(message_type);

-- Update RLS policies to handle media messages
-- (existing policies should already cover this, but let's ensure they work with new columns)

COMMENT ON COLUMN messages.message_type IS 'Type of message: text, voice, image, video, file';
COMMENT ON COLUMN messages.media_url IS 'URL to media file in storage bucket';
COMMENT ON COLUMN messages.media_duration IS 'Duration in seconds for audio/video messages';
COMMENT ON COLUMN messages.media_size IS 'File size in bytes';

