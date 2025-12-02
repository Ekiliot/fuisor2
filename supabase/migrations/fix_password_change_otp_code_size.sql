-- Fix password_change_otp table: change otp_code from VARCHAR(6) to VARCHAR(255)
-- to accommodate hashed OTP codes (SHA-256 produces 64-character hex strings)

ALTER TABLE password_change_otp 
ALTER COLUMN otp_code TYPE VARCHAR(255);

-- Update comment to clarify that this stores hashed OTP
COMMENT ON COLUMN password_change_otp.otp_code IS 'Hashed OTP code (SHA-256, 64 characters)';

