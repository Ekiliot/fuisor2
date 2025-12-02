-- Create table for password reset OTP codes
-- Reusing password_change_otp table structure but for password resets
-- Note: This uses the same table as password changes since the logic is identical

-- We can reuse the existing password_change_otp table for password resets
-- Or create a separate table for clarity

CREATE TABLE IF NOT EXISTS password_reset_otp (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  otp_code VARCHAR(255) NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  used BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create index for faster lookups
CREATE INDEX idx_password_reset_otp_user_id ON password_reset_otp(user_id);
CREATE INDEX idx_password_reset_otp_expires_at ON password_reset_otp(expires_at);
CREATE INDEX idx_password_reset_otp_user_used ON password_reset_otp(user_id, used);

-- Enable Row Level Security
ALTER TABLE password_reset_otp ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Service role can do anything (for API access)
CREATE POLICY "Service role can insert OTP codes"
  ON password_reset_otp
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Service role can update OTP codes"
  ON password_reset_otp
  FOR UPDATE
  USING (true);

CREATE POLICY "Service role can delete OTP codes"
  ON password_reset_otp
  FOR DELETE
  USING (true);

CREATE POLICY "Service role can select OTP codes"
  ON password_reset_otp
  FOR SELECT
  USING (true);

-- Function to cleanup expired OTP codes
CREATE OR REPLACE FUNCTION cleanup_expired_reset_otp_codes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM password_reset_otp
  WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$;

-- Grant necessary permissions
GRANT ALL ON password_reset_otp TO service_role;

-- Add comment
COMMENT ON TABLE password_reset_otp IS 'Stores OTP codes for password reset functionality';

