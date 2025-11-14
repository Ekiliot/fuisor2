import { body, param, validationResult } from 'express-validator';

// Validation middleware
export const validateRequest = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      message: 'Validation failed',
      errors: errors.array()
    });
  }
  next();
};

// Auth validation rules
export const validateSignup = [
  body('email')
    .isEmail()
    .normalizeEmail()
    .withMessage('Valid email is required'),
  body('password')
    .isLength({ min: 6 })
    .withMessage('Password must be at least 6 characters long'),
  body('username')
    .isLength({ min: 3, max: 30 })
    .matches(/^[a-zA-Z0-9_]+$/)
    .withMessage('Username must be 3-30 characters long and contain only letters, numbers, and underscores'),
  body('name')
    .isLength({ min: 1, max: 50 })
    .withMessage('Name must be 1-50 characters long'),
  validateRequest
];

export const validateLogin = [
  body('email_or_username')
    .notEmpty()
    .withMessage('Email or username is required'),
  body('password')
    .notEmpty()
    .withMessage('Password is required'),
  validateRequest
];

// Post validation rules
export const validatePost = [
  body('caption')
    .optional()
    .isLength({ max: 2000 })
    .withMessage('Caption must be less than 2000 characters'),
  body('media_type')
    .optional()
    .isIn(['image', 'video'])
    .withMessage('Media type must be either image or video'),
  validateRequest
];

export const validatePostUpdate = [
  body('caption')
    .optional()
    .isLength({ max: 2000 })
    .withMessage('Caption must be less than 2000 characters'),
  validateRequest
];

// Comment validation rules
export const validateComment = [
  body('content')
    .notEmpty()
    .trim()
    .isLength({ min: 1, max: 1000 })
    .withMessage('Comment content must be between 1 and 1000 characters'),
  validateRequest
];

// Profile validation rules
export const validateProfileUpdate = [
  body('username')
    .optional()
    .isLength({ min: 3, max: 30 })
    .matches(/^[a-zA-Z0-9_]+$/)
    .withMessage('Username must be 3-30 characters long and contain only letters, numbers, and underscores'),
  body('name')
    .optional()
    .isLength({ min: 1, max: 50 })
    .withMessage('Name must be 1-50 characters long'),
  body('bio')
    .optional()
    .isLength({ max: 500 })
    .withMessage('Bio must be less than 500 characters'),
  validateRequest
];

// UUID validation
export const validateUUID = [
  param('id')
    .isUUID()
    .withMessage('Invalid ID format'),
  validateRequest
];

export const validateChatId = [
  param('chatId')
    .isUUID()
    .withMessage('Invalid chat ID format'),
  validateRequest
];

export const validateMessageId = [
  param('messageId')
    .isUUID()
    .withMessage('Invalid message ID format'),
  validateRequest
];

export const validateCommentId = [
  param('commentId')
    .isUUID()
    .withMessage('Invalid comment ID format'),
  validateRequest
];
