import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_editor/video_editor.dart';
import 'package:video_player/video_player.dart';
import '../utils/export_service.dart';
import '../../../widgets/app_notification.dart';

class EditorScreen extends StatefulWidget {
  final File file;

  const EditorScreen({super.key, required this.file});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum EditorMode { trim, text }

class _EditorScreenState extends State<EditorScreen> {
  late VideoEditorController _controller;
  bool _exported = false;
  String _exportText = "";
  EditorMode _currentMode = EditorMode.trim;
  String _overlayText = "";
  Offset _textPosition = Offset.zero; // Center offset
  double _textStartTime = 0.0; // Start time in seconds
  double _textEndTime = 12.0; // End time in seconds
  bool _isDeleteMode = false; // Track if delete mode is active

  @override
  void initState() {
    super.initState();
    _controller = VideoEditorController.file(
      widget.file,
      minDuration: const Duration(seconds: 1),
      maxDuration: const Duration(seconds: 60),
    );

    _controller.initialize(aspectRatio: 9 / 16).then((_) {
      setState(() {});
    }).catchError((error) {
      Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _exportText = "";
    _controller.dispose();
    super.dispose();
  }

  Future<void> _exportVideo() async {
    // Let user choose save location
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить видео',
      fileName: 'trimmed_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
      type: FileType.video,
      allowedExtensions: ['mp4'],
    );

    if (outputPath == null) {
      // User cancelled
      return;
    }

    setState(() => _exported = true);
    
    await _controller.video.pause();

    final start = _controller.minTrim * _controller.video.value.duration.inMilliseconds;
    final end = _controller.maxTrim * _controller.video.value.duration.inMilliseconds;
    final duration = end - start;

    // Note: Text export is not yet implemented in FFmpeg command
    final path = await ExportService.exportVideo(
      inputPath: widget.file.path,
      outputPath: outputPath,
      startSeconds: start / 1000.0,
      durationSeconds: duration / 1000.0,
    );

    setState(() => _exported = false);

    if (path != null) {
      if (mounted) {
        AppNotification.showSuccess(
          context,
          'Видео сохранено: $path',
        );
      }
    } else {
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка сохранения видео',
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _addText() {
    showDialog(
      context: context,
      builder: (context) {
        String text = _overlayText;
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Редактировать текст", style: TextStyle(color: Colors.white)),
          content: TextField(
            onChanged: (value) => text = value,
            controller: TextEditingController(text: _overlayText),
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFFFF00)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Отмена", style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () {
                setState(() => _overlayText = text);
                Navigator.pop(context);
              },
              child: const Text("OK", style: TextStyle(color: Color(0xFFFFFF00))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _controller.initialized
          ? SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      _topNavBar(),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CropGridViewer.preview(controller: _controller),
                            if (_overlayText.isNotEmpty)
                              AnimatedBuilder(
                                animation: _controller.video,
                                builder: (_, __) {
                                  final currentPosition = _controller.video.value.position.inSeconds.toDouble();
                                  final isVisible = currentPosition >= _textStartTime && currentPosition <= _textEndTime;
                                  
                                  if (!isVisible) return Container();
                                  
                                  return Positioned(
                                    left: _textPosition.dx,
                                    top: _textPosition.dy,
                                    child: Draggable(
                                      feedback: _buildTextWidget(isDragging: true),
                                      childWhenDragging: Container(),
                                      onDragEnd: (details) {
                                        setState(() {
                                          // Use localPosition for absolute positioning
                                          _textPosition = details.offset;
                                        });
                                      },
                                      child: _buildTextWidget(),
                                    ),
                                  );
                                },
                              ),
                            AnimatedBuilder(
                              animation: _controller.video,
                              builder: (_, __) => AnimatedOpacity(
                                opacity: _controller.isPlaying ? 0 : 1,
                                duration: const Duration(milliseconds: 300),
                                child: GestureDetector(
                                  onTap: _controller.video.play,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black26,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                      size: 80,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ValueListenableBuilder(
                                  valueListenable: _controller.video,
                                  builder: (context, VideoPlayerValue value, child) {
                                    final duration = _controller.video.value.duration;
                                    final pos = value.position;
                                    return Text(
                                      "${_formatDuration(pos)}/${_formatDuration(duration)}",
                                      style: const TextStyle(color: Colors.white),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _controlBar(),
                      if (_currentMode == EditorMode.trim) _trimmer(),
                      if (_currentMode == EditorMode.text) _textEditor(),
                      _bottomNavBar(),
                    ],
                  ),
                  if (_exported)
                    Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(color: Color(0xFFFFFF00)),
                      ),
                    ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator(color: Color(0xFFFFFF00))),
    );
  }

  Widget _topNavBar() {
    return Container(
      height: 0,
    );
  }

  Widget _controlBar() {
    if (_isDeleteMode) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _overlayText = "";
                  _isDeleteMode = false;
                  _currentMode = EditorMode.trim;
                });
              },
              icon: const Icon(Icons.delete),
              label: const Text("Удалить текст", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _isDeleteMode = false;
                });
              },
              child: const Text("Отмена", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildControlButton(
            _currentMode == EditorMode.trim ? "Обрезка" : "",
            Icons.cut,
            _currentMode == EditorMode.trim,
            onTap: () => setState(() => _currentMode = EditorMode.trim),
          ),
          const SizedBox(width: 10),
          _buildControlButton(
            _currentMode == EditorMode.text ? "Текст" : "",
            Icons.text_fields,
            _currentMode == EditorMode.text,
            onTap: () {
              setState(() {
                _currentMode = EditorMode.text;
                if (_overlayText.isEmpty) {
                  _overlayText = "text";
                  // Initialize text position to center of screen
                  _textPosition = Offset(
                    MediaQuery.of(context).size.width / 2 - 50,
                    MediaQuery.of(context).size.height / 3,
                  );
                }
              });
            },
          ),
          const SizedBox(width: 10),
          _buildControlButton("", Icons.music_note, false),
          const SizedBox(width: 10),
          _buildControlButton("", Icons.pause, false, onTap: () {
             if (_controller.isPlaying) _controller.video.pause();
          }),
          const SizedBox(width: 10),
          const Icon(Icons.undo, color: Colors.white),
          const SizedBox(width: 10),
          const Icon(Icons.redo, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildControlButton(String text, IconData icon, bool isActive, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFFFF00) : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isNotEmpty) ...[
              Text(
                text,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Icon(icon, color: Colors.black, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextWidget({bool isDragging = false}) {
    return GestureDetector(
      onTap: isDragging ? null : _addText,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDragging ? Colors.black45 : Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _overlayText,
          style: const TextStyle(
            fontSize: 30,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 3.0,
                color: Colors.black,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textEditor() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          const Text(
            'Используйте трекбар в режиме обрезки для настройки времени текста',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _addText,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFFF00),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: const Text("Редактировать текст", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _trimmer() {
    final videoDuration = _controller.video.value.duration.inSeconds.toDouble();
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TrimSlider(
                  controller: _controller,
                  height: 60,
                  horizontalMargin: 12,
                  child: TrimTimeline(
                    controller: _controller,
                    padding: const EdgeInsets.only(top: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Text track (only show if text exists)
        if (_overlayText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final startPosition = (_textStartTime / videoDuration) * totalWidth;
                final endPosition = (_textEndTime / videoDuration) * totalWidth;
                final trackWidth = endPosition - startPosition;

                return GestureDetector(
                  onTap: () {
                    setState(() => _currentMode = EditorMode.text);
                  },
                  onLongPress: () {
                    setState(() {
                      _isDeleteMode = true;
                    });
                  },
                  child: Container(
                    height: 60,
                    color: Colors.transparent,
                    child: Stack(
                      children: [
                        // Background (full timeline)
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[850],
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        // Text track
                        Positioned(
                          left: startPosition,
                          child: GestureDetector(
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                final delta = details.delta.dx / totalWidth * videoDuration;
                                final newStart = (_textStartTime + delta).clamp(0.0, videoDuration);
                                final newEnd = (_textEndTime + delta).clamp(0.0, videoDuration);
                                
                                // Keep duration constant when dragging
                                final duration = _textEndTime - _textStartTime;
                                if (newEnd <= videoDuration && newStart >= 0) {
                                  _textStartTime = newStart;
                                  _textEndTime = newEnd;
                                }
                              });
                            },
                            child: Container(
                              width: trackWidth.clamp(60.0, totalWidth),
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFF00),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Row(
                                children: [
                                  // Left handle
                                  GestureDetector(
                                    onHorizontalDragUpdate: (details) {
                                      setState(() {
                                        final delta = details.delta.dx / totalWidth * videoDuration;
                                        _textStartTime = (_textStartTime + delta).clamp(0.0, _textEndTime - 0.5);
                                      });
                                    },
                                    child: Container(
                                      width: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(6),
                                          bottomLeft: Radius.circular(6),
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.drag_handle, color: Colors.black, size: 12),
                                      ),
                                    ),
                                  ),
                                  // Center content
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.text_fields, color: Colors.black, size: 16),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              _overlayText.length > 8 ? '${_overlayText.substring(0, 8)}...' : _overlayText,
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '${(_textEndTime - _textStartTime).toInt()}s',
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Right handle
                                  GestureDetector(
                                    onHorizontalDragUpdate: (details) {
                                      setState(() {
                                        final delta = details.delta.dx / totalWidth * videoDuration;
                                        _textEndTime = (_textEndTime + delta).clamp(_textStartTime + 0.5, videoDuration);
                                      });
                                    },
                                    child: Container(
                                      width: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(6),
                                          bottomRight: Radius.circular(6),
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.drag_handle, color: Colors.black, size: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _bottomNavBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Назад", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: _exportVideo,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Сохранить", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
