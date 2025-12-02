# 📍 Анализ реализации геолокации (Geo) в приложении Sonet

## 📋 Обзор

Приложение Sonet имеет частичную реализацию функций геолокации:
- ✅ **Гео-посты (geo-posts)** - посты с привязкой к местоположению
- ⚠️ **Location Sharing** - обмен местоположением с друзьями (частично реализовано)

---

## 🗄️ База данных (Supabase)

### 1. Миграции

#### `supabase/migrations/add_geolocation.sql`
Добавляет поддержку геолокации:

**Таблица `posts`:**
- `latitude DOUBLE PRECISION` - широта поста
- `longitude DOUBLE PRECISION` - долгота поста
- Индекс `idx_posts_location` для оптимизации гео-запросов

**Таблица `profiles`:**
- `location_sharing_enabled BOOLEAN DEFAULT FALSE` - включен ли обмен местоположением
- `last_location_lat DOUBLE PRECISION` - последняя известная широта
- `last_location_lng DOUBLE PRECISION` - последняя известная долгота
- `last_location_updated_at TIMESTAMPTZ` - время последнего обновления
- Индексы для оптимизации запросов location sharing

#### `supabase/migrations/add_geo_posts_fields.sql`
Добавляет дополнительные поля для geo-posts:

**Таблица `posts`:**
- `visibility TEXT DEFAULT 'public'` - видимость поста:
  - `'public'` - все видят
  - `'friends'` - только взаимные подписчики
  - `'private'` - только автор
- `expires_at TIMESTAMPTZ` - время истечения geo-post (12/24/48 часов)
- Композитный индекс `idx_posts_geo_active` для оптимизации запросов

---

## 🔌 API (Backend)

### Реализованные эндпоинты

#### 1. Получение гео-постов для карты
**`GET /api/posts/geo/map`**

**Параметры запроса:**
- `swLat` - юго-западная широта (bounding box)
- `swLng` - юго-западная долгота
- `neLat` - северо-восточная широта
- `neLng` - северо-восточная долгота

**Функционал:**
- Получает посты в указанных границах карты
- Фильтрует посты по видимости (public/friends/private)
- Фильтрует истекшие посты (expires_at)
- Возвращает посты с информацией о лайках и авторах
- Учитывает взаимных подписчиков для visibility='friends'

**Файл:** `src/routes/post.routes.js` (строки 1498-1616)

#### 2. Создание поста с геолокацией
**`POST /api/posts`**

**Параметры тела запроса:**
- `latitude` (опционально) - широта
- `longitude` (опционально) - долгота
- `visibility` (опционально) - видимость поста
- `expires_in_hours` (опционально) - время жизни geo-post (12/24/48)

**Функционал:**
- Сохраняет координаты поста в БД
- Устанавливает expires_at если указан expires_in_hours

**Файл:** `src/routes/post.routes.js` (строки 329-434)

### ❌ Отсутствующие эндпоинты

Следующие эндпоинты вызываются из фронтенда, но **НЕ РЕАЛИЗОВАНЫ** в backend:

#### 1. Обновление местоположения пользователя
**`POST /api/users/location`**

**Ожидаемые параметры:**
```json
{
  "latitude": 55.7558,
  "longitude": 37.6173
}
```

**Должен:**
- Обновлять `last_location_lat`, `last_location_lng`, `last_location_updated_at` в таблице `profiles`
- Работать только если `location_sharing_enabled = true`

#### 2. Включение/выключение location sharing
**`POST /api/users/location/sharing`**

**Ожидаемые параметры:**
```json
{
  "enabled": true
}
```

**Должен:**
- Обновлять `location_sharing_enabled` в таблице `profiles`
- При включении - обновлять текущее местоположение

#### 3. Получение местоположений друзей
**`GET /api/users/friends/locations`**

**Должен:**
- Возвращать список друзей с включенным location sharing
- Показывать только взаимных подписчиков
- Возвращать: `id`, `username`, `name`, `avatar_url`, `latitude`, `longitude`, `last_location_updated_at`

---

## 📱 Frontend (Flutter)

### Зависимости

**`fuisor_app/pubspec.yaml`:**
```yaml
# Maps and location
mapbox_maps_flutter: ^2.12.0
geolocator: ^13.0.1
```

### Основные компоненты

#### 1. MapScreen (`fuisor_app/lib/screens/map_screen.dart`)

**Функционал:**
- ✅ Отображение карты с использованием Mapbox
- ✅ Получение текущей геолокации пользователя
- ✅ Отображение маркеров гео-постов на карте
- ✅ Отображение маркеров друзей (если location sharing включен)
- ✅ Переключение между вкладками "Friends" и "Posts"
- ✅ Создание geo-post через камеру
- ✅ Анимации и эффекты (пульсация маркеров, 3D режим)
- ✅ Автоматическое обновление стиля карты в зависимости от времени суток

**Ключевые методы:**
- `_getCurrentLocation()` - получение текущей геолокации
- `_loadGeoPosts()` - загрузка гео-постов для видимой области
- `_loadFriendsLocations()` - загрузка местоположений друзей
- `_addGeoPostMarkers()` - добавление маркеров постов на карту
- `_addFriendMarkers()` - добавление маркеров друзей
- `_toggleLocationSharing()` - переключение location sharing

#### 2. ApiService (`fuisor_app/lib/services/api_service.dart`)

**Реализованные методы:**

```dart
// Получение гео-постов в границах карты
Future<List<Post>> getGeoPosts({
  required double swLat,
  required double swLng,
  required double neLat,
  required double neLng,
})

// Обновление местоположения пользователя
Future<void> updateLocation({
  required double latitude,
  required double longitude,
})

// Получение местоположений друзей
Future<List<Map<String, dynamic>>> getFriendsLocations()

// Включение/выключение location sharing
Future<void> setLocationSharing(bool enabled)
```

**Проблема:** Эти методы вызывают несуществующие эндпоинты API!

#### 3. Модель Post (`fuisor_app/lib/models/post.dart`)

**Проблема:** Модель `Post` **НЕ СОДЕРЖИТ** полей для геолокации:
- `latitude`
- `longitude`
- `visibility`
- `expiresAt`

Эти поля приходят с API, но не парсятся в модель.

---

## 🔧 Что нужно исправить/добавить

### 1. Backend API

#### Добавить в `src/routes/user.routes.js`:

```javascript
// Обновление местоположения пользователя
router.post('/location', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { latitude, longitude } = req.body;

    // Проверяем, включен ли location sharing
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('location_sharing_enabled')
      .eq('id', userId)
      .single();

    if (!profile?.location_sharing_enabled) {
      return res.status(403).json({ 
        error: 'Location sharing is not enabled' 
      });
    }

    const { error } = await supabaseAdmin
      .from('profiles')
      .update({
        last_location_lat: parseFloat(latitude),
        last_location_lng: parseFloat(longitude),
        last_location_updated_at: new Date().toISOString(),
      })
      .eq('id', userId);

    if (error) throw error;

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Включение/выключение location sharing
router.post('/location/sharing', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { enabled } = req.body;

    const { error } = await supabaseAdmin
      .from('profiles')
      .update({
        location_sharing_enabled: enabled,
      })
      .eq('id', userId);

    if (error) throw error;

    res.json({ success: true, enabled });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Получение местоположений друзей
router.get('/friends/locations', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    // Получаем взаимных подписчиков
    const { data: following } = await supabaseAdmin
      .from('follows')
      .select('following_id')
      .eq('follower_id', userId);

    const { data: followers } = await supabaseAdmin
      .from('follows')
      .select('follower_id')
      .eq('following_id', userId);

    const followingIds = following.map(f => f.following_id);
    const followerIds = followers.map(f => f.follower_id);
    const mutualFollowerIds = followingIds.filter(id => 
      followerIds.includes(id)
    );

    // Получаем профили друзей с включенным location sharing
    const { data: friends, error } = await supabaseAdmin
      .from('profiles')
      .select('id, username, name, avatar_url, last_location_lat, last_location_lng, last_location_updated_at')
      .in('id', mutualFollowerIds)
      .eq('location_sharing_enabled', true)
      .not('last_location_lat', 'is', null)
      .not('last_location_lng', 'is', null);

    if (error) throw error;

    const friendsLocations = (friends || []).map(friend => ({
      id: friend.id,
      username: friend.username,
      name: friend.name,
      avatar_url: friend.avatar_url,
      latitude: friend.last_location_lat,
      longitude: friend.last_location_lng,
      last_location_updated_at: friend.last_location_updated_at,
    }));

    res.json({ friends: friendsLocations });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
```

### 2. Frontend - Модель Post

#### Обновить `fuisor_app/lib/models/post.dart`:

```dart
class Post {
  // ... существующие поля ...
  final double? latitude;
  final double? longitude;
  final String? visibility;
  final DateTime? expiresAt;

  Post({
    // ... существующие параметры ...
    this.latitude,
    this.longitude,
    this.visibility,
    this.expiresAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      // ... существующие поля ...
      latitude: json['latitude'] != null 
        ? (json['latitude'] is double 
          ? json['latitude'] 
          : (json['latitude'] as num).toDouble())
        : null,
      longitude: json['longitude'] != null
        ? (json['longitude'] is double
          ? json['longitude']
          : (json['longitude'] as num).toDouble())
        : null,
      visibility: json['visibility'],
      expiresAt: json['expires_at'] != null
        ? DateTime.tryParse(json['expires_at'])
        : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // ... существующие поля ...
      'latitude': latitude,
      'longitude': longitude,
      'visibility': visibility,
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  Post copyWith({
    // ... существующие параметры ...
    double? latitude,
    double? longitude,
    String? visibility,
    DateTime? expiresAt,
  }) {
    return Post(
      // ... существующие поля ...
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      visibility: visibility ?? this.visibility,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
```

---

## 📊 Структура данных

### Geo-Post в БД
```sql
{
  id: UUID,
  user_id: UUID,
  caption: TEXT,
  media_url: TEXT,
  media_type: 'image' | 'video',
  latitude: DOUBLE PRECISION,  -- ✅ Есть
  longitude: DOUBLE PRECISION,  -- ✅ Есть
  visibility: 'public' | 'friends' | 'private',  -- ✅ Есть
  expires_at: TIMESTAMPTZ,  -- ✅ Есть (null для обычных постов)
  created_at: TIMESTAMPTZ,
  updated_at: TIMESTAMPTZ
}
```

### Location Sharing в БД
```sql
-- Таблица profiles
{
  id: UUID,
  location_sharing_enabled: BOOLEAN,  -- ✅ Есть
  last_location_lat: DOUBLE PRECISION,  -- ✅ Есть
  last_location_lng: DOUBLE PRECISION,  -- ✅ Есть
  last_location_updated_at: TIMESTAMPTZ  -- ✅ Есть
}
```

---

## 🎯 Итоговая оценка

| Компонент | Статус | Примечание |
|-----------|--------|------------|
| **БД - Гео-посты** | ✅ Готово | Все поля и индексы созданы |
| **БД - Location Sharing** | ✅ Готово | Все поля и индексы созданы |
| **API - Гео-посты** | ✅ Готово | Эндпоинт `/posts/geo/map` работает |
| **API - Location Sharing** | ❌ Не реализовано | Нужно добавить 3 эндпоинта |
| **Frontend - MapScreen** | ✅ Готово | Полная реализация карты |
| **Frontend - Модель Post** | ⚠️ Частично | Нет полей для геолокации |
| **Frontend - API Service** | ⚠️ Частично | Методы есть, но вызывают несуществующие эндпоинты |

---

## 🚀 Рекомендации

1. **Приоритет 1:** Добавить недостающие API эндпоинты для location sharing
2. **Приоритет 2:** Обновить модель `Post` для поддержки геолокации
3. **Приоритет 3:** Добавить валидацию координат в API
4. **Приоритет 4:** Добавить обработку ошибок для случаев, когда location sharing отключен

---

## 📝 Дополнительные заметки

- Mapbox токен настроен в `main.dart` (строка 21-24)
- Используется Mapbox Standard стиль карты
- Поддерживается 3D режим карты
- Маркеры автоматически масштабируются в зависимости от уровня зума
- Реализована пульсация маркера текущей локации
- Поддерживается автоматическое обновление стиля карты в зависимости от времени суток

