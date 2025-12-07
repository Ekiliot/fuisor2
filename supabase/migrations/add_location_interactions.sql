-- Migration: Add location_interactions table for smart recommendations
-- This migration creates a table to track user interactions with posts from different locations

-- ==============================================
-- 1. Create location_interactions table
-- ==============================================

CREATE TABLE IF NOT EXISTS location_interactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  location_country VARCHAR(100),
  location_city VARCHAR(100),
  location_district VARCHAR(100),
  interaction_type VARCHAR(20) NOT NULL CHECK (interaction_type IN ('like')),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================
-- 2. Add indexes for optimization
-- ==============================================

-- Index for querying user interactions by location and time
CREATE INDEX IF NOT EXISTS idx_location_interactions_user_district_time 
ON location_interactions(user_id, location_district, created_at DESC);

-- Index for querying user interactions by time
CREATE INDEX IF NOT EXISTS idx_location_interactions_user_time 
ON location_interactions(user_id, created_at DESC);

-- Index for querying by post
CREATE INDEX IF NOT EXISTS idx_location_interactions_post 
ON location_interactions(post_id);

-- ==============================================
-- 3. Enable RLS (Row Level Security)
-- ==============================================

ALTER TABLE location_interactions ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only read their own interactions
CREATE POLICY "Users can read own interactions"
ON location_interactions
FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Users can insert their own interactions
CREATE POLICY "Users can insert own interactions"
ON location_interactions
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Users can delete their own interactions
CREATE POLICY "Users can delete own interactions"
ON location_interactions
FOR DELETE
USING (auth.uid() = user_id);

-- ==============================================
-- 4. Add comments for documentation
-- ==============================================

COMMENT ON TABLE location_interactions IS 'Tracks user interactions with posts from different locations for smart recommendations';
COMMENT ON COLUMN location_interactions.user_id IS 'User who interacted with the post';
COMMENT ON COLUMN location_interactions.location_country IS 'Country of the post location';
COMMENT ON COLUMN location_interactions.location_city IS 'City of the post location';
COMMENT ON COLUMN location_interactions.location_district IS 'District of the post location';
COMMENT ON COLUMN location_interactions.interaction_type IS 'Type of interaction (currently only "like")';
COMMENT ON COLUMN location_interactions.post_id IS 'Post that was interacted with';
COMMENT ON COLUMN location_interactions.created_at IS 'When the interaction occurred';

