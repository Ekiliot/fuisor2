-- Migration: Add geolocation support for posts and location sharing for users
-- This migration adds latitude/longitude to posts and location sharing fields to profiles

-- ==============================================
-- 1. Add geolocation to posts table
-- ==============================================

-- Add latitude and longitude columns to posts
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Create index for geo-spatial queries (posts with location)
CREATE INDEX IF NOT EXISTS idx_posts_location ON posts(latitude, longitude)
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN posts.latitude IS 'Latitude of the post location (for geo-posts)';
COMMENT ON COLUMN posts.longitude IS 'Longitude of the post location (for geo-posts)';

-- ==============================================
-- 2. Add location sharing to profiles table
-- ==============================================

-- Add location sharing fields to profiles
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS location_sharing_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS last_location_lat DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS last_location_lng DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS last_location_updated_at TIMESTAMPTZ;

-- Create index for location sharing queries
CREATE INDEX IF NOT EXISTS idx_profiles_location_sharing ON profiles(location_sharing_enabled)
WHERE location_sharing_enabled = TRUE;

-- Create index for location updates
CREATE INDEX IF NOT EXISTS idx_profiles_location_updated ON profiles(last_location_updated_at DESC)
WHERE location_sharing_enabled = TRUE AND last_location_updated_at IS NOT NULL;

-- Add comments for documentation
COMMENT ON COLUMN profiles.location_sharing_enabled IS 'Whether user has enabled location sharing with friends';
COMMENT ON COLUMN profiles.last_location_lat IS 'Last known latitude of the user';
COMMENT ON COLUMN profiles.last_location_lng IS 'Last known longitude of the user';
COMMENT ON COLUMN profiles.last_location_updated_at IS 'Timestamp of last location update';

-- ==============================================
-- 3. RLS Policies (if needed)
-- ==============================================

-- Posts with location are viewable by everyone (same as regular posts)
-- Location sharing data is only viewable by friends (handled in API)

-- Note: RLS policies for location sharing will be handled in the API layer
-- to ensure only friends can see each other's locations

