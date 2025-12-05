-- Проверка соавторов для поста
-- Замените '5bad2462-d6a1-4644-abe6-6f4f8c59994c' на ID вашего поста

-- 1. Проверить, есть ли запись в post_coauthors
SELECT 
  pc.*,
  p.caption as post_caption,
  author.username as author_username,
  coauthor.username as coauthor_username,
  coauthor.name as coauthor_name
FROM post_coauthors pc
JOIN posts p ON pc.post_id = p.id
JOIN profiles author ON p.user_id = author.id
JOIN profiles coauthor ON pc.coauthor_user_id = coauthor.id
WHERE pc.post_id = '5bad2462-d6a1-4644-abe6-6f4f8c59994c';

-- 2. Проверить все посты с соавторами
SELECT 
  p.id as post_id,
  p.caption,
  author.username as author,
  coauthor.username as coauthor,
  coauthor.name as coauthor_name,
  coauthor.avatar_url as coauthor_avatar,
  pc.created_at as coauthor_added_at
FROM posts p
LEFT JOIN post_coauthors pc ON p.id = pc.post_id
LEFT JOIN profiles author ON p.user_id = author.id
LEFT JOIN profiles coauthor ON pc.coauthor_user_id = coauthor.id
WHERE pc.coauthor_user_id IS NOT NULL
ORDER BY p.created_at DESC;

-- 3. Проверить конкретный пост с JOIN (как в API)
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

