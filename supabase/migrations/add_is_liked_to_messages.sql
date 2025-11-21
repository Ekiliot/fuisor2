-- Добавить поле is_liked в таблицу messages
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS is_liked BOOLEAN DEFAULT FALSE;

