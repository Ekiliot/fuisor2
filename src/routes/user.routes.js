import express from 'express';
import { supabase, supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { validateProfileUpdate, validateUUID, validateFriendId } from '../middleware/validation.middleware.js';
import { logger } from '../utils/logger.js';
import multer from 'multer';

const router = express.Router();
const upload = multer();

// Константы для определения временных интервалов
const ONLINE_THRESHOLD = 60 * 1000; // 1 минута (если heartbeat не приходил дольше - считаем офлайн)
const RECENTLY_THRESHOLD = 5 * 60 * 1000; // 5 минут
const THIS_WEEK_THRESHOLD = 7 * 24 * 60 * 60 * 1000; // 7 дней
const THIS_MONTH_THRESHOLD = 30 * 24 * 60 * 60 * 1000; // 30 дней

// Get current user profile
router.get('/profile', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    console.log('Get current user profile for:', userId);

    // Get user profile
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();

    if (profileError || !profile) {
      console.log('Profile error:', profileError);
      return res.status(404).json({ message: 'User profile not found' });
    }

    // Get followers count
    const { count: followersCount, error: followersError } = await supabaseAdmin
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('following_id', userId);

    if (followersError) throw followersError;

    // Get following count
    const { count: followingCount, error: followingError } = await supabaseAdmin
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('follower_id', userId);

    if (followingError) throw followingError;

    // Get posts count
    const { count: postsCount, error: postsError } = await supabaseAdmin
      .from('posts')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId);

    if (postsError) throw postsError;

    res.json({
      ...profile,
      followers_count: followersCount || 0,
      following_count: followingCount || 0,
      posts_count: postsCount || 0,
    });
  } catch (error) {
    console.error('Error getting current user profile:', error);
    res.status(500).json({ error: 'Failed to get user profile' });
  }
});

// Get user profile by username
router.get('/username/:username', async (req, res) => {
  console.log('GET /username/:username route hit', { params: req.params, path: req.path, url: req.url });
  try {
    const { username } = req.params;
    const trimmedUsername = username.trim();
    
    console.log('Get user by username request:', { username, trimmedUsername });

    if (!trimmedUsername || trimmedUsername.length === 0) {
      return res.status(400).json({ message: 'Username is required' });
    }

    // Normalize username: trim and convert to lowercase for comparison
    const normalizedUsername = trimmedUsername.toLowerCase().trim();
    
    // Try exact match first (case-sensitive)
    let { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('*')
      .eq('username', trimmedUsername)
      .single();
    
    console.log('Exact match result:', { 
      searched: trimmedUsername, 
      found: !!profile, 
      error: profileError?.code 
    });

    // If not found, try case-insensitive search using LOWER() function
    if (profileError && profileError.code === 'PGRST116') {
      console.log('Exact match failed, trying case-insensitive search with normalized:', normalizedUsername);
      
      // Use RPC or raw query for case-insensitive search
      // First try with ilike (PostgreSQL case-insensitive)
      const result = await supabaseAdmin
        .from('profiles')
        .select('*')
        .ilike('username', trimmedUsername)
        .maybeSingle();
      
      profile = result.data;
      profileError = result.error;
      
      console.log('Case-insensitive search result:', { 
        searched: trimmedUsername,
        normalized: normalizedUsername,
        found: !!profile,
        error: profileError?.code 
      });
      
      // If still not found, try to find any user with similar username (for debugging)
      if (!profile) {
        const { data: allUsers, error: debugError } = await supabaseAdmin
          .from('profiles')
          .select('username')
          .limit(10);
        
        console.log('Sample usernames in DB:', allUsers?.map(u => u.username) || []);
      }
    }

    if (profileError || !profile) {
      console.log('User not found:', { username: trimmedUsername, error: profileError });
      return res.status(404).json({ message: 'User not found' });
    }

    // Get followers count
    const { count: followersCount, error: followersError } = await supabase
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('following_id', profile.id);

    if (followersError) throw followersError;

    // Get following count
    const { count: followingCount, error: followingError } = await supabase
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('follower_id', profile.id);

    if (followingError) throw followingError;

    // Get posts count
    const { count: postsCount, error: postsError } = await supabase
      .from('posts')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', profile.id);

    if (postsError) throw postsError;

    res.json({
      ...profile,
      followers_count: followersCount || 0,
      following_count: followingCount || 0,
      posts_count: postsCount || 0
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get notification preferences
router.get('/notification-preferences', validateAuth, async (req, res) => {
  try {
    const userId = req.user?.id;
    
    if (!userId) {
      console.error('GET /notification-preferences: No user ID in request');
      return res.status(401).json({ error: 'User not authenticated' });
    }
    
    console.log('GET /notification-preferences - Request:', {
      userId,
      hasUser: !!req.user,
    });
    
    const { getUserNotificationPreferences } = await import('../utils/notification_preferences.js');
    const preferences = await getUserNotificationPreferences(userId);

    if (!preferences) {
      console.error('GET /notification-preferences: Failed to get preferences');
      return res.status(500).json({ error: 'Failed to get notification preferences' });
    }

    // Ensure we return a single object, not an array
    const response = Array.isArray(preferences) ? preferences[0] : preferences;
    
    console.log('GET /notification-preferences - Response:', { 
      hasPreferences: !!response,
      keys: Object.keys(response || {})
    });
    
    res.json(response);
  } catch (error) {
    console.error('Error getting notification preferences:', error);
    res.status(500).json({ error: error.message });
  }
});

// Update notification preferences
router.put('/notification-preferences', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const updates = req.body;

    // Validate updates object
    const validKeys = [
      'mention_enabled',
      'comment_mention_enabled',
      'new_post_enabled',
      'new_story_enabled',
      'follow_enabled',
      'like_enabled',
      'comment_enabled',
      'comment_reply_enabled',
      'comment_like_enabled',
    ];

    const updateKeys = Object.keys(updates);
    const invalidKeys = updateKeys.filter(key => !validKeys.includes(key));

    if (invalidKeys.length > 0) {
      return res.status(400).json({ 
        error: `Invalid preference keys: ${invalidKeys.join(', ')}` 
      });
    }

    // Validate boolean values
    for (const key of updateKeys) {
      if (typeof updates[key] !== 'boolean') {
        return res.status(400).json({ 
          error: `Preference "${key}" must be a boolean` 
        });
      }
    }

    const { updateNotificationPreferences } = await import('../utils/notification_preferences.js');
    const success = await updateNotificationPreferences(userId, updates);

    if (!success) {
      return res.status(500).json({ error: 'Failed to update notification preferences' });
    }

    // Return updated preferences
    const { getUserNotificationPreferences } = await import('../utils/notification_preferences.js');
    const preferences = await getUserNotificationPreferences(userId);

    res.json(preferences);
  } catch (error) {
    console.error('Error updating notification preferences:', error);
    res.status(500).json({ error: error.message });
  }
});

// ВАЖНО: Конкретные маршруты должны быть ПЕРЕД параметрическими маршрутами
// Иначе Express будет пытаться обработать их как /:id и validateUUID вернет 400

// Get recommendation settings
router.get('/recommendation-settings', (req, res, next) => {
  console.log('GET /recommendation-settings: Request received', {
    headers: req.headers,
    query: req.query,
    hasAuth: !!req.headers.authorization
  });
  next();
}, validateAuth, async (req, res) => {
  try {
    const userId = req.user?.id;
    
    if (!userId) {
      console.error('GET /recommendation-settings: No user ID in request');
      return res.status(401).json({ error: 'User not authenticated' });
    }

    console.log('GET /recommendation-settings: Fetching settings for user:', userId);

    const { data, error } = await supabaseAdmin
      .from('profiles')
      .select('recommendation_country, recommendation_city, recommendation_district, recommendation_locations, recommendation_radius, recommendation_auto_location, recommendation_prompt_shown, recommendation_enabled, explorer_mode_enabled, explorer_mode_expires_at')
      .eq('id', userId)
      .maybeSingle();

    // Если ошибка и это не "не найдено", выбрасываем ошибку
    if (error) {
      // PGRST116 - это код "не найдено" для maybeSingle, это нормально
      if (error.code !== 'PGRST116') {
        console.error('GET /recommendation-settings: Supabase error:', error);
        throw error;
      }
    }

    // Если данных нет, возвращаем дефолтные значения
    if (!data) {
      console.log('GET /recommendation-settings: No data found, returning defaults');
      return res.json({
        country: null,
        city: null,
        district: null,
        locations: [],
        radius: 0,
        autoLocation: false,
        promptShown: false,
        enabled: false,
        explorerModeEnabled: false,
        explorerModeExpiresAt: null
      });
    }

    console.log('GET /recommendation-settings: Returning settings for user:', userId);
    res.json({
      country: data.recommendation_country,
      city: data.recommendation_city,
      district: data.recommendation_district,
      locations: data.recommendation_locations || [],
      radius: data.recommendation_radius || 0,
      autoLocation: data.recommendation_auto_location || false,
      promptShown: data.recommendation_prompt_shown || false,
      enabled: data.recommendation_enabled || false,
      explorerModeEnabled: data.explorer_mode_enabled || false,
      explorerModeExpiresAt: data.explorer_mode_expires_at
    });
  } catch (error) {
    console.error('GET /recommendation-settings: Error:', error);
    // Не возвращаем 400, возвращаем 500 для серверных ошибок
    res.status(500).json({ error: error.message || 'Internal server error' });
  }
});

// Get location suggestions (smart recommendations)
router.get('/location-suggestions', (req, res, next) => {
  console.log('GET /location-suggestions: Request received', {
    headers: req.headers,
    query: req.query,
    hasAuth: !!req.headers.authorization
  });
  next();
}, validateAuth, async (req, res) => {
  try {
    const userId = req.user?.id;
    
    if (!userId) {
      console.error('GET /location-suggestions: No user ID in request');
      return res.status(401).json({ error: 'User not authenticated' });
    }

    console.log('GET /location-suggestions: Fetching suggestions for user:', userId);

    // Get user's current locations
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('recommendation_locations')
      .eq('id', userId)
      .maybeSingle();

    // Если ошибка и это не "не найдено", выбрасываем ошибку
    if (profileError) {
      // PGRST116 - это код "не найдено" для maybeSingle, это нормально
      if (profileError.code !== 'PGRST116') {
        console.error('GET /location-suggestions: Profile error:', profileError);
        throw profileError;
      }
    }

    const currentLocations = profile?.recommendation_locations || [];
    const currentDistricts = currentLocations.map(loc => loc?.district).filter(Boolean);

    // Get interactions from last 7 days
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

    const { data: interactions, error: interactionsError } = await supabaseAdmin
      .from('location_interactions')
      .select('location_country, location_city, location_district')
      .eq('user_id', userId)
      .gte('created_at', sevenDaysAgo)
      .not('location_district', 'is', null);

    if (interactionsError) {
      console.error('GET /location-suggestions: Interactions error:', interactionsError);
      throw interactionsError;
    }

    // Если нет взаимодействий, возвращаем пустой массив
    if (!interactions || interactions.length === 0) {
      console.log('GET /location-suggestions: No interactions found, returning empty array');
      return res.json([]);
    }

    // Group by location and count interactions
    const locationCounts = {};
    interactions.forEach(interaction => {
      const key = `${interaction.location_district}|${interaction.location_city}|${interaction.location_country}`;
      if (!locationCounts[key]) {
        locationCounts[key] = {
          district: interaction.location_district,
          city: interaction.location_city,
          country: interaction.location_country,
          count: 0
        };
      }
      locationCounts[key].count++;
    });

    // Filter out current locations and sort by count
    const suggestions = Object.values(locationCounts)
      .filter(loc => !currentDistricts.includes(loc.district))
      .sort((a, b) => b.count - a.count)
      .slice(0, 3)
      .map(loc => ({
        district: loc.district,
        city: loc.city,
        country: loc.country,
        interactionCount: loc.count
      }));

    console.log('GET /location-suggestions: Returning', suggestions.length, 'suggestions');
    res.json(suggestions);
  } catch (error) {
    console.error('GET /location-suggestions: Error:', error);
    // Не возвращаем 400, возвращаем 500 для серверных ошибок
    res.status(500).json({ error: error.message || 'Internal server error' });
  }
});

// Get user profile by ID (параметрический маршрут должен быть ПОСЛЕ конкретных)
router.get('/:id', validateUUID, async (req, res) => {
  try {
    const { id } = req.params;

    // Get user profile
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', id)
      .single();

    if (profileError || !profile) {
      return res.status(404).json({ message: 'User not found' });
    }

    // Get followers count
    const { count: followersCount, error: followersError } = await supabase
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('following_id', id);

    if (followersError) throw followersError;

    // Get following count
    const { count: followingCount, error: followingError } = await supabase
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('follower_id', id);

    if (followingError) throw followingError;

    // Get posts count
    const { count: postsCount, error: postsError } = await supabase
      .from('posts')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', id);

    if (postsError) throw postsError;

    res.json({
      ...profile,
      followers_count: followersCount || 0,
      following_count: followingCount || 0,
      posts_count: postsCount || 0
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update user profile
router.put('/profile', validateAuth, upload.single('avatar'), validateProfileUpdate, async (req, res) => {
  try {
    const { username, name, bio, website_url } = req.body;
    const avatar = req.file;
    let avatarUrl = null;

    console.log('Update profile request:', { username, name, bio, website_url, hasAvatar: !!avatar });

    if (avatar) {
      // Сначала получаем текущий аватар пользователя для удаления
      const { data: currentProfile } = await supabaseAdmin
        .from('profiles')
        .select('avatar_url')
        .eq('id', req.user.id)
        .single();

      // Upload avatar to Supabase Storage
      console.log('Avatar file info:', {
        originalname: avatar.originalname,
        mimetype: avatar.mimetype,
        size: avatar.size
      });

      // Определяем расширение файла
      let fileExt = 'jpg'; // По умолчанию
      
      if (avatar.originalname && avatar.originalname.includes('.')) {
        fileExt = avatar.originalname.split('.').pop().toLowerCase();
      } else if (avatar.mimetype) {
        // Определяем расширение по MIME типу
        const mimeToExt = {
          'image/jpeg': 'jpg',
          'image/jpg': 'jpg',
          'image/png': 'png',
          'image/gif': 'gif',
          'image/webp': 'webp'
        };
        fileExt = mimeToExt[avatar.mimetype] || 'jpg';
      }

      // Проверяем, что расширение валидное
      const validExts = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
      if (!validExts.includes(fileExt)) {
        fileExt = 'jpg';
      }

      const fileName = `${Math.random().toString(36).substring(7)}.${fileExt}`;
      console.log('Generated filename:', fileName);

      const { error: uploadError } = await supabase.storage
        .from('avatars')
        .upload(fileName, avatar.buffer);

      if (uploadError) {
        console.error('Avatar upload error:', uploadError);
        throw uploadError;
      }

      // Get public URL for the uploaded avatar
      const { data: { publicUrl } } = supabase.storage
        .from('avatars')
        .getPublicUrl(fileName);

      avatarUrl = publicUrl;
      console.log('Avatar uploaded successfully:', avatarUrl);

      // Удаляем старый аватар, если он существует
      if (currentProfile?.avatar_url) {
        try {
          // Извлекаем имя файла из URL
          const oldFileName = currentProfile.avatar_url.split('/').pop();
          console.log('Deleting old avatar:', oldFileName);
          
          const { error: deleteError } = await supabaseAdmin.storage
            .from('avatars')
            .remove([oldFileName]);
          
          if (deleteError) {
            console.error('Error deleting old avatar:', deleteError);
            // Не прерываем выполнение, так как новый аватар уже загружен
          } else {
            console.log('Old avatar deleted successfully');
          }
        } catch (deleteErr) {
          console.error('Error deleting old avatar:', deleteErr);
          // Не прерываем выполнение, так как новый аватар уже загружен
        }
      }
    }

    const updates = {
      ...(username && { username }),
      ...(name && { name }),
      ...(bio !== undefined && { bio }),
      ...(website_url !== undefined && { website_url }),
      ...(avatarUrl && { avatar_url: avatarUrl }),
      updated_at: new Date()
    };

    console.log('Updates to apply:', updates);
    console.log('User ID:', req.user.id);

    // Сначала проверим, существует ли пользователь
    const { data: existingUser, error: checkError } = await supabaseAdmin
      .from('profiles')
      .select('id, username, name')
      .eq('id', req.user.id)
      .single();

    if (checkError) {
      console.error('User check error:', checkError);
      throw new Error(`User not found: ${checkError.message}`);
    }

    console.log('Existing user:', existingUser);

    const { data, error } = await supabaseAdmin
      .from('profiles')
      .update(updates)
      .eq('id', req.user.id)
      .select()
      .single();

    if (error) {
      console.error('Supabase update error:', error);
      throw error;
    }

    console.log('Profile updated successfully:', data);

    // Get updated profile with counts
    const { data: updatedProfile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('*')
      .eq('id', req.user.id)
      .single();

    if (profileError) throw profileError;

    // Get followers count
    const { count: followersCount, error: followersError } = await supabase
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('following_id', req.user.id);

    // Get following count
    const { count: followingCount, error: followingError } = await supabase
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('follower_id', req.user.id);

    // Get posts count
    const { count: postsCount, error: postsError } = await supabase
      .from('posts')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', req.user.id);

    res.json({
      ...updatedProfile,
      followers_count: followersCount || 0,
      following_count: followingCount || 0,
      posts_count: postsCount || 0
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Follow user
router.post('/follow/:id', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;
    const followerId = req.user.id;

    if (id === followerId) {
      return res.status(400).json({ message: 'Cannot follow yourself' });
    }

    const { error } = await supabase
      .from('follows')
      .insert([
        { follower_id: followerId, following_id: id }
      ]);

    if (error) throw error;

    res.json({ message: 'Successfully followed user' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Unfollow user
router.post('/unfollow/:id', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;
    const followerId = req.user.id;

    const { error } = await supabase
      .from('follows')
      .delete()
      .eq('follower_id', followerId)
      .eq('following_id', id);

    if (error) throw error;

    res.json({ message: 'Successfully unfollowed user' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get mutual followers (users who follow each other)
router.get('/mutual-followers', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    // Get users that current user follows
    const { data: following, error: followingError } = await supabaseAdmin
      .from('follows')
      .select('following_id')
      .eq('follower_id', userId);

    if (followingError) throw followingError;

    const followingIds = following.map(f => f.following_id);

    // Get users who follow current user
    const { data: followers, error: followersError } = await supabaseAdmin
      .from('follows')
      .select('follower_id')
      .eq('following_id', userId);

    if (followersError) throw followersError;

    const followerIds = followers.map(f => f.follower_id);

    // Mutual followers: users who follow us AND we follow them
    const mutualFollowerIds = followingIds.filter(id => followerIds.includes(id));

    // Get profiles of mutual followers
    let mutualFollowers = [];
    if (mutualFollowerIds.length > 0) {
      const { data: profiles, error: profilesError } = await supabaseAdmin
        .from('profiles')
        .select('id, username, name, avatar_url')
        .in('id', mutualFollowerIds);

      if (profilesError) throw profilesError;
      mutualFollowers = profiles || [];
    }

    res.json({ mutualFollowers });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get user posts
router.get('/:id/posts', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 10 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    // Check if user exists
    const { data: user, error: userError } = await supabaseAdmin
      .from('profiles')
      .select('id')
      .eq('id', id)
      .single();

    if (userError || !user) {
      return res.status(404).json({ message: 'User not found' });
    }

    const { data, error, count } = await supabaseAdmin
      .from('posts')
      .select(`
        *,
        profiles:user_id (username, name, avatar_url),
        likes(count),
        coauthor:coauthor_user_id (id, username, name, avatar_url)
      `, { count: 'exact' })
      .eq('user_id', id)
      .is('expires_at', null) // Исключаем сторис (посты с expires_at)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    // Get user's likes for all posts (if user is authenticated)
    let likedPostIds = new Set();
    const currentUserId = req.user?.id;
    if (currentUserId) {
      const postIds = data.map(post => post.id);
      const { data: userLikes, error: likesError } = await supabaseAdmin
        .from('likes')
        .select('post_id')
        .eq('user_id', currentUserId)
        .in('post_id', postIds);

      if (!likesError && userLikes) {
        likedPostIds = new Set(userLikes.map(like => like.post_id));
      }
    }

    // Transform data to include likes count, is_liked status, and coauthor
    const postsWithLikes = data.map(post => ({
      ...post,
      likes_count: post.likes?.[0]?.count || 0,
      is_liked: likedPostIds.has(post.id),
      likes: undefined // Remove the likes array from response
    }));

    res.json({
      posts: postsWithLikes,
      total: count,
      page: parseInt(page),
      totalPages: Math.ceil(count / limit)
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get saved posts
router.get('/me/saved', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { page = 1, limit = 20 } = req.query;
    const from = (page - 1) * limit;
    const to = from + parseInt(limit) - 1;

    // Get saved posts with post details (excluding stories)
    const { data: savedPosts, error: savedError } = await supabaseAdmin
      .from('saved_posts')
      .select(`
        post_id,
        created_at,
        posts:post_id (
          id,
          user_id,
          caption,
          media_url,
          media_type,
          thumbnail_url,
          created_at,
          updated_at,
          expires_at,
          profiles:user_id (
            id,
            username,
            name,
            avatar_url
          )
        )
      `)
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (savedError) throw savedError;

    // Get counts for each post (filter out stories)
    const postsWithCounts = await Promise.all(
      (savedPosts || []).map(async (savedPost) => {
        const post = savedPost.posts;
        if (!post) return null;
        
        // Исключаем сторис (посты с expires_at)
        if (post.expires_at != null) return null;

        // Get likes count
        const { count: likesCount } = await supabaseAdmin
          .from('likes')
          .select('*', { count: 'exact', head: true })
          .eq('post_id', post.id);

        // Get comments count
        const { count: commentsCount } = await supabaseAdmin
          .from('comments')
          .select('*', { count: 'exact', head: true })
          .eq('post_id', post.id)
          .is('parent_comment_id', null);

        // Check if current user liked this post
        const { data: userLike } = await supabaseAdmin
          .from('likes')
          .select('id')
          .eq('post_id', post.id)
          .eq('user_id', userId)
          .single();

        return {
          ...post,
          likesCount: likesCount || 0,
          commentsCount: commentsCount || 0,
          isLiked: !!userLike,
          isSaved: true,
        };
      })
    );

    // Filter out nulls and get total count
    const filteredPosts = postsWithCounts.filter(p => p !== null);

    const { count } = await supabaseAdmin
      .from('saved_posts')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId);

    res.json({
      posts: filteredPosts,
      page: parseInt(page),
      limit: parseInt(limit),
      total: count || 0,
      totalPages: Math.ceil((count || 0) / limit)
    });
  } catch (error) {
    console.error('Error getting saved posts:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get liked posts
router.get('/me/liked', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { page = 1, limit = 20 } = req.query;
    const from = (page - 1) * limit;
    const to = from + parseInt(limit) - 1;

    // Get liked posts with post details (excluding stories)
    const { data: likedPosts, error: likedError } = await supabaseAdmin
      .from('likes')
      .select(`
        post_id,
        created_at,
        posts:post_id (
          id,
          user_id,
          caption,
          media_url,
          media_type,
          thumbnail_url,
          created_at,
          updated_at,
          expires_at,
          profiles:user_id (
            id,
            username,
            name,
            avatar_url
          )
        )
      `)
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (likedError) throw likedError;

    // Get counts for each post (filter out stories)
    const postsWithCounts = await Promise.all(
      (likedPosts || []).map(async (likedPost) => {
        const post = likedPost.posts;
        if (!post) return null;
        
        // Исключаем сторис (посты с expires_at)
        if (post.expires_at != null) return null;

        // Get likes count
        const { count: likesCount } = await supabaseAdmin
          .from('likes')
          .select('*', { count: 'exact', head: true })
          .eq('post_id', post.id);

        // Get comments count
        const { count: commentsCount } = await supabaseAdmin
          .from('comments')
          .select('*', { count: 'exact', head: true })
          .eq('post_id', post.id)
          .is('parent_comment_id', null);

        // Check if current user saved this post
        const { data: userSave } = await supabaseAdmin
          .from('saved_posts')
          .select('id')
          .eq('post_id', post.id)
          .eq('user_id', userId)
          .single();

        return {
          ...post,
          likesCount: likesCount || 0,
          commentsCount: commentsCount || 0,
          isLiked: true, // Always true since these are liked posts
          isSaved: !!userSave,
        };
      })
    );

    // Filter out nulls and get total count
    const filteredPosts = postsWithCounts.filter(p => p !== null);

    const { count } = await supabaseAdmin
      .from('likes')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId);

    res.json({
      posts: filteredPosts,
      page: parseInt(page),
      limit: parseInt(limit),
      total: count || 0,
      totalPages: Math.ceil((count || 0) / limit)
    });
  } catch (error) {
    console.error('Error getting liked posts:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// Обновить статус онлайн (heartbeat)
// ==============================================
router.post('/heartbeat', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const now = new Date().toISOString();

    const { error } = await supabaseAdmin
      .from('profiles')
      .update({
        is_online: true,
        last_seen: now,
      })
      .eq('id', userId);

    if (error) {
      console.error('Error updating online status:', error);
      return res.status(500).json({ error: error.message });
    }

    res.json({ success: true, last_seen: now });
  } catch (error) {
    console.error('Error in heartbeat:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// Получить статус пользователя (онлайн/последний заход)
// ==============================================
router.get('/:userId/status', validateAuth, async (req, res) => {
  try {
    const { userId } = req.params;
    const currentUserId = req.user.id;

    // Получаем данные пользователя
    const { data: user, error: userError } = await supabaseAdmin
      .from('profiles')
      .select('id, is_online, last_seen, show_online_status')
      .eq('id', userId)
      .single();

    if (userError || !user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // ПРОВЕРКА: Если last_seen старше ONLINE_THRESHOLD, принудительно ставим is_online = false
    const lastSeenDate = new Date(user.last_seen);
    const now = new Date();
    const timeSinceLastSeen = now - lastSeenDate;
    
    let isActuallyOnline = user.is_online;
    
    // Если прошло больше ONLINE_THRESHOLD с последнего heartbeat - пользователь ОФЛАЙН
    if (timeSinceLastSeen > ONLINE_THRESHOLD) {
      logger.users(`User ${userId} is OFFLINE (last seen ${timeSinceLastSeen}ms ago, threshold: ${ONLINE_THRESHOLD}ms)`, {
        userId,
        timeSinceLastSeen,
        threshold: ONLINE_THRESHOLD,
      });
      isActuallyOnline = false;
      
      // Обновляем в БД чтобы не проверять каждый раз
      await supabaseAdmin
        .from('profiles')
        .update({ is_online: false })
        .eq('id', userId);
    } else {
      logger.users(`User ${userId} is ONLINE (last seen ${timeSinceLastSeen}ms ago)`, {
        userId,
        timeSinceLastSeen,
      });
    }

    // Получаем настройку приватности текущего пользователя
    const { data: currentUser, error: currentUserError } = await supabaseAdmin
      .from('profiles')
      .select('show_online_status')
      .eq('id', currentUserId)
      .single();

    if (currentUserError) {
      console.error('Error fetching current user settings:', currentUserError);
    }

    // Если у текущего пользователя отключен показ статуса, показываем приблизительное время для всех
    const showExactTime = currentUser?.show_online_status !== false && user.show_online_status !== false;

    // Если пользователь онлайн (реально онлайн!), всегда показываем это
    if (isActuallyOnline) {
      return res.json({
        is_online: true,
        last_seen: user.last_seen,
        status_text: 'online',
      });
    }

    // Если пользователь оффлайн
    const diff = timeSinceLastSeen;

    let statusText;
    if (showExactTime) {
      // Показываем точное время
      if (diff < RECENTLY_THRESHOLD) {
        statusText = 'recently';
      } else if (diff < THIS_WEEK_THRESHOLD) {
        statusText = 'this week';
      } else if (diff < THIS_MONTH_THRESHOLD) {
        statusText = 'this month';
      } else {
        statusText = 'long ago';
      }
    } else {
      // Показываем приблизительное время
      if (diff < THIS_WEEK_THRESHOLD) {
        statusText = 'recently';
      } else if (diff < THIS_MONTH_THRESHOLD) {
        statusText = 'this week';
      } else {
        statusText = 'long ago';
      }
    }

    res.json({
      is_online: false,
      last_seen: showExactTime ? user.last_seen : null,
      status_text: statusText,
    });
  } catch (error) {
    console.error('Error getting user status:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// Установить статус офлайн (при выходе из приложения)
// ==============================================
router.post('/set-offline', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    const { error } = await supabaseAdmin
      .from('profiles')
      .update({
        is_online: false,
      })
      .eq('id', userId);

    if (error) {
      console.error('Error setting offline status:', error);
      return res.status(500).json({ error: error.message });
    }

    console.log(`[SetOffline] User ${userId} is now offline`);
    res.json({ success: true });
  } catch (error) {
    console.error('Error in set-offline:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// Обновить настройку приватности онлайн-статуса
// ==============================================
router.put('/settings/online-status', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { show_online_status } = req.body;

    if (typeof show_online_status !== 'boolean') {
      return res.status(400).json({ error: 'show_online_status must be a boolean' });
    }

    const { data, error } = await supabaseAdmin
      .from('profiles')
      .update({ show_online_status })
      .eq('id', userId)
      .select()
      .single();

    if (error) {
      console.error('Error updating online status setting:', error);
      return res.status(500).json({ error: error.message });
    }

    res.json(data);
  } catch (error) {
    console.error('Error updating online status setting:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// Location Sharing Endpoints
// ==============================================

// Update user's current location
router.post('/location', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { latitude, longitude } = req.body;

    console.log('Update location request:', {
      userId,
      latitude,
      longitude,
      hasLatitude: !!latitude,
      hasLongitude: !!longitude
    });

    if (!latitude || !longitude) {
      console.log('Update location: Missing latitude or longitude');
      return res.status(400).json({ error: 'Latitude and longitude are required' });
    }

    // Проверяем, включен ли location sharing
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('location_sharing_enabled')
      .eq('id', userId)
      .single();

    if (profileError) {
      console.error('Update location: Error fetching profile:', profileError);
      throw profileError;
    }

    console.log('Update location: Profile location_sharing_enabled:', profile?.location_sharing_enabled);

    if (!profile?.location_sharing_enabled) {
      console.log('Update location: Location sharing is not enabled for user');
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

    if (error) {
      console.error('Update location: Error updating profile:', error);
      throw error;
    }

    console.log('Update location: ✅ Successfully updated location for user', userId);
    res.json({ success: true });
  } catch (error) {
    console.error('Update location: Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Toggle location sharing
router.post('/location/sharing', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { enabled } = req.body;

    if (typeof enabled !== 'boolean') {
      return res.status(400).json({ error: 'enabled must be a boolean' });
    }

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

// Get location visibility setting
router.get('/location/visibility', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    const { data: profile, error } = await supabaseAdmin
      .from('profiles')
      .select('location_visibility, location_sharing_enabled')
      .eq('id', userId)
      .single();

    if (error) throw error;

    res.json({
      location_visibility: profile?.location_visibility || 'mutual_followers',
      location_sharing_enabled: profile?.location_sharing_enabled || false,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update location visibility setting
router.put('/location/visibility', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { location_visibility } = req.body;

    const validValues = ['nobody', 'mutual_followers', 'followers', 'close_friends'];
    if (!validValues.includes(location_visibility)) {
      return res.status(400).json({ 
        error: `location_visibility must be one of: ${validValues.join(', ')}` 
      });
    }

    const { data, error } = await supabaseAdmin
      .from('profiles')
      .update({ location_visibility })
      .eq('id', userId)
      .select()
      .single();

    if (error) throw error;

    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get friends' locations (filtered by visibility setting)
router.get('/friends/locations', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    // Get current user's location visibility setting
    const { data: currentUserProfile } = await supabaseAdmin
      .from('profiles')
      .select('location_visibility')
      .eq('id', userId)
      .single();

    const visibility = currentUserProfile?.location_visibility || 'mutual_followers';

    // Get users based on visibility setting
    let visibleUserIds = [];

    if (visibility === 'nobody') {
      // Nobody can see location
      console.log('Friends locations request:', {
        userId,
        visibility,
        visibleUserIdsCount: 0,
        friendsWithLocations: 0
      });
      return res.json({ friends: [] });
    } else if (visibility === 'mutual_followers') {
      // Only mutual followers
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
      visibleUserIds = followingIds.filter(id => followerIds.includes(id));
    } else if (visibility === 'followers') {
      // All followers
      const { data: followers } = await supabaseAdmin
        .from('follows')
        .select('follower_id')
        .eq('following_id', userId);

      visibleUserIds = followers.map(f => f.follower_id);
    } else if (visibility === 'close_friends') {
      // Only close friends
      const { data: closeFriends } = await supabaseAdmin
        .from('close_friends')
        .select('friend_id')
        .eq('user_id', userId);

      visibleUserIds = closeFriends.map(f => f.friend_id);
    }

    if (visibleUserIds.length === 0) {
      console.log('Friends locations request:', {
        userId,
        visibility,
        visibleUserIdsCount: 0,
        friendsWithLocations: 0
      });
      return res.json({ friends: [] });
    }

    // Get profiles of visible users with enabled location sharing
    const { data: friends, error } = await supabaseAdmin
      .from('profiles')
      .select('id, username, name, avatar_url, last_location_lat, last_location_lng, last_location_updated_at')
      .in('id', visibleUserIds)
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

    console.log('Friends locations request:', {
      userId,
      visibility,
      visibleUserIdsCount: visibleUserIds.length,
      friendsWithLocations: friendsLocations.length,
      friends: friendsLocations.map(f => ({ username: f.username, hasLocation: !!(f.latitude && f.longitude) }))
    });

    res.json({ friends: friendsLocations });
  } catch (error) {
    console.error('Error in /friends/locations:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==============================================
// Close Friends Endpoints
// ==============================================

// Get close friends list
router.get('/close-friends', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    const { data: closeFriends, error } = await supabaseAdmin
      .from('close_friends')
      .select(`
        friend_id,
        profiles:friend_id (
          id,
          username,
          name,
          avatar_url
        )
      `)
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (error) throw error;

    const friends = (closeFriends || []).map(cf => ({
      id: cf.profiles?.id,
      username: cf.profiles?.username,
      name: cf.profiles?.name,
      avatar_url: cf.profiles?.avatar_url,
    })).filter(f => f.id != null);

    res.json({ close_friends: friends });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Add user to close friends
router.post('/close-friends/:friendId', validateAuth, validateFriendId, async (req, res) => {
  try {
    const userId = req.user.id;
    const { friendId } = req.params;

    if (userId === friendId) {
      return res.status(400).json({ error: 'Cannot add yourself to close friends' });
    }

    // Check if user exists
    const { data: friend } = await supabaseAdmin
      .from('profiles')
      .select('id')
      .eq('id', friendId)
      .single();

    if (!friend) {
      return res.status(404).json({ error: 'User not found' });
    }

    const { error } = await supabaseAdmin
      .from('close_friends')
      .insert([{
        user_id: userId,
        friend_id: friendId,
      }]);

    if (error) {
      if (error.code === '23505') { // Unique constraint violation
        return res.status(400).json({ error: 'User is already in close friends' });
      }
      throw error;
    }

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Remove user from close friends
router.delete('/close-friends/:friendId', validateAuth, validateFriendId, async (req, res) => {
  try {
    const userId = req.user.id;
    const { friendId } = req.params;

    const { error } = await supabaseAdmin
      .from('close_friends')
      .delete()
      .eq('user_id', userId)
      .eq('friend_id', friendId);

    if (error) throw error;

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update FCM token
router.put('/fcm-token', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { fcm_token } = req.body;

    if (typeof fcm_token !== 'string') {
      return res.status(400).json({ error: 'fcm_token must be a string' });
    }

    // Update FCM token in profile (empty string means remove token)
    const tokenValue = fcm_token.trim() === '' ? null : fcm_token;
    const { error: updateError } = await supabaseAdmin
      .from('profiles')
      .update({ fcm_token: tokenValue })
      .eq('id', userId);

    if (updateError) {
      console.error('Error updating FCM token:', updateError);
      return res.status(500).json({ error: 'Failed to update FCM token' });
    }

    console.log(`[FCM] FCM token updated for user ${userId}`);
    res.json({ success: true, message: 'FCM token updated successfully' });
  } catch (error) {
    console.error('Error updating FCM token:', error);
    res.status(500).json({ error: error.message });
  }
});

// Update recommendation settings
router.put('/recommendation-settings', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { locations, radius, auto_location, enabled } = req.body;

    // Validate locations (max 3)
    if (locations && (!Array.isArray(locations) || locations.length > 3)) {
      return res.status(400).json({ error: 'locations must be an array with maximum 3 items' });
    }

    // Validate radius (0-100000 meters)
    if (radius !== undefined && (typeof radius !== 'number' || radius < 0 || radius > 100000)) {
      return res.status(400).json({ error: 'radius must be between 0 and 100000 meters' });
    }

    const updateData = {
      recommendation_prompt_shown: true
    };

    if (locations !== undefined) {
      updateData.recommendation_locations = locations;
      // Also update individual fields for backward compatibility
      if (locations.length > 0) {
        updateData.recommendation_country = locations[0].country || null;
        updateData.recommendation_city = locations[0].city || null;
        updateData.recommendation_district = locations[0].district || null;
      }
    }

    if (radius !== undefined) {
      updateData.recommendation_radius = radius;
    }

    if (auto_location !== undefined) {
      updateData.recommendation_auto_location = auto_location;
    }

    if (enabled !== undefined) {
      updateData.recommendation_enabled = enabled;
    }

    const { error } = await supabaseAdmin
      .from('profiles')
      .update(updateData)
      .eq('id', userId);

    if (error) throw error;

    res.json({ success: true });
  } catch (error) {
    console.error('Error updating recommendation settings:', error);
    res.status(500).json({ error: error.message });
  }
});

// Auto-detect location
router.post('/auto-detect-location', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { latitude, longitude } = req.body;

    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      return res.status(400).json({ error: 'latitude and longitude must be numbers' });
    }

    // Call Nominatim API for reverse geocoding
    const nominatimUrl = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}&addressdetails=1&accept-language=ro`;
    
    const response = await fetch(nominatimUrl, {
      headers: {
        'User-Agent': 'FuisorApp/1.0'
      }
    });

    if (!response.ok) {
      throw new Error('Failed to fetch location data');
    }

    const data = await response.json();
    const address = data.address || {};

    // Extract location info
    let country = address.country || null;
    let city = address.city || address.town || address.village || null;
    let district = address.suburb || address.neighbourhood || address.quarter || null;

    // Special handling for Moldovan districts
    if (data.display_name) {
      const displayLower = data.display_name.toLowerCase();
      if (displayLower.includes('ботаника') || displayLower.includes('botanica')) {
        district = 'Botanica';
      } else if (displayLower.includes('центр') || displayLower.includes('centru')) {
        district = 'Centru';
      } else if (displayLower.includes('ришкановка') || displayLower.includes('riscani')) {
        district = 'Rîșcani';
      } else if (displayLower.includes('чеканы') || displayLower.includes('ciocana')) {
        district = 'Ciocana';
      } else if (displayLower.includes('буюканы') || displayLower.includes('buiucani')) {
        district = 'Buiucani';
      }
    }

    // Update user's recommendation settings
    const { error: updateError } = await supabaseAdmin
      .from('profiles')
      .update({
        recommendation_country: country,
        recommendation_city: city,
        recommendation_district: district,
        recommendation_locations: [{ country, city, district }],
        recommendation_enabled: true,
        recommendation_prompt_shown: true,
        last_location_lat: latitude,
        last_location_lng: longitude,
        last_location_updated_at: new Date().toISOString()
      })
      .eq('id', userId);

    if (updateError) throw updateError;

    res.json({
      country,
      city,
      district
    });
  } catch (error) {
    console.error('Error auto-detecting location:', error);
    res.status(500).json({ error: error.message });
  }
});

// Toggle explorer mode
router.post('/toggle-explorer-mode', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const { enabled } = req.body;

    if (typeof enabled !== 'boolean') {
      return res.status(400).json({ error: 'enabled must be a boolean' });
    }

    const updateData = {
      explorer_mode_enabled: enabled
    };

    if (enabled) {
      // Set expiration to 15 minutes from now
      const expiresAt = new Date(Date.now() + 15 * 60 * 1000);
      updateData.explorer_mode_expires_at = expiresAt.toISOString();
    } else {
      updateData.explorer_mode_expires_at = null;
    }

    const { error } = await supabaseAdmin
      .from('profiles')
      .update(updateData)
      .eq('id', userId);

    if (error) throw error;

    res.json({
      enabled,
      expiresAt: updateData.explorer_mode_expires_at
    });
  } catch (error) {
    console.error('Error toggling explorer mode:', error);
    res.status(500).json({ error: error.message });
  }
});

// Mark recommendation prompt as shown
router.post('/mark-recommendation-prompt-shown', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;

    const { error } = await supabaseAdmin
      .from('profiles')
      .update({ recommendation_prompt_shown: true })
      .eq('id', userId);

    if (error) throw error;

    res.json({ success: true });
  } catch (error) {
    console.error('Error marking prompt as shown:', error);
    res.status(500).json({ error: error.message });
  }
});

// Получить список всех городов из таблицы locations
// Автоматически парсит и синхронизирует все локации из таблицы постов
router.get('/locations/cities', validateAuth, async (req, res) => {
  try {
    const { country = 'Moldova' } = req.query;
    
    console.log('Parsing cities from posts table and syncing locations...');
    
    // Функции нормализации (вынесены в начало)
    const normalizeCountry = (country) => {
      if (!country) return null;
      const countryLower = country.toLowerCase().trim();
      if (countryLower === 'молдова' || countryLower === 'молдавия' || countryLower === 'moldova') {
        return 'Moldova';
      }
      return country;
    };
    
    const normalizeCity = (city) => {
      if (!city) return null;
      const cityLower = city.toLowerCase().trim();
      // Нормализуем варианты написания Кишинева
      if (cityLower === 'кишинёв' || cityLower === 'кишинев' || cityLower === 'chisinau' || cityLower === 'chișinău') {
        return 'Chișinău';
      }
      return city;
    };
    
    const normalizeDistrict = (district) => {
      if (!district) return null;
      const districtLower = district.toLowerCase().trim();
      // Нормализуем варианты написания районов
      if (districtLower === 'ботаника' || districtLower === 'сектор ботаника' || districtLower === 'botanica') {
        return 'Botanica';
      }
      if (districtLower === 'центру' || districtLower === 'центр' || districtLower === 'centru') {
        return 'Centru';
      }
      if (districtLower === 'ришкан' || districtLower === 'ришканский' || districtLower === 'rîșcani' || districtLower === 'riscani') {
        return 'Rîșcani';
      }
      if (districtLower === 'чокана' || districtLower === 'ciocana') {
        return 'Ciocana';
      }
      if (districtLower === 'буюкань' || districtLower === 'буюкани' || districtLower === 'buiucani') {
        return 'Buiucani';
      }
      return district;
    };
    
    const postsLocationsMap = new Map();
    postsLocations.forEach(post => {
      // Нормализуем значения
      const normalizedCountry = normalizeCountry(post.country);
      const normalizedCity = normalizeCity(post.city);
      const normalizedDistrict = normalizeDistrict(post.district);
      
      // Используем нормализованные значения для ключа
      const key = `${normalizedCountry}|${normalizedCity || ''}|${normalizedDistrict || ''}`;
      const existing = postsLocationsMap.get(key) || {
        country: normalizedCountry,
        city: normalizedCity,
        district: normalizedDistrict,
        count: 0
      };
      existing.count++;
      postsLocationsMap.set(key, existing);
    });
    
    console.log(`Found ${postsLocationsMap.size} unique locations in posts`);
    
    // 3. Получаем существующие локации из таблицы locations
    const { data: existingLocations, error: locError } = await supabaseAdmin
      .from('locations')
      .select('id, country, city, district, post_count');
    
    if (locError) throw locError;
    
    // 4. Создаем Map существующих локаций для быстрой проверки и обновления
    const existingLocationsMap = new Map();
    existingLocations.forEach(loc => {
      const key = `${loc.country}|${loc.city || ''}|${loc.district || ''}`;
      existingLocationsMap.set(key, loc);
    });
    
    console.log(`Found ${existingLocationsMap.size} locations in database`);
    
    // 5. Находим недостающие локации и локации, которые нужно обновить
    const missingLocations = [];
    const locationsToUpdate = [];
    
    postsLocationsMap.forEach((loc, key) => {
      const existing = existingLocationsMap.get(key);
      if (!existing) {
        // Новая локация - добавляем
        missingLocations.push({
          country: loc.country,
          city: loc.city || null,
          district: loc.district || null,
          post_count: loc.count
        });
      } else {
        // Существующая локация - обновляем счетчик, если он изменился
        if (existing.post_count !== loc.count) {
          locationsToUpdate.push({
            id: existing.id,
            post_count: loc.count
          });
        }
      }
    });
    
    // 6. Добавляем недостающие локации
    if (missingLocations.length > 0) {
      console.log(`Adding ${missingLocations.length} missing locations to database`);
      const { error: insertError } = await supabaseAdmin
        .from('locations')
        .insert(missingLocations);
      
      if (insertError) {
        console.error('Error inserting missing locations:', insertError);
        // Не бросаем ошибку, продолжаем работу
      } else {
        console.log(`Successfully added ${missingLocations.length} locations`);
      }
    }
    
    // 7. Обновляем счетчики для существующих локаций
    if (locationsToUpdate.length > 0) {
      console.log(`Updating post_count for ${locationsToUpdate.length} existing locations`);
      for (const loc of locationsToUpdate) {
        await supabaseAdmin
          .from('locations')
          .update({ 
            post_count: loc.post_count,
            updated_at: new Date().toISOString()
          })
          .eq('id', loc.id);
      }
      console.log(`Successfully updated ${locationsToUpdate.length} locations`);
    }
    
    // 8. Получаем финальный список городов для запрошенной страны
    // Учитываем все варианты названий Молдовы
    const normalizedCountry = normalizeCountry(country);
    const moldovaVariants = ['Moldova', 'Молдова', 'Молдавия'];
    const isMoldova = moldovaVariants.includes(normalizedCountry);
    
    let finalData;
    if (isMoldova) {
      // Если запрашивают Молдову, возвращаем города из всех вариантов названий
      const { data, error: finalError } = await supabaseAdmin
        .from('locations')
        .select('city, post_count')
        .in('country', moldovaVariants)
        .not('city', 'is', null)
        .order('post_count', { ascending: false });
      
      if (finalError) throw finalError;
      finalData = data;
    } else {
      // Для других стран - обычная фильтрация
      const { data, error: finalError } = await supabaseAdmin
        .from('locations')
        .select('city, post_count')
        .eq('country', normalizedCountry)
        .not('city', 'is', null)
        .order('post_count', { ascending: false });
      
      if (finalError) throw finalError;
      finalData = data;
    }
    
    // 9. Группируем по городам и суммируем post_count
    const citiesMap = new Map();
    finalData.forEach(item => {
      if (item.city) {
        const existing = citiesMap.get(item.city) || 0;
        citiesMap.set(item.city, existing + (item.post_count || 0));
      }
    });
    
    // 10. Преобразуем в массив и сортируем
    const cities = Array.from(citiesMap.keys()).sort();
    
    console.log(`Returning ${cities.length} cities for ${country}`);
    
    res.json({ 
      cities, 
      synced: missingLocations.length,
      updated: locationsToUpdate.length 
    });
  } catch (error) {
    console.error('Error getting cities:', error);
    res.status(500).json({ error: error.message });
  }
});

// Получить список районов для конкретного города
// Также синхронизирует локации из постов перед возвратом
router.get('/locations/districts', validateAuth, async (req, res) => {
  try {
    const { city, country = 'Moldova' } = req.query;
    
    if (!city) {
      return res.status(400).json({ error: 'City parameter is required' });
    }
    
    console.log(`Fetching districts for city: ${city}, syncing from posts...`);
    
    // 1. Получаем все локации из постов для этого города
    const { data: postsLocations, error: postsError } = await supabaseAdmin
      .from('posts')
      .select('country, city, district')
      .eq('country', country)
      .eq('city', city)
      .not('district', 'is', null);
    
    if (postsError) throw postsError;
    
    // 3. Группируем локации из постов с нормализацией
    const postsLocationsMap = new Map();
    postsLocations.forEach(post => {
      // Нормализуем значения
      const normCountry = normalizeCountry(post.country);
      const normCity = normalizeCity(post.city);
      const normDistrict = normalizeDistrict(post.district);
      
      const key = `${normCountry}|${normCity || ''}|${normDistrict || ''}`;
      const existing = postsLocationsMap.get(key) || {
        country: normCountry,
        city: normCity,
        district: normDistrict,
        count: 0
      };
      existing.count++;
      postsLocationsMap.set(key, existing);
    });
    
    // 4. Получаем существующие локации из таблицы locations (с учетом всех вариантов)
    let existingLocations;
    if (isMoldova) {
      const { data, error: locError } = await supabaseAdmin
        .from('locations')
        .select('id, country, city, district, post_count')
        .in('country', moldovaVariants)
        .in('city', cityVariants);
      
      if (locError) throw locError;
      existingLocations = data;
    } else {
      const { data, error: locError } = await supabaseAdmin
        .from('locations')
        .select('id, country, city, district, post_count')
        .eq('country', normalizedCountry)
        .in('city', cityVariants);
      
      if (locError) throw locError;
      existingLocations = data;
    }
    
    // 4. Создаем Map существующих локаций
    const existingLocationsMap = new Map();
    existingLocations.forEach(loc => {
      const key = `${loc.country}|${loc.city || ''}|${loc.district || ''}`;
      existingLocationsMap.set(key, loc);
    });
    
    // 5. Находим недостающие локации и обновляем счетчики
    const missingLocations = [];
    const locationsToUpdate = [];
    
    postsLocationsMap.forEach((loc, key) => {
      const existing = existingLocationsMap.get(key);
      if (!existing) {
        missingLocations.push({
          country: loc.country,
          city: loc.city || null,
          district: loc.district || null,
          post_count: loc.count
        });
      } else if (existing.post_count !== loc.count) {
        locationsToUpdate.push({
          id: existing.id,
          post_count: loc.count
        });
      }
    });
    
    // 6. Добавляем недостающие локации
    if (missingLocations.length > 0) {
      console.log(`Adding ${missingLocations.length} missing districts for ${city}`);
      await supabaseAdmin
        .from('locations')
        .insert(missingLocations);
    }
    
    // 7. Обновляем счетчики
    if (locationsToUpdate.length > 0) {
      for (const loc of locationsToUpdate) {
        await supabaseAdmin
          .from('locations')
          .update({ 
            post_count: loc.post_count,
            updated_at: new Date().toISOString()
          })
          .eq('id', loc.id);
      }
    }
    
    // 8. Получаем финальный список районов (с учетом всех вариантов)
    let finalData;
    if (isMoldova) {
      const { data, error: finalError } = await supabaseAdmin
        .from('locations')
        .select('district, post_count')
        .in('country', moldovaVariants)
        .in('city', cityVariants)
        .not('district', 'is', null)
        .order('post_count', { ascending: false });
      
      if (finalError) throw finalError;
      finalData = data;
    } else {
      const { data, error: finalError } = await supabaseAdmin
        .from('locations')
        .select('district, post_count')
        .eq('country', normalizedCountry)
        .in('city', cityVariants)
        .not('district', 'is', null)
        .order('post_count', { ascending: false });
      
      if (finalError) throw finalError;
      finalData = data;
    }
    
    // 9. Группируем по районам и суммируем post_count
    const districtsMap = new Map();
    finalData.forEach(item => {
      if (item.district) {
        const existing = districtsMap.get(item.district) || 0;
        districtsMap.set(item.district, existing + (item.post_count || 0));
      }
    });
    
    // 10. Преобразуем в массив и сортируем
    const districts = Array.from(districtsMap.keys()).sort();
    
    console.log(`Returning ${districts.length} districts for ${city}`);
    
    res.json({ 
      districts,
      synced: missingLocations.length,
      updated: locationsToUpdate.length
    });
  } catch (error) {
    console.error('Error getting districts:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;