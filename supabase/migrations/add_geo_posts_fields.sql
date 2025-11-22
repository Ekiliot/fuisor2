-- Migration: Add visibility and expiration fields for geo-posts
-- This migration adds visibility and expires_at columns to posts table

-- ==============================================
-- 1. Add visibility column to posts table
-- ==============================================

-- Add visibility column with CHECK constraint
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'public' CHECK (visibility IN ('public', 'friends', 'private'));

-- Add comment for documentation
COMMENT ON COLUMN posts.visibility IS 'Post visibility: public (everyone), friends (mutual followers), private (author only)';

-- ==============================================
-- 2. Add expires_at column to posts table
-- ==============================================

-- Add expires_at column for geo-posts expiration
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Add comment for documentation
COMMENT ON COLUMN posts.expires_at IS 'Expiration timestamp for geo-posts (null for regular posts)';

-- ==============================================
-- 3. Create indexes for optimization
-- ==============================================

-- Index for filtering posts by visibility
CREATE INDEX IF NOT EXISTS idx_posts_visibility ON posts(visibility)
WHERE visibility IS NOT NULL;

-- Index for filtering expired posts
CREATE INDEX IF NOT EXISTS idx_posts_expires_at ON posts(expires_at)
WHERE expires_at IS NOT NULL;

-- Composite index for geo-posts queries (visibility + expiration + location)
CREATE INDEX IF NOT EXISTS idx_posts_geo_active ON posts(visibility, expires_at, latitude, longitude)
WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND expires_at IS NOT NULL;

-- ==============================================
-- 4. Update existing posts (optional)
-- ==============================================

-- Set default visibility for existing posts (if needed)
-- UPDATE posts SET visibility = 'public' WHERE visibility IS NULL;

