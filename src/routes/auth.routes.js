import express from 'express';
import { supabase, supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { validateSignup, validateLogin } from '../middleware/validation.middleware.js';
import { logger } from '../utils/logger.js';

const router = express.Router();

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

export default router;