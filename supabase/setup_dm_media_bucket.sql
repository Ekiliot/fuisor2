-- Create bucket for DM media (voice messages, images, videos, etc.)
INSERT INTO storage.buckets (id, name, public)
VALUES ('dm_media', 'dm_media', false)
ON CONFLICT (id) DO NOTHING;

-- RLS Policy: Users can upload to dm_media (files in their own folder)
CREATE POLICY "Users can upload their own DM media" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'dm_media' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

-- RLS Policy: Users can read DM media if they are participants in any chat
-- (Simplified: check if user is in chat_participants for the chat in path)
CREATE POLICY "Users can read DM media from their chats" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'dm_media' AND
  EXISTS (
    SELECT 1 FROM chat_participants cp
    WHERE cp.user_id = auth.uid()
    AND cp.chat_id::text = (storage.foldername(name))[2]
  )
);

-- RLS Policy: Users can delete their own DM media
CREATE POLICY "Users can delete their own DM media" ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'dm_media' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

