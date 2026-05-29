-- Migration: Add news categories and subcategories tables
-- Creates structure for organizing news by categories and subcategories

-- Create news_categories table
CREATE TABLE IF NOT EXISTS news_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_en TEXT NOT NULL,
  name_ru TEXT NOT NULL,
  icon TEXT,
  order_index INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create news_subcategories table
CREATE TABLE IF NOT EXISTS news_subcategories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL REFERENCES news_categories(id) ON DELETE CASCADE,
  name_en TEXT NOT NULL,
  name_ru TEXT NOT NULL,
  order_index INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_news_subcategories_category_id ON news_subcategories(category_id);
CREATE INDEX IF NOT EXISTS idx_news_categories_order ON news_categories(order_index);

-- Insert main categories
INSERT INTO news_categories (name_en, name_ru, icon, order_index) VALUES
  ('Politics & Society', 'Политика и Общество', '🌍', 1),
  ('Economy & Finance', 'Экономика и Финансы', '💰', 2),
  ('Science & Technology', 'Наука и Технологии', '🚀', 3),
  ('Digital World & Media', 'Цифровой мир и Медиа', '💻', 4),
  ('Sports', 'Спорт', '⚽', 5),
  ('Culture & Arts', 'Культура и Искусство', '🎨', 6),
  ('Travel & Lifestyle', 'Путешествия и Стиль жизни', '🗺️', 7),
  ('Incidents', 'Происшествия', '🚨', 8),
  ('Opinions & Analytics', 'Мнения и Аналитика', '💡', 9)
ON CONFLICT DO NOTHING;

-- Get category IDs for subcategories (using CTE)
WITH category_ids AS (
  SELECT id, name_en FROM news_categories
)
-- Insert subcategories for Politics & Society
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Politics & Society'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('Global Relations', 'Международные отношения', 1),
  ('Domestic Politics', 'Внутренняя политика', 2),
  ('Law & Legislation', 'Право и Законодательство', 3),
  ('Social Issues', 'Социальные вопросы', 4),
  ('Elections & Voting', 'Выборы и Голосование', 5),
  ('Human Rights', 'Права человека', 6),
  ('Education', 'Образование', 7),
  ('Healthcare System', 'Здравоохранение', 8)
) AS sub(name_en, name_ru, order_index);

-- Insert subcategories for Economy & Finance
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Economy & Finance'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('Global Economy', 'Мировая экономика', 1),
  ('Markets & Stock Exchanges', 'Рынки и Биржи', 2),
  ('Personal Finance', 'Личные финансы', 3),
  ('Business & Corporations', 'Бизнес и Корпорации', 4),
  ('Real Estate', 'Недвижимость', 5),
  ('Labor and Employment', 'Труд и Занятость', 6),
  ('Taxes and Budget', 'Налоги и Бюджет', 7),
  ('Cryptocurrencies', 'Криптовалюты', 8)
) AS sub(name_en, name_ru, order_index);

-- Insert subcategories for Science & Technology
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Science & Technology'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('Fundamental Research', 'Фундаментальные исследования', 1),
  ('Space and Astronomy', 'Космос и Астрономия', 2),
  ('Medicine and Biotechnology', 'Медицина и Биотехнологии', 3),
  ('IT & Gadgets', 'IT и Гаджеты', 4),
  ('Ecology and Climate', 'Экология и Климат', 5),
  ('AI and Robotics', 'Искусственный интеллект (ИИ) и Робототехника', 6),
  ('Developments and Discoveries', 'Разработки и Открытия', 7),
  ('Military Technology', 'Военные технологии', 8),
  ('Energy and Alternative Sources', 'Энергетика и Альтернативные источники', 9),
  ('Archaeology and Paleontology', 'Археология и Палеонтология', 10)
) AS sub(name_en, name_ru, order_index);

-- Insert subcategories for Digital World & Media
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Digital World & Media'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('Internet and Infrastructure', 'Интернет и Инфраструктура', 1),
  ('Software and Applications', 'Программное обеспечение и Приложения', 2),
  ('Cybersecurity', 'Кибербезопасность', 3),
  ('Gaming and Video Game Industry', 'Гейминг и Индустрия Видеоигр', 4),
  ('Social Networks and Communications', 'Социальные сети и Коммуникации', 5),
  ('Streaming Services', 'Стриминговые сервисы', 6),
  ('Bloggers and Influencers', 'Блогеры и Инфлюенсеры', 7),
  ('Advertising, Marketing, and PR Online', 'Реклама, Маркетинг и PR в Сети', 8),
  ('Regulation and Digital Law', 'Регулирование и Цифровое право', 9),
  ('Development and Code', 'Разработка и Код', 10),
  ('Metaverses and VR/AR', 'Метавселенные и VR/AR', 11),
  ('Blockchain and NFT', 'Блокчейн и NFT', 12)
) AS sub(name_en, name_ru, order_index);

-- Insert subcategories for Sports
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Sports'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('Football/Soccer', 'Футбол', 1),
  ('Basketball', 'Баскетбол', 2),
  ('Hockey', 'Хоккей', 3),
  ('Olympic Games', 'Олимпийские игры', 4),
  ('Esports', 'Киберспорт', 5),
  ('Motorsports', 'Автоспорт', 6),
  ('Sports Management', 'Спортивный менеджмент', 7),
  ('Fitness and Healthy Lifestyle', 'Фитнес и ЗОЖ', 8)
) AS sub(name_en, name_ru, order_index);

-- Insert subcategories for Culture & Arts
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Culture & Arts'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('Cinema & TV Series', 'Кино и Сериалы', 1),
  ('Music', 'Музыка', 2),
  ('Literature', 'Литература', 3),
  ('Theatre & Ballet', 'Театр и Балет', 4),
  ('Exhibitions & Museums', 'Выставки и Музеи', 5),
  ('Fashion and Design', 'Мода и Дизайн', 6),
  ('History and Archaeology', 'История и Археология', 7)
) AS sub(name_en, name_ru, order_index);

-- Insert subcategories for Travel & Lifestyle
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Travel & Lifestyle'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('International Tourism', 'Международный туризм', 1),
  ('Domestic Tourism', 'Внутренний туризм', 2),
  ('Destination Reviews and Guides', 'Обзоры мест и Гиды', 3),
  ('Culinary and Gastronomy', 'Кулинария и Гастрономия', 4),
  ('Home, Interior, and Design', 'Дом, Интерьер и Дизайн', 5),
  ('Family and Relationships', 'Семья и Отношения', 6),
  ('Automobiles and Transport', 'Автомобили и Транспорт', 7),
  ('Fashion and Beauty', 'Мода и Красота', 8),
  ('Hobbies and Leisure', 'Хобби и Досуг', 9),
  ('Eco-Friendly Lifestyle', 'Экологичный образ жизни', 10)
) AS sub(name_en, name_ru, order_index);

-- Insert subcategories for Incidents
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Incidents'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('Crime', 'Криминал', 1),
  ('Natural Disasters', 'Стихийные бедствия', 2),
  ('Accidents & Catastrophes', 'Аварии и Катастрофы', 3),
  ('Investigations', 'Расследования', 4),
  ('Emergency Situations', 'Чрезвычайные ситуации', 5)
) AS sub(name_en, name_ru, order_index);

-- Insert subcategories for Opinions & Analytics
INSERT INTO news_subcategories (category_id, name_en, name_ru, order_index)
SELECT 
  (SELECT id FROM category_ids WHERE name_en = 'Opinions & Analytics'),
  sub.name_en,
  sub.name_ru,
  sub.order_index
FROM (VALUES
  ('Columns and Blogs', 'Колонки и Блоги', 1),
  ('Interviews with Experts', 'Интервью с экспертами', 2),
  ('Reviews and Critiques', 'Обзоры и Рецензии', 3),
  ('In-Depth Event Analysis', 'Глубокий анализ событий', 4),
  ('Forecasts and Trends', 'Прогнозы и Тренды', 5),
  ('Reader''s Letters', 'Читательские письма', 6),
  ('Controversy and Discussions', 'Полемика и Дискуссии', 7),
  ('Historical Parallels', 'Исторические параллели', 8)
) AS sub(name_en, name_ru, order_index);

-- Enable RLS
ALTER TABLE news_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE news_subcategories ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Public read access
CREATE POLICY "Anyone can view news categories"
  ON news_categories FOR SELECT
  USING (true);

CREATE POLICY "Anyone can view news subcategories"
  ON news_subcategories FOR SELECT
  USING (true);

