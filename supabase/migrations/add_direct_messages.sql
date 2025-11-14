-- ==============================================
-- Direct Messages System Migration
-- ==============================================
-- Создает таблицы для системы прямых сообщений
-- с полной поддержкой безопасности через RLS

-- ==============================================
-- 1. Создание таблиц
-- ==============================================

-- Таблица чатов
CREATE TABLE IF NOT EXISTS chats (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type TEXT DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Таблица участников чата
CREATE TABLE IF NOT EXISTS chat_participants (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    unread_count INTEGER DEFAULT 0,
    last_read_at TIMESTAMPTZ,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Таблица сообщений
CREATE TABLE IF NOT EXISTS messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    deleted_by_ids UUID[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================
-- 2. Создание индексов
-- ==============================================

-- Индексы для chats
CREATE INDEX IF NOT EXISTS idx_chats_updated_at ON chats(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_chats_type ON chats(type) WHERE type = 'direct';

-- Индексы для chat_participants
CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_chat_id ON chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_unread_count ON chat_participants(unread_count) WHERE unread_count > 0;

-- Индексы для messages
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_is_read ON messages(is_read);
CREATE INDEX IF NOT EXISTS idx_messages_deleted_at ON messages(deleted_at) WHERE deleted_at IS NOT NULL;

-- ==============================================
-- 3. Включение Row Level Security (RLS)
-- ==============================================

ALTER TABLE chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- ==============================================
-- 4. RLS Политики для chats
-- ==============================================

-- SELECT: Пользователь видит чат ТОЛЬКО если он участник
CREATE POLICY "Users can view own chats."
  ON chats FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = chats.id 
      AND chat_participants.user_id = auth.uid()
    )
  );

-- INSERT: Авторизованный пользователь может создать чат
CREATE POLICY "Authenticated users can create chats."
  ON chats FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- UPDATE: Пользователь может обновить чат ТОЛЬКО если он участник
CREATE POLICY "Users can update own chats."
  ON chats FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = chats.id 
      AND chat_participants.user_id = auth.uid()
    )
  );

-- DELETE: Пользователь может удалить чат ТОЛЬКО если он участник
CREATE POLICY "Users can delete own chats."
  ON chats FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = chats.id 
      AND chat_participants.user_id = auth.uid()
    )
  );

-- ==============================================
-- 5. RLS Политики для chat_participants
-- ==============================================

-- SELECT: Пользователь видит участников ТОЛЬКО в своих чатах
CREATE POLICY "Users can view participants in own chats."
  ON chat_participants FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants cp2
      WHERE cp2.chat_id = chat_participants.chat_id 
      AND cp2.user_id = auth.uid()
    )
  );

-- INSERT: Пользователь может добавить себя в чат
CREATE POLICY "Authenticated users can be added to chats."
  ON chat_participants FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated' AND
    auth.uid() = user_id
  );

-- UPDATE: Пользователь может обновить свои записи участия
CREATE POLICY "Users can update own participant records."
  ON chat_participants FOR UPDATE
  USING (auth.uid() = user_id);

-- DELETE: Только через каскадное удаление чата или через API с проверками
-- (обычно не нужно удалять напрямую, но если нужно - через API)

-- ==============================================
-- 6. RLS Политики для messages
-- ==============================================

-- SELECT: Пользователь видит сообщения ТОЛЬКО из своих чатов
-- + фильтрация soft delete (не показываем сообщения, которые пользователь удалил)
CREATE POLICY "Users can view messages from own chats."
  ON messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = messages.chat_id 
      AND chat_participants.user_id = auth.uid()
    )
    AND (
      deleted_at IS NULL OR 
      (deleted_at IS NOT NULL AND auth.uid() != ALL(deleted_by_ids))
    )
  );

-- INSERT: Пользователь может отправить сообщение ТОЛЬКО в свой чат
CREATE POLICY "Users can send messages to own chats."
  ON messages FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated' AND
    auth.uid() = sender_id AND
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = messages.chat_id 
      AND chat_participants.user_id = auth.uid()
    )
  );

-- UPDATE: Пользователь может обновить ТОЛЬКО свои сообщения
CREATE POLICY "Users can update own messages."
  ON messages FOR UPDATE
  USING (auth.uid() = sender_id);

-- DELETE: Пользователь может удалить ТОЛЬКО свои сообщения
CREATE POLICY "Users can delete own messages."
  ON messages FOR DELETE
  USING (auth.uid() = sender_id);

-- ==============================================
-- 7. PostgreSQL функции и триггеры
-- ==============================================

-- Функция: Обновление updated_at в чате при новом сообщении
CREATE OR REPLACE FUNCTION update_chat_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE chats 
  SET updated_at = NEW.created_at 
  WHERE id = NEW.chat_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер: Автоматическое обновление updated_at
CREATE TRIGGER messages_update_chat_timestamp
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_chat_updated_at();

-- Функция: Увеличить счётчик непрочитанных для получателей
CREATE OR REPLACE FUNCTION increment_unread_count()
RETURNS TRIGGER AS $$
BEGIN
  -- Увеличиваем счётчик для всех участников кроме отправителя
  UPDATE chat_participants
  SET unread_count = unread_count + 1
  WHERE chat_id = NEW.chat_id 
    AND user_id != NEW.sender_id
    AND (last_read_at IS NULL OR last_read_at < NEW.created_at);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер: Автоматическое увеличение счётчика непрочитанных
CREATE TRIGGER messages_increment_unread
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION increment_unread_count();

-- Функция: Сброс счётчика при прочтении (опционально)
CREATE OR REPLACE FUNCTION reset_unread_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.last_read_at IS NOT NULL AND (OLD.last_read_at IS NULL OR NEW.last_read_at > OLD.last_read_at) THEN
    UPDATE chat_participants
    SET unread_count = 0
    WHERE id = NEW.id AND unread_count > 0;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер: Сброс счётчика непрочитанных при обновлении last_read_at
CREATE TRIGGER chat_participants_reset_unread
  AFTER UPDATE OF last_read_at ON chat_participants
  FOR EACH ROW
  EXECUTE FUNCTION reset_unread_count();

-- ==============================================
-- 8. Комментарии к таблицам
-- ==============================================

COMMENT ON TABLE chats IS 'Chats between users (direct or group)';
COMMENT ON TABLE chat_participants IS 'Participants in chats with unread count tracking';
COMMENT ON TABLE messages IS 'Messages in chats with soft delete support';
COMMENT ON COLUMN chat_participants.unread_count IS 'Number of unread messages for this participant';
COMMENT ON COLUMN messages.deleted_by_ids IS 'Array of user IDs who deleted this message (soft delete)';

