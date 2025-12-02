-- Create table for password change OTP codes
CREATE TABLE IF NOT EXISTS password_change_otp (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  otp_code VARCHAR(6) NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  used BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create index for faster lookups
CREATE INDEX idx_password_change_otp_user_id ON password_change_otp(user_id);
CREATE INDEX idx_password_change_otp_expires_at ON password_change_otp(expires_at);
CREATE INDEX idx_password_change_otp_user_used ON password_change_otp(user_id, used);

-- Enable Row Level Security
ALTER TABLE password_change_otp ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can only see their own OTP codes (though this table should only be accessed via API)
CREATE POLICY "Users can view their own OTP codes"
  ON password_change_otp
  FOR SELECT
  USING (auth.uid() = user_id);

-- Only service role can insert OTP codes
CREATE POLICY "Service role can insert OTP codes"
  ON password_change_otp
  FOR INSERT
  WITH CHECK (true);

-- Only service role can update OTP codes
CREATE POLICY "Service role can update OTP codes"
  ON password_change_otp
  FOR UPDATE
  USING (true);

-- Function to cleanup expired OTP codes (optional, can be called periodically)
CREATE OR REPLACE FUNCTION cleanup_expired_otp_codes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM password_change_otp
  WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$;

-- Grant necessary permissions
GRANT ALL ON password_change_otp TO service_role;
GRANT SELECT ON password_change_otp TO authenticated;

