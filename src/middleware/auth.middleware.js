import { supabase } from '../config/supabase.js';
import { logger } from '../utils/logger.js';

export const validateAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      logger.authError('No authorization header', { url: req.url, method: req.method });
      return res.status(401).json({ message: 'No authorization header' });
    }

    const token = authHeader.split(' ')[1];
    if (!token) {
      logger.authError('No token provided', { url: req.url });
      return res.status(401).json({ message: 'No token provided' });
    }

    const { data: { user }, error } = await supabase.auth.getUser(token);
    
    if (error) {
      logger.authError('Auth middleware error', { 
        error: error.message,
        url: req.url,
        tokenPreview: token.substring(0, 20) + '...'
      });
      return res.status(401).json({ message: 'Invalid or expired token' });
    }

    logger.auth('User authenticated', { userId: user.id, email: user.email, url: req.url });
    req.user = user;
    next();
  } catch (error) {
    logger.authError('Authentication failed', error);
    res.status(401).json({ message: 'Authentication failed' });
  }
};