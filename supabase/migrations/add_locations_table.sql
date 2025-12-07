-- Создаем таблицу для хранения уникальных локаций из постов
CREATE TABLE IF NOT EXISTS locations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  country VARCHAR(100) NOT NULL,
  city VARCHAR(100),
  district VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  post_count INTEGER DEFAULT 1,
  
  -- Уникальность по комбинации страна-город-район
  UNIQUE(country, city, district)
);

-- Индексы для быстрого поиска
CREATE INDEX idx_locations_country ON locations(country);
CREATE INDEX idx_locations_city ON locations(city);
CREATE INDEX idx_locations_district ON locations(district);
CREATE INDEX idx_locations_post_count ON locations(post_count DESC);

-- RLS политики
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;

-- Все могут читать локации
CREATE POLICY "Locations are viewable by everyone"
  ON locations FOR SELECT
  USING (true);

-- Только сервер может добавлять/обновлять локации (через service role)
CREATE POLICY "Locations can be inserted by service role"
  ON locations FOR INSERT
  WITH CHECK (false); -- Блокируем для обычных пользователей

CREATE POLICY "Locations can be updated by service role"
  ON locations FOR UPDATE
  USING (false); -- Блокируем для обычных пользователей

-- Функция для автоматического обновления updated_at
CREATE OR REPLACE FUNCTION update_locations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_locations_updated_at_trigger
  BEFORE UPDATE ON locations
  FOR EACH ROW
  EXECUTE FUNCTION update_locations_updated_at();

-- Заполняем начальными данными из существующих постов
INSERT INTO locations (country, city, district, post_count)
SELECT 
  country,
  city,
  district,
  COUNT(*) as post_count
FROM posts
WHERE country IS NOT NULL
GROUP BY country, city, district
ON CONFLICT (country, city, district) DO NOTHING;

