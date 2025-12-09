import express from 'express';
import { supabase, supabaseAdmin } from '../config/supabase.js';
import { validateAuth } from '../middleware/auth.middleware.js';
import { validateSignup, validateLogin } from '../middleware/validation.middleware.js';
import { logger } from '../utils/logger.js';
import { generateOTP, hashOTP, verifyOTP, getOTPExpirationTime } from '../utils/otp_utils.js';
import { sendOTPEmail } from '../utils/email_service.js';
import { maskEmail } from '../utils/email_mask_utils.js';

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
    const { email, password, username, name, gender, birth_date } = req.body;
    
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

    // Prepare profile data
    const profileData = {
      id: data.user.id,
      username,
      name,
      email,
      birth_date: birth_date || null,
    };

    // Only include gender if provided
    if (gender && ['male', 'female', 'secret'].includes(gender)) {
      profileData.gender = gender;
    }

    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .insert([profileData]);

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

// Request OTP for password change
router.post('/password/request-otp', validateAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const userEmail = req.user.email;

    if (!supabaseAdmin) {
      throw new Error('Service role key not configured');
    }

    // Generate OTP code
    const otpCode = generateOTP();
    const hashedOTP = hashOTP(otpCode);
    const expiresAt = getOTPExpirationTime();

    // Save OTP to database
    const { error: insertError } = await supabaseAdmin
      .from('password_change_otp')
      .insert([
        {
          user_id: userId,
          otp_code: hashedOTP,
          expires_at: expiresAt.toISOString(),
        },
      ]);

    if (insertError) {
      logger.authError('Error saving OTP', insertError);
      throw insertError;
    }

    // Send OTP via email
    try {
      await sendOTPEmail(userEmail, otpCode);
      logger.auth('OTP email sent successfully', { 
        userId, 
        email: userEmail,
        expiresAt: expiresAt.toISOString() 
      });
    } catch (emailError) {
      // Log error but don't fail the request
      // OTP is saved in DB, user can still use it
      logger.authError('Failed to send OTP email', emailError);
      console.error(`[EMAIL] Failed to send OTP email to ${userEmail}:`, emailError);
      // In development, log the OTP
      if (process.env.NODE_ENV === 'development') {
        console.log(`[DEV] OTP Code for ${userEmail}: ${otpCode}`);
      }
    }

    res.json({ 
      message: 'OTP code has been sent to your email'
    });
  } catch (error) {
    logger.authError('Error requesting OTP', error);
    res.status(500).json({ error: error.message || 'Failed to request OTP' });
  }
});

// Change password with OTP verification
router.post('/password/change', validateAuth, async (req, res) => {
  try {
    const { otp_code, new_password } = req.body;
    const userId = req.user.id;

    // Validate inputs
    if (!otp_code || otp_code.trim().length !== 6) {
      return res.status(400).json({ error: 'Valid 6-digit OTP code is required' });
    }

    if (!new_password || new_password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    if (!supabaseAdmin) {
      throw new Error('Service role key not configured');
    }

    // Get the latest unused OTP for this user
    const { data: otpRecords, error: fetchError } = await supabaseAdmin
      .from('password_change_otp')
      .select('*')
      .eq('user_id', userId)
      .eq('used', false)
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1);

    if (fetchError) {
      logger.authError('Error fetching OTP', fetchError);
      throw fetchError;
    }

    if (!otpRecords || otpRecords.length === 0) {
      logger.authError('No valid OTP found', { userId });
      return res.status(400).json({ error: 'Invalid or expired OTP code' });
    }

    const otpRecord = otpRecords[0];

    // Verify OTP
    const isValid = verifyOTP(otp_code.trim(), otpRecord.otp_code);
    if (!isValid) {
      logger.authError('Invalid OTP code', { userId });
      return res.status(400).json({ error: 'Invalid OTP code' });
    }

    // Mark OTP as used
    const { error: updateError } = await supabaseAdmin
      .from('password_change_otp')
      .update({ used: true })
      .eq('id', otpRecord.id);

    if (updateError) {
      logger.authError('Error marking OTP as used', updateError);
      throw updateError;
    }

    // Update password using Supabase Admin
    const { error: passwordError } = await supabaseAdmin.auth.admin.updateUserById(
      userId,
      { password: new_password }
    );

    if (passwordError) {
      logger.authError('Error updating password', passwordError);
      throw passwordError;
    }

    logger.auth('Password changed successfully', { userId });

    res.json({ message: 'Password changed successfully' });
  } catch (error) {
    logger.authError('Error changing password', error);
    res.status(500).json({ error: error.message || 'Failed to change password' });
  }
});

// Password Reset Flow (without authentication)

// Step 1: Initiate password reset - verify user exists and return profile info
router.post('/password/reset/initiate', async (req, res) => {
  try {
    const { identifier } = req.body;

    if (!identifier || identifier.trim().length === 0) {
      return res.status(400).json({ error: 'Username or email is required' });
    }

    const trimmedIdentifier = identifier.trim();
    
    // Determine if identifier is email or username
    const isEmail = trimmedIdentifier.includes('@');
    
    let profile;
    
    if (isEmail) {
      // Search by email
      const { data, error } = await supabaseAdmin
        .from('profiles')
        .select('id, username, name, avatar_url, email')
        .eq('email', trimmedIdentifier)
        .single();
      
      if (error || !data) {
        logger.authError('Password reset initiate - user not found by email', { identifier: trimmedIdentifier });
        return res.status(404).json({ error: 'User not found' });
      }
      
      profile = data;
    } else {
      // Search by username
      const { data, error } = await supabaseAdmin
        .from('profiles')
        .select('id, username, name, avatar_url, email')
        .ilike('username', trimmedIdentifier)
        .single();
      
      if (error || !data) {
        logger.authError('Password reset initiate - user not found by username', { identifier: trimmedIdentifier });
        return res.status(404).json({ error: 'User not found' });
      }
      
      profile = data;
    }

    logger.auth('Password reset initiated', { userId: profile.id, identifier: trimmedIdentifier });

    // Return user profile info for confirmation
    // Mask email for security - only show partial email
    res.json({
      username: profile.username,
      name: profile.name,
      avatar_url: profile.avatar_url,
      email: maskEmail(profile.email) // Return masked email for security
    });
  } catch (error) {
    logger.authError('Error initiating password reset', error);
    res.status(500).json({ error: error.message || 'Failed to initiate password reset' });
  }
});

// Step 2: Send OTP code to user's email
router.post('/password/reset/send-otp', async (req, res) => {
  try {
    const { identifier } = req.body;

    if (!identifier || identifier.trim().length === 0) {
      return res.status(400).json({ error: 'Username or email is required' });
    }

    if (!supabaseAdmin) {
      throw new Error('Service role key not configured');
    }

    const trimmedIdentifier = identifier.trim();
    
    // Determine if identifier is email or username
    const isEmail = trimmedIdentifier.includes('@');
    
    let profile;
    
    if (isEmail) {
      // Search by email
      const { data, error } = await supabaseAdmin
        .from('profiles')
        .select('id, email')
        .eq('email', trimmedIdentifier)
        .single();
      
      if (error || !data) {
        return res.status(404).json({ error: 'User not found' });
      }
      
      profile = data;
    } else {
      // Search by username
      const { data, error } = await supabaseAdmin
        .from('profiles')
        .select('id, email')
        .ilike('username', trimmedIdentifier)
        .single();
      
      if (error || !data) {
        return res.status(404).json({ error: 'User not found' });
      }
      
      profile = data;
    }

    // Generate OTP
    const otpCode = generateOTP();
    const hashedOTP = hashOTP(otpCode);
    const expiresAt = getOTPExpirationTime();

    // Save OTP to database
    const { error: insertError } = await supabaseAdmin
      .from('password_reset_otp')
      .insert([
        {
          user_id: profile.id,
          otp_code: hashedOTP,
          expires_at: expiresAt.toISOString(),
        },
      ]);

    if (insertError) {
      logger.authError('Error saving reset OTP', insertError);
      throw insertError;
    }

    // Send OTP via email
    try {
      await sendOTPEmail(profile.email, otpCode, 'password_reset');
      logger.auth('Password reset OTP sent successfully', { 
        userId: profile.id, 
        email: profile.email,
        expiresAt: expiresAt.toISOString() 
      });
    } catch (emailError) {
      // Log error but don't fail the request
      logger.authError('Failed to send reset OTP email', emailError);
      console.error(`[EMAIL] Failed to send reset OTP email to ${profile.email}:`, emailError);
      // In development, log the OTP
      if (process.env.NODE_ENV === 'development') {
        console.log(`[DEV] Reset OTP Code for ${profile.email}: ${otpCode}`);
      }
    }

    res.json({ 
      message: 'OTP code has been sent to your email'
    });
  } catch (error) {
    logger.authError('Error sending reset OTP', error);
    res.status(500).json({ error: error.message || 'Failed to send OTP' });
  }
});

// Step 3: Confirm password reset with OTP and new password
router.post('/password/reset/confirm', async (req, res) => {
  try {
    const { identifier, otp_code, new_password } = req.body;

    if (!identifier || identifier.trim().length === 0) {
      return res.status(400).json({ error: 'Username or email is required' });
    }

    if (!otp_code || otp_code.trim().length !== 6) {
      return res.status(400).json({ error: 'Valid 6-digit OTP code is required' });
    }

    if (!new_password || new_password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    if (!supabaseAdmin) {
      throw new Error('Service role key not configured');
    }

    const trimmedIdentifier = identifier.trim();
    
    // Determine if identifier is email or username
    const isEmail = trimmedIdentifier.includes('@');
    
    let profile;
    
    if (isEmail) {
      // Search by email
      const { data, error } = await supabaseAdmin
        .from('profiles')
        .select('id, email')
        .eq('email', trimmedIdentifier)
        .single();
      
      if (error || !data) {
        return res.status(404).json({ error: 'User not found' });
      }
      
      profile = data;
    } else {
      // Search by username
      const { data, error } = await supabaseAdmin
        .from('profiles')
        .select('id, email')
        .ilike('username', trimmedIdentifier)
        .single();
      
      if (error || !data) {
        return res.status(404).json({ error: 'User not found' });
      }
      
      profile = data;
    }

    // Get the latest unused OTP for this user
    const { data: otpRecords, error: fetchError } = await supabaseAdmin
      .from('password_reset_otp')
      .select('*')
      .eq('user_id', profile.id)
      .eq('used', false)
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1);

    if (fetchError) {
      logger.authError('Error fetching reset OTP', fetchError);
      throw fetchError;
    }

    if (!otpRecords || otpRecords.length === 0) {
      logger.authError('No valid reset OTP found', { userId: profile.id });
      return res.status(400).json({ error: 'Invalid or expired OTP code' });
    }

    const otpRecord = otpRecords[0];

    // Verify OTP
    const isValid = verifyOTP(otp_code.trim(), otpRecord.otp_code);
    if (!isValid) {
      logger.authError('Invalid reset OTP code', { userId: profile.id });
      return res.status(400).json({ error: 'Invalid OTP code' });
    }

    // Mark OTP as used
    const { error: updateError } = await supabaseAdmin
      .from('password_reset_otp')
      .update({ used: true })
      .eq('id', otpRecord.id);

    if (updateError) {
      logger.authError('Error marking reset OTP as used', updateError);
      throw updateError;
    }

    // Update password using Supabase Admin
    const { error: passwordError } = await supabaseAdmin.auth.admin.updateUserById(
      profile.id,
      { password: new_password }
    );

    if (passwordError) {
      logger.authError('Error updating password via reset', passwordError);
      throw passwordError;
    }

    logger.auth('Password reset successfully', { userId: profile.id });

    res.json({ message: 'Password reset successfully' });
  } catch (error) {
    logger.authError('Error confirming password reset', error);
    res.status(500).json({ error: error.message || 'Failed to reset password' });
  }
});

export default router;