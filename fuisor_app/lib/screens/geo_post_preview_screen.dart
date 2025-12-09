import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import '../providers/posts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_notification.dart';

class GeoPostPreviewScreen extends StatefulWidget {
  final XFile? selectedFile;
  final Uint8List? selectedImageBytes;
  final VideoPlayerController? videoController;
  final double latitude;
  final double longitude;
  final String visibility;
  final int expiresInHours;

  const GeoPostPreviewScreen({
    super.key,
    this.selectedFile,
    this.selectedImageBytes,
    this.videoController,
    required this.latitude,
    required this.longitude,
    required this.visibility,
    required this.expiresInHours,
  });

  @override
  State<GeoPostPreviewScreen> createState() => _GeoPostPreviewScreenState();
}

class _GeoPostPreviewScreenState extends State<GeoPostPreviewScreen> {
  bool _isLoading = false;
  String? _error;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = widget.videoController;
    if (_videoController != null && !_videoController!.value.isInitialized) {
      _videoController!.initialize().then((_) {
        if (mounted) {
          setState(() {});
          _videoController!.play();
        }
      });
    } else if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.play();
    }
  }

  @override
  void dispose() {
    // Don't dispose video controller here as it might be reused
    super.dispose();
  }

  String _getVisibilityLabel() {
    switch (widget.visibility) {
      case 'public':
        return 'Все';
      case 'friends':
        return 'Друзья';
      case 'private':
        return 'Только я';
      default:
        return 'Все';
    }
  }

  IconData _getVisibilityIcon() {
    switch (widget.visibility) {
      case 'public':
        return EvaIcons.globe2Outline;
      case 'friends':
        return EvaIcons.peopleOutline;
      case 'private':
        return EvaIcons.lockOutline;
      default:
        return EvaIcons.globe2Outline;
    }
  }

  String _getExpiresLabel() {
    if (widget.expiresInHours == 12) {
      return '12 часов';
    } else if (widget.expiresInHours == 24) {
      return '1 день';
    } else {
      return '2 дня';
    }
  }

  Future<void> _publishPost() async {
    if (widget.selectedFile == null) {
      setState(() {
        _error = 'No file selected';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final postsProvider = context.read<PostsProvider>();
      final authProvider = context.read<AuthProvider>();

      if (authProvider.currentUser == null) {
        throw Exception('User not authenticated');
      }

      String mediaType = 'image';
      Uint8List? mediaBytes = widget.selectedImageBytes;
      String mediaFileName = 'post_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Determine media type
      final fileName = widget.selectedFile!.name.toLowerCase();
      final filePath = widget.selectedFile!.path.toLowerCase();
      final isVideo = fileName.contains('.mp4') ||
          fileName.contains('.mov') ||
          fileName.contains('.avi') ||
          fileName.contains('.webm') ||
          filePath.contains('.mp4') ||
          filePath.contains('.mov') ||
          filePath.contains('.avi') ||
          filePath.contains('.webm');

      if (isVideo) {
        mediaType = 'video';
        mediaFileName = 'post_${DateTime.now().millisecondsSinceEpoch}.mp4';
        mediaBytes = await widget.selectedFile!.readAsBytes();
      }

      // Upload media
      final apiService = ApiService();
      final accessToken = await _getAccessToken();
      if (accessToken != null) {
        apiService.setAccessToken(accessToken);
      }

      final mediaUrl = await apiService.uploadMedia(
        fileBytes: mediaBytes!,
        fileName: mediaFileName,
        mediaType: mediaType,
      );

      // Upload thumbnail for video if needed
      String? thumbnailUrl;
      if (mediaType == 'video' && _videoController != null && _videoController!.value.isInitialized) {
        try {
          // Generate thumbnail from video
          final thumbnailBytes = await _generateVideoThumbnail();
          if (thumbnailBytes != null) {
            final thumbnailFileName = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
            thumbnailUrl = await apiService.uploadThumbnail(
              thumbnailBytes: thumbnailBytes,
              fileName: thumbnailFileName,
            );
          }
        } catch (e) {
          print('Error generating thumbnail: $e');
        }
      }

      // Create post
      await postsProvider.createPost(
        caption: '',
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl,
        latitude: widget.latitude,
        longitude: widget.longitude,
        visibility: widget.visibility,
        expiresInHours: widget.expiresInHours,
        accessToken: accessToken,
        currentUser: authProvider.currentUser, // Передаем данные текущего пользователя
      );

      // Navigate back to map screen
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка публикации: $e',
        );
      }
    }
  }

  Future<String?> _getAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token');
    } catch (e) {
      print('Error getting access token: $e');
      return null;
    }
  }

  Future<Uint8List?> _generateVideoThumbnail() async {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return null;
    }

    try {
      // Seek to 1 second
      await _videoController!.seekTo(const Duration(seconds: 1));
      await Future.delayed(const Duration(milliseconds: 100));

      // Get video frame (this is a simplified approach)
      // In production, you might want to use a proper video thumbnail library
      return null; // Placeholder - implement proper thumbnail generation
    } catch (e) {
      print('Error generating thumbnail: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Предпросмотр',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Media preview
          Expanded(
            child: Center(
              child: widget.selectedImageBytes != null
                  ? Image.memory(
                      widget.selectedImageBytes!,
                      fit: BoxFit.contain,
                    )
                  : _videoController != null && _videoController!.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        )
                      : const CircularProgressIndicator(),
            ),
          ),

          // Settings chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                _buildSettingChip(
                  icon: _getVisibilityIcon(),
                  label: _getVisibilityLabel(),
                ),
                const SizedBox(width: 12),
                _buildSettingChip(
                  icon: EvaIcons.clockOutline,
                  label: _getExpiresLabel(),
                ),
              ],
            ),
          ),

          // Error message
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                _error!,
                style: GoogleFonts.inter(
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
            ),

          // Publish button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _publishPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0095F6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  disabledBackgroundColor: Colors.grey,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Опубликовать',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

