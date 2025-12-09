import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_editor/video_editor.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/export_service.dart';
import '../widgets/app_notification.dart';

// Model for text overlay styling
class TextOverlayStyle {
  final String text;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final Color textColor;
  final Color backgroundColor;

  const TextOverlayStyle({
    required this.text,
    this.fontWeight = FontWeight.bold,
    this.fontStyle = FontStyle.normal,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0x4D000000), // black@0.3
  });

  TextOverlayStyle copyWith({
    String? text,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    Color? textColor,
    Color? backgroundColor,
  }) {
    return TextOverlayStyle(
      text: text ?? this.text,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }
}

// Model for a complete text layer (style + position + timing)
class TextLayer {
  TextOverlayStyle style;
  Offset positionNormalized;
  double startTime;
  double endTime;

  TextLayer({
    required this.style,
    this.positionNormalized = const Offset(0.5, 0.5),
    this.startTime = 0.0,
    this.endTime = 3.0,
  });
}

class VideoEditorScreen extends StatefulWidget {
  final XFile? selectedFile;
  final Uint8List? selectedImageBytes;
  final VideoPlayerController? videoController;

  const VideoEditorScreen({
    super.key,
    this.selectedFile,
    this.selectedImageBytes,
    this.videoController,
  });

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

enum EditorMode { trim, text }

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  late VideoEditorController _controller;
  bool _exported = false;
  EditorMode _currentMode = EditorMode.trim;
  
  // Text overlay state - multiple layers support
  List<TextLayer> _textLayers = [];
  int? _selectedLayerIndex; // Currently selected layer for editing
  bool _isDeleteMode = false; // Track if delete mode is active
  
  // Text input controller for the selected layer
  final TextEditingController _textInputController = TextEditingController();
  
  // Audio state
  XFile? _selectedAudio;
  String? _audioFileName;
  double _audioStartTime = 0.0;
  double _audioEndTime = 0.0;
  // ignore: unused_field
  double _audioDuration = 0.0; // Will be used when file picker is fully integrated
  bool _muteOriginalAudio = false;
  
  final GlobalKey _previewKey = GlobalKey(); // Key для получения размеров превью
  final GlobalKey _stackKey = GlobalKey(); // Key для Stack для получения координат
  final GlobalKey _trimmerKey = GlobalKey(); // Key для измерения размеров TrimSlider
  Size? _previewSize; // Кешируем размер превью для фиксации
  bool _isSeeking = false; // Флаг для предотвращения множественных seek операций
  Timer? _positionCheckTimer; // Timer для периодической проверки позиции

  @override
  void initState() {
    super.initState();
    if (widget.selectedFile == null) {
      // Вернуться назад если нет файла
      WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
          Navigator.pop(context);
        }
      });
      return;
          }

    _controller = VideoEditorController.file(
      File(widget.selectedFile!.path),
      minDuration: const Duration(seconds: 1),
      maxDuration: const Duration(seconds: 60),
    );

    _controller.initialize(aspectRatio: 9 / 16).then((_) {
      if (mounted) {
        // Сбрасываем кеш размера при инициализации
        _previewSize = null;
        
        // Add listener for video position changes
        _controller.video.addListener(_onVideoPositionChanged);
        
        // Используем Timer для периодической проверки позиции и границ обрезки
        _positionCheckTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
          if (mounted && _controller.initialized && _controller.video.value.isInitialized) {
            _handleVideoPosition();
          } else {
            timer.cancel();
          }
        });
        
        setState(() {});
      }
    }).catchError((error) {
      print('Error initializing video editor: $error');
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }
  
  void _onVideoPositionChanged() {
    // Trigger rebuild when video position changes to update text visibility
    if (mounted && _textLayers.isNotEmpty) {
      setState(() {});
    }
  }

  void _handleVideoPosition() {
    if (!_controller.initialized || !_controller.video.value.isInitialized || _isSeeking) return;
    if (!_controller.isPlaying) return; // Проверяем только когда видео воспроизводится

    final videoDuration = _controller.video.value.duration.inMilliseconds;
    final currentPosition = _controller.video.value.position.inMilliseconds;
    final trimStart = _controller.minTrim * videoDuration;
    final trimEnd = _controller.maxTrim * videoDuration;

    // Проверяем, нужно ли выполнять seek (только если позиция значительно вышла за границы)
    bool needsSeek = false;
    if (currentPosition >= trimEnd) {
      needsSeek = true;
    } else if (currentPosition < trimStart - 100) { // Добавляем запас 100ms для начала
      needsSeek = true;
    }

    if (!needsSeek) return;

    _isSeeking = true;

    // Простой seek без паузы для более плавного зацикливания
    final seekPosition = trimStart.toInt();
    _controller.video.seekTo(Duration(milliseconds: seekPosition)).then((_) {
      // Убеждаемся, что видео продолжает играть после seek
      if (mounted && !_controller.isPlaying) {
        _controller.video.play();
      }
      // Сбрасываем флаг быстрее для более быстрого отклика
      Future.delayed(const Duration(milliseconds: 50), () {
    if (mounted) {
          _isSeeking = false;
        }
      });
    });
        }
        
  @override
  void dispose() {
    // Отменяем Timer для проверки позиции
    _positionCheckTimer?.cancel();
    _positionCheckTimer = null;
    
    // Remove video position listener
    _controller.video.removeListener(_onVideoPositionChanged);
    
    // Очищаем текстовый контроллер
    _textInputController.dispose();
    
    // Отключаем видео контроллер из предыдущего экрана, если он был передан
    widget.videoController?.pause();
    widget.videoController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _exportVideo() async {
    if (widget.selectedFile == null) {
          return;
        }
        
    setState(() => _exported = true);
    
    await _controller.video.pause();

    final start = _controller.minTrim * _controller.video.value.duration.inMilliseconds;
    final end = _controller.maxTrim * _controller.video.value.duration.inMilliseconds;
    final duration = end - start;

    // Используем временную директорию вместо диалога сохранения
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Получаем размеры видео
    final videoSize = _controller.video.value.size;
    final videoWidth = videoSize.width.round();
    final videoHeight = videoSize.height.round();

    // Подготавливаем параметры текста (поддержка нескольких слоёв)
    List<TextOverlay> textOverlays = [];
    if (_textLayers.isNotEmpty) {
      final videoDuration = _controller.video.value.duration.inMilliseconds / 1000.0;
      final trimStart = _controller.minTrim * videoDuration;
      final trimEnd = _controller.maxTrim * videoDuration;
      
      print('VideoEditorScreen: Video info:');
      print('  Total duration: ${videoDuration}s');
      print('  Trim: ${trimStart}s - ${trimEnd}s');
      print('  Text layers: ${_textLayers.length}');
      
      for (int i = 0; i < _textLayers.length; i++) {
        final layer = _textLayers[i];
        if (layer.style.text.isEmpty) continue;
        
        // Ограничиваем время текста границами обрезанного сегмента
        final clampedTextStart = layer.startTime.clamp(trimStart, trimEnd);
        final clampedTextEnd = layer.endTime.clamp(trimStart, trimEnd);
        
        // Время текста относительно начала обрезанного сегмента
        final textStartRelative = clampedTextStart - trimStart;
        final textEndRelative = clampedTextEnd - trimStart;
        
        // Оцениваем размер текста для корректировки позиции
        // Limit text width to 80% of video width
        final textSize = _estimateTextSize(layer.style, maxWidth: videoWidth * 0.8);
        final textWidth = textSize.width;
        final textHeight = textSize.height;
        
        // Рассчитываем абсолютные координаты из нормализованных (центр текста)
        final centerX = layer.positionNormalized.dx * videoWidth;
        final centerY = layer.positionNormalized.dy * videoHeight;
        
        // Конвертируем в верхний левый угол и ограничиваем границами видео
        final clampedX = (centerX - textWidth / 2).clamp(0.0, videoWidth - textWidth);
        final clampedY = (centerY - textHeight / 2).clamp(0.0, videoHeight - textHeight);
        
        textOverlays.add(TextOverlay(
          text: layer.style.text,
          x: clampedX,
          y: clampedY,
          startTime: textStartRelative,
          endTime: textEndRelative,
          fontWeight: layer.style.fontWeight,
          fontStyle: layer.style.fontStyle,
          textColor: layer.style.textColor,
          backgroundColor: layer.style.backgroundColor,
        ));
        
        print('  Layer $i: "${layer.style.text}" at (${clampedX.round()}, ${clampedY.round()}) time: ${textStartRelative.toStringAsFixed(2)}s - ${textEndRelative.toStringAsFixed(2)}s');
      }
    }
    
    // Подготавливаем параметры аудио, если оно есть
    String? audioPath;
    double? audioStartTime;
    double? audioEndTime;
    if (_selectedAudio != null) {
      audioPath = _selectedAudio!.path;
      final videoDuration = _controller.video.value.duration.inMilliseconds / 1000.0;
      final trimStart = _controller.minTrim * videoDuration;
      final trimEnd = _controller.maxTrim * videoDuration;
      
      // Ограничиваем время аудио границами обрезанного сегмента
      audioStartTime = _audioStartTime.clamp(trimStart, trimEnd);
      audioEndTime = _audioEndTime.clamp(trimStart, trimEnd);
      
      print('VideoEditorScreen: Exporting with audio:');
      print('  Audio path: $audioPath');
      print('  Audio time: ${audioStartTime}s - ${audioEndTime}s');
      print('  Mute original: $_muteOriginalAudio');
    }

    final path = await ExportService.exportVideo(
      inputPath: widget.selectedFile!.path,
      outputPath: outputPath,
      startSeconds: start / 1000.0,
      durationSeconds: duration / 1000.0,
      textOverlays: textOverlays.isNotEmpty ? textOverlays : null,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      audioPath: audioPath,
      audioStartTime: audioStartTime,
      audioEndTime: audioEndTime,
      muteOriginalAudio: _muteOriginalAudio,
    );

    setState(() => _exported = false);

    if (path != null && mounted) {
      // Небольшая задержка для завершения записи файла
      await Future.delayed(const Duration(milliseconds: 500));

      // Проверяем, что файл действительно создан
      final exportedFile = File(path);
      final fileExists = await exportedFile.exists();
      final fileSize = fileExists ? await exportedFile.length() : 0;
      print('VideoEditorScreen: Export completed - file exists: $fileExists, size: $fileSize bytes, path: $path');

      if (fileExists && fileSize > 0) {
        // Возвращаем XFile для использования в CreatePostScreen
        Navigator.of(context).pop(XFile(path));
      } else {
        print('VideoEditorScreen: Exported file is invalid');
        if (mounted) {
          AppNotification.showError(
            context,
            'Ошибка: экспортированный файл поврежден',
          );
        }
      }
    } else {
      print('VideoEditorScreen: Export failed - path is null');
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

  void _addNewTextLayer() {
    if (!_controller.initialized) return;
    
    final videoDurationMs = _controller.video.value.duration.inMilliseconds;
    final videoDuration = videoDurationMs / 1000.0;
    final trimStart = _controller.minTrim * videoDuration;
    final trimEnd = _controller.maxTrim * videoDuration;
    final currentPositionMs = _controller.video.value.position.inMilliseconds;
    final currentPosition = currentPositionMs / 1000.0;

    final startTime = currentPosition.clamp(trimStart, trimEnd - 0.5);
    final endTime = (startTime + 3.0).clamp(startTime + 0.5, trimEnd);

    final newLayer = TextLayer(
      style: const TextOverlayStyle(text: "Текст"),
      positionNormalized: const Offset(0.5, 0.5),
      startTime: startTime,
      endTime: endTime,
    );

    setState(() {
      _textLayers.add(newLayer);
      _selectedLayerIndex = _textLayers.length - 1;
    });
  }

  void _deleteSelectedLayer() {
    if (_selectedLayerIndex == null || _selectedLayerIndex! >= _textLayers.length) return;
    
    setState(() {
      _textLayers.removeAt(_selectedLayerIndex!);
      if (_textLayers.isEmpty) {
        _selectedLayerIndex = null;
        _currentMode = EditorMode.trim;
      } else {
        _selectedLayerIndex = (_selectedLayerIndex! - 1).clamp(0, _textLayers.length - 1);
      }
    });
  }

  Future<void> _pickAudio() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.white),
              title: const Text('Из галереи', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                await _pickAudioFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_music, color: Colors.white),
              title: const Text('Из библиотеки', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                AppNotification.showInfo(
                  context,
                  'Скоро будет доступно',
                );
              },
            ),
            if (_selectedAudio != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Удалить аудио', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedAudio = null;
                    _audioFileName = null;
                    _audioDuration = 0.0;
                    _audioStartTime = 0.0;
                    _audioEndTime = 0.0;
                    _muteOriginalAudio = false;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAudioFromGallery() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        
        // Get audio duration
        final duration = await _getAudioDuration(file.path);
        
        if (duration <= 0) {
          if (mounted) {
            AppNotification.showError(
              context,
              'Не удалось определить длительность аудио файла',
            );
          }
          return;
        }

        // Get video trim info for default audio timing
        if (!_controller.initialized) {
          if (mounted) {
            AppNotification.showError(
              context,
              'Дождитесь загрузки видео',
            );
          }
          return;
        }

        final videoDurationMs = _controller.video.value.duration.inMilliseconds;
        final videoDuration = videoDurationMs / 1000.0;
        final trimStart = _controller.minTrim * videoDuration;
        final trimEnd = _controller.maxTrim * videoDuration;
        final trimDuration = trimEnd - trimStart;

        // Set audio to start at trim start, end at min(audio duration, trim duration)
        final audioDuration = duration;
        final audioEndTime = trimStart + audioDuration.clamp(0.0, trimDuration);

        setState(() {
          _selectedAudio = XFile(file.path);
          _audioFileName = fileName;
          _audioDuration = audioDuration;
          _audioStartTime = trimStart;
          _audioEndTime = audioEndTime;
          _muteOriginalAudio = false;
        });
      }
    } catch (e) {
      print('Error picking audio: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка выбора аудио: $e',
        );
      }
    }
  }

  // ignore: unused_element
  Future<double> _getAudioDuration(String audioPath) async {
    try {
      final player = AudioPlayer();
      await player.setSourceDeviceFile(audioPath);
      final duration = await player.getDuration();
      await player.dispose();
      return (duration?.inMilliseconds ?? 0).toDouble() / 1000.0;
    } catch (e) {
      print('Error getting audio duration: $e');
      return 0.0;
    }
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
                      // Фиксированная высота для превью (не зависит от области инструментов)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Вычисляем размер превью с учетом aspect ratio при первом расчете
                          if (_previewSize == null) {
                            final screenWidth = MediaQuery.of(context).size.width;
                            final screenHeight = MediaQuery.of(context).size.height;
                            // Используем 50% высоты экрана для превью
                            final maxHeight = screenHeight * 0.5;
                            final previewHeight = screenWidth / (9 / 16); // 9:16 aspect ratio
                            final calculatedHeight = (previewHeight > maxHeight) ? maxHeight : previewHeight;
                            final calculatedWidth = calculatedHeight * (9 / 16);
                            _previewSize = Size(calculatedWidth, calculatedHeight);
                          }
                          
                          // Используем кешированный размер для фиксации
                          final fixedPreviewWidth = _previewSize!.width;
                          final fixedPreviewHeight = _previewSize!.height;
                          
                          return SizedBox(
                            height: fixedPreviewHeight,
                            child: Center(
        child: Stack(
                                key: _stackKey,
                                alignment: Alignment.center,
          children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: fixedPreviewWidth,
                                      height: fixedPreviewHeight,
                                      key: _previewKey,
                                      child: CropGridViewer.preview(controller: _controller),
                ),
              ),
                                // Multiple text layers - each layer is independent
                                ..._textLayers.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final layer = entry.value;
                                  
                                  // Pre-calculate text size once per layer (not in AnimatedBuilder)
                                  // Limit text width to 80% of preview width to avoid overflow
                                  final textSize = _estimateTextSize(layer.style, maxWidth: fixedPreviewWidth * 0.8);
                                  final textWidth = textSize.width;
                                  final textHeight = textSize.height;
                                  
                                  // Calculate position based on normalized coords
                                  // Use center-based positioning to avoid jumps
                                  final centerX = layer.positionNormalized.dx * fixedPreviewWidth;
                                  final centerY = layer.positionNormalized.dy * fixedPreviewHeight;
                                  
                                  // Convert to top-left position, clamped to bounds
                                  final leftPos = (centerX - textWidth / 2).clamp(0.0, fixedPreviewWidth - textWidth);
                                  final topPos = (centerY - textHeight / 2).clamp(0.0, fixedPreviewHeight - textHeight);
                                  
                                  final isSelected = _selectedLayerIndex == index;
                                  
                                  // ValueListenableBuilder automatically rebuilds when video position changes
                                  return ValueListenableBuilder<VideoPlayerValue>(
                                    valueListenable: _controller.video,
                                    builder: (_, videoValue, __) {
                                      // Use EXACT same calculation as trackbar for synchronization
                                      final videoDurationMs = videoValue.duration.inMilliseconds;
                                      final videoDuration = videoDurationMs / 1000.0;
                                      
                                      // Calculate trim bounds (EXACTLY same as in trackbar)
                                      final trimStart = _controller.minTrim * videoDuration;
                                      final trimEnd = _controller.maxTrim * videoDuration;
                                      
                                      // Clamp layer times (EXACTLY like in trackbar)
                                      final layerStart = layer.startTime.clamp(trimStart, trimEnd);
                                      final layerEnd = layer.endTime.clamp(layerStart, trimEnd);
                                      
                                      // Get current position in seconds (absolute)
                                      final currentPosition = videoValue.position.inMilliseconds / 1000.0;
                                      
                                      // Playhead shows position relative to trimStart (0 at trimStart, increases to trimDuration at trimEnd)
                                      // Calculate relative positions to match playhead visualization
                                      final relativeCurrentPos = currentPosition - trimStart;
                                      final relativeLayerStart = layerStart - trimStart;
                                      final relativeLayerEnd = layerEnd - trimStart;
                                      
                                      // Text is visible when relative position matches layer range (exactly like playhead)
                                      final isVisible = relativeCurrentPos >= relativeLayerStart && relativeCurrentPos <= relativeLayerEnd;
                                      
                                      if (!isVisible) return const SizedBox.shrink();
                                      
                                      return Positioned(
                                        left: leftPos,
                                        top: topPos,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedLayerIndex = index;
                                              _currentMode = EditorMode.text;
                                            });
                                          },
                                          child: Draggable(
                                            feedback: Material(
                                              color: Colors.transparent,
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: fixedPreviewWidth * 0.8,
                                                ),
                                                child: _buildTextWidgetForLayer(layer.style, isDragging: true),
                                              ),
                                            ),
                                            childWhenDragging: const SizedBox.shrink(),
                                            onDragEnd: (details) {
                                              final RenderBox? stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
                                              if (stackBox != null) {
                                                final localPosition = stackBox.globalToLocal(details.offset);
                                                // Store center position (add half of text size back)
                                                final centerX = localPosition.dx + textWidth / 2;
                                                final centerY = localPosition.dy + textHeight / 2;
                                                final normalizedX = (centerX / fixedPreviewWidth).clamp(0.0, 1.0);
                                                final normalizedY = (centerY / fixedPreviewHeight).clamp(0.0, 1.0);
              
                                                setState(() {
                                                  layer.positionNormalized = Offset(normalizedX, normalizedY);
                                                });
                                              }
                                            },
                                            child: Container(
                                              decoration: isSelected ? BoxDecoration(
                                                border: Border.all(color: const Color(0xFFFFFF00), width: 2),
                                                borderRadius: BorderRadius.circular(6),
                                              ) : null,
                                              child: _buildTextWidgetForLayer(layer.style),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                                AnimatedBuilder(
                                  animation: _controller.video,
                                  builder: (_, __) => AnimatedOpacity(
                                    opacity: _controller.isPlaying ? 0 : 1,
                                    duration: const Duration(milliseconds: 300),
                    child: GestureDetector(
                      onTap: () {
                                        // Убеждаемся, что воспроизведение начинается с начала обрезанного сегмента
                                        if (_controller.initialized && _controller.video.value.isInitialized) {
                                          final videoDuration = _controller.video.value.duration.inMilliseconds;
                                          final trimStart = _controller.minTrim * videoDuration;
                                          final currentPosition = _controller.video.value.position.inMilliseconds;
                                          
                                          // Если позиция вне обрезанного сегмента, перематываем к началу
                                          if (currentPosition < trimStart || currentPosition >= _controller.maxTrim * videoDuration) {
                                            _controller.video.seekTo(Duration(milliseconds: trimStart.toInt()));
                                          }
                                        }
                                        _controller.video.play();
                      },
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
                          );
                        },
            ),
                      _controlBar(),
                      // Фиксированная высота для области инструментов (не влияет на размер превью)
          Expanded(
            child: _currentMode == EditorMode.trim 
                ? _trimmer()
                : _currentMode == EditorMode.text 
                    ? _textEditor()
                    : const SizedBox.shrink(),
          ),
                    ],
                  ),
                  // Кнопки прикреплены к низу экрана
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _bottomNavBar(),
                  ),
                  if (_exported)
          Container(
                      color: Colors.black.withOpacity(0.85),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Animated circular progress indicator
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: CircularProgressIndicator(
                                  color: const Color(0xFFFFFF00),
                                  strokeWidth: 4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Processing text
                              Text(
                                'Обработка видео...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Subtitle
                              Text(
                                'Применяем эффекты',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                      _deleteSelectedLayer();
                      setState(() {
                        _isDeleteMode = false;
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
              // Check if controller is initialized before switching to text mode
              if (!_controller.initialized) {
                AppNotification.showError(
                  context,
                  'Подождите загрузки видео',
                );
                return;
              }
              setState(() {
                _currentMode = EditorMode.text;
                // If no layers exist, create first one
                if (_textLayers.isEmpty) {
                  _addNewTextLayer();
                } else if (_selectedLayerIndex == null) {
                  // Select first layer if none selected
                  _selectedLayerIndex = 0;
                }
              });
            },
          ),
          const SizedBox(width: 10),
          _buildControlButton(
            _audioFileName ?? "",
            Icons.music_note,
            _selectedAudio != null,
            onTap: _pickAudio,
          ),
          const SizedBox(width: 10),
          // Mute original audio toggle (only visible when audio is selected)
          if (_selectedAudio != null)
            _buildControlButton(
              "",
              _muteOriginalAudio ? Icons.volume_off : Icons.volume_up,
              _muteOriginalAudio,
              onTap: () {
                setState(() => _muteOriginalAudio = !_muteOriginalAudio);
              },
            ),
          if (_selectedAudio != null) const SizedBox(width: 10),
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

  Widget _buildTextWidgetForLayer(TextOverlayStyle style, {bool isDragging = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        style.text,
        style: TextStyle(
          fontSize: 30,
          color: style.textColor,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
          shadows: const [],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // Оценка размера текста для ограничения позиции
  Size _estimateTextSize(TextOverlayStyle style, {double? maxWidth}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: style.text,
        style: TextStyle(
          fontSize: 30,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
        ),
      ),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: maxWidth ?? double.infinity);
    return Size(
      textPainter.width + 24, // + padding
      textPainter.height + 24, // + padding
    );
  }

  Widget _textEditor() {
    // Preset colors for text
    final textColors = [
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.blue,
      const Color(0xFFFFFF00),
      Colors.green,
      Colors.pink,
    ];

    // Preset colors for background (with alpha)
    final backgroundColors = [
      const Color(0x4D000000),
      const Color(0x4DFFFFFF),
      const Color(0x4DFF0000),
      const Color(0x4D0000FF),
      const Color(0x4DFFFF00),
      Colors.transparent,
    ];

    // If no layer selected or no layers exist, show add button
    if (_textLayers.isEmpty || _selectedLayerIndex == null || _selectedLayerIndex! >= _textLayers.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ElevatedButton.icon(
            onPressed: _addNewTextLayer,
            icon: const Icon(Icons.add),
            label: const Text('Добавить текст'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFFF00),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ),
      );
    }

    final currentLayer = _textLayers[_selectedLayerIndex!];
    final currentStyle = currentLayer.style;
    
    // Sync text controller with current layer (only if text differs to preserve cursor)
    if (_textInputController.text != currentStyle.text) {
      _textInputController.text = currentStyle.text;
      _textInputController.selection = TextSelection.collapsed(offset: currentStyle.text.length);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + 80,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Layer management row
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _addNewTextLayer,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Новый'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFFF00),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _deleteSelectedLayer,
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Удалить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          
          // Layer selector (if multiple layers)
          if (_textLayers.length > 1) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _textLayers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final layer = entry.value;
                  final isSelected = _selectedLayerIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedLayerIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFFFFF00) : Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          layer.style.text.characters.length > 10 
                              ? '${layer.style.text.characters.take(10)}...' 
                              : layer.style.text,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          
          // Text input
          TextField(
            controller: _textInputController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Введите текст...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFFFF00)),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            onChanged: (text) {
              // Update layer style without setState to avoid cursor jump
              currentLayer.style = currentStyle.copyWith(text: text);
              // Trigger rebuild for preview update
              setState(() {});
            },
          ),
          const SizedBox(height: 16),

          // Font style buttons
          const Text(
            'Стиль',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactFontButton(
                  label: 'B',
                  isSelected: currentStyle.fontWeight == FontWeight.bold && currentStyle.fontStyle == FontStyle.normal,
                  onTap: () => setState(() {
                    currentLayer.style = currentStyle.copyWith(
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.normal,
                    );
                  }),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactFontButton(
                  label: 'I',
                  isSelected: currentStyle.fontStyle == FontStyle.italic && currentStyle.fontWeight == FontWeight.normal,
                  onTap: () => setState(() {
                    currentLayer.style = currentStyle.copyWith(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.normal,
                    );
                  }),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactFontButton(
                  label: 'Aa',
                  isSelected: currentStyle.fontWeight == FontWeight.normal && currentStyle.fontStyle == FontStyle.normal,
                  onTap: () => setState(() {
                    currentLayer.style = currentStyle.copyWith(
                      fontWeight: FontWeight.normal,
                      fontStyle: FontStyle.normal,
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Text color
          const Text(
            'Цвет текста',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: textColors.map((color) {
              return _buildCompactColorButton(
                color: color,
                isSelected: currentStyle.textColor == color,
                onTap: () => setState(() {
                  currentLayer.style = currentStyle.copyWith(textColor: color);
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Background color
          const Text(
            'Цвет фона',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: backgroundColors.map((color) {
              return _buildCompactColorButton(
                color: color,
                isSelected: currentStyle.backgroundColor == color,
                onTap: () => setState(() {
                  currentLayer.style = currentStyle.copyWith(backgroundColor: color);
                }),
                showTransparentPattern: color == Colors.transparent,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFontButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFFF00) : Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontSize: 16,
              fontWeight: fontWeight ?? FontWeight.normal,
              fontStyle: fontStyle ?? FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactColorButton({
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    bool showTransparentPattern = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: showTransparentPattern ? Colors.grey[800] : color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFFF00) : Colors.white.withOpacity(0.3),
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: showTransparentPattern
            ? Stack(
                children: [
                  CustomPaint(
                    size: const Size(40, 40),
                    painter: _CheckerboardPainter(),
                  ),
                  const Center(
                    child: Icon(
                      Icons.block,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              )
            : isSelected
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 20,
                  )
                : null,
      ),
    );
  }
                          
  Widget _trimmer() {
    // Используем миллисекунды для точности (как в _handleVideoPosition и превью)
    final videoDurationMs = _controller.video.value.duration.inMilliseconds;
    final videoDuration = videoDurationMs / 1000.0; // Конвертируем в секунды для совместимости
    // Вычисляем границы обрезанного сегмента
    final trimStart = _controller.minTrim * videoDuration;
    final trimEnd = _controller.maxTrim * videoDuration;
    final trimDuration = trimEnd - trimStart;
    
    return Expanded(
      child: Column(
        children: [
          // TrimSlider - fixed at top, always visible
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TrimSlider(
                    key: _trimmerKey,
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
          // Scrollable area for text and audio tracks
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Text tracks (show all text layers)
                  ..._textLayers.asMap().entries.map((entry) {
          final layerIndex = entry.key;
          final layer = entry.value;
          final isSelected = _selectedLayerIndex == layerIndex;
          
          return Padding(
            padding: EdgeInsets.only(
              left: 16, 
              right: 16, 
              top: layerIndex == 0 ? 10 : 0, // Top margin for first track
              bottom: 8,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth + 32;

                double trimmedSegmentWidth;
                try {
                  final trimmerContext = _trimmerKey.currentContext;
                  if (trimmerContext != null) {
                    final trimmerBox = trimmerContext.findRenderObject() as RenderBox?;
                    if (trimmerBox != null) {
                      final measuredWidth = trimmerBox.size.width - 24;
                      trimmedSegmentWidth = measuredWidth.clamp(0.0, totalWidth);
                    } else {
                      trimmedSegmentWidth = totalWidth - 28;
                    }
                  } else {
                    trimmedSegmentWidth = totalWidth - 28;
                  }
                } catch (e) {
                  trimmedSegmentWidth = totalWidth - 28;
                }

                // Use layer times directly (they are already in absolute video time)
                final layerStart = layer.startTime.clamp(trimStart, trimEnd);
                final layerEnd = layer.endTime.clamp(layerStart, trimEnd);

                // Calculate position on trackbar relative to trim segment
                final startPosition = ((layerStart - trimStart) / trimDuration) * trimmedSegmentWidth;
                final endPosition = ((layerEnd - trimStart) / trimDuration) * trimmedSegmentWidth;
                final trackWidth = (endPosition - startPosition).clamp(40.0, trimmedSegmentWidth);
    
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedLayerIndex = layerIndex;
                      _currentMode = EditorMode.text;
                    });
                  },
                  onLongPress: () {
                    setState(() {
                      _selectedLayerIndex = layerIndex;
                      _isDeleteMode = true;
                    });
                  },
                  child: Container(
                    height: 50,
                    color: Colors.transparent,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 12,
                          child: Container(
                            width: trimmedSegmentWidth,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12 + startPosition.clamp(0.0, trimmedSegmentWidth),
                          child: GestureDetector(
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                final delta = details.delta.dx / trimmedSegmentWidth * trimDuration;
                                final newStart = (layer.startTime + delta).clamp(trimStart, trimEnd - 0.5);
                                final newEnd = (layer.endTime + delta).clamp(trimStart + 0.5, trimEnd);
                                final currentDuration = layer.endTime - layer.startTime;
                                const minDuration = 0.5;

                                if (newStart >= trimStart && newEnd <= trimEnd && newEnd - newStart >= minDuration) {
                                  layer.startTime = newStart;
                                  layer.endTime = newStart + currentDuration;
                                  if (layer.endTime > trimEnd) {
                                    layer.endTime = trimEnd;
                                    layer.startTime = layer.endTime - currentDuration;
                                  }
                                  if (layer.endTime - layer.startTime < minDuration) {
                                    layer.endTime = layer.startTime + minDuration;
                                  }
                                }
                              });
                            },
                            child: Container(
                              width: trackWidth.clamp(60.0, trimmedSegmentWidth),
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFFFFF00) : const Color(0xFFFFFF00).withOpacity(0.6),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Left handle
                                  GestureDetector(
                                    onHorizontalDragUpdate: (details) {
                                      setState(() {
                                        final delta = details.delta.dx / trimmedSegmentWidth * trimDuration;
                                        final newStart = (layer.startTime + delta).clamp(trimStart, layer.endTime - 0.5);
                                        if (layer.endTime - newStart >= 0.5) {
                                          layer.startTime = newStart;
                                        } else {
                                          layer.startTime = layer.endTime - 0.5;
                                        }
                                      });
                                    },
                                    child: Container(
                                      width: 12,
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(6),
                                          bottomLeft: Radius.circular(6),
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.drag_handle, color: Colors.black, size: 10),
                                      ),
                                    ),
                                  ),
                                  // Center content
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.text_fields, color: Colors.black, size: 14),
                                          const SizedBox(width: 4),
                                          if (trackWidth > 100)
                                            Flexible(
                                              child: Text(
                                                layer.style.text.characters.length > 6 ? '${layer.style.text.characters.take(6)}...' : layer.style.text,
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                                overflow: TextOverflow.ellipsis,
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
                                        final delta = details.delta.dx / trimmedSegmentWidth * trimDuration;
                                        final newEnd = (layer.endTime + delta).clamp(layer.startTime + 0.5, trimEnd);
                                        if (newEnd - layer.startTime >= 0.5) {
                                          layer.endTime = newEnd;
                                        } else {
                                          layer.endTime = layer.startTime + 0.5;
                                        }
                                      });
                                    },
                                    child: Container(
                                      width: 12,
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(6),
                                          bottomRight: Radius.circular(6),
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.drag_handle, color: Colors.black, size: 10),
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
          );
        }),
        
        // Audio track (only show if audio is selected)
        if (_selectedAudio != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth + 32;
                double trimmedSegmentWidth;
                
                try {
                  final trimmerContext = _trimmerKey.currentContext;
                  if (trimmerContext != null) {
                    final trimmerBox = trimmerContext.findRenderObject() as RenderBox?;
                    if (trimmerBox != null) {
                      trimmedSegmentWidth = (trimmerBox.size.width - 24).clamp(0.0, totalWidth);
                    } else {
                      trimmedSegmentWidth = totalWidth - 28;
                    }
                  } else {
                    trimmedSegmentWidth = totalWidth - 28;
                  }
                } catch (e) {
                  trimmedSegmentWidth = totalWidth - 28;
                }

                final audioDurationInSegment = (_audioEndTime - _audioStartTime).clamp(0.0, trimDuration);
                final startPosition = ((_audioStartTime - trimStart) / trimDuration * trimmedSegmentWidth).clamp(0.0, trimmedSegmentWidth);
                final trackWidth = (audioDurationInSegment / trimDuration * trimmedSegmentWidth).clamp(60.0, trimmedSegmentWidth);

                return GestureDetector(
                  onLongPress: () {
                    setState(() {
                      _selectedAudio = null;
                      _audioFileName = null;
                      _audioDuration = 0.0;
                      _audioStartTime = 0.0;
                      _audioEndTime = 0.0;
                      _muteOriginalAudio = false;
                    });
                  },
                  child: Container(
                    height: 60,
                    color: Colors.transparent,
                    child: Stack(
                      children: [
                        // Background
                        Positioned(
                          left: 12,
                          child: Container(
                            width: trimmedSegmentWidth,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        // Audio track
                        Positioned(
                          left: 12 + startPosition.clamp(0.0, trimmedSegmentWidth),
                          child: GestureDetector(
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                final delta = details.delta.dx / trimmedSegmentWidth * trimDuration;
                                final newStart = (_audioStartTime + delta).clamp(trimStart, trimEnd - 0.5);
                                final newEnd = (_audioEndTime + delta).clamp(trimStart + 0.5, trimEnd);

                                final currentDuration = _audioEndTime - _audioStartTime;
                                final minDuration = 0.5;

                                if (newStart >= trimStart && newEnd <= trimEnd && newEnd - newStart >= minDuration) {
                                  _audioStartTime = newStart;
                                  _audioEndTime = newStart + currentDuration;
                                  if (_audioEndTime > trimEnd) {
                                    _audioEndTime = trimEnd;
                                    _audioStartTime = _audioEndTime - currentDuration;
                                  }
                                  if (_audioEndTime - _audioStartTime < minDuration) {
                                    _audioEndTime = _audioStartTime + minDuration;
                                  }
                                }
                              });
                            },
                            child: Container(
                              width: trackWidth.clamp(60.0, trimmedSegmentWidth),
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF9C27B0), // Purple for audio
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Row(
                                children: [
                                  // Left handle
                                  GestureDetector(
                                    onHorizontalDragUpdate: (details) {
                                      setState(() {
                                        final delta = details.delta.dx / trimmedSegmentWidth * trimDuration;
                                        final newStart = (_audioStartTime + delta).clamp(trimStart, _audioEndTime - 0.5);
                                        if (_audioEndTime - newStart >= 0.5) {
                                          _audioStartTime = newStart;
                                        } else {
                                          _audioStartTime = _audioEndTime - 0.5;
                                        }
                                      });
                                    },
                                    child: Container(
                                      width: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.only(
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
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.music_note, color: Colors.white, size: 16),
                                          const SizedBox(width: 4),
                                          if (_audioFileName != null && trackWidth > 120)
                                            Flexible(
                                              child: Text(
                                                _audioFileName!.length > 8 
                                                    ? '${_audioFileName!.substring(0, 8)}...' 
                                                    : _audioFileName!,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
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
                                        final delta = details.delta.dx / trimmedSegmentWidth * trimDuration;
                                        final newEnd = (_audioEndTime + delta).clamp(_audioStartTime + 0.5, trimEnd);
                                        if (newEnd - _audioStartTime >= 0.5) {
                                          _audioEndTime = newEnd;
                                        } else {
                                          _audioEndTime = _audioStartTime + 0.5;
                                        }
                                      });
                                    },
                                    child: Container(
                                      width: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.only(
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
        ],
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNavBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text("Назад", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _exportVideo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                child: const Text("Сохранить", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
        ),
      ),
    );
  }
}

// Text Style Editor Bottom Sheet
class _TextStyleEditorSheet extends StatefulWidget {
  final TextOverlayStyle? initialStyle;
  final Function(TextOverlayStyle) onSave;

  const _TextStyleEditorSheet({
    required this.initialStyle,
    required this.onSave,
  });

  @override
  State<_TextStyleEditorSheet> createState() => _TextStyleEditorSheetState();
}

class _TextStyleEditorSheetState extends State<_TextStyleEditorSheet> {
  late TextEditingController _textController;
  late FontWeight _fontWeight;
  late FontStyle _fontStyle;
  late Color _textColor;
  late Color _backgroundColor;

  // Preset colors for text
  final List<Color> _textColors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.blue,
    const Color(0xFFFFFF00), // Yellow
    Colors.green,
    Colors.pink,
  ];

  // Preset colors for background (with alpha)
  final List<Color> _backgroundColors = [
    const Color(0x4D000000), // black@0.3
    const Color(0x4DFFFFFF), // white@0.3
    const Color(0x4DFF0000), // red@0.3
    const Color(0x4D0000FF), // blue@0.3
    const Color(0x4DFFFF00), // yellow@0.3
    Colors.transparent,
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialStyle?.text ?? '');
    _fontWeight = widget.initialStyle?.fontWeight ?? FontWeight.bold;
    _fontStyle = widget.initialStyle?.fontStyle ?? FontStyle.normal;
    _textColor = widget.initialStyle?.textColor ?? Colors.white;
    _backgroundColor = widget.initialStyle?.backgroundColor ?? const Color(0x4D000000);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Редактировать текст',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Text input
              TextField(
                controller: _textController,
                autofocus: true,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Введите текст...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFFFF00)),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),

              // Preview
              const Text(
                'Превью',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _backgroundColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _textController.text.isEmpty ? 'Текст' : _textController.text,
                    style: TextStyle(
                      fontSize: 30,
                      color: _textColor,
                      fontWeight: _fontWeight,
                      fontStyle: _fontStyle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Font style buttons
              const Text(
                'Стиль шрифта',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildFontStyleButton(
                      label: 'B',
                      isSelected: _fontWeight == FontWeight.bold && _fontStyle == FontStyle.normal,
                      onTap: () => setState(() {
                        _fontWeight = FontWeight.bold;
                        _fontStyle = FontStyle.normal;
                      }),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFontStyleButton(
                      label: 'I',
                      isSelected: _fontStyle == FontStyle.italic && _fontWeight == FontWeight.normal,
                      onTap: () => setState(() {
                        _fontStyle = FontStyle.italic;
                        _fontWeight = FontWeight.normal;
                      }),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFontStyleButton(
                      label: 'Regular',
                      isSelected: _fontWeight == FontWeight.normal && _fontStyle == FontStyle.normal,
                      onTap: () => setState(() {
                        _fontWeight = FontWeight.normal;
                        _fontStyle = FontStyle.normal;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Text color
              const Text(
                'Цвет текста',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _textColors.map((color) {
                  return _buildColorButton(
                    color: color,
                    isSelected: _textColor == color,
                    onTap: () => setState(() => _textColor = color),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Background color
              const Text(
                'Цвет фона',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _backgroundColors.map((color) {
                  return _buildColorButton(
                    color: color,
                    isSelected: _backgroundColor == color,
                    onTap: () => setState(() => _backgroundColor = color),
                    showTransparentPattern: color == Colors.transparent,
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _textController.text.isEmpty
                      ? null
                      : () {
                          widget.onSave(TextOverlayStyle(
                            text: _textController.text,
                            fontWeight: _fontWeight,
                            fontStyle: _fontStyle,
                            textColor: _textColor,
                            backgroundColor: _backgroundColor,
                          ));
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFFF00),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Сохранить',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFontStyleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFFF00) : Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFFF00) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontSize: 18,
              fontWeight: fontWeight ?? FontWeight.normal,
              fontStyle: fontStyle ?? FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorButton({
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    bool showTransparentPattern = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: showTransparentPattern ? Colors.grey[800] : color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFFF00) : Colors.white.withOpacity(0.3),
            width: isSelected ? 3 : 1,
          ),
        ),
        child: showTransparentPattern
            ? Stack(
                children: [
                  // Checkerboard pattern for transparent
                  CustomPaint(
                    size: const Size(48, 48),
                    painter: _CheckerboardPainter(),
                  ),
                  const Center(
                    child: Icon(
                      Icons.block,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              )
            : isSelected
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 24,
                  )
                : null,
      ),
    );
  }
}

// Checkerboard painter for transparent color preview
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const squareSize = 8.0;
    final paint1 = Paint()..color = Colors.grey[700]!;
    final paint2 = Paint()..color = Colors.grey[600]!;

    for (var i = 0; i < size.width / squareSize; i++) {
      for (var j = 0; j < size.height / squareSize; j++) {
        final paint = (i + j) % 2 == 0 ? paint1 : paint2;
        canvas.drawRect(
          Rect.fromLTWH(i * squareSize, j * squareSize, squareSize, squareSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
