import express from 'express';
import { supabase, supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { validateSignup, validateLogin } from '../middleware/validation.middleware.js';
import { logger } from '../utils/logger.js';

const router = express.Router();

// Check username availability
router.get('/check-username', async (req, res) => {
  try {
    const { username } = req.query;

    if (!username || username.trim().length === 0) {
      return res.status(400).json({ 
        available: false, 
        message: 'Username is required' 
      });
    }

    // Validate username format (3-30 characters, letters, numbers, dots, underscores)
    const usernameRegex = /^[a-zA-Z0-9._]+$/;
    if (!usernameRegex.test(username) || username.length < 3 || username.length > 30) {
      return res.status(400).json({ 
        available: false, 
        message: 'Invalid username format' 
      });
    }

    // Check if username exists
    const { data: existingUser, error: searchError } = await supabase
      .from('profiles')
      .select('username')
      .eq('username', username.trim())
      .single();

    // If user found, username is taken
    if (existingUser) {
      logger.auth('Username check - already taken', { username });
      return res.json({ available: false });
    }

    // If error is "not found" (PGRST116), username is available
    if (searchError && searchError.code === 'PGRST116') {
      logger.auth('Username check - available', { username });
      return res.json({ available: true });
    }

    // Other errors
    if (searchError) {
      logger.authError('Username check error', searchError);
      // In case of error, assume available to not block registration
      return res.json({ available: true });
    }

    // No user found, username is available
    logger.auth('Username check - available', { username });
    res.json({ available: true });
  } catch (error) {
    logger.authError('Username check error', error);
    // In case of error, assume available to not block registration
    res.json({ available: true });
  }
});

// Check email availability
router.get('/check-email', async (req, res) => {
  try {
    const { email } = req.query;

    if (!email || email.trim().length === 0) {
      return res.status(400).json({ 
        available: false, 
        message: 'Email is required' 
      });
    }

    // Validate email format
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ 
        available: false, 
        message: 'Invalid email format' 
      });
    }

    // Check if email exists
    const { data: existingUser, error: searchError } = await supabase
      .from('profiles')
      .select('email')
      .eq('email', email.trim())
      .single();

    // If user found, email is taken
    if (existingUser) {
      logger.auth('Email check - already taken', { email });
      return res.json({ available: false });
    }

    // If error is "not found" (PGRST116), email is available
    if (searchError && searchError.code === 'PGRST116') {
      logger.auth('Email check - available', { email });
      return res.json({ available: true });
    }

    // Other errors
    if (searchError) {
      logger.authError('Email check error', searchError);
      // In case of error, assume available to not block registration
      return res.json({ available: true });
    }

    // No user found, email is available
    logger.auth('Email check - available', { email });
    res.json({ available: true });
  } catch (error) {
    logger.authError('Email check error', error);
    // In case of error, assume available to not block registration
    res.json({ available: true });
  }
});

// Sign up
router.post('/signup', validateSignup, async (req, res) => {
  try {
    const { email, password, username, name } = req.body;
    
    const { data: existingUser, error: searchError } = await supabase
      .from('profiles')
      .select('username')
      .eq('username', username)
      .single();

    if (existingUser) {
      logger.auth('Registration attempt with existing username', { username });
      return res.status(400).json({ message: 'Username already taken' });
    }

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
    });

    if (error) throw error;

    // Create profile using admin client to bypass RLS
    if (!supabaseAdmin) {
      throw new Error('Service role key not configured');
    }

    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .insert([
        {
          id: data.user.id,
          username,
          name,
          email,
        },
      ]);

    if (profileError) {
      logger.authError('Profile creation error', profileError);
      throw profileError;
    }

    logger.auth('User registered successfully', { userId: data.user.id, username, email });
    res.status(201).json({ message: 'User created successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Login
router.post('/login', validateLogin, async (req, res) => {
  try {
    const { email_or_username, password } = req.body;

    // Determine if input is email or username
    const isEmail = email_or_username.includes('@');
    
    let userEmail;
    
    if (isEmail) {
      // Input is email, use directly
      userEmail = email_or_username;
    } else {
      // Input is username, find corresponding email
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('email')
        .eq('username', email_or_username)
        .single();

      if (profileError || !profile) {
        logger.auth('Login attempt with invalid username', { email_or_username });
        return res.status(401).json({ error: 'Invalid username or password' });
      }
      
      userEmail = profile.email;
    }

    const { data, error } = await supabase.auth.signInWithPassword({
      email: userEmail,
      password,
    });

    if (error) {
      logger.authError('Login failed', { email_or_username, error: error.message });
      throw error;
    }

    // Get user profile for additional info
    const { data: userProfile } = await supabase
      .from('profiles')
      .select('username, name, avatar_url, bio')
      .eq('id', data.user.id)
      .single();

    logger.auth('User logged in successfully', { userId: data.user.id, username: userProfile?.username });

    res.json({ 
      user: data.user, 
      session: data.session,
      profile: userProfile
    });
  } catch (error) {
    logger.authError('Login error', error);
    res.status(401).json({ error: error.message });
  }
});

// Logout
router.post('/logout', validateAuth, async (req, res) => {
  try {
    const { error } = await supabase.auth.signOut();
    if (error) {
      logger.authError('Logout error', error);
      throw error;
    }
    logger.auth('User logged out', { userId: req.user.id });
    res.json({ message: 'Logged out successfully' });
  } catch (error) {
    logger.authError('Logout error', error);
    res.status(500).json({ error: error.message });
  }
});

// Get Supabase credentials for client-side uploads
router.get('/supabase-config', async (req, res) => {
  try {
    // Возвращаем только публичные credentials (anon key безопасен для клиента)
    res.json({
      supabaseUrl: process.env.SUPABASE_URL,
      supabaseAnonKey: process.env.SUPABASE_ANON_KEY,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

export default router;