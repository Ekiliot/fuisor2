import express from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { createNotification } from './notification.routes.js';

const router = express.Router();

// Follow a user
router.post('/:userId', validateAuth, async (req, res) => {
  try {
    const followingId = req.params.userId;
    const followerId = req.user.id;

    // Check if user is trying to follow themselves
    if (followerId === followingId) {
      return res.status(400).json({ error: 'Cannot follow yourself' });
    }

    // Check if already following
    const { data: existingFollow, error: checkError } = await supabaseAdmin
      .from('follows')
      .select('*')
      .eq('follower_id', followerId)
      .eq('following_id', followingId)
      .single();

    if (existingFollow) {
      return res.status(400).json({ error: 'Already following this user' });
    }

    // Create follow
    const { data: follow, error: followError } = await supabaseAdmin
      .from('follows')
      .insert({
        follower_id: followerId,
        following_id: followingId
      })
      .select()
      .single();

    if (followError) {
      console.error('Error creating follow:', followError);
      return res.status(500).json({ error: followError.message });
    }

    // Get actor info for notification
    const { data: actorInfo } = await supabaseAdmin
      .from('profiles')
      .select('username, name')
      .eq('id', followerId)
      .single();

    const actorName = actorInfo?.name || actorInfo?.username || 'Someone';

    // Create notification for the followed user (using createNotification which handles FCM)
    await createNotification(followingId, followerId, 'follow', null, null, {
      actorName,
    });

    res.status(201).json(follow);
  } catch (error) {
    console.error('Error following user:', error);
    res.status(500).json({ error: error.message });
  }
});

// Unfollow a user
router.delete('/:userId', validateAuth, async (req, res) => {
  try {
    const followingId = req.params.userId;
    const followerId = req.user.id;

    const { error } = await supabaseAdmin
      .from('follows')
      .delete()
      .eq('follower_id', followerId)
      .eq('following_id', followingId);

    if (error) {
      console.error('Error unfollowing user:', error);
      return res.status(500).json({ error: error.message });
    }

    // Delete follow notification
    await supabaseAdmin
      .from('notifications')
      .delete()
      .eq('user_id', followingId)
      .eq('actor_id', followerId)
      .eq('type', 'follow');

    res.json({ message: 'Unfollowed successfully' });
  } catch (error) {
    console.error('Error unfollowing user:', error);
    res.status(500).json({ error: error.message });
  }
});

// Check if following a user
router.get('/status/:userId', validateAuth, async (req, res) => {
  try {
    const followingId = req.params.userId;
    const followerId = req.user.id;

    const { data, error } = await supabaseAdmin
      .from('follows')
      .select('*')
      .eq('follower_id', followerId)
      .eq('following_id', followingId)
      .single();

    if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
      console.error('Error checking follow status:', error);
      return res.status(500).json({ error: error.message });
    }

    res.json({ isFollowing: !!data });
  } catch (error) {
    console.error('Error checking follow status:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get followers list
router.get('/followers/:userId', validateAuth, async (req, res) => {
  try {
    const userId = req.params.userId;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;

    // Get followers with profile info
    const { data: followers, error } = await supabaseAdmin
      .from('follows')
      .select(`
        follower_id,
        created_at,
        follower:follower_id (
          id,
          username,
          name,
          avatar_url,
          bio
        )
      `)
      .eq('following_id', userId)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      console.error('Error fetching followers:', error);
      return res.status(500).json({ error: error.message });
    }

    // Get total count
    const { count, error: countError } = await supabaseAdmin
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('following_id', userId);

    if (countError) {
      console.error('Error counting followers:', countError);
      return res.status(500).json({ error: countError.message });
    }

    // Transform data
    const transformedFollowers = followers.map(f => ({
      ...f.follower,
      followed_at: f.created_at
    }));

    res.json({
      followers: transformedFollowers,
      total: count,
      page,
      totalPages: Math.ceil(count / limit)
    });
  } catch (error) {
    console.error('Error fetching followers:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get following list
router.get('/following/:userId', validateAuth, async (req, res) => {
  try {
    const userId = req.params.userId;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;

    // Get following with profile info
    const { data: following, error } = await supabaseAdmin
      .from('follows')
      .select(`
        following_id,
        created_at,
        following:following_id (
          id,
          username,
          name,
          avatar_url,
          bio
        )
      `)
      .eq('follower_id', userId)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      console.error('Error fetching following:', error);
      return res.status(500).json({ error: error.message });
    }

    // Get total count
    const { count, error: countError } = await supabaseAdmin
      .from('follows')
      .select('*', { count: 'exact', head: true })
      .eq('follower_id', userId);

    if (countError) {
      console.error('Error counting following:', countError);
      return res.status(500).json({ error: countError.message });
    }

    // Transform data
    const transformedFollowing = following.map(f => ({
      ...f.following,
      followed_at: f.created_at
    }));

    res.json({
      following: transformedFollowing,
      total: count,
      page,
      totalPages: Math.ceil(count / limit)
    });
  } catch (error) {
    console.error('Error fetching following:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

