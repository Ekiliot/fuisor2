-- Migration: Add external link support to posts
-- Allows posts to have a custom button with URL and text

-- Add external link fields to posts table
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS external_link_url TEXT,
ADD COLUMN IF NOT EXISTS external_link_text VARCHAR(8);

-- Create index for posts with external links
CREATE INDEX IF NOT EXISTS idx_posts_external_link ON posts(external_link_url) WHERE external_link_url IS NOT NULL;

-- Add comments
COMMENT ON COLUMN posts.external_link_url IS 'External URL for the post action button';
COMMENT ON COLUMN posts.external_link_text IS 'Custom button text (6-8 characters)';

