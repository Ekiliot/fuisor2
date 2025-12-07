-- Migration: Add recommendation settings to profiles
-- This migration adds fields for personalized location-based recommendations

-- ==============================================
-- 1. Add recommendation settings to profiles
-- ==============================================

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS recommendation_country VARCHAR(100),
ADD COLUMN IF NOT EXISTS recommendation_city VARCHAR(100),
ADD COLUMN IF NOT EXISTS recommendation_district VARCHAR(100),
ADD COLUMN IF NOT EXISTS recommendation_locations JSONB DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS recommendation_radius INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS recommendation_auto_location BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS recommendation_prompt_shown BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS recommendation_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS explorer_mode_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS explorer_mode_expires_at TIMESTAMPTZ;

-- ==============================================
-- 2. Add indexes for optimization
-- ==============================================

-- Index for filtering by district
CREATE INDEX IF NOT EXISTS idx_profiles_recommendation_district 
ON profiles(recommendation_district) 
WHERE recommendation_enabled = true;

-- Index for filtering by city
CREATE INDEX IF NOT EXISTS idx_profiles_recommendation_city 
ON profiles(recommendation_city) 
WHERE recommendation_enabled = true;

-- Index for explorer mode
CREATE INDEX IF NOT EXISTS idx_profiles_explorer_mode 
ON profiles(explorer_mode_enabled, explorer_mode_expires_at) 
WHERE explorer_mode_enabled = true;

-- ==============================================
-- 3. Add comments for documentation
-- ==============================================

COMMENT ON COLUMN profiles.recommendation_country IS 'Country for recommendations (in Romanian)';
COMMENT ON COLUMN profiles.recommendation_city IS 'City for recommendations (in Romanian)';
COMMENT ON COLUMN profiles.recommendation_district IS 'District for recommendations (in Romanian)';
COMMENT ON COLUMN profiles.recommendation_locations IS 'Array of up to 3 locations for multiple selection (JSONB)';
COMMENT ON COLUMN profiles.recommendation_radius IS 'Radius in meters (0-100000, i.e. 0-100km)';
COMMENT ON COLUMN profiles.recommendation_auto_location IS 'Auto-detect location on app start and pull-to-refresh';
COMMENT ON COLUMN profiles.recommendation_prompt_shown IS 'Whether the initial recommendation prompt has been shown';
COMMENT ON COLUMN profiles.recommendation_enabled IS 'Whether personalized recommendations are enabled';
COMMENT ON COLUMN profiles.explorer_mode_enabled IS 'Whether explorer mode is active';
COMMENT ON COLUMN profiles.explorer_mode_expires_at IS 'When explorer mode expires (15 minutes from activation)';

