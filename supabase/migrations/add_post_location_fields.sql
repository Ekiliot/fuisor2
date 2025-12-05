-- Добавляем поля для локации постов
ALTER TABLE posts ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS district TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS street TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS country TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS location_visibility TEXT;

-- Индекс для поиска по городу
CREATE INDEX IF NOT EXISTS idx_posts_city ON posts(city);

