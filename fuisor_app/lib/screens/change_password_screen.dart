import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pretty_animated_text/pretty_animated_text.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/email_utils.dart';
import 'dart:async';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final ApiService _apiService = ApiService();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoadingOTP = false;
  bool _isChangingPassword = false;
  bool _otpSent = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  
  int _resendCountdown = 0;
  Timer? _countdownTimer;
  
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadAccessToken();
  }

  Future<void> _loadAccessToken() async {
    try {
      // Get token from AuthProvider (like other screens do)
      final authProvider = context.read<AuthProvider>();
      final accessToken = await authProvider.getAccessToken();
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
      }
    } catch (e) {
      print('Error loading access token: $e');
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startResendCountdown() {
    setState(() {
      _resendCountdown = 60;
    });
    
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _requestOTP() async {
    setState(() {
      _isLoadingOTP = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Get token from AuthProvider and set it
      final authProvider = context.read<AuthProvider>();
      final accessToken = await authProvider.getAccessToken();
      
      if (accessToken == null) {
        setState(() {
          _errorMessage = 'You must be logged in to change your password';
          _isLoadingOTP = false;
        });
        return;
      }
      
      // Set token explicitly before request
      _apiService.setAccessToken(accessToken);
      
      await _apiService.requestPasswordChangeOTP();
      
      setState(() {
        _otpSent = true;
        _successMessage = 'OTP code has been sent to your email';
        _isLoadingOTP = false;
      });
      
      _startResendCountdown();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoadingOTP = false;
      });
    }
  }

  Future<void> _changePassword() async {
    // Validate inputs
    if (_otpController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the OTP code';
      });
      return;
    }

    if (_newPasswordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a new password';
      });
      return;
    }

    if (_newPasswordController.text.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters';
      });
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _isChangingPassword = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Get token from AuthProvider and set it
      final authProvider = context.read<AuthProvider>();
      final accessToken = await authProvider.getAccessToken();
      
      if (accessToken == null) {
        setState(() {
          _errorMessage = 'You must be logged in to change your password';
          _isChangingPassword = false;
        });
        return;
      }
      
      // Set token explicitly before request
      _apiService.setAccessToken(accessToken);
      
      await _apiService.changePassword(
        _otpController.text.trim(),
        _newPasswordController.text,
      );

      if (mounted) {
        // Reset loading state first
        setState(() {
          _isChangingPassword = false;
        });

        // Show success dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text(
              'Password Changed',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Your password has been changed successfully. You will be logged out.',
              style: TextStyle(color: Color(0xFFE0E0E0)),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  // Close dialog
                  if (mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  
                  // Get auth provider reference
                  final authProvider = context.read<AuthProvider>();
                  
                  // Close change password screen
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                  
                  // Wait for navigation to complete
                  await Future.delayed(const Duration(milliseconds: 300));
                  
                  // Close all screens back to root/main screen
                  if (mounted) {
                    Navigator.of(context).popUntil((route) {
                      // Keep popping until we reach the first route (MainScreen or root)
                      return route.isFirst;
                    });
                  }
                  
                  // Small delay to ensure all screens are closed
                  await Future.delayed(const Duration(milliseconds: 100));
                  
                  // Logout - AuthWrapper will automatically switch to LoginScreen
                  if (mounted) {
                    await authProvider.logout();
                  }
                },
                child: const Text(
                  'OK',
                  style: TextStyle(color: Color(0xFF0095F6)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isChangingPassword = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userEmail = authProvider.currentUser?.email ?? '';
    final maskedEmail = EmailUtils.maskEmail(userEmail);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: BlurText(
          text: 'Change password',
          duration: const Duration(seconds: 1),
          type: AnimationType.word,
          textStyle: GoogleFonts.delaGothicOne(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Email display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF262626)),
              ),
              child: Row(
                children: [
                  const Icon(
                    EvaIcons.emailOutline,
                    color: Color(0xFF0095F6),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Email',
                          style: TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          maskedEmail,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Request OTP button
            if (!_otpSent)
              Center(
                child: Container(
                  width: 200,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _isLoadingOTP
                        ? const Color(0xFF8E8E8E)
                        : const Color(0xFF0095F6),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: _isLoadingOTP
                        ? []
                        : [
                            BoxShadow(
                              color: const Color(0xFF0095F6).withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _isLoadingOTP ? null : _requestOTP,
                      child: Center(
                        child: _isLoadingOTP
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Request OTP Code',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),

            // OTP input section
            if (_otpSent) ...[
              const Text(
                'Enter OTP Code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF121212),
                  counterText: '',
                  hintText: '000000',
                  hintStyle: const TextStyle(
                    color: Color(0xFF4A4A4A),
                    letterSpacing: 4,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF262626)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF262626)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF0095F6)),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Resend OTP
              Center(
                child: TextButton(
                  onPressed: _resendCountdown > 0 ? null : _requestOTP,
                  child: Text(
                    _resendCountdown > 0
                        ? 'Resend code in $_resendCountdown seconds'
                        : 'Resend OTP Code',
                    style: TextStyle(
                      color: _resendCountdown > 0
                          ? const Color(0xFF8E8E8E)
                          : const Color(0xFF0095F6),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // New password
              const Text(
                'New Password',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF121212),
                  hintText: 'Enter new password',
                  hintStyle: const TextStyle(color: Color(0xFF4A4A4A)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNewPassword
                          ? EvaIcons.eyeOffOutline
                          : EvaIcons.eyeOutline,
                      color: const Color(0xFF8E8E8E),
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureNewPassword = !_obscureNewPassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF262626)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF262626)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF0095F6)),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Confirm password
              const Text(
                'Confirm Password',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF121212),
                  hintText: 'Confirm new password',
                  hintStyle: const TextStyle(color: Color(0xFF4A4A4A)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? EvaIcons.eyeOffOutline
                          : EvaIcons.eyeOutline,
                      color: const Color(0xFF8E8E8E),
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF262626)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF262626)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF0095F6)),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Change password button
              Center(
                child: Container(
                  width: 200,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _isChangingPassword
                        ? const Color(0xFF8E8E8E)
                        : const Color(0xFF0095F6),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: _isChangingPassword
                        ? []
                        : [
                            BoxShadow(
                              color: const Color(0xFF0095F6).withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _isChangingPassword ? null : _changePassword,
                      child: Center(
                        child: _isChangingPassword
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Change password',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(EvaIcons.alertCircleOutline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Success message
            if (_successMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0095F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0095F6).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(EvaIcons.checkmark, color: Color(0xFF0095F6), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(color: Color(0xFF0095F6), fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

