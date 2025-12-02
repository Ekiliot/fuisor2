/**
 * Utility functions for masking email addresses
 */

/**
 * Masks an email address for privacy
 * Example: value@gmail.com -> val···@g···com
 * @param {string} email - The email address to mask
 * @returns {string} Masked email address
 */
export function maskEmail(email) {
  if (!email || typeof email !== 'string') return '';
  
  // Split email into local and domain parts
  const parts = email.split('@');
  if (parts.length !== 2) return email; // Invalid email format
  
  const local = parts[0];
  const domain = parts[1];
  
  // Mask local part (show first 3 characters)
  let maskedLocal;
  if (local.length <= 3) {
    maskedLocal = local;
  } else {
    maskedLocal = `${local.substring(0, 3)}···`;
  }
  
  // Mask domain (show first character and extension)
  let maskedDomain;
  const domainParts = domain.split('.');
  if (domainParts.length >= 2) {
    const domainName = domainParts[0];
    const extension = domainParts.slice(1).join('.');
    
    if (domainName.length <= 1) {
      maskedDomain = `${domainName}.${extension}`;
    } else {
      maskedDomain = `${domainName.substring(0, 1)}···${extension}`;
    }
  } else {
    maskedDomain = domain;
  }
  
  return `${maskedLocal}@${maskedDomain}`;
}

