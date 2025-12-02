# 🔥 Настройка Firebase Cloud Messaging (FCM)

## 📋 Что было сделано

✅ Добавлены Firebase зависимости (`firebase_core`, `firebase_messaging`)
✅ Создан FCM сервис для обработки уведомлений
✅ Интегрирован в приложение (инициализация, получение токена, отправка на сервер)
✅ Удален старый WorkManager код
✅ Обновлен API сервис для отправки FCM токена

---

## 🔧 Настройка Firebase (ТРЕБУЕТСЯ)

### Шаг 1: Создание Firebase проекта

1. Перейдите на [Firebase Console](https://console.firebase.google.com/)
2. Нажмите **"Add project"** или выберите существующий проект
3. Следуйте инструкциям создания проекта

### Шаг 2: Добавление Android приложения

1. В Firebase Console выберите ваш проект
2. Нажмите на иконку **Android** (или **Add app** → **Android**)
3. Заполните форму:
   - **Android package name**: `com.fuisor.app.fuisor_app`
   - **App nickname** (опционально): `Sonet`
   - **Debug signing certificate SHA-1** (опционально, для debug сборок)
4. Нажмите **"Register app"**

### Шаг 3: Скачивание google-services.json

1. После регистрации приложения, Firebase предложит скачать `google-services.json`
2. **ВАЖНО**: Скачайте файл и поместите его в:
   ```
   fuisor_app/android/app/google-services.json
   ```
3. Файл должен быть на этом пути, иначе Firebase не будет работать!

### Шаг 4: Настройка Cloud Messaging

1. В Firebase Console перейдите в **"Cloud Messaging"** (в левом меню)
2. Нажмите **"Get started"** (если еще не активирован)
3. Убедитесь, что Cloud Messaging API включен

---

## 📝 Структура файлов после настройки

```
fuisor_app/
├── android/
│   ├── app/
│   │   ├── google-services.json  ← ДОБАВЬТЕ ЭТОТ ФАЙЛ!
│   │   └── build.gradle.kts
│   ├── build.gradle.kts
│   └── settings.gradle.kts
└── lib/
    └── services/
        └── fcm_service.dart  ← Создан
```

---

## 🔌 Backend интеграция

### Требуется обновить ваш backend:

1. **Добавить эндпоинт для сохранения FCM токена:**
   ```
   PUT /api/users/fcm-token
   Body: { "fcm_token": "..." }
   Authorization: Bearer <access_token>
   ```

2. **Установить Firebase Admin SDK** на сервере:
   ```bash
   npm install firebase-admin
   ```

3. **Отправка уведомлений через FCM** при событиях:
   - Новые уведомления
   - Новые сообщения
   - Новые посты от подписок
   - Новые stories

### Пример кода для отправки уведомлений (Node.js):

```javascript
const admin = require('firebase-admin');

// Инициализация (один раз при старте сервера)
const serviceAccount = require('./path/to/serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

// Отправка уведомления
async function sendNotification(userId, title, body, data) {
  // Получить FCM токен пользователя из БД
  const user = await getUser(userId);
  if (!user.fcm_token) return;

  const message = {
    notification: {
      title: title,
      body: body,
    },
    data: {
      type: data.type,
      ...data,
    },
    token: user.fcm_token,
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('Successfully sent message:', response);
  } catch (error) {
    console.error('Error sending message:', error);
    // Возможно, токен устарел - удалить его из БД
  }
}
```

---

## ✅ Проверка работы

После настройки Firebase:

1. Запустите приложение:
   ```bash
   flutter run
   ```

2. Войдите в аккаунт - FCM токен должен автоматически отправиться на сервер

3. Проверьте логи:
   ```
   FCMService: FCM Token obtained: ...
   FCMService: FCM token sent to server successfully
   ```

4. Протестируйте отправку уведомления через Firebase Console:
   - Перейдите в Cloud Messaging → **"Send test message"**
   - Введите FCM токен из логов
   - Отправьте тестовое сообщение

---

## 🐛 Troubleshooting

### Ошибка: "FirebaseApp not initialized"
- Убедитесь, что файл `google-services.json` находится в `android/app/`
- Перезапустите приложение
- Выполните `flutter clean && flutter pub get`

### Ошибка: "google-services.json not found"
- Проверьте путь к файлу: `android/app/google-services.json`
- Убедитесь, что файл не поврежден (должен быть валидный JSON)

### FCM токен не отправляется на сервер
- Проверьте, что пользователь авторизован (есть access_token)
- Проверьте логи на наличие ошибок
- Убедитесь, что эндпоинт `/api/users/fcm-token` существует на сервере

### Уведомления не приходят
- Проверьте разрешения на уведомления (Settings → Apps → Sonet → Notifications)
- Убедитесь, что FCM токен сохранен на сервере
- Проверьте, что сервер отправляет уведомления через FCM Admin SDK

---

## 📚 Дополнительные ресурсы

- [Firebase Console](https://console.firebase.google.com/)
- [FlutterFire Documentation](https://firebase.flutter.dev/)
- [Firebase Cloud Messaging Docs](https://firebase.google.com/docs/cloud-messaging)
- [FCM Admin SDK](https://firebase.google.com/docs/cloud-messaging/server)
