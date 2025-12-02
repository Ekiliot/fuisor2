# Что такое RESEND_FROM_EMAIL?

## Простыми словами

`RESEND_FROM_EMAIL` — это **адрес отправителя** для писем. Это адрес, который будет виден пользователю, когда он получит письмо с OTP кодом.

## Формат

```
RESEND_FROM_EMAIL=SONET <noreply@yourdomain.com>
```

Разберем по частям:

### 1. `SONET` 
Это **имя отправителя**. Будет видно в почтовом клиенте:
```
От: SONET <noreply@yourdomain.com>
```

### 2. `<noreply@yourdomain.com>`
Это **email адрес отправителя**. Замените `yourdomain.com` на ваш реальный домен.

## Примеры

### ✅ Для тестирования (работает сразу):
```env
RESEND_FROM_EMAIL=SONET <onboarding@resend.dev>
```
Это тестовый домен от Resend, можно использовать сразу без настройки.

### ✅ Для продакшена (ваш домен):
```env
RESEND_FROM_EMAIL=SONET <noreply@fuisor2.vercel.app>
```
Или если у вас свой домен:
```env
RESEND_FROM_EMAIL=SONET <noreply@myapp.com>
```

## Что видит пользователь

Когда пользователь получит письмо с OTP, он увидит:

```
От: SONET <noreply@yourdomain.com>
Тема: Your Password Change Verification Code - SONET
```

## Важные моменты

### Для разработки
- Можете использовать `onboarding@resend.dev` — работает сразу
- Не требует настройки DNS
- Ограниченное количество писем в день

### Для продакшена
- Нужен свой домен (например, `yourdomain.com`)
- Нужно добавить домен в Resend Dashboard
- Нужно настроить DNS записи (SPF, DKIM)
- Нужно дождаться верификации домена

## Минимальная настройка для старта

Просто добавьте в `.env`:
```env
RESEND_API_KEY=re_your_api_key_here
RESEND_FROM_EMAIL=SONET <onboarding@resend.dev>
```

И всё будет работать! Письма будут отправляться с адреса `onboarding@resend.dev`.

## Где это используется

В коде это используется здесь:
```javascript
from: process.env.RESEND_FROM_EMAIL || 'SONET <noreply@sonet.app>'
```

Если переменная не установлена, будет использоваться значение по умолчанию.

## Пример полного .env файла

```env
# Supabase
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key

# Resend Email
RESEND_API_KEY=re_1234567890abcdef
RESEND_FROM_EMAIL=SONET <onboarding@resend.dev>
```

## Вопросы?

- **Можно ли не указывать?** Да, будет использовано значение по умолчанию: `SONET <noreply@sonet.app>`
- **Можно ли изменить имя?** Да, измените `SONET` на любое другое имя
- **Можно ли изменить email?** Да, но для продакшена нужна верификация домена

