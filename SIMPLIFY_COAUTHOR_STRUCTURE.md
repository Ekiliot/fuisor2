# Упрощение структуры соавторов

## Проблема
Использование отдельной таблицы `post_coauthors` было избыточным, так как у нас может быть только **один соавтор на пост**.

## Решение
Добавлена колонка `coauthor_user_id` напрямую в таблицу `posts`.

## Преимущества

1. **Простота** - одна таблица вместо двух
2. **Производительность** - меньше JOIN запросов
3. **Читаемость** - проще понять структуру данных
4. **Меньше кода** - не нужны отдельные запросы к `post_coauthors`

## Миграция

### Файл: `supabase/migrations/add_coauthor_to_posts.sql`

```sql
-- Добавляем колонку coauthor_user_id в posts
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS coauthor_user_id UUID REFERENCES profiles(id) ON DELETE SET NULL;

-- Мигрируем данные из post_coauthors в posts
UPDATE posts p
SET coauthor_user_id = (
  SELECT pc.coauthor_user_id 
  FROM post_coauthors pc 
  WHERE pc.post_id = p.id 
  LIMIT 1
)
WHERE EXISTS (
  SELECT 1 FROM post_coauthors pc WHERE pc.post_id = p.id
);

-- Создаем индекс
CREATE INDEX IF NOT EXISTS idx_posts_coauthor_user_id 
ON posts(coauthor_user_id) WHERE coauthor_user_id IS NOT NULL;
```

## Изменения в Backend

### 1. Создание поста (`POST /api/posts`)

**Было:**
- Создавался пост
- Отдельно вставлялась запись в `post_coauthors`

**Стало:**
- `coauthor_user_id` устанавливается напрямую при создании поста
- JOIN с `profiles` через `coauthor_user_id` для получения данных соавтора

### 2. Получение постов

**Было:**
```sql
SELECT *,
  post_coauthors!left (
    profiles:coauthor_user_id (...)
  )
FROM posts
```

**Стало:**
```sql
SELECT *,
  coauthor:coauthor_user_id (id, username, name, avatar_url)
FROM posts
```

### 3. Обновление поста (`PUT /api/posts/:id`)

**Было:**
- Удаление из `post_coauthors`
- Вставка новой записи в `post_coauthors`
- Отдельный запрос для получения соавтора

**Стало:**
- Просто обновление `coauthor_user_id` в `posts`
- JOIN автоматически возвращает данные соавтора

## Обновленные Endpoints

1. ✅ `GET /api/posts` - получение всех постов
2. ✅ `GET /api/posts/feed` - лента постов
3. ✅ `POST /api/posts` - создание поста
4. ✅ `PUT /api/posts/:id` - обновление поста
5. ✅ `GET /api/users/:id/posts` - посты пользователя

## Удаленный код

- ❌ Функция `transformPostWithCoauthor()` - больше не нужна
- ❌ Отдельные запросы к `post_coauthors`
- ❌ Сложная логика объединения данных

## Структура данных

### До:
```
posts
  └── post_coauthors (отдельная таблица)
      └── coauthor_user_id → profiles
```

### После:
```
posts
  └── coauthor_user_id → profiles (прямая связь)
```

## Примечания

1. **Таблица `post_coauthors`** оставлена для обратной совместимости
   - Можно удалить после проверки, что все работает
   - Данные уже мигрированы в `posts.coauthor_user_id`

2. **Ограничение "один соавтор"** теперь обеспечивается на уровне структуры
   - Одна колонка = один соавтор
   - Не нужны уникальные ограничения на промежуточной таблице

3. **Производительность**
   - Меньше JOIN запросов
   - Проще индексы
   - Быстрее запросы

## Тестирование

После применения миграции проверьте:

1. ✅ Посты с соавторами отображаются правильно
2. ✅ Создание поста с соавтором работает
3. ✅ Обновление соавтора работает
4. ✅ Удаление соавтора работает (установка `coauthor_user_id = null`)

## Откат (если нужно)

Если что-то пойдет не так, можно вернуться к старой структуре:

```sql
-- Вернуть данные в post_coauthors
INSERT INTO post_coauthors (post_id, coauthor_user_id)
SELECT id, coauthor_user_id 
FROM posts 
WHERE coauthor_user_id IS NOT NULL
ON CONFLICT DO NOTHING;
```

Но это не должно понадобиться, так как новая структура проще и надежнее!

