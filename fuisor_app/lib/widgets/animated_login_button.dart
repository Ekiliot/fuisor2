import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';

enum AnimationPhase {
  idle,
  shrinking,
  spinning,
  showingResult,
  expandingBack,
}

class AnimatedLoginButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final LoginButtonState state;

  const AnimatedLoginButton({
    super.key,
    required this.onPressed,
    required this.state,
  });

  @override
  State<AnimatedLoginButton> createState() => _AnimatedLoginButtonState();
}

class _AnimatedLoginButtonState extends State<AnimatedLoginButton>
    with TickerProviderStateMixin {
  late AnimationController _shrinkController;
  late AnimationController _rotationController;
  late AnimationController _colorController;
  late AnimationController _scaleController;
  late Animation<Color?> _colorAnimation;
  AnimationPhase _currentPhase = AnimationPhase.idle;

  @override
  void initState() {
    super.initState();

    // Контроллер сужения/расширения (более плавный)
    _shrinkController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Контроллер вращения
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Контроллер цвета
    _colorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Контроллер масштаба для эффекта "пульсации"
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _colorAnimation = ColorTween(
      begin: const Color(0xFF0095F6),
      end: const Color(0xFF0095F6),
    ).animate(CurvedAnimation(
      parent: _colorController,
      curve: Curves.easeInOut,
    ));

    _shrinkController.addStatusListener(_onShrinkAnimationStatus);
  }

  void _onShrinkAnimationStatus(AnimationStatus status) {
    if (!mounted) return;

    if (status == AnimationStatus.completed) {
      if (_currentPhase == AnimationPhase.shrinking) {
        setState(() {
          _currentPhase = AnimationPhase.spinning;
        });
        _rotationController.repeat();
      }
    } else if (status == AnimationStatus.dismissed) {
      if (_currentPhase == AnimationPhase.expandingBack) {
        _colorAnimation = ColorTween(
          begin: const Color(0xFF0095F6),
          end: const Color(0xFF0095F6),
        ).animate(CurvedAnimation(
          parent: _colorController,
          curve: Curves.linear,
        ));
        _colorController.reset();
        
        setState(() {
          _currentPhase = AnimationPhase.idle;
        });
      }
    }
  }

  @override
  void didUpdateWidget(AnimatedLoginButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _handleStateChange();
    }
  }

  void _handleStateChange() {
    switch (widget.state) {
      case LoginButtonState.loading:
        if (_currentPhase == AnimationPhase.idle) {
          // Эффект нажатия
          _scaleController.forward().then((_) {
            _scaleController.reverse();
          });
          
          setState(() {
            _currentPhase = AnimationPhase.shrinking;
          });
          _shrinkController.forward();
        }
        break;

      case LoginButtonState.success:
        if (_currentPhase == AnimationPhase.spinning) {
          _rotationController.stop();

          _colorAnimation = ColorTween(
            begin: _colorAnimation.value ?? const Color(0xFF0095F6),
            end: const Color(0xFF4CAF50), // Более приятный зеленый
          ).animate(CurvedAnimation(
            parent: _colorController,
            curve: Curves.easeOutCubic,
          ));

          _colorController.forward(from: 0.0).then((_) {
            if (mounted) {
              setState(() {
                _currentPhase = AnimationPhase.showingResult;
              });

              // Эффект пульсации при успехе
              _scaleController.forward().then((_) {
                _scaleController.reverse();
              });

              Future.delayed(const Duration(milliseconds: 1800), () {
                if (mounted && _currentPhase == AnimationPhase.showingResult) {
                  setState(() {
                    _currentPhase = AnimationPhase.expandingBack;
                  });
                  _shrinkController.reverse();

                  _colorAnimation = ColorTween(
                    begin: const Color(0xFF4CAF50),
                    end: const Color(0xFF0095F6),
                  ).animate(CurvedAnimation(
                    parent: _colorController,
                    curve: Curves.easeInOut,
                  ));
                  _colorController.duration = const Duration(milliseconds: 400);
                  _colorController.forward(from: 0.0);
                }
              });
            }
          });
        }
        break;

      case LoginButtonState.error:
        if (_currentPhase == AnimationPhase.spinning) {
          _rotationController.stop();

          _colorAnimation = ColorTween(
            begin: _colorAnimation.value ?? const Color(0xFF0095F6),
            end: const Color(0xFFEF4444), // Более приятный красный
          ).animate(CurvedAnimation(
            parent: _colorController,
            curve: Curves.easeOutCubic,
          ));

          _colorController.forward(from: 0.0).then((_) {
            if (mounted) {
              setState(() {
                _currentPhase = AnimationPhase.showingResult;
              });

              // Эффект тряски при ошибке
              _shakeAnimation();

              Future.delayed(const Duration(milliseconds: 1800), () {
                if (mounted && _currentPhase == AnimationPhase.showingResult) {
                  setState(() {
                    _currentPhase = AnimationPhase.expandingBack;
                  });
                  _shrinkController.reverse();

                  _colorAnimation = ColorTween(
                    begin: const Color(0xFFEF4444),
                    end: const Color(0xFF0095F6),
                  ).animate(CurvedAnimation(
                    parent: _colorController,
                    curve: Curves.easeInOut,
                  ));
                  _colorController.duration = const Duration(milliseconds: 400);
                  _colorController.forward(from: 0.0);
                }
              });
            }
          });
        }
        break;

      case LoginButtonState.normal:
        _rotationController.stop();
        _rotationController.reset();
        _shrinkController.reset();
        _scaleController.reset();
        
        _colorAnimation = ColorTween(
          begin: _colorAnimation.value ?? const Color(0xFF0095F6),
          end: const Color(0xFF0095F6),
        ).animate(CurvedAnimation(
          parent: _colorController,
          curve: Curves.linear,
        ));
        _colorController.duration = const Duration(milliseconds: 300);
        _colorController.reset();
        _colorController.forward();
        
        setState(() {
          _currentPhase = AnimationPhase.idle;
        });
        break;
    }
  }

  // Анимация тряски при ошибке
  void _shakeAnimation() {
    const duration = Duration(milliseconds: 80);
    Future.delayed(duration * 0, () => _scaleController.animateTo(0.95));
    Future.delayed(duration * 1, () => _scaleController.animateTo(1.05));
    Future.delayed(duration * 2, () => _scaleController.animateTo(0.95));
    Future.delayed(duration * 3, () => _scaleController.animateTo(1.0));
  }

  @override
  void dispose() {
    _shrinkController.dispose();
    _rotationController.dispose();
    _colorController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Color _getButtonColor() {
    return _colorAnimation.value ?? const Color(0xFF0095F6);
  }

  Widget _buildButtonContent() {
    switch (_currentPhase) {
      case AnimationPhase.idle:
        return const Text(
          'Log In',
          key: ValueKey('login_text'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        );

      case AnimationPhase.shrinking:
      case AnimationPhase.spinning:
        return const SizedBox.shrink();

      case AnimationPhase.showingResult:
        if (widget.state == LoginButtonState.success) {
          return const Icon(
            Icons.check_rounded,
            key: ValueKey('success'),
            color: Colors.white,
            size: 32,
          );
        } else if (widget.state == LoginButtonState.error) {
          return const Icon(
            Icons.close_rounded,
            key: ValueKey('error'),
            color: Colors.white,
            size: 32,
          );
        }
        return const SizedBox.shrink();

      case AnimationPhase.expandingBack:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor = _getButtonColor();

    return AnimatedBuilder(
      animation: Listenable.merge([
        _shrinkController,
        _rotationController,
        _colorController,
        _scaleController,
      ]),
      builder: (context, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final padding = 32.0 * 2;
        final fullWidth = screenWidth - padding;
        final targetWidth = 56.0; // Немного больше для лучшей видимости

        // Плавная анимация ширины с easeInOutCubic
        final progress = Curves.easeInOutCubic.transform(_shrinkController.value);
        final currentWidth = _currentPhase == AnimationPhase.idle
            ? fullWidth
            : fullWidth - (progress * (fullWidth - targetWidth));

        // Динамический borderRadius
        final radiusProgress = Curves.easeInOutCubic.transform(_shrinkController.value);
        final currentBorderRadius = _currentPhase == AnimationPhase.idle 
            ? 24.0 
            : 24.0 + (radiusProgress * 4.0); // От 24 до 28

        // Масштаб для эффектов
        final scale = 1.0 - (_scaleController.value * 0.05);

        Widget buttonWidget = Transform.scale(
          scale: scale,
          child: Container(
            width: currentWidth,
            height: 56,
            decoration: BoxDecoration(
              color: buttonColor,
              borderRadius: BorderRadius.circular(currentBorderRadius),
              boxShadow: [
                // Основная тень
                BoxShadow(
                  color: buttonColor.withOpacity(0.3),
                  blurRadius: _currentPhase == AnimationPhase.spinning ? 20 : 12,
                  spreadRadius: _currentPhase == AnimationPhase.spinning ? 3 : 0,
                  offset: const Offset(0, 4),
                ),
                // Дополнительная тень для глубины
                if (_currentPhase == AnimationPhase.idle)
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
                borderRadius: BorderRadius.circular(currentBorderRadius),
                onTap: widget.state == LoginButtonState.normal 
                    ? widget.onPressed 
                    : null,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.7, end: 1.0).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutBack,
                            ),
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: _buildButtonContent(),
                  ),
                ),
              ),
            ),
          ),
        );

        // Плавное вращение во время загрузки
        if (_currentPhase == AnimationPhase.spinning) {
          buttonWidget = RotationTransition(
            turns: Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(
                parent: _rotationController,
                curve: Curves.linear, // Равномерное вращение
              ),
            ),
            child: Container(
              width: targetWidth,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(currentBorderRadius),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 3,
                ),
              ),
              child: Center(
                child: Container(
                  width: targetWidth * 0.4,
                  height: 56 * 0.4,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          );
          
          buttonWidget = Container(
            width: targetWidth,
            height: 56,
            decoration: BoxDecoration(
              color: buttonColor,
              borderRadius: BorderRadius.circular(currentBorderRadius),
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: buttonWidget,
          );
        }

        return Center(
          child: SizedBox(
            width: _currentPhase == AnimationPhase.idle ? double.infinity : null,
            child: buttonWidget,
          ),
        );
      },
    );
  }
}