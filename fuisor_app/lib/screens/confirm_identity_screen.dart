import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../widgets/safe_avatar.dart';
import 'reset_password_otp_screen.dart';

class ConfirmIdentityScreen extends StatelessWidget {
  final String identifier;
  final String username;
  final String name;
  final String? avatarUrl;
  final String email;

  const ConfirmIdentityScreen({
    super.key,
    required this.identifier,
    required this.username,
    required this.name,
    this.avatarUrl,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Confirm Identity',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              
              // Question
              const Text(
                'Is this you?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 12),
              
              const Text(
                'We found this account. Please confirm it\'s yours before continuing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E8E8E),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Profile Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF262626),
                  ),
                ),
                child: Column(
                  children: [
                    // Avatar
                    SafeAvatar(
                      imageUrl: avatarUrl,
                      radius: 50,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Username
                    Text(
                      '@$username',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Name
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFF8E8E8E),
                        fontSize: 16,
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Divider
                    Container(
                      height: 1,
                      color: const Color(0xFF262626),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Email (already masked by API)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          EvaIcons.emailOutline,
                          color: Color(0xFF8E8E8E),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          email, // Already masked by backend API
                          style: const TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Yes Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ResetPasswordOTPScreen(
                          identifier: identifier,
                          email: email,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0095F6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Yes, Continue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              // No Button
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFF262626),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'No, Go Back',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

