-- Добавляем поля для отслеживания онлайн статуса
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS last_seen TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS show_online_status BOOLEAN DEFAULT TRUE;

-- Индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_profiles_is_online ON profiles(is_online) WHERE is_online = TRUE;
CREATE INDEX IF NOT EXISTS idx_profiles_last_seen ON profiles(last_seen DESC);

-- Комментарии
COMMENT ON COLUMN profiles.last_seen IS 'Время последней активности пользователя';
COMMENT ON COLUMN profiles.is_online IS 'Флаг онлайн статуса (обновляется каждые 30 секунд)';
COMMENT ON COLUMN profiles.show_online_status IS 'Настройка приватности: показывать ли время захода';

