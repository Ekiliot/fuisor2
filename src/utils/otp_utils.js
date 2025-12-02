import crypto from 'crypto';

/**
 * Generate a random 6-digit OTP code
 * @returns {string} 6-digit OTP code
 */
export function generateOTP() {
  // Generate random 6-digit number
  const otp = Math.floor(100000 + Math.random() * 900000);
  return otp.toString();
}

/**
 * Hash an OTP code for secure storage
 * @param {string} otp - The OTP code to hash
 * @returns {string} Hashed OTP
 */
export function hashOTP(otp) {
  return crypto
    .createHash('sha256')
    .update(otp)
    .digest('hex');
}

/**
 * Verify an OTP code against a hashed version
 * @param {string} inputOtp - The OTP code to verify
 * @param {string} hashedOtp - The hashed OTP to compare against
 * @returns {boolean} True if OTP matches
 */
export function verifyOTP(inputOtp, hashedOtp) {
  const inputHash = hashOTP(inputOtp);
  return inputHash === hashedOtp;
}

/**
 * Cleanup expired OTP codes from the database
 * @param {object} supabaseAdmin - Supabase admin client
 * @returns {Promise<void>}
 */
export async function cleanupExpiredOTPs(supabaseAdmin) {
  try {
    const { error } = await supabaseAdmin
      .from('password_change_otp')
      .delete()
      .lt('expires_at', new Date().toISOString());

    if (error) {
      console.error('Error cleaning up expired OTPs:', error);
    } else {
      console.log('Expired OTPs cleaned up successfully');
    }
  } catch (error) {
    console.error('Error in cleanupExpiredOTPs:', error);
  }
}

/**
 * Get expiration time for OTP (10 minutes from now)
 * @returns {Date} Expiration timestamp
 */
export function getOTPExpirationTime() {
  const expiresAt = new Date();
  expiresAt.setMinutes(expiresAt.getMinutes() + 10);
  return expiresAt;
}

