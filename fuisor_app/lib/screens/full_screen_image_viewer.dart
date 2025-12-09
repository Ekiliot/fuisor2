import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../widgets/cached_network_image_with_signed_url.dart';

/// Полноэкранный просмотр изображения
class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? chatId;
  final String? postId;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.chatId,
    this.postId,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController = TransformationController();
  bool _showControls = true;
  Timer? _hideHintTimer;

  @override
  void initState() {
    super.initState();
    // Скрываем системные панели для полноэкранного режима
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    // Скрываем подсказку через 3 секунды
    _hideHintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  @override
  void dispose() {
    // Восстанавливаем системные панели
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hideHintTimer?.cancel();
    _transformationController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    // При показе контролов снова скрываем подсказку через 3 секунды
    if (_showControls) {
      _hideHintTimer?.cancel();
      _hideHintTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Изображение с возможностью зума и панорамирования
          GestureDetector(
            onTap: _toggleControls,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: CachedNetworkImageWithSignedUrl(
                  imageUrl: widget.imageUrl,
                  chatId: widget.chatId,
                  postId: widget.postId,
                  fit: BoxFit.contain,
                  placeholder: (context) => const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0095F6),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(
                      EvaIcons.imageOutline,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Верхняя панель с кнопкой закрытия
          if (_showControls)
            SafeArea(
              child: Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          EvaIcons.arrowBack,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      IconButton(
                        icon: const Icon(
                          EvaIcons.maximizeOutline,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: _resetZoom,
                        tooltip: 'Сбросить масштаб',
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Подсказка внизу (скрывается через 3 секунды)
          if (_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Нажмите для скрытия/показа элементов управления\nСведите пальцы для масштабирования',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

