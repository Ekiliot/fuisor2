-- Migration: Add news likes and comments tables
-- Creates interaction tables for news (similar to posts)

-- Create news_likes table
CREATE TABLE IF NOT EXISTS news_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(news_id, user_id)
);

-- Create news_comments table
CREATE TABLE IF NOT EXISTS news_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  parent_comment_id UUID REFERENCES news_comments(id) ON DELETE CASCADE,
  likes_count INTEGER DEFAULT 0,
  dislikes_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_news_likes_news_id ON news_likes(news_id);
CREATE INDEX IF NOT EXISTS idx_news_likes_user_id ON news_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_news_comments_news_id ON news_comments(news_id);
CREATE INDEX IF NOT EXISTS idx_news_comments_user_id ON news_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_news_comments_parent_id ON news_comments(parent_comment_id) WHERE parent_comment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_news_comments_created_at ON news_comments(created_at DESC);

-- Enable RLS
ALTER TABLE news_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE news_comments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for news_likes
-- Anyone can view likes
CREATE POLICY "Anyone can view news likes"
  ON news_likes FOR SELECT
  USING (true);

-- Authenticated users can like/unlike news
CREATE POLICY "Authenticated users can like news"
  ON news_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can unlike own likes"
  ON news_likes FOR DELETE
  USING (auth.uid() = user_id);

-- RLS Policies for news_comments
-- Anyone can view comments on published news
CREATE POLICY "Anyone can view news comments"
  ON news_comments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM news 
      WHERE news.id = news_comments.news_id 
      AND news.is_published = true
    )
    OR EXISTS (
      SELECT 1 FROM news 
      WHERE news.id = news_comments.news_id 
      AND (news.user_id = auth.uid() OR news.coauthor_user_id = auth.uid())
    )
  );

-- Authenticated users can create comments
CREATE POLICY "Authenticated users can create news comments"
  ON news_comments FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own comments
CREATE POLICY "Users can update own news comments"
  ON news_comments FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Users can delete their own comments
CREATE POLICY "Users can delete own news comments"
  ON news_comments FOR DELETE
  USING (auth.uid() = user_id);

-- Trigger to update news likes_count
CREATE OR REPLACE FUNCTION update_news_likes_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE news 
    SET likes_count = likes_count + 1 
    WHERE id = NEW.news_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE news 
    SET likes_count = GREATEST(likes_count - 1, 0) 
    WHERE id = OLD.news_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_news_likes_count_trigger
  AFTER INSERT OR DELETE ON news_likes
  FOR EACH ROW
  EXECUTE FUNCTION update_news_likes_count();

-- Trigger to update news comments_count
CREATE OR REPLACE FUNCTION update_news_comments_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE news 
    SET comments_count = comments_count + 1 
    WHERE id = NEW.news_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE news 
    SET comments_count = GREATEST(comments_count - 1, 0) 
    WHERE id = OLD.news_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_news_comments_count_trigger
  AFTER INSERT OR DELETE ON news_comments
  FOR EACH ROW
  EXECUTE FUNCTION update_news_comments_count();

-- Trigger to update updated_at for comments
CREATE OR REPLACE FUNCTION update_news_comments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_news_comments_updated_at
  BEFORE UPDATE ON news_comments
  FOR EACH ROW
  EXECUTE FUNCTION update_news_comments_updated_at();

