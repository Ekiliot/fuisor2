-- Migration: Fix RLS policy to show deleted messages to all users
-- Problem: Currently deleted messages are hidden from the user who deleted them
-- Solution: Show all messages (including deleted) to all participants, let frontend handle display

-- Drop the existing policy
DROP POLICY IF EXISTS "Users can view messages from own chats." ON messages;

-- Create new policy that shows all messages (including deleted ones) to all participants
-- Frontend will handle showing "deleted" status appropriately
CREATE POLICY "Users can view messages from own chats."
  ON messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = messages.chat_id 
      AND chat_participants.user_id = auth.uid()
    )
  );

-- Note: The previous policy was filtering out messages where the user was in deleted_by_ids
-- Now all messages are visible, and the frontend will show appropriate "deleted" text
-- based on deleted_at and deleted_by_ids fields

