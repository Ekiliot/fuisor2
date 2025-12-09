import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/signed_url_cache_service.dart';

/// Обертка для CachedNetworkImage, которая автоматически получает signed URL
/// для приватных файлов (начинающихся с post_ или thumb_, или путей сообщений userId/chatId/...)
class CachedNetworkImageWithSignedUrl extends StatefulWidget {
  final String imageUrl;
  final String? postId; // postId для уникального ключа кеша (для постов)
  final String? chatId; // chatId для сообщений (dm_media bucket)
  final String? cachedSignedUrl; // Предварительно сохраненный signed URL (для мгновенного показа)
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  const CachedNetworkImageWithSignedUrl({
    super.key,
    required this.imageUrl,
    this.postId, // Опциональный postId для уникального ключа кеша
    this.chatId, // Опциональный chatId для сообщений
    this.cachedSignedUrl, // Опциональный предварительно сохраненный signed URL
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<CachedNetworkImageWithSignedUrl> createState() => _CachedNetworkImageWithSignedUrlState();
}

class _CachedNetworkImageWithSignedUrlState extends State<CachedNetworkImageWithSignedUrl> {
  String? _signedUrl;
  bool _isLoading = true;
  String? _error;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isRefreshing = false; // Флаг для фонового обновления signed URL

  @override
  void initState() {
    super.initState();
    final imageUrlPreview = widget.imageUrl.length > 50 
        ? '${widget.imageUrl.substring(0, 50)}...' 
        : widget.imageUrl;
    print('CachedNetworkImageWithSignedUrl: 🚀 initState для $imageUrlPreview');
    
    // Сначала проверяем кеш SignedUrlCacheService (самый быстрый способ)
    final cacheService = SignedUrlCacheService();
    final cachedUrl = cacheService.getCachedSignedUrl(
      path: widget.imageUrl,
      chatId: widget.chatId,
      postId: widget.postId,
    );
    
    // Если есть кешированный signed URL, используем его сразу
    if (cachedUrl != null) {
      print('CachedNetworkImageWithSignedUrl: ⚡ Найден кешированный signed URL, показываем сразу');
      _signedUrl = cachedUrl;
      _isLoading = false;
      // Параллельно проверяем актуальность в фоне
      _refreshSignedUrlInBackground();
    } 
    // Если передан предварительно сохраненный signed URL, используем его
    else if (widget.cachedSignedUrl != null) {
      print('CachedNetworkImageWithSignedUrl: ⚡ Используем переданный cachedSignedUrl');
      _signedUrl = widget.cachedSignedUrl;
      _isLoading = false;
      // Параллельно проверяем актуальность в фоне
      _refreshSignedUrlInBackground();
    } 
    // Иначе загружаем signed URL
    else {
      print('CachedNetworkImageWithSignedUrl: 📥 Signed URL не в кеше, загружаем...');
      _loadSignedUrl();
    }
  }

  @override
  void didUpdateWidget(CachedNetworkImageWithSignedUrl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если imageUrl или postId изменился, перезагружаем signed URL
    if (oldWidget.imageUrl != widget.imageUrl || oldWidget.postId != widget.postId) {
      print('CachedNetworkImageWithSignedUrl: didUpdateWidget - imageUrl или postId изменился, перезагружаем');
      _retryCount = 0;
      _isLoading = true;
      _error = null;
      _signedUrl = null;
      _loadSignedUrl();
    } else if (_error != null) {
      // Если была ошибка и imageUrl не изменился, пытаемся перезагрузить signed URL
      _retryCount = 0;
      _loadSignedUrl();
    }
  }

  Future<void> _loadSignedUrl({bool isRetry = false, bool backgroundRefresh = false}) async {
    // Проверяем, является ли imageUrl путем к файлу
    // Пути постов: начинаются с post_ или thumb_
    // Пути сообщений: формат userId/chatId/timestamp.ext или dm_media/userId/chatId/timestamp.ext
    final isPostPath = widget.imageUrl.startsWith('post_') || widget.imageUrl.startsWith('thumb_');
    final normalizedUrl = widget.imageUrl.startsWith('dm_media/') 
        ? widget.imageUrl.replaceFirst('dm_media/', '')
        : widget.imageUrl;
    final isMessagePath = (normalizedUrl.contains('/') || widget.imageUrl.startsWith('dm_media/')) && 
                          !widget.imageUrl.startsWith('http') && 
                          !widget.imageUrl.startsWith('blob:') &&
                          widget.chatId != null;
    
    if (!isPostPath && !isMessagePath) {
      // Если это уже URL, используем его напрямую
      setState(() {
        _signedUrl = widget.imageUrl;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    // ВАЖНО: Сначала проверяем кеш синхронно для мгновенного показа
    final cacheService = SignedUrlCacheService();
    final cachedSignedUrl = cacheService.getCachedSignedUrl(
      path: widget.imageUrl,
      chatId: widget.chatId,
      postId: widget.postId,
    );

    // Если есть кешированный signed URL, используем его сразу
    if (cachedSignedUrl != null && !backgroundRefresh) {
      print('CachedNetworkImageWithSignedUrl: ⚡ Используем кешированный signed URL (мгновенный показ)');
      if (mounted) {
        setState(() {
          _signedUrl = cachedSignedUrl;
          _isLoading = false;
          _error = null;
        });
      }
      
      // Параллельно проверяем актуальность signed URL в фоне
      _refreshSignedUrlInBackground();
      return;
    }

    // Если это фоновое обновление и signed URL не изменился, не обновляем состояние
    if (backgroundRefresh && cachedSignedUrl == _signedUrl) {
      return;
    }

    // Получаем signed URL для приватного файла через кеш-сервис
    try {
      final imageUrlPreview = widget.imageUrl.length > 50 
          ? '${widget.imageUrl.substring(0, 50)}...' 
          : widget.imageUrl;
      
      if (!backgroundRefresh) {
        print('CachedNetworkImageWithSignedUrl: 📥 Начало загрузки signed URL для: $imageUrlPreview');
      }
      
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken != null) {
        final apiService = ApiService();
        apiService.setAccessToken(accessToken);
        
        // Используем сервис кеширования signed URL
        final signedUrl = await cacheService.getSignedUrl(
          path: widget.imageUrl,
          chatId: widget.chatId,
          postId: widget.postId,
          apiService: apiService,
        );
        
        if (!backgroundRefresh) {
          print('CachedNetworkImageWithSignedUrl: ✅ Signed URL получен, начинаем загрузку изображения');
        }
        
        if (mounted) {
          setState(() {
            // Обновляем signed URL только если он изменился
            if (_signedUrl != signedUrl) {
              _signedUrl = signedUrl;
            }
            if (!backgroundRefresh) {
              _isLoading = false;
            }
            _error = null;
            _retryCount = 0; // Сбрасываем счетчик при успехе
            _isRefreshing = false;
          });
        }
      } else {
        print('CachedNetworkImageWithSignedUrl: ⚠️ Нет access token');
        // Нет токена, используем оригинальный URL (может не работать для приватных файлов)
        if (mounted && !backgroundRefresh) {
          setState(() {
            _signedUrl = widget.imageUrl;
            _isLoading = false;
            _error = 'No access token';
          });
        }
      }
    } catch (e) {
      print('CachedNetworkImageWithSignedUrl: ❌ Ошибка получения signed URL: $e');
      if (mounted && !backgroundRefresh) {
        setState(() {
          _signedUrl = widget.imageUrl; // Fallback на оригинальный URL
          _isLoading = false;
          _error = e.toString();
          _isRefreshing = false;
        });
      }
    }
  }

  /// Фоновая проверка актуальности signed URL
  Future<void> _refreshSignedUrlInBackground() async {
    if (_isRefreshing) return;
    
    _isRefreshing = true;
    
    // Небольшая задержка, чтобы не блокировать UI
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Проверяем актуальность signed URL в фоне
    await _loadSignedUrl(backgroundRefresh: true);
  }

  Future<void> _handleImageError(String url, dynamic error) async {
    print('CachedNetworkImageWithSignedUrl: Image load error for $url: $error');
    
    // Проверяем, является ли это ошибкой истечения signed URL
    final isExpiredError = error.toString().contains('403') || 
                          error.toString().contains('401') || 
                          error.toString().contains('expired') ||
                          error.toString().contains('Forbidden') ||
                          error.toString().contains('Unauthorized');
    
    // Если это ошибка истечения signed URL и мы еще не превысили лимит попыток
    if (isExpiredError && _retryCount < _maxRetries) {
      _retryCount++;
      print('CachedNetworkImageWithSignedUrl: Signed URL expired, refreshing (attempt $_retryCount/$_maxRetries)');
      
      // Инвалидируем кеш и запрашиваем новый signed URL
      final cacheService = SignedUrlCacheService();
      cacheService.invalidate(
        path: widget.imageUrl,
        chatId: widget.chatId,
        postId: widget.postId,
      );
      
      // Обновляем signed URL
      await _loadSignedUrl(isRetry: true);
    } else {
      // Показываем ошибку
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ВАЖНО: Всегда возвращаем контейнер с фиксированными размерами,
    // чтобы не было "прыжков" текста при появлении изображения
    
    // Показываем placeholder пока signed URL загружается
    if (_isLoading) {
      print('CachedNetworkImageWithSignedUrl: ⏳ Показываем placeholder внутри контейнера (isLoading=true)');
      // Возвращаем контейнер с фиксированными размерами и placeholder внутри
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.placeholder?.call(context) ?? Container(
          color: const Color(0xFF262626),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
            ),
          ),
        ),
      );
    }

    // Если ошибка и нет signed URL, показываем error widget в контейнере
    if (_signedUrl == null) {
      print('CachedNetworkImageWithSignedUrl: ❌ Нет signed URL, показываем error widget');
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.errorWidget?.call(context, widget.imageUrl, _error) ?? Container(
          color: const Color(0xFF262626),
          child: const Center(
            child: Icon(Icons.error),
          ),
        ),
      );
    }

    // Проверяем, есть ли signed URL в кеше для определения, нужно ли показывать анимацию
    final cacheService = SignedUrlCacheService();
    final cachedSignedUrl = cacheService.getCachedSignedUrl(
      path: widget.imageUrl,
      chatId: widget.chatId,
      postId: widget.postId,
    );
    
    // Если signed URL был в кеше, значит изображение скорее всего тоже в кеше
    // Показываем без fadeIn анимации для мгновенного появления
    final hasCachedUrl = cachedSignedUrl != null;
    
    if (hasCachedUrl) {
      print('CachedNetworkImageWithSignedUrl: ⚡ Signed URL в кеше, показываем без fadeIn анимации');
    }
    
    // Показываем изображение
    // ВАЖНО: Если signed URL был в кеше, изображение скорее всего тоже в кеше CachedNetworkImage
    // Используем fadeInDuration: Duration.zero для мгновенного появления
    return CachedNetworkImage(
      imageUrl: _signedUrl!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      // Если signed URL был в кеше, убираем fadeIn для мгновенного появления
      fadeInDuration: hasCachedUrl ? Duration.zero : const Duration(milliseconds: 100),
      fadeOutDuration: const Duration(milliseconds: 100),
      fadeInCurve: Curves.easeOut,
      // ВАЖНО: Если signed URL в кеше, не показываем placeholder - изображение должно быть в кеше CachedNetworkImage
      placeholder: hasCachedUrl 
          ? null // Не показываем placeholder если signed URL в кеше
          : (context, url) => widget.placeholder?.call(context) ?? Container(
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
      errorWidget: (context, url, error) {
        // НЕ вызываем setState во время build - используем addPostFrameCallback
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _handleImageError(url, error);
          }
        });
        
        // Показываем виджет ошибки
        return widget.errorWidget?.call(context, url, error) ?? Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(Icons.error),
          ),
        );
      },
      // ВАЖНО: Используем уникальный ключ кеша
      // Это предотвращает коллизии кеша для разных постов/сообщений с одинаковыми путями файлов
      // Добавляем хэш от полного пути для дополнительной уникальности
      cacheKey: widget.postId != null 
          ? 'post_${widget.postId}_${widget.imageUrl}_${widget.imageUrl.hashCode}' // Уникальный ключ с postId и хэшем для постов
          : widget.chatId != null
              ? 'chat_${widget.chatId}_${widget.imageUrl}_${widget.imageUrl.hashCode}' // Уникальный ключ с chatId и хэшем для сообщений
              : '${widget.imageUrl}_${widget.imageUrl.hashCode}_${DateTime.now().millisecondsSinceEpoch}', // Fallback с timestamp для уникальности
      // ВАЖНО: НЕ используем memCacheWidth и memCacheHeight для сохранения пропорций изображения
      // Они могут искажать изображение, особенно для скриншотов с нестандартными пропорциями
      // Используем key для правильного перерисовывания при изменении signed URL
      // Включаем postId в key для гарантии уникальности
      key: ValueKey('${widget.postId ?? widget.chatId ?? ''}_$_signedUrl'),
    );
  }
}

