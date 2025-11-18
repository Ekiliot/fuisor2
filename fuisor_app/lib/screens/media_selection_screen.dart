import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_cropper/image_cropper.dart';
import 'create_post_screen.dart';

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
            // Android 13+ (API 33+) - используем READ_MEDIA_IMAGES и READ_MEDIA_VIDEO
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
        // Также запрашиваем через photo_manager для совместимости
        final photoStatus = await PhotoManager.requestPermissionExtend();
        print('After request - PhotoManager status: $photoStatus');
        
        // Поддерживаем как полный, так и ограниченный доступ
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
        final PermissionState status = await PhotoManager.requestPermissionExtend();
        if (status == PermissionState.authorized || status == PermissionState.limited) {
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
          PhotoManager.openSetting();
        }
      } catch (e2) {
        print('Error with photo_manager fallback: $e2');
        if (mounted) {
          setState(() {
            _hasPermission = false;
          });
        }
      }
    }
  }

  Future<void> _loadMedia({bool loadMore = false}) async {
    if (!_hasPermission || _isLoadingMedia) return;

    setState(() {
      _isLoadingMedia = true;
    });

    try {
      // Для видео используем RequestType.common и фильтруем потом
      // так как RequestType.video может не работать на некоторых устройствах
      final RequestType requestType = _currentTabIndex == 0 
          ? RequestType.image 
          : RequestType.common; // Используем common для видео и фильтруем

      // Получаем все альбомы с фильтром по типу
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: requestType,
        hasAll: true,
      );

      if (albums.isEmpty) {
        setState(() {
          _isLoadingMedia = false;
          _hasMore = false;
        });
        return;
      }

      // Используем первый альбом (обычно это "All Photos" или "Camera Roll")
      final AssetPathEntity recentAlbum = albums.first;

      // Получаем общее количество медиа в альбоме
      int totalCount;
      try {
        totalCount = await recentAlbum.assetCountAsync;
      } catch (e) {
        print('Error getting asset count: $e');
        // Если не удалось получить количество, используем большой номер
        // и будем загружать пока не вернется пустой список
        totalCount = 999999;
      }
      
      final int currentCount = loadMore ? _mediaAssets.length : 0;
      
      print('Total media count: $totalCount, Current loaded: $currentCount');

      // Если totalCount = 0, значит альбом пустой
      if (totalCount == 0) {
        setState(() {
          _hasMore = false;
          _isLoadingMedia = false;
          if (!loadMore) {
            _mediaAssets = [];
          }
        });
        return;
      }

      // Проверяем, есть ли еще медиа для загрузки
      if (currentCount >= totalCount) {
        setState(() {
          _hasMore = false;
          _isLoadingMedia = false;
        });
        return;
      }

      // Загружаем медиа с пагинацией
      // Для видео загружаем больше, так как будем фильтровать
      final int loadCount = _currentTabIndex == 1 ? _pageSize * 2 : _pageSize;
      final int actualEndIndex = (currentCount + loadCount).clamp(0, totalCount);
      
      List<AssetEntity> assets = await recentAlbum.getAssetListRange(
        start: currentCount,
        end: actualEndIndex,
      );

      // Если это вкладка видео, фильтруем только видео
      if (_currentTabIndex == 1) {
        final originalCount = assets.length;
        assets = assets.where((asset) => asset.type == AssetType.video).toList();
        print('Filtered to ${assets.length} videos from $originalCount assets');
        
        // Если после фильтрации получилось мало видео, но мы еще не достигли конца,
        // продолжаем загрузку (но ограничиваем количество попыток)
        if (assets.length < _pageSize && actualEndIndex < totalCount && loadMore) {
          // Пробуем загрузить еще одну порцию
          final int nextEndIndex = (actualEndIndex + loadCount).clamp(0, totalCount);
          final List<AssetEntity> moreAssets = await recentAlbum.getAssetListRange(
            start: actualEndIndex,
            end: nextEndIndex,
          );
          final List<AssetEntity> moreVideos = moreAssets.where((asset) => asset.type == AssetType.video).toList();
          assets.addAll(moreVideos);
          print('Loaded additional ${moreVideos.length} videos (total: ${assets.length})');
        }
      }

      print('Loaded ${assets.length} assets (from $currentCount to $actualEndIndex)');

      // Если загрузили 0 элементов, значит это конец
      if (assets.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMedia = false;
        });
        return;
      }

      setState(() {
        if (loadMore) {
          _mediaAssets.addAll(assets);
        } else {
          _mediaAssets = assets;
        }
        // Проверяем, есть ли еще медиа для загрузки
        // Если totalCount = 999999 (fallback), проверяем по количеству загруженных
        if (totalCount == 999999) {
          // Для видео проверяем по actualEndIndex, для фото по количеству
          _hasMore = _currentTabIndex == 1 
              ? actualEndIndex < 999999 // Продолжаем пока не достигли конца
              : assets.length == _pageSize; // Если загрузили полную страницу, возможно есть еще
        } else {
          // Проверяем, достигли ли мы конца альбома
          _hasMore = actualEndIndex < totalCount;
        }
        _isLoadingMedia = false;
      });
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
          _videoController?.dispose();
          _videoController = null;
        });
      } else if (asset.type == AssetType.video) {
        // Для видео - проверяем длительность (до 5 минут)
        final durationSeconds = asset.duration;
        if (durationSeconds > 300) {
          // Видео слишком длинное
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video must be 5 minutes or less'),
                backgroundColor: Colors.red,
              ),
            );
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

  Future<void> _cropImage() async {
    if (_selectedFile == null || _selectedImageBytes == null || kIsWeb) return;

    try {
      setState(() {
        _isLoading = true;
      });

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: _selectedFile!.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: const Color(0xFF000000),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
            ],
            backgroundColor: const Color(0xFF000000),
            activeControlsWidgetColor: const Color(0xFF0095F6),
            dimmedLayerColor: Colors.black.withOpacity(0.8),
            cropFrameColor: Colors.white,
            cropGridColor: Colors.white.withOpacity(0.3),
            cropFrameStrokeWidth: 2,
            cropGridStrokeWidth: 1,
          ),
          IOSUiSettings(
            title: 'Crop Image',
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
            ],
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            hidesNavigationBar: false,
          ),
        ],
      );

      if (croppedFile != null) {
        final bytes = await croppedFile.readAsBytes();
        setState(() {
          _selectedFile = XFile(croppedFile.path);
          _selectedImageBytes = bytes;
        });
      }
    } catch (e) {
      print('Error cropping image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cropping image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
                        // Кнопки управления
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Row(
                            children: [
                              // Кнопка обрезки (только для фото)
                              if (_selectedImageBytes != null && !kIsWeb)
                                IconButton(
                                  icon: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      EvaIcons.cropOutline,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  onPressed: _isLoading ? null : _cropImage,
                                ),
                            ],
                          ),
                        ),
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
          
          // Вкладки (под предпросмотром)
          if (!kIsWeb && _hasPermission)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Color(0xFF262626),
                    width: 0.5,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF0095F6),
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF8E8E8E),
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(EvaIcons.imageOutline, size: 20),
                    text: 'Photos',
                  ),
                  Tab(
                    icon: Icon(EvaIcons.videoOutline, size: 20),
                    text: 'Videos',
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

    if (_selectedImageBytes != null) {
      // Для фото - центрируем и показываем полностью
      return Center(
        child: Image.memory(
          _selectedImageBytes!,
          fit: BoxFit.contain, // Показываем фото полностью, центрируем
          alignment: Alignment.center,
        ),
      );
    } else if (_videoController != null) {
      // Для видео - используем AspectRatio
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
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
      cacheExtent: 500, // Ограничиваем область кеширования
      addAutomaticKeepAlives: false, // Отключаем автоматическое сохранение состояния
      addRepaintBoundaries: true, // Включаем границы перерисовки
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _mediaAssets.length + (_hasMore && !_isLoadingMedia ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _mediaAssets.length) {
          // Загружаем больше при достижении конца (только если не загружается уже)
          if (!_isLoadingMedia) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadMedia(loadMore: true);
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
          key: ValueKey(asset.id),
          child: _buildMediaThumbnail(asset),
        );
      },
    );
  }

  Widget _buildMediaThumbnail(AssetEntity asset) {
    // Вычисляем размер thumbnail на основе размера экрана для оптимизации
    final screenWidth = MediaQuery.of(context).size.width;
    final thumbnailSize = (screenWidth / 3).round(); // Размер одной ячейки grid
    
    return GestureDetector(
      onTap: () => _selectMedia(asset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail изображения/видео - используем меньший размер для производительности
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              ThumbnailSize(thumbnailSize, thumbnailSize), // Адаптивный размер
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  // Оптимизация изображения
                  gaplessPlayback: true, // Плавная замена изображений
                  filterQuality: FilterQuality.low, // Низкое качество фильтрации для производительности
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
          if (asset.type == AssetType.video)
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
