import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnimatedTextField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const AnimatedTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  State<AnimatedTextField> createState() => _AnimatedTextFieldState();
}

class _AnimatedTextFieldState extends State<AnimatedTextField>
    with TickerProviderStateMixin {
  late FocusNode _focusNode;
  late AnimationController _animationController;
  late AnimationController _shakeController;
  late AnimationController _gradientController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _shakeAnimation;
  late Animation<double> _gradientAnimation;
  
  String? _currentError;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);

    // Основной контроллер анимации
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Контроллер для тряски при ошибке
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Контроллер для анимации градиента
    _gradientController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Анимация тряски (shake)
    _shakeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticIn,
    ));

    // Анимация градиента (бесконечное вращение)
    _gradientAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _gradientController,
      curve: Curves.linear,
    ));
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _animationController.forward();
      // Запускаем анимацию градиента при фокусе
      _gradientController.repeat();
    } else {
      _animationController.reverse();
      // Останавливаем градиент
      _gradientController.stop();
      _gradientController.reset();
    }
  }

  // Функция для запуска анимации тряски
  void _triggerShake() {
    _shakeController.forward(from: 0.0);
  }

  // Вычисление смещения для эффекта тряски
  double _getShakeOffset() {
    const distance = 8.0;
    final progress = _shakeAnimation.value;
    
    if (progress < 0.2) {
      return distance * (progress / 0.2);
    } else if (progress < 0.4) {
      return distance * (1 - (progress - 0.2) / 0.2);
    } else if (progress < 0.6) {
      return -distance * ((progress - 0.4) / 0.2);
    } else if (progress < 0.8) {
      return -distance * (1 - (progress - 0.6) / 0.2);
    } else {
      return distance * 0.5 * ((progress - 0.8) / 0.2) * (1 - (progress - 0.8) / 0.2);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _animationController.dispose();
    _shakeController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _animationController,
        _shakeController,
        _gradientController,
      ]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.translate(
            offset: Offset(_getShakeOffset(), 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Обёртка с тенью только для поля ввода
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: _focusNode.hasFocus
                        ? [
                            BoxShadow(
                              color: _hasError
                                  ? Colors.red.withOpacity(0.3 * _glowAnimation.value)
                                  : const Color(0xFF0095F6).withOpacity(0.3 * _glowAnimation.value),
                              blurRadius: 15 * _glowAnimation.value,
                              spreadRadius: 2 * _glowAnimation.value,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: _hasError
                                  ? Colors.red.withOpacity(0.2 * _glowAnimation.value)
                                  : const Color(0xFF0095F6).withOpacity(0.2 * _glowAnimation.value),
                              blurRadius: 25 * _glowAnimation.value,
                              spreadRadius: 0,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : [],
                  ),
                  child: Stack(
                    children: [
                      // Градиентная рамка (только при фокусе и без ошибки)
                      if (_focusNode.hasFocus && !_hasError)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: SweepGradient(
                                colors: const [
                                  Color(0xFF0095F6),
                                  Color(0xFF00D4FF),
                                  Color(0xFF0095F6),
                                  Color(0xFF667EEA),
                                  Color(0xFF0095F6),
                                ],
                                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                                transform: GradientRotation(
                                  _gradientAnimation.value * 3.14159 * 2,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Само текстовое поле
                      TextFormField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        obscureText: widget.obscureText,
                        keyboardType: widget.keyboardType,
                        inputFormatters: widget.inputFormatters,
                        validator: (value) {
                          final error = widget.validator?.call(value);
                          
                          // Если есть ошибка и она изменилась
                          if (error != null && error != _currentError) {
                            _currentError = error;
                            _hasError = true;
                            // Запускаем анимацию тряски
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _triggerShake();
                            });
                          } else if (error == null) {
                            _hasError = false;
                            _currentError = null;
                          }
                          
                          return error;
                        },
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          labelText: widget.labelText,
                          labelStyle: TextStyle(
                            color: _hasError
                                ? Colors.red
                                : _focusNode.hasFocus
                                    ? const Color(0xFF0095F6)
                                    : Colors.grey,
                          ),
                          suffixIcon: widget.suffixIcon,
                          filled: true,
                          fillColor: const Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: Colors.grey.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: _hasError
                                ? const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  )
                                : BorderSide.none, // Градиент будет видно
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: Colors.red,
                              width: 1,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: Colors.red,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          prefixIcon: widget.prefixIcon,
                          errorStyle: const TextStyle(
                            height: 0.01, // Скрываем стандартный текст ошибки
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Кастомный текст ошибки с анимацией
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: _hasError && _currentError != null
                      ? Padding(
                          padding: const EdgeInsets.only(left: 20, top: 6),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Colors.red,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _currentError!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}