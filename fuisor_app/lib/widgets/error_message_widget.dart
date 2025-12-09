import 'package:flutter/material.dart';

class ErrorMessageWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onForgotPassword;

  const ErrorMessageWidget({
    super.key,
    required this.message,
    this.onForgotPassword,
  });

  @override
  Widget build(BuildContext context) {
    final messageLower = message.toLowerCase();
    final isPasswordError = messageLower.contains('invalid email or password') ||
        messageLower.contains('invalid username or password') ||
        messageLower.contains('invalid credentials') ||
        messageLower.contains('user not found') ||
        messageLower.contains('unable to sign in');

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (isPasswordError && onForgotPassword != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onForgotPassword,
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_reset,
                    color: Color(0xFF0095F6),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: Color(0xFF0095F6),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

