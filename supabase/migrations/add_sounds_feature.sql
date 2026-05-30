-- Migration: Add Original Sounds feature

-- 1. Create sounds table
CREATE TABLE sounds (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title TEXT NOT NULL,
    audio_url TEXT NOT NULL,
    author_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    source_post_id UUID, -- References posts(id), will add foreign key after posts table modification
    duration INTEGER NOT NULL, -- Duration in seconds
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Modify posts table to add sound_id
ALTER TABLE posts
ADD COLUMN sound_id UUID REFERENCES sounds(id) ON DELETE SET NULL;

-- Now that posts table is modified, we can add the foreign key constraint back to sounds
ALTER TABLE sounds
ADD CONSTRAINT fk_source_post FOREIGN KEY (source_post_id) REFERENCES posts(id) ON DELETE SET NULL;

-- 3. Set up Storage for sounds
-- Create bucket if it doesn't exist (this might need to be run separately depending on your Supabase permissions)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('sounds', 'sounds', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for sounds
CREATE POLICY "Sound files are publicly accessible."
  ON storage.objects FOR SELECT
  USING ( bucket_id = 'sounds' );

CREATE POLICY "Authenticated users can upload sounds."
  ON storage.objects FOR INSERT
  WITH CHECK ( bucket_id = 'sounds' AND auth.role() = 'authenticated' );

-- 4. Enable RLS on sounds table
ALTER TABLE sounds ENABLE ROW LEVEL SECURITY;

-- 5. Create policies for sounds table
CREATE POLICY "Sounds are viewable by everyone."
  ON sounds FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can create sounds."
  ON sounds FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can update own sounds."
  ON sounds FOR UPDATE
  USING ( auth.uid() = author_id );

CREATE POLICY "Users can delete own sounds."
  ON sounds FOR DELETE
  USING ( auth.uid() = author_id );
