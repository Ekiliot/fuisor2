import express from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { logger } from '../utils/logger.js';

const router = express.Router();

// Search for users, posts, and hashtags
router.get('/', validateAuth, async (req, res) => {
  try {
    const { q, type = 'all', page = 1, limit = 20 } = req.query;
    const userId = req.user.id;

    if (!q || q.trim().length === 0) {
      return res.json({
        users: [],
        posts: [],
        hashtags: [],
        total: 0
      });
    }

    const searchQuery = q.trim().toLowerCase();
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    let users = [];
    let posts = [];
    let hashtags = [];

    // Search users
    if (type === 'all' || type === 'users') {
      const { data: usersData, error: usersError } = await supabaseAdmin
        .from('profiles')
        .select('id, username, name, avatar_url, bio')
        .ilike('username', `%${searchQuery}%`)
        .range(from, to);

      if (usersError) {
        logger.searchError('Error searching users', usersError);
      } else {
        users = usersData || [];
        logger.search(`Found ${users.length} users for query "${searchQuery}"`);
      }
    }

    // Search posts by caption
    if (type === 'all' || type === 'posts') {
      const { data: postsData, error: postsError } = await supabaseAdmin
        .from('posts')
        .select(`
          *,
          profiles:user_id (username, name, avatar_url),
          likes(count)
        `)
        .ilike('caption', `%${searchQuery}%`)
        .order('created_at', { ascending: false })
        .range(from, to);

      if (postsError) {
        logger.searchError('Error searching posts', postsError);
      } else {
        // Get user's likes for posts
        const postIds = postsData.map(post => post.id);
        if (postIds.length > 0) {
          const { data: userLikes } = await supabaseAdmin
            .from('likes')
            .select('post_id')
            .eq('user_id', userId)
            .in('post_id', postIds);

          const likedPostIds = new Set(userLikes?.map(like => like.post_id) || []);

          posts = postsData.map(post => ({
            ...post,
            likes_count: post.likes?.[0]?.count || 0,
            is_liked: likedPostIds.has(post.id),
            likes: undefined
          }));
        }
      }
    }

    // Search hashtags
    if (type === 'all' || type === 'hashtags') {
      const { data: hashtagsData, error: hashtagsError } = await supabaseAdmin
        .from('hashtags')
        .select(`
          id,
          name,
          created_at,
          post_hashtags(count)
        `)
        .ilike('name', `%${searchQuery}%`)
        .range(from, to);

      if (hashtagsError) {
        logger.searchError('Error searching hashtags', hashtagsError);
      } else {
        hashtags = hashtagsData?.map(hashtag => ({
          id: hashtag.id,
          name: hashtag.name,
          posts_count: hashtag.post_hashtags?.[0]?.count || 0,
          created_at: hashtag.created_at
        })) || [];
      }
    }

    res.json({
      users,
      posts,
      hashtags,
      total: users.length + posts.length + hashtags.length,
      page: parseInt(page),
      query: q
    });
  } catch (error) {
    logger.searchError('Error searching', error);
    res.status(500).json({ error: error.message });
  }
});

// Search users only (for mentions, etc)
router.get('/users', validateAuth, async (req, res) => {
  try {
    const { q, limit = 20 } = req.query;

    if (!q || q.trim().length === 0) {
      return res.json({ users: [] });
    }

    const searchQuery = q.trim().toLowerCase();

    const { data, error } = await supabaseAdmin
      .from('profiles')
      .select('id, username, name, avatar_url')
      .ilike('username', `%${searchQuery}%`)
      .limit(limit);

    if (error) {
      logger.searchError('Error searching users', error);
      return res.status(500).json({ error: error.message });
    }

    res.json({ users: data || [] });
  } catch (error) {
    logger.searchError('Error searching users', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

