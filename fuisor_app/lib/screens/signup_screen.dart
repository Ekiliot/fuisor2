import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../providers/auth_provider.dart';
import '../widgets/animated_text_field.dart';
import '../services/api_service.dart';
import 'main_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _apiService = ApiService();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  int _currentStep = 0; // 0: username, 1: password, 2: confirm password, 3: name, 4: email
  
  // Username validation state
  bool? _isUsernameAvailable;
  bool _isCheckingUsername = false;
  Timer? _usernameCheckTimer;
  
  // Email validation state
  bool? _isEmailAvailable;
  bool _isCheckingEmail = false;
  Timer? _emailCheckTimer;
  
  // Password validation state
  bool _hasLetters = false;
  bool _hasNumbers = false;
  bool _hasUppercase = false;
  bool _hasValidChars = true;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(() {
      setState(() {}); // Обновляем UI при изменении подтверждения пароля
    });
    _nameController.addListener(() {
      setState(() {}); // Обновляем UI при изменении имени
    });
    _emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    _usernameCheckTimer?.cancel();
    _emailCheckTimer?.cancel();
    _usernameController.removeListener(_onUsernameChanged);
    _passwordController.removeListener(_onPasswordChanged);
    _emailController.removeListener(_onEmailChanged);
    _emailController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    final password = _passwordController.text;
    
    setState(() {
      _hasLetters = RegExp(r'[a-zA-Z]').hasMatch(password);
      _hasNumbers = RegExp(r'[0-9]').hasMatch(password);
      _hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
      // Разрешенные безопасные символы: буквы, цифры и специальные символы
      // Безопасные символы: !@#$%^&*()_+-=[]{}:"|,.<>/?~`
      // Исключаем одинарную кавычку и обратный слеш для безопасности
      final safeCharsPattern = r'^[a-zA-Z0-9!@#\$%^&*()_+\-=\[\]{};:"|,.<>\/?~`]*$';
      _hasValidChars = RegExp(safeCharsPattern).hasMatch(password);
    });
  }

  void _onUsernameChanged() {
    final username = _usernameController.text.trim();
    
    // Сбрасываем состояние при изменении
    if (username.isEmpty) {
      setState(() {
        _isUsernameAvailable = null;
        _isCheckingUsername = false;
      });
      _usernameCheckTimer?.cancel();
      return;
    }

    // Проверяем формат username (только буквы, цифры, точки, подчеркивания)
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(username)) {
      setState(() {
        _isUsernameAvailable = null;
        _isCheckingUsername = false;
      });
      _usernameCheckTimer?.cancel();
      return;
    }

    // Проверяем минимальную длину
    if (username.length < 3) {
      setState(() {
        _isUsernameAvailable = null;
        _isCheckingUsername = false;
      });
      _usernameCheckTimer?.cancel();
      return;
    }

    // Отменяем предыдущий таймер
    _usernameCheckTimer?.cancel();

    // Сбрасываем состояние проверки (ждем паузу)
    setState(() {
      _isCheckingUsername = false;
      _isUsernameAvailable = null;
    });

    // Запускаем проверку с задержкой 2 секунды после паузы ввода
    _usernameCheckTimer = Timer(const Duration(seconds: 2), () {
      _checkUsernameAvailability(username);
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    if (!mounted) return;
    
    setState(() {
      _isCheckingUsername = true;
    });

    try {
      final isAvailable = await _apiService.checkUsernameAvailability(username);
      
      if (!mounted) return;
      
      setState(() {
        _isUsernameAvailable = isAvailable;
        _isCheckingUsername = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        // В случае ошибки не показываем статус
      });
    }
  }

  void _onEmailChanged() {
    final email = _emailController.text.trim();
    
    // Сбрасываем состояние при изменении
    if (email.isEmpty) {
      setState(() {
        _isEmailAvailable = null;
        _isCheckingEmail = false;
      });
      _emailCheckTimer?.cancel();
      return;
    }

    // Проверяем формат email
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() {
        _isEmailAvailable = null;
        _isCheckingEmail = false;
      });
      _emailCheckTimer?.cancel();
      return;
    }

    // Отменяем предыдущий таймер
    _emailCheckTimer?.cancel();

    // Сбрасываем состояние проверки (ждем паузу)
    setState(() {
      _isCheckingEmail = false;
      _isEmailAvailable = null;
    });

    // Запускаем проверку с задержкой 2 секунды после паузы ввода
    _emailCheckTimer = Timer(const Duration(seconds: 2), () {
      _checkEmailAvailability(email);
    });
  }

  Future<void> _checkEmailAvailability(String email) async {
    if (!mounted) return;
    
    setState(() {
      _isCheckingEmail = true;
    });

    try {
      final isAvailable = await _apiService.checkEmailAvailability(email);
      
      if (!mounted) return;
      
      setState(() {
        _isEmailAvailable = isAvailable;
        _isCheckingEmail = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingEmail = false;
      });
    }
  }

  // Username Step Widget
  Widget _buildUsernameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create a username',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a username for your account. You can always change it later.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E8E),
          ),
        ),
        const SizedBox(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedTextField(
              controller: _usernameController,
              labelText: 'Username',
              suffixIcon: _buildUsernameStatusIcon(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter username';
                }
                if (value.length < 3) {
                  return 'Username must be at least 3 characters';
                }
                if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(value)) {
                  return 'Username can only contain letters, numbers, dots, and underscores';
                }
                if (_isUsernameAvailable == false) {
                  return 'Username is already taken';
                }
                if (_isCheckingUsername) {
                  return null; // Не показываем ошибку во время проверки
                }
                if (_isUsernameAvailable == null && value.length >= 3) {
                  return null; // Еще не проверили
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            _buildUsernameStatusMessage(),
          ],
        ),
      ],
    );
  }

  Widget? _buildUsernameStatusIcon() {
    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
          ),
        ),
      );
    }
    
    if (_isUsernameAvailable == true) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: Icon(
          Icons.check_circle,
          color: Color(0xFF4CAF50),
          size: 24,
        ),
      );
    }
    
    if (_isUsernameAvailable == false) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: Icon(
          Icons.cancel,
          color: Colors.red,
          size: 24,
        ),
      );
    }
    
    return null;
  }

  Widget _buildUsernameStatusMessage() {
    final username = _usernameController.text.trim();
    
    // Не показываем сообщение, если поле пустое
    if (username.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Показываем сообщение о проверке только во время активной проверки
    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.only(left: 20.0),
        child: Text(
          'Checking availability...',
          style: TextStyle(
            color: Color(0xFF8E8E8E),
            fontSize: 12,
          ),
        ),
      );
    }
    
    if (_isUsernameAvailable == true) {
      return const Padding(
        padding: EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Color(0xFF4CAF50),
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              'Username is available',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    
    if (_isUsernameAvailable == false) {
      return const Padding(
        padding: EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            Icon(
              Icons.cancel,
              color: Colors.red,
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              'Username is already taken',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    
    // Если username введен, но еще не проверен (ждем паузу)
    if (username.length >= 3 && RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(username)) {
      return const SizedBox.shrink();
    }
    
    return const SizedBox.shrink();
  }

  Widget? _buildEmailStatusIcon() {
    if (_isCheckingEmail) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
          ),
        ),
      );
    }
    
    if (_isEmailAvailable == true) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: Icon(
          Icons.check_circle,
          color: Color(0xFF4CAF50),
          size: 24,
        ),
      );
    }
    
    if (_isEmailAvailable == false) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: Icon(
          Icons.cancel,
          color: Colors.red,
          size: 24,
        ),
      );
    }
    
    return null;
  }

  Widget _buildEmailStatusMessage() {
    final email = _emailController.text.trim();
    
    // Не показываем сообщение, если поле пустое
    if (email.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Показываем сообщение о проверке только во время активной проверки
    if (_isCheckingEmail) {
      return const Padding(
        padding: EdgeInsets.only(left: 20.0),
        child: Text(
          'Checking availability...',
          style: TextStyle(
            color: Color(0xFF8E8E8E),
            fontSize: 12,
          ),
        ),
      );
    }
    
    if (_isEmailAvailable == true) {
      return const Padding(
        padding: EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Color(0xFF4CAF50),
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              'Email is available',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    
    if (_isEmailAvailable == false) {
      return const Padding(
        padding: EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            Icon(
              Icons.cancel,
              color: Colors.red,
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              'Email is already registered',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  // Password Step Widget
  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create a password',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your password must be secure and meet the requirements below.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E8E),
          ),
        ),
        const SizedBox(height: 24),
        AnimatedTextField(
          controller: _passwordController,
          labelText: 'Password',
          obscureText: !_isPasswordVisible,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9!@#\$%^&*()_+\-=\[\]{};:"|,.<>\/?~`]')),
          ],
          suffixIcon: IconButton(
            icon: Icon(
              _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
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
            if (value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            if (!_hasLetters) {
              return 'Password must contain at least one letter';
            }
            if (!_hasNumbers) {
              return 'Password must contain at least one number';
            }
            if (!_hasValidChars) {
              return 'Password contains invalid characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        // Password requirements indicators
        _buildPasswordRequirements(),
      ],
    );
  }

  // Confirm Password Step Widget
  Widget _buildConfirmPasswordStep() {
    final passwordsMatch = _passwordController.text == _confirmPasswordController.text &&
        _confirmPasswordController.text.isNotEmpty;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confirm your password',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Please enter your password again to confirm.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E8E),
          ),
        ),
        const SizedBox(height: 24),
        AnimatedTextField(
          controller: _confirmPasswordController,
          labelText: 'Confirm Password',
          obscureText: !_isConfirmPasswordVisible,
          suffixIcon: passwordsMatch
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.check_circle,
                    color: Color(0xFF4CAF50),
                    size: 24,
                  ),
                )
              : IconButton(
                  icon: Icon(
                    _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    color: Colors.grey,
                  ),
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please confirm password';
            }
            if (value != _passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        // Password match indicator
        if (_confirmPasswordController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20.0),
            child: Row(
              children: [
                Icon(
                  passwordsMatch ? Icons.check_circle : Icons.cancel,
                  color: passwordsMatch ? const Color(0xFF4CAF50) : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  passwordsMatch ? 'Passwords match' : 'Passwords do not match',
                  style: TextStyle(
                    color: passwordsMatch ? const Color(0xFF4CAF50) : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Password Requirements Widget
  Widget _buildPasswordRequirements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 20.0, bottom: 8.0),
          child: Text(
            'Password requirements:',
            style: TextStyle(
              color: Color(0xFF8E8E8E),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _buildRequirementItem(
          'At least 6 characters',
          _passwordController.text.length >= 6,
          required: true,
        ),
        _buildRequirementItem(
          'Contains letters',
          _hasLetters,
          required: true,
        ),
        _buildRequirementItem(
          'Contains numbers',
          _hasNumbers,
          required: true,
        ),
        _buildRequirementItem(
          'Contains uppercase letters',
          _hasUppercase,
          required: false,
        ),
        _buildRequirementItem(
          'Only safe characters',
          _hasValidChars,
          required: true,
        ),
      ],
    );
  }

  Widget _buildRequirementItem(String text, bool isValid, {required bool required}) {
    return Padding(
      padding: const EdgeInsets.only(left: 20.0, top: 4.0),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.cancel,
            color: isValid 
                ? (required ? const Color(0xFF4CAF50) : const Color(0xFF0095F6))
                : (required ? Colors.red : const Color(0xFF8E8E8E)),
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: isValid 
                  ? (required ? const Color(0xFF4CAF50) : const Color(0xFF0095F6))
                  : (required ? Colors.red : const Color(0xFF8E8E8E)),
              fontSize: 12,
            ),
          ),
          if (!required)
            const Padding(
              padding: EdgeInsets.only(left: 4.0),
              child: Text(
                '(optional)',
                style: TextStyle(
                  color: Color(0xFF8E8E8E),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Name Step Widget
  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What\'s your name?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your full name. This will be displayed on your profile.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E8E),
          ),
        ),
        const SizedBox(height: 24),
        AnimatedTextField(
          controller: _nameController,
          labelText: 'Full Name',
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._\-]')),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your name';
            }
            if (value.length < 1) {
              return 'Name must be at least 1 character';
            }
            if (value.length > 50) {
              return 'Name must be less than 50 characters';
            }
            if (!RegExp(r'^[a-zA-Z0-9._\-]+$').hasMatch(value)) {
              return 'Name contains invalid characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  // Email Step Widget
  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add your email',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'We\'ll use this email to send you important updates and notifications.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E8E),
          ),
        ),
        const SizedBox(height: 24),
        AnimatedTextField(
          controller: _emailController,
          labelText: 'Email',
          keyboardType: TextInputType.emailAddress,
          suffixIcon: _buildEmailStatusIcon(),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter email';
            }
            final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
            if (!emailRegex.hasMatch(value)) {
              return 'Please enter a valid email';
            }
            if (_isEmailAvailable == false) {
              return 'Email is already registered';
            }
            if (_isCheckingEmail) return null;
            if (_isEmailAvailable == null && emailRegex.hasMatch(value)) return null;
            return null;
          },
        ),
        const SizedBox(height: 16),
        _buildEmailStatusMessage(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index <= _currentStep
                        ? const Color(0xFF0095F6)
                        : const Color(0xFF8E8E8E),
                  ),
                ),
                if (index < 4)
                  Container(
                    width: 32,
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index < _currentStep
                          ? const Color(0xFF0095F6)
                          : const Color(0xFF8E8E8E),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
              ],
            );
          }),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),

                    // Step Content
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Username Step Widget
                          if (_currentStep == 0) _buildUsernameStep(),
                          // Password Step Widget
                          if (_currentStep == 1) _buildPasswordStep(),
                          // Confirm Password Step Widget
                          if (_currentStep == 2) _buildConfirmPasswordStep(),
                          // Name Step Widget
                          if (_currentStep == 3) _buildNameStep(),
                          // Email Step Widget
                          if (_currentStep == 4) _buildEmailStep(),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Terms
                    const Text(
                      'By signing up, you agree to our Terms, Data Policy and Cookies Policy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8E8E8E),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Bottom Buttons
            SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          // Next Button (по центру)
                          Center(
                            child: Builder(
                              builder: (context) {
                                bool isButtonActive = false;
                                
                                if (_currentStep == 0) {
                                  // Username step
                                  final username = _usernameController.text.trim();
                                  final isValidFormat = username.length >= 3 && 
                                      RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(username);
                                  isButtonActive = isValidFormat && 
                                      _isUsernameAvailable == true && 
                                      !_isCheckingUsername;
                                } else if (_currentStep == 1) {
                                  // Password step
                                  isButtonActive = _hasLetters && _hasNumbers && 
                                      _hasValidChars && _passwordController.text.length >= 6;
                            } else if (_currentStep == 2) {
                              // Confirm password step
                              isButtonActive = _passwordController.text == 
                                  _confirmPasswordController.text &&
                                  _confirmPasswordController.text.isNotEmpty;
                            } else if (_currentStep == 3) {
                              // Name step
                              final name = _nameController.text.trim();
                              isButtonActive = name.isNotEmpty && 
                                  name.length >= 1 && 
                                  name.length <= 50 &&
                                  RegExp(r'^[a-zA-Z0-9._\-]+$').hasMatch(name);
                            } else if (_currentStep == 4) {
                              // Email step
                              final email = _emailController.text.trim();
                              final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                              isButtonActive = email.isNotEmpty && 
                                  emailRegex.hasMatch(email) &&
                                  _isEmailAvailable == true &&
                                  !_isCheckingEmail;
                            }
                                
                                return Container(
                                  width: 200,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: isButtonActive
                                        ? const Color(0xFF0095F6)
                                        : const Color(0xFF8E8E8E),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: isButtonActive
                                        ? [
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
                                          ]
                                        : [],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(24),
                                  onTap: isButtonActive
                                      ? () async {
                                          if (_formKey.currentState!.validate()) {
                                            if (_currentStep < 4) {
                                              setState(() {
                                                _currentStep++;
                                              });
                                            } else if (_currentStep == 4) {
                                              // Final step - sign up
                                              final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                              final success = await authProvider.signup(
                                                _emailController.text.trim(),
                                                _passwordController.text,
                                                _usernameController.text.trim(),
                                                _nameController.text.trim(),
                                              );
                                              
                                              if (success && mounted) {
                                                Navigator.of(context).pushReplacement(
                                                  MaterialPageRoute(
                                                    builder: (context) => const MainScreen(),
                                                  ),
                                                );
                                              }
                                            }
                                          }
                                        }
                                      : null,
                                      child: Center(
                                        child: Text(
                                          _currentStep == 4 ? 'Sign Up' : 'Next',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Back Button (слева от Next)
                          Positioned(
                            left: (constraints.maxWidth / 2) - (200 / 2) - 12 - 56,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () {
                                    if (_currentStep > 0) {
                                      setState(() {
                                        _currentStep--;
                                      });
                                    } else {
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: const Center(
                                    child: Icon(
                                      EvaIcons.arrowBackOutline,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
