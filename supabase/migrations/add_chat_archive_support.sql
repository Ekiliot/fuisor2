-- ==============================================
-- Chat Archive Support Migration
-- ==============================================
-- Добавляет поддержку архивирования чатов для пользователей
-- Архивирование индивидуально для каждого участника чата

-- ==============================================
-- 1. Добавление поля is_archived в chat_participants
-- ==============================================

ALTER TABLE chat_participants 
ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE;

-- ==============================================
-- 2. Создание индекса для быстрого поиска
-- ==============================================

CREATE INDEX IF NOT EXISTS idx_chat_participants_is_archived 
ON chat_participants(user_id, is_archived) 
WHERE is_archived = TRUE;

-- ==============================================
-- 3. Комментарий к полю
-- ==============================================

COMMENT ON COLUMN chat_participants.is_archived IS 'Whether this participant has archived the chat (individual per user)';

