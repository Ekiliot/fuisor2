import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'create_post_screen.dart';

class MediaSelectionScreen extends StatefulWidget {
  const MediaSelectionScreen({super.key});

  @override
  State<MediaSelectionScreen> createState() => _MediaSelectionScreenState();
}

class _MediaSelectionScreenState extends State<MediaSelectionScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedFile;
  Uint8List? _selectedImageBytes;
  VideoPlayerController? _videoController;
  bool _isLoading = false;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedFile = image;
          _selectedImageBytes = bytes;
          _videoController?.dispose();
          _videoController = null;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      print('MediaSelectionScreen: Starting video pick...');
      setState(() {
        _isLoading = true;
      });

      print('MediaSelectionScreen: Calling pickVideo...');
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      print('MediaSelectionScreen: Video picked: ${video != null}');
      if (video != null) {
        print('MediaSelectionScreen: Video path: ${video.path}');
        print('MediaSelectionScreen: Video name: ${video.name}');
        print('MediaSelectionScreen: Video size: ${video.length} bytes');
        
        _videoController?.dispose();
        
        // Используем условную компиляцию для разных платформ
        if (kIsWeb) {
          print('MediaSelectionScreen: Web platform detected');
          // Для веб просто сохраняем файл без инициализации видео контроллера
          setState(() {
            _selectedFile = video;
            _selectedImageBytes = null;
            _videoController = null;
          });
          print('MediaSelectionScreen: Video file saved for web');
        } else {
          print('MediaSelectionScreen: Mobile platform detected');
          // Для мобильных платформ используем File
          try {
            print('MediaSelectionScreen: Checking if file exists...');
            final file = File(video.path);
            final exists = await file.exists();
            print('MediaSelectionScreen: File exists: $exists');
            
            if (exists) {
              print('MediaSelectionScreen: Initializing video controller...');
              _videoController = VideoPlayerController.file(file);
              await _videoController!.initialize();
              print('MediaSelectionScreen: Video controller initialized');
              
              setState(() {
                _selectedFile = video;
                _selectedImageBytes = null;
              });
              print('MediaSelectionScreen: Video file saved');
            } else {
              print('MediaSelectionScreen: File does not exist at path: ${video.path}');
              throw Exception('Video file does not exist');
            }
          } catch (fileError) {
            print('MediaSelectionScreen: Error initializing video controller: $fileError');
            // Если не удалось инициализировать контроллер, все равно сохраняем файл
            setState(() {
              _selectedFile = video;
              _selectedImageBytes = null;
              _videoController = null;
            });
            print('MediaSelectionScreen: Video file saved without controller');
          }
        }
      } else {
        print('MediaSelectionScreen: No video selected');
      }
    } catch (e) {
      print('MediaSelectionScreen: Error picking video: $e');
      print('MediaSelectionScreen: Error stack: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking video: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        print('MediaSelectionScreen: Loading state set to false');
      }
    }
  }

  void _proceedToEdit() {
    print('MediaSelectionScreen: _proceedToEdit called');
    print('MediaSelectionScreen: _selectedFile is null: ${_selectedFile == null}');
    
    if (_selectedFile != null) {
      print('MediaSelectionScreen: Navigating to CreatePostScreen');
      print('MediaSelectionScreen: File path: ${_selectedFile!.path}');
      print('MediaSelectionScreen: File name: ${_selectedFile!.name}');
      print('MediaSelectionScreen: Has image bytes: ${_selectedImageBytes != null}');
      print('MediaSelectionScreen: Has video controller: ${_videoController != null}');
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            print('MediaSelectionScreen: Building CreatePostScreen');
            return CreatePostScreen(
              selectedFile: _selectedFile!,
              selectedImageBytes: _selectedImageBytes,
              videoController: _videoController,
            );
          },
        ),
      ).then((_) {
        print('MediaSelectionScreen: Returned from CreatePostScreen');
      });
    } else {
      print('MediaSelectionScreen: ERROR - Cannot proceed, no file selected');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        title: const Text(
          'New Post',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(EvaIcons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_selectedFile != null)
            TextButton(
              onPressed: _proceedToEdit,
              child: const Text(
                'Next',
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
          // Предпросмотр выбранного медиа
          if (_selectedFile != null)
            Container(
              height: 300,
              width: double.infinity,
              color: const Color(0xFF1A1A1A),
              child: _buildPreview(),
            ),
          
          // Кнопки выбора медиа
          Expanded(
            child: _buildMediaSelection(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_selectedFile == null) return const SizedBox();

    if (_selectedImageBytes != null) {
      return Image.memory(
        _selectedImageBytes!,
        fit: BoxFit.cover,
      );
    } else if (_videoController != null) {
      return AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      );
    }

    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF0095F6),
      ),
    );
  }

  Widget _buildMediaSelection() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            EvaIcons.imageOutline,
            size: 80,
            color: Color(0xFF8E8E8E),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Media',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a photo or video to share',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF8E8E8E),
            ),
          ),
          const SizedBox(height: 32),
          
          // Кнопка выбора фото
          SizedBox(
            width: 200,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickFromGallery,
              icon: const Icon(EvaIcons.imageOutline),
              label: const Text('Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0095F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Кнопка выбора видео
          SizedBox(
            width: 200,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickVideoFromGallery,
              icon: const Icon(EvaIcons.videoOutline),
              label: const Text('Video'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF262626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          
          if (_isLoading) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(
              color: Color(0xFF0095F6),
            ),
          ],
        ],
      ),
    );
  }
}
