import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Виджет для lazy loading медиа - загружает контент только когда виджет становится видимым
class LazyMediaLoader extends StatefulWidget {
  final Widget child;
  final VoidCallback? onVisible; // Callback когда виджет становится видимым
  final bool loadImmediately; // Загружать сразу или ждать видимости
  final double preloadDistance; // Расстояние предзагрузки в пикселях
  final double? width; // Ширина для placeholder (чтобы избежать сплюснутости)
  final double? height; // Высота для placeholder

  const LazyMediaLoader({
    super.key,
    required this.child,
    this.onVisible,
    this.loadImmediately = false,
    this.preloadDistance = 500, // Предзагружаем за 500px до появления
    this.width,
    this.height,
  });

  @override
  State<LazyMediaLoader> createState() => _LazyMediaLoaderState();
}

class _LazyMediaLoaderState extends State<LazyMediaLoader> {
  bool _isVisible = false;
  final GlobalKey _key = GlobalKey();
  Timer? _fallbackTimer; // Таймер для принудительной загрузки если долго не видно

  @override
  void initState() {
    super.initState();
    if (widget.loadImmediately) {
      print('LazyMediaLoader: ⚡ Загрузка медиа сразу (loadImmediately=true)');
      _isVisible = true;
      widget.onVisible?.call();
    } else {
      print('LazyMediaLoader: 🔍 Начинаем проверку видимости...');
      // Проверяем видимость сразу (может сработать если виджет уже построен)
      _checkVisibility();
      // И после первого кадра
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _checkVisibility();
      });
      // Уменьшаем задержку с 50ms до 10ms для более быстрой реакции
      Future.delayed(const Duration(milliseconds: 10), () {
        if (mounted && !_isVisible) {
          _checkVisibility();
        }
      });
      
      // БАГ FIX: Fallback - если через 2 секунды не загрузилось, загружаем принудительно
      _fallbackTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && !_isVisible) {
          print('LazyMediaLoader: ⏰ Fallback - принудительная загрузка после 2 секунд');
          setState(() {
            _isVisible = true;
          });
          widget.onVisible?.call();
        }
      });
    }
  }
  
  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  void _checkVisibility() {
    if (!mounted || _isVisible) return;

    final BuildContext? context = _key.currentContext;
    if (context == null) {
      print('LazyMediaLoader: ⏳ Контекст еще не готов, повтор через 50ms...');
      // Уменьшаем задержку с 100ms до 50ms
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && !_isVisible) {
          _checkVisibility();
        }
      });
      return;
    }

    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      print('LazyMediaLoader: ⏳ RenderObject еще не готов...');
      return;
    }

    final RenderBox? renderBox = renderObject as RenderBox?;
    if (renderBox == null) return;

    // Получаем позицию виджета относительно viewport
    try {
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final screenHeight = MediaQuery.of(context).size.height;

      // БАГ FIX: Учитываем preloadDistance для более ранней загрузки
      // Считаем видимым если виджет в пределах экрана + preloadDistance
      final isVisible = position.dy < screenHeight + widget.preloadDistance && 
                       position.dy + size.height > -widget.preloadDistance;

      if (isVisible && !_isVisible) {
        print('LazyMediaLoader: ✅ Медиа стало видимым! Позиция: ${position.dy.toStringAsFixed(0)}px, экран: ${screenHeight.toStringAsFixed(0)}px');
        _fallbackTimer?.cancel(); // Отменяем fallback таймер
        setState(() {
          _isVisible = true;
        });
        widget.onVisible?.call();
      } else if (!isVisible) {
        print('LazyMediaLoader: 👁️ Медиа не видно. Позиция: ${position.dy.toStringAsFixed(0)}px, экран: ${screenHeight.toStringAsFixed(0)}px');
      }
    } catch (e) {
      print('LazyMediaLoader: ⚠️ Ошибка проверки видимости: $e, загружаем медиа (fallback)');
      // При ошибке считаем видимым (fallback для надежности)
      if (!_isVisible) {
        setState(() {
          _isVisible = true;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.loadImmediately && !_isVisible) {
      // Проверяем видимость при изменении зависимостей
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _checkVisibility();
      });
    }
  }

  // БАГ FIX: Принудительная загрузка при взаимодействии пользователя
  void _forceLoad() {
    if (!_isVisible && mounted) {
      print('LazyMediaLoader: 👆 Принудительная загрузка при взаимодействии');
      _fallbackTimer?.cancel();
      setState(() {
        _isVisible = true;
      });
      widget.onVisible?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // БАГ FIX: Проверяем видимость при скролле более агрессивно
        if (!widget.loadImmediately && !_isVisible) {
          // Проверяем сразу при скролле (не ждем postFrameCallback)
          _checkVisibility();
          // И еще раз после кадра для надежности
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isVisible) {
              _checkVisibility();
            }
          });
        }
        return false;
      },
      child: Container(
        key: _key,
        // БАГ FIX: Используем фиксированные размеры для placeholder чтобы избежать сплюснутости
        width: widget.width,
        height: widget.height,
        child: _isVisible || widget.loadImmediately
            ? widget.child
            : GestureDetector(
                // БАГ FIX: При нажатии/зажатии на placeholder загружаем медиа принудительно
                onTap: _forceLoad,
                onLongPress: _forceLoad,
                child: Container(
                  // БАГ FIX: Placeholder с теми же размерами что и реальный контент
                  width: widget.width,
                  height: widget.height,
                  color: const Color(0xFF262626),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to load',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

