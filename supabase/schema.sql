-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create profiles table
CREATE TABLE profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    avatar_url TEXT,
    bio TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (id)
);

-- Create posts table
CREATE TABLE posts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    caption TEXT,
    media_url TEXT NOT NULL,
    media_type TEXT NOT NULL CHECK (media_type IN ('image', 'video')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create comments table
CREATE TABLE comments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create likes table
CREATE TABLE likes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, user_id)
);

-- Create follows table
CREATE TABLE follows (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    follower_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    following_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(follower_id, following_id)
);

-- Create notifications table
CREATE TABLE notifications (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('like', 'comment', 'comment_like', 'follow', 'mention')),
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create post mentions table
CREATE TABLE post_mentions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    mentioned_user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, mentioned_user_id)
);

-- Create hashtags table
CREATE TABLE hashtags (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create post hashtags table
CREATE TABLE post_hashtags (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    hashtag_id UUID REFERENCES hashtags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, hashtag_id)
);

-- Create sounds table
CREATE TABLE sounds (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title TEXT NOT NULL,
    audio_url TEXT NOT NULL,
    author_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    source_post_id UUID REFERENCES posts(id) ON DELETE SET NULL,
    duration INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Modify posts table to add sound_id
ALTER TABLE posts ADD COLUMN sound_id UUID REFERENCES sounds(id) ON DELETE SET NULL;

-- Create storage buckets
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true);
INSERT INTO storage.buckets (id, name, public) VALUES ('post-media', 'post-media', true);
INSERT INTO storage.buckets (id, name, public) VALUES ('sounds', 'sounds', true);

-- Set up storage policies
CREATE POLICY "Avatar images are publicly accessible."
  ON storage.objects FOR SELECT
  USING ( bucket_id = 'avatars' );

CREATE POLICY "Anyone can upload an avatar."
  ON storage.objects FOR INSERT
  WITH CHECK ( bucket_id = 'avatars' );

CREATE POLICY "Post media are publicly accessible."
  ON storage.objects FOR SELECT
  USING ( bucket_id = 'post-media' );

CREATE POLICY "Authenticated users can upload post media."
  ON storage.objects FOR INSERT
  WITH CHECK ( bucket_id = 'post-media' AND auth.role() = 'authenticated' );

CREATE POLICY "Sound files are publicly accessible."
  ON storage.objects FOR SELECT
  USING ( bucket_id = 'sounds' );

CREATE POLICY "Authenticated users can upload sounds."
  ON storage.objects FOR INSERT
  WITH CHECK ( bucket_id = 'sounds' AND auth.role() = 'authenticated' );

-- Set up RLS (Row Level Security)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_mentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE sounds ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Public profiles are viewable by everyone."
  ON profiles FOR SELECT
  USING ( true );

CREATE POLICY "Users can insert own profile."
  ON profiles FOR INSERT
  WITH CHECK ( auth.uid() = id );

CREATE POLICY "Users can update own profile."
  ON profiles FOR UPDATE
  USING ( auth.uid() = id );

-- Posts policies
CREATE POLICY "Posts are viewable by everyone."
  ON posts FOR SELECT
  USING ( true );

CREATE POLICY "Users can create posts."
  ON posts FOR INSERT
  WITH CHECK ( auth.uid() = user_id );

CREATE POLICY "Users can update own posts."
  ON posts FOR UPDATE
  USING ( auth.uid() = user_id );

CREATE POLICY "Users can delete own posts."
  ON posts FOR DELETE
  USING ( auth.uid() = user_id );

-- Comments policies
CREATE POLICY "Comments are viewable by everyone."
  ON comments FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can create comments."
  ON comments FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can delete own comments."
  ON comments FOR DELETE
  USING ( auth.uid() = user_id );

-- Likes policies
CREATE POLICY "Likes are viewable by everyone."
  ON likes FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can like posts."
  ON likes FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can remove own likes."
  ON likes FOR DELETE
  USING ( auth.uid() = user_id );

-- Follows policies
CREATE POLICY "Follows are viewable by everyone."
  ON follows FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can follow others."
  ON follows FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can unfollow."
  ON follows FOR DELETE
  USING ( auth.uid() = follower_id );

-- Notifications policies
CREATE POLICY "Users can view own notifications."
  ON notifications FOR SELECT
  USING ( auth.uid() = user_id );

CREATE POLICY "Authenticated users can create notifications."
  ON notifications FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can update own notifications."
  ON notifications FOR UPDATE
  USING ( auth.uid() = user_id );

CREATE POLICY "Users can delete own notifications."
  ON notifications FOR DELETE
  USING ( auth.uid() = user_id );

-- Post mentions policies
CREATE POLICY "Post mentions are viewable by everyone."
  ON post_mentions FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can create mentions."
  ON post_mentions FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can delete mentions from their posts."
  ON post_mentions FOR DELETE
  USING ( auth.uid() IN (
    SELECT user_id FROM posts WHERE id = post_id
  ));

-- Hashtags policies
CREATE POLICY "Hashtags are viewable by everyone."
  ON hashtags FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can create hashtags."
  ON hashtags FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

-- Post hashtags policies
CREATE POLICY "Post hashtags are viewable by everyone."
  ON post_hashtags FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can create post hashtags."
  ON post_hashtags FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can delete hashtags from their posts."
  ON post_hashtags FOR DELETE
  USING ( auth.uid() IN (
    SELECT user_id FROM posts WHERE id = post_id
  ));

-- Sounds policies
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

-- Create comment_likes table
CREATE TABLE comment_likes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(comment_id, user_id)
);

-- Create comment_dislikes table
CREATE TABLE comment_dislikes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(comment_id, user_id)
);

-- Set up RLS for comment likes/dislikes
ALTER TABLE comment_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE comment_dislikes ENABLE ROW LEVEL SECURITY;

-- Comment likes policies
CREATE POLICY "Comment likes are viewable by everyone."
  ON comment_likes FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can like comments."
  ON comment_likes FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can remove own comment likes."
  ON comment_likes FOR DELETE
  USING ( auth.uid() = user_id );

-- Comment dislikes policies
CREATE POLICY "Comment dislikes are viewable by everyone."
  ON comment_dislikes FOR SELECT
  USING ( true );

CREATE POLICY "Authenticated users can dislike comments."
  ON comment_dislikes FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' );

CREATE POLICY "Users can remove own comment dislikes."
  ON comment_dislikes FOR DELETE
  USING ( auth.uid() = user_id );

-- Create saved_posts table
CREATE TABLE saved_posts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, post_id)
);

-- Enable RLS for saved_posts
ALTER TABLE saved_posts ENABLE ROW LEVEL SECURITY;

-- Saved posts policies
CREATE POLICY "Users can view own saved posts."
  ON saved_posts FOR SELECT
  USING ( auth.uid() = user_id );

CREATE POLICY "Authenticated users can save posts."
  ON saved_posts FOR INSERT
  WITH CHECK ( auth.role() = 'authenticated' AND auth.uid() = user_id );

CREATE POLICY "Users can remove own saved posts."
  ON saved_posts FOR DELETE
  USING ( auth.uid() = user_id );