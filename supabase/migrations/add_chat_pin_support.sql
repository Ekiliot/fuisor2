-- Добавление поддержки закрепления чатов
-- Добавляем поле is_pinned в таблицу chat_participants

ALTER TABLE chat_participants
ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT FALSE;

-- Создаем индекс для быстрого поиска закрепленных чатов
CREATE INDEX IF NOT EXISTS idx_chat_participants_is_pinned ON chat_participants(is_pinned);

-- Обновление политики RLS для chat_participants, чтобы разрешить обновление is_pinned
-- Политика уже должна существовать, но убедимся что она позволяет обновлять is_pinned
-- (обычно политика "Users can update own participant records" уже покрывает это)

