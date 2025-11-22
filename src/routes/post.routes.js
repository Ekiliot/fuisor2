import express from 'express';
import multer from 'multer';
import { supabase, supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { validatePost, validatePostUpdate, validateComment, validateUUID, validateCommentId } from '../middleware/validation.middleware.js';
import { createNotification } from './notification.routes.js';
import { logger } from '../utils/logger.js';

const router = express.Router();

// Multer setup for media uploads
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 100 * 1024 * 1024, // 100MB max (Vercel limit is 4.5MB for request body, but we'll stream to Supabase)
  },
});

// Логирование всех POST запросов к /posts
router.use('/', (req, res, next) => {
  if (req.method === 'POST') {
    logger.post('POST request to /posts', {
      method: req.method,
      url: req.url,
      bodyKeys: Object.keys(req.body || {})
    });
  }
  next();
});

// Get all posts (with pagination)
router.get('/', validateAuth, async (req, res) => {
  try {
    const { page = 1, limit = 10 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;
    const userId = req.user.id;

    const { data, error, count } = await supabaseAdmin
      .from('posts')
      .select(`
        *,
        profiles:user_id (username, name, avatar_url),
        likes(count)
      `, { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    // Get user's likes for all posts
    const postIds = data.map(post => post.id);
    const { data: userLikes, error: likesError } = await supabaseAdmin
      .from('likes')
      .select('post_id')
      .eq('user_id', userId)
      .in('post_id', postIds);

    if (likesError) throw likesError;

    const likedPostIds = new Set(userLikes.map(like => like.post_id));

    // Transform data to include likes count and is_liked status
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

// Upload media file (image or video) - returns URL
router.post('/upload-media', validateAuth, upload.single('media'), async (req, res) => {
  try {
    const file = req.file;
    const { mediaType } = req.body; // 'image' or 'video'
    
    if (!file) {
      return res.status(400).json({ error: 'No file provided' });
    }

    if (!mediaType || !['image', 'video'].includes(mediaType)) {
      return res.status(400).json({ error: 'Media type must be "image" or "video"' });
    }

    // Security: Validate MIME type
    const allowedMimeTypes = {
      image: ['image/jpeg', 'image/png', 'image/gif', 'image/webp'],
      video: ['video/mp4', 'video/webm', 'video/quicktime', 'video/x-msvideo']
    };
    
    const allowedMimes = allowedMimeTypes[mediaType];
    if (!allowedMimes || !allowedMimes.includes(file.mimetype)) {
      logger.postError('Invalid MIME type', {
      userId: req.user.id,
        mediaType,
        mimetype: file.mimetype,
        allowed: allowedMimes
      });
      return res.status(400).json({ 
        error: `Invalid MIME type for ${mediaType}. Expected: ${allowedMimes.join(', ')}, got: ${file.mimetype}` 
      });
    }

    // Security: Validate file extension
    const fileExt = file.originalname.split('.').pop()?.toLowerCase();
    const allowedExts = mediaType === 'image' 
      ? ['jpg', 'jpeg', 'png', 'gif', 'webp']
      : ['mp4', 'webm', 'mov', 'avi'];

    if (!fileExt || !allowedExts.includes(fileExt)) {
      logger.postError('Invalid file extension', {
        userId: req.user.id,
        mediaType,
        extension: fileExt,
        allowed: allowedExts
      });
      return res.status(400).json({ 
        error: `Invalid file extension. Allowed for ${mediaType}: ${allowedExts.join(', ')}, got: ${fileExt || 'none'}` 
      });
    }

    // Security: Sanitize file name (prevent path traversal)
    const sanitizedExt = fileExt.replace(/[^a-z0-9]/gi, '');
    if (sanitizedExt !== fileExt) {
      return res.status(400).json({ error: 'Invalid file extension format' });
    }

    logger.post('Media upload request', {
      userId: req.user.id,
      mediaType,
      fileName: file.originalname,
      fileSize: file.size,
      mimetype: file.mimetype,
      extension: fileExt,
    });

    const fileName = `post_${req.user.id}_${Date.now()}.${fileExt}`;

    // Upload to Supabase Storage
    const { data: uploadData, error: uploadError } = await supabaseAdmin
      .storage
      .from('post-media')
      .upload(fileName, file.buffer, {
        contentType: file.mimetype,
        upsert: false,
      });

    if (uploadError) {
      logger.postError('Error uploading media to Supabase', uploadError);
      return res.status(500).json({ error: 'Failed to upload media: ' + uploadError.message });
    }

    // Bucket is private, so we return the file path instead of public URL
    // Signed URL will be obtained via API when needed
    const mediaPath = uploadData.path || fileName;

    logger.post('Media uploaded successfully', {
      userId: req.user.id,
      fileName,
      mediaPath,
    });

    // Return the file path (not public URL) since bucket is private
    res.json({ mediaUrl: mediaPath });
  } catch (error) {
    logger.postError('Error in upload-media endpoint', error);
    res.status(500).json({ error: error.message });
    }
});

// Upload thumbnail - returns URL
router.post('/upload-thumbnail', validateAuth, upload.single('thumbnail'), async (req, res) => {
  try {
    const file = req.file;
    
    if (!file) {
      return res.status(400).json({ error: 'No thumbnail file provided' });
    }

    // Security: Validate MIME type (thumbnails are always images)
    const allowedImageMimes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (!allowedImageMimes.includes(file.mimetype)) {
      logger.postError('Invalid thumbnail MIME type', {
        userId: req.user.id,
        mimetype: file.mimetype,
        allowed: allowedImageMimes
      });
      return res.status(400).json({ 
        error: `Invalid thumbnail MIME type. Expected: ${allowedImageMimes.join(', ')}, got: ${file.mimetype}` 
      });
    }

    // Security: Validate file extension
    const fileExt = file.originalname.split('.').pop()?.toLowerCase() || 'jpg';
    const allowedImageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    
    if (!allowedImageExts.includes(fileExt)) {
      logger.postError('Invalid thumbnail extension', {
        userId: req.user.id,
        extension: fileExt,
        allowed: allowedImageExts
      });
      return res.status(400).json({ 
        error: `Invalid thumbnail extension. Allowed: ${allowedImageExts.join(', ')}, got: ${fileExt}` 
      });
    }

    // Security: Sanitize file extension
    const sanitizedExt = fileExt.replace(/[^a-z0-9]/gi, '');
    if (sanitizedExt !== fileExt) {
      return res.status(400).json({ error: 'Invalid thumbnail extension format' });
    }

    logger.post('Thumbnail upload request', {
      userId: req.user.id,
      fileName: file.originalname,
      fileSize: file.size,
      mimetype: file.mimetype,
      extension: fileExt,
    });

    const fileName = `thumb_${req.user.id}_${Date.now()}.${fileExt}`;
    
    // Upload to Supabase Storage
    const { data: uploadData, error: uploadError } = await supabaseAdmin
      .storage
      .from('post-media')
      .upload(fileName, file.buffer, {
        contentType: file.mimetype,
        upsert: false,
      });

    if (uploadError) {
      logger.postError('Error uploading thumbnail to Supabase', uploadError);
      return res.status(500).json({ error: 'Failed to upload thumbnail: ' + uploadError.message });
    }
    
    // Bucket is private, so we return the file path instead of public URL
    // Signed URL will be obtained via API when needed
    const thumbnailPath = uploadData.path || fileName;

    logger.post('Thumbnail uploaded successfully', {
      userId: req.user.id,
      fileName,
      thumbnailPath,
    });

    // Return the file path (not public URL) since bucket is private
    res.json({ thumbnailUrl: thumbnailPath });
  } catch (error) {
    logger.postError('Error in upload-thumbnail endpoint', error);
    res.status(500).json({ error: error.message });
  }
});

// GET /api/posts/media/signed-url?path=...
// Получить signed URL для приватного медиа файла поста
router.get('/media/signed-url', validateAuth, async (req, res) => {
  try {
    const { path, postId } = req.query; // Добавляем postId как опциональный параметр
    const userId = req.user.id;
    
    logger.post('Get signed URL request', {
      userId,
      path,
      postId,
    });

    if (!path) {
      return res.status(400).json({ error: 'Path parameter is required' });
    }

    // Проверяем, что путь валидный (начинается с post_ или thumb_)
    const fileName = path.split('/').pop() || path;
    if (!fileName.startsWith('post_') && !fileName.startsWith('thumb_')) {
      logger.postError('Invalid media path', { path, userId });
      return res.status(400).json({ error: 'Invalid media path. Must start with post_ or thumb_' });
    }

    // Создаем signed URL (действителен 1 час = 3600 секунд)
    const { data, error } = await supabaseAdmin
      .storage
      .from('post-media')
      .createSignedUrl(path, 3600);

    if (error) {
      logger.postError('Error creating signed URL', error);
      return res.status(500).json({ error: 'Failed to create signed URL: ' + error.message });
    }

    logger.post('Signed URL created successfully', {
      path,
      postId,
      hasSignedUrl: !!data?.signedUrl,
    });

    // Возвращаем signedUrl и postId (если передан)
    res.json({ 
      signedUrl: data.signedUrl,
      postId: postId || null // Возвращаем postId если был передан
    });
  } catch (error) {
    logger.postError('Error in GET /api/posts/media/signed-url', error);
    res.status(500).json({ error: error.message });
  }
});

// Create post (теперь принимает URL вместо файлов)
router.post('/', validateAuth, validatePost, async (req, res) => {
  try {
    logger.post('Post creation request', {
      userId: req.user.id,
      userEmail: req.user.email,
      hasMediaUrl: !!req.body.media_url,
      hasThumbnailUrl: !!req.body.thumbnail_url,
    });
    
    const { caption, media_url, media_type, thumbnail_url, mentions, visibility, expires_in_hours, latitude, longitude } = req.body;

    if (!media_url) {
      logger.postError('No media URL provided', { userId: req.user.id });
      return res.status(400).json({ message: 'Media URL is required' });
    }

    // Validate media type
    if (!media_type || !['image', 'video'].includes(media_type)) {
      logger.postError('Invalid media type', { media_type, userId: req.user.id });
      return res.status(400).json({ 
        message: 'Media type must be "image" or "video"' 
      });
    }

    logger.post('Media URL received, validating...');

    // Validate media_url - может быть путь к файлу (для приватного bucket) или URL
    // Путь к файлу начинается с post_ или thumb_
    const isFilePath = media_url.startsWith('post_') || media_url.startsWith('thumb_');
    if (!isFilePath) {
      // Если не путь, проверяем что это валидный URL
      try {
        new URL(media_url);
      } catch (urlError) {
        logger.postError('Invalid media URL format', { media_url, userId: req.user.id });
        return res.status(400).json({ 
          message: 'Invalid media URL format. Must be a valid URL or file path starting with post_ or thumb_' 
        });
      }
    }

    // Validate thumbnail URL if provided - аналогично
    if (thumbnail_url) {
      const isThumbnailPath = thumbnail_url.startsWith('post_') || thumbnail_url.startsWith('thumb_');
      if (!isThumbnailPath) {
        try {
          new URL(thumbnail_url);
        } catch (urlError) {
          logger.postError('Invalid thumbnail URL format', { thumbnail_url, userId: req.user.id });
          return res.status(400).json({ 
            message: 'Invalid thumbnail URL format. Must be a valid URL or file path starting with post_ or thumb_' 
          });
        }
      }
    }

    logger.post('Media type validation passed');

    // Validate visibility if provided
    const validVisibilityValues = ['public', 'friends', 'private'];
    const postVisibility = visibility || 'public';
    if (!validVisibilityValues.includes(postVisibility)) {
      logger.postError('Invalid visibility value', { visibility: postVisibility, userId: req.user.id });
      return res.status(400).json({ 
        message: `Visibility must be one of: ${validVisibilityValues.join(', ')}` 
      });
    }

    // Validate expires_in_hours if provided
    const validExpiresHours = [12, 24, 48];
    let expiresAt = null;
    if (expires_in_hours !== undefined && expires_in_hours !== null) {
      if (!validExpiresHours.includes(parseInt(expires_in_hours))) {
        logger.postError('Invalid expires_in_hours value', { expires_in_hours, userId: req.user.id });
        return res.status(400).json({ 
          message: `expires_in_hours must be one of: ${validExpiresHours.join(', ')}` 
        });
      }
      // Calculate expires_at based on expires_in_hours
      expiresAt = new Date();
      expiresAt.setHours(expiresAt.getHours() + parseInt(expires_in_hours));
    }

    // Create post record using admin client to bypass RLS
    logger.post('Creating post in database', {
      userId: req.user.id,
      caption: caption?.substring(0, 50),
      mediaType: media_type,
      mediaUrl: media_url,
      thumbnailUrl: thumbnail_url || 'none',
      hasMentions: !!mentions,
      visibility: postVisibility,
      expiresAt: expiresAt ? expiresAt.toISOString() : null,
      hasLocation: !!(latitude && longitude),
    });
    
    const postData = {
      user_id: req.user.id,
      caption,
      media_url: media_url,
      media_type: media_type,
      thumbnail_url: thumbnail_url || null,
      visibility: postVisibility,
    };

    // Add expires_at if provided
    if (expiresAt) {
      postData.expires_at = expiresAt.toISOString();
    }

    // Add location if provided
    if (latitude !== undefined && latitude !== null && longitude !== undefined && longitude !== null) {
      postData.latitude = parseFloat(latitude);
      postData.longitude = parseFloat(longitude);
    }
    
    const { data, error } = await supabaseAdmin
      .from('posts')
      .insert([postData])
      .select()
      .single();
      
    if (error) {
      logger.postError('Database error creating post', error);
      throw error;
    }

    logger.post('Post created successfully', { postId: data.id, userId: req.user.id });

    // Process mentions if provided
    if (mentions && Array.isArray(mentions)) {
      for (const username of mentions) {
        // Find user by username
        const { data: mentionedUser } = await supabaseAdmin
          .from('profiles')
          .select('id')
          .eq('username', username)
          .single();

        if (mentionedUser) {
          await supabaseAdmin
            .from('post_mentions')
            .insert([{
              post_id: data.id,
              mentioned_user_id: mentionedUser.id
            }]);
        }
      }
    }

    // Hashtags are now stored directly in the caption text
    // No need for separate hashtag processing

    res.status(201).json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get feed posts (posts from followed users) - MUST be before /:id route
router.get('/feed', validateAuth, async (req, res) => {
  try {
    const { page = 1, limit = 10, media_type, following_only } = req.query;
    
    logger.recommendations('Feed request received', {
      userId: req.user?.id,
      userEmail: req.user?.email,
      page: req.query.page,
      limit: req.query.limit,
      mediaType: media_type,
      followingOnly: following_only
    });
    
    const from = (page - 1) * limit;
    const to = from + limit - 1;
    const userId = req.user.id;

    // Определяем режим: рекомендации (все видео) или подписки (только от подписок)
    const isRecommendations = media_type === 'video' && following_only !== 'true';
    const isFollowingOnly = following_only === 'true' || (media_type !== 'video' && !following_only);

    logger.recommendations('Feed mode', {
      isRecommendations: isRecommendations,
      isFollowingOnly: isFollowingOnly,
      mediaType: media_type
    });

    // Get followed users (только если нужен режим подписок)
    let followingIds = [];
    if (isFollowingOnly) {
    const { data: following, error: followingError } = await supabaseAdmin
      .from('follows')
      .select('following_id')
      .eq('follower_id', userId);

    if (followingError) {
      logger.recommendationsError('Error getting following users', followingError);
      throw followingError;
    }

      followingIds = following.map(f => f.following_id);
      // Always include own posts in feed when showing following
    followingIds.push(userId);
    }
    
    logger.recommendations('Feed preparation', {
      followingCount: followingIds.length,
      isRecommendations: isRecommendations,
      isFollowingOnly: isFollowingOnly
    });

    // Строим запрос
    let query = supabaseAdmin
      .from('posts')
      .select(`
        *,
        profiles:user_id (username, name, avatar_url),
        likes(count)
      `, { count: 'exact' });

    // Фильтруем по типу медиа, если указан
    if (media_type && (media_type === 'video' || media_type === 'image')) {
      query = query.eq('media_type', media_type);
      logger.recommendations(`Filtering by media_type: ${media_type}`);
    }

    // Для рекомендаций показываем ВСЕ видео (не фильтруем по подпискам)
    // Для подписок фильтруем по подпискам
    if (isRecommendations) {
      // Рекомендации: показываем все видео от всех пользователей
      logger.recommendations('Recommendations mode: showing all videos from all users');
    } else if (isFollowingOnly) {
      // Подписки: фильтруем по подпискам
      if (followingIds.length > 0) {
      query = query.in('user_id', followingIds);
        logger.recommendations('Following mode: showing posts from followed users');
    } else {
        // Если нет подписок, показываем все посты (discovery mode)
        logger.recommendations('Discovery mode: showing all posts (new user, no follows)');
      }
    }

    const { data, error, count } = await query
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) {
      logger.recommendationsError('Error getting posts', error);
      throw error;
    }

    logger.recommendations('Posts retrieved', { count: data?.length || 0, total: count });

    // Get user's likes for all posts
    const postIds = data.map(post => post.id);
    const { data: userLikes, error: likesError } = await supabaseAdmin
      .from('likes')
      .select('post_id')
      .eq('user_id', userId)
      .in('post_id', postIds);

    if (likesError) {
      logger.recommendationsError('Error getting user likes', likesError);
      throw likesError;
    }

    const likedPostIds = new Set(userLikes.map(like => like.post_id));
    logger.recommendations('Feed response prepared', { 
      postsCount: data?.length || 0,
      likedPosts: likedPostIds.size
    });

    // Get comments count for all posts (including replies)
    const { data: commentsCounts, error: commentsCountError } = await supabaseAdmin
      .from('comments')
      .select('post_id')
      .in('post_id', postIds);

    if (commentsCountError) {
      logger.recommendationsError('Error getting comments count', commentsCountError);
    }

    // Count comments per post (including replies)
    const commentsCountMap = {};
    if (commentsCounts) {
      commentsCounts.forEach(comment => {
        commentsCountMap[comment.post_id] = (commentsCountMap[comment.post_id] || 0) + 1;
      });
    }

    // Transform data to include likes count, comments count and is_liked status
    const postsWithLikes = data.map(post => ({
      ...post,
      likes_count: post.likes?.[0]?.count || 0,
      comments_count: commentsCountMap[post.id] || 0,
      is_liked: likedPostIds.has(post.id),
      likes: undefined // Remove the likes array from response
    }));

    logger.recommendations('Feed response sent successfully');
    res.json({
      posts: postsWithLikes,
      total: count,
      page: parseInt(page),
      totalPages: Math.ceil(count / limit)
    });
  } catch (error) {
    logger.recommendationsError('Feed error', error);
    res.status(500).json({ error: error.message });
  }
});

// Get single post
router.get('/:id', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    const { data, error } = await supabaseAdmin
      .from('posts')
      .select(`
        *,
        profiles:user_id (username, name, avatar_url),
        comments (
          id,
          content,
          parent_comment_id,
          created_at,
          profiles:user_id (username, name, avatar_url)
        ),
        likes(count)
      `)
      .eq('id', id)
      .single();

    if (error) throw error;
    if (!data) return res.status(404).json({ message: 'Post not found' });

    // Check if user liked this post
    const { data: userLike, error: likeError } = await supabaseAdmin
      .from('likes')
      .select('id')
      .eq('user_id', userId)
      .eq('post_id', id)
      .single();

    const isLiked = !likeError && userLike;

    // Transform data to include likes count and is_liked status
    const postWithLikes = {
      ...data,
      likes_count: data.likes?.[0]?.count || 0,
      is_liked: isLiked,
      likes: undefined // Remove the likes array from response
    };

    res.json(postWithLikes);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete post
router.delete('/:id', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;

    // Check if post exists and belongs to user
    const { data: post, error: fetchError } = await supabaseAdmin
      .from('posts')
      .select('user_id, media_url')
      .eq('id', id)
      .single();

    if (fetchError) throw fetchError;
    if (!post) return res.status(404).json({ message: 'Post not found' });
    if (post.user_id !== req.user.id) {
      return res.status(403).json({ message: 'Unauthorized' });
    }

    // Delete media from storage
    const mediaName = post.media_url.split('/').pop();
    const { error: storageError } = await supabaseAdmin.storage
      .from('post-media')
      .remove([mediaName]);

    if (storageError) throw storageError;

    // Delete post
    const { error } = await supabaseAdmin
      .from('posts')
      .delete()
      .eq('id', id);

    if (error) throw error;

    res.json({ message: 'Post deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Like/Unlike post
router.post('/:id/like', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    logger.post('Like/Unlike post request', {
      postId: id,
      userId: userId,
      userEmail: req.user.email
    });

    // Check if already liked
    const { data: existingLike } = await supabaseAdmin
      .from('likes')
      .select()
      .eq('post_id', id)
      .eq('user_id', userId)
      .single();

    let isLiked;
    let likesCount;

    if (existingLike) {
      // Unlike
      logger.post('Unliking post', { postId: id, userId: userId });
      
      const { error } = await supabaseAdmin
        .from('likes')
        .delete()
        .eq('post_id', id)
        .eq('user_id', userId);

      if (error) {
        logger.postError('Error unliking post', { postId: id, userId: userId, error });
        throw error;
      }

      // Delete like notification
      await supabaseAdmin
        .from('notifications')
        .delete()
        .eq('post_id', id)
        .eq('actor_id', userId)
        .eq('type', 'like');

      isLiked = false;
      logger.post('Post unliked successfully', { postId: id, userId: userId });
    } else {
      // Like
      logger.post('Liking post', { postId: id, userId: userId });
      
      const { error } = await supabaseAdmin
        .from('likes')
        .insert([{ post_id: id, user_id: userId }]);

      if (error) {
        logger.postError('Error liking post', { postId: id, userId: userId, error });
        throw error;
      }

      // Get post owner to create notification
      const { data: post } = await supabaseAdmin
        .from('posts')
        .select('user_id')
        .eq('id', id)
        .single();

      if (post && post.user_id !== userId) {
        await createNotification(post.user_id, userId, 'like', id);
        logger.post('Like notification created', { 
          postId: id, 
          likerId: userId, 
          postOwnerId: post.user_id 
        });
      }

      isLiked = true;
      logger.post('Post liked successfully', { postId: id, userId: userId });
    }

    // Get updated likes count
    const { count: likesCountResult, error: likesCountError } = await supabaseAdmin
      .from('likes')
      .select('id', { count: 'exact', head: true })
      .eq('post_id', id);

    if (likesCountError) {
      logger.postError('Error getting likes count', { postId: id, error: likesCountError });
      likesCount = 0;
    } else {
      likesCount = likesCountResult || 0;
      logger.post('Likes count retrieved', { postId: id, likesCount: likesCount });
    }

    logger.post('Like/Unlike response prepared', {
      postId: id,
      isLiked: isLiked,
      likesCount: likesCount
    });

    res.json({ 
      message: isLiked ? 'Post liked successfully' : 'Post unliked successfully',
      isLiked: isLiked,
      likesCount: likesCount
    });
  } catch (error) {
    logger.postError('Like/Unlike post error', { 
      postId: req.params.id, 
      userId: req.user?.id, 
      error: error.message 
    });
    res.status(500).json({ error: error.message });
  }
});

// Get comments for a post
router.get('/:id/comments', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;
    const { page = 1, limit = 20 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    // Get top-level comments (parent_comment_id is null)
    const { data: comments, error, count } = await supabaseAdmin
      .from('comments')
      .select(`
        *,
        profiles:user_id (username, avatar_url),
        comment_likes(count),
        comment_dislikes(count)
      `, { count: 'exact' })
      .eq('post_id', id)
      .is('parent_comment_id', null)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    // Get total count of ALL comments (including replies) for this post
    const { count: totalCommentsCount, error: totalCountError } = await supabaseAdmin
      .from('comments')
      .select('id', { count: 'exact', head: true })
      .eq('post_id', id);

    if (totalCountError) {
      logger.postError('Error getting total comments count', { postId: id, error: totalCountError });
    }

    // Get comment IDs for all comments (including replies)
    const commentIds = comments.map(c => c.id);
    
    // Get replies for each comment
    if (commentIds.length > 0) {
      const { data: replies, error: repliesError } = await supabaseAdmin
        .from('comments')
        .select(`
          *,
          profiles:user_id (username, avatar_url),
          comment_likes(count),
          comment_dislikes(count)
        `)
        .in('parent_comment_id', commentIds)
        .order('created_at', { ascending: true });

      if (repliesError) throw repliesError;

      // Add replies to main comment list for easier processing
      const allComments = [...comments, ...replies];
      
      // Get user's likes and dislikes for all comments
      const allCommentIds = allComments.map(c => c.id);
      const { data: userLikes } = await supabaseAdmin
        .from('comment_likes')
        .select('comment_id')
        .eq('user_id', userId)
        .in('comment_id', allCommentIds);
      
      const { data: userDislikes } = await supabaseAdmin
        .from('comment_dislikes')
        .select('comment_id')
        .eq('user_id', userId)
        .in('comment_id', allCommentIds);
      
      const likedCommentIds = new Set(userLikes?.map(l => l.comment_id) || []);
      const dislikedCommentIds = new Set(userDislikes?.map(d => d.comment_id) || []);
      
      // Process all comments (main and replies)
      allComments.forEach(comment => {
        comment.likes_count = comment.comment_likes?.[0]?.count || 0;
        comment.dislikes_count = comment.comment_dislikes?.[0]?.count || 0;
        comment.is_liked = likedCommentIds.has(comment.id);
        comment.is_disliked = dislikedCommentIds.has(comment.id);
        delete comment.comment_likes;
        delete comment.comment_dislikes;
      });

      // Group replies by parent_comment_id
      const repliesMap = {};
      replies.forEach(reply => {
        if (!repliesMap[reply.parent_comment_id]) {
          repliesMap[reply.parent_comment_id] = [];
        }
        repliesMap[reply.parent_comment_id].push(reply);
      });

      // Add replies to comments
      comments.forEach(comment => {
        comment.replies = repliesMap[comment.id] || [];
      });
    }

    // Use total count of all comments (including replies) instead of just top-level comments
    const finalTotal = totalCommentsCount !== null ? totalCommentsCount : count;

    res.json({
      comments,
      total: finalTotal, // Total count of ALL comments including replies
      page: parseInt(page),
      totalPages: Math.ceil(count / limit) // Pages are still based on top-level comments for pagination
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Add comment to post
router.post('/:id/comments', validateAuth, validateUUID, validateComment, async (req, res) => {
  try {
    const { id } = req.params;
    const { content, parent_comment_id } = req.body;
    const userId = req.user.id;

    if (!content || content.trim().length === 0) {
      return res.status(400).json({ message: 'Comment content is required' });
    }

    // Check if post exists and get owner
    const { data: post, error: postError } = await supabaseAdmin
      .from('posts')
      .select('id, user_id')
      .eq('id', id)
      .single();

    if (postError || !post) {
      return res.status(404).json({ message: 'Post not found' });
    }

    // If replying to a comment, check if parent comment exists
    if (parent_comment_id) {
      const { data: parentComment, error: parentError } = await supabaseAdmin
        .from('comments')
        .select('id')
        .eq('id', parent_comment_id)
        .eq('post_id', id)
        .single();

      if (parentError || !parentComment) {
        return res.status(404).json({ message: 'Parent comment not found' });
      }
    }

    // Create comment
    const { data, error } = await supabaseAdmin
      .from('comments')
      .insert([
        {
          post_id: id,
          user_id: userId,
          parent_comment_id: parent_comment_id || null,
          content: content.trim()
        }
      ])
      .select(`
        *,
        profiles:user_id (username, name, avatar_url)
      `)
      .single();

    if (error) throw error;

    // Create notification for post owner
    if (post.user_id !== userId) {
      await createNotification(post.user_id, userId, 'comment', id, data.id);
    }

    res.status(201).json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update comment
router.put('/:id/comments/:commentId', validateAuth, validateUUID, validateCommentId, validateComment, async (req, res) => {
  try {
    const { id, commentId } = req.params;
    const { content } = req.body;
    const userId = req.user.id;

    if (!content || content.trim().length === 0) {
      return res.status(400).json({ message: 'Comment content is required' });
    }

    // Check if comment exists and belongs to user
    const { data: comment, error: fetchError } = await supabaseAdmin
      .from('comments')
      .select('user_id, post_id')
      .eq('id', commentId)
      .eq('post_id', id)
      .single();

    if (fetchError || !comment) {
      return res.status(404).json({ message: 'Comment not found' });
    }

    if (comment.user_id !== userId) {
      return res.status(403).json({ message: 'Unauthorized to edit this comment' });
    }

    // Update comment
    const { data: updatedComment, error } = await supabaseAdmin
      .from('comments')
      .update({
        content: content.trim(),
        updated_at: new Date().toISOString()
      })
      .eq('id', commentId)
      .select(`
        *,
        profiles:user_id (username, name, avatar_url)
      `)
      .single();

    if (error) throw error;

    res.json(updatedComment);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete comment
router.delete('/:id/comments/:commentId', validateAuth, validateUUID, validateCommentId, async (req, res) => {
  try {
    const { id, commentId } = req.params;
    const userId = req.user.id;

    // Check if comment exists and belongs to user
    const { data: comment, error: fetchError } = await supabaseAdmin
      .from('comments')
      .select('user_id, post_id')
      .eq('id', commentId)
      .eq('post_id', id)
      .single();

    if (fetchError || !comment) {
      return res.status(404).json({ message: 'Comment not found' });
    }

    if (comment.user_id !== userId) {
      return res.status(403).json({ message: 'Unauthorized to delete this comment' });
    }

    // Delete comment
    const { error } = await supabaseAdmin
      .from('comments')
      .delete()
      .eq('id', commentId);

    if (error) throw error;

    res.json({ message: 'Comment deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Like a comment
router.post('/:id/comments/:commentId/like', validateAuth, validateUUID, validateCommentId, async (req, res) => {
  try {
    const { id: postId, commentId } = req.params;
    const userId = req.user.id;

    // Check if post exists
    const { data: post, error: postError } = await supabaseAdmin
      .from('posts')
      .select('id')
      .eq('id', postId)
      .single();

    if (postError || !post) {
      return res.status(404).json({ message: 'Post not found' });
    }

    // Check if comment exists and belongs to this post
    const { data: comment, error: commentError } = await supabaseAdmin
      .from('comments')
      .select('id, user_id')
      .eq('id', commentId)
      .eq('post_id', postId)
      .single();

    if (commentError || !comment) {
      return res.status(404).json({ message: 'Comment not found' });
    }

    // Check if user already liked the comment
    const { data: existingLike } = await supabaseAdmin
      .from('comment_likes')
      .select('id')
      .eq('comment_id', commentId)
      .eq('user_id', userId)
      .single();

    if (existingLike) {
      // Unlike: delete the like
      await supabaseAdmin
        .from('comment_likes')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId);

      // Check if user has a dislike, remove it too
      const { data: existingDislike } = await supabaseAdmin
        .from('comment_dislikes')
        .select('id')
        .eq('comment_id', commentId)
        .eq('user_id', userId)
        .single();

      if (existingDislike) {
        await supabaseAdmin
          .from('comment_dislikes')
          .delete()
          .eq('comment_id', commentId)
          .eq('user_id', userId);
      }

      return res.json({ isLiked: false, isDisliked: false });
    }

    // Like: insert the like
    // First, check if user has a dislike and remove it
    const { data: existingDislike } = await supabaseAdmin
      .from('comment_dislikes')
      .select('id')
      .eq('comment_id', commentId)
      .eq('user_id', userId)
      .single();

    if (existingDislike) {
      await supabaseAdmin
        .from('comment_dislikes')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId);
    }

    // Insert the like
    const { error: likeError } = await supabaseAdmin
      .from('comment_likes')
      .insert({
        comment_id: commentId,
        user_id: userId
      });

    if (likeError) throw likeError;

    // Create notification if comment owner is not the liker
    if (comment.user_id !== userId) {
      await createNotification(comment.user_id, userId, 'comment_like', postId, commentId);
    }

    res.json({ isLiked: true, isDisliked: false });
  } catch (error) {
    logger.postError('Error liking comment', error);
    res.status(500).json({ error: error.message });
  }
});

// Dislike a comment
router.post('/:id/comments/:commentId/dislike', validateAuth, validateUUID, validateCommentId, async (req, res) => {
  try {
    const { id: postId, commentId } = req.params;
    const userId = req.user.id;

    // Check if post exists
    const { data: post, error: postError } = await supabaseAdmin
      .from('posts')
      .select('id')
      .eq('id', postId)
      .single();

    if (postError || !post) {
      return res.status(404).json({ message: 'Post not found' });
    }

    // Check if comment exists and belongs to this post
    const { data: comment, error: commentError } = await supabaseAdmin
      .from('comments')
      .select('id')
      .eq('id', commentId)
      .eq('post_id', postId)
      .single();

    if (commentError || !comment) {
      return res.status(404).json({ message: 'Comment not found' });
    }

    // Check if user already disliked the comment
    const { data: existingDislike } = await supabaseAdmin
      .from('comment_dislikes')
      .select('id')
      .eq('comment_id', commentId)
      .eq('user_id', userId)
      .single();

    if (existingDislike) {
      // Undislike: delete the dislike
      await supabaseAdmin
        .from('comment_dislikes')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId);

      return res.json({ isLiked: false, isDisliked: false });
    }

    // Dislike: insert the dislike
    // First, check if user has a like and remove it
    const { data: existingLike } = await supabaseAdmin
      .from('comment_likes')
      .select('id')
      .eq('comment_id', commentId)
      .eq('user_id', userId)
      .single();

    if (existingLike) {
      await supabaseAdmin
        .from('comment_likes')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId);
    }

    // Insert the dislike
    const { error: dislikeError } = await supabaseAdmin
      .from('comment_dislikes')
      .insert({
        comment_id: commentId,
        user_id: userId
      });

    if (dislikeError) throw dislikeError;

    res.json({ isLiked: false, isDisliked: true });
  } catch (error) {
    logger.postError('Error disliking comment', error);
    res.status(500).json({ error: error.message });
  }
});

// Update post
router.put('/:id', validateAuth, validateUUID, validatePostUpdate, async (req, res) => {
  try {
    const { id } = req.params;
    const { caption } = req.body;
    const userId = req.user.id;

    // Check if post exists and belongs to user
    const { data: post, error: fetchError } = await supabaseAdmin
      .from('posts')
      .select('user_id')
      .eq('id', id)
      .single();

    if (fetchError || !post) {
      return res.status(404).json({ message: 'Post not found' });
    }

    if (post.user_id !== userId) {
      return res.status(403).json({ message: 'Unauthorized to update this post' });
    }

    // Update post
    const { data, error } = await supabaseAdmin
      .from('posts')
      .update({
        caption: caption || null,
        updated_at: new Date()
      })
      .eq('id', id)
      .select(`
        *,
        profiles:user_id (username, name, avatar_url)
      `)
      .single();

    if (error) throw error;

    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get posts by hashtag
router.get('/hashtag/:hashtag', validateAuth, async (req, res) => {
  try {
    const { hashtag } = req.params;
    const { page = 1, limit = 10 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;
    const userId = req.user.id;

    logger.hashtags('Hashtag search', { hashtag, page, limit, userId });

    // Search for posts where caption contains the hashtag
    const { data, error, count } = await supabaseAdmin
      .from('posts')
      .select(`
        *,
        profiles:user_id (username, name, avatar_url),
        likes(count)
      `, { count: 'exact' })
      .ilike('caption', `%#${hashtag.toLowerCase()}%`)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) {
      logger.hashtags('Hashtag search error', error);
      throw error;
    }

    logger.hashtags(`Found ${data.length} posts for hashtag #${hashtag}`);

    // Get user's likes for all posts
    const postIds = data.map(post => post.id);
    const { data: userLikes, error: likesError } = await supabaseAdmin
      .from('likes')
      .select('post_id')
      .eq('user_id', userId)
      .in('post_id', postIds);

    if (likesError) throw likesError;

    const likedPostIds = new Set(userLikes.map(like => like.post_id));

    // Transform data to include likes count and is_liked status
    const postsWithLikes = data.map(post => ({
      ...post,
      likes_count: post.likes?.[0]?.count || 0,
      is_liked: likedPostIds.has(post.id),
      likes: undefined // Remove the likes array from response
    }));

    logger.hashtags('Hashtag search completed', { 
      hashtag, 
      postsCount: postsWithLikes.length, 
      total: count 
    });

    res.json({
      posts: postsWithLikes,
      total: count,
      page: parseInt(page),
      totalPages: Math.ceil(count / limit)
    });
  } catch (error) {
    logger.hashtags('Hashtag search error', error);
    res.status(500).json({ error: error.message });
  }
});

// Get posts where user is mentioned
router.get('/mentions', validateAuth, async (req, res) => {
  try {
    const { page = 1, limit = 10 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;
    const userId = req.user.id;

    const { data, error, count } = await supabaseAdmin
      .from('posts')
      .select(`
        *,
        profiles:user_id (username, name, avatar_url),
        likes(count),
        post_mentions!inner(mentioned_user_id)
      `, { count: 'exact' })
      .eq('post_mentions.mentioned_user_id', userId)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    // Get user's likes for all posts
    const postIds = data.map(post => post.id);
    const { data: userLikes, error: likesError } = await supabaseAdmin
      .from('likes')
      .select('post_id')
      .eq('user_id', userId)
      .in('post_id', postIds);

    if (likesError) throw likesError;

    const likedPostIds = new Set(userLikes.map(like => like.post_id));

    // Transform data to include likes count and is_liked status
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

// Save/Unsave post
router.post('/:id/save', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    // Check if post exists
    const { data: post, error: postError } = await supabaseAdmin
      .from('posts')
      .select('id')
      .eq('id', id)
      .single();

    if (postError || !post) {
      return res.status(404).json({ message: 'Post not found' });
    }

    // Check if already saved
    const { data: existingSave, error: checkError } = await supabaseAdmin
      .from('saved_posts')
      .select('id')
      .eq('user_id', userId)
      .eq('post_id', id)
      .single();

    if (existingSave) {
      return res.json({ message: 'Post already saved', saved: true });
    }

    // Save post
    const { data, error } = await supabaseAdmin
      .from('saved_posts')
      .insert([{
        user_id: userId,
        post_id: id
      }])
      .select()
      .single();

    if (error) throw error;

    res.json({ message: 'Post saved successfully', saved: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get geo-posts for map view
router.get('/geo/map', validateAuth, async (req, res) => {
  try {
    const { swLat, swLng, neLat, neLng } = req.query;
    const userId = req.user.id;

    if (!swLat || !swLng || !neLat || !neLng) {
      return res.status(400).json({ error: 'All bounding box parameters (swLat, swLng, neLat, neLng) are required' });
    }

    const swLatNum = parseFloat(swLat);
    const swLngNum = parseFloat(swLng);
    const neLatNum = parseFloat(neLat);
    const neLngNum = parseFloat(neLng);

    // Get current time for filtering expired posts
    const now = new Date().toISOString();

    // Get mutual followers for visibility filtering
    const { data: following, error: followingError } = await supabaseAdmin
      .from('follows')
      .select('following_id')
      .eq('follower_id', userId);

    if (followingError) throw followingError;

    const followingIds = following.map(f => f.following_id);

    // Get users who follow current user (mutual followers)
    const { data: followers, error: followersError } = await supabaseAdmin
      .from('follows')
      .select('follower_id')
      .eq('following_id', userId);

    if (followersError) throw followersError;

    const followerIds = followers.map(f => f.follower_id);
    // Mutual followers: users who follow us AND we follow them
    const mutualFollowerIds = followingIds.filter(id => followerIds.includes(id));
    // Always include current user's own posts
    const visibleUserIds = [...mutualFollowerIds, userId];

    // Build query for geo-posts within bounding box
    let query = supabaseAdmin
      .from('posts')
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url)
      `)
      .not('latitude', 'is', null)
      .not('longitude', 'is', null)
      .gte('latitude', swLatNum)
      .lte('latitude', neLatNum)
      .gte('longitude', swLngNum)
      .lte('longitude', neLngNum);

    // Filter out expired posts
    query = query.or(`expires_at.is.null,expires_at.gt.${now}`);

    // Filter by visibility
    // We need to get all posts first, then filter in JavaScript
    // because Supabase doesn't support complex OR conditions with user_id checks easily
    const { data: allGeoPosts, error: postsError } = await query;

    if (postsError) throw postsError;

    // Filter posts by visibility
    const filteredPosts = allGeoPosts.filter(post => {
      // Private posts: only author can see
      if (post.visibility === 'private') {
        return post.user_id === userId;
      }
      // Friends posts: only mutual followers can see
      if (post.visibility === 'friends') {
        return visibleUserIds.includes(post.user_id);
      }
      // Public posts: everyone can see
      return true;
    });

    // Get likes count and is_liked status for filtered posts
    const postIds = filteredPosts.map(post => post.id);
    let likedPostIds = new Set();
    if (postIds.length > 0) {
      const { data: userLikes, error: likesError } = await supabaseAdmin
        .from('likes')
        .select('post_id')
        .eq('user_id', userId)
        .in('post_id', postIds);

      if (!likesError && userLikes) {
        likedPostIds = new Set(userLikes.map(like => like.post_id));
      }

      // Get likes count for each post
      const { data: likesCounts, error: likesCountError } = await supabaseAdmin
        .from('likes')
        .select('post_id')
        .in('post_id', postIds);

      if (!likesCountError && likesCounts) {
        const likesCountMap = new Map();
        likesCounts.forEach(like => {
          likesCountMap.set(like.post_id, (likesCountMap.get(like.post_id) || 0) + 1);
        });

        // Add likes_count and is_liked to each post
        filteredPosts.forEach(post => {
          post.likes_count = likesCountMap.get(post.id) || 0;
          post.is_liked = likedPostIds.has(post.id);
        });
      }
    }

    res.json({ posts: filteredPosts });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Unsave post
router.delete('/:id/save', validateAuth, validateUUID, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    // Remove saved post
    const { error } = await supabaseAdmin
      .from('saved_posts')
      .delete()
      .eq('user_id', userId)
      .eq('post_id', id);

    if (error) throw error;

    res.json({ message: 'Post unsaved successfully', saved: false });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

export default router;