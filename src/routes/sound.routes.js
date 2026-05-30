import express from 'express';
import multer from 'multer';
import { supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { logger } from '../utils/logger.js';

const router = express.Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 20 * 1024 * 1024, // 20MB limit for audio
  },
});

// GET /api/sounds - Search/List sounds
router.get('/', validateAuth, async (req, res) => {
  try {
    const { query, page = 1, limit = 20 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    let supabaseQuery = supabaseAdmin
      .from('sounds')
      .select('*, author:author_id(id, username, name, avatar_url)', { count: 'exact' });

    if (query) {
      supabaseQuery = supabaseQuery.ilike('title', `%${query}%`);
    }

    const { data, count, error } = await supabaseQuery
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    res.json({
      sounds: data,
      total: count,
      page: parseInt(page),
      totalPages: Math.ceil((count || 0) / limit)
    });
  } catch (error) {
    logger.error('Error fetching sounds', error);
    res.status(500).json({ error: error.message });
  }
});

// GET /api/sounds/:id - Get sound details
router.get('/:id', validateAuth, async (req, res) => {
  try {
    const { id } = req.params;

    const { data, error } = await supabaseAdmin
      .from('sounds')
      .select('*, author:author_id(id, username, name, avatar_url)')
      .eq('id', id)
      .single();

    if (error) throw error;

    res.json(data);
  } catch (error) {
    logger.error(`Error fetching sound details for ${req.params.id}`, error);
    res.status(500).json({ error: error.message });
  }
});

// GET /api/sounds/:id/posts - Get posts using a specific sound
router.get('/:id/posts', validateAuth, async (req, res) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 20 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    const { data, count, error } = await supabaseAdmin
      .from('posts')
      .select(`*, profiles:user_id (username, name, avatar_url), likes(count), coauthor:coauthor_user_id (id, username, name, avatar_url), sound:sound_id (id, title, audio_url, author_id, duration, author:author_id(username, name))`, { count: 'exact' })
      .eq('sound_id', id)
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) throw error;

    res.json({
      posts: data,
      total: count,
      page: parseInt(page),
      totalPages: Math.ceil((count || 0) / limit)
    });
  } catch (error) {
    logger.error(`Error fetching posts for sound ${req.params.id}`, error);
    res.status(500).json({ error: error.message });
  }
});

// POST /api/sounds/upload - Upload a new sound extract
router.post('/upload', validateAuth, upload.single('audio'), async (req, res) => {
  try {
    const file = req.file;
    const { title, duration } = req.body;
    const userId = req.user.id;

    if (!file) {
      return res.status(400).json({ error: 'No audio file provided' });
    }

    if (!title || !duration) {
        return res.status(400).json({ error: 'Title and duration are required' });
    }

    const fileExt = file.originalname.split('.').pop()?.toLowerCase() || 'm4a';
    const fileName = `sound_${userId}_${Date.now()}.${fileExt}`;

    // Upload to Supabase Storage
    const { data: uploadData, error: uploadError } = await supabaseAdmin
      .storage
      .from('sounds')
      .upload(fileName, file.buffer, {
        contentType: file.mimetype || 'audio/m4a',
        upsert: false,
      });

    if (uploadError) {
      logger.error('Error uploading sound to Supabase', uploadError);
      return res.status(500).json({ error: 'Failed to upload sound: ' + uploadError.message });
    }

    const audioUrl = uploadData.path || fileName;

    // Insert into Sounds table
    const { data: soundData, error: dbError } = await supabaseAdmin
        .from('sounds')
        .insert([{
            title: title,
            audio_url: audioUrl,
            author_id: userId,
            duration: parseInt(duration),
        }])
        .select()
        .single();
    
    if (dbError) {
       logger.error('Error saving sound to DB', dbError);
       return res.status(500).json({ error: 'Failed to save sound info: ' + dbError.message });
    }

    res.status(201).json(soundData);
  } catch (error) {
    logger.error('Error in upload sound endpoint', error);
    res.status(500).json({ error: error.message });
  }
});

// GET /api/sounds/audio/signed-url - Get audio stream URL
router.get('/audio/signed-url', validateAuth, async (req, res) => {
    try {
      const { path } = req.query;
      
      if (!path) {
        return res.status(400).json({ error: 'Path parameter is required' });
      }
  
      const { data, error } = await supabaseAdmin
        .storage
        .from('sounds')
        .createSignedUrl(path, 604800); // 7 days
  
      if (error) throw error;
  
      res.json({ signedUrl: data.signedUrl });
    } catch (error) {
      logger.error('Error creating sound signed URL', error);
      res.status(500).json({ error: error.message });
    }
  });

export default router;
