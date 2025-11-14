-- ==============================================
-- Изменение таблицы messages для поддержки голосовых сообщений
-- ==============================================
-- Делаем поле content nullable, т.к. голосовые сообщения
-- не имеют текстового содержимого

-- Изменяем ограничение NOT NULL на content
ALTER TABLE messages 
ALTER COLUMN content DROP NOT NULL;

-- Проверяем, что либо content, либо media_url должны быть заполнены
ALTER TABLE messages
ADD CONSTRAINT messages_content_or_media_check 
CHECK (
  (content IS NOT NULL AND content != '') OR 
  (media_url IS NOT NULL AND media_url != '')
);

-- Комментарий для документации
COMMENT ON COLUMN messages.content IS 'Text content of the message. Can be NULL for voice/media messages.';
COMMENT ON CONSTRAINT messages_content_or_media_check ON messages IS 'Ensures either text content or media URL is present';

