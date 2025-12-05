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

// Get user profile by ID
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
        post_coauthors!left (
          profiles:coauthor_user_id (id, username, name, avatar_url)
        )
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
      likes: undefined, // Remove the likes array from response
      coauthor: post.post_coauthors?.[0]?.profiles || post.post_coauthors?.[0]?.coauthor || null,
      post_coauthors: undefined // Remove the raw coauthors array
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

export default router;