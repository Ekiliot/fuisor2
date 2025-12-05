# Отладка проблемы с соавтором

## Проблема
Соавтор не отображается в посте `5bad2462-d6a1-4644-abe6-6f4f8c59994c`

## Шаги для проверки

### 1. Проверить, есть ли запись в post_coauthors

Выполните в Supabase SQL Editor:

```sql
SELECT * FROM post_coauthors 
WHERE post_id = '5bad2462-d6a1-4644-abe6-6f4f8c59994c';
```

**Если записей нет:**
- Соавтор не был добавлен при создании поста
- Нужно добавить соавтора через редактирование поста

**Если запись есть:**
- Проверьте следующий шаг

### 2. Проверить JOIN запрос (как в API)

```sql
SELECT 
  p.*,
  json_build_object(
    'username', author.username,
    'name', author.name,
    'avatar_url', author.avatar_url
  ) as profiles,
  (
    SELECT json_agg(
      json_build_object(
        'coauthor', json_build_object(
          'id', coauthor.id,
          'username', coauthor.username,
          'name', coauthor.name,
          'avatar_url', coauthor.avatar_url
        )
      )
    )
    FROM post_coauthors pc2
    JOIN profiles coauthor ON pc2.coauthor_user_id = coauthor.id
    WHERE pc2.post_id = p.id
  ) as post_coauthors
FROM posts p
JOIN profiles author ON p.user_id = author.id
WHERE p.id = '5bad2462-d6a1-4644-abe6-6f4f8c59994c';
```

Проверьте поле `post_coauthors` - должно быть не null и содержать данные соавтора.

### 3. Проверить логи в backend

В логах сервера должны быть записи:
```
TransformPostWithCoauthor: Found coauthor data
```

Если их нет - JOIN не работает или запись отсутствует.

### 4. Проверить логи в Flutter

В консоли Flutter должны быть записи:
```
Post.fromJson DEBUG for post 5bad2462-d6a1-4644-abe6-6f4f8c59994c:
  - coauthor field: ...
  - post_coauthors field: ...
```

### 5. Если запись отсутствует - добавить соавтора

1. Откройте пост
2. Нажмите на три точки (⋮)
3. Выберите "Edit"
4. Добавьте соавтора через поиск
5. Сохраните

### 6. Проверить структуру данных от Supabase

Возможно, Supabase возвращает данные в другом формате. Проверьте в логах backend структуру `post_coauthors`.

## Возможные проблемы

1. **Запись отсутствует в post_coauthors**
   - Решение: добавить через редактирование поста

2. **Неправильная структура JOIN**
   - Проверить формат ответа от Supabase
   - Возможно, нужно изменить `transformPostWithCoauthor`

3. **Проблема с парсингом в Flutter**
   - Проверить логи в Flutter
   - Убедиться, что `json['coauthor']` не null

## Быстрое решение

Если нужно быстро добавить соавтора вручную:

```sql
-- Замените 'USER_ID_COAUTHOR' на ID пользователя-соавтора
INSERT INTO post_coauthors (post_id, coauthor_user_id)
VALUES ('5bad2462-d6a1-4644-abe6-6f4f8c59994c', 'USER_ID_COAUTHOR')
ON CONFLICT (post_id) DO UPDATE 
SET coauthor_user_id = EXCLUDED.coauthor_user_id;
```

