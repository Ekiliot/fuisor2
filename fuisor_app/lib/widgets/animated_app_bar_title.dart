import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pretty_animated_text/pretty_animated_text.dart';

/// Переиспользуемый виджет для анимированного заголовка AppBar
/// Использует BlurText из pretty_animated_text для плавной анимации появления
class AnimatedAppBarTitle extends StatefulWidget {
  final String text;
  final TextStyle? textStyle;
  final Duration duration;
  final AnimationType animationType;

  const AnimatedAppBarTitle({
    super.key,
    required this.text,
    this.textStyle,
    this.duration = const Duration(seconds: 1),
    this.animationType = AnimationType.word,
  });

  @override
  State<AnimatedAppBarTitle> createState() => _AnimatedAppBarTitleState();
}

class _AnimatedAppBarTitleState extends State<AnimatedAppBarTitle> {
  // Уникальный ключ для перезапуска анимации при каждом появлении виджета
  Key? _animationKey;

  @override
  void initState() {
    super.initState();
    // Создаем уникальный ключ при инициализации
    _animationKey = ValueKey('${widget.text}_${DateTime.now().millisecondsSinceEpoch}');
    // Перезапускаем анимацию после первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _animationKey = ValueKey('${widget.text}_${DateTime.now().millisecondsSinceEpoch}');
        });
      }
    });
  }

  @override
  void didUpdateWidget(AnimatedAppBarTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Перезапускаем анимацию только если текст действительно изменился
    if (oldWidget.text != widget.text) {
      setState(() {
        _animationKey = ValueKey('${widget.text}_${DateTime.now().millisecondsSinceEpoch}');
      });
    }
    // Если текст не изменился, не перезапускаем анимацию
  }

  @override
  Widget build(BuildContext context) {
    return BlurText(
      key: _animationKey, // Уникальный ключ для перезапуска анимации
      text: widget.text,
      duration: widget.duration,
      type: widget.animationType,
      textStyle: widget.textStyle ?? GoogleFonts.delaGothicOne(
        fontSize: 24,
        color: Colors.white,
      ),
    );
  }
}

