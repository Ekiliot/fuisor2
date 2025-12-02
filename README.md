# Sonet Backend API

Backend service for Sonet - an Instagram-like social media application using Supabase as the database.

**Repository:** [https://github.com/Ekiliot/fuisor2](https://github.com/Ekiliot/fuisor2)

## 🚀 Quick Deploy

This backend is ready to deploy on:
- **Vercel** (recommended) - See `vercel.json`
- **Railway** - See `railway.json`
- **Render** - See `render.yaml`
- **Heroku** - See `Procfile`

For detailed deployment instructions, see [DEPLOYMENT.md](./DEPLOYMENT.md)

## Features

- User authentication (using Supabase Auth)
- Post management (create, read, update, delete)
- **Media upload and storage (images and videos)**
- User profiles
- Following/followers system
- Comments and likes
- **Support for both images and videos in posts**

## Setup

1. Clone the repository
2. Install dependencies:
```bash
npm install
```
3. Create a Supabase project and get your credentials
4. Copy `.env.example` to `.env` and fill in your Supabase credentials
5. Run the development server:
```bash
npm run dev
```

## API Endpoints

### Auth
- POST /api/auth/signup - Register a new user (with validation)
- POST /api/auth/login - Login user with email or username (with validation)
- POST /api/auth/logout - Logout user

### Posts
- GET /api/posts - Get all posts (with pagination and likes count)
- GET /api/posts/feed - Get feed posts from followed users (authenticated)
- GET /api/posts/:id - Get specific post (with comments and likes count)
- GET /api/posts/hashtag/:hashtag - Get posts by hashtag
- GET /api/posts/mentions - Get posts where user is mentioned (authenticated)
- POST /api/posts - Create new post with media (image/video), caption, mentions, and hashtags
- PUT /api/posts/:id - Update post caption (with validation)
- DELETE /api/posts/:id - Delete post

### Users
- GET /api/users/:id - Get user profile (with followers/following/posts count)
- GET /api/users/:id/posts - Get user's posts (with pagination)
- PUT /api/users/profile - Update user profile (with validation)
- POST /api/users/follow/:id - Follow user
- POST /api/users/unfollow/:id - Unfollow user

### Comments
- POST /api/posts/:id/comments - Add comment or reply to comment (with validation)
- DELETE /api/posts/:id/comments/:commentId - Delete comment

### Likes
- POST /api/posts/:id/like - Like/Unlike post (toggle functionality)

## Features Added

### ✅ Completed Features
- **Input Validation**: All endpoints now have proper validation using express-validator
- **Comments System**: Full CRUD operations for comments
- **Post Updates**: Users can now edit their post captions
- **Enhanced User Profiles**: Includes followers, following, and posts count
- **User Posts**: Get all posts from a specific user
- **Feed System**: Get posts from users you follow
- **Likes Count**: All post queries now include likes count
- **UUID Validation**: All ID parameters are validated as proper UUIDs
- **Error Handling**: Comprehensive error handling throughout the API
- **🎥 Video Support**: Posts now support both images and videos
- **📁 Media Storage**: Unified storage system for all post media
- **👤 Username Login**: Users can login with either email or username
- **💬 Comment Replies**: Support for nested comments and replies
- **👥 User Mentions**: Tag users in posts with @username
- **#️⃣ Hashtags**: Support for hashtags in posts

### 🔧 Technical Improvements
- **Middleware Validation**: Centralized validation middleware
- **Data Transformation**: Clean API responses with proper data structure
- **Security**: Enhanced security with proper authorization checks
- **Performance**: Optimized database queries with proper joins