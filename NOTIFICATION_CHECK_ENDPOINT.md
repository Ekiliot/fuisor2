# Notification Check Endpoint Implementation

## Overview

Реализован универсальный эндпоинт `GET /api/notifications/check` для проверки всех новых событий пользователя. Этот эндпоинт предназначен для использования фоновым сервисом push-уведомлений.

## Эндпоинт

### GET `/api/notifications/check`

**Аутентификация:** Требуется (Bearer token)

**Query параметры:**
- `lastCheckTime` (string, опционально) - ISO 8601 timestamp последней проверки
- `limit` (number, опционально, по умолчанию 50) - лимит результатов для каждого типа событий

### Структура ответа

```json
{
  "summary": {
    "notifications": 5,
    "messages": 3,
    "posts": 2,
    "stories": 1,
    "total": 11
  },
  "details": {
    "notifications": [...],
    "messages": [...],
    "posts": [...],
    "stories": [...]
  },
  "timestamp": "2025-12-02T12:00:00.000Z"
}
```

## Что проверяется

### 1. Notifications (Уведомления)

**Критерий "новизны":** `is_read = false`

Возвращает непрочитанные уведомления пользователя со всей необходимой информацией:
- Информация об актере (кто выполнил действие)
- Связанный пост (если применимо)
- Связанный комментарий (если применимо)

**Типы уведомлений:**
- `like` - лайк на пост
- `comment` - комментарий к посту
- `comment_like` - лайк на комментарий
- `follow` - новый подписчик
- `mention` - упоминание в посте

### 2. Messages (Сообщения)

**Критерий "новизны":** `unread_count > 0` в чате

Возвращает список чатов с непрочитанными сообщениями, включая:
- Информацию о другом участнике чата
- Последнее сообщение в чате
- Количество непрочитанных сообщений

### 3. Posts (Посты от подписок)

**Критерий "новизны":** `created_at > lastCheckTime` (или последние 24 часа)

Возвращает новые обычные посты (не stories) от пользователей, на которых подписан текущий пользователь:
- Информация о пользователе-авторе
- Медиа контент (URL, тип, thumbnail)
- Caption

**Фильтры:**
- `expires_at IS NULL` - исключает stories
- Только от пользователей из списка подписок

### 4. Stories (Сторис от подписок)

**Критерий "новизны":** `created_at > lastCheckTime` (или последние 24 часа)

Возвращает новые stories от подписок:
- Только активные stories (`expires_at > NOW()`)
- Информация о пользователе-авторе
- Медиа контент

**Фильтры:**
- `expires_at IS NOT NULL` - только stories
- `expires_at > NOW()` - не истекшие
- Только от пользователей из списка подписок

## Оптимизация

Созданы следующие индексы для оптимизации производительности:

### 1. `idx_posts_user_id_created_at_no_stories`
```sql
ON posts(user_id, created_at DESC) WHERE expires_at IS NULL
```
Ускоряет получение обычных постов от подписок.

### 2. `idx_posts_user_id_stories_expires_at`
```sql
ON posts(user_id, expires_at DESC, created_at DESC) WHERE expires_at IS NOT NULL
```
Ускоряет получение активных stories от подписок.

### 3. `idx_messages_chat_id_created_at`
```sql
ON messages(chat_id, created_at DESC) WHERE deleted_at IS NULL
```
Ускоряет получение последнего сообщения для каждого чата.

### 4. `idx_notifications_user_id_unread_created_at`
```sql
ON notifications(user_id, created_at DESC) WHERE is_read = false
```
Ускоряет получение непрочитанных уведомлений.

## Производительность

- **Параллельное выполнение:** Все 4 проверки выполняются одновременно через `Promise.all()`
- **Лимитирование:** Каждый тип событий ограничен параметром `limit` (по умолчанию 50)
- **Безопасность:** Использует существующие RLS политики Supabase
- **Обработка ошибок:** Каждая проверка обернута в try-catch, возвращает пустой массив при ошибке

## Логирование

Эндпоинт логирует:
- Начало проверки с userId и lastCheckTime
- Количество найденных событий каждого типа
- Итоговую сводку
- Все ошибки на каждом этапе

Префикс логов: `[Notifications Check]`

## Использование

### Пример запроса

```bash
GET /api/notifications/check?lastCheckTime=2025-12-02T10:00:00.000Z&limit=20
Authorization: Bearer <access_token>
```

### Пример использования в фоновом сервисе

```javascript
// Каждые 30-60 секунд
async function checkForNewEvents() {
  const lastCheck = localStorage.getItem('lastNotificationCheck');
  
  const response = await fetch(
    `/api/notifications/check?lastCheckTime=${lastCheck}&limit=50`,
    {
      headers: {
        'Authorization': `Bearer ${accessToken}`
      }
    }
  );
  
  const data = await response.json();
  
  // Сохранить новый timestamp для следующей проверки
  localStorage.setItem('lastNotificationCheck', data.timestamp);
  
  // Показать уведомления пользователю
  if (data.summary.total > 0) {
    showNotifications(data.details);
  }
}
```

## Файлы

### Изменённые:
- `src/routes/notification.routes.js` - добавлен роут `/check`

### Созданные:
- `supabase/migrations/add_notification_check_indexes.sql` - индексы для оптимизации

## Следующие шаги

Для полной реализации фонового сервиса push-уведомлений потребуется:

1. **Frontend (Flutter):**
   - Добавить пакеты: `flutter_background_service`, `flutter_local_notifications`
   - Создать `BackgroundNotificationService`
   - Создать `NotificationManager` для показа локальных уведомлений
   - Интегрировать в `main.dart`

2. **Настройка Android:**
   - Добавить permissions в `AndroidManifest.xml`
   - Настроить foreground service

3. **Настройка iOS:**
   - Настроить Background Modes в `Info.plist`
   - Настроить уведомления

4. **Тестирование:**
   - Проверить работу в фоне
   - Проверить расход батареи
   - Проверить поведение при различных условиях сети

