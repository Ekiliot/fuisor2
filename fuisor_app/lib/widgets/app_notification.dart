import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';

enum AppNotificationType {
  success,
  error,
  info,
  loading,
}

class AppNotification {
  static OverlayEntry? _currentOverlay;

  static void show(
    BuildContext context, {
    required String message,
    AppNotificationType type = AppNotificationType.info,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
    Color? iconColor,
  }) {
    // Удаляем предыдущее уведомление, если оно есть
    hide();

    final overlay = Overlay.of(context);
    
    _currentOverlay = OverlayEntry(
      builder: (context) => _AppNotificationWidget(
        message: message,
        type: type,
        duration: duration,
        icon: icon,
        iconColor: iconColor,
        onDismiss: () {
          hide();
        },
      ),
    );

    overlay.insert(_currentOverlay!);
  }

  static void hide() {
    if (_currentOverlay != null) {
      _currentOverlay!.remove();
      _currentOverlay = null;
    }
  }

  // Удобные методы для разных типов уведомлений
  static void showSuccess(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message: message,
      type: AppNotificationType.success,
      icon: EvaIcons.checkmarkCircle2Outline,
      iconColor: Colors.green,
      duration: duration ?? const Duration(seconds: 2),
    );
  }

  static void showError(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message: message,
      type: AppNotificationType.error,
      icon: EvaIcons.alertCircleOutline,
      iconColor: Colors.red,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  static void showInfo(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message: message,
      type: AppNotificationType.info,
      icon: EvaIcons.infoOutline,
      iconColor: const Color(0xFF0095F6),
      duration: duration ?? const Duration(seconds: 2),
    );
  }

  static void showLoading(BuildContext context, String message) {
    show(
      context,
      message: message,
      type: AppNotificationType.loading,
      duration: const Duration(seconds: 10), // Долгое для loading
    );
  }
}

class _AppNotificationWidget extends StatefulWidget {
  final String message;
  final AppNotificationType type;
  final Duration duration;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback onDismiss;

  const _AppNotificationWidget({
    required this.message,
    required this.type,
    required this.duration,
    this.icon,
    this.iconColor,
    required this.onDismiss,
  });

  @override
  State<_AppNotificationWidget> createState() => _AppNotificationWidgetState();
}

class _AppNotificationWidgetState extends State<_AppNotificationWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _glowController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _slideAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: Curves.easeInOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    // Автоматически скрываем через duration
    if (widget.type != AppNotificationType.loading) {
      Future.delayed(widget.duration, () {
        if (mounted) {
          _controller.reverse().then((_) {
            widget.onDismiss();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Color _getGlowColor() {
    if (widget.iconColor != null) {
      return widget.iconColor!;
    }
    
    switch (widget.type) {
      case AppNotificationType.success:
        return Colors.green;
      case AppNotificationType.error:
        return Colors.red;
      case AppNotificationType.info:
        return const Color(0xFF0095F6);
      case AppNotificationType.loading:
        return const Color(0xFF0095F6);
    }
  }

  Widget _getIcon() {
    if (widget.icon != null) {
      return Icon(
        widget.icon,
        color: Colors.white,
        size: 20,
      );
    }

    switch (widget.type) {
      case AppNotificationType.success:
        return const Icon(
          EvaIcons.checkmarkCircle2Outline,
          color: Colors.white,
          size: 20,
        );
      case AppNotificationType.error:
        return const Icon(
          EvaIcons.alertCircleOutline,
          color: Colors.white,
          size: 20,
        );
      case AppNotificationType.info:
        return const Icon(
          EvaIcons.infoOutline,
          color: Colors.white,
          size: 20,
        );
      case AppNotificationType.loading:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final glowColor = _getGlowColor();
    
    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: true,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(_slideAnimation),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_glowAnimation, _glowController]),
                  builder: (context, child) {
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          // Glow эффект
                          BoxShadow(
                            color: glowColor.withOpacity(0.4 * _glowAnimation.value),
                            blurRadius: 12 + (8 * _glowAnimation.value),
                            spreadRadius: 2 + (2 * _glowAnimation.value),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _getIcon(),
                      const SizedBox(width: 10),
                      Flexible(
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            height: 1.0,
                          ),
                          child: Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

