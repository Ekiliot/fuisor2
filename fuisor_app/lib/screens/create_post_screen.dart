import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/posts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/supabase_storage_service.dart';
import '../widgets/animated_app_bar_title.dart';
import '../widgets/app_notification.dart';
import '../widgets/location_selector.dart';
import '../models/user.dart';
import '../services/geocoding_service.dart';

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
  final TextEditingController _linkUrlController = TextEditingController();
  final TextEditingController _linkTextController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  VideoPlayerController? _webVideoController;
  VideoPlayerController? _mobileVideoController;
  User? _selectedCoauthor;
  LocationInfo? _locationInfo;
  Set<String> _locationVisibility = {};

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
      
      // Проверяем, является ли файл видео
        final fileName = widget.selectedFile!.name.toLowerCase();
      final filePath = widget.selectedFile!.path.toLowerCase();
        final isVideo = fileName.contains('.mp4') ||
            fileName.contains('.mov') ||
            fileName.contains('.avi') ||
            fileName.contains('.webm') ||
          fileName.contains('.quicktime') ||
          filePath.contains('.mp4') ||
          filePath.contains('.mov') ||
          filePath.contains('.avi') ||
          filePath.contains('.webm') ||
          filePath.contains('.quicktime');
      
      // Для веб-платформы создаем видеоплеер из blob URL
      if (kIsWeb && widget.videoController == null && isVideo) {
        if (widget.selectedFile!.path.startsWith('blob:')) {
          print('CreatePostScreen: Creating web video controller for blob URL');
          _initializeWebVideoController();
        }
      }
      
      // Для мобильных платформ создаем видеоплеер из файла, если контроллер не передан
      if (!kIsWeb && widget.videoController == null && isVideo && widget.selectedImageBytes == null) {
        print('CreatePostScreen: Creating mobile video controller for file');
        _initializeMobileVideoController();
      }
    }
  }
  
  Future<void> _initializeMobileVideoController() async {
    try {
      print('CreatePostScreen: Initializing mobile video controller...');
      print('CreatePostScreen: File path: ${widget.selectedFile!.path}');
      
      // Проверяем, что файл существует
      final file = File(widget.selectedFile!.path);
      final fileExists = await file.exists();
      final fileSize = fileExists ? await file.length() : 0;
      
      print('CreatePostScreen: File exists: $fileExists, size: $fileSize bytes');
      
      if (!fileExists || fileSize == 0) {
        print('CreatePostScreen: File does not exist or is empty, cannot initialize video controller');
        return;
      }
      
      _mobileVideoController = VideoPlayerController.file(file);
      await _mobileVideoController!.initialize();
      print('CreatePostScreen: Mobile video controller initialized successfully');
      print('CreatePostScreen: Video duration: ${_mobileVideoController!.value.duration}');
      print('CreatePostScreen: Video aspect ratio: ${_mobileVideoController!.value.aspectRatio}');
      
      if (mounted) {
        setState(() {});
      }
    } catch (e, stackTrace) {
      print('CreatePostScreen: Error initializing mobile video controller: $e');
      print('CreatePostScreen: Stack trace: $stackTrace');
      _mobileVideoController?.dispose();
      _mobileVideoController = null;
      if (mounted) {
        setState(() {});
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
    _linkUrlController.dispose();
    _linkTextController.dispose();
    _webVideoController?.dispose();
    _mobileVideoController?.dispose();
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

  // Show external link bottom sheet
  Future<void> _showExternalLinkSheet() async {
    final TextEditingController urlController = TextEditingController(text: _linkUrlController.text);
    final TextEditingController textController = TextEditingController(text: _linkTextController.text);

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'External Link',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(EvaIcons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // URL field
                  const Text(
                    'Link URL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: urlController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'https://example.com',
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
                      fillColor: Color(0xFF262626),
                      prefixIcon: Icon(EvaIcons.link, color: Color(0xFF8E8E8E)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Button text field
                  const Text(
                    'Button Text',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    maxLength: 8,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '6-8 characters',
                      hintStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF262626)),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF262626)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: Color(0xFF0095F6)),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF262626),
                      counterText: '${textController.text.length}/8',
                      counterStyle: const TextStyle(color: Color(0xFF8E8E8E)),
                    ),
                    onChanged: (value) {
                      setModalState(() {}); // Update counter in modal
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Button text will be displayed on the post',
                    style: TextStyle(
                      color: Color(0xFF8E8E8E),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0095F6),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _linkUrlController.text = urlController.text;
                          _linkTextController.text = textController.text;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Show user search dialog
  Future<void> _showUserSearch() async {
    final TextEditingController searchController = TextEditingController();
    List<User> searchResults = [];
    bool isSearching = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Search Coauthor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search by username...',
                        hintStyle: TextStyle(color: Color(0xFF8E8E8E)),
                        prefixIcon: Icon(EvaIcons.search, color: Color(0xFF8E8E8E)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        filled: true,
                        fillColor: Color(0xFF262626),
                      ),
                      onChanged: (value) async {
                        if (value.length >= 2) {
                          setState(() {
                            isSearching = true;
                          });
                          
                          try {
                            final token = await _getAccessTokenFromAuthProvider();
                            if (token != null) {
                              final apiService = ApiService();
                              apiService.setAccessToken(token);
                              final results = await apiService.searchUsers(value, limit: 10);
                              
                              setState(() {
                                searchResults = results;
                                isSearching = false;
                              });
                            }
                          } catch (e) {
                            print('Error searching users: $e');
                            setState(() {
                              isSearching = false;
                            });
                          }
                        } else {
                          setState(() {
                            searchResults = [];
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    if (isSearching)
                      const CircularProgressIndicator(
                        color: Color(0xFF0095F6),
                      )
                    else if (searchResults.isNotEmpty)
                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final user = searchResults[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user.avatarUrl != null
                                    ? NetworkImage(user.avatarUrl!)
                                    : null,
                                child: user.avatarUrl == null
                                    ? const Icon(EvaIcons.personOutline)
                                    : null,
                              ),
                              title: Text(
                                user.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '@${user.username}',
                                style: const TextStyle(color: Color(0xFF8E8E8E)),
                              ),
                              onTap: () {
                                this.setState(() {
                                  _selectedCoauthor = user;
                                });
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
      print('Media size: ${mediaBytes.length} bytes (${(mediaBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');

      // Проверка размера файла
      // Vercel limit ~4.5MB для request body, но мы загружаем через API который может обработать больше
      // Multer на backend настроен на 100MB, но Vercel все еще имеет лимит
      // Для видео увеличиваем лимит до 10MB с предупреждением
      const maxFileSize = 10 * 1024 * 1024; // 10MB
      const warningSize = 4 * 1024 * 1024; // 4MB - предупреждение
      
      if (mediaBytes.length > maxFileSize) {
        throw Exception('File size is too large (${(mediaBytes.length / 1024 / 1024).toStringAsFixed(2)} MB). Maximum size is 10 MB.');
      }
      
      // Показываем предупреждение для больших файлов, но не блокируем загрузку
      if (mediaBytes.length > warningSize && isVideo) {
        print('CreatePostScreen: WARNING - Large video file (${(mediaBytes.length / 1024 / 1024).toStringAsFixed(2)} MB). Upload may fail if file exceeds Vercel limits.');
      }

      // Получаем токен из AuthProvider
      final accessToken = authProvider.currentUser != null ? 
        await _getAccessTokenFromAuthProvider() : null;
      
      // Загружаем медиа файл через API с fallback на Supabase Storage
      print('CreatePostScreen: Uploading media through API...');
      final apiService = ApiService();
      if (accessToken != null) {
        apiService.setAccessToken(accessToken);
      }
      
      String mediaUrl;
      try {
        // Пробуем загрузить через API
        mediaUrl = await apiService.uploadMedia(
          fileBytes: mediaBytes,
          fileName: mediaFileName,
          mediaType: mediaType,
        );
        print('CreatePostScreen: Media uploaded via API, URL: $mediaUrl');
      } catch (e) {
        // Если получили 413 или другую ошибку, используем прямую загрузку в Supabase
        print('CreatePostScreen: API upload failed: $e');
        if (e.toString().contains('413') || e.toString().contains('Request Entity Too Large') || e.toString().contains('FILE_TOO_LARGE_FOR_VERCEL')) {
          print('CreatePostScreen: Falling back to direct Supabase Storage upload...');
          // Используем SupabaseStorageService для больших файлов
          mediaUrl = await SupabaseStorageService.uploadMedia(
            fileBytes: mediaBytes,
            fileName: mediaFileName,
            bucketName: 'post-media',
            accessToken: accessToken,
            mediaType: mediaType, // Передаем mediaType для валидации
          );
          print('CreatePostScreen: Media uploaded via Supabase Storage, URL: $mediaUrl');
        } else {
          // Для других ошибок пробрасываем исключение
          rethrow;
        }
      }
      
      // Загружаем thumbnail если есть через API с fallback
      String? thumbnailUrl;
      if (thumbnailBytes != null) {
        print('CreatePostScreen: Uploading thumbnail...');
        final thumbnailFileName = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          // Пробуем через API
          thumbnailUrl = await apiService.uploadThumbnail(
            thumbnailBytes: thumbnailBytes,
            fileName: thumbnailFileName,
          );
          print('CreatePostScreen: Thumbnail uploaded via API, URL: $thumbnailUrl');
        } catch (e) {
          // Fallback на Supabase Storage
          print('CreatePostScreen: Thumbnail API upload failed: $e, using Supabase Storage...');
          try {
            thumbnailUrl = await SupabaseStorageService.uploadThumbnail(
              thumbnailBytes: thumbnailBytes,
              fileName: thumbnailFileName,
              accessToken: accessToken,
            );
            print('CreatePostScreen: Thumbnail uploaded via Supabase Storage, URL: $thumbnailUrl');
          } catch (supabaseError) {
            print('CreatePostScreen: WARNING - Thumbnail upload failed: $supabaseError, continuing without thumbnail');
          }
        }
      }
      
      // Hashtags are stored directly in the caption text
      final captionText = _captionController.text.trim();
      
      // Получаем геолокацию только если включен Geo boost
      double? latitude;
      double? longitude;
      if (_locationInfo != null && _locationVisibility.isNotEmpty) {
        try {
          print('CreatePostScreen: Getting current location for Geo boost...');
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (serviceEnabled) {
            LocationPermission permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
            }
            
            if (permission == LocationPermission.whileInUse || 
                permission == LocationPermission.always) {
              Position position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              );
              latitude = position.latitude;
              longitude = position.longitude;
              print('CreatePostScreen: Location obtained: lat=$latitude, lng=$longitude');
            } else {
              print('CreatePostScreen: Location permission denied, creating post without location');
            }
          } else {
            print('CreatePostScreen: Location services disabled, creating post without location');
          }
        } catch (e) {
          print('CreatePostScreen: Error getting location: $e, creating post without location');
          // Не блокируем создание поста при ошибке получения геолокации
        }
      }
      
      // Validate external link fields
      String? linkUrl;
      String? linkText;
      
      linkUrl = _linkUrlController.text.trim();
      linkText = _linkTextController.text.trim();
      
      if (linkUrl.isNotEmpty) {
        // Add https:// if no protocol specified
        if (!linkUrl.startsWith('http://') && !linkUrl.startsWith('https://')) {
          linkUrl = 'https://$linkUrl';
        }
        
        // Validate URL
        final uri = Uri.tryParse(linkUrl);
        if (uri == null || !uri.hasAbsolutePath) {
          throw Exception('Invalid URL format');
        }
        
        // Validate link text length
        if (linkText.isNotEmpty && (linkText.length < 6 || linkText.length > 8)) {
          throw Exception('Button text must be 6-8 characters');
        }
      }
      
      print('CreatePostScreen: About to call postsProvider.createPost');
      print('CreatePostScreen: Caption: $captionText');
      print('CreatePostScreen: Media type: $mediaType');
      print('CreatePostScreen: Media URL: $mediaUrl');
      print('CreatePostScreen: Thumbnail URL: ${thumbnailUrl ?? "None"}');
      print('CreatePostScreen: Location: ${latitude != null ? "lat=$latitude, lng=$longitude" : "None"}');
      print('CreatePostScreen: Coauthor ID: ${_selectedCoauthor?.id ?? "None"}');
      print('CreatePostScreen: Coauthor Username: ${_selectedCoauthor?.username ?? "None"}');
      print('CreatePostScreen: External link URL: $linkUrl');
      print('CreatePostScreen: External link Text: $linkText');
      print('CreatePostScreen: Location info: ${_locationInfo != null ? "Present" : "None"}');
      print('CreatePostScreen: Location visibility: $_locationVisibility');
      print('CreatePostScreen: Access token: ${accessToken != null ? "Present" : "Missing"}');
      
      // Формируем строку location_visibility из выбранных элементов
      // Если ничего не выбрано, не передаем данные локации
      String? locationVisibilityStr;
      if (_locationVisibility.isNotEmpty && _locationInfo != null) {
        locationVisibilityStr = _locationVisibility.join(',');
      }
      
      await postsProvider.createPost(
        caption: captionText,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl,
        accessToken: accessToken,
        latitude: locationVisibilityStr != null ? latitude : null,
        longitude: locationVisibilityStr != null ? longitude : null,
        currentUser: authProvider.currentUser, // Передаем данные текущего пользователя
        coauthor: _selectedCoauthor?.id,
        externalLinkUrl: linkUrl,
        externalLinkText: linkText,
        city: locationVisibilityStr != null ? _locationInfo?.city : null,
        district: locationVisibilityStr != null ? _locationInfo?.district : null,
        street: locationVisibilityStr != null ? _locationInfo?.street : null,
        address: locationVisibilityStr != null ? _locationInfo?.address : null,
        country: locationVisibilityStr != null ? _locationInfo?.country : null,
        locationVisibility: locationVisibilityStr,
      );

      print('CreatePostScreen: Post created successfully!');

      if (mounted) {
        // Закрываем все экраны создания поста и возвращаемся к главному экрану
        Navigator.of(context).popUntil((route) => route.isFirst);
        
        AppNotification.showSuccess(
          context,
          'Post created successfully!',
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
        
        AppNotification.showError(
          context,
          'Error creating post: ${e.toString()}',
          duration: const Duration(seconds: 5),
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
        title: const AnimatedAppBarTitle(
          text: 'New Post',
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
          
          // Поле для подписи и другие опции
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
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
                
                // Coauthor section
                const SizedBox(height: 16),
                const Text(
                  'Coauthor',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                if (_selectedCoauthor != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: _selectedCoauthor!.avatarUrl != null
                              ? NetworkImage(_selectedCoauthor!.avatarUrl!)
                              : null,
                          child: _selectedCoauthor!.avatarUrl == null
                              ? const Icon(EvaIcons.personOutline, size: 20)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedCoauthor!.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '@${_selectedCoauthor!.username}',
                                style: const TextStyle(
                                  color: Color(0xFF8E8E8E),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(EvaIcons.close, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _selectedCoauthor = null;
                            });
                          },
                        ),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _showUserSearch(),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF262626),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF404040),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(EvaIcons.personAddOutline, color: Color(0xFF8E8E8E)),
                          SizedBox(width: 12),
                          Text(
                            'Add coauthor (optional)',
                            style: TextStyle(color: Color(0xFF8E8E8E)),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // External link section
                const SizedBox(height: 16),
                const Text(
                  'External Link',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _showExternalLinkSheet(),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _linkUrlController.text.isNotEmpty 
                            ? const Color(0xFF0095F6)
                            : const Color(0xFF404040),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          EvaIcons.link,
                          color: _linkUrlController.text.isNotEmpty 
                              ? const Color(0xFF0095F6)
                              : const Color(0xFF8E8E8E),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _linkUrlController.text.isNotEmpty
                                ? _linkTextController.text.isNotEmpty
                                    ? '${_linkTextController.text} • ${_linkUrlController.text}'
                                    : _linkUrlController.text
                                : 'Add external link (optional)',
                            style: TextStyle(
                              color: _linkUrlController.text.isNotEmpty
                                  ? Colors.white
                                  : const Color(0xFF8E8E8E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_linkUrlController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(EvaIcons.close, color: Colors.white, size: 20),
                            onPressed: () {
                              setState(() {
                                _linkUrlController.clear();
                                _linkTextController.clear();
                              });
                            },
                          )
                        else
                          const Icon(EvaIcons.arrowIosForward, color: Color(0xFF8E8E8E)),
                      ],
                    ),
                  ),
                ),
                
                // Location selector section
                const SizedBox(height: 16),
                LocationSelector(
                  initialLocation: _locationInfo,
                  initialVisibility: _locationVisibility,
                  onLocationChanged: (locationInfo, visibility) {
                    setState(() {
                      _locationInfo = locationInfo;
                      _locationVisibility = visibility;
                    });
                  },
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
    
    // Видео с контроллером (мобильная платформа - переданный контроллер)
    if (widget.videoController != null) {
      return AspectRatio(
        aspectRatio: widget.videoController!.value.aspectRatio,
        child: VideoPlayer(widget.videoController!),
      );
    }

    // Видео с контроллером (мобильная платформа - созданный контроллер)
    if (_mobileVideoController != null && _mobileVideoController!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _mobileVideoController!.value.aspectRatio,
        child: VideoPlayer(_mobileVideoController!),
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
