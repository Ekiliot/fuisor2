# Password Recovery Implementation

## Обзор

Реализована полная функциональность восстановления пароля с поддержкой username/email, подтверждением личности и OTP кодами.

## Реализованные компоненты

### Backend (Node.js API)

#### 1. База данных
**Файл:** `supabase/migrations/add_password_reset_otp.sql`
- Создана таблица `password_reset_otp` для хранения OTP кодов
- OTP коды хранятся в хешированном виде (SHA-256, VARCHAR(255))
- Срок действия OTP: 10 минут
- RLS политики для безопасности

#### 2. API Endpoints
**Файл:** `src/routes/auth.routes.js`

**POST `/api/auth/password/reset/initiate`**
- Принимает username или email
- Возвращает профиль пользователя (username, name, avatar_url, email)
- Не требует авторизации

**POST `/api/auth/password/reset/send-otp`**
- Генерирует и отправляет OTP на email
- Использует встроенный email шаблон
- Поддерживает Resend API

**POST `/api/auth/password/reset/confirm`**
- Проверяет OTP код
- Обновляет пароль через Supabase Admin
- Помечает OTP как использованный

### Frontend (Flutter)

#### 3. API Methods
**Файл:** `fuisor_app/lib/services/api_service.dart`
- `initiatePasswordReset(String identifier)` - инициализация
- `sendPasswordResetOTP(String identifier)` - отправка OTP
- `confirmPasswordReset(String identifier, String otpCode, String newPassword)` - подтверждение

#### 4. Экраны

**ForgotPasswordScreen** (`fuisor_app/lib/screens/forgot_password_screen.dart`)
- Ввод username или email
- Валидация email формата
- Навигация на ConfirmIdentityScreen

**ConfirmIdentityScreen** (`fuisor_app/lib/screens/confirm_identity_screen.dart`)
- Отображение аватара, username, name
- Замаскированный email (через `EmailUtils.maskEmail()`)
- Подтверждение личности ("Is this you?")

**ResetPasswordOTPScreen** (`fuisor_app/lib/screens/reset_password_otp_screen.dart`)
- Отправка OTP на email
- Ввод 6-значного OTP кода
- Ввод нового пароля и подтверждения
- Таймер обратного отсчета для повторной отправки (60 секунд)
- Навигация на LoginScreen после успеха

#### 5. Интеграция
**Файл:** `fuisor_app/lib/screens/login_screen.dart`
- Добавлена кнопка "Forgot Password?" в ErrorMessageWidget
- Навигация на ForgotPasswordScreen

## Навигационный поток

```
LoginScreen (Forgot Password?)
    ↓
ForgotPasswordScreen (ввод username/email)
    ↓
ConfirmIdentityScreen (подтверждение личности)
    ↓
ResetPasswordOTPScreen (OTP + новый пароль)
    ↓
LoginScreen (успешное восстановление)
```

## Безопасность

1. **OTP коды:**
   - Хранятся в хешированном виде (SHA-256)
   - Срок действия: 10 минут
   - Одноразовые (помечаются как использованные)

2. **Валидация:**
   - Email формат проверяется
   - Пароль минимум 6 символов
   - Подтверждение пароля

3. **Защита данных:**
   - Email маскируется при отображении
   - RLS политики в базе данных
   - Не требуется авторизация для восстановления

## UI/UX Features

1. **Замаскированный email:** `val···@g···com`
2. **Таймер обратного отсчета:** 60 секунд для повторной отправки OTP
3. **Валидация в реальном времени**
4. **Понятные сообщения об ошибках**
5. **Загрузочные индикаторы**
6. **Темная тема в стиле SONET**

## Необходимые действия

### 1. Применить миграцию базы данных

Выполните SQL из файла `supabase/migrations/add_password_reset_otp.sql` в Supabase Dashboard или через CLI:

```bash
supabase db push
```

### 2. Настроить отправку email (опционально)

Для отправки email на почту настройте Resend API:

```env
RESEND_API_KEY=re_your_api_key_here
RESEND_FROM_EMAIL=SONET <onboarding@resend.dev>
```

Без настройки OTP коды будут логироваться в консоль сервера (для разработки).

### 3. Перезапустить backend

```bash
npm restart
# или
pm2 restart all
```

### 4. Перезапустить Flutter приложение

```bash
cd fuisor_app
flutter run
```

## Тестирование

### Backend API

**1. Инициализация восстановления:**
```bash
curl -X POST http://localhost:3000/api/auth/password/reset/initiate \
  -H "Content-Type: application/json" \
  -d '{"identifier":"username"}'
```

**2. Отправка OTP:**
```bash
curl -X POST http://localhost:3000/api/auth/password/reset/send-otp \
  -H "Content-Type: application/json" \
  -d '{"identifier":"username"}'
```

**3. Подтверждение с OTP:**
```bash
curl -X POST http://localhost:3000/api/auth/password/reset/confirm \
  -H "Content-Type: application/json" \
  -d '{"identifier":"username","otp_code":"123456","new_password":"newpass123"}'
```

### Frontend Flow

1. Открыть LoginScreen
2. Нажать "Forgot Password?" (в ErrorMessageWidget после неудачного входа)
3. Ввести username или email
4. Подтвердить личность
5. Отправить OTP
6. Ввести OTP и новый пароль
7. Успех - переход на LoginScreen

## Файлы

### Новые файлы:
- `supabase/migrations/add_password_reset_otp.sql`
- `fuisor_app/lib/screens/forgot_password_screen.dart`
- `fuisor_app/lib/screens/confirm_identity_screen.dart`
- `fuisor_app/lib/screens/reset_password_otp_screen.dart`

### Изменённые файлы:
- `src/routes/auth.routes.js` - 3 новых endpoint
- `fuisor_app/lib/screens/login_screen.dart` - кнопка "Forgot Password?"
- `fuisor_app/lib/services/api_service.dart` - 3 новых метода

## Известные ограничения

1. **Email отправка:** Требует настройки Resend API для production
2. **Rate limiting:** Нет ограничения на количество запросов OTP (рекомендуется добавить)
3. **Brute force protection:** Нет защиты от подбора OTP (рекомендуется добавить лимит попыток)

## Будущие улучшения

1. Добавить rate limiting для отправки OTP
2. Добавить защиту от brute force (лимит попыток ввода OTP)
3. Добавить возможность восстановления через SMS
4. Добавить 2FA для дополнительной безопасности
5. Логирование всех попыток восстановления пароля

