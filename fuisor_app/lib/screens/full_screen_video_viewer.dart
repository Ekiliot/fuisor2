import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/signed_url_cache_service.dart';

/// Полноэкранный просмотр видео
class FullScreenVideoViewer extends StatefulWidget {
  final String videoUrl;
  final String? chatId;
  final String? postId;
  final String? thumbnailUrl;

  const FullScreenVideoViewer({
    super.key,
    required this.videoUrl,
    this.chatId,
    this.postId,
    this.thumbnailUrl,
  });

  @override
  State<FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<FullScreenVideoViewer> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _showControls = true;
  bool _isPlaying = false;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    // Скрываем системные панели для полноэкранного режима
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _loadVideo();
  }

  @override
  void dispose() {
    // Восстанавливаем системные панели
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadVideo() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Получаем signed URL
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        throw Exception('No access token');
      }

      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      
      final cacheService = SignedUrlCacheService();
      final signedUrl = await cacheService.getSignedUrl(
        path: widget.videoUrl,
        chatId: widget.chatId,
        postId: widget.postId,
        apiService: apiService,
      );

      if (!mounted) return;

      // Инициализируем видеоплеер
      _controller = VideoPlayerController.networkUrl(Uri.parse(signedUrl));
      await _controller!.initialize();
      
      _controller!.addListener(() {
        if (mounted) {
          setState(() {
            _isPlaying = _controller!.value.isPlaying;
          });
        }
      });

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Автоматически запускаем воспроизведение
        await _controller!.play();
        _startControlsTimer();
      }
    } catch (e) {
      print('FullScreenVideoViewer: Error loading video: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  Future<void> _togglePlayPause() async {
    if (_controller == null) return;
    
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    } else {
      await _controller!.play();
    }
    _startControlsTimer();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Видео
          Center(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0095F6),
                    ),
                  )
                : _hasError
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              EvaIcons.videoOutline,
                              color: Colors.white,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Ошибка загрузки видео',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadVideo,
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      )
                    : GestureDetector(
                        onTap: _toggleControls,
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
          ),

          // Элементы управления
          if (_showControls && !_isLoading && !_hasError && _controller != null)
            Stack(
              children: [
                // Верхняя панель
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
                          if (_controller!.value.duration.inSeconds > 0)
                            Text(
                              '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Центральная кнопка play/pause
                Center(
                  child: GestureDetector(
                    onTap: _togglePlayPause,
                    child: Container(
                      width: 80,
                      height: 80,
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

                // Нижняя панель с прогресс-баром
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Прогресс-бар
                        if (_controller!.value.duration.inSeconds > 0)
                          _VideoProgressBar(
                            controller: _controller!,
                          ),
                        const SizedBox(height: 8),
                        // Кнопки управления
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isPlaying ? EvaIcons.pauseCircle : EvaIcons.playCircle,
                                color: Colors.white,
                                size: 32,
                              ),
                              onPressed: _togglePlayPause,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Кастомный прогресс-бар для видео с возможностью перемотки
class _VideoProgressBar extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoProgressBar({
    required this.controller,
  });

  @override
  State<_VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<_VideoProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateProgress);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateProgress);
    super.dispose();
  }

  void _updateProgress() {
    if (!_isDragging && mounted) {
      setState(() {});
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.controller.value.duration;
    final position = _isDragging
        ? Duration(milliseconds: (_dragValue * duration.inMilliseconds).round())
        : widget.controller.value.position;
    
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Column(
      children: [
        // Время и прогресс-бар
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onHorizontalDragStart: (details) {
                        setState(() {
                          _isDragging = true;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        final x = details.localPosition.dx;
                        final width = constraints.maxWidth;
                        final newProgress = (x / width).clamp(0.0, 1.0);
                        setState(() {
                          _dragValue = newProgress;
                        });
                      },
                      onHorizontalDragEnd: (details) async {
                        final newPosition = Duration(
                          milliseconds: (_dragValue * duration.inMilliseconds).round(),
                        );
                        await widget.controller.seekTo(newPosition);
                        setState(() {
                          _isDragging = false;
                        });
                      },
                      onTapDown: (details) async {
                        final x = details.localPosition.dx;
                        final width = constraints.maxWidth;
                        final newProgress = (x / width).clamp(0.0, 1.0);
                        final newPosition = Duration(
                          milliseconds: (newProgress * duration.inMilliseconds).round(),
                        );
                        await widget.controller.seekTo(newPosition);
                      },
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: Colors.white10,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Буферизованная часть
                            if (widget.controller.value.buffered.isNotEmpty)
                              ...widget.controller.value.buffered.map((range) {
                                final start = range.start.inMilliseconds / duration.inMilliseconds;
                                final end = range.end.inMilliseconds / duration.inMilliseconds;
                                return Positioned(
                                  left: constraints.maxWidth * start,
                                  child: SizedBox(
                                    width: constraints.maxWidth * (end - start),
                                    child: Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(2),
                                        color: Colors.white30,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            // Прогресс
                            FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  color: const Color(0xFF0095F6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

