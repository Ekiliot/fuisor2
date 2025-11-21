import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/posts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_storage_service.dart';

class CreatePostScreen extends StatefulWidget {
  final XFile? selectedFile;
  final Uint8List? selectedImageBytes;
  final VideoPlayerController? videoController;

  const CreatePostScreen({
    super.key,
    this.selectedFile,
    this.selectedImageBytes,
    this.videoController,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _captionController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  VideoPlayerController? _webVideoController;

  @override
  void initState() {
    super.initState();
    print('CreatePostScreen: initState called');
    print('CreatePostScreen: selectedFile is null: ${widget.selectedFile == null}');
    if (widget.selectedFile != null) {
      print('CreatePostScreen: File path: ${widget.selectedFile!.path}');
      print('CreatePostScreen: File name: ${widget.selectedFile!.name}');
      print('CreatePostScreen: Has image bytes: ${widget.selectedImageBytes != null}');
      print('CreatePostScreen: Has video controller: ${widget.videoController != null}');
      
      // Для веб-платформы создаем видеоплеер из blob URL
      if (kIsWeb && widget.videoController == null && widget.selectedFile != null) {
        final fileName = widget.selectedFile!.name.toLowerCase();
        final isVideo = fileName.contains('.mp4') ||
            fileName.contains('.mov') ||
            fileName.contains('.avi') ||
            fileName.contains('.webm') ||
            fileName.contains('.quicktime');
        
        if (isVideo && widget.selectedFile!.path.startsWith('blob:')) {
          print('CreatePostScreen: Creating web video controller for blob URL');
          _initializeWebVideoController();
        }
      }
    }
  }

  Future<void> _initializeWebVideoController() async {
    try {
      print('CreatePostScreen: Initializing web video controller...');
      _webVideoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.selectedFile!.path),
      );
      await _webVideoController!.initialize();
      print('CreatePostScreen: Web video controller initialized');
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('CreatePostScreen: Error initializing web video controller: $e');
      _webVideoController?.dispose();
      _webVideoController = null;
    }
  }

  @override
  void dispose() {
    print('CreatePostScreen: dispose called');
    _captionController.dispose();
    _webVideoController?.dispose();
    super.dispose();
  }

  // Получить токен из AuthProvider
  Future<String?> _getAccessTokenFromAuthProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token');
    } catch (e) {
      print('Error getting access token: $e');
      return null;
    }
  }

  // Создать thumbnail из видео
  Future<Uint8List?> _generateVideoThumbnail(String videoPath) async {
    try {
      print('CreatePostScreen: Generating thumbnail from video: $videoPath');
      
      // Получаем длительность видео для выбора случайного кадра
      VideoPlayerController? tempController;
      Duration? videoDuration;
      
      try {
        if (kIsWeb) {
          // Для веб используем blob URL напрямую
          tempController = VideoPlayerController.networkUrl(Uri.parse(videoPath));
        } else {
          // Для мобильных платформ используем файл
          tempController = VideoPlayerController.file(File(videoPath));
        }
        
        await tempController.initialize();
        videoDuration = tempController.value.duration;
        await tempController.dispose();
      } catch (e) {
        print('CreatePostScreen: Error getting video duration: $e');
        // Если не удалось получить длительность, используем 0
        videoDuration = const Duration(seconds: 1);
      }

      // Выбираем случайное время (от 10% до 90% длительности, минимум 1 секунда)
      final maxTime = videoDuration.inMilliseconds;
      final minTime = (maxTime * 0.1).round();
      final maxTimeForRandom = (maxTime * 0.9).round();
      final randomTime = minTime + Random().nextInt(maxTimeForRandom - minTime);
      
      print('CreatePostScreen: Video duration: ${videoDuration.inSeconds}s');
      print('CreatePostScreen: Random time selected: ${randomTime}ms');

      // Генерируем thumbnail
      String? thumbnailPath;
      
      if (kIsWeb) {
        // Для веб платформы используем другой подход
        // Создаем временный файл из blob URL
        final videoBytes = await widget.selectedFile!.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        final tempVideoFile = File('${tempDir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await tempVideoFile.writeAsBytes(videoBytes);
        
        thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: tempVideoFile.path,
          imageFormat: ImageFormat.JPEG,
          timeMs: randomTime,
          quality: 75,
        );
        
        // Удаляем временный файл
        await tempVideoFile.delete();
      } else {
        // Для мобильных платформ
        thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: randomTime,
          quality: 75,
        );
      }

      if (thumbnailPath == null) {
        print('CreatePostScreen: Failed to generate thumbnail');
        return null;
      }

      print('CreatePostScreen: Thumbnail generated at: $thumbnailPath');
      
      // Читаем thumbnail как байты
      final thumbnailFile = File(thumbnailPath);
      final thumbnailBytes = await thumbnailFile.readAsBytes();
      
      // Удаляем временный файл thumbnail
      await thumbnailFile.delete();
      
      print('CreatePostScreen: Thumbnail size: ${thumbnailBytes.length} bytes');
      return thumbnailBytes;
    } catch (e) {
      print('CreatePostScreen: Error generating thumbnail: $e');
      return null;
    }
  }

  Future<void> _createPost() async {
    print('CreatePostScreen: _createPost called');
    
    if (widget.selectedFile == null) {
      print('CreatePostScreen: ERROR - No file selected!');
      return;
    }

    print('CreatePostScreen: Setting loading state...');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('CreatePostScreen: Getting providers...');
      final postsProvider = context.read<PostsProvider>();
      final authProvider = context.read<AuthProvider>();

      if (authProvider.currentUser == null) {
        print('CreatePostScreen: ERROR - User not authenticated');
        throw Exception('User not authenticated');
      }

      print('CreatePostScreen: User authenticated: ${authProvider.currentUser!.username}');
      print('CreatePostScreen: Selected file path: ${widget.selectedFile!.path}');
      print('CreatePostScreen: Selected file name: ${widget.selectedFile!.name}');
      print('CreatePostScreen: Has image bytes: ${widget.selectedImageBytes != null}');
      print('CreatePostScreen: Has video controller: ${widget.videoController != null}');

      String mediaType = 'image';
      Uint8List? mediaBytes = widget.selectedImageBytes;
      String mediaFileName = 'post_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Определяем тип медиа по расширению файла
      // На веб-платформе path может быть blob URL, поэтому проверяем имя файла
      final fileName = widget.selectedFile!.name.toLowerCase();
      final filePath = widget.selectedFile!.path.toLowerCase();
      print('CreatePostScreen: File path: ${widget.selectedFile!.path}');
      print('CreatePostScreen: File name: ${widget.selectedFile!.name}');
      
      // Проверяем расширение в имени файла (более надежно для веб)
      final isVideo = fileName.contains('.mp4') ||
          fileName.contains('.mov') ||
          fileName.contains('.avi') ||
          fileName.contains('.webm') ||
          fileName.contains('.quicktime') ||
          // Также проверяем путь на случай, если там есть расширение
          filePath.contains('.mp4') ||
          filePath.contains('.mov') ||
          filePath.contains('.avi') ||
          filePath.contains('.webm') ||
          filePath.contains('.quicktime');
      
      Uint8List? thumbnailBytes;
      
      if (isVideo) {
        mediaType = 'video';
        mediaFileName = 'post_${DateTime.now().millisecondsSinceEpoch}.mp4';
        
        print('CreatePostScreen: Detected video file');
        print('CreatePostScreen: Reading video file as bytes...');
        
        // Для видео читаем файл как байты
        try {
          print('CreatePostScreen: Attempting to read video file...');
          print('CreatePostScreen: File path: ${widget.selectedFile!.path}');
          print('CreatePostScreen: Is web platform: $kIsWeb');
          
          // На веб-платформе используем только XFile.readAsBytes()
          // На мобильных платформах тоже используем XFile.readAsBytes() как основной метод
          if (kIsWeb) {
            print('CreatePostScreen: Web platform - using XFile.readAsBytes()...');
            mediaBytes = await widget.selectedFile!.readAsBytes();
            print('CreatePostScreen: Video file read via XFile.readAsBytes() successfully');
            print('CreatePostScreen: Video file size: ${mediaBytes.length} bytes (${(mediaBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
          } else {
            // На мобильных платформах пробуем XFile.readAsBytes() сначала
            try {
              print('CreatePostScreen: Mobile platform - trying XFile.readAsBytes()...');
              mediaBytes = await widget.selectedFile!.readAsBytes();
              print('CreatePostScreen: Video file read via XFile.readAsBytes() successfully');
              print('CreatePostScreen: Video file size: ${mediaBytes.length} bytes (${(mediaBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
            } catch (xfileError) {
              print('CreatePostScreen: XFile.readAsBytes() failed: $xfileError');
              print('CreatePostScreen: Trying File.readAsBytes() as fallback...');
              
              // Fallback на File если XFile не работает
        final file = File(widget.selectedFile!.path);
              final fileExists = await file.exists();
              print('CreatePostScreen: File exists: $fileExists');
              
              if (!fileExists) {
                throw Exception('Video file does not exist at path: ${widget.selectedFile!.path}');
              }
              
        mediaBytes = await file.readAsBytes();
              print('CreatePostScreen: Video file read via File.readAsBytes() successfully');
              print('CreatePostScreen: Video file size: ${mediaBytes.length} bytes (${(mediaBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
            }
          }
        } catch (fileError) {
          print('CreatePostScreen: Error reading video file: $fileError');
          print('CreatePostScreen: Error type: ${fileError.runtimeType}');
          throw Exception('Failed to read video file: $fileError');
        }
        
        // Генерируем thumbnail из видео
        print('CreatePostScreen: Generating thumbnail from video...');
        final videoPath = kIsWeb ? widget.selectedFile!.path : widget.selectedFile!.path;
        thumbnailBytes = await _generateVideoThumbnail(videoPath);
        
        if (thumbnailBytes == null) {
          print('CreatePostScreen: WARNING - Failed to generate thumbnail, continuing without thumbnail');
        } else {
          print('CreatePostScreen: Thumbnail generated successfully, size: ${thumbnailBytes.length} bytes');
        }
      } else {
        print('CreatePostScreen: Detected image file');
        // Для изображений используем selectedImageBytes (обрезанное изображение)
        // Если selectedImageBytes null, читаем файл (fallback для веб или если обрезка не была выполнена)
        if (mediaBytes == null) {
          print('CreatePostScreen: selectedImageBytes is null, reading file...');
          try {
            if (kIsWeb) {
              mediaBytes = await widget.selectedFile!.readAsBytes();
            } else {
              try {
                mediaBytes = await widget.selectedFile!.readAsBytes();
              } catch (xfileError) {
                final file = File(widget.selectedFile!.path);
                if (await file.exists()) {
                  mediaBytes = await file.readAsBytes();
                } else {
                  throw Exception('Image file does not exist at path: ${widget.selectedFile!.path}');
                }
              }
            }
            print('CreatePostScreen: Image file read successfully, size: ${mediaBytes.length} bytes');
          } catch (fileError) {
            print('CreatePostScreen: Error reading image file: $fileError');
            throw Exception('Failed to read image file: $fileError');
          }
        } else {
          print('CreatePostScreen: Using selectedImageBytes (cropped image), size: ${mediaBytes.length} bytes');
        }
      }

      // mediaBytes гарантированно не null после обработки выше
      print('Media type: $mediaType');
      print('Media filename: $mediaFileName');
      print('Caption: ${_captionController.text.trim()}');

      // Получаем токен из AuthProvider
      final accessToken = authProvider.currentUser != null ? 
        await _getAccessTokenFromAuthProvider() : null;
      
      // Загружаем медиа файл напрямую в Supabase Storage
      print('CreatePostScreen: Uploading media to Supabase Storage...');
      final mediaUrl = await SupabaseStorageService.uploadMedia(
        fileBytes: mediaBytes,
        fileName: mediaFileName,
        bucketName: 'post-media',
        accessToken: accessToken,
      );
      
      print('CreatePostScreen: Media uploaded, URL: $mediaUrl');
      
      // Загружаем thumbnail если есть
      String? thumbnailUrl;
      if (thumbnailBytes != null) {
        print('CreatePostScreen: Uploading thumbnail to Supabase Storage...');
        final thumbnailFileName = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
        thumbnailUrl = await SupabaseStorageService.uploadThumbnail(
          thumbnailBytes: thumbnailBytes,
          fileName: thumbnailFileName,
          accessToken: accessToken,
        );
        if (thumbnailUrl != null) {
          print('CreatePostScreen: Thumbnail uploaded, URL: $thumbnailUrl');
        } else {
          print('CreatePostScreen: WARNING - Thumbnail upload failed, continuing without thumbnail');
        }
      }
      
      // Hashtags are stored directly in the caption text
      final captionText = _captionController.text.trim();
      
      print('CreatePostScreen: About to call postsProvider.createPost');
      print('CreatePostScreen: Caption: $captionText');
      print('CreatePostScreen: Media type: $mediaType');
      print('CreatePostScreen: Media URL: $mediaUrl');
      print('CreatePostScreen: Thumbnail URL: ${thumbnailUrl ?? "None"}');
      print('CreatePostScreen: Access token: ${accessToken != null ? "Present" : "Missing"}');
      
      await postsProvider.createPost(
        caption: captionText,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl,
        accessToken: accessToken,
      );

      print('CreatePostScreen: Post created successfully!');

      if (mounted) {
        // Закрываем все экраны создания поста и возвращаемся к главному экрану
        Navigator.of(context).popUntil((route) => route.isFirst);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post created successfully!'),
            backgroundColor: Color(0xFF0095F6),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('CreatePostScreen: ERROR creating post: $e');
      print('CreatePostScreen: Stack trace: $stackTrace');
      if (mounted) {
      setState(() {
        _error = e.toString();
          _isLoading = false;
      });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating post: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
      setState(() {
        _isLoading = false;
      });
        print('CreatePostScreen: Loading state set to false');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        title: Text(
          'New Post',
          style: GoogleFonts.delaGothicOne(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(EvaIcons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () {
              print('CreatePostScreen: Share button pressed');
              print('CreatePostScreen: _isLoading: $_isLoading');
              print('CreatePostScreen: selectedFile is null: ${widget.selectedFile == null}');
              _createPost();
            },
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Color(0xFF0095F6),
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Share',
                    style: TextStyle(
                      color: Color(0xFF0095F6),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Предпросмотр медиа
          if (widget.selectedFile != null)
            Container(
              height: 300,
              width: double.infinity,
              color: const Color(0xFF1A1A1A),
              child: _buildMediaPreview(),
            ),
          
          // Поле для подписи
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Caption',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _captionController,
                  maxLines: 5,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Write a caption...',
                    hintStyle: TextStyle(color: Color(0xFF8E8E8E)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Color(0xFF262626)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Color(0xFF262626)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Color(0xFF0095F6)),
                    ),
                    filled: true,
                    fillColor: Color(0xFF1A1A1A),
                  ),
                ),
                
                // Ошибка
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (widget.selectedFile == null) return const SizedBox();

    // Изображение
    if (widget.selectedImageBytes != null) {
      return Image.memory(
        widget.selectedImageBytes!,
        fit: BoxFit.cover,
      );
    }
    
    // Видео с контроллером (мобильная платформа)
    if (widget.videoController != null) {
      return AspectRatio(
        aspectRatio: widget.videoController!.value.aspectRatio,
        child: VideoPlayer(widget.videoController!),
      );
    }

    // Видео для веб-платформы
    if (_webVideoController != null && _webVideoController!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _webVideoController!.value.aspectRatio,
        child: VideoPlayer(_webVideoController!),
      );
    }
    
    // Проверяем, является ли файл видео (для веб)
    if (kIsWeb && widget.selectedFile != null) {
      final fileName = widget.selectedFile!.name.toLowerCase();
      final isVideo = fileName.contains('.mp4') ||
          fileName.contains('.mov') ||
          fileName.contains('.avi') ||
          fileName.contains('.webm') ||
          fileName.contains('.quicktime');
      
      if (isVideo) {
        // Показываем placeholder для видео, пока загружается
        return Container(
          color: Colors.black,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  EvaIcons.videoOutline,
                  color: Colors.white,
                  size: 48,
                ),
                SizedBox(height: 8),
                Text(
                  'Video preview loading...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Загрузка
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF0095F6),
      ),
    );
  }
}
