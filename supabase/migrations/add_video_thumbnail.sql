-- Add thumbnail_url column to posts table for video thumbnails
-- Run this in Supabase SQL Editor

ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

-- Add comment
COMMENT ON COLUMN posts.thumbnail_url IS 'URL to thumbnail image for video posts';

