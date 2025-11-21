-- Add website_url column to profiles table
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS website_url TEXT;

