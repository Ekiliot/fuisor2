import EventEmitter from 'events';

class Logger extends EventEmitter {
  constructor() {
    super();
    this.logs = [];
    this.maxLogs = 1000;
    this.categories = {
      POSTS: 'POSTS',
      AUTH: 'AUTH',
      RECOMMENDATIONS: 'RECOMMENDATIONS',
      SEARCH: 'SEARCH',
      MESSAGES: 'MESSAGES',
      USERS: 'USERS',
      FOLLOW: 'FOLLOW',
      HASHTAGS: 'HASHTAGS',
      NOTIFICATIONS: 'NOTIFICATIONS',
      SERVER: 'SERVER',
      ERROR: 'ERROR',
      GENERAL: 'GENERAL'
    };
  }

  _addLog(category, level, message, data = null) {
    const logEntry = {
      id: Date.now() + Math.random(),
      timestamp: new Date(),
      category,
      level,
      message,
      data
    };

    this.logs.push(logEntry);
    
    // Keep only last maxLogs entries
    if (this.logs.length > this.maxLogs) {
      this.logs.shift();
    }

    // Emit event for CLI to listen
    this.emit('log', logEntry);
    
    return logEntry;
  }

  // Post logs
  post(message, data = null) {
    return this._addLog(this.categories.POSTS, 'info', message, data);
  }

  postError(message, error = null) {
    return this._addLog(this.categories.POSTS, 'error', message, error);
  }

  // Auth logs
  auth(message, data = null) {
    return this._addLog(this.categories.AUTH, 'info', message, data);
  }

  authError(message, error = null) {
    return this._addLog(this.categories.AUTH, 'error', message, error);
  }

  // Recommendations/Feed logs
  recommendations(message, data = null) {
    return this._addLog(this.categories.RECOMMENDATIONS, 'info', message, data);
  }

  recommendationsError(message, error = null) {
    return this._addLog(this.categories.RECOMMENDATIONS, 'error', message, error);
  }

  // Search logs
  search(message, data = null) {
    return this._addLog(this.categories.SEARCH, 'info', message, data);
  }

  searchError(message, error = null) {
    return this._addLog(this.categories.SEARCH, 'error', message, error);
  }

  // Messages logs
  messages(message, data = null) {
    return this._addLog(this.categories.MESSAGES, 'info', message, data);
  }

  messagesError(message, error = null) {
    return this._addLog(this.categories.MESSAGES, 'error', message, error);
  }

  // Users logs
  users(message, data = null) {
    return this._addLog(this.categories.USERS, 'info', message, data);
  }

  usersError(message, error = null) {
    return this._addLog(this.categories.USERS, 'error', message, error);
  }

  // Follow logs
  follow(message, data = null) {
    return this._addLog(this.categories.FOLLOW, 'info', message, data);
  }

  // Hashtags logs
  hashtags(message, data = null) {
    return this._addLog(this.categories.HASHTAGS, 'info', message, data);
  }

  // Notifications logs
  notifications(message, data = null) {
    return this._addLog(this.categories.NOTIFICATIONS, 'info', message, data);
  }

  // Server logs
  server(message, data = null) {
    return this._addLog(this.categories.SERVER, 'info', message, data);
  }

  serverError(message, error = null) {
    return this._addLog(this.categories.SERVER, 'error', message, error);
  }

  // General error logs
  error(message, error = null) {
    return this._addLog(this.categories.ERROR, 'error', message, error);
  }

  // General info logs
  info(message, data = null) {
    return this._addLog(this.categories.GENERAL, 'info', message, data);
  }

  // Get logs by category
  getLogsByCategory(category, limit = 100) {
    return this.logs
      .filter(log => log.category === category)
      .slice(-limit)
      .reverse();
  }

  // Get all logs
  getAllLogs(limit = 100) {
    return this.logs.slice(-limit).reverse();
  }

  // Clear logs
  clear() {
    this.logs = [];
    this.emit('clear');
  }

  // Get stats
  getStats() {
    const stats = {};
    Object.values(this.categories).forEach(category => {
      stats[category] = this.logs.filter(log => log.category === category).length;
    });
    return stats;
  }
}

// Export singleton instance
export const logger = new Logger();

// Also export for backward compatibility with console.log
export default logger;

