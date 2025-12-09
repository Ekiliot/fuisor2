import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';

class VideoPreviewScreen extends StatefulWidget {
  final String videoPath;
  final bool shouldMirror;

  const VideoPreviewScreen({
    super.key,
    required this.videoPath,
    this.shouldMirror = false,
  });

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.file(File(widget.videoPath));
    await _controller!.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = true;
        _isPlaying = true;
      });
      _controller!.play();
      _controller!.setLooping(true);
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;

    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _controller!.play();
    } else {
      _controller!.pause();
    }
  }

  void _confirmVideo() {
    // Возвращаем путь к видео
    Navigator.of(context).pop(widget.videoPath);
  }

  void _cancelVideo() {
    // Удаляем видео файл и возвращаемся
    try {
      final file = File(widget.videoPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      // Игнорируем ошибки удаления
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Видео превью
            if (_isInitialized && _controller != null)
              Positioned.fill(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),

            // Кнопка закрытия (отмена) вверху слева
            Positioned(
              top: 20,
              left: 20,
              child: GestureDetector(
                onTap: _cancelVideo,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    EvaIcons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

            // Кнопка воспроизведения/паузы по центру
            if (_isInitialized)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _togglePlayPause,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlaying ? EvaIcons.pauseCircle : EvaIcons.playCircle,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),

            // Кнопка подтверждения внизу справа
            Positioned(
              bottom: 40,
              right: 20,
              child: GestureDetector(
                onTap: _confirmVideo,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0095F6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    EvaIcons.checkmark,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

