-- Migration: Add location visibility settings for location sharing
-- This migration adds location_visibility field to profiles table

-- ==============================================
-- Add location_visibility column to profiles table
-- ==============================================

-- Add location_visibility column with CHECK constraint
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS location_visibility TEXT DEFAULT 'mutual_followers' 
CHECK (location_visibility IN ('nobody', 'mutual_followers', 'followers', 'close_friends'));

-- Add comment for documentation
COMMENT ON COLUMN profiles.location_visibility IS 'Who can see user location: nobody (nobody), mutual_followers (mutual followers), followers (all followers), close_friends (close friends list)';

-- ==============================================
-- Create table for close friends (like Instagram)
-- ==============================================

-- Create close_friends table for storing close friends relationships
CREATE TABLE IF NOT EXISTS close_friends (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    friend_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, friend_id)
);

-- Create index for close friends queries
CREATE INDEX IF NOT EXISTS idx_close_friends_user ON close_friends(user_id);
CREATE INDEX IF NOT EXISTS idx_close_friends_friend ON close_friends(friend_id);

-- Add comment for documentation
COMMENT ON TABLE close_friends IS 'Stores close friends relationships (like Instagram close friends list)';

-- ==============================================
-- RLS Policies for close_friends
-- ==============================================

ALTER TABLE close_friends ENABLE ROW LEVEL SECURITY;

-- Users can view their own close friends list
CREATE POLICY "Users can view own close friends"
  ON close_friends FOR SELECT
  USING (auth.uid() = user_id);

-- Users can add to their own close friends list
CREATE POLICY "Users can add to own close friends"
  ON close_friends FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can remove from their own close friends list
CREATE POLICY "Users can remove from own close friends"
  ON close_friends FOR DELETE
  USING (auth.uid() = user_id);

