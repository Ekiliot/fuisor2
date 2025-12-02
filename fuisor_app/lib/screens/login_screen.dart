import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../providers/auth_provider.dart';
import '../widgets/animated_login_button.dart';
import '../widgets/animated_text_field.dart';
import '../widgets/error_message_widget.dart';
import 'main_screen.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  late AnimationController _titleAnimationController;
  late Animation<double> _blurAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _titleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _blurAnimation = Tween<double>(
      begin: 50.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _titleAnimationController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _titleAnimationController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    ));

    // Запускаем анимацию при загрузке
    _titleAnimationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _titleAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title with blur animation
              AnimatedBuilder(
                animation: _titleAnimationController,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Blur effect
                      if (_blurAnimation.value > 0)
                        ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: _blurAnimation.value,
                              sigmaY: _blurAnimation.value,
                            ),
                            child: Opacity(
                              opacity: (1.0 - _opacityAnimation.value) * 0.8,
                              child: Text(
                                'Sonet',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.delaGothicOne(
                                  fontSize: 42,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Main text
                      Opacity(
                        opacity: _opacityAnimation.value,
                        child: Text(
                          'Sonet',
                textAlign: TextAlign.center,
                style: GoogleFonts.delaGothicOne(
                  fontSize: 42,
                  color: Colors.white,
                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),

              // Login Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Email/Username Field
                    AnimatedTextField(
                      controller: _emailController,
                        labelText: 'Email or Username',
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: const Icon(
                        EvaIcons.email,
                        color: Color(0xFF8E8E8E),
                        size: 24,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter email or username';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Password Field
                    AnimatedTextField(
                      controller: _passwordController,
                      labelText: 'Password',
                      obscureText: !_isPasswordVisible,
                      prefixIcon: const Icon(
                        EvaIcons.lock,
                        color: Color(0xFF8E8E8E),
                        size: 24,
                      ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                              ? EvaIcons.eye
                              : EvaIcons.eyeOff,
                          color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Login Button
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        return AnimatedLoginButton(
                          state: authProvider.loginButtonState,
                          onPressed: () async {
                                    if (_formKey.currentState!.validate()) {
                                      final success = await authProvider.login(
                                        _emailController.text.trim(),
                                        _passwordController.text,
                                      );

                                      if (success && mounted) {
                                // Небольшая задержка для показа успешного состояния
                                await Future.delayed(const Duration(milliseconds: 500));
                                if (mounted) {
                                        Navigator.of(context).pushReplacement(
                                          MaterialPageRoute(
                                            builder: (context) => const MainScreen(),
                                          ),
                                        );
                                      }
                                    }
                            }
                          },
                        );
                      },
                    ),

                    // Error Message (показывается только после завершения анимации)
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        return AnimatedSize(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, -0.2),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  )),
                                  child: child,
                                ),
                              );
                            },
                            child: authProvider.shouldShowError
                                ? ErrorMessageWidget(
                                    key: ValueKey(authProvider.error),
                                    message: authProvider.error!,
                                    onForgotPassword: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => const ForgotPasswordScreen(),
                                        ),
                                      );
                                    },
                                  )
                                : const SizedBox.shrink(key: ValueKey('empty')),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Sign Up Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Color(0xFF8E8E8E)),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SignupScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: Color(0xFF0095F6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

