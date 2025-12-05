# Реализация соавторов постов и внешних ссылок

## Обзор

Были реализованы две новые функции для постов:

1. **Соавторы постов** - возможность добавить одного соавтора к посту
2. **Внешние ссылки** - кастомная кнопка со ссылкой на внешний ресурс

## 1. База данных

### 1.1 Миграция для соавторов

Файл: `supabase/migrations/add_post_coauthors.sql`

- Создана таблица `post_coauthors` с полями:
  - `id` - UUID, первичный ключ
  - `post_id` - ссылка на пост
  - `coauthor_user_id` - ссылка на пользователя-соавтора
  - `created_at` - время создания
- Уникальное ограничение на `post_id` - только один соавтор на пост
- Индексы для быстрого поиска
- RLS политики для безопасности

### 1.2 Миграция для внешних ссылок

Файл: `supabase/migrations/add_post_external_link.sql`

- Добавлены поля в таблицу `posts`:
  - `external_link_url` (TEXT) - URL внешней ссылки
  - `external_link_text` (VARCHAR(8)) - текст кнопки (6-8 символов)
- Индекс для поиска постов с внешними ссылками

### 1.3 Миграция для типа уведомлений

Файл: `supabase/migrations/add_coauthor_notification_type.sql`

- Добавлен новый тип уведомления `coauthor`
- Обновлен CHECK constraint с учетом всех существующих типов:
  - `like`, `comment`, `comment_like`, `comment_reply`, `comment_mention`
  - `follow`, `mention`, `new_post`, `new_story`
  - **`coauthor`** (новый)
- Уведомление отправляется пользователю, когда его добавляют как соавтора

## 2. Backend API

### 2.1 Создание поста

Файл: `src/routes/post.routes.js`

**Новые параметры:**
- `coauthors` - массив с одним элементом (user_id или username)
  - Валидация: максимум 1 элемент
  - Автоматическое создание уведомления соавтору
- `external_link_url` - URL внешней ссылки
  - Валидация формата URL
- `external_link_text` - текст кнопки
  - Валидация длины: 6-8 символов

**Процесс:**
1. Валидация входных данных
2. Создание поста с новыми полями
3. Поиск соавтора по username/user_id
4. Создание записи в `post_coauthors`
5. Отправка уведомления соавтору (тип 'coauthor')

### 2.2 Получение постов

Обновлены endpoints:
- `GET /api/posts` - все посты
- `GET /api/posts/feed` - лента постов
- `GET /api/users/:id/posts` - посты пользователя

**Изменения:**
- LEFT JOIN с таблицей `post_coauthors` и `profiles`
- Включение данных соавтора в ответ: `{ id, username, name, avatar_url }`
- Включение полей `external_link_url` и `external_link_text`

## 3. Flutter - Модели

### 3.1 Модель Post

Файл: `fuisor_app/lib/models/user.dart`

**Новые поля:**
```dart
final User? coauthor; // Один соавтор
final String? externalLinkUrl; // URL внешней ссылки
final String? externalLinkText; // Текст кнопки (6-8 символов)
```

**Обновлены методы:**
- `fromJson` - парсинг соавтора и ссылок
- `toJson` - сериализация
- `copyWith` - копирование с новыми полями

## 4. Flutter - UI создания поста

### 4.1 Поле соавтора

Файл: `fuisor_app/lib/screens/create_post_screen.dart`

**Функционал:**
- Кнопка "Add coauthor" с иконкой
- Поиск пользователей через modal bottom sheet
- Поиск в реальном времени (минимум 2 символа)
- Отображение выбранного соавтора с аватаром
- Кнопка удаления соавтора (X)
- Ограничение: максимум 1 соавтор

**Метод поиска:**
```dart
Future<void> _showUserSearch() async
```
- Использует `ApiService.searchUsers`
- Отображает результаты в списке
- Клик на пользователя выбирает его как соавтора

### 4.2 Поля внешней ссылки

**Функционал:**
- Переключатель (Switch) для активации секции
- Поле URL с валидацией формата
- Поле текста кнопки с счетчиком символов (6-8 символов)
- Автоматическая валидация перед отправкой

**Валидация:**
- URL должен быть валидным (проверка через `Uri.tryParse`)
- Текст кнопки: 6-8 символов
- Ошибки отображаются пользователю

### 4.3 Отправка данных

**Обновлен метод `_createPost()`:**
- Добавлена валидация внешней ссылки
- Передача `coauthor` (user_id или null)
- Передача `externalLinkUrl` и `externalLinkText`

## 5. Flutter - Провайдеры и сервисы

### 5.1 PostsProvider

Файл: `fuisor_app/lib/providers/posts_provider.dart`

**Новые параметры в `createPost`:**
```dart
String? coauthor, // Coauthor user ID
String? externalLinkUrl, // External link URL
String? externalLinkText, // External link button text
```

### 5.2 ApiService

Файл: `fuisor_app/lib/services/api_service.dart`

**Обновлен метод `createPost`:**
- Добавлены новые параметры
- Формирование массива `coauthors` для API
- Отправка полей внешней ссылки

## 6. Flutter - UI отображения поста

### 6.1 Отображение соавтора

Файл: `fuisor_app/lib/widgets/post_card.dart`

**Визуальное представление:**
```
@author с @coauthor
```

**Реализация:**
- Отображается после имени автора в header
- Синий цвет (@coauthor) для выделения
- Кликабельное имя соавтора
- Переход на профиль соавтора при клике

### 6.2 Кнопка внешней ссылки

**Визуальное представление:**
- Синяя кнопка на всю ширину
- Иконка внешней ссылки слева
- Кастомный текст кнопки (или "Link" по умолчанию)
- Расположена после caption, перед комментариями

**Функционал:**
```dart
Future<void> _openExternalLink(String url) async
```
- Использует `url_launcher`
- Открывает ссылку во внешнем браузере
- Обработка ошибок с уведомлениями

## 7. Зависимости

Проверено наличие:
- ✅ `url_launcher: ^6.2.5` - уже есть в `pubspec.yaml`

## 8. Тестирование

Рекомендуется протестировать:

### 8.1 Соавторы
- [ ] Создание поста с одним соавтором
- [ ] Попытка добавить более 1 соавтора (должна быть ошибка)
- [ ] Поиск пользователей по username
- [ ] Отображение соавтора в ленте
- [ ] Клик на имя соавтора (переход на профиль)
- [ ] Удаление соавтора перед публикацией
- [ ] Уведомление соавтору

### 8.2 Внешние ссылки
- [ ] Создание поста с внешней ссылкой
- [ ] Валидация URL (невалидный URL)
- [ ] Валидация текста кнопки (менее 6 символов)
- [ ] Валидация текста кнопки (более 8 символов)
- [ ] Отображение кнопки в посте
- [ ] Открытие внешней ссылки (клик на кнопку)
- [ ] Отключение внешней ссылки (Switch OFF)

### 8.3 Интеграция
- [ ] Пост с соавтором и внешней ссылкой одновременно
- [ ] Пост без соавтора и без ссылки (стандартный пост)
- [ ] Отображение в разных секциях (лента, профиль, shorts)

## 9. Примечания

### 9.1 Ограничения
- Максимум **1 соавтор** на пост (по дизайну)
- Текст кнопки: **6-8 символов** (строгое ограничение)
- URL должен быть валидным (проверка на клиенте и сервере)

### 9.2 Уведомления
- Соавтор получает уведомление типа `coauthor`
- Уведомление содержит данные актора (кто добавил)
- Уведомление ссылается на пост

### 9.3 RLS (Row Level Security)
- Соавторы видны всем (публичное чтение)
- Создавать соавторов могут только авторизованные пользователи
- Удалять соавторов может только автор поста

## 10. Примеры использования

### 10.1 Backend - создание поста с соавтором

```javascript
POST /api/posts
{
  "caption": "Check out this amazing photo!",
  "media_url": "https://...",
  "media_type": "image",
  "coauthors": ["user_id_or_username"],
  "external_link_url": "https://example.com",
  "external_link_text": "Visit"
}
```

### 10.2 Backend - ответ с соавтором

```json
{
  "id": "post_id",
  "caption": "...",
  "profiles": { "username": "author", ... },
  "coauthor": {
    "id": "user_id",
    "username": "coauthor_username",
    "name": "Coauthor Name",
    "avatar_url": "https://..."
  },
  "external_link_url": "https://example.com",
  "external_link_text": "Visit"
}
```

### 10.3 Flutter - создание поста

```dart
await postsProvider.createPost(
  caption: captionText,
  mediaUrl: mediaUrl,
  mediaType: mediaType,
  coauthor: selectedCoauthor?.id, // User ID
  externalLinkUrl: 'https://example.com',
  externalLinkText: 'Visit',
  // ... other params
);
```

## 11. Файлы изменений

### База данных
- `supabase/migrations/add_post_coauthors.sql` ✅
- `supabase/migrations/add_post_external_link.sql` ✅
- `supabase/migrations/add_coauthor_notification_type.sql` ✅

### Backend
- `src/routes/post.routes.js` ✅
- `src/routes/user.routes.js` ✅

### Flutter - Модели
- `fuisor_app/lib/models/user.dart` ✅

### Flutter - Screens
- `fuisor_app/lib/screens/create_post_screen.dart` ✅

### Flutter - Providers
- `fuisor_app/lib/providers/posts_provider.dart` ✅

### Flutter - Services
- `fuisor_app/lib/services/api_service.dart` ✅

### Flutter - Widgets
- `fuisor_app/lib/widgets/post_card.dart` ✅

## Статус: ✅ Завершено

Все функции реализованы и готовы к тестированию.

