import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:async';
import 'dart:math' as math;
import 'create_post_screen.dart';
import 'video_editor_screen.dart';
import '../widgets/custom_image_cropper.dart';
import '../widgets/app_notification.dart';

class MediaSelectionScreen extends StatefulWidget {
  const MediaSelectionScreen({super.key});

  @override
  State<MediaSelectionScreen> createState() => _MediaSelectionScreenState();
}

class _MediaSelectionScreenState extends State<MediaSelectionScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedFile;
  Uint8List? _selectedImageBytes;
  VideoPlayerController? _videoController;
  bool _isLoading = false;
  
  // Для grid медиа
  List<AssetEntity> _mediaAssets = [];
  bool _isLoadingMedia = false;
  bool _hasPermission = false;
  bool _isLimitedAccess = false; // Флаг ограниченного доступа
  static const int _pageSize = 50;
  bool _hasMore = true;
  
  // Для вкладок
  late TabController _tabController;
  int _currentTabIndex = 0; // 0 = Фото, 1 = Видео

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index != _currentTabIndex) {
        setState(() {
          _currentTabIndex = _tabController.index;
          _mediaAssets = [];
          _hasMore = true;
          _thumbnailCache.clear(); // Очищаем кеш при переключении вкладок
        });
        if (_hasPermission) {
          _loadMedia();
        }
      }
    });
    if (!kIsWeb) {
      _checkPermissionAndLoadMedia();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Проверяем разрешения при возврате в приложение (например, из настроек)
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      _checkPermissionAndLoadMedia();
    }
  }

  // Проверяем текущий статус разрешений без запроса
  Future<void> _checkPermissionAndLoadMedia() async {
    try {
      Permission permission;
      
      // Определяем какое разрешение проверять в зависимости от платформы и версии
      if (Platform.isAndroid) {
        try {
          final deviceInfo = DeviceInfoPlugin();
          final androidInfo = await deviceInfo.androidInfo;
          
          if (androidInfo.version.sdkInt >= 33) {
            permission = Permission.photos;
          } else {
            permission = Permission.storage;
          }
        } catch (e) {
          permission = Permission.storage;
        }
      } else if (Platform.isIOS) {
        permission = Permission.photos;
      } else {
        // Для других платформ проверяем через photo_manager
        final photoStatus = await PhotoManager.requestPermissionExtend();
        if (photoStatus == PermissionState.authorized) {
          if (mounted) {
            setState(() {
              _hasPermission = true;
            });
            await _loadMedia();
          }
        } else {
          if (mounted) {
            setState(() {
              _hasPermission = false;
            });
          }
        }
        return;
      }
      
      // Проверяем статус разрешения
      final status = await permission.status;
      print('Permission status: $status');
      
      if (status.isGranted) {
        // Разрешение дано - проверяем через photo_manager
        print('Permission granted, checking photo_manager...');
        final photoStatus = await PhotoManager.requestPermissionExtend();
        print('PhotoManager status: $photoStatus');
        
        if (photoStatus == PermissionState.authorized) {
          print('Both permissions granted, loading media...');
          if (mounted) {
            setState(() {
              _hasPermission = true;
            });
            await _loadMedia();
          }
        } else {
          // permission_handler говорит что дано, но photo_manager не видит
          // Попробуем запросить еще раз через photo_manager (может быть ограниченный доступ)
          print('PhotoManager not authorized, requesting again...');
          final retryStatus = await PhotoManager.requestPermissionExtend();
          print('PhotoManager retry status: $retryStatus');
          
          if (retryStatus == PermissionState.authorized || retryStatus == PermissionState.limited) {
            // Ограниченный доступ тоже подходит
            print('PhotoManager authorized (limited), loading media...');
            if (mounted) {
              setState(() {
                _hasPermission = true;
              });
              await _loadMedia();
            }
          } else {
            if (mounted) {
              setState(() {
                _hasPermission = false;
              });
            }
          }
        }
      } else {
        // Разрешение не дано - запрашиваем
        print('Permission not granted, requesting...');
        await _requestPermissionAndLoadMedia();
      }
    } catch (e) {
      print('Error checking permission: $e');
      // Fallback - проверяем через photo_manager
      try {
        final photoStatus = await PhotoManager.requestPermissionExtend();
        if (photoStatus == PermissionState.authorized || photoStatus == PermissionState.limited) {
          if (mounted) {
            setState(() {
              _hasPermission = true;
            });
            await _loadMedia();
          }
        } else {
          if (mounted) {
            setState(() {
              _hasPermission = false;
            });
          }
        }
      } catch (e2) {
        print('Error with photo_manager check: $e2');
        if (mounted) {
          setState(() {
            _hasPermission = false;
          });
        }
      }
    }
  }

  Future<void> _requestPermissionAndLoadMedia() async {
    try {
      Permission permission;
      
      // Определяем какое разрешение запрашивать в зависимости от платформы и версии
      if (Platform.isAndroid) {
        try {
          final deviceInfo = DeviceInfoPlugin();
          final androidInfo = await deviceInfo.androidInfo;
          
          if (androidInfo.version.sdkInt >= 33) {
            // Android 13+ (API 33+) - запрашиваем и фото, и видео отдельно
            final photosStatus = await Permission.photos.request();
            final videosStatus = await Permission.videos.request();
            
            print('Android 13+ permissions - Photos: $photosStatus, Videos: $videosStatus');
            
            // Проверяем оба разрешения
            if (!videosStatus.isGranted) {
              print('WARNING: Video permission denied! Videos may not be accessible.');
            }
            
            // Используем photos как основной для photo_manager
            permission = Permission.photos;
          } else {
            // Android < 13 - используем READ_EXTERNAL_STORAGE
            permission = Permission.storage;
          }
        } catch (e) {
          // Если не удалось определить версию, используем storage для совместимости
          permission = Permission.storage;
        }
      } else if (Platform.isIOS) {
        // iOS - используем Permission.photos
        permission = Permission.photos;
      } else {
        // Для других платформ используем photo_manager напрямую
        final PermissionState status = await PhotoManager.requestPermissionExtend();
        if (status == PermissionState.authorized) {
          setState(() {
            _hasPermission = true;
          });
          await _loadMedia();
        } else {
          setState(() {
            _hasPermission = false;
          });
          PhotoManager.openSetting();
        }
        return;
      }
      
      // Запрашиваем разрешение через permission_handler
      final status = await permission.request();
      
      if (status.isGranted) {
        // Также запрашиваем через photo_manager с указанием RequestType.all
        final photoStatus = await PhotoManager.requestPermissionExtend(
          requestOption: PermissionRequestOption(
            androidPermission: AndroidPermission(
              type: RequestType.all, // Запрашиваем доступ ко всему
              mediaLocation: false,
            ),
          ),
        );
        print('After request - PhotoManager status: $photoStatus');
        
        // Поддерживаем как полный, так и ограниченный доступ
        if (photoStatus == PermissionState.authorized) {
          if (mounted) {
            setState(() {
              _hasPermission = true;
              _isLimitedAccess = false;
            });
            await _loadMedia();
          }
        } else if (photoStatus == PermissionState.limited) {
          // Ограниченный доступ - показываем предупреждение
          if (mounted) {
            setState(() {
              _hasPermission = true;
              _isLimitedAccess = true;
            });
            await _loadMedia();
            // Показываем предупреждение о ограниченном доступе
            _showLimitedAccessWarning();
          }
        } else {
          if (mounted) {
            setState(() {
              _hasPermission = false;
              _isLimitedAccess = false;
            });
          }
        }
      } else if (status.isPermanentlyDenied) {
        // Разрешение отклонено навсегда - открываем настройки
        setState(() {
          _hasPermission = false;
        });
        await openAppSettings();
      } else {
        // Разрешение отклонено временно
        setState(() {
          _hasPermission = false;
        });
      }
    } catch (e) {
      print('Error requesting permission: $e');
      // Fallback на photo_manager если что-то пошло не так
      try {
        final PermissionState status = await PhotoManager.requestPermissionExtend(
          requestOption: PermissionRequestOption(
            androidPermission: AndroidPermission(
              type: RequestType.all,
              mediaLocation: false,
            ),
          ),
        );
        if (status == PermissionState.authorized) {
          if (mounted) {
            setState(() {
              _hasPermission = true;
              _isLimitedAccess = false;
            });
            await _loadMedia();
          }
        } else if (status == PermissionState.limited) {
          if (mounted) {
            setState(() {
              _hasPermission = true;
              _isLimitedAccess = true;
            });
            await _loadMedia();
            _showLimitedAccessWarning();
          }
        } else {
          if (mounted) {
            setState(() {
              _hasPermission = false;
              _isLimitedAccess = false;
            });
          }
          PhotoManager.openSetting();
        }
      } catch (e2) {
        print('Error with photo_manager fallback: $e2');
        if (mounted) {
          setState(() {
            _hasPermission = false;
            _isLimitedAccess = false;
          });
        }
      }
    }
  }

  void _showLimitedAccessWarning() {
    if (!mounted) return;
    
    AppNotification.showInfo(
      context,
      'Limited access - some videos may be hidden',
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _requestFullAccess() async {
    try {
      // Показываем диалог пользователю
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Limited Access'),
          content: const Text(
            'The app currently has limited access to your media. '
            'To see all videos, please grant full access in the next screen.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Grant Access'),
            ),
          ],
        ),
      );

      if (result == true && mounted) {
        // Открываем системный picker для выбора дополнительных файлов
        await PhotoManager.presentLimited();
        
        // Перезагружаем медиа после выбора
        await _loadMedia();
        
        // Проверяем статус разрешений снова
        final status = await PhotoManager.requestPermissionExtend(
          requestOption: PermissionRequestOption(
            androidPermission: AndroidPermission(
              type: RequestType.all,
              mediaLocation: false,
            ),
          ),
        );
        
        print('New permission status after selection: $status');
        
        if (status == PermissionState.authorized) {
          setState(() {
            _isLimitedAccess = false;
          });
          if (mounted) {
            AppNotification.showSuccess(context, 'Full access granted!');
          }
        }
      }
    } catch (e) {
      print('Error requesting full access: $e');
      if (mounted) {
        AppNotification.showError(context, 'Error: ${e.toString()}');
      }
    }
  }

  Future<void> _loadMedia({bool loadMore = false}) async {
    if (!_hasPermission || _isLoadingMedia) return;

    print('=== Loading media for tab: $_currentTabIndex ===');
    
    // Проверяем разрешения
    final permissionState = await PhotoManager.requestPermissionExtend();
    print('Permission state: $permissionState');

    setState(() {
      _isLoadingMedia = true;
    });

    try {
      // Упрощенная версия для тестирования
      RequestType requestType;
      
      if (_currentTabIndex == 0) {
        requestType = RequestType.image;
      } else {
        // Для видео используем RequestType.video напрямую
        requestType = RequestType.video;
      }

      // Получаем все альбомы с фильтром по типу
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: requestType,
        hasAll: true,
        onlyAll: false, // Важно! Показывает все альбомы
      );

      // Если для видео не нашлось альбомов, пробуем all как fallback
      if (albums.isEmpty && _currentTabIndex == 1) {
        print('No albums found with RequestType.video, trying RequestType.all...');
        requestType = RequestType.all;
        albums = await PhotoManager.getAssetPathList(
          type: requestType,
          hasAll: true,
          onlyAll: false,
        );
        print('Found ${albums.length} albums with RequestType.all');
      }
      
      print('Loading ${_currentTabIndex == 0 ? "images" : "videos"} with RequestType: $requestType, found ${albums.length} albums');

      if (albums.isEmpty) {
        print('No albums found!');
        setState(() {
          _isLoadingMedia = false;
          _hasMore = false;
        });
        return;
      }

      // Для вкладки Videos: собираем видео из всех альбомов, а не только из первого
      if (_currentTabIndex == 1) {
        // Если уже загрузили видео и пытаемся подгрузить еще — просто выходим
        if (loadMore && _mediaAssets.isNotEmpty) {
          setState(() {
            _isLoadingMedia = false;
          });
          return;
        }

        const int pageSize = _pageSize;
        const int maxVideosToLoad = 300; // ограничение для производительности
        final List<AssetEntity> videos = [];

        for (final album in albums) {
          final int albumCount = await album.assetCountAsync;
          print('Scanning album for videos: ${album.name}, count: $albumCount');
          if (albumCount == 0) continue;

          for (int start = 0; start < albumCount && videos.length < maxVideosToLoad; start += pageSize) {
            final int end = (start + pageSize).clamp(0, albumCount);
            print('Loading assets from album ${album.name}: range=[$start, $end)');

            final batch = await album.getAssetListRange(
              start: start,
              end: end,
            );

            // Некоторые устройства/версии Android помечают видео не как AssetType.video,
            // но при этом у них duration > 0. Используем duration как основной критерий.
            final batchVideos = batch.where((a) => a.duration > 0).toList();
            print('Found ${batchVideos.length} videos in this batch');

            // Отладка: выведем типы и длительности первых 5 ассетов
            for (int i = 0; i < math.min(5, batch.length); i++) {
              final a = batch[i];
              print('Asset $i: type=${a.type}, duration=${a.duration}, width=${a.width}, height=${a.height}, path=${a.relativePath ?? "no path"}');
            }

            videos.addAll(batchVideos);
          }

          if (videos.length >= maxVideosToLoad) {
            print('Reached maxVideosToLoad=$maxVideosToLoad, stopping album scan');
            break;
          }
        }

        setState(() {
          _mediaAssets = videos;
          _thumbnailCache.clear();
          _hasMore = false; // мы уже просканировали все доступные альбомы
          _isLoadingMedia = false;
        });

        print('Video loading completed across albums: ${_mediaAssets.length} videos total');

        // Если видео не найдены, попробуем другой подход - запросить через image_picker
        if (_mediaAssets.isEmpty) {
          print('No videos found via PhotoManager, trying image_picker fallback...');
          try {
            final XFile? video = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
            if (video != null) {
              print('Fallback image_picker found video: ${video.path}');
              // Создадим AssetEntity из файла (упрощённо)
              // Но это сложно, лучше просто показать что видео доступны через picker
            }
          } catch (e) {
            print('Fallback image_picker failed: $e');
          }
        }
        return;
      }

      // Для фото (Photos вкладка) используем первый альбом (обычно "Recent" или "All")
      AssetPathEntity recentAlbum = albums.first;

      int totalCount = await recentAlbum.assetCountAsync;
      print('Album: ${recentAlbum.name}, Asset count: $totalCount');

      if (totalCount == 0) {
        print('Album is empty!');
        setState(() {
          _hasMore = false;
          _isLoadingMedia = false;
          if (!loadMore) {
            _mediaAssets = [];
          }
        });
        return;
      }

      // Определяем начальную позицию и количество для загрузки
      final int currentCount = loadMore ? _mediaAssets.length : 0;
      final int pageSize = _pageSize; // Размер страницы
      final int startIndex = currentCount;
      final int endIndex = (startIndex + pageSize).clamp(0, totalCount);
      
      print('Loading media: start=$startIndex, end=$endIndex, currentCount=$currentCount, totalCount=$totalCount');
      
      // Загружаем следующую порцию ассетов
      List<AssetEntity> assets = await recentAlbum.getAssetListRange(
        start: startIndex,
        end: endIndex,
      );

      print('Loaded ${assets.length} assets from range [$startIndex, $endIndex)');
      
      // Для видео фильтруем только по типу
      if (_currentTabIndex == 1) {
        final originalCount = assets.length;
        assets = assets.where((asset) => asset.type == AssetType.video).toList();
        print('Filtered to ${assets.length} videos from $originalCount assets');
        
        // Для видео: если после фильтрации получили 0, но еще не достигли конца альбома,
        // продолжаем загрузку (видео могут быть разбросаны)
        int currentEndIndex = endIndex;
        while (assets.isEmpty && currentEndIndex < totalCount) {
          print('No videos in this batch, loading next batch...');
          final nextStartIndex = currentEndIndex;
          final nextEndIndex = (nextStartIndex + pageSize).clamp(0, totalCount);
          
          if (nextStartIndex >= totalCount) break;
          
            final nextAssets = await recentAlbum.getAssetListRange(
              start: nextStartIndex,
            end: nextEndIndex,
          );
          
            final nextVideos = nextAssets.where((asset) => asset.type == AssetType.video).toList();
          print('Next batch [$nextStartIndex, $nextEndIndex): found ${nextVideos.length} videos from ${nextAssets.length} assets');
            
            if (nextVideos.isNotEmpty) {
              assets = nextVideos;
            currentEndIndex = nextEndIndex;
            break;
          }
          
          currentEndIndex = nextEndIndex;
          
          // Ограничение: не более 10 попыток (500 ассетов)
          if (currentEndIndex - endIndex > pageSize * 10) {
            print('Reached maximum search depth for videos');
            break;
          }
        }
        
        // Обновляем состояние
              setState(() {
                if (loadMore) {
            final existingIds = _mediaAssets.map((a) => a.id).toSet();
            final newAssets = assets.where((a) => !existingIds.contains(a.id)).toList();
            _mediaAssets.addAll(newAssets);
            print('Added ${newAssets.length} new video assets');
                } else {
                  _mediaAssets = assets;
                  _thumbnailCache.clear();
                }
          _hasMore = currentEndIndex < totalCount;
                _isLoadingMedia = false;
              });
        print('Video loading completed: ${_mediaAssets.length} videos total, hasMore: $_hasMore');
              return;
      } else {
        // Для фото фильтруем только изображения
        final originalCount = assets.length;
        assets = assets.where((asset) => asset.type == AssetType.image).toList();
        print('Filtered to ${assets.length} images from $originalCount assets');
      }

      // Если загрузили 0 элементов и достигли конца альбома, значит это конец
      if (assets.isEmpty && endIndex >= totalCount) {
        print('No more assets found! Reached end of album.');
        setState(() {
          _hasMore = false;
          _isLoadingMedia = false;
        });
        return;
      }

      // Если загрузили 0 элементов, но еще не достигли конца (для фото)
      if (assets.isEmpty && _currentTabIndex == 0) {
        print('No images in this batch, but more assets available.');
        setState(() {
          _hasMore = endIndex < totalCount;
          _isLoadingMedia = false;
        });
        return;
      }

      // Устанавливаем состояние
      setState(() {
        if (loadMore) {
          // При подгрузке добавляем к существующим, избегая дубликатов
          final existingIds = _mediaAssets.map((a) => a.id).toSet();
          final newAssets = assets.where((a) => !existingIds.contains(a.id)).toList();
          _mediaAssets.addAll(newAssets);
          print('Added ${newAssets.length} new assets (${assets.length - newAssets.length} duplicates skipped)');
        } else {
          // При первой загрузке заменяем и очищаем кеш
          _mediaAssets = assets;
          _thumbnailCache.clear(); // Очищаем кеш при первой загрузке
        }
        // Проверяем, есть ли еще медиа для загрузки
        if (_currentTabIndex == 1) {
          // Для видео: продолжаем пока не достигли конца альбома
          _hasMore = endIndex < totalCount;
        } else {
          // Для фото: если загрузили меньше чем pageSize, значит это конец
          _hasMore = endIndex < totalCount && assets.length >= pageSize;
        }
        _isLoadingMedia = false;
      });
      
      print('Media loaded successfully: ${_mediaAssets.length} items total, hasMore: $_hasMore');
    } catch (e) {
      print('Error loading media: $e');
      setState(() {
        _isLoadingMedia = false;
        _hasMore = false; // Останавливаем загрузку при ошибке
      });
    }
  }

  Future<void> _selectMedia(AssetEntity asset) async {
    try {
      // Паузим и отключаем предыдущий видео контроллер перед выбором нового медиа
      if (_videoController != null) {
        await _videoController!.pause();
        _videoController!.dispose();
        _videoController = null;
      }
      
      setState(() {
        _isLoading = true;
      });

      final file = await asset.file;
      if (file == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      if (asset.type == AssetType.image) {
        // Для изображений
        final bytes = await file.readAsBytes();
        final xFile = XFile(file.path);
        
        setState(() {
          _selectedFile = xFile;
          _selectedImageBytes = bytes;
          _videoController = null;
        });
      } else if (asset.type == AssetType.video) {
        // Для видео - проверяем длительность (до 5 минут)
        final durationSeconds = asset.duration;
        if (durationSeconds > 300) {
          // Видео слишком длинное
          if (mounted) {
            AppNotification.showError(context, 'Video must be 5 minutes or less');
          }
          setState(() {
            _isLoading = false;
          });
          return;
        }

        final xFile = XFile(file.path);
        
        _videoController?.dispose();
        
        if (kIsWeb) {
          setState(() {
            _selectedFile = xFile;
            _selectedImageBytes = null;
            _videoController = null;
          });
        } else {
          try {
            final videoFile = File(file.path);
            if (await videoFile.exists()) {
              _videoController = VideoPlayerController.file(videoFile);
              await _videoController!.initialize();
              
              setState(() {
                _selectedFile = xFile;
                _selectedImageBytes = null;
              });
            }
          } catch (e) {
            print('Error initializing video: $e');
            setState(() {
              _selectedFile = xFile;
              _selectedImageBytes = null;
              _videoController = null;
            });
          }
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error selecting media: $e');
      setState(() {
        _isLoading = false;
      });
    }
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
        AppNotification.showError(context, 'Error picking video: ${e.toString()}');
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


  Future<void> _proceedToEdit() async {
    print('MediaSelectionScreen: _proceedToEdit called');
    print('MediaSelectionScreen: _selectedFile is null: ${_selectedFile == null}');
    
    if (_selectedFile != null) {
      // Для видео открываем редактор
      if (_videoController != null || _isVideoFile(_selectedFile!)) {
        // Отключаем видео контроллер перед переходом в редактор
        if (_videoController != null) {
          await _videoController!.pause();
          _videoController!.dispose();
          _videoController = null;
        }
        
        final editedFile = await Navigator.of(context).push<XFile>(
          MaterialPageRoute(
            builder: (context) => VideoEditorScreen(
              selectedFile: _selectedFile,
              videoController: null, // Не передаем контроллер, он уже отключен
            ),
            fullscreenDialog: true,
          ),
        );
        
        if (editedFile != null && mounted) {
          print('MediaSelectionScreen: Received edited file: ${editedFile.path}');

          // Инициализируем видео контроллер для отредактированного файла
          VideoPlayerController? newController;
          if (!kIsWeb) {
            try {
              final editedVideoFile = File(editedFile.path);
              final fileExists = await editedVideoFile.exists();
              print('MediaSelectionScreen: Edited file exists: $fileExists, size: ${fileExists ? await editedVideoFile.length() : 0} bytes');

              if (fileExists && await editedVideoFile.length() > 0) {
                newController = VideoPlayerController.file(editedVideoFile);
                await newController.initialize();
                print('MediaSelectionScreen: Edited video controller initialized successfully, aspect ratio: ${newController.value.aspectRatio}');
                
                // Добавляем слушатель для обновления UI при изменении состояния
                newController.addListener(() {
                  if (mounted) {
                    setState(() {});
                  }
                });
              } else {
                print('MediaSelectionScreen: Edited file does not exist or is empty!');
              }
            } catch (e) {
              print('MediaSelectionScreen: Error initializing edited video controller: $e');
            }
          }

          setState(() {
            _selectedFile = editedFile;
            _videoController = newController;
          });
          _navigateToCreatePost();
        }
      } else if (_selectedImageBytes != null && !kIsWeb) {
        // Если это фото, открываем собственный кроппер
        final croppedBytes = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(
            builder: (context) => CustomImageCropper(
              imageBytes: _selectedImageBytes!,
            ),
            fullscreenDialog: true,
          ),
      );

        if (croppedBytes != null && mounted) {
        setState(() {
            _selectedImageBytes = croppedBytes;
        });
          _navigateToCreatePost();
        } else if (mounted) {
          // Пользователь отменил обрезку, используем оригинальное изображение
          _navigateToCreatePost();
      }
      } else {
        // Для веб или других случаев сразу переходим
        _navigateToCreatePost();
      }
    } else {
      print('MediaSelectionScreen: ERROR - Cannot proceed, no file selected');
    }
  }

  bool _isVideoFile(XFile file) {
    final name = file.name.toLowerCase();
    return name.contains('.mp4') || name.contains('.mov') || 
           name.contains('.avi') || name.contains('.webm') ||
           name.contains('.quicktime');
  }

  void _navigateToCreatePost() async {
      print('MediaSelectionScreen: Navigating to CreatePostScreen');
      print('MediaSelectionScreen: File path: ${_selectedFile!.path}');
      print('MediaSelectionScreen: File name: ${_selectedFile!.name}');
      print('MediaSelectionScreen: Has image bytes: ${_selectedImageBytes != null}');
      print('MediaSelectionScreen: Has video controller: ${_videoController != null}');
      
      // Отключаем видео контроллер перед переходом в CreatePostScreen
      if (_videoController != null) {
        await _videoController!.pause();
        _videoController!.dispose();
        _videoController = null;
      }
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            print('MediaSelectionScreen: Building CreatePostScreen');
            return CreatePostScreen(
              selectedFile: _selectedFile!,
              selectedImageBytes: _selectedImageBytes,
              videoController: null, // Не передаем контроллер, он уже отключен
            );
          },
        ),
      ).then((_) {
        print('MediaSelectionScreen: Returned from CreatePostScreen');
      });
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
          // Кнопка для изменения доступа к медиа (если ограниченный доступ)
          if (_isLimitedAccess)
            IconButton(
              icon: const Icon(EvaIcons.settingsOutline, color: Colors.white),
              tooltip: 'Change media access',
              onPressed: () async {
                await _requestFullAccess();
              },
            ),
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: 400,
              width: double.infinity,
              color: const Color(0xFF1A1A1A),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0095F6),
                      ),
                    )
                  : Stack(
                      children: [
                        _buildPreview(),
                        // Кнопки управления (кнопка обрезки убрана, кроппер встроен в предпросмотр)
                        // Кнопка закрытия предпросмотра
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                EvaIcons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedFile = null;
                                _selectedImageBytes = null;
                                _videoController?.dispose();
                                _videoController = null;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          
          // Вкладки (под предпросмотром) - в стиле профиля
          if (!kIsWeb && _hasPermission)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Photos Tab
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_tabController.index != 0) {
                          _tabController.animateTo(0);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _tabController.index == 0
                              ? Colors.white.withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                EvaIcons.imageOutline,
                                color: _tabController.index == 0
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.6),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Photos',
                                style: TextStyle(
                                  color: _tabController.index == 0
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.6),
                                  fontSize: 14,
                                  fontWeight: _tabController.index == 0
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Videos Tab
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_tabController.index != 1) {
                          _tabController.animateTo(1);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _tabController.index == 1
                              ? Colors.white.withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                EvaIcons.videoOutline,
                                color: _tabController.index == 1
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.6),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Videos',
                                style: TextStyle(
                                  color: _tabController.index == 1
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.6),
                                  fontSize: 14,
                                  fontWeight: _tabController.index == 1
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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

    if (_selectedImageBytes != null && !kIsWeb) {
      // Для фото - показываем изображение с возможностью обрезки
      return Center(
        child: Image.memory(
          _selectedImageBytes!,
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ),
      );
    } else if (_selectedImageBytes != null && kIsWeb) {
      // Для веб - просто показываем изображение
      return Center(
        child: Image.memory(
          _selectedImageBytes!,
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ),
      );
    } else if (_videoController != null) {
      // Для видео - используем AnimatedBuilder для автоматического обновления при изменении контроллера
      return AnimatedBuilder(
        animation: _videoController!,
        builder: (context, child) {
          // Паузим видео при показе предпросмотра, чтобы не нагружать систему
          if (_videoController!.value.isPlaying) {
            _videoController!.pause();
          }
          
          if (!_videoController!.value.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            );
          }
          
          return Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          );
        },
      );
    }

    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF0095F6),
      ),
    );
  }

  Widget _buildMediaSelection() {
    // Для веб используем старый способ с кнопками
    if (kIsWeb) {
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

    // Для мобильных - показываем grid
    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              EvaIcons.lockOutline,
              size: 80,
              color: Color(0xFF8E8E8E),
            ),
            const SizedBox(height: 16),
            const Text(
              'Permission Required',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please grant access to your photos',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8E8E8E),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                // Открываем настройки
                await openAppSettings();
                // Ждем немного и проверяем разрешения снова
                await Future.delayed(const Duration(milliseconds: 500));
                _checkPermissionAndLoadMedia();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0095F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (_isLoadingMedia && _mediaAssets.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0095F6),
        ),
      );
    }

    if (_mediaAssets.isEmpty && !_isLoadingMedia) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentTabIndex == 0 
                  ? EvaIcons.imageOutline 
                  : EvaIcons.videoOutline,
              size: 80,
              color: const Color(0xFF8E8E8E),
            ),
            const SizedBox(height: 16),
            Text(
              _currentTabIndex == 0 
                  ? 'No Photos Found'
                  : 'No Videos Found',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _currentTabIndex == 0 
                  ? 'Your gallery has no photos'
                  : 'Your gallery has no videos',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF8E8E8E),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      // Оптимизация производительности
      cacheExtent: 1000, // Увеличиваем область кеширования
      addAutomaticKeepAlives: true, // Включаем сохранение состояния для предотвращения перезагрузки
      addRepaintBoundaries: true, // Включаем границы перерисовки
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1.0, // Явно задаём квадратные ячейки 1:1
      ),
      itemCount: _mediaAssets.length + (_hasMore && !_isLoadingMedia ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _mediaAssets.length) {
          // Загружаем больше при достижении конца (только если не загружается уже)
          if (!_isLoadingMedia) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isLoadingMedia) {
              _loadMedia(loadMore: true);
              }
            });
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
                strokeWidth: 2,
              ),
            ),
          );
        }

        final asset = _mediaAssets[index];
        // Используем key для оптимизации перерисовок
        return RepaintBoundary(
          key: ValueKey('media_${asset.id}_$index'), // Добавляем index для уникальности
          child: _buildMediaThumbnail(asset),
        );
      },
    );
  }

  // Кеш для thumbnail данных
  final Map<String, Future<Uint8List?>> _thumbnailCache = {};

  Widget _buildMediaThumbnail(AssetEntity asset) {
    // Вычисляем размер thumbnail на основе размера экрана для оптимизации
    final screenWidth = MediaQuery.of(context).size.width;
    final thumbnailSize = (screenWidth / 3).round(); // Размер одной ячейки grid
    
    // Вычисляем размеры thumbnail с сохранением пропорций, чтобы избежать искажений
    // Минимальная сторона должна быть равна thumbnailSize
    final double aspect = asset.width / asset.height;
    int w, h;
    if (aspect > 1) {
       // Landscape: height = size, width = size * aspect
       h = thumbnailSize;
       w = (thumbnailSize * aspect).round();
    } else {
       // Portrait: width = size, height = size / aspect
       w = thumbnailSize;
       h = (thumbnailSize / aspect).round();
    }
    
    // Кешируем Future для предотвращения перезагрузки
    final cacheKey = '${asset.id}_${w}x$h';
    if (!_thumbnailCache.containsKey(cacheKey)) {
      _thumbnailCache[cacheKey] = asset.thumbnailDataWithSize(
        ThumbnailSize(w, h),
      );
    }
    
    return GestureDetector(
      onTap: () => _selectMedia(asset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail изображения/видео - используем кешированный Future
          FutureBuilder<Uint8List?>(
            future: _thumbnailCache[cacheKey],
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData) {
                // Рисуем thumbnail с сохранением пропорций без искажений:
                // - bitmap генерим с правильным aspect (w x h)
                // - FittedBox с BoxFit.cover вписывает это изображение в квадрат ячейки,
                //   показывая только центральную часть, без "сплющивания".
                return ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: w.toDouble(),
                      height: h.toDouble(),
                    child: Image.memory(
                      snapshot.data!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        cacheWidth: w,
                        cacheHeight: h,
                      ),
                    ),
                  ),
                );
              }
              return Container(
                color: const Color(0xFF262626),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0095F6),
                    strokeWidth: 2,
                  ),
                ),
              );
            },
          ),
          // Индикатор видео
          if (asset.duration > 0)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      EvaIcons.videoOutline,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Builder(
                      builder: (context) {
                        final durationSeconds = asset.duration;
                        if (durationSeconds > 0) {
                          final minutes = durationSeconds ~/ 60;
                          final seconds = durationSeconds % 60;
                          return Text(
                            '${minutes}:${seconds.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
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
