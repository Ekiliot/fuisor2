-- Migration: Add news table
-- Creates table for news articles with HTML content, categories, coauthors, and external links

CREATE TABLE IF NOT EXISTS news (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  sanitized_content TEXT,
  category_id UUID NOT NULL REFERENCES news_categories(id) ON DELETE RESTRICT,
  subcategory_id UUID REFERENCES news_subcategories(id) ON DELETE SET NULL,
  cover_image_url TEXT,
  coauthor_user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  external_link_url TEXT,
  external_link_text VARCHAR(8),
  views_count INTEGER DEFAULT 0,
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  is_published BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_news_user_id ON news(user_id);
CREATE INDEX IF NOT EXISTS idx_news_category_id ON news(category_id);
CREATE INDEX IF NOT EXISTS idx_news_subcategory_id ON news(subcategory_id);
CREATE INDEX IF NOT EXISTS idx_news_coauthor_user_id ON news(coauthor_user_id) WHERE coauthor_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_news_created_at_desc ON news(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_news_views_count_desc ON news(views_count DESC);
CREATE INDEX IF NOT EXISTS idx_news_is_published ON news(is_published) WHERE is_published = true;
CREATE INDEX IF NOT EXISTS idx_news_external_link ON news(external_link_url) WHERE external_link_url IS NOT NULL;

-- Add comments
COMMENT ON COLUMN news.content IS 'Original HTML content from editor';
COMMENT ON COLUMN news.sanitized_content IS 'Sanitized HTML for safe display';
COMMENT ON COLUMN news.coauthor_user_id IS 'User ID of the news coauthor (only one coauthor per news allowed)';
COMMENT ON COLUMN news.external_link_url IS 'External URL for the news action button';
COMMENT ON COLUMN news.external_link_text IS 'Custom button text (6-8 characters)';

-- Enable RLS
ALTER TABLE news ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can view published news
CREATE POLICY "Anyone can view published news"
  ON news FOR SELECT
  USING (is_published = true);

-- Users can view their own news (even if unpublished)
CREATE POLICY "Users can view own news"
  ON news FOR SELECT
  USING (auth.uid() = user_id OR auth.uid() = coauthor_user_id);

-- Users can create news
CREATE POLICY "Authenticated users can create news"
  ON news FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own news
CREATE POLICY "Users can update own news"
  ON news FOR UPDATE
  USING (auth.uid() = user_id OR auth.uid() = coauthor_user_id)
  WITH CHECK (auth.uid() = user_id OR auth.uid() = coauthor_user_id);

-- Users can delete their own news
CREATE POLICY "Users can delete own news"
  ON news FOR DELETE
  USING (auth.uid() = user_id);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_news_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_news_updated_at
  BEFORE UPDATE ON news
  FOR EACH ROW
  EXECUTE FUNCTION update_news_updated_at();

