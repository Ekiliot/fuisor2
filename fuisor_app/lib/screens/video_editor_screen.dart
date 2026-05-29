import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  double scale;
  double rotation;

  TextLayer({
    required this.style,
    this.positionNormalized = const Offset(0.5, 0.5),
    this.startTime = 0.0,
    this.endTime = 3.0,
    this.scale = 1.0,
    this.rotation = 0.0,
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
  double _exportProgress = 0.0;
  EditorMode _currentMode = EditorMode.trim;
  
  // Text overlay state - multiple layers support
  List<TextLayer> _textLayers = [];
  int? _selectedLayerIndex; // Currently selected layer for editing
  bool _isDeleteMode = false; // Track if delete mode is active

  // History state for undo/redo
  List<List<TextLayer>> _history = [];
  int _historyIndex = -1;
  
  void _saveToHistory() {
    final copy = _textLayers.map((e) => TextLayer(
      style: e.style.copyWith(),
      positionNormalized: e.positionNormalized,
      startTime: e.startTime,
      endTime: e.endTime,
      scale: e.scale,
      rotation: e.rotation,
    )).toList();
    
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    
    _history.add(copy);
    _historyIndex = _history.length - 1;
    
    if (_history.length > 30) {
      _history.removeAt(0);
      _historyIndex--;
    }
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        final previousState = _history[_historyIndex];
        _textLayers = previousState.map((e) => TextLayer(
          style: e.style.copyWith(),
          positionNormalized: e.positionNormalized,
          startTime: e.startTime,
          endTime: e.endTime,
          scale: e.scale,
          rotation: e.rotation,
        )).toList();
        if (_selectedLayerIndex != null && _selectedLayerIndex! >= _textLayers.length) {
          _selectedLayerIndex = null;
          _currentMode = EditorMode.trim;
        }
      });
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        final nextState = _history[_historyIndex];
        _textLayers = nextState.map((e) => TextLayer(
          style: e.style.copyWith(),
          positionNormalized: e.positionNormalized,
          startTime: e.startTime,
          endTime: e.endTime,
          scale: e.scale,
          rotation: e.rotation,
        )).toList();
      });
    }
  }
  
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
  
  // Gesture tracking
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  bool _snappedX = false;
  bool _snappedY = false;
  
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
        
        _saveToHistory();
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
        
    setState(() {
      _exported = true;
      _exportProgress = 0.0;
    });
    
    await _controller.video.pause();

    final start = _controller.minTrim * _controller.video.value.duration.inMilliseconds;
    final end = _controller.maxTrim * _controller.video.value.duration.inMilliseconds;
    final duration = end - start;

    // Используем временную директорию вместо диалога сохранения
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Получаем размеры видео
    final videoSize = _controller.video.value.size;
    final videoWidth = (videoSize.width.round() / 2).floor() * 2;
    final videoHeight = (videoSize.height.round() / 2).floor() * 2;

    // Подготавливаем параметры текста (перевод в картинки)
    List<ImageOverlay> imageOverlays = [];
    if (_textLayers.isNotEmpty && _previewSize != null) {
      final scale = videoWidth / _previewSize!.width;
      final videoDuration = _controller.video.value.duration.inMilliseconds / 1000.0;
      final trimStart = _controller.minTrim * videoDuration;
      final trimEnd = _controller.maxTrim * videoDuration;
      
      for (int i = 0; i < _textLayers.length; i++) {
        final layer = _textLayers[i];
        if (layer.style.text.isEmpty) continue;
        
        final clampedTextStart = layer.startTime.clamp(trimStart, trimEnd);
        final clampedTextEnd = layer.endTime.clamp(trimStart, trimEnd);
        
        final textStartRelative = clampedTextStart - trimStart;
        final textEndRelative = clampedTextEnd - trimStart;
        
        // Render text to PNG image
        final imagePath = await _renderTextLayerToImage(layer, scale, videoWidth * 0.8);
        
        // Measure the resulting image bounds
        final imgFile = File(imagePath);
        final decodedImage = await decodeImageFromList(await imgFile.readAsBytes());
        final textWidth = decodedImage.width.toDouble();
        final textHeight = decodedImage.height.toDouble();
        
        final centerX = layer.positionNormalized.dx * videoWidth;
        final centerY = layer.positionNormalized.dy * videoHeight;
        
        final maxLeft = (videoWidth - textWidth) > 0 ? videoWidth - textWidth : 0.0;
        final maxTop = (videoHeight - textHeight) > 0 ? videoHeight - textHeight : 0.0;
        
        final clampedX = (centerX - textWidth / 2).clamp(0.0, maxLeft);
        final clampedY = (centerY - textHeight / 2).clamp(0.0, maxTop);
        
        imageOverlays.add(ImageOverlay(
          imagePath: imagePath,
          x: clampedX,
          y: clampedY,
          startTime: textStartRelative,
          endTime: textEndRelative,
        ));
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
      imageOverlays: imageOverlays.isNotEmpty ? imageOverlays : null,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      audioPath: audioPath,
      audioStartTime: audioStartTime,
      audioEndTime: audioEndTime,
      muteOriginalAudio: _muteOriginalAudio,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _exportProgress = progress;
          });
        }
      },
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
            'Error: exported file is corrupted',
          );
        }
      }
    } else {
      print('VideoEditorScreen: Export failed - path is null');
      if (mounted) {
        AppNotification.showError(
          context,
          'Error saving video',
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
      style: const TextOverlayStyle(text: "Text"),
      positionNormalized: const Offset(0.5, 0.5),
      startTime: startTime,
      endTime: endTime,
      scale: 1.0,
      rotation: 0.0,
    );

    setState(() {
      _textLayers.add(newLayer);
      _selectedLayerIndex = _textLayers.length - 1;
    });
    _saveToHistory();
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
    _saveToHistory();
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
              title: const Text('From Gallery', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                await _pickAudioFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_music, color: Colors.white),
              title: const Text('From Library', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                AppNotification.showInfo(
                  context,
                  'Coming Soon',
                );
              },
            ),
            if (_selectedAudio != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Audio', style: TextStyle(color: Colors.red)),
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
              'Could not determine audio file duration',
            );
          }
          return;
        }

        // Get video trim info for default audio timing
        if (!_controller.initialized) {
          if (mounted) {
            AppNotification.showError(
              context,
              'Please wait for video to load',
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
          'Error selecting audio: $e',
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
                                  
                                  // Convert to top-left position, clamped to bounds safely
                                  final maxLeft = (fixedPreviewWidth - textWidth) > 0 ? fixedPreviewWidth - textWidth : 0.0;
                                  final maxTop = (fixedPreviewHeight - textHeight) > 0 ? fixedPreviewHeight - textHeight : 0.0;
                                  final leftPos = (centerX - textWidth / 2).clamp(0.0, maxLeft);
                                  final topPos = (centerY - textHeight / 2).clamp(0.0, maxTop);
                                  
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
                                          onDoubleTap: () {
                                            setState(() {
                                              _selectedLayerIndex = index;
                                              _currentMode = EditorMode.text;
                                            });
                                          },
                                          onTap: () {
                                            setState(() {
                                              _selectedLayerIndex = index;
                                            });
                                          },
                                          onScaleStart: (details) {
                                            setState(() {
                                              _selectedLayerIndex = index;
                                              _baseScale = layer.scale;
                                              _baseRotation = layer.rotation;
                                              _snappedX = false;
                                              _snappedY = false;
                                            });
                                          },
                                          onScaleUpdate: (details) {
                                            double newScale = (_baseScale * details.scale).clamp(0.5, 5.0);
                                            double newRotation = _baseRotation + details.rotation;
                                            
                                            double dx = details.focalPointDelta.dx / fixedPreviewWidth;
                                            double dy = details.focalPointDelta.dy / fixedPreviewHeight;
                                            
                                            double newX = layer.positionNormalized.dx + dx;
                                            double newY = layer.positionNormalized.dy + dy;
                                            
                                            bool snapX = false;
                                            bool snapY = false;
                                            
                                            if ((newX - 0.5).abs() < 0.03) {
                                              newX = 0.5;
                                              snapX = true;
                                            }
                                            if ((newY - 0.5).abs() < 0.03) {
                                              newY = 0.5;
                                              snapY = true;
                                            }
                                            
                                            if (snapX && !_snappedX) {
                                              HapticFeedback.lightImpact();
                                              _snappedX = true;
                                            } else if (!snapX) {
                                              _snappedX = false;
                                            }
                                            
                                            if (snapY && !_snappedY) {
                                              HapticFeedback.lightImpact();
                                              _snappedY = true;
                                            } else if (!snapY) {
                                              _snappedY = false;
                                            }
                                            
                                            setState(() {
                                              layer.scale = newScale;
                                              layer.rotation = newRotation;
                                              layer.positionNormalized = Offset(newX.clamp(0.0, 1.0), newY.clamp(0.0, 1.0));
                                            });
                                          },
                                          onScaleEnd: (details) {
                                            _saveToHistory();
                                          },
                                          child: Transform.rotate(
                                            angle: layer.rotation,
                                            child: Transform.scale(
                                              scale: layer.scale,
                                              child: Container(
                                                decoration: isSelected ? BoxDecoration(
                                                  border: Border.all(color: const Color(0xFFFFFF00), width: 2 / layer.scale),
                                                  borderRadius: BorderRadius.circular(6),
                                                ) : null,
                                                child: ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                    maxWidth: fixedPreviewWidth * 0.8,
                                                  ),
                                                  child: _buildTextWidgetForLayer(layer.style),
                                                ),
                                              ),
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
                      // Stable height for tools panel with smooth transitions
                      SizedBox(
                        height: 190,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeInOut,
                          switchOutCurve: Curves.easeInOut,
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.08),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _currentMode == EditorMode.trim 
                              ? _trimmer()
                              : _currentMode == EditorMode.text 
                                  ? _textEditor()
                                  : const SizedBox.shrink(),
                        ),
                      ),
                      _bottomNavBar(),
                    ],
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
                              // Animated circular progress indicator with percentage
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 80,
                                      height: 80,
                                      child: CircularProgressIndicator(
                                        value: _exportProgress > 0 ? _exportProgress : null,
                                        color: const Color(0xFFFFFF00),
                                        strokeWidth: 4,
                                      ),
                                    ),
                                    if (_exportProgress > 0)
                                      Text(
                                        '${(_exportProgress * 100).toInt()}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Processing text
                              Text(
                                'Processing video...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Subtitle
                              Text(
                                'Applying effects',
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
              label: const Text("Delete text", style: TextStyle(fontWeight: FontWeight.bold)),
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
              child: const Text("Cancel", style: TextStyle(color: Colors.white)),
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
            _currentMode == EditorMode.trim ? "Trim" : "",
            Icons.cut,
            _currentMode == EditorMode.trim,
            onTap: () => setState(() => _currentMode = EditorMode.trim),
          ),
          const SizedBox(width: 10),
          _buildControlButton(
            _currentMode == EditorMode.text ? "Text" : "",
            Icons.text_fields,
            _currentMode == EditorMode.text,
            onTap: () {
              // Check if controller is initialized before switching to text mode
              if (!_controller.initialized) {
                AppNotification.showError(
                  context,
                  'Please wait for video to load',
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
          IconButton(
            icon: Icon(Icons.undo, color: _historyIndex > 0 ? Colors.white : Colors.white30),
            onPressed: _historyIndex > 0 ? _undo : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 15),
          IconButton(
            icon: Icon(Icons.redo, color: _historyIndex < _history.length - 1 ? Colors.white : Colors.white30),
            onPressed: _historyIndex < _history.length - 1 ? _redo : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(String text, IconData icon, bool isActive, {VoidCallback? onTap}) {
    final foregroundColor = isActive ? Colors.black : Colors.white70;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isActive ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFFFFF00) : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
              width: 1,
            ),
            boxShadow: isActive ? [
              BoxShadow(
                color: const Color(0xFFFFFF00).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ] : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foregroundColor, size: 20),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (text.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: foregroundColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        child: Text(text),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
        textAlign: TextAlign.center,
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

  Future<String> _renderTextLayerToImage(TextLayer layer, double scale, double maxWidth) async {
    final textStyle = layer.style;
    final textSpan = TextSpan(
      text: textStyle.text,
      style: TextStyle(
        fontSize: 30 * scale,
        color: textStyle.textColor,
        fontWeight: textStyle.fontWeight,
        fontStyle: textStyle.fontStyle,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      textAlign: TextAlign.center,
    );
    textPainter.layout(maxWidth: maxWidth);

    final padding = 12.0 * scale;
    final borderRadius = 4.0 * scale;
    
    final originalWidth = textPainter.width + padding * 2;
    final originalHeight = textPainter.height + padding * 2;

    final double maxDim = math.sqrt(originalWidth * originalWidth + originalHeight * originalHeight) * layer.scale;
    final int width = maxDim.ceil();
    final int height = maxDim.ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.translate(width / 2, height / 2);
    canvas.rotate(layer.rotation);
    canvas.scale(layer.scale);
    canvas.translate(-originalWidth / 2, -originalHeight / 2);

    final bgPaint = Paint()..color = textStyle.backgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, originalWidth, originalHeight), Radius.circular(borderRadius)),
      bgPaint,
    );

    textPainter.paint(canvas, Offset(padding, padding));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/text_layer_${DateTime.now().millisecondsSinceEpoch}_${layer.hashCode}.png');
    await file.writeAsBytes(buffer);
    
    return file.path;
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
        key: const ValueKey('addText'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ElevatedButton.icon(
            onPressed: _addNewTextLayer,
            icon: const Icon(Icons.add),
            label: const Text('Add Text'),
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
      key: const ValueKey('textEditor'),
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12,
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
                  label: const Text('New'),
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
                label: const Text('Delete'),
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
              hintText: 'Enter text...',
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
            'Style',
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
            'Text Color',
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
            'Background Color',
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
    
    return Column(
      key: const ValueKey('trimmer'),
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

                // Calculate position on trackbar relative to full video duration to sync with TrimSlider
                final startPosition = (layerStart / videoDuration) * trimmedSegmentWidth;
                final endPosition = (layerEnd / videoDuration) * trimmedSegmentWidth;
                final trackWidth = (endPosition - startPosition).clamp(24.0, trimmedSegmentWidth);
    
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
                            onHorizontalDragEnd: (_) => _saveToHistory(),
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                final delta = details.delta.dx / trimmedSegmentWidth * videoDuration;
                                final newStart = (layer.startTime + delta).clamp(trimStart, trimEnd - ((24.0 / trimmedSegmentWidth) * videoDuration).clamp(0.1, 5.0));
                                final newEnd = (layer.endTime + delta).clamp(trimStart + ((24.0 / trimmedSegmentWidth) * videoDuration).clamp(0.1, 5.0), trimEnd);
                                final currentDuration = layer.endTime - layer.startTime;
                                final minDuration = ((24.0 / trimmedSegmentWidth) * videoDuration).clamp(0.1, 5.0);

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
                              width: trackWidth.clamp(24.0, trimmedSegmentWidth),
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
                                    onHorizontalDragEnd: (_) => _saveToHistory(),
                                    onHorizontalDragUpdate: (details) {
                                      setState(() {
                                        final delta = details.delta.dx / trimmedSegmentWidth * videoDuration;
                                        final minDuration = ((24.0 / trimmedSegmentWidth) * videoDuration).clamp(0.1, 5.0);
                                        final newStart = (layer.startTime + delta).clamp(trimStart, layer.endTime - minDuration);
                                        if (layer.endTime - newStart >= minDuration) {
                                          layer.startTime = newStart;
                                        } else {
                                          layer.startTime = layer.endTime - minDuration;
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
                                    onHorizontalDragEnd: (_) => _saveToHistory(),
                                    onHorizontalDragUpdate: (details) {
                                      setState(() {
                                        final delta = details.delta.dx / trimmedSegmentWidth * videoDuration;
                                        final minDuration = ((24.0 / trimmedSegmentWidth) * videoDuration).clamp(0.1, 5.0);
                                        final newEnd = (layer.endTime + delta).clamp(layer.startTime + minDuration, trimEnd);
                                        if (newEnd - layer.startTime >= minDuration) {
                                          layer.endTime = newEnd;
                                        } else {
                                          layer.endTime = layer.startTime + minDuration;
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
                final trackWidth = (audioDurationInSegment / trimDuration * trimmedSegmentWidth).clamp(24.0, trimmedSegmentWidth);

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
                                final delta = details.delta.dx / trimmedSegmentWidth * videoDuration;
                                final minDuration = ((24.0 / trimmedSegmentWidth) * videoDuration).clamp(0.1, 5.0);
                                final newStart = (_audioStartTime + delta).clamp(trimStart, trimEnd - minDuration);
                                final newEnd = (_audioEndTime + delta).clamp(trimStart + minDuration, trimEnd);

                                final currentDuration = _audioEndTime - _audioStartTime;

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
                              width: trackWidth.clamp(24.0, trimmedSegmentWidth),
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
                                        final delta = details.delta.dx / trimmedSegmentWidth * videoDuration;
                                        final minDuration = ((24.0 / trimmedSegmentWidth) * videoDuration).clamp(0.1, 5.0);
                                        final newStart = (_audioStartTime + delta).clamp(trimStart, _audioEndTime - minDuration);
                                        if (_audioEndTime - newStart >= minDuration) {
                                          _audioStartTime = newStart;
                                        } else {
                                          _audioStartTime = _audioEndTime - minDuration;
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
                                        final delta = details.delta.dx / trimmedSegmentWidth * videoDuration;
                                        final minDuration = ((24.0 / trimmedSegmentWidth) * videoDuration).clamp(0.1, 5.0);
                                        final newEnd = (_audioEndTime + delta).clamp(_audioStartTime + minDuration, trimEnd);
                                        if (newEnd - _audioStartTime >= minDuration) {
                                          _audioEndTime = newEnd;
                                        } else {
                                          _audioEndTime = _audioStartTime + minDuration;
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
                child: const Text("Back", style: TextStyle(fontWeight: FontWeight.bold)),
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
                child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
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
                    'Edit text',
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
                  hintText: 'Enter text...',
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
                'Preview',
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
                    _textController.text.isEmpty ? 'Text' : _textController.text,
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
                'Font Style',
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
                'Text Color',
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
                'Background Color',
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
                    'Save',
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
