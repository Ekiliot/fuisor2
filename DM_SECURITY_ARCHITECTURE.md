# 🔒 Архитектура безопасности для системы прямых сообщений (DM)

## 📋 **Общая концепция**

Система DM должна гарантировать, что пользователь может:
- ✅ Читать **только свои** сообщения
- ✅ Видеть **только свои** чаты
- ✅ Отправлять сообщения **только в свои чаты**
- ❌ НЕ может читать чужие чаты даже если знает их ID
- ❌ НЕ может отправить сообщение в чужой чат

---

## 🗄️ **Структура базы данных**

### ⚠️ **ВАЖНО: Два подхода к хранению чатов**

#### **Вариант 1: Прямые поля (user1_id, user2_id)** - для простых DM
```sql
CREATE TABLE chats (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user1_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    user2_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user1_id, user2_id) -- Один чат между двумя пользователями
);
```
**Плюсы:**
- ✅ Проще для двух пользователей
- ✅ Быстрее запросы (меньше JOIN)
- ✅ Меньше записей в БД

**Минусы:**
- ❌ Нужна нормализация (user1_id < user2_id)
- ❌ Сложно расширять до групповых чатов

#### **Вариант 2: Таблица участников (chat_participants)** - более гибкий ✨
```sql
CREATE TABLE chats (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type TEXT DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE chat_participants (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(chat_id, user_id) -- Пользователь может быть только один раз в чате
);
```
**Плюсы:**
- ✅ Гибко - легко расширяется до групповых чатов
- ✅ Нормализованная структура
- ✅ Проще запросы ("WHERE user_id = X")
- ✅ Можно добавлять метаданные участника (роль, время входа и т.д.)

**Минусы:**
- ❌ Больше JOIN в запросах
- ❌ Чуть сложнее логика

### **Рекомендация: Вариант 2 (chat_participants)** 

**Почему?**
- Современный подход (используется в Telegram, Discord, Slack)
- Гибкость для будущих функций (групповые чаты)
- Более чистые RLS политики
- Легче поддерживать

### **Выбранная структура (Вариант 2):**

```sql
CREATE TABLE chats (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type TEXT DEFAULT 'direct' CHECK (type IN ('direct', 'group')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE chat_participants (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    unread_count INTEGER DEFAULT 0, -- Счётчик непрочитанных сообщений
    last_read_at TIMESTAMPTZ, -- Когда последний раз читал чат
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(chat_id, user_id)
);

-- Индексы для быстрого поиска
CREATE INDEX idx_chat_participants_user_id ON chat_participants(user_id);
CREATE INDEX idx_chat_participants_chat_id ON chat_participants(chat_id);
CREATE INDEX idx_chats_updated_at ON chats(updated_at DESC);
CREATE INDEX idx_chat_participants_unread_count ON chat_participants(unread_count) WHERE unread_count > 0;

-- Триггеры для автоматического обновления
```

### **Триггеры для автоматизации**

#### **1. Обновление `chats.updated_at` при новом сообщении**
```sql
CREATE OR REPLACE FUNCTION update_chat_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE chats 
  SET updated_at = NEW.created_at 
  WHERE id = NEW.chat_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER messages_update_chat_timestamp
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_chat_updated_at();
```

#### **2. Увеличить счётчик непрочитанных для получателей**
```sql
CREATE OR REPLACE FUNCTION increment_unread_count()
RETURNS TRIGGER AS $$
BEGIN
  -- Увеличиваем счётчик для всех участников кроме отправителя
  UPDATE chat_participants
  SET unread_count = unread_count + 1
  WHERE chat_id = NEW.chat_id 
    AND user_id != NEW.sender_id
    AND (last_read_at IS NULL OR last_read_at < NEW.created_at);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER messages_increment_unread
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION increment_unread_count();
```

#### **3. Сброс счётчика при прочтении (опционально)**
```sql
CREATE OR REPLACE FUNCTION reset_unread_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.last_read_at > OLD.last_read_at THEN
    UPDATE chat_participants
    SET unread_count = 0
    WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER chat_participants_reset_unread
  AFTER UPDATE OF last_read_at ON chat_participants
  FOR EACH ROW
  EXECUTE FUNCTION reset_unread_count();
```

**Для прямых сообщений:**
- При создании чата между двумя пользователями создается `chat` с `type='direct'`
- Добавляются 2 записи в `chat_participants` (по одной на каждого участника)
- Проверка что в direct-чате ровно 2 участника

### **Таблица `messages`**
```sql
CREATE TABLE messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ, -- Soft delete: когда сообщение удалено
    deleted_by_ids UUID[] DEFAULT '{}', -- Кто удалил (массив для "удалить для себя")
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Индексы
CREATE INDEX idx_messages_chat_id ON messages(chat_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX idx_messages_is_read ON messages(is_read);
CREATE INDEX idx_messages_deleted_at ON messages(deleted_at) WHERE deleted_at IS NOT NULL;
```

**Soft Delete механизм:**
- `deleted_at IS NULL` = сообщение видно всем
- `deleted_at IS NOT NULL AND user_id NOT IN deleted_by_ids` = видно этому пользователю
- `deleted_at IS NOT NULL AND user_id IN deleted_by_ids` = скрыто для этого пользователя
- Если все участники в `deleted_by_ids` → можно физически удалить (опционально)

---

## 🔐 **RLS (Row Level Security) Политики - ОСНОВА БЕЗОПАСНОСТИ**

### **Таблица `chats` - RLS политики**

```sql
-- Включить RLS
ALTER TABLE chats ENABLE ROW LEVEL SECURITY;

-- ✅ SELECT: Пользователь видит чат ТОЛЬКО если он участник
CREATE POLICY "Users can view own chats."
  ON chats FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = chats.id 
      AND chat_participants.user_id = auth.uid()
    )
  );

-- ✅ INSERT: Авторизованный пользователь может создать чат
CREATE POLICY "Authenticated users can create chats."
  ON chats FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- ✅ UPDATE: Пользователь может обновить чат ТОЛЬКО если он участник
CREATE POLICY "Users can update own chats."
  ON chats FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = chats.id 
      AND chat_participants.user_id = auth.uid()
    )
  );

-- ✅ DELETE: Пользователь может удалить чат ТОЛЬКО если он участник
CREATE POLICY "Users can delete own chats."
  ON chats FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = chats.id 
      AND chat_participants.user_id = auth.uid()
    )
  );
```

### **Таблица `chat_participants` - RLS политики**

```sql
-- Включить RLS
ALTER TABLE chat_participants ENABLE ROW LEVEL SECURITY;

-- ✅ SELECT: Пользователь видит участников ТОЛЬКО в своих чатах
CREATE POLICY "Users can view participants in own chats."
  ON chat_participants FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants cp2
      WHERE cp2.chat_id = chat_participants.chat_id 
      AND cp2.user_id = auth.uid()
    )
  );

-- ✅ INSERT: Пользователь может добавить себя в чат, если он создается
-- (контролируется через API, не через RLS напрямую)
CREATE POLICY "Authenticated users can be added to chats."
  ON chat_participants FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated' AND
    auth.uid() = user_id
  );

-- ❌ UPDATE: Не разрешено (участники не изменяются)
-- ❌ DELETE: Только через каскадное удаление чата (или через API с проверками)
```

### **Таблица `messages` - RLS политики**

```sql
-- Включить RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- ✅ SELECT: Пользователь видит сообщения ТОЛЬКО из своих чатов
-- + фильтрация soft delete (не показываем сообщения, которые пользователь удалил)
CREATE POLICY "Users can view messages from own chats."
  ON messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = messages.chat_id 
      AND chat_participants.user_id = auth.uid()
    )
    AND (
      deleted_at IS NULL OR 
      (deleted_at IS NOT NULL AND auth.uid() != ALL(deleted_by_ids))
    )
  );

-- ✅ INSERT: Пользователь может отправить сообщение ТОЛЬКО в свой чат
CREATE POLICY "Users can send messages to own chats."
  ON messages FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated' AND
    auth.uid() = sender_id AND
    EXISTS (
      SELECT 1 FROM chat_participants 
      WHERE chat_participants.chat_id = messages.chat_id 
      AND chat_participants.user_id = auth.uid()
    )
  );

-- ✅ UPDATE: Пользователь может обновить ТОЛЬКО свои сообщения
CREATE POLICY "Users can update own messages."
  ON messages FOR UPDATE
  USING (auth.uid() = sender_id);

-- ✅ DELETE: Пользователь может удалить ТОЛЬКО свои сообщения
CREATE POLICY "Users can delete own messages."
  ON messages FOR DELETE
  USING (auth.uid() = sender_id);
```

---

## 🛡️ **Дополнительные меры безопасности на уровне API**

### **1. Проверка участия в чате (КРИТИЧНО!)**

**При получении чата:**
```javascript
// ✅ ПРАВИЛЬНО - проверка через chat_participants
const { data: participant } = await supabase
  .from('chat_participants')
  .select('chat_id')
  .eq('chat_id', chatId)
  .eq('user_id', req.user.id)
  .single();

// ДОПОЛНИТЕЛЬНАЯ проверка на уровне API
if (!participant) {
  // ⚠️ Protection от timing attacks: случайная задержка для 404
  await new Promise(r => setTimeout(r, Math.random() * 100));
  return res.status(404).json({ message: 'Chat not found' });
}

// Теперь безопасно получить чат
const { data: chat } = await supabase
  .from('chats')
  .select('*')
  .eq('id', chatId)
  .single();
```

**Зачем двойная проверка?**
- RLS защищает от прямого SQL доступа
- API проверка защищает от ошибок в логике и добавляет дополнительный слой
- Защита от "defense in depth" (многоуровневая защита)

### **2. Проверка при отправке сообщения**

```javascript
// ✅ Всегда проверяем участие в чате ПЕРЕД отправкой
const { data: participant } = await supabase
  .from('chat_participants')
  .select('chat_id')
  .eq('chat_id', chatId)
  .eq('user_id', req.user.id)
  .single();

if (!participant) {
  return res.status(404).json({ message: 'Chat not found' });
}

// Проверка отправителя (sender_id должен быть равен текущему пользователю)
if (req.user.id !== senderId) {
  return res.status(403).json({ message: 'Unauthorized: Cannot send as another user' });
}
```

### **3. Проверка при создании чата**

```javascript
// ✅ Создание чата с другим пользователем
const { otherUserId } = req.body;
const currentUserId = req.user.id;

// Нельзя создать чат с собой
if (otherUserId === currentUserId) {
  return res.status(400).json({ message: 'Cannot create chat with yourself' });
}

// Проверка существующего прямого чата через chat_participants
// Находим чаты где оба пользователя являются участниками
const { data: currentUserChats } = await supabase
  .from('chat_participants')
  .select('chat_id')
  .eq('user_id', currentUserId);

const { data: otherUserChats } = await supabase
  .from('chat_participants')
  .select('chat_id')
  .eq('user_id', otherUserId);

const currentUserChatIds = currentUserChats?.map(c => c.chat_id) || [];
const otherUserChatIds = otherUserChats?.map(c => c.chat_id) || [];

// Находим пересечение - чаты где оба пользователя участники
const commonChatIds = currentUserChatIds.filter(id => otherUserChatIds.includes(id));

if (commonChatIds.length > 0) {
  // Проверяем что это direct чат
  const { data: existingDirectChat } = await supabase
    .from('chats')
    .select('id, type')
    .eq('id', commonChatIds[0])
    .eq('type', 'direct')
    .single();

  if (existingDirectChat) {
    // Чат уже существует, возвращаем его
    return res.json({ chat: existingDirectChat });
  }
}

// Создаем новый чат
const { data: newChat } = await supabase
  .from('chats')
  .insert([{ type: 'direct' }])
  .select()
  .single();

// Добавляем участников
await supabase
  .from('chat_participants')
  .insert([
    { chat_id: newChat.id, user_id: currentUserId },
    { chat_id: newChat.id, user_id: otherUserId }
  ]);
```

### **4. Проверка при получении списка сообщений**

```javascript
// ✅ Всегда проверяем участие в чате
const chatId = req.params.chatId;

// 1. Проверяем участие через chat_participants
const { data: participant } = await supabase
  .from('chat_participants')
  .select('chat_id')
  .eq('chat_id', chatId)
  .eq('user_id', req.user.id)
  .single();

if (!participant) {
  return res.status(404).json({ message: 'Chat not found' });
}

// 2. Только после проверки участия - получаем сообщения
// RLS автоматически отфильтрует, но мы уже проверили на уровне API
const { data: messages } = await supabase
  .from('messages')
  .select(`
    *,
    sender:profiles!sender_id(username, avatar_url, name)
  `)
  .eq('chat_id', chatId)
  .order('created_at', { ascending: true });
```

---

## 🚨 **Предотвращение уязвимостей**

### **1. SQL Injection**
- ✅ Используем параметризованные запросы Supabase (автоматически защищено)
- ✅ Никогда не вставляем пользовательский ввод напрямую в SQL

### **2. Подмена user_id**
- ✅ Всегда используем `req.user.id` из JWT токена (проверяется middleware)
- ✅ Никогда не доверяем `user_id` из body/params для критичных операций
- ✅ Проверяем `sender_id === req.user.id` при отправке сообщений

### **3. Прямой доступ через API**
- ✅ RLS политики блокируют на уровне БД
- ✅ Дополнительные проверки на уровне API
- ✅ Валидация всех входных параметров

### **4. Enumeration атаки (узнать ID чужих чатов)**
- ✅ При попытке доступа к несуществующему чату - 404
- ✅ При попытке доступа к чужому чату - 403
- ✅ Не раскрывать различия между "не существует" и "нет доступа"

```javascript
// ✅ ПРАВИЛЬНО - одинаковый ответ для безопасности
if (!chat || !isParticipant) {
  return res.status(404).json({ message: 'Chat not found' });
}

// ❌ НЕПРАВИЛЬНО - раскрывает информацию
if (!chat) {
  return res.status(404).json({ message: 'Chat not found' });
}
if (!isParticipant) {
  return res.status(403).json({ message: 'Access denied' }); // Раскрывает, что чат существует!
}
```

### **5. Rate Limiting**
- ✅ Ограничение на количество сообщений в минуту/час
- ✅ Защита от спама
- ✅ Middleware для rate limiting

---

## 📊 **API Endpoints (безопасная реализация)**

### **1. GET /api/messages/chats**
**Получить список всех чатов текущего пользователя**

**Проверки:**
- ✅ Только авторизованные пользователи
- ✅ Возвращаем только чаты где `user_id = req.user.id`
- ✅ Используем RLS + API проверку

**Реализация:**
```javascript
// Получаем все чаты где пользователь является участником
const { data: participantRecords } = await supabase
  .from('chat_participants')
  .select('chat_id, unread_count')
  .eq('user_id', userId);

const chatIds = participantRecords?.map(p => p.chat_id) || [];

if (chatIds.length === 0) {
  return res.json({ chats: [] });
}

// Получаем чаты с другими участниками и последним сообщением
const { data: chats } = await supabase
  .from('chats')
  .select(`
    *,
    participants:chat_participants(
      user:profiles(id, username, name, avatar_url),
      unread_count
    ),
    last_message:messages(
      id,
      content,
      created_at,
      sender_id,
      sender:profiles!sender_id(username)
    )
  `)
  .in('id', chatIds)
  .order('updated_at', { ascending: false })
  .limit(1, { foreignTable: 'messages', orderBy: { foreignTable: 'messages', column: 'created_at', ascending: false } });

// Форматируем для фронтенда
const formattedChats = chats?.map(chat => {
  const myParticipant = chat.participants.find(p => p.user.id === userId);
  
  if (chat.type === 'direct') {
    const otherParticipant = chat.participants.find(p => p.user.id !== userId);
    return {
      ...chat,
      otherUser: otherParticipant?.user,
      unreadCount: myParticipant?.unread_count || 0,
      lastMessage: chat.last_message?.[0] || null,
      participants: undefined // Скрываем для фронтенда
    };
  }
  return {
    ...chat,
    unreadCount: myParticipant?.unread_count || 0,
    lastMessage: chat.last_message?.[0] || null
  };
});
```

### **2. GET /api/messages/chats/:chatId**
**Получить конкретный чат**

**Проверки:**
- ✅ Проверка участия в чате
- ✅ RLS + API проверка
- ✅ Возвращаем 404 если чат не существует или нет доступа

### **3. GET /api/messages/chats/:chatId/messages**
**Получить сообщения чата**

**Проверки:**
- ✅ Проверка участия в чате ПЕРЕД запросом сообщений
- ✅ RLS фильтрует на уровне БД
- ✅ API проверка перед отправкой ответа

### **4. POST /api/messages/chats/:chatId/messages**
**Отправить сообщение**

**Проверки:**
- ✅ Проверка участия в чате
- ✅ Проверка что `sender_id === req.user.id`
- ✅ Валидация содержимого сообщения
- ✅ Rate limiting

### **5. POST /api/messages/chats**
**Создать новый чат**

**Проверки:**
- ✅ Проверка что текущий пользователь - участник
- ✅ Проверка на существующий чат
- ✅ Нормализация (user1_id < user2_id)

### **6. PUT /api/messages/chats/:chatId/messages/:messageId/read**
**Отметить сообщение как прочитанное**

**Проверки:**
- ✅ Проверка участия в чате
- ✅ Проверка что сообщение принадлежит этому чату
- ✅ Пользователь может отметить как прочитанное только сообщения в своих чатах

### **7. DELETE /api/messages/chats/:chatId/messages/:messageId**
**Удалить сообщение**

**Проверки:**
- ✅ Пользователь может удалить ТОЛЬКО свои сообщения
- ✅ Проверка участия в чате
- ✅ RLS + API проверка

---

## 🔍 **Тестирование безопасности**

### **Сценарии для проверки:**

1. **Попытка прочитать чужой чат:**
   - ✅ Получить список чатов пользователя A
   - ✅ Попытаться использовать ID чужого чата от пользователя B
   - ✅ Должен вернуть 404 (не раскрывать, что чат существует)

2. **Попытка отправить в чужой чат:**
   - ✅ Пользователь A пытается отправить в чат пользователей B и C
   - ✅ Должен вернуть 403

3. **Попытка подменить sender_id:**
   - ✅ Пользователь A отправляет сообщение с sender_id = пользователь B
   - ✅ Должен вернуть 403

4. **Enumeration атака:**
   - ✅ Пробовать разные UUID чатов
   - ✅ Всегда возвращать 404 (не раскрывать какие чаты существуют)

5. **SQL Injection:**
   - ✅ Пробовать `'; DROP TABLE messages; --` в параметрах
   - ✅ Supabase должен автоматически экранировать

---

## 🎯 **Рекомендации по реализации**

### **Приоритет 1: Безопасность**
1. ✅ ВСЕГДА использовать RLS политики
2. ✅ ВСЕГДА проверять участие в чате на уровне API
3. ✅ Никогда не доверять user_id из запроса
4. ✅ Использовать `req.user.id` из JWT токена

### **Приоритет 2: Производительность**
- Индексы на `user1_id`, `user2_id`, `chat_id`, `sender_id`
- Индекс на `created_at` для сортировки
- Кэширование списка чатов (опционально)

### **Приоритет 3: UX**
- Real-time обновления (Supabase Realtime)
- Push-уведомления при новых сообщениях
- Отметка о прочтении
- Удаление для всех участников (как в Telegram) или только для себя

---

## 📝 **Дополнительные соображения**

### **Блокировка пользователей**
Если реализуется блокировка:
- Блокированный пользователь не может:
  - Создать новый чат с блокирующим
  - Отправить сообщение в существующий чат
- Проверка при создании чата:
```javascript
// Проверка блокировки
const { data: blocked } = await supabase
  .from('blocked_users')
  .select('id')
  .eq('blocker_id', user1_id)
  .eq('blocked_id', user2_id)
  .single();

if (blocked) {
  return res.status(403).json({ message: 'User has blocked you' });
}
```

### **Групповые чаты (будущее)**
Если добавим групповые чаты:
- Нужна таблица `chat_participants` (многие-ко-многим)
- RLS политики должны проверять участие через JOIN
- Более сложная логика проверки

---

## ✅ **Итоговый чеклист безопасности**

- [ ] RLS политики включены для `chats` и `messages`
- [ ] RLS политика SELECT проверяет участие в чате
- [ ] RLS политика INSERT проверяет участие перед отправкой
- [ ] API проверка участия в чате перед ВСЕМИ операциями
- [ ] Проверка `sender_id === req.user.id` при отправке
- [ ] Нормализация участников чата (user1_id < user2_id)
- [ ] Индексы на все ключевые поля
- [ ] Валидация входных данных
- [ ] Rate limiting на отправку сообщений
- [ ] Логирование подозрительных попыток доступа
- [ ] Тестирование всех сценариев безопасности

---

## 🔄 **Real-time обновления (Supabase Realtime)**

### **Подписка на новые сообщения**
```javascript
// На фронтенде (Flutter/Dart)
// Используем Supabase Realtime client
final channel = supabase
  .channel('messages')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'messages',
    filter: 'chat_id=eq.$chatId'
  }, (payload) => {
    // Добавить новое сообщение в UI
    final newMessage = Message.fromJson(payload.new);
    setState(() {
      messages.add(newMessage);
    });
  })
  .subscribe();

// Отписка при dispose
channel.unsubscribe();
```

### **Typing indicator (опционально)**
```javascript
// Используем Supabase Presence для показа "печатает..."
const typingChannel = supabase.channel(`typing:${chatId}`)
  .on('presence', { event: 'sync' }, () => {
    final typingUsers = typingChannel.presenceState();
    // Обновить UI с пользователями которые печатают
  })
  .on('presence', { event: 'join' }, ({ key, newPresences }) => {
    // Пользователь начал печатать
  })
  .on('presence', { event: 'leave' }, ({ key, leftPresences }) => {
    // Пользователь перестал печатать
  });

// Когда пользователь печатает:
await typingChannel.track({
  typing: true,
  userId: currentUserId,
  timestamp: DateTime.now().toIso8601String()
});

// Когда перестал:
await typingChannel.track({
  typing: false
});
```

### **Обновление счётчика непрочитанных в реальном времени**
```javascript
// Подписка на изменения в chat_participants
final unreadChannel = supabase
  .channel('chat_participants')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'chat_participants',
    filter: 'user_id=eq.${currentUserId}'
  }, (payload) => {
    // Обновить счётчик непрочитанных в списке чатов
    final updatedParticipant = payload.new;
    updateChatUnreadCount(updatedParticipant['chat_id'], updatedParticipant['unread_count']);
  })
  .subscribe();
```

---

## 🎓 **Заключение**

Основные принципы безопасности для DM:

1. **RLS на уровне БД** - первая линия защиты
2. **API проверки** - вторая линия защиты
3. **Не доверять входным данным** - всегда проверять
4. **Defense in depth** - многоуровневая защита
5. **Минимум раскрытия информации** - одинаковые ответы для безопасности
6. **Timing attack protection** - случайные задержки для 404
7. **Soft delete** - гибкое удаление сообщений
8. **Автоматические триггеры** - для обновления метаданных
9. **Real-time обновления** - через Supabase Realtime

### **Дополнительные улучшения (из фидбека):**

✅ **Soft delete** - `deleted_at` и `deleted_by_ids[]` для гибкого удаления  
✅ **Автообновление timestamps** - триггер обновляет `chats.updated_at`  
✅ **Счётчик непрочитанных** - в `chat_participants` с автоматическим обновлением  
✅ **Оптимизация запросов** - последнее сообщение загружается одним запросом  
✅ **Real-time** - Supabase Realtime для мгновенных обновлений  
✅ **Typing indicator** - через Presence API  
✅ **Timing attack protection** - случайные задержки

При соблюдении этих принципов система будет максимально защищена и готова к масштабированию до 100-500k активных пользователей.

