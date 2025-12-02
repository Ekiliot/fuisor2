-- Add FCM token field to profiles table
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- Create index for faster lookups by FCM token
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token 
ON profiles(fcm_token) 
WHERE fcm_token IS NOT NULL;

-- Add comment to document the field
COMMENT ON COLUMN profiles.fcm_token IS 'Firebase Cloud Messaging token for push notifications';
