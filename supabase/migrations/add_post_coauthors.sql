-- Migration: Add post coauthors support
-- Allows one coauthor per post

-- Create post_coauthors table
CREATE TABLE IF NOT EXISTS post_coauthors (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
    coauthor_user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    -- Unique constraint to prevent duplicate coauthor entries
    UNIQUE(post_id, coauthor_user_id),
    -- Only one coauthor per post
    UNIQUE(post_id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_post_coauthors_post_id ON post_coauthors(post_id);
CREATE INDEX IF NOT EXISTS idx_post_coauthors_user_id ON post_coauthors(coauthor_user_id);

-- Enable RLS
ALTER TABLE post_coauthors ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Anyone can view coauthors
CREATE POLICY "Coauthors are viewable by everyone"
  ON post_coauthors FOR SELECT
  USING (true);

-- Authenticated users can create coauthor entries (post authors)
CREATE POLICY "Authenticated users can create coauthors"
  ON post_coauthors FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Post authors can delete coauthor entries from their posts
CREATE POLICY "Post authors can delete coauthors"
  ON post_coauthors FOR DELETE
  USING (
    auth.uid() IN (
      SELECT user_id FROM posts WHERE id = post_id
    )
  );

-- Add comment
COMMENT ON TABLE post_coauthors IS 'Stores post coauthors (maximum 1 per post)';
COMMENT ON COLUMN post_coauthors.post_id IS 'Reference to the post';
COMMENT ON COLUMN post_coauthors.coauthor_user_id IS 'User who is tagged as coauthor';

