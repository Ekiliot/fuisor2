import express from 'express';
import { supabase, supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { validateNews, validateNewsUpdate, validateNewsId, validateCategoryId, validateComment, validateCommentId } from '../middleware/validation.middleware.js';
import { sanitizeHtmlContent } from '../utils/html_sanitizer.js';
import { createNotification } from './notification.routes.js';
import { logger } from '../utils/logger.js';

const router = express.Router();

// Get all news (with pagination and filtering)
router.get('/', validateAuth, async (req, res) => {
  try {
    const { page = 1, limit = 10, categoryId } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;
    const userId = req.user.id;

    let query = supabaseAdmin
      .from('news')
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url),
        coauthor:coauthor_user_id (id, username, name, avatar_url),
        category:category_id (id, name_en, name_ru, icon),
        subcategory:subcategory_id (id, name_en, name_ru),
        likes(count)
      `, { count: 'exact' })
      .eq('is_published', true)
      .order('created_at', { ascending: false })
      .range(from, to);

    // Filter by category if provided
    if (categoryId) {
      query = query.eq('category_id', categoryId);
    }

    const { data, error, count } = await query;

    if (error) throw error;

    // Get user's likes for all news
    const newsIds = data.map(news => news.id);
    const { data: userLikes, error: likesError } = await supabaseAdmin
      .from('news_likes')
      .select('news_id')
      .eq('user_id', userId)
      .in('news_id', newsIds);

    if (likesError) throw likesError;

    const likedNewsIds = new Set(userLikes.map(like => like.news_id));

    // Transform data to include likes count and is_liked status
    const newsWithLikes = data.map(news => ({
      ...news,
      likes_count: news.likes?.[0]?.count || 0,
      is_liked: likedNewsIds.has(news.id),
      likes: undefined // Remove the likes array from response
    }));

    res.json({
      news: newsWithLikes,
      total: count,
      page: parseInt(page),
      totalPages: Math.ceil(count / limit)
    });
  } catch (error) {
    logger.error('Error fetching news feed', error);
    res.status(500).json({ error: error.message });
  }
});

// Get single news article
router.get('/:id', validateAuth, validateNewsId, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    const { data, error } = await supabaseAdmin
      .from('news')
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url),
        coauthor:coauthor_user_id (id, username, name, avatar_url),
        category:category_id (id, name_en, name_ru, icon),
        subcategory:subcategory_id (id, name_en, name_ru),
        likes(count)
      `)
      .eq('id', id)
      .single();

    if (error) throw error;

    if (!data) {
      return res.status(404).json({ message: 'News not found' });
    }

    // Check if user can view this news (published or own)
    if (!data.is_published && data.user_id !== userId && data.coauthor_user_id !== userId) {
      return res.status(403).json({ message: 'Access denied' });
    }

    // Check if user liked this news
    const { data: userLike } = await supabaseAdmin
      .from('news_likes')
      .select('news_id')
      .eq('news_id', id)
      .eq('user_id', userId)
      .single();

    // Increment views count
    await supabaseAdmin
      .from('news')
      .update({ views_count: (data.views_count || 0) + 1 })
      .eq('id', id);

    res.json({
      ...data,
      likes_count: data.likes?.[0]?.count || 0,
      is_liked: !!userLike,
      views_count: (data.views_count || 0) + 1,
      likes: undefined
    });
  } catch (error) {
    logger.error('Error fetching news', error);
    res.status(500).json({ error: error.message });
  }
});

// Create news article
router.post('/', validateAuth, validateNews, async (req, res) => {
  try {
    const { 
      title, 
      content, 
      category_id, 
      subcategory_id, 
      cover_image_url,
      coauthors,
      external_link_url,
      external_link_text
    } = req.body;

    // Sanitize HTML content
    const sanitizedContent = sanitizeHtmlContent(content);

    // Validate coauthors (maximum 1)
    if (coauthors && Array.isArray(coauthors)) {
      if (coauthors.length > 1) {
        return res.status(400).json({ 
          message: 'Maximum 1 coauthor per news is allowed' 
        });
      }
    }

    // Validate external link text length if URL is provided
    if (external_link_url && external_link_text) {
      if (external_link_text.length < 6 || external_link_text.length > 8) {
        return res.status(400).json({ 
          message: 'External link text must be between 6 and 8 characters' 
        });
      }
    }

    const newsData = {
      user_id: req.user.id,
      title,
      content,
      sanitized_content: sanitizedContent,
      category_id,
      subcategory_id: subcategory_id || null,
      cover_image_url: cover_image_url || null,
      external_link_url: external_link_url || null,
      external_link_text: external_link_text || null
    };

    // Process coauthor if provided
    if (coauthors && Array.isArray(coauthors) && coauthors.length > 0) {
      const coauthorUsername = coauthors[0];
      
      let coauthorQuery = supabaseAdmin
        .from('profiles')
        .select('id, username');
      
      const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(coauthorUsername);
      
      if (isUUID) {
        coauthorQuery = coauthorQuery.eq('id', coauthorUsername);
      } else {
        coauthorQuery = coauthorQuery.eq('username', coauthorUsername);
      }
      
      const { data: coauthorUser } = await coauthorQuery.single();

      if (coauthorUser && coauthorUser.id !== req.user.id) {
        newsData.coauthor_user_id = coauthorUser.id;
      }
    }

    const { data, error } = await supabaseAdmin
      .from('news')
      .insert([newsData])
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url),
        coauthor:coauthor_user_id (id, username, name, avatar_url),
        category:category_id (id, name_en, name_ru, icon),
        subcategory:subcategory_id (id, name_en, name_ru)
      `)
      .single();

    if (error) throw error;

    res.status(201).json(data);
  } catch (error) {
    logger.error('Error creating news', error);
    res.status(500).json({ error: error.message });
  }
});

// Update news article
router.put('/:id', validateAuth, validateNewsId, validateNewsUpdate, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    // Check if news exists and user owns it
    const { data: existingNews, error: fetchError } = await supabaseAdmin
      .from('news')
      .select('user_id, coauthor_user_id')
      .eq('id', id)
      .single();

    if (fetchError) throw fetchError;
    if (!existingNews) {
      return res.status(404).json({ message: 'News not found' });
    }

    if (existingNews.user_id !== userId && existingNews.coauthor_user_id !== userId) {
      return res.status(403).json({ message: 'You can only update your own news' });
    }

    const updateData = {};

    if (req.body.title) updateData.title = req.body.title;
    if (req.body.content) {
      updateData.content = req.body.content;
      updateData.sanitized_content = sanitizeHtmlContent(req.body.content);
    }
    if (req.body.category_id) updateData.category_id = req.body.category_id;
    if (req.body.subcategory_id !== undefined) updateData.subcategory_id = req.body.subcategory_id || null;
    if (req.body.cover_image_url !== undefined) updateData.cover_image_url = req.body.cover_image_url || null;
    if (req.body.external_link_url !== undefined) updateData.external_link_url = req.body.external_link_url || null;
    if (req.body.external_link_text !== undefined) updateData.external_link_text = req.body.external_link_text || null;
    if (req.body.is_published !== undefined) updateData.is_published = req.body.is_published;

    // Handle coauthor update
    if (req.body.coauthors !== undefined) {
      if (req.body.coauthors && Array.isArray(req.body.coauthors) && req.body.coauthors.length > 0) {
        const coauthorUsername = req.body.coauthors[0];
        
        let coauthorQuery = supabaseAdmin
          .from('profiles')
          .select('id, username');
        
        const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(coauthorUsername);
        
        if (isUUID) {
          coauthorQuery = coauthorQuery.eq('id', coauthorUsername);
        } else {
          coauthorQuery = coauthorQuery.eq('username', coauthorUsername);
        }
        
        const { data: coauthorUser } = await coauthorQuery.single();

        if (coauthorUser && coauthorUser.id !== userId) {
          updateData.coauthor_user_id = coauthorUser.id;
        } else {
          updateData.coauthor_user_id = null;
        }
      } else {
        updateData.coauthor_user_id = null;
      }
    }

    const { data, error } = await supabaseAdmin
      .from('news')
      .update(updateData)
      .eq('id', id)
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url),
        coauthor:coauthor_user_id (id, username, name, avatar_url),
        category:category_id (id, name_en, name_ru, icon),
        subcategory:subcategory_id (id, name_en, name_ru)
      `)
      .single();

    if (error) throw error;

    res.json(data);
  } catch (error) {
    logger.error('Error updating news', error);
    res.status(500).json({ error: error.message });
  }
});

// Delete news article
router.delete('/:id', validateAuth, validateNewsId, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    // Check if news exists and user owns it
    const { data: existingNews, error: fetchError } = await supabaseAdmin
      .from('news')
      .select('user_id')
      .eq('id', id)
      .single();

    if (fetchError) throw fetchError;
    if (!existingNews) {
      return res.status(404).json({ message: 'News not found' });
    }

    if (existingNews.user_id !== userId) {
      return res.status(403).json({ message: 'You can only delete your own news' });
    }

    const { error } = await supabaseAdmin
      .from('news')
      .delete()
      .eq('id', id);

    if (error) throw error;

    res.json({ message: 'News deleted successfully' });
  } catch (error) {
    logger.error('Error deleting news', error);
    res.status(500).json({ error: error.message });
  }
});

// Like/unlike news
router.post('/:id/like', validateAuth, validateNewsId, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;

    // Check if news exists
    const { data: news, error: newsError } = await supabaseAdmin
      .from('news')
      .select('id, is_published, user_id')
      .eq('id', id)
      .single();

    if (newsError) throw newsError;
    if (!news) {
      return res.status(404).json({ message: 'News not found' });
    }

    // Check if user can view this news
    if (!news.is_published && news.user_id !== userId) {
      return res.status(403).json({ message: 'Access denied' });
    }

    // Check if already liked
    const { data: existingLike } = await supabaseAdmin
      .from('news_likes')
      .select('id')
      .eq('news_id', id)
      .eq('user_id', userId)
      .single();

    if (existingLike) {
      // Unlike
      const { error } = await supabaseAdmin
        .from('news_likes')
        .delete()
        .eq('id', existingLike.id);

      if (error) throw error;

      // Note: Unlike doesn't typically create notifications

      res.json({ liked: false });
    } else {
      // Like
      const { error } = await supabaseAdmin
        .from('news_likes')
        .insert([{ news_id: id, user_id: userId }]);

      if (error) throw error;

      // Create notification only if not own news
      if (news.user_id !== userId) {
        await createNotification(news.user_id, userId, 'news_like', null, null, { news_id: id });
      }

      res.json({ liked: true });
    }
  } catch (error) {
    logger.error('Error liking/unliking news', error);
    res.status(500).json({ error: error.message });
  }
});

// Get all categories and subcategories
router.get('/categories/all', validateAuth, async (req, res) => {
  try {
    const { data: categories, error: catError } = await supabaseAdmin
      .from('news_categories')
      .select('*')
      .order('order_index', { ascending: true });

    if (catError) throw catError;

    const { data: subcategories, error: subError } = await supabaseAdmin
      .from('news_subcategories')
      .select('*')
      .order('order_index', { ascending: true });

    if (subError) throw subError;

    // Group subcategories by category
    const categoriesWithSubs = categories.map(category => ({
      ...category,
      subcategories: subcategories.filter(sub => sub.category_id === category.id)
    }));

    res.json({ categories: categoriesWithSubs });
  } catch (error) {
    logger.error('Error fetching categories', error);
    res.status(500).json({ error: error.message });
  }
});

// Get news by category
router.get('/category/:categoryId', validateAuth, validateCategoryId, async (req, res) => {
  try {
    const { categoryId } = req.params;
    const { page = 1, limit = 10 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;
    const userId = req.user.id;

    const { data, error, count } = await supabaseAdmin
      .from('news')
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url),
        coauthor:coauthor_user_id (id, username, name, avatar_url),
        category:category_id (id, name_en, name_ru, icon),
        subcategory:subcategory_id (id, name_en, name_ru),
        likes(count)
      `, { count: 'exact' })
      .eq('category_id', categoryId)
      .eq('is_published', true)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    // Get user's likes
    const newsIds = data.map(news => news.id);
    const { data: userLikes } = await supabaseAdmin
      .from('news_likes')
      .select('news_id')
      .eq('user_id', userId)
      .in('news_id', newsIds);

    const likedNewsIds = new Set(userLikes?.map(like => like.news_id) || []);

    const newsWithLikes = data.map(news => ({
      ...news,
      likes_count: news.likes?.[0]?.count || 0,
      is_liked: likedNewsIds.has(news.id),
      likes: undefined
    }));

    res.json({
      news: newsWithLikes,
      total: count,
      page: parseInt(page),
      totalPages: Math.ceil(count / limit)
    });
  } catch (error) {
    logger.error('Error fetching news by category', error);
    res.status(500).json({ error: error.message });
  }
});

// Get comments for a news article
router.get('/:id/comments', validateAuth, validateNewsId, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id;
    const { page = 1, limit = 20 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    // Get top-level comments (parent_comment_id is null)
    const { data: comments, error, count } = await supabaseAdmin
      .from('news_comments')
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url)
      `, { count: 'exact' })
      .eq('news_id', id)
      .is('parent_comment_id', null)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    // Get total count of ALL comments (including replies) for this news
    const { count: totalCommentsCount } = await supabaseAdmin
      .from('news_comments')
      .select('id', { count: 'exact', head: true })
      .eq('news_id', id);

    // Get comment IDs for all comments (including replies)
    const commentIds = comments.map(c => c.id);
    
    // Get replies for each comment
    let replies = [];
    if (commentIds.length > 0) {
      const { data: repliesData, error: repliesError } = await supabaseAdmin
        .from('news_comments')
        .select(`
          *,
          profiles:user_id (id, username, name, avatar_url)
        `)
        .in('parent_comment_id', commentIds)
        .order('created_at', { ascending: true });

      if (repliesError) throw repliesError;
      replies = repliesData || [];
    }

    // Process comments and replies
    const allComments = [...comments, ...replies];
    allComments.forEach(comment => {
      comment.likes_count = comment.likes_count || 0;
      comment.dislikes_count = comment.dislikes_count || 0;
    });

    // Group replies by parent_comment_id
    const repliesMap = {};
    replies.forEach(reply => {
      if (!repliesMap[reply.parent_comment_id]) {
        repliesMap[reply.parent_comment_id] = [];
      }
      repliesMap[reply.parent_comment_id].push(reply);
    });

    // Add replies to each comment
    const commentsWithReplies = comments.map(comment => ({
      ...comment,
      replies: repliesMap[comment.id] || []
    }));

    res.json({
      comments: commentsWithReplies,
      total: totalCommentsCount || 0,
      page: parseInt(page),
      totalPages: Math.ceil((totalCommentsCount || 0) / limit)
    });
  } catch (error) {
    logger.error('Error fetching news comments', error);
    res.status(500).json({ error: error.message });
  }
});

// Create comment on news
router.post('/:id/comments', validateAuth, validateNewsId, validateComment, async (req, res) => {
  try {
    const { id } = req.params;
    const { content, parent_comment_id } = req.body;
    const userId = req.user.id;

    if (!content || content.trim().length === 0) {
      return res.status(400).json({ message: 'Comment content is required' });
    }

    // Check if news exists and get owner
    const { data: news, error: newsError } = await supabaseAdmin
      .from('news')
      .select('id, user_id, coauthor_user_id')
      .eq('id', id)
      .single();

    if (newsError || !news) {
      return res.status(404).json({ message: 'News not found' });
    }

    // If replying to a comment, check if parent comment exists
    if (parent_comment_id) {
      const { data: parentComment, error: parentError } = await supabaseAdmin
        .from('news_comments')
        .select('id, user_id')
        .eq('id', parent_comment_id)
        .eq('news_id', id)
        .single();

      if (parentError || !parentComment) {
        return res.status(404).json({ message: 'Parent comment not found' });
      }
    }

    // Create comment
    const { data, error } = await supabaseAdmin
      .from('news_comments')
      .insert([
        {
          news_id: id,
          user_id: userId,
          parent_comment_id: parent_comment_id || null,
          content: content.trim()
        }
      ])
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url)
      `)
      .single();

    if (error) throw error;

    // Create notification for news owner (if not self-comment)
    const newsOwnerId = news.user_id;
    if (newsOwnerId !== userId) {
      await createNotification(newsOwnerId, userId, 'news_comment', null, null, {
        news_id: id,
      });
    }

    // If this is a reply, notify the parent comment owner
    if (parent_comment_id) {
      const { data: parentComment } = await supabaseAdmin
        .from('news_comments')
        .select('user_id')
        .eq('id', parent_comment_id)
        .single();

      if (parentComment && parentComment.user_id !== userId && parentComment.user_id !== newsOwnerId) {
        // Notify parent comment owner (only if not already notified as news owner)
        await createNotification(parentComment.user_id, userId, 'comment_reply', null, data.id, {
          news_id: id,
        });
      }
    }

    res.status(201).json(data);
  } catch (error) {
    logger.error('Error creating news comment', error);
    res.status(500).json({ error: error.message });
  }
});

// Update news comment
router.put('/:id/comments/:commentId', validateAuth, validateNewsId, validateCommentId, validateComment, async (req, res) => {
  try {
    const { id, commentId } = req.params;
    const { content } = req.body;
    const userId = req.user.id;

    // Check if comment exists and belongs to user
    const { data: comment, error: commentError } = await supabaseAdmin
      .from('news_comments')
      .select('id, user_id, news_id')
      .eq('id', commentId)
      .eq('news_id', id)
      .single();

    if (commentError || !comment) {
      return res.status(404).json({ message: 'Comment not found' });
    }

    if (comment.user_id !== userId) {
      return res.status(403).json({ message: 'You can only edit your own comments' });
    }

    // Update comment
    const { data: updatedComment, error: updateError } = await supabaseAdmin
      .from('news_comments')
      .update({ content: content.trim() })
      .eq('id', commentId)
      .select(`
        *,
        profiles:user_id (id, username, name, avatar_url)
      `)
      .single();

    if (updateError) throw updateError;

    res.json(updatedComment);
  } catch (error) {
    logger.error('Error updating news comment', error);
    res.status(500).json({ error: error.message });
  }
});

// Delete news comment
router.delete('/:id/comments/:commentId', validateAuth, validateNewsId, validateCommentId, async (req, res) => {
  try {
    const { id, commentId } = req.params;
    const userId = req.user.id;

    // Check if comment exists and belongs to user
    const { data: comment, error: commentError } = await supabaseAdmin
      .from('news_comments')
      .select('id, user_id, news_id')
      .eq('id', commentId)
      .eq('news_id', id)
      .single();

    if (commentError || !comment) {
      return res.status(404).json({ message: 'Comment not found' });
    }

    if (comment.user_id !== userId) {
      return res.status(403).json({ message: 'You can only delete your own comments' });
    }

    // Delete comment (cascade will handle replies)
    const { error: deleteError } = await supabaseAdmin
      .from('news_comments')
      .delete()
      .eq('id', commentId);

    if (deleteError) throw deleteError;

    res.json({ message: 'Comment deleted successfully' });
  } catch (error) {
    logger.error('Error deleting news comment', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

