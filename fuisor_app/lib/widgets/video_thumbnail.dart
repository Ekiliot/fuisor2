import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class VideoThumbnail extends StatefulWidget {
  final String videoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const VideoThumbnail({
    super.key,
    required this.videoUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      // Проверяем, является ли videoUrl путем к файлу (начинается с post_)
      String videoUrl = widget.videoUrl;
      final isFilePath = videoUrl.startsWith('post_') || videoUrl.startsWith('thumb_');
      
      if (isFilePath) {
        // Получаем signed URL для приватного файла
        try {
          final prefs = await SharedPreferences.getInstance();
          final accessToken = prefs.getString('access_token');
          if (accessToken != null) {
            final apiService = ApiService();
            apiService.setAccessToken(accessToken);
            
            final result = await apiService.getPostMediaSignedUrl(
              mediaPath: widget.videoUrl,
            );
            videoUrl = result['signedUrl']!;
            print('VideoThumbnail: Got signed URL for video');
          }
        } catch (e) {
          print('VideoThumbnail: Error getting signed URL: $e, using original URL');
          // Продолжаем с оригинальным URL, если не удалось получить signed URL
        }
      }

      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _controller!.initialize();
      
      // Переходим к первому кадру и останавливаем
      await _controller!.seekTo(Duration.zero);
      await _controller!.pause();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading video thumbnail: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF0095F6),
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_hasError || _controller == null || !_controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(
            EvaIcons.playCircleOutline,
            color: Colors.white,
            size: 48,
          ),
        ),
      );
    }

    // Используем VideoPlayer для отображения первого кадра
    return Stack(
      fit: StackFit.expand,
      children: [
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
        // Затемнение для лучшей видимости иконки play
        Container(
          color: Colors.black.withOpacity(0.2),
        ),
        // Иконка play по центру
        const Center(
          child: Icon(
            EvaIcons.playCircleOutline,
            color: Colors.white,
            size: 48,
          ),
        ),
      ],
    );
  }
}

