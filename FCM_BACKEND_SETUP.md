# 🔥 Backend FCM Integration Setup

## ✅ Что было сделано

1. ✅ Добавлен `firebase-admin` в `package.json`
2. ✅ Создан FCM сервис (`src/utils/fcm_service.js`)
3. ✅ Создана миграция для добавления `fcm_token` в таблицу `profiles`
4. ✅ Создан эндпоинт `PUT /api/users/fcm-token` для сохранения токена
5. ✅ Интегрирована отправка FCM уведомлений в:
   - Подписки (`follow.routes.js`)
   - Лайки постов (`post.routes.js`)
   - Комментарии (`post.routes.js`)
   - Лайки комментариев (`post.routes.js`)
   - Сообщения (`messages.routes.js`)
6. ✅ Обновлена функция `createNotification()` для автоматической отправки FCM

---

## 🔧 Настройка Firebase Admin SDK

### Шаг 1: Получение Service Account Key

1. Перейдите в [Firebase Console](https://console.firebase.google.com/)
2. Выберите ваш проект
3. Перейдите в **Project Settings** (шестеренка рядом с "Project Overview")
4. Откройте вкладку **"Service accounts"**
5. Нажмите **"Generate new private key"**
6. Скачайте JSON файл с credentials

### Шаг 2: Настройка переменной окружения

Скопируйте содержимое скачанного JSON файла и добавьте его как переменную окружения:

#### Для локальной разработки:

Создайте файл `.env` в корне проекта (если его нет) и добавьте:

```env
FIREBASE_ADMIN_CONFIG='{"type":"service_account","project_id":"your-project-id",...}'
```

**ВАЖНО**: Весь JSON должен быть в одной строке, экранируйте кавычки правильно!

#### Для production (Vercel/Railway/Render):

Добавьте переменную окружения `FIREBASE_ADMIN_CONFIG` в настройках вашего хостинга:
- Значение: весь JSON из service account key (в одну строку)

---

## 📦 Установка зависимостей

После добавления `firebase-admin` в `package.json`, установите зависимости:

```bash
npm install
```

---

## 🗄️ Применение миграции базы данных

Примените миграцию для добавления поля `fcm_token`:

```bash
# Через Supabase CLI
supabase migration up add_fcm_token_to_profiles

# Или через Supabase Dashboard
# Загрузите файл supabase/migrations/add_fcm_token_to_profiles.sql
```

---

## 🔍 Структура FCM сервиса

### Основные функции:

1. **`initializeFCM()`** - Инициализация Firebase Admin SDK
   - Автоматически вызывается при старте сервера
   - Читает `FIREBASE_ADMIN_CONFIG` из переменных окружения

2. **`sendNotificationForEvent(userId, actorId, type, options)`** - Отправка уведомления для события
   - `userId` - кому отправить
   - `actorId` - кто совершил действие
   - `type` - тип события ('like', 'comment', 'follow', 'mention', 'message', 'comment_like')
   - `options` - дополнительные параметры (postId, commentId, messageContent и т.д.)

3. **`getUserFCMToken(userId)`** - Получение FCM токена пользователя из БД

---

## 📡 Типы уведомлений

### 1. **Like** (лайк поста)
```javascript
sendNotificationForEvent(postOwnerId, likerId, 'like', {
  postId: 'uuid'
});
```
**Текст**: "{Имя} liked your post"

### 2. **Comment** (комментарий)
```javascript
sendNotificationForEvent(postOwnerId, commenterId, 'comment', {
  postId: 'uuid',
  commentId: 'uuid',
  commentContent: 'Текст комментария'
});
```
**Текст**: "{Имя} commented on your post" + текст комментария

### 3. **Follow** (подписка)
```javascript
sendNotificationForEvent(followedUserId, followerId, 'follow');
```
**Текст**: "{Имя} started following you"

### 4. **Message** (новое сообщение)
```javascript
sendNotificationForEvent(recipientId, senderId, 'message', {
  otherUserName: 'Имя отправителя',
  messageContent: 'Текст сообщения',
  chatId: 'uuid',
  unreadCount: 5
});
```
**Текст**: "{Имя отправителя}" + текст сообщения

### 5. **Comment Like** (лайк комментария)
```javascript
sendNotificationForEvent(commentOwnerId, likerId, 'comment_like', {
  postId: 'uuid',
  commentId: 'uuid'
});
```
**Текст**: "{Имя} liked your comment"

---

## 🔄 Где отправляются уведомления

### Автоматически через `createNotification()`:

- ✅ **Лайки постов** - `post.routes.js` → `POST /api/posts/:id/like`
- ✅ **Комментарии** - `post.routes.js` → `POST /api/posts/:id/comments`
- ✅ **Лайки комментариев** - `post.routes.js` → `POST /api/posts/:postId/comments/:commentId/like`
- ✅ **Подписки** - `follow.routes.js` → `POST /api/follow/:userId`

### Отдельно для сообщений:

- ✅ **Новые сообщения** - `messages.routes.js` → `POST /api/messages/chats/:chatId/messages`

---

## 📝 Эндпоинты

### `PUT /api/users/fcm-token`

Сохраняет FCM токен пользователя.

**Request:**
```json
{
  "fcm_token": "dGhpcyBpcyBhIGZha2UgdG9rZW4..."
}
```

**Response:**
```json
{
  "success": true,
  "message": "FCM token updated successfully"
}
```

**Authorization:** Bearer token required

---

## 🐛 Troubleshooting

### Ошибка: "FIREBASE_ADMIN_CONFIG not found"

**Решение:**
1. Проверьте, что переменная окружения `FIREBASE_ADMIN_CONFIG` установлена
2. Убедитесь, что JSON валидный и в одной строке
3. Перезапустите сервер после добавления переменной

### Ошибка: "Firebase Admin SDK initialization failed"

**Решение:**
1. Проверьте правильность JSON credentials
2. Убедитесь, что service account key не истек
3. Проверьте, что в Firebase Console включен Cloud Messaging API

### Уведомления не отправляются

**Решение:**
1. Проверьте логи сервера на наличие ошибок FCM
2. Убедитесь, что у пользователя есть валидный `fcm_token` в БД
3. Проверьте, что Firebase Admin SDK инициализирован (должно быть в логах при старте)
4. Если токен невалидный, он автоматически удаляется из БД

### "Invalid registration token"

**Решение:**
- Это означает, что FCM токен устарел или невалиден
- Сервис автоматически удаляет такие токены из БД
- Пользователю нужно будет обновить токен (отправить новый через `/api/users/fcm-token`)

---

## 📚 Дополнительные ресурсы

- [Firebase Admin SDK Documentation](https://firebase.google.com/docs/admin/setup)
- [FCM Server Documentation](https://firebase.google.com/docs/cloud-messaging/server)
- [Service Account Keys](https://console.firebase.google.com/project/_/settings/serviceaccounts/adminsdk)

---

## ✅ Проверка работы

После настройки:

1. Запустите сервер:
   ```bash
   npm start
   ```

2. В логах должно быть:
   ```
   [FCM] Firebase Admin initialized successfully
   ```

3. Протестируйте отправку уведомления через создание события:
   - Поставьте лайк на пост
   - Оставьте комментарий
   - Отправьте сообщение

4. Проверьте логи на наличие:
   ```
   [FCM] Successfully sent notification to user...
   ```

Готово! 🎉
