-- Migration: Add coauthor_user_id directly to posts table
-- Simplifies structure - no need for separate post_coauthors table when only 1 coauthor is allowed

-- Step 1: Add coauthor_user_id column to posts
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS coauthor_user_id UUID REFERENCES profiles(id) ON DELETE SET NULL;

-- Step 2: Migrate data from post_coauthors to posts
UPDATE posts p
SET coauthor_user_id = (
  SELECT pc.coauthor_user_id 
  FROM post_coauthors pc 
  WHERE pc.post_id = p.id 
  LIMIT 1
)
WHERE EXISTS (
  SELECT 1 FROM post_coauthors pc WHERE pc.post_id = p.id
);

-- Step 3: Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_posts_coauthor_user_id ON posts(coauthor_user_id) WHERE coauthor_user_id IS NOT NULL;

-- Step 4: Add comment
COMMENT ON COLUMN posts.coauthor_user_id IS 'User ID of the post coauthor (only one coauthor per post allowed)';

-- Note: We keep post_coauthors table for now for backward compatibility
-- It can be dropped later after verifying everything works

