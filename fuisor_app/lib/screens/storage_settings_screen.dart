import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/storage_cache_utils.dart';
import '../utils/image_cache_utils.dart';
import '../widgets/app_notification.dart';
import '../services/media_cache_service.dart';
import 'dart:async';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  int _totalCacheSize = 0;
  int _imageCacheSize = 0;
  int _videoCacheSize = 0;
  bool _isLoading = true;
  bool _isClearing = false;
  bool _imageCacheSelected = false;
  bool _videoCacheSelected = false;
  bool _allCacheSelected = false;
  
  // Настройки кеша изображений
  bool _cacheUnlimited = false;
  int _cacheSizeLimitMB = 100;
  bool _isLoadingCacheSettings = false;
  Timer? _periodicCleanupTimer;
  
  // Настройки предзагрузки медиа (из MediaCacheService)
  final MediaCacheService _mediaCache = MediaCacheService();
  bool _preloadEnabled = true;
  int _preloadCount = 10;
  bool _preloadThumbnails = true;
  bool _preloadVideos = false;
  int _maxCacheSize = 1000;
  int _stalePeriodDays = 30;
  bool _isLoadingMediaSettings = false;
  bool _isSavingMediaSettings = false;
  String _mediaCacheSizeMB = '0.00';

  @override
  void initState() {
    super.initState();
    _loadCacheSizes();
    _loadCacheSettings();
    _loadMediaCacheSettings();
    
    // Периодическая проверка и очистка кеша (каждые 30 минут)
    _periodicCleanupTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      ImageCacheUtils.checkAndCleanCacheIfNeeded();
    });
  }
  
  @override
  void dispose() {
    _periodicCleanupTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadCacheSettings() async {
    setState(() => _isLoadingCacheSettings = true);
    try {
      final isUnlimited = await ImageCacheUtils.isCacheUnlimited();
      final limitMB = await ImageCacheUtils.getCacheSizeLimit();
      
      setState(() {
        _cacheUnlimited = isUnlimited;
        _cacheSizeLimitMB = limitMB > 0 ? limitMB : 100;
        _isLoadingCacheSettings = false;
      });
    } catch (e) {
      setState(() => _isLoadingCacheSettings = false);
      print('Error loading cache settings: $e');
    }
  }
  
  Future<void> _onCacheLimitChanged(bool isUnlimited, int? sizeMB) async {
    setState(() {
      _cacheUnlimited = isUnlimited;
      if (sizeMB != null) {
        _cacheSizeLimitMB = sizeMB;
      }
    });
    
    try {
      if (isUnlimited) {
        await ImageCacheUtils.setCacheSizeLimit(-1);
      } else {
        await ImageCacheUtils.setCacheSizeLimit(sizeMB ?? _cacheSizeLimitMB);
      }
    } catch (e) {
      print('Error saving cache settings: $e');
      if (mounted) {
        AppNotification.showError(context, 'Error saving cache settings: $e');
      }
    }
  }

  Future<void> _loadMediaCacheSettings() async {
    setState(() => _isLoadingMediaSettings = true);
    
    try {
      final settings = _mediaCache.getSettings();
      final stats = await _mediaCache.getStats();
      
      setState(() {
        _preloadEnabled = settings['preloadEnabled'] as bool;
        _preloadCount = settings['preloadCount'] as int;
        _preloadThumbnails = settings['preloadThumbnails'] as bool;
        _preloadVideos = settings['preloadVideos'] as bool;
        _maxCacheSize = settings['maxCacheSize'] as int;
        _stalePeriodDays = settings['stalePeriodDays'] as int;
        if (stats.containsKey('cacheSizeMB')) {
          _mediaCacheSizeMB = stats['cacheSizeMB'] as String;
        }
        _isLoadingMediaSettings = false;
      });
    } catch (e) {
      print('Error loading media cache settings: $e');
      setState(() => _isLoadingMediaSettings = false);
    }
  }

  Future<void> _saveMediaCacheSettings() async {
    setState(() => _isSavingMediaSettings = true);
    
    try {
      await _mediaCache.updateSettings(
        maxCacheSize: _maxCacheSize,
        stalePeriodDays: _stalePeriodDays,
        preloadEnabled: _preloadEnabled,
        preloadCount: _preloadCount,
        preloadThumbnails: _preloadThumbnails,
        preloadVideos: _preloadVideos,
      );

      if (mounted) {
        AppNotification.showSuccess(context, 'Media cache settings saved');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'Error saving settings: $e');
      }
    } finally {
      setState(() => _isSavingMediaSettings = false);
    }
  }

  Future<void> _clearMediaCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Clear media cache?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'All cached media files will be deleted. This will free up approximately $_mediaCacheSizeMB MB.',
          style: const TextStyle(color: Color(0xFF8E8E8E)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF8E8E8E)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _mediaCache.clearAllCache();
        await _loadMediaCacheSettings();
        
        if (mounted) {
          AppNotification.showSuccess(context, 'Media cache cleared');
        }
      } catch (e) {
        if (mounted) {
          AppNotification.showError(context, 'Error clearing cache: $e');
        }
      }
    }
  }

  Future<void> _loadCacheSizes() async {
    setState(() => _isLoading = true);
    try {
      final total = await StorageCacheUtils.getTotalCacheSize();
      final image = await StorageCacheUtils.getImageCacheSize();
      final video = await StorageCacheUtils.getVideoCacheSize();
      
      setState(() {
        _totalCacheSize = total;
        _imageCacheSize = image;
        _videoCacheSize = video;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        AppNotification.showError(context, 'Error loading data: $e');
      }
    }
  }

  Future<void> _clearSelectedCache() async {
    if (_isClearing) return;
    
    if (!_imageCacheSelected && !_videoCacheSelected && !_allCacheSelected) {
      return; // Ничего не выбрано
    }

    // Если выбрано "Clear all cache", показываем диалог подтверждения
    if (_allCacheSelected) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Clear all cache?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This action will delete all cached data (photos, videos). This action cannot be undone.',
            style: TextStyle(color: Color(0xFF8E8E8E)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF8E8E8E)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Clear',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isClearing = true);
    try {
      if (_allCacheSelected) {
        await StorageCacheUtils.clearAllCache();
      } else {
        if (_imageCacheSelected) {
          await StorageCacheUtils.clearImageCache();
        }
        if (_videoCacheSelected) {
          await StorageCacheUtils.clearVideoCache();
        }
      }
      
      await _loadCacheSizes();
      
      // Сохраняем выбранные типы перед сбросом чекбоксов
      final wasAllCache = _allCacheSelected;
      final wasImageCache = _imageCacheSelected;
      final wasVideoCache = _videoCacheSelected;
      
      // Сбрасываем выбранные чекбоксы
      setState(() {
        _imageCacheSelected = false;
        _videoCacheSelected = false;
        _allCacheSelected = false;
      });
      
      if (mounted) {
        final clearedTypes = <String>[];
        if (wasAllCache) {
          clearedTypes.add('all cache');
        } else {
          if (wasImageCache) clearedTypes.add('image cache');
          if (wasVideoCache) clearedTypes.add('video cache');
        }
        
        AppNotification.showSuccess(context, '${clearedTypes.join(' and ')} cleared');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'Error clearing cache: $e');
      }
    } finally {
      setState(() => _isClearing = false);
    }
  }

  void _onAllCacheChanged(bool? value) {
    setState(() {
      _allCacheSelected = value ?? false;
      if (_allCacheSelected) {
        _imageCacheSelected = false;
        _videoCacheSelected = false;
      }
    });
  }

  void _onImageCacheChanged(bool? value) {
    setState(() {
      _imageCacheSelected = value ?? false;
      if (_imageCacheSelected) {
        _allCacheSelected = false;
      }
    });
  }

  void _onVideoCacheChanged(bool? value) {
    setState(() {
      _videoCacheSelected = value ?? false;
      if (_videoCacheSelected) {
        _allCacheSelected = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Storage',
          style: GoogleFonts.delaGothicOne(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadCacheSizes,
                    color: const Color(0xFF0095F6),
                    child: ListView(
                      children: [
                        // Общая информация
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Storage Usage',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _StorageInfoRow(
                                  icon: EvaIcons.hardDriveOutline,
                                  label: 'Total cache size',
                                  size: _totalCacheSize,
                                ),
                                const SizedBox(height: 12),
                                _StorageInfoRow(
                                  icon: EvaIcons.imageOutline,
                                  label: 'Image cache',
                                  size: _imageCacheSize,
                                ),
                                const SizedBox(height: 12),
                                _StorageInfoRow(
                                  icon: EvaIcons.videoOutline,
                                  label: 'Video cache',
                                  size: _videoCacheSize,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        
                        // Настройки кеша изображений
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      EvaIcons.settingsOutline,
                                      color: Color(0xFF0095F6),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Image Cache Settings',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Переключатель неограниченного кеша
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Unlimited cache',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _cacheUnlimited
                                                ? 'Cache will grow without limit'
                                                : 'Cache limited to ${_cacheSizeLimitMB}MB',
                                            style: const TextStyle(
                                              color: Color(0xFF8E8E8E),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    CupertinoSwitch(
                                      value: _cacheUnlimited,
                                      onChanged: _isLoadingCacheSettings
                                          ? null
                                          : (value) => _onCacheLimitChanged(value, null),
                                      activeColor: const Color(0xFF0095F6),
                                    ),
                                  ],
                                ),
                                
                                // Ползунок размера кеша (если не неограниченно)
                                if (!_cacheUnlimited) ...[
                                  const SizedBox(height: 24),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Cache size limit',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            '${_cacheSizeLimitMB} MB',
                                            style: const TextStyle(
                                              color: Color(0xFF0095F6),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Slider(
                                        value: _cacheSizeLimitMB.toDouble(),
                                        min: ImageCacheUtils.getMinCacheSize().toDouble(),
                                        max: ImageCacheUtils.getMaxCacheSize().toDouble(),
                                        divisions: (ImageCacheUtils.getMaxCacheSize() - ImageCacheUtils.getMinCacheSize()) ~/ 10,
                                        label: '${_cacheSizeLimitMB} MB',
                                        activeColor: const Color(0xFF0095F6),
                                        inactiveColor: const Color(0xFF262626),
                                        onChanged: _isLoadingCacheSettings
                                            ? null
                                            : (value) {
                                                setState(() {
                                                  _cacheSizeLimitMB = value.round();
                                                });
                                                _onCacheLimitChanged(false, _cacheSizeLimitMB);
                                              },
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${ImageCacheUtils.getMinCacheSize()} MB',
                                            style: const TextStyle(
                                              color: Color(0xFF8E8E8E),
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '${ImageCacheUtils.getMaxCacheSize()} MB',
                                            style: const TextStyle(
                                              color: Color(0xFF8E8E8E),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                                
                                const SizedBox(height: 16),
                                const Divider(color: Color(0xFF262626)),
                                const SizedBox(height: 12),
                                
                                // Информация о текущем размере
                                FutureBuilder<int>(
                                  future: ImageCacheUtils.getCacheSize(),
                                  builder: (context, snapshot) {
                                    final currentSize = snapshot.data ?? 0;
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Current cache size',
                                          style: TextStyle(
                                            color: Color(0xFF8E8E8E),
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          ImageCacheUtils.formatBytes(currentSize),
                                          style: TextStyle(
                                            color: !_cacheUnlimited && currentSize > _cacheSizeLimitMB * 1024 * 1024
                                                ? Colors.orange
                                                : Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Настройки предзагрузки медиа
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      EvaIcons.downloadOutline,
                                      color: Color(0xFF0095F6),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Media Preload Settings',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Enable preload switch
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Enable preload',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Automatically load media for fast viewing',
                                            style: const TextStyle(
                                              color: Color(0xFF8E8E8E),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    CupertinoSwitch(
                                      value: _preloadEnabled,
                                      onChanged: _isLoadingMediaSettings || _isSavingMediaSettings
                                          ? null
                                          : (value) {
                                              setState(() => _preloadEnabled = value);
                                              _saveMediaCacheSettings();
                                            },
                                      activeColor: const Color(0xFF0095F6),
                                    ),
                                  ],
                                ),
                                
                                if (_preloadEnabled) ...[
                                  const SizedBox(height: 24),
                                  // Preload count slider
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Preload count',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            '$_preloadCount posts',
                                            style: const TextStyle(
                                              color: Color(0xFF0095F6),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Slider(
                                        value: _preloadCount.toDouble(),
                                        min: 5,
                                        max: 50,
                                        divisions: 9,
                                        label: '$_preloadCount posts',
                                        activeColor: const Color(0xFF0095F6),
                                        inactiveColor: const Color(0xFF262626),
                                        onChanged: _isLoadingMediaSettings || _isSavingMediaSettings
                                            ? null
                                            : (value) {
                                                setState(() => _preloadCount = value.toInt());
                                                _saveMediaCacheSettings();
                                              },
                                      ),
                                      const Text(
                                        'First N posts will be loaded immediately',
                                        style: TextStyle(
                                          color: Color(0xFF8E8E8E),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 24),
                                  
                                  // Preload thumbnails switch
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Preload thumbnails',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Fast loading of video previews',
                                              style: TextStyle(
                                                color: Color(0xFF8E8E8E),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      CupertinoSwitch(
                                        value: _preloadThumbnails,
                                        onChanged: _isLoadingMediaSettings || _isSavingMediaSettings
                                            ? null
                                            : (value) {
                                                setState(() => _preloadThumbnails = value);
                                                _saveMediaCacheSettings();
                                              },
                                        activeColor: const Color(0xFF0095F6),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 16),
                                  
                                  // Preload videos switch
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Preload videos',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'May consume a lot of data',
                                              style: TextStyle(
                                                color: Color(0xFF8E8E8E),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      CupertinoSwitch(
                                        value: _preloadVideos,
                                        onChanged: _isLoadingMediaSettings || _isSavingMediaSettings
                                            ? null
                                            : (value) {
                                                setState(() => _preloadVideos = value);
                                                _saveMediaCacheSettings();
                                              },
                                        activeColor: const Color(0xFF0095F6),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Storage settings
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      EvaIcons.settingsOutline,
                                      color: Color(0xFF0095F6),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Storage Settings',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Max cache size slider
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Max files in cache',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '$_maxCacheSize files',
                                          style: const TextStyle(
                                            color: Color(0xFF0095F6),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Slider(
                                      value: _maxCacheSize.toDouble(),
                                      min: 100,
                                      max: 5000,
                                      divisions: 49,
                                      label: '$_maxCacheSize files',
                                      activeColor: const Color(0xFF0095F6),
                                      inactiveColor: const Color(0xFF262626),
                                      onChanged: _isLoadingMediaSettings || _isSavingMediaSettings
                                          ? null
                                          : (value) {
                                              setState(() => _maxCacheSize = value.toInt());
                                              _saveMediaCacheSettings();
                                            },
                                    ),
                                    const Text(
                                      'Old files will be deleted automatically',
                                      style: TextStyle(
                                        color: Color(0xFF8E8E8E),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 24),
                                
                                // Stale period slider
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Storage period',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '$_stalePeriodDays days',
                                          style: const TextStyle(
                                            color: Color(0xFF0095F6),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Slider(
                                      value: _stalePeriodDays.toDouble(),
                                      min: 7,
                                      max: 90,
                                      divisions: 83,
                                      label: '$_stalePeriodDays days',
                                      activeColor: const Color(0xFF0095F6),
                                      inactiveColor: const Color(0xFF262626),
                                      onChanged: _isLoadingMediaSettings || _isSavingMediaSettings
                                          ? null
                                          : (value) {
                                              setState(() => _stalePeriodDays = value.toInt());
                                              _saveMediaCacheSettings();
                                            },
                                    ),
                                    const Text(
                                      'Files older than this period will be deleted',
                                      style: TextStyle(
                                        color: Color(0xFF8E8E8E),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 16),
                                const Divider(color: Color(0xFF262626)),
                                const SizedBox(height: 12),
                                
                                // Media cache info
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Media cache size',
                                      style: TextStyle(
                                        color: Color(0xFF8E8E8E),
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      '~$_mediaCacheSizeMB MB',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 12),
                                
                                // Clear media cache button
                                SizedBox(
                                  width: double.infinity,
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(24),
                                        onTap: _clearMediaCache,
                                        child: const Center(
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                EvaIcons.trash2Outline,
                                                size: 18,
                                                color: Colors.red,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Clear media cache',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.5,
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 4),
                        
                        // Чекбокс для очистки изображений
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _CacheCheckbox(
                            icon: EvaIcons.imageOutline,
                            title: 'Clear image cache',
                            isSelected: _imageCacheSelected,
                            onChanged: _imageCacheSize > 0 && !_isClearing && !_allCacheSelected
                                ? _onImageCacheChanged
                                : null,
                          ),
                        ),

                        const SizedBox(height: 4),

                        // Чекбокс для очистки видео
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _CacheCheckbox(
                            icon: EvaIcons.videoOutline,
                            title: 'Clear video cache',
                            isSelected: _videoCacheSelected,
                            onChanged: _videoCacheSize > 0 && !_isClearing && !_allCacheSelected
                                ? _onVideoCacheChanged
                                : null,
                          ),
                        ),

                        const SizedBox(height: 4),

                        // Чекбокс для очистки всего
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _CacheCheckbox(
                            icon: EvaIcons.trash2Outline,
                            title: 'Clear all cache',
                            isSelected: _allCacheSelected,
                            iconColor: Colors.red,
                            textColor: Colors.red,
                            onChanged: _totalCacheSize > 0 && !_isClearing && !_imageCacheSelected && !_videoCacheSelected
                                ? _onAllCacheChanged
                                : null,
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
                
                // Кнопка Clear внизу
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                    child: Container(
                      width: 200,
                      height: 56,
                      decoration: BoxDecoration(
                        color: (_imageCacheSelected || _videoCacheSelected || _allCacheSelected) && !_isClearing
                            ? const Color(0xFF0095F6)
                            : const Color(0xFF8E8E8E),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: (_imageCacheSelected || _videoCacheSelected || _allCacheSelected) && !_isClearing
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF0095F6).withOpacity(0.3),
                                  blurRadius: 12,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: (_imageCacheSelected || _videoCacheSelected || _allCacheSelected) && !_isClearing
                              ? _clearSelectedCache
                              : null,
                          child: Center(
                            child: _isClearing
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Clear',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StorageInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int size;

  const _StorageInfoRow({
    required this.icon,
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0095F6), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E8E8E),
              fontSize: 14,
            ),
          ),
        ),
        Text(
          StorageCacheUtils.formatBytes(size),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CacheCheckbox extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final ValueChanged<bool?>? onChanged;
  final Color? iconColor;
  final Color? textColor;

  const _CacheCheckbox({
    required this.icon,
    required this.title,
    required this.isSelected,
    this.onChanged,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;
    final effectiveIconColor = iconColor ?? 
        (isEnabled ? Colors.white : const Color(0xFF4A4A4A));
    final effectiveTextColor = textColor ?? 
        (isEnabled ? Colors.white : const Color(0xFF4A4A4A));
    
    return GestureDetector(
      onTap: isEnabled ? () => onChanged!(!isSelected) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: effectiveIconColor,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: effectiveTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            CupertinoCheckbox(
              value: isSelected,
              onChanged: onChanged,
              activeColor: const Color(0xFF0095F6),
            ),
          ],
        ),
      ),
    );
  }
}

