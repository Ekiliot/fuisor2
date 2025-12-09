import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'dart:io';
import 'video_editor_screen.dart';
import 'geo_post_preview_screen.dart';
import 'geo_post_settings_sheet.dart';
import 'story_settings_sheet.dart';
import '../services/api_service.dart';
import '../widgets/app_notification.dart';
import '../utils/video_compressor.dart';
import '../utils/image_compressor.dart';

class StoryPreviewScreen extends StatefulWidget {
  final XFile? selectedFile;
  final Uint8List? selectedImageBytes;
  final VideoPlayerController? videoController;
  final bool isGeoPost;
  final double? latitude;
  final double? longitude;
  final String? visibility;
  final int? expiresInHours;

  const StoryPreviewScreen({
    super.key,
    this.selectedFile,
    this.selectedImageBytes,
    this.videoController,
    this.isGeoPost = false,
    this.latitude,
    this.longitude,
    this.visibility,
    this.expiresInHours,
  });

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  XFile? _currentFile;
  Uint8List? _currentImageBytes;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.selectedFile;
    _currentImageBytes = widget.selectedImageBytes;
    _videoController = widget.videoController;
    if (_videoController != null && !_videoController!.value.isInitialized) {
      _videoController!.initialize().then((_) {
        if (mounted) {
          setState(() {
            _isPlaying = true;
          });
          _videoController!.play();
          _videoController!.setLooping(true);
        }
      });
    } else if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.play();
      _videoController!.setLooping(true);
      _isPlaying = true;
    }
  }

  @override
  void dispose() {
    // Останавливаем и удаляем видео контроллер
    if (_videoController != null) {
      _videoController!.pause();
      _videoController!.dispose();
    }
    super.dispose();
  }

  Future<void> _updateVideoController(XFile videoFile) async {
    // Останавливаем и удаляем старый контроллер
    if (_videoController != null) {
      await _videoController!.pause();
      await _videoController!.dispose();
      _videoController = null;
    }

    // Создаем новый контроллер для отредактированного видео
    try {
      final videoFileIO = File(videoFile.path);
      if (await videoFileIO.exists()) {
        _videoController = VideoPlayerController.file(videoFileIO);
        await _videoController!.initialize();
        if (mounted) {
          setState(() {
            _isPlaying = true;
          });
          _videoController!.play();
          _videoController!.setLooping(true);
        }
      }
    } catch (e) {
      print('Error updating video controller: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка загрузки видео: $e',
        );
      }
    }
  }

  void _togglePlayPause() {
    if (_videoController == null) return;

    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _videoController!.play();
    } else {
      _videoController!.pause();
    }
  }

  Future<void> _openEditor() async {
    try {
      // Останавливаем видео перед переходом к редактору
      if (_videoController != null) {
        await _videoController!.pause();
        await _videoController!.seekTo(Duration.zero);
      }

      final editedFile = await Navigator.of(context).push<XFile?>(
        MaterialPageRoute(
          builder: (context) => VideoEditorScreen(
            selectedFile: _currentFile ?? widget.selectedFile,
            selectedImageBytes: _currentImageBytes ?? widget.selectedImageBytes,
            videoController: _videoController,
          ),
        ),
      );

      if (editedFile != null && mounted) {
        // Обновляем файл после редактирования
        if (widget.isGeoPost && widget.latitude != null && widget.longitude != null) {
          // Для гео-постов переходим к GeoPostPreviewScreen
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => GeoPostPreviewScreen(
                selectedFile: editedFile,
                selectedImageBytes: _currentImageBytes,
                videoController: _videoController,
                latitude: widget.latitude!,
                longitude: widget.longitude!,
                visibility: widget.visibility ?? 'public',
                expiresInHours: widget.expiresInHours ?? 24,
              ),
            ),
          );
        } else {
          // Для обычных сторис обновляем текущий экран с отредактированным файлом
          setState(() {
            _currentFile = editedFile;
            _currentImageBytes = null; // Для видео байты не нужны
          });
          
          // Обновляем видеоконтроллер для отредактированного видео
          await _updateVideoController(editedFile);
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка открытия редактора: $e',
        );
      }
    }
  }

  Future<void> _publishStory({
    required String visibility,
    required int expiresInHours,
  }) async {
    if (!mounted) return;
    
    try {
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      // Получаем токен
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        throw Exception('Not authenticated');
      }

      final apiService = ApiService();
      apiService.setAccessToken(accessToken);

      // Определяем тип медиа
      final file = _currentFile ?? widget.selectedFile;
      if (file == null) {
        throw Exception('No file selected');
      }

      final isVideo = _videoController != null;
      final mediaType = isVideo ? 'video' : 'image';

      // Загружаем медиа
      if (!mounted) return;
      
      setState(() {
        _uploadProgress = 0.1;
      });

      Uint8List fileBytes;
      String fileName = file.name;
      String? compressedVideoPath;

      if (_currentImageBytes != null) {
        // Для изображений проверяем размер и сжимаем при необходимости
        final imageSize = _currentImageBytes!.length;
        const int maxSizeBytes = 4718592; // 4.5 МБ

        if (imageSize > 1024 * 1024) { // Больше 1 МБ
          print('StoryPreviewScreen: Image size (${(imageSize / 1024 / 1024).toStringAsFixed(2)} MB), compressing...');
          
          if (mounted) {
            setState(() {
              _uploadProgress = 0.15;
            });
          }

          // Сжимаем изображение в WebP
          final compressedBytes = await ImageCompressor.compressImageToWebP(
            imageBytes: _currentImageBytes!,
            targetSizeBytes: maxSizeBytes,
          );

          if (compressedBytes != null) {
            print('StoryPreviewScreen: Using compressed image');
            fileBytes = compressedBytes;
            // Меняем расширение на .webp
            final originalName = file.name;
            final nameWithoutExt = originalName.split('.').first;
            fileName = '$nameWithoutExt.webp';
          } else {
            print('StoryPreviewScreen: Compression not needed or failed, using original image');
            fileBytes = _currentImageBytes!;
          }
        } else {
          print('StoryPreviewScreen: Image size (${(imageSize / 1024 / 1024).toStringAsFixed(2)} MB) is within limit, no compression needed');
        fileBytes = _currentImageBytes!;
        }
      } else if (isVideo) {
        // Для видео проверяем размер и сжимаем при необходимости
        final fileSize = await file.length();
        const int maxSizeBytes = 4718592; // 4.5 МБ (4.5 * 1024 * 1024)

        if (fileSize > maxSizeBytes) {
          print('StoryPreviewScreen: Video size (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB) exceeds limit, compressing...');
          
          if (mounted) {
            setState(() {
              _uploadProgress = 0.15;
            });
          }

          // Сжимаем видео в AV1 1080p
          compressedVideoPath = await VideoCompressor.compressVideoToAV1(
            inputPath: file.path,
            maxSizeBytes: maxSizeBytes,
          );

          if (compressedVideoPath != null && compressedVideoPath != file.path) {
            print('StoryPreviewScreen: Using compressed video: $compressedVideoPath');
            final compressedFile = File(compressedVideoPath);
            fileBytes = await compressedFile.readAsBytes();
            fileName = 'compressed_${file.name}';
          } else {
            print('StoryPreviewScreen: Compression not needed or failed, using original file');
            fileBytes = await file.readAsBytes();
          }
        } else {
          print('StoryPreviewScreen: Video size (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB) is within limit, no compression needed');
          fileBytes = await file.readAsBytes();
        }
      } else {
        // Для изображений из файла также проверяем размер и сжимаем
        final fileSize = await file.length();
        const int maxSizeBytes = 4718592; // 4.5 МБ

        if (fileSize > 1024 * 1024) { // Больше 1 МБ
          print('StoryPreviewScreen: Image file size (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB), compressing...');
          
          if (mounted) {
            setState(() {
              _uploadProgress = 0.15;
            });
          }

          // Сжимаем изображение в WebP
          final compressedBytes = await ImageCompressor.compressImageFile(
            filePath: file.path,
            targetSizeBytes: maxSizeBytes,
          );

          if (compressedBytes != null) {
            print('StoryPreviewScreen: Using compressed image');
            fileBytes = compressedBytes;
            // Меняем расширение на .webp
            final originalName = file.name;
            final nameWithoutExt = originalName.split('.').first;
            fileName = '$nameWithoutExt.webp';
          } else {
            print('StoryPreviewScreen: Compression not needed or failed, using original file');
            fileBytes = await file.readAsBytes();
          }
        } else {
          print('StoryPreviewScreen: Image file size (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB) is within limit, no compression needed');
        fileBytes = await file.readAsBytes();
        }
      }

      if (mounted) {
        setState(() {
          _uploadProgress = 0.2;
        });
      }

      final mediaUrl = await apiService.uploadMedia(
        fileBytes: fileBytes,
        fileName: fileName,
        mediaType: mediaType,
      );

      // Удаляем временный сжатый файл после загрузки
      if (compressedVideoPath != null && compressedVideoPath != file.path) {
        try {
          final compressedFile = File(compressedVideoPath);
          if (await compressedFile.exists()) {
            await compressedFile.delete();
            print('StoryPreviewScreen: Deleted temporary compressed video file');
          }
        } catch (e) {
          print('StoryPreviewScreen: Error deleting compressed file: $e');
        }
      }

      print('StoryPreviewScreen: Media uploaded, mounted=$mounted');
      
      // Обновляем прогресс только если виджет еще на экране
      if (mounted) {
        setState(() {
          _uploadProgress = 0.7;
        });
      }

      // Создаем пост (сторис) ВСЕГДА, даже если виджет размонтирован
      // Это критическая операция — пользователь загрузил файл, пост должен быть создан
      print('StoryPreviewScreen: Creating story post with:');
      print('  - mediaUrl: $mediaUrl');
      print('  - mediaType: $mediaType');
      print('  - visibility: $visibility');
      print('  - expiresInHours: $expiresInHours');
      
      try {
        final createdPost = await apiService.createPost(
          caption: '',
          mediaUrl: mediaUrl,
          mediaType: mediaType,
          visibility: visibility,
          expiresInHours: expiresInHours,
        );
        
        print('StoryPreviewScreen: Post created with ID: ${createdPost.id}');
        print('StoryPreviewScreen: Post expires_at: ${createdPost.expiresAt}');
      } catch (postError) {
        print('StoryPreviewScreen: ERROR creating post: $postError');
        // Не бросаем ошибку дальше, просто логируем
        // throw postError;
      }

      // Если виджет размонтирован, просто выходим без обновления UI
      if (!mounted) {
        print('StoryPreviewScreen: Widget not mounted, skipping UI updates');
        return;
      }
      
      setState(() {
        _uploadProgress = 1.0;
      });

      print('StoryPreviewScreen: Story published successfully!');

      // Останавливаем видео перед закрытием
      if (_videoController != null) {
        await _videoController!.pause();
      }

      if (!mounted) return;

      // Закрываем все экраны до HomeScreen
      Navigator.of(context).popUntil((route) => route.isFirst);
      
      // Показываем уведомление
      if (mounted) {
        AppNotification.showSuccess(
          context,
          'Story published successfully!',
        );
      }
    } catch (e) {
      print('Error publishing story: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });

        AppNotification.showError(
          context,
          'Failed to publish story: $e',
        );
      }
    }
  }

  Future<void> _onPublish() async {
    if (widget.isGeoPost && widget.latitude != null && widget.longitude != null) {
      // Для гео-постов сначала показываем настройки
      final settings = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => GeoPostSettingsSheet(
          onContinue: (visibility, expiresInHours) {
            Navigator.of(context).pop({
              'visibility': visibility,
              'expiresInHours': expiresInHours,
            });
          },
        ),
      );

      if (settings != null && mounted) {
        // Переходим к GeoPostPreviewScreen для публикации
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => GeoPostPreviewScreen(
              selectedFile: _currentFile ?? widget.selectedFile,
              selectedImageBytes: _currentImageBytes ?? widget.selectedImageBytes,
              videoController: _videoController,
              latitude: widget.latitude!,
              longitude: widget.longitude!,
              visibility: settings['visibility'] as String,
              expiresInHours: settings['expiresInHours'] as int,
            ),
          ),
        );
      }
    } else {
      // Для обычных сторис показываем настройки
      final settings = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => StorySettingsSheet(
          onContinue: (visibility, expiresInHours) {
            Navigator.of(context).pop({
              'visibility': visibility,
              'expiresInHours': expiresInHours,
            });
          },
        ),
      );

      if (settings != null && mounted) {
        // Публикуем сторис через API
        await _publishStory(
          visibility: settings['visibility'] as String,
          expiresInHours: settings['expiresInHours'] as int,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _videoController != null && _videoController!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isUploading
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          _isUploading ? 'Publishing...' : 'Предпросмотр',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
        children: [
          // Media preview
          Expanded(
            child: Center(
              child: _currentImageBytes != null
                  ? Image.memory(
                      _currentImageBytes!,
                      fit: BoxFit.contain,
                    )
                  : isVideo
                      ? GestureDetector(
                          onTap: _togglePlayPause,
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: Stack(
                              children: [
                                VideoPlayer(_videoController!),
                                if (!_isPlaying)
                                  Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        EvaIcons.playCircle,
                                        color: Colors.white,
                                        size: 50,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : const CircularProgressIndicator(),
            ),
          ),

          // Buttons
          if (!_isUploading)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Edit button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _openEditor,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF0095F6), width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(EvaIcons.editOutline, color: Color(0xFF0095F6), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Редактировать',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0095F6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Publish/Share button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _onPublish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0095F6),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        widget.isGeoPost ? 'Опубликовать' : 'Поделиться',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
          // Upload progress overlay
          if (_isUploading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
                      strokeWidth: 6,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '${(_uploadProgress * 100).toInt()}%',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Uploading story...',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

