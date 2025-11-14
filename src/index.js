import express from 'express';
import dotenv from 'dotenv';
import cors from 'cors';
import authRoutes from './routes/auth.routes.js';
import postRoutes from './routes/post.routes.js';
import userRoutes from './routes/user.routes.js';
import followRoutes from './routes/follow.routes.js';
import searchRoutes from './routes/search.routes.js';
import hashtagRoutes from './routes/hashtag.routes.js';
import { router as notificationRoutes } from './routes/notification.routes.js';
import messagesRoutes from './routes/messages.routes.js';
import { logger } from './utils/logger.js';

dotenv.config();

const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
  logger.info(`${req.method} ${req.path}`, {
    ip: req.ip,
    userAgent: req.get('user-agent')
  });
  next();
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/posts', (req, res, next) => {
  if (req.method === 'POST' && req.path.includes('/like')) {
    logger.post('POST request to /api/posts' + req.path, {
      method: req.method,
      path: req.path,
      postId: req.params?.id,
      headers: {
        authorization: req.headers.authorization ? 'Present' : 'Missing'
      }
    });
  }
  next();
}, postRoutes);
app.use('/api/users', userRoutes);
app.use('/api/follow', followRoutes);
app.use('/api/search', searchRoutes);
app.use('/api/hashtags', hashtagRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/messages', messagesRoutes);

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error('Server error', err);
  res.status(500).json({ message: 'Something went wrong!' });
});

// Для деплоя используем 0.0.0.0, для локальной разработки тоже
const host = process.env.HOST || '0.0.0.0';
const server = app.listen(port, host, () => {
  logger.server(`Server is running on ${host}:${port}`);
  if (process.env.NODE_ENV !== 'production') {
    logger.server(`Access from other devices: http://<YOUR_LOCAL_IP>:${port}`);
  }
});

// Обработка ошибки занятого порта
server.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    logger.serverError(`Port ${port} is already in use`);
    logger.serverError('Please wait, the manager will try to free the port...');
    // Менеджер обработает это через stderr
  } else {
    logger.serverError(`Server error: ${error.message}`);
  }
});