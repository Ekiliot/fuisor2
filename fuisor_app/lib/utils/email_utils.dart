/// Utility class for email operations
class EmailUtils {
  /// Masks an email address for privacy
  /// Example: value@gmail.com -> val···@g···com
  static String maskEmail(String email) {
    if (email.isEmpty) return '';
    
    // Split email into local and domain parts
    final parts = email.split('@');
    if (parts.length != 2) return email; // Invalid email format
    
    final local = parts[0];
    final domain = parts[1];
    
    // Mask local part (show first 3 characters)
    String maskedLocal;
    if (local.length <= 3) {
      maskedLocal = local;
    } else {
      maskedLocal = '${local.substring(0, 3)}···';
    }
    
    // Mask domain (show first character and extension)
    String maskedDomain;
    final domainParts = domain.split('.');
    if (domainParts.length >= 2) {
      final domainName = domainParts[0];
      final extension = domainParts.sublist(1).join('.');
      
      if (domainName.length <= 1) {
        maskedDomain = '$domainName.$extension';
      } else {
        maskedDomain = '${domainName.substring(0, 1)}···$extension';
      }
    } else {
      maskedDomain = domain;
    }
    
    return '$maskedLocal@$maskedDomain';
  }
  
  /// Validates email format
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;
    
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    return emailRegex.hasMatch(email);
  }
}

