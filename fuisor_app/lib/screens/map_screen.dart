import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' show Geolocator, LocationPermission, LocationAccuracy;
import 'package:geolocator/geolocator.dart' as geo show Position;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:async' show Timer, TimeoutException;
import '../models/user.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/geo_marker_clipper.dart';
import '../widgets/location_settings_sheet.dart';
import 'camera_screen.dart';
import 'geo_stories_viewer.dart';
import 'profile_screen.dart';
import '../widgets/app_notification.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// Класс для обработки нажатий на маркер моей локации
class _MyLocationAnnotationClickListener extends OnPointAnnotationClickListener {
  final Function(PointAnnotation) onTap;

  _MyLocationAnnotationClickListener({required this.onTap});

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    onTap(annotation);
  }
}

// Класс для обработки нажатий на маркер друга
class _FriendAnnotationClickListener extends OnPointAnnotationClickListener {
  final Function(PointAnnotation) onTap;

  _FriendAnnotationClickListener({required this.onTap});

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    onTap(annotation);
  }
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  // TabController для переключения между Friends и Posts
  late TabController _tabController;
  
  // Текущая выбранная вкладка (0 = Friends, 1 = Posts)
  int _currentTabIndex = 0;
  
  // Выбранный маркер для отображения информации
  Map<String, dynamic>? _selectedMarker;
  
  MapboxMap? _mapboxMap;
  bool _isMapReady = false;
  geo.Position? _currentPosition;
  bool _isLoadingLocation = true;
  List<Post> _geoPosts = [];
  List<Map<String, dynamic>> _friendsLocations = [];
  bool _isLoadingGeoPosts = false;
  final ApiService _apiService = ApiService();
  bool _locationSharingEnabled = false;
  bool _hasLocationPermission = false;
  bool _is3DMode = true; // Режим карты: всегда 3D
  
  // Annotation managers для маркеров
  PointAnnotationManager? _geoPostsAnnotationManager;
  PointAnnotationManager? _friendsAnnotationManager;
  PointAnnotationManager? _myLocationAnnotationManager;
  
  // Храним ID аннотаций для последующего удаления
  final List<String> _geoPostAnnotationIds = [];
  final List<String> _friendAnnotationIds = [];
  String? _myLocationAnnotationId;
  
  // Храним координаты маркеров для проверки нажатий
  final Map<String, Map<String, double>> _geoPostMarkerCoords = {}; // annotationId -> {lat, lng}
  final Map<String, Map<String, double>> _friendMarkerCoords = {}; // annotationId -> {lat, lng}
  
  // Таймер для обновления стиля карты в зависимости от времени суток
  Timer? _styleUpdateTimer;
  
  // Таймер для проверки изменений зума и обновления размера маркера
  Timer? _zoomCheckTimer;
  
  // Таймер для периодического обновления локации на сервере
  Timer? _locationUpdateTimer;
  
  // Текущий уровень зума карты
  double _currentZoom = 15.5;
  
  // Debounce для обновления маркера - предотвращает слишком частые обновления
  DateTime? _lastMarkerUpdateTime;
  static const Duration _markerUpdateDebounce = Duration(milliseconds: 500);
  Timer? _pulseUpdateTimer; // Таймер для обновления маркера при пульсации
  
  // Анимации для маркера
  late AnimationController _pulseAnimationController;
  late AnimationController _scaleAnimationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;
  
  // Состояние анимации
  bool _isMarkerVisible = false;
  
  // Анимация для появления данных в заголовке
  late AnimationController _headerAnimationController;
  late Animation<double> _headerFadeAnimation;
  late Animation<Offset> _headerSlideAnimation;
  
  // Анимации для открытия страницы
  late AnimationController _pageOpenAnimationController;
  late Animation<double> _appBarAnimation;
  late Animation<double> _bottomBarAnimation;
  late Animation<double> _leftButtonAnimation;
  late Animation<double> _rightButtonAnimation;
  
  // Анимация для glow эффекта по бокам
  late AnimationController _glowAnimationController;
  late Animation<double> _glowRotationAnimation;
  late Animation<double> _glowOpacityAnimation;
  
  // Анимация для meta balls эффекта
  late AnimationController _metaBallsAnimationController;
  late Animation<double> _metaBallsAnimation;
  
  // Отслеживание показа уведомления
  OverlayEntry? _locationNotificationOverlay;
  OverlayEntry? _loadingNotificationOverlay;

  @override
  void initState() {
    super.initState();
    
    // Инициализируем TabController для вкладок Friends и Posts
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
        // Обновляем маркеры в зависимости от выбранной вкладки
        if (_currentTabIndex == 0) {
          // Friends - показываем маркеры друзей, скрываем geo-посты
          _loadFriendsLocations();
          // Очищаем geo-посты
          if (_geoPostsAnnotationManager != null) {
            _geoPostsAnnotationManager!.deleteAll();
          }
        } else {
          // Posts - показываем geo-посты, скрываем маркеры друзей
          _loadGeoPosts();
          // Очищаем маркеры друзей
          if (_friendsAnnotationManager != null) {
            _friendsAnnotationManager!.deleteAll();
          }
        }
      }
    });
    
    // Инициализируем контроллеры анимации ПЕРЕД вызовом других методов
    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _scaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    // Создаем анимации
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scaleAnimationController,
        curve: Curves.easeOutBack,
      ),
    );
    
    // Устанавливаем начальное значение для scaleAnimation
    _scaleAnimationController.value = 1.0;
    
    // Инициализируем анимацию для заголовка
    _headerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _headerFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerAnimationController,
        curve: Curves.easeOut,
      ),
    );
    
    _headerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _headerAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    
    // Инициализируем анимации для открытия страницы
    _pageOpenAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    // Staggered анимации для элементов
    _appBarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pageOpenAnimationController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
      ),
    );
    
    _leftButtonAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pageOpenAnimationController,
        curve: const Interval(0.2, 0.5, curve: Curves.easeOutBack),
      ),
    );
    
    _rightButtonAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pageOpenAnimationController,
        curve: const Interval(0.2, 0.5, curve: Curves.easeOutBack),
      ),
    );
    
    _bottomBarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pageOpenAnimationController,
        curve: const Interval(0.4, 0.7, curve: Curves.easeOutBack),
      ),
    );
    
    // Анимация для glow эффекта по бокам
    _glowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    
    _glowRotationAnimation = Tween<double>(begin: 0.0, end: 2 * 3.14159).animate(
      CurvedAnimation(
        parent: _glowAnimationController,
        curve: Curves.linear,
      ),
    );
    
    _glowOpacityAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(
        parent: _glowAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Анимация для meta balls эффекта
    _metaBallsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _metaBallsAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _metaBallsAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Запускаем анимацию открытия страницы
    _pageOpenAnimationController.forward();
    
    // Запускаем glow анимацию (будет остановлена когда получим геолокацию)
    _glowAnimationController.repeat();
    
    // Запускаем meta balls анимацию
    _metaBallsAnimationController.repeat(reverse: true);
    
    // Добавляем observer для отслеживания lifecycle приложения
    WidgetsBinding.instance.addObserver(this);
    
    _initializeMap();
    _checkLocationPermission();
    _loadLocationSharingStatus();
    // Не вызываем _getCurrentLocation здесь, так как карта еще не создана
    // Вызовем после создания карты
    
    // Запускаем таймер для обновления стиля карты каждую минуту
    _styleUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateMapStyleForTimeOfDay();
    });
    
    // Запускаем таймер для проверки изменений зума и обновления размера маркера
    // Увеличиваем интервал проверки зума для уменьшения нагрузки
    _zoomCheckTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      _checkZoomAndUpdateMarker();
    });
    
    // Запускаем таймер для периодического обновления локации на сервере (каждые 5 минут)
    _startLocationUpdateTimer();
    
    // Запускаем таймер для периодического обновления локации на сервере (каждые 5 минут)
    _startLocationUpdateTimer();
  }
  
  // Отслеживание lifecycle приложения для обновления локации при возврате в foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      print('MapScreen: App resumed, updating location if sharing is enabled');
      // Обновляем локацию при возврате приложения в foreground
      if (_locationSharingEnabled && _currentPosition != null) {
        _updateLocationOnServer(_currentPosition!);
      } else if (_locationSharingEnabled) {
        // Если локация еще не получена, получаем её
        _getCurrentLocation();
      }
    }
  }
  
  // Запускает таймер для периодического обновления локации
  void _startLocationUpdateTimer() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_locationSharingEnabled && _currentPosition != null) {
        print('MapScreen: Periodic location update (every 5 minutes)');
        _updateLocationOnServer(_currentPosition!);
      }
    });
  }
  
  // Обновляет локацию на сервере (вынесено в отдельный метод для переиспользования)
  Future<void> _updateLocationOnServer(geo.Position position) async {
    if (!_locationSharingEnabled) {
      print('MapScreen: ⚠️ Location sharing is disabled, not updating server');
      return;
    }
    
    try {
      print('MapScreen: Attempting to update location on server: ${position.latitude}, ${position.longitude}');
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken != null) {
        _apiService.setAccessToken(accessToken);
        await _apiService.updateLocation(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        print('MapScreen: ✅ Successfully updated location on server');
      } else {
        print('MapScreen: ⚠️ No access token available');
      }
    } catch (e) {
      print('MapScreen: ❌ Error updating location on server: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _styleUpdateTimer?.cancel();
    _zoomCheckTimer?.cancel();
    _pulseUpdateTimer?.cancel();
    _locationUpdateTimer?.cancel();
    _pulseAnimationController.dispose();
    _scaleAnimationController.dispose();
    _headerAnimationController.dispose();
    _pageOpenAnimationController.dispose();
    _glowAnimationController.dispose();
    _metaBallsAnimationController.dispose();
    _tabController.dispose();
    super.dispose();
  }
  
  // Метод для получения цвета meta balls эффекта
  Color _getMetaBallColor(double animationValue) {
    // Переход между цветами заката и фиолетовым
    final sunsetColor = const Color(0xFFFF6B35); // Оранжево-красный закат
    final purpleColor = const Color(0xFF9C27B0); // Фиолетовый
    
    return Color.lerp(sunsetColor, purpleColor, animationValue)!;
  }
  
  // Проверяет зум карты и обновляет размер маркера при необходимости
  Future<void> _checkZoomAndUpdateMarker() async {
    if (_mapboxMap == null || _currentPosition == null || _myLocationAnnotationManager == null) {
      return;
    }

    try {
      final cameraState = await _mapboxMap!.getCameraState();
      final newZoom = cameraState.zoom;
      
      // Определяем, нужно ли обновлять размер маркера
      // Обновляем только при переходе через порог zoom 16.0 (50 метров) или при значительном изменении
      final oldNeedsLargeSize = _currentZoom >= 16.0;
      final newNeedsLargeSize = newZoom >= 16.0;
      final zoomDiff = (newZoom - _currentZoom).abs();
      
      // Увеличиваем порог до 1.0 для уменьшения частоты обновлений и устранения лагов
      // Обновляем размер маркера только при переходе через порог или при значительном изменении зума (> 1.0)
      if (oldNeedsLargeSize != newNeedsLargeSize || zoomDiff > 1.0) {
        // Debounce: проверяем, прошло ли достаточно времени с последнего обновления
        final now = DateTime.now();
        if (_lastMarkerUpdateTime != null && 
            now.difference(_lastMarkerUpdateTime!) < _markerUpdateDebounce) {
          return; // Пропускаем обновление, если прошло слишком мало времени
        }
        
        _lastMarkerUpdateTime = now;
        
        setState(() {
          _currentZoom = newZoom;
        });
        
        // Плавная анимация изменения размера
        _scaleAnimationController.forward(from: 0.8).then((_) {
          _scaleAnimationController.forward();
        });
        
        // Обновляем маркер с новым размером
        await _addMyLocationMarker();
        
        // Пульсация запускается только когда маркер выбран (в _onMyLocationMarkerTapped)
        // Не запускаем автоматически при зуме
        
        print('MapScreen: ✅ Marker size updated for zoom: $_currentZoom (large: $newNeedsLargeSize)');
      }
    } catch (e) {
      // Игнорируем ошибки при проверке зума
    }
  }

  Future<void> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _hasLocationPermission = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      setState(() {
        _hasLocationPermission = permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always;
      });

      if (!_hasLocationPermission && permission == LocationPermission.denied) {
        // Показываем диалог с объяснением
        _showLocationPermissionDialog();
      } else if (permission == LocationPermission.deniedForever) {
        // Показываем диалог с предложением открыть настройки
        _showLocationPermissionDeniedForeverDialog();
      }
    } catch (e) {
      print('MapScreen: Error checking location permission: $e');
    }
  }

  Future<void> _loadLocationSharingStatus() async {
    try {
      print('MapScreen: Loading location sharing status...');
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        print('MapScreen: ⚠️ No access token, cannot load location sharing status');
        return;
      }

      _apiService.setAccessToken(accessToken);
      
      // Загружаем настройки локации из API
      final settings = await _apiService.getLocationVisibility();
      
      print('MapScreen: Received location settings: $settings');
      
      setState(() {
        _locationSharingEnabled = settings['location_sharing_enabled'] ?? false;
      });
      
      print('MapScreen: ✅ Loaded location sharing status: $_locationSharingEnabled');
    } catch (e) {
      print('MapScreen: ❌ Error loading location sharing status: $e');
    }
  }

  void _showLocationPermissionDialog() {
    final messages = [
      "Oops, you're somewhere... but where exactly is a secret 🤫",
      "Looks like you're a ninja. Location is hidden 🥷",
      "GPS is on vacation. Try again later?",
      "Location is playing hide and seek 🙈",
      "You're invisible! Enable location so friends can find you",
    ];
    final message = messages[DateTime.now().millisecond % messages.length];
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => _AnimatedLocationDialog(
        icon: EvaIcons.mapOutline,
        iconColor: const Color(0xFF0095F6),
        title: 'Location Access',
        message: message,
        description: 'Let\'s find you on the map! We need location access 📍',
        primaryButtonText: 'Grant Access',
        secondaryButtonText: 'Maybe Later',
        onPrimaryPressed: () async {
          Navigator.of(context).pop();
          final permission = await Geolocator.requestPermission();
          setState(() {
            _hasLocationPermission = permission == LocationPermission.whileInUse ||
                permission == LocationPermission.always;
          });
          if (_hasLocationPermission) {
            _getCurrentLocation();
          }
        },
        onSecondaryPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showLocationPermissionDeniedForeverDialog() {
    final messages = [
      "You're a mystery on the map",
      "Location: unknown",
      "Coordinates got stuck on the way",
      "Where are you? 🤔",
      "GPS is being shy today 😊",
    ];
    final message = messages[DateTime.now().millisecond % messages.length];
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => _AnimatedLocationDialog(
        icon: EvaIcons.settingsOutline,
        iconColor: const Color(0xFF0095F6),
        title: 'Location Settings',
        message: message,
        description: 'Location access was denied. Enable it in app settings to share your location with friends!',
        primaryButtonText: 'Open Settings',
        secondaryButtonText: 'Cancel',
        onPrimaryPressed: () async {
          Navigator.of(context).pop();
          await Geolocator.openAppSettings();
        },
        onSecondaryPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
  
  // Показывает красивое уведомление загрузки с glow эффектом
  void _showLoadingNotification(String message) {
    // Если уведомление уже показывается, обновляем его
    if (_loadingNotificationOverlay != null) {
      _loadingNotificationOverlay!.markNeedsBuild();
      return;
    }
    
    // Создаем overlay entry для показа уведомления поверх карты
    final overlay = Overlay.of(context);
    
    _loadingNotificationOverlay = OverlayEntry(
      builder: (context) => _LoadingNotification(
        message: message,
        onDismiss: () {
          if (_loadingNotificationOverlay != null && _loadingNotificationOverlay!.mounted) {
            _loadingNotificationOverlay!.remove();
            _loadingNotificationOverlay = null;
          }
        },
      ),
    );
    
    overlay.insert(_loadingNotificationOverlay!);
  }
  
  // Скрывает уведомление загрузки
  void _hideLoadingNotification() {
    if (_loadingNotificationOverlay != null && _loadingNotificationOverlay!.mounted) {
      _loadingNotificationOverlay!.remove();
      _loadingNotificationOverlay = null;
    }
  }
  
  // Показывает красивое уведомление об обновлении геолокации с glow эффектом
  void _showLocationUpdatedNotification() {
    // Если уведомление уже показывается, не создаем новое
    if (_locationNotificationOverlay != null) {
      return;
    }
    
    // Создаем overlay entry для показа уведомления поверх карты
    final overlay = Overlay.of(context);
    
    _locationNotificationOverlay = OverlayEntry(
      builder: (context) => _LocationUpdatedNotification(
        initialState: _LocationNotificationState.updating,
        onDismiss: () {
          if (_locationNotificationOverlay != null && _locationNotificationOverlay!.mounted) {
            _locationNotificationOverlay!.remove();
            _locationNotificationOverlay = null;
          }
        },
      ),
    );
    
    overlay.insert(_locationNotificationOverlay!);
    
    // Обновляем состояние уведомления через небольшие задержки
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_locationNotificationOverlay != null && _locationNotificationOverlay!.mounted) {
        _locationNotificationOverlay!.markNeedsBuild();
      }
    });
    
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (_locationNotificationOverlay != null && _locationNotificationOverlay!.mounted) {
        _locationNotificationOverlay!.markNeedsBuild();
      }
    });
  }

  // Получает случайное дружелюбное сообщение об ошибке геолокации
  String _getRandomLocationErrorMessage(String errorType) {
    final messages = {
      'denied': [
        "Oops, you're somewhere... but where exactly is a secret 🤫",
        "Looks like you're a ninja. Location is hidden 🥷",
        "GPS is on vacation. Try again later?",
        "Location is playing hide and seek 🙈",
        "You're invisible! Enable location so friends can find you",
      ],
      'deniedForever': [
        "You're a mystery on the map",
        "Location: unknown",
        "Coordinates got stuck on the way",
        "Where are you? 🤔",
        "GPS is being shy today 😊",
      ],
      'serviceDisabled': [
        "GPS is on vacation. Try again later?",
        "Location services are playing hide and seek 🙈",
        "Let us know where you are! Enable location in settings ✨",
        "Without location, we're like blind kittens 🐱",
        "Want friends to know where you're hanging out? Allow access!",
      ],
      'timeout': [
        "GPS is thinking a bit... Let's wait together?",
        "Satellites got lost. Or did you? 🛰️",
        "Signal is wandering somewhere. Try again!",
        "Coordinates are being shy today 😊",
        "Maps are loading... Or is the world around you moving? 🌍",
      ],
      'error': [
        "Something went wrong with location. Let's try again!",
        "Location is being tricky today. One more try?",
        "Oops! Location service hiccuped. Try again?",
        "Location got confused. Let's help it out!",
        "GPS needs a moment. We'll wait!",
      ],
    };
    
    final typeMessages = messages[errorType] ?? messages['error']!;
    return typeMessages[DateTime.now().millisecond % typeMessages.length];
  }
  
  void _showLocationServiceDisabledDialog() {
    final message = _getRandomLocationErrorMessage('serviceDisabled');
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => _AnimatedLocationDialog(
        icon: EvaIcons.navigation2Outline,
        iconColor: const Color(0xFF0095F6),
        title: 'Location Services',
        message: message,
        description: 'Location services are disabled on your device. Enable them in system settings to use geo features!',
        primaryButtonText: 'Open Settings',
        secondaryButtonText: 'Maybe Later',
        onPrimaryPressed: () async {
          Navigator.of(context).pop();
          await Geolocator.openLocationSettings();
        },
        onSecondaryPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
  
  void _showLocationErrorDialog(String errorType, {String? customMessage}) {
    final message = customMessage ?? _getRandomLocationErrorMessage(errorType);
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => _AnimatedLocationDialog(
        icon: EvaIcons.alertCircleOutline,
        iconColor: const Color(0xFFFF6B6B),
        title: 'Location Issue',
        message: message,
        description: null,
        primaryButtonText: 'Try Again',
        secondaryButtonText: null,
        onPrimaryPressed: () {
          Navigator.of(context).pop();
          // Попробуем получить локацию снова
          _getCurrentLocation();
        },
        onSecondaryPressed: null,
      ),
    );
  }

  Future<void> _toggleLocationSharing() async {
    if (!_hasLocationPermission) {
      _showLocationPermissionDialog();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      
      final newValue = !_locationSharingEnabled;
      print('MapScreen: Toggling location sharing to: $newValue');
      await _apiService.setLocationSharing(newValue);
      
      setState(() {
        _locationSharingEnabled = newValue;
      });
      
      // Обновляем локацию, если включаем sharing
      if (newValue && _currentPosition != null) {
        print('MapScreen: Location sharing enabled, updating location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
        await _updateLocationOnServer(_currentPosition!);
        // Перезапускаем таймер периодического обновления
        _startLocationUpdateTimer();
      } else if (!newValue) {
        // Останавливаем таймер, если location sharing отключен
        _locationUpdateTimer?.cancel();
      }

      if (mounted) {
        AppNotification.showSuccess(
          context,
          newValue
              ? 'Location sharing enabled'
              : 'Location sharing disabled',
        );
      }
    } catch (e) {
      print('MapScreen: Error toggling location sharing: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Error: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _initializeMap() async {
    // Mapbox будет инициализирован при создании виджета
    setState(() {
      _isMapReady = true;
    });
  }

  // Определяет время суток и возвращает соответствующий lightPreset
  String _getTimeOfDayLightPreset() {
    final now = DateTime.now();
    final hour = now.hour;
    
    // Ночь: 20:00 - 06:00
    if (hour >= 20 || hour < 6) {
      return 'night';
    }
    // Закат/Рассвет: 06:00 - 08:00 и 18:00 - 20:00
    else if ((hour >= 6 && hour < 8) || (hour >= 18 && hour < 20)) {
      return 'dusk';
    }
    // День: 08:00 - 18:00
    else {
      return 'day';
    }
  }

  // Обновляет стиль карты в зависимости от времени суток
  Future<void> _updateMapStyleForTimeOfDay() async {
    if (_mapboxMap == null) return;

    try {
      final lightPreset = _getTimeOfDayLightPreset();
      print('MapScreen: Updating map style to lightPreset: $lightPreset');

      // Получаем стиль карты через свойство style
      final style = _mapboxMap!.style;
      
      // Устанавливаем lightPreset для Mapbox Standard
      // Import ID для Mapbox Standard - "basemap"
      await style.setStyleImportConfigProperty(
        'basemap', // Import ID для Mapbox Standard
        'lightPreset',
        lightPreset,
      );

      print('MapScreen: ✅ Map style updated to $lightPreset');
    } catch (e) {
      print('MapScreen: Error updating map style: $e');
      // Если не удалось установить lightPreset, возможно стиль еще не загружен
      // или используется не Mapbox Standard стиль
    }
  }

  // Переключает режим карты между 2D и 3D
  Future<void> _toggle3DMode() async {
    if (_mapboxMap == null) return;

    setState(() {
      _is3DMode = !_is3DMode;
    });

    try {
      // Получаем текущие параметры камеры
      final currentCamera = await _mapboxMap!.getCameraState();
      
      // Переключаем pitch (наклон камеры)
      // 0 = 2D вид сверху, 60 = 3D вид с наклоном
      final newPitch = _is3DMode ? 60.0 : 0.0;

      // Анимированно переключаем режим
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: currentCamera.center,
          zoom: currentCamera.zoom,
          pitch: newPitch,
          bearing: currentCamera.bearing,
        ),
        MapAnimationOptions(duration: 800, startDelay: 0),
      );
    } catch (e) {
      print('MapScreen: Error toggling 3D mode: $e');
      // Откатываем изменение состояния при ошибке
      setState(() {
        _is3DMode = !_is3DMode;
      });
    }
  }

  // Обработчик нажатия на маркер моей локации
  Future<void> _onMyLocationMarkerTapped() async {
    if (_mapboxMap == null || _currentPosition == null) return;
    
    // Получаем информацию о текущем пользователе
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    
    // Устанавливаем выбранный маркер для отображения информации в заголовке
    setState(() {
      _selectedMarker = {
        'type': 'me',
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'username': user?.username ?? 'unknown',
        'lastSeen': DateTime.now(), // Для своего маркера показываем текущее время
        'isOnline': true, // Свой маркер всегда считается онлайн
      };
    });
    
    // Запускаем анимацию появления в заголовке
    _headerAnimationController.forward(from: 0.0);
    
    // Анимация нажатия (масштабирование)
    _scaleAnimationController.forward(from: 0.9).then((_) {
      _scaleAnimationController.reverse();
    });
    

    try {
      // Делаем зум к местоположению пользователя
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              _currentPosition!.longitude,
              _currentPosition!.latitude,
            ),
          ),
          zoom: 18.0, // Близкий зум при нажатии на маркер
          pitch: 60.0, // Сохраняем 3D режим
        ),
        MapAnimationOptions(
          duration: 1500, // Плавная анимация приближения
          startDelay: 0,
        ),
      );
      print('MapScreen: ✅ Zoomed to my location on marker tap');
    } catch (e) {
      print('MapScreen: Error zooming to location on marker tap: $e');
    }
  }

  // Обработчик нажатия на кнопку "Посмотреть"
  void _onViewButtonTapped() {
    if (_selectedMarker == null) return;

    final markerType = _selectedMarker!['type'];
    if (markerType == 'geo_post') {
      // Открываем viewer для гео-поста
      final postId = _selectedMarker!['postId'] as String?;
      if (postId != null) {
        final post = _geoPosts.firstWhere(
          (p) => p.id == postId,
          orElse: () => _geoPosts.first,
        );
        
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => GeoStoriesViewer(
              initialPost: post,
              posts: _geoPosts,
            ),
          ),
        );
      }
    } else if (markerType == 'me') {
      // Для своего маркера можно показать профиль или ничего
      print('View my location');
    } else if (markerType == 'friend') {
      // Открываем профиль друга
      final friendId = _selectedMarker!['friendId'] as String?;
      if (friendId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: friendId),
          ),
        );
      }
    }
  }

  // Обработчик расфокуса маркера
  void _onDeselectMarker() {
    setState(() {
      _selectedMarker = null;
    });
    // Возвращаем камеру к обычному виду (если был zoom)
    // Можно добавить анимацию возврата камеры
  }

  // Обработчик нажатия на кнопку геолокации для обновления локации
  Future<void> _onLocationUpdateButtonTapped() async {
    try {
      print('MapScreen: Location update button tapped');
      
      // Проверяем разрешения
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showLocationServiceDisabledDialog();
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted && _locationSharingEnabled) {
            _showLocationPermissionDialog();
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted && _locationSharingEnabled) {
          _showLocationPermissionDeniedForeverDialog();
        }
        return;
      }

      // Показываем индикатор загрузки только если не в режиме friends
      if (mounted && _currentTabIndex != 0) {
        AppNotification.show(
          context,
          message: 'Updating location...',
          type: AppNotificationType.loading,
          duration: const Duration(seconds: 2),
        );
      }

      // Получаем текущую позицию
      geo.Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Location request timed out');
        },
      );

      // Обновляем состояние
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _hasLocationPermission = true;
        });
      }

      // Показываем уведомление "Updating location..."
      if (mounted && _currentTabIndex == 0) {
        _showLocationUpdatedNotification();
      }

      // Обновляем маркер на карте
      if (_myLocationAnnotationManager != null && mounted) {
        await _addMyLocationMarker();
      }

      // Обновляем локацию на сервере
      await _updateLocationOnServer(position);

      // Обновляем список друзей (чтобы увидеть обновленную локацию)
      if (mounted) {
        await _loadFriendsLocations();
      }

      // Показываем успешное сообщение
      if (mounted) {
        if (_currentTabIndex == 0) {
          // В режиме friends уведомление само обновится через задержки
        } else {
          // В других режимах показываем обычный snackbar
          AppNotification.hide();
          AppNotification.showSuccess(
            context,
            'Location updated!',
          );
        }
      }

      print('MapScreen: ✅ Location updated successfully');
    } catch (e) {
      print('MapScreen: ❌ Error updating location: $e');
      
      if (mounted) {
        AppNotification.hide();
        
        // Определяем тип ошибки
        String errorType = 'error';
        if (e.toString().contains('timeout') || e.toString().contains('TIMEOUT')) {
          errorType = 'timeout';
        } else if (e.toString().contains('permission') || e.toString().contains('denied')) {
          errorType = 'denied';
        } else if (e.toString().contains('service') || e.toString().contains('disabled')) {
          errorType = 'serviceDisabled';
        }
        
        _showLocationErrorDialog(errorType);
      }
    }
  }

  // Обработчик нажатия на кнопку "+" для создания гео-поста
  Future<void> _onPlusButtonTapped() async {
    try {
      // Проверяем разрешения на камеру и геолокацию
      final cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        final cameraResult = await Permission.camera.request();
        if (!cameraResult.isGranted) {
          if (mounted) {
            AppNotification.showError(
              context,
              'Необходимо разрешение на использование камеры',
            );
          }
          return;
        }
      }

      // Получаем текущую геолокацию
      if (_currentPosition == null) {
        // Если локация еще не получена, пытаемся получить
        await _getCurrentLocation();
      }

      if (_currentPosition != null) {
        // Открываем камеру в режиме гео-поста
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CameraScreen(
              isGeoPost: true,
              latitude: _currentPosition!.latitude,
              longitude: _currentPosition!.longitude,
            ),
          ),
        );

        // После возврата из камеры обновляем гео-посты
        if (mounted) {
          await _loadGeoPosts();
        }
      } else {
        // Если локация недоступна, показываем ошибку
        if (mounted) {
          AppNotification.showError(
            context,
            'Не удалось получить вашу геолокацию. Пожалуйста, включите GPS.',
            duration: const Duration(seconds: 3),
          );
        }
      }
    } catch (e) {
      print('MapScreen: Error opening camera for geo post: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Ошибка открытия камеры: $e',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  // Показывает мою локацию на карте (с проверкой разрешений)
  Future<void> _showMyLocationOnMap() async {
    try {
      // Проверяем, включена ли служба геолокации
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text(
                'Location Services Disabled',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'Please enable location services in your device settings to show your location on the map.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK', style: TextStyle(color: Color(0xFF0095F6))),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Проверяем разрешения
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        // Запрашиваем разрешение
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            _showLocationPermissionDialog();
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showLocationPermissionDeniedForeverDialog();
        }
        return;
      }

      // Если разрешения есть, получаем локацию и показываем на карте
      setState(() {
        _isLoadingLocation = true;
        if (mounted) {
          _showLoadingNotification('Getting your location...');
        }
        _hasLocationPermission = true;
      });

      // Получаем текущую позицию
      geo.Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
        _hideLoadingNotification();
      });

      // Добавляем/обновляем маркер моей локации (только если manager уже создан)
      // Если вызывается из onMapCreated, маркер будет добавлен там
      if (_myLocationAnnotationManager != null) {
        _addMyLocationMarker();
      }

      // Обновляем локацию на сервере, если location sharing включен
      await _updateLocationOnServer(position);

      // Перемещаем карту к текущей позиции с анимацией приближения
      if (_mapboxMap != null && _currentPosition != null) {
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(
                _currentPosition!.longitude,
                _currentPosition!.latitude,
              ),
            ),
            zoom: 17.5, // Близкий zoom для детального показа локации
            pitch: 60.0, // Сохраняем 3D режим
          ),
          MapAnimationOptions(
            duration: 2500, // Плавная анимация приближения
            startDelay: 0,
          ),
        );
      }
    } catch (e) {
      print('MapScreen: Error showing my location: $e');
      setState(() {
        _isLoadingLocation = false;
        _hideLoadingNotification();
      });
      
      // Останавливаем glow анимацию плавно
      _glowAnimationController.animateTo(0.0, duration: const Duration(milliseconds: 1000));
      
      if (mounted) {
        // Определяем тип ошибки
        String errorType = 'error';
        String? customMessage;
        
        if (e.toString().contains('timeout') || e.toString().contains('TIMEOUT')) {
          errorType = 'timeout';
        } else if (e.toString().contains('permission') || e.toString().contains('denied')) {
          errorType = 'denied';
        } else if (e.toString().contains('service') || e.toString().contains('disabled')) {
          errorType = 'serviceDisabled';
        }
        
        _showLocationErrorDialog(errorType, customMessage: customMessage);
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Проверяем разрешения
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoadingLocation = false;
        _hideLoadingNotification();
        });
        if (mounted && _locationSharingEnabled) {
          _showLocationServiceDisabledDialog();
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoadingLocation = false;
        _hideLoadingNotification();
          });
          if (mounted && _locationSharingEnabled) {
            _showLocationPermissionDialog();
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoadingLocation = false;
        _hideLoadingNotification();
        });
        if (mounted && _locationSharingEnabled) {
          _showLocationPermissionDeniedForeverDialog();
        }
        return;
      }

      // Получаем текущую позицию
      geo.Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
        _hideLoadingNotification();
        _hasLocationPermission = true;
      });

      // Добавляем/обновляем маркер моей локации (только если manager уже создан)
      // Если вызывается из onMapCreated, маркер будет добавлен там
      if (_myLocationAnnotationManager != null) {
        _addMyLocationMarker();
      }

      // Обновляем локацию на сервере, если location sharing включен
      await _updateLocationOnServer(position);

      // Перемещаем карту к текущей позиции с анимацией приближения
      if (_mapboxMap != null && _currentPosition != null) {
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(
                _currentPosition!.longitude,
                _currentPosition!.latitude,
              ),
            ),
            zoom: 15.5, // Увеличенный zoom для лучшего обзора
            pitch: 60.0, // Всегда 3D режим
          ),
          MapAnimationOptions(
            duration: 2000, // Плавная анимация приближения
            startDelay: 0,
          ),
        );
      }
    } catch (e) {
      print('MapScreen: Error getting location: $e');
      setState(() {
        _isLoadingLocation = false;
        _hideLoadingNotification();
      });
      
      // Останавливаем glow анимацию плавно
      _glowAnimationController.animateTo(0.0, duration: const Duration(milliseconds: 1000));
    }
  }

  Future<void> _loadGeoPosts() async {
    if (_mapboxMap == null || _currentPosition == null) return;

    setState(() {
      _isLoadingGeoPosts = true;
      if (mounted) {
        _showLoadingNotification('Loading geo posts...');
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        setState(() {
          _isLoadingGeoPosts = false;
        _hideLoadingNotification();
        });
        return;
      }

      _apiService.setAccessToken(accessToken);

      // Получаем границы видимой области карты
      // TODO: Реализовать получение границ карты через Mapbox API
      // Пока используем приблизительные границы вокруг текущей позиции
      final lat = _currentPosition?.latitude ?? 0.0;
      final lng = _currentPosition?.longitude ?? 0.0;
      final delta = 0.1; // Примерно 10 км

      // Загружаем geo-posts в видимой области
      final geoPosts = await _apiService.getGeoPosts(
        swLat: lat - delta,
        swLng: lng - delta,
        neLat: lat + delta,
        neLng: lng + delta,
      );

      // Фильтруем посты по expires_at (на клиенте, так как backend уже фильтрует)
      final now = DateTime.now();
      final activeGeoPosts = geoPosts.where((post) {
        if (post.expiresAt == null) return true; // Обычные посты без истечения
        return post.expiresAt!.isAfter(now); // Гео-посты должны быть активными
      }).toList();

      setState(() {
        _geoPosts = activeGeoPosts;
        _isLoadingGeoPosts = false;
        _hideLoadingNotification();
      });

      // Добавляем маркеры на карту
      _addGeoPostMarkers();
    } catch (e) {
      print('MapScreen: Error loading geo posts: $e');
      setState(() {
        _isLoadingGeoPosts = false;
        _hideLoadingNotification();
      });
    }
  }

  Future<void> _loadFriendsLocations() async {
    if (!mounted) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);

      final friendsLocations = await _apiService.getFriendsLocations();

      print('MapScreen: Loaded ${friendsLocations.length} friends locations');
      for (var friend in friendsLocations) {
        print('MapScreen: Friend ${friend['username']} at ${friend['latitude']}, ${friend['longitude']}');
      }

      if (!mounted) return;
      setState(() {
        _friendsLocations = friendsLocations;
      });

      // Добавляем маркеры друзей на карту
      if (mounted) {
        _addFriendMarkers();
      }
    } catch (e) {
      print('MapScreen: Error loading friends locations: $e');
      if (mounted) {
        setState(() {
          _friendsLocations = [];
        });
      }
    }
  }

  Future<void> _addGeoPostMarkers() async {
    if (_mapboxMap == null || _geoPostsAnnotationManager == null) return;
    if (_geoPosts.isEmpty) return;

    try {
      // Удаляем старые маркеры
      if (_geoPostAnnotationIds.isNotEmpty) {
        await _geoPostsAnnotationManager!.deleteAll();
        _geoPostAnnotationIds.clear();
      }

      // Создаем маркеры для каждого geo-post
      final annotations = <PointAnnotationOptions>[];
      
      // Вычисляем размер маркера в зависимости от зума
      final baseSize = 120.0;
      final markerSize = _currentZoom >= 16.0 
          ? baseSize * 1.4
          : baseSize;
      
      for (final post in _geoPosts) {
        if (post.latitude != null && post.longitude != null) {
          // Создаем маркер с аватаром пользователя для каждого поста
          final avatarUrl = post.user?.avatarUrl;
          final isSelected = _selectedMarker != null && 
              _selectedMarker!['type'] == 'geo_post' &&
              _selectedMarker!['postId'] == post.id;
          
          final markerImage = await _createMyLocationMarkerImage(
            avatarUrl: avatarUrl,
            size: markerSize.round(),
            isOnline: null, // Для гео-постов не показываем статус
            lastSeen: post.createdAt,
            isSelected: isSelected,
          );
          
          annotations.add(
            PointAnnotationOptions(
              geometry: Point(
                coordinates: Position(
                  post.longitude!,
                  post.latitude!,
                ),
              ),
              image: markerImage,
              iconSize: 1.0,
              iconAnchor: IconAnchor.BOTTOM,
            ),
          );
        }
      }

      if (annotations.isNotEmpty) {
        final createdAnnotations = await _geoPostsAnnotationManager!.createMulti(annotations);
        for (int i = 0; i < createdAnnotations.length; i++) {
          final annotation = createdAnnotations[i];
          final id = annotation?.id;
          if (id != null && id.isNotEmpty) {
            _geoPostAnnotationIds.add(id);
            
            // Сохраняем координаты маркера для проверки нажатий
            if (i < _geoPosts.length) {
              final post = _geoPosts[i];
              if (post.latitude != null && post.longitude != null) {
                _geoPostMarkerCoords[id] = {
                  'lat': post.latitude!,
                  'lng': post.longitude!,
                };
              }
            }
          }
        }
        print('MapScreen: Added ${createdAnnotations.length} geo-post markers');
      }
    } catch (e) {
      print('MapScreen: Error adding geo-post markers: $e');
    }
  }

  Future<void> _addFriendMarkers() async {
    print('MapScreen: _addFriendMarkers called');
    print('MapScreen: _mapboxMap is null: ${_mapboxMap == null}');
    print('MapScreen: _friendsAnnotationManager is null: ${_friendsAnnotationManager == null}');
    print('MapScreen: _friendsLocations count: ${_friendsLocations.length}');
    
    if (_mapboxMap == null || _friendsAnnotationManager == null) {
      print('MapScreen: ⚠️ Cannot add friend markers - map or manager is null');
      return;
    }
    if (_friendsLocations.isEmpty) {
      print('MapScreen: ⚠️ No friends locations to display');
      return;
    }

    try {
      // Удаляем старые маркеры
      if (_friendAnnotationIds.isNotEmpty) {
        print('MapScreen: Deleting ${_friendAnnotationIds.length} old friend markers');
        await _friendsAnnotationManager!.deleteAll();
        _friendAnnotationIds.clear();
        _friendMarkerCoords.clear();
      }

      // Создаем маркеры для каждого друга в том же стиле, что и свой маркер
      final annotations = <PointAnnotationOptions>[];
      
      // Вычисляем размер маркера в зависимости от зума (как для своего маркера)
      final baseSize = 120.0;
      final markerSize = _currentZoom >= 16.0 
          ? baseSize * 1.4
          : baseSize;
      
      print('MapScreen: Creating markers for ${_friendsLocations.length} friends');
      for (int i = 0; i < _friendsLocations.length; i++) {
        final friend = _friendsLocations[i];
        final lat = friend['latitude'];
        final lng = friend['longitude'];
        final avatarUrl = friend['avatar_url'] as String?;
        final lastLocationUpdatedAt = friend['last_location_updated_at'] as String?;
        
        print('MapScreen: Friend $i: ${friend['username']}, lat: $lat (${lat.runtimeType}), lng: $lng (${lng.runtimeType}), avatar: $avatarUrl');
        
        // Преобразуем в double если нужно
        double? latDouble;
        double? lngDouble;
        
        if (lat is double) {
          latDouble = lat;
        } else if (lat is int) {
          latDouble = lat.toDouble();
        } else if (lat is String) {
          latDouble = double.tryParse(lat);
        }
        
        if (lng is double) {
          lngDouble = lng;
        } else if (lng is int) {
          lngDouble = lng.toDouble();
        } else if (lng is String) {
          lngDouble = double.tryParse(lng);
        }
        
        if (latDouble != null && lngDouble != null) {
          // Парсим last_location_updated_at для определения статуса
          DateTime? lastSeen;
          bool? isOnline;
          
          if (lastLocationUpdatedAt != null) {
            try {
              lastSeen = DateTime.parse(lastLocationUpdatedAt);
              // Считаем онлайн, если обновление было менее минуты назад
              final now = DateTime.now();
              final difference = now.difference(lastSeen);
              isOnline = difference.inSeconds < 60;
            } catch (e) {
              print('MapScreen: Error parsing last_location_updated_at: $e');
            }
          }
          
          // Проверяем, выбран ли этот маркер
          final isSelected = _selectedMarker != null && 
              _selectedMarker!['type'] == 'friend' &&
              _selectedMarker!['friendId'] == friend['id'];
          
          print('MapScreen: ✅ Creating marker image for ${friend['username']} at $latDouble, $lngDouble');
          
          // Создаем маркер в том же стиле, что и свой маркер
          final friendMarkerImage = await _createMyLocationMarkerImage(
            avatarUrl: avatarUrl,
            size: markerSize.round(),
            isOnline: isOnline,
            lastSeen: lastSeen,
            isSelected: isSelected,
          );
          
          print('MapScreen: ✅ Adding marker for ${friend['username']} at $latDouble, $lngDouble');
          annotations.add(
            PointAnnotationOptions(
              geometry: Point(
                coordinates: Position(lngDouble, latDouble),
              ),
              image: friendMarkerImage,
              iconSize: 1.0,
              iconAnchor: IconAnchor.BOTTOM,
            ),
          );
        } else {
          print('MapScreen: ⚠️ Invalid coordinates for ${friend['username']}: lat=$lat, lng=$lng');
        }
      }

        print('MapScreen: Created ${annotations.length} annotation options');
      
      if (annotations.isNotEmpty) {
        final createdAnnotations = await _friendsAnnotationManager!.createMulti(annotations);
        print('MapScreen: Created ${createdAnnotations.length} annotations on map');
        
        for (int i = 0; i < createdAnnotations.length; i++) {
          final annotation = createdAnnotations[i];
          final id = annotation?.id;
          if (id != null && id.isNotEmpty) {
            _friendAnnotationIds.add(id);
            
            // Сохраняем координаты маркера для проверки нажатий
            if (i < _friendsLocations.length) {
              final friend = _friendsLocations[i];
              final lat = friend['latitude'];
              final lng = friend['longitude'];
              
              double? latDouble;
              double? lngDouble;
              
              if (lat is double) {
                latDouble = lat;
              } else if (lat is int) {
                latDouble = lat.toDouble();
              } else if (lat is String) {
                latDouble = double.tryParse(lat);
              }
              
              if (lng is double) {
                lngDouble = lng;
              } else if (lng is int) {
                lngDouble = lng.toDouble();
              } else if (lng is String) {
                lngDouble = double.tryParse(lng);
              }
              
              if (latDouble != null && lngDouble != null) {
                _friendMarkerCoords[id] = {
                  'lat': latDouble,
                  'lng': lngDouble,
                };
                print('MapScreen: ✅ Saved coordinates for marker $id: $latDouble, $lngDouble');
              }
            }
          } else {
            print('MapScreen: ⚠️ Annotation $i has null or empty id');
          }
        }
        
        // Добавляем обработчик нажатий на маркеры друзей
        try {
          _friendsAnnotationManager!.addOnPointAnnotationClickListener(
            _FriendAnnotationClickListener(
              onTap: (annotation) {
                // Проверяем, что это маркер друга
                if (_friendAnnotationIds.contains(annotation.id)) {
                  print('MapScreen: 🎯 Friend marker tapped! ID: ${annotation.id}');
                  _onFriendMarkerTapped(annotation);
                }
              },
            ),
          );
          print('MapScreen: ✅ Added click listener for friend markers');
        } catch (e) {
          print('MapScreen: ⚠️ Error adding click listener for friend markers: $e');
        }
        
        print('MapScreen: ✅✅✅ Successfully added ${createdAnnotations.length} friend markers');
      } else {
        print('MapScreen: ⚠️ No annotations to add (all coordinates invalid?)');
      }
    } catch (e, stackTrace) {
      print('MapScreen: ❌ Error adding friend markers: $e');
      print('MapScreen: Stack trace: $stackTrace');
    }
  }

  // Добавляет маркер моей локации с аватаркой
  Future<void> _addMyLocationMarker() async {
    print('MapScreen: _addMyLocationMarker called');
    print('MapScreen: _mapboxMap is null: ${_mapboxMap == null}');
    print('MapScreen: _myLocationAnnotationManager is null: ${_myLocationAnnotationManager == null}');
    print('MapScreen: _currentPosition is null: ${_currentPosition == null}');
    
    if (_mapboxMap == null || _myLocationAnnotationManager == null) {
      print('MapScreen: ⚠️ Cannot add marker - map or manager is null');
      return;
    }
    if (_currentPosition == null) {
      print('MapScreen: ⚠️ Cannot add marker - position is null');
      return;
    }

    try {
      print('MapScreen: 📍 Starting to add/update my location marker at ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      
      // Получаем аватарку пользователя
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      final avatarUrl = user?.avatarUrl;
      
      print('MapScreen: 👤 User: ${user?.username}, Avatar URL: $avatarUrl');

      // Вычисляем размер маркера в зависимости от зума
      // При zoom >= 16 (примерно 50 метров) увеличиваем маркер
      final baseSize = 120.0; // Увеличенный базовый размер
      final markerSize = _currentZoom >= 16.0 
          ? baseSize * 1.4 // Увеличиваем на 40% при приближении
          : baseSize;
      
      // Получаем статус пользователя (онлайн/офлайн)
      // Для текущего пользователя считаем, что он онлайн, если карта открыта
      final isOnline = true; // Пользователь онлайн, так как карта открыта
      final lastSeen = DateTime.now();
      
      // Создаем изображение маркера с аватаркой
      // Проверяем, выбран ли маркер для применения пульсации
      final isSelected = _selectedMarker != null && _selectedMarker!['type'] == 'me';
      print('MapScreen: 🎨 Creating marker image with size: $markerSize (zoom: $_currentZoom, selected: $isSelected)...');
      final markerImage = await _createMyLocationMarkerImage(
        avatarUrl: avatarUrl,
        size: markerSize.round(),
        isOnline: isOnline,
        lastSeen: lastSeen,
        isSelected: isSelected,
      );
      print('MapScreen: ✅ Marker image created, size: ${markerImage.length} bytes');

      // Если маркер уже существует, создаем новый перед удалением старого
      // чтобы маркер не исчезал при обновлении
      String? oldMarkerId = _myLocationAnnotationId;

      // Создаем новую аннотацию, если маркера еще нет
      print('MapScreen: 📌 Creating new annotation at ${_currentPosition!.latitude}, ${_currentPosition!.longitude}...');
      final annotation = await _myLocationAnnotationManager!.create(
        PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(
              _currentPosition!.longitude,
              _currentPosition!.latitude,
            ),
          ),
          image: markerImage,
          iconSize: 1.0,
          iconAnchor: IconAnchor.BOTTOM, // Якорь внизу для "хвостика"
        ),
      );

      _myLocationAnnotationId = annotation.id;
      print('MapScreen: ✅✅✅ Successfully added my location marker with ID: ${annotation.id}');
      
      // Удаляем старый маркер только после создания нового, чтобы маркер не исчезал
      // Используем deleteAll, так как у нас только один маркер в этом manager
      // и новый маркер уже создан, поэтому старый можно безопасно удалить
      if (oldMarkerId != null && oldMarkerId != annotation.id) {
        // Небольшая задержка, чтобы новый маркер успел отобразиться
        await Future.delayed(const Duration(milliseconds: 50));
        try {
          // Удаляем все старые маркеры (их должно быть не больше одного)
          // Новый маркер уже создан, поэтому он не будет удален
          await _myLocationAnnotationManager!.deleteAll();
          // После deleteAll нужно пересоздать маркер, так как он тоже был удален
          final newAnnotation = await _myLocationAnnotationManager!.create(
            PointAnnotationOptions(
              geometry: Point(
                coordinates: Position(
                  _currentPosition!.longitude,
                  _currentPosition!.latitude,
                ),
              ),
              image: markerImage,
              iconSize: 1.0,
              iconAnchor: IconAnchor.BOTTOM,
            ),
          );
          _myLocationAnnotationId = newAnnotation.id;
          print('MapScreen: 🗑️ Deleted old marker and recreated with ID: ${newAnnotation.id}');
        } catch (e) {
          print('MapScreen: ⚠️ Error deleting old marker: $e');
          // Если ошибка, оставляем новый маркер как есть
        }
      }
    } catch (e, stackTrace) {
      print('MapScreen: ❌❌❌ Error adding my location marker: $e');
      print('MapScreen: Stack trace: $stackTrace');
    }
  }

  // Создает изображение маркера с аватаркой пользователя в стиле Geo
  Future<Uint8List> _createMyLocationMarkerImage({
    String? avatarUrl,
    required int size,
    bool? isOnline,
    DateTime? lastSeen,
    bool isSelected = false,
  }) async {
    // Размеры для маркера Geo (значительно увеличенные размеры)
    // Применяем анимацию масштабирования для плавного изменения размера
    double scaleFactor = 1.0;
    
    try {
      scaleFactor = _scaleAnimation.value > 0 ? _scaleAnimation.value : 1.0;
    } catch (e) {
      // Анимация еще не инициализирована, используем значение по умолчанию
      scaleFactor = 1.0;
    }
    
    final combinedScale = scaleFactor;
    
    final markerWidth = (size * 1.8 * combinedScale).toDouble(); // Увеличенная ширина с анимацией
    final markerHeight = (size * 2.1 * combinedScale).round().toDouble(); // Увеличенная высота с анимацией
    
    // Размер аватарки внутри маркера (круглая) - адаптивный размер в зависимости от зума
    final avatarSizeRatio = _currentZoom >= 16.0 ? 1.15 : 1.3; // Увеличенный размер (было 1.0 и 0.85)
    final avatarSize = (size * avatarSizeRatio * combinedScale).round();
    final avatarCenterX = markerWidth / 2.0;
    final avatarCenterY = markerHeight * 0.42; // Позиция аватарки выше центра (42% от высоты вместо 50%)

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Используем GeoMarkerClipper для создания формы маркера
    final clipper = GeoMarkerClipper();
    final markerPath = clipper.getClip(ui.Size(markerWidth, markerHeight));
    
    // Рисуем свечение (glow) вокруг маркера
    final glowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawPath(markerPath, glowPaint);
    
    // Рисуем фон маркера с градиентом (от темно-серого к черному)
    final gradient = ui.Gradient.linear(
      Offset(0, 0),
      Offset(markerWidth, markerHeight),
      [
        const Color(0xFF1A1A1A), // Темно-серый
        Colors.black, // Черный
      ],
    );
    final backgroundPaint = Paint()..shader = gradient;
    canvas.drawPath(markerPath, backgroundPaint);
    
    // Рисуем тень внутри маркера для глубины
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(markerPath, shadowPaint);
    
    // Загружаем и рисуем аватарку
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      try {
        // Загружаем изображение из сети через http
        final response = await http.get(Uri.parse(avatarUrl));
        
        if (response.statusCode == 200) {
          final codec = await ui.instantiateImageCodec(response.bodyBytes);
          final frame = await codec.getNextFrame();
          final avatarImage = frame.image;
          
          // Создаем круглую маску для аватарки с отступом
          final avatarRect = Rect.fromCenter(
            center: Offset(avatarCenterX, avatarCenterY),
            width: avatarSize.toDouble(),
            height: avatarSize.toDouble(),
          );
          final avatarPath = Path()
            ..addOval(avatarRect);
          
          // Рисуем размытый фон под аватаркой для лучшей читаемости
          final blurPaint = Paint()
            ..color = Colors.black.withOpacity(0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
          canvas.drawOval(avatarRect, blurPaint);
          
          canvas.save();
          canvas.clipPath(avatarPath);
          
          // Рисуем аватарку
          canvas.drawImageRect(
            avatarImage,
            Rect.fromLTWH(0, 0, avatarImage.width.toDouble(), avatarImage.height.toDouble()),
            avatarRect,
            Paint(),
          );
          
          canvas.restore();
          
          // Рисуем индикатор статуса (кольцо вокруг аватарки)
          final statusColor = _getStatusColor(isOnline, lastSeen);
          final statusRingWidth = size * 0.06; // Толщина кольца
          final statusRingRadius = avatarSize / 2.0 + statusRingWidth / 2.0;
          
          final statusPaint = Paint()
            ..color = statusColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = statusRingWidth;
          
          canvas.drawCircle(
            Offset(avatarCenterX, avatarCenterY),
            statusRingRadius,
            statusPaint,
          );
          
          // Если онлайн, добавляем пульсирующий эффект (внешнее кольцо)
          if (isOnline == true) {
            final pulsePaint = Paint()
              ..color = statusColor.withOpacity(0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = statusRingWidth * 0.5;
            
            canvas.drawCircle(
              Offset(avatarCenterX, avatarCenterY),
              statusRingRadius + statusRingWidth * 0.5,
              pulsePaint,
            );
          }
          
          avatarImage.dispose();
        } else {
          // Если не удалось загрузить, рисуем иконку по умолчанию
          _drawDefaultAvatar(canvas, avatarCenterX, avatarCenterY, avatarSize.toDouble());
          // Рисуем индикатор статуса для дефолтной аватарки
          _drawStatusIndicator(canvas, avatarCenterX, avatarCenterY, avatarSize.toDouble(), isOnline, lastSeen);
        }
      } catch (e) {
        print('MapScreen: Error loading avatar image: $e');
        // Если не удалось загрузить, рисуем иконку по умолчанию
        _drawDefaultAvatar(canvas, avatarCenterX, avatarCenterY, avatarSize.toDouble());
        // Рисуем индикатор статуса для дефолтной аватарки
        _drawStatusIndicator(canvas, avatarCenterX, avatarCenterY, avatarSize.toDouble(), isOnline, lastSeen);
      }
    } else {
      // Рисуем иконку по умолчанию
      _drawDefaultAvatar(canvas, avatarCenterX, avatarCenterY, avatarSize.toDouble());
      // Рисуем индикатор статуса для дефолтной аватарки
      _drawStatusIndicator(canvas, avatarCenterX, avatarCenterY, avatarSize.toDouble(), isOnline, lastSeen);
    }
    
    final picture = recorder.endRecording();
    final imageHeight = markerHeight.round();
    print('MapScreen: Creating Geo marker image with size: ${markerWidth.round()}x$imageHeight');
    final image = await picture.toImage(markerWidth.round(), imageHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) {
      print('MapScreen: ❌ Failed to convert image to bytes');
      image.dispose();
      picture.dispose();
      throw Exception('Failed to create marker image');
    }
    
    final imageBytes = byteData.buffer.asUint8List();
    print('MapScreen: ✅ Geo marker image created successfully, size: ${imageBytes.length} bytes, dimensions: ${markerWidth.round()}x$imageHeight');
    
    image.dispose();
    picture.dispose();
    
    return imageBytes;
  }

  // Определяет цвет индикатора статуса
  Color _getStatusColor(bool? isOnline, DateTime? lastSeen) {
    if (isOnline == true) {
      return Colors.green; // Зеленое - онлайн/активен
    }
    
    if (lastSeen != null) {
      final now = DateTime.now();
      final difference = now.difference(lastSeen);
      
      if (difference.inMinutes < 5) {
        return Colors.green; // Зеленое - недавно был онлайн
      } else if (difference.inHours < 1) {
        return Colors.grey; // Серое - недавно был онлайн
      } else {
        return Colors.red; // Красное - офлайн давно
      }
    }
    
    return Colors.grey; // По умолчанию серое
  }
  
  // Рисует индикатор статуса вокруг аватарки
  void _drawStatusIndicator(Canvas canvas, double centerX, double centerY, double avatarSize, bool? isOnline, DateTime? lastSeen) {
    final statusColor = _getStatusColor(isOnline, lastSeen);
    final statusRingWidth = avatarSize * 0.06; // Толщина кольца
    final statusRingRadius = avatarSize / 2.0 + statusRingWidth / 2.0;
    
    final statusPaint = Paint()
      ..color = statusColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = statusRingWidth;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      statusRingRadius,
      statusPaint,
    );
    
    // Если онлайн, добавляем пульсирующий эффект (внешнее кольцо)
    if (isOnline == true) {
      final pulsePaint = Paint()
        ..color = statusColor.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = statusRingWidth * 0.5;
      
      canvas.drawCircle(
        Offset(centerX, centerY),
        statusRingRadius + statusRingWidth * 0.5,
        pulsePaint,
      );
    }
  }
  
  // Рисует иконку пользователя по умолчанию (круглая)
  void _drawDefaultAvatar(Canvas canvas, double centerX, double centerY, double size) {
    final avatarRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: size.toDouble(),
      height: size.toDouble(),
    );
    
    // Рисуем круглый фон
    final paint = Paint()..color = const Color(0xFF0095F6);
    canvas.drawOval(avatarRect, paint);
    
    // Рисуем иконку человека
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    // Голова (круг)
    canvas.drawCircle(
      Offset(centerX, centerY - size * 0.15),
      size * 0.2,
      iconPaint,
    );
    
    // Тело (прямоугольник со скругленными углами)
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY + size * 0.2),
        width: size * 0.4,
        height: size * 0.5,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(bodyRect, iconPaint);
  }

  // Создает простое изображение маркера заданного цвета
  Future<Uint8List> _createMarkerImage({required Color color, required int size}) async {
    // Создаем простое изображение маркера
    // В будущем можно использовать более сложные иконки
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = color;
    
    // Рисуем круг
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      size / 2 - 2,
      paint,
    );
    
    // Рисуем белую обводку
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(
      Offset(size / 2, size / 2),
      size / 2 - 2,
      borderPaint,
    );
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    
    return byteData!.buffer.asUint8List();
  }

  // Обработчик нажатия на маркер geo-post
  void _onGeoPostMarkerTapped(PointAnnotation annotation) {
    // Находим пост по ID аннотации
    final annotationIndex = _geoPostAnnotationIds.indexOf(annotation.id);
    if (annotationIndex >= 0 && annotationIndex < _geoPosts.length) {
      final post = _geoPosts[annotationIndex];
      
       // Устанавливаем выбранный маркер
       setState(() {
         _selectedMarker = {
           'type': 'geo_post',
           'postId': post.id,
           'post': post,
           'latitude': post.latitude,
           'longitude': post.longitude,
           'username': post.user?.username ?? 'unknown',
           'createdAt': post.createdAt,
         };
       });
       
       // Запускаем анимацию появления в заголовке
       _headerAnimationController.forward(from: 0.0);
       
       
       print('MapScreen: Geo-post marker tapped: ${post.id}, username: ${post.user?.username}');
    }
  }

  // Обработчик нажатия на маркер друга
  void _onFriendMarkerTapped(PointAnnotation annotation) async {
    // Находим друга по ID аннотации
    final annotationIndex = _friendAnnotationIds.indexOf(annotation.id);
    if (annotationIndex >= 0 && annotationIndex < _friendsLocations.length) {
      final friend = _friendsLocations[annotationIndex];
      
      // Преобразуем координаты
      final lat = friend['latitude'];
      final lng = friend['longitude'];
      
      double? latDouble;
      double? lngDouble;
      
      if (lat is double) {
        latDouble = lat;
      } else if (lat is int) {
        latDouble = lat.toDouble();
      } else if (lat is String) {
        latDouble = double.tryParse(lat);
      }
      
      if (lng is double) {
        lngDouble = lng;
      } else if (lng is int) {
        lngDouble = lng.toDouble();
      } else if (lng is String) {
        lngDouble = double.tryParse(lng);
      }
      
      if (latDouble == null || lngDouble == null) {
        print('MapScreen: ⚠️ Invalid coordinates for friend ${friend['username']}');
        return;
      }
      
      // Парсим last_location_updated_at для определения статуса
      DateTime? lastSeen;
      bool? isOnline;
      
      final lastLocationUpdatedAt = friend['last_location_updated_at'] as String?;
      if (lastLocationUpdatedAt != null) {
        try {
          lastSeen = DateTime.parse(lastLocationUpdatedAt);
          // Считаем онлайн, если обновление было менее минуты назад
          final now = DateTime.now();
          final difference = now.difference(lastSeen);
          isOnline = difference.inSeconds < 60;
        } catch (e) {
          print('MapScreen: Error parsing last_location_updated_at: $e');
        }
      }
      
      // Устанавливаем выбранный маркер
      setState(() {
        _selectedMarker = {
          'type': 'friend',
          'friendId': friend['id'],
          'friend': friend,
          'latitude': latDouble,
          'longitude': lngDouble,
          'username': friend['username'],
          'name': friend['name'],
          'avatar_url': friend['avatar_url'],
          'lastSeen': lastSeen,
          'isOnline': isOnline,
        };
      });
      
      // Запускаем анимацию появления в заголовке
      _headerAnimationController.forward(from: 0.0);
      
      // Анимация нажатия (масштабирование)
      _scaleAnimationController.forward(from: 0.9).then((_) {
        _scaleAnimationController.reverse();
      });
      
      // Делаем зум к местоположению друга
      try {
        if (_mapboxMap != null) {
          await _mapboxMap!.flyTo(
            CameraOptions(
              center: Point(
                coordinates: Position(lngDouble, latDouble),
              ),
              zoom: 18.0, // Близкий зум при нажатии на маркер
              pitch: 60.0, // Сохраняем 3D режим
            ),
            MapAnimationOptions(
              duration: 1500, // Плавная анимация приближения
              startDelay: 0,
            ),
          );
          print('MapScreen: ✅ Zoomed to friend location on marker tap');
        }
      } catch (e) {
        print('MapScreen: Error zooming to friend location on marker tap: $e');
      }
      
      print('MapScreen: Friend marker tapped: ${friend['username']}');
    }
  }
   
   // Вычисляет расстояние между двумя координатами в километрах
   double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
     return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000; // Конвертируем метры в километры
   }
   
   // Форматирует время (когда был в сети или опубликован)
   String _formatTime(DateTime? dateTime) {
     if (dateTime == null) return 'Unknown';
     
     final now = DateTime.now();
     final difference = now.difference(dateTime);
     
     if (difference.inMinutes < 1) {
       return 'Just now';
     } else if (difference.inMinutes < 60) {
       return '${difference.inMinutes}m ago';
     } else if (difference.inHours < 24) {
       return '${difference.inHours}h ago';
     } else if (difference.inDays < 7) {
       return '${difference.inDays}d ago';
     } else {
       return '${(difference.inDays / 7).floor()}w ago';
     }
   }

  // Показывает детали поста
  void _showPostDetails(Post post) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.user != null) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: post.user!.avatarUrl != null
                        ? NetworkImage(post.user!.avatarUrl!)
                        : null,
                    child: post.user!.avatarUrl == null
                        ? const Icon(EvaIcons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.user!.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '@${post.user!.username}',
                          style: const TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (post.caption.isNotEmpty) ...[
              Text(
                post.caption,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                const Icon(EvaIcons.heartOutline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${post.likesCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(width: 16),
                const Icon(EvaIcons.messageCircleOutline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${post.commentsCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Показывает информацию о локации друга
  void _showFriendLocation(Map<String, dynamic> friend) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: friend['avatar_url'] != null
                      ? NetworkImage(friend['avatar_url'] as String)
                      : null,
                  child: friend['avatar_url'] == null
                      ? const Icon(EvaIcons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friend['name'] ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '@${friend['username'] ?? 'unknown'}',
                        style: const TextStyle(
                          color: Color(0xFF8E8E8E),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Location shared',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: ui.Size(double.infinity, kToolbarHeight),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: FadeTransition(
                opacity: _appBarAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -1),
                    end: Offset.zero,
                  ).animate(_appBarAnimation),
                  child: AppBar(
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    leading: IconButton(
                      icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    title: SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // "Geo" по центру
                      Text(
                        'Geo',
                        style: GoogleFonts.delaGothicOne(
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                      // Данные о выбранном маркере с анимацией
                      if (_selectedMarker != null && _currentPosition != null)
                        FadeTransition(
                          opacity: _headerFadeAnimation,
                          child: SlideTransition(
                            position: _headerSlideAnimation,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 8),
                                // Точка-разделитель
                                Container(
                                  width: 4,
                                  height: 4,
                                  decoration: const BoxDecoration(
                                    color: Colors.white70,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Юзернейм
                                Text(
                                  '@${_selectedMarker!['username'] ?? 'unknown'}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Расстояние
                                if (_selectedMarker!['latitude'] != null && _selectedMarker!['longitude'] != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          EvaIcons.navigation2Outline,
                                          color: Color(0xFF0095F6),
                                          size: 12,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${_calculateDistance(
                                            _currentPosition!.latitude,
                                            _currentPosition!.longitude,
                                            _selectedMarker!['latitude'],
                                            _selectedMarker!['longitude'],
                                          ).toStringAsFixed(1)} km',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                // Время
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _selectedMarker!['type'] == 'post'
                                            ? EvaIcons.imageOutline
                                            : EvaIcons.clockOutline,
                                        color: Colors.white70,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _selectedMarker!['type'] == 'post'
                                            ? _formatTime(_selectedMarker!['createdAt'])
                                            : _selectedMarker!['type'] == 'me'
                                                ? _formatTime(_selectedMarker!['lastSeen'] as DateTime?)
                                                : _selectedMarker!['type'] == 'friend'
                                                    ? _formatTime(_selectedMarker!['lastSeen'] as DateTime?)
                                                    : _formatTime(_selectedMarker!['lastSeen'] != null
                                                        ? (_selectedMarker!['lastSeen'] is DateTime
                                                            ? _selectedMarker!['lastSeen'] as DateTime
                                                            : DateTime.parse(_selectedMarker!['lastSeen'] as String))
                                                        : null),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                centerTitle: true,
                    actions: [],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Mapbox карта
          if (_isMapReady)
            MapWidget(
              key: const ValueKey("mapWidget"),
                cameraOptions: CameraOptions(
                  center: _currentPosition != null
                      ? Point(
                          coordinates: Position(
                            _currentPosition!.longitude,
                            _currentPosition!.latitude,
                          ),
                        )
                      : Point(
                          coordinates: Position(0.0, 0.0), // Default location
                        ),
                  zoom: _currentPosition != null ? 15.5 : 2.0, // Увеличенный начальный zoom
                  pitch: 60.0, // Всегда 3D режим
                ),
                styleUri: 'mapbox://styles/mapbox/standard', // Mapbox Standard для поддержки lightPreset
                textureView: true,
                onMapCreated: (MapboxMap mapboxMap) async {
                _mapboxMap = mapboxMap;
                
                // Получаем начальный зум
                try {
                  final cameraState = await mapboxMap.getCameraState();
                  _currentZoom = cameraState.zoom;
                  print('MapScreen: Initial zoom: $_currentZoom');
                } catch (e) {
                  print('MapScreen: Error getting initial camera state: $e');
                }
                
                // Инициализируем annotation managers
                try {
                  final annotationManager = await mapboxMap.annotations.createPointAnnotationManager();
                  _geoPostsAnnotationManager = annotationManager;
                  
                  // Создаем отдельный manager для друзей
                  final friendsManager = await mapboxMap.annotations.createPointAnnotationManager();
                  _friendsAnnotationManager = friendsManager;
                  
                  // Создаем отдельный manager для маркера моей локации
                  final myLocationManager = await mapboxMap.annotations.createPointAnnotationManager();
                  
                  // ВАЖНО: Обновляем состояние, чтобы manager был доступен
                  setState(() {
                    _myLocationAnnotationManager = myLocationManager;
                  });
                  
                  print('MapScreen: ✅ All annotation managers created');
                  
                  // Убеждаемся, что настройки локации загружены перед получением локации
                  await _loadLocationSharingStatus();
                  
                  // Получаем локацию
                  await _getCurrentLocation();
                  
                  // Добавляем маркер моей локации напрямую (manager уже создан и установлен в состоянии)
                  if (_currentPosition != null && _myLocationAnnotationManager != null) {
                    // Анимация появления маркера
                    _scaleAnimationController.forward();
                    setState(() {
                      _isMarkerVisible = true;
                    });
                    
                    await _addMyLocationMarker();
                    
                    // Пульсация запускается только когда маркер выбран (в _onMyLocationMarkerTapped)
                    
                    // Добавляем обработчик нажатий на маркер моей локации
                    try {
                      _myLocationAnnotationManager!.addOnPointAnnotationClickListener(
                        _MyLocationAnnotationClickListener(
                          onTap: (annotation) {
                            // Проверяем, что это наш маркер
                            if (annotation.id == _myLocationAnnotationId) {
                              print('MapScreen: 🎯 My location marker tapped!');
                              _onMyLocationMarkerTapped();
                            }
                          },
                        ),
                      );
                      print('MapScreen: ✅ Added click listener for my location marker');
                    } catch (e) {
                      print('MapScreen: ⚠️ Error adding click listener: $e');
                    }
                  }
                  
                  // Загружаем данные в зависимости от текущей вкладки
                  if (_currentTabIndex == 0) {
                    _loadFriendsLocations();
                  } else {
                    _loadGeoPosts();
                  }
                  
                  // Устанавливаем начальный стиль в зависимости от времени суток
                  // Добавляем небольшую задержку, чтобы стиль успел загрузиться
                  Future.delayed(const Duration(milliseconds: 500), () {
                    _updateMapStyleForTimeOfDay();
                  });
                } catch (e) {
                  print('MapScreen: Error creating annotation managers: $e');
                }
              },
            )
          else
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            ),

          // Уведомления загрузки показываются через overlay
          
          // Нижняя панель с вкладками и кнопками
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Кнопка настроек слева
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                builder: (context) => const LocationSettingsSheet(),
                              );
                            },
                            borderRadius: BorderRadius.circular(26),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: const Icon(EvaIcons.settingsOutline, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Вкладки или кнопка "Посмотреть" в зависимости от выбранного маркера
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _selectedMarker != null
                              ? // Кнопка "Посмотреть" когда маркер выбран
                              ScaleTransition(
                                  scale: _bottomBarAnimation,
                                  child: FadeTransition(
                                    opacity: _bottomBarAnimation,
                                    child: Center(
                                      child: Container(
                                        key: const ValueKey('view_button'),
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(30),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.3),
                                            width: 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _getMetaBallColor(_metaBallsAnimation.value).withOpacity(0.4),
                                              blurRadius: 12 + (8 * _metaBallsAnimation.value),
                                              spreadRadius: 2 + (2 * _metaBallsAnimation.value),
                                            ),
                                          ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: _onViewButtonTapped,
                                            borderRadius: BorderRadius.circular(26),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(EvaIcons.eyeOutline, color: Colors.white, size: 20),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Посмотреть',
                                                    style: GoogleFonts.inter(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : // Вкладки когда маркер не выбран
                              ScaleTransition(
                                  scale: _bottomBarAnimation,
                                  child: FadeTransition(
                                    opacity: _bottomBarAnimation,
                                    child: AnimatedBuilder(
                                      key: const ValueKey('tabs'),
                                      animation: Listenable.merge([_tabController, _metaBallsAnimation]),
                                      builder: (context, child) {
                                        return Center(
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.5),
                                              borderRadius: BorderRadius.circular(30),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(0.3),
                                                width: 1,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: _getMetaBallColor(_metaBallsAnimation.value).withOpacity(0.4),
                                                  blurRadius: 12 + (8 * _metaBallsAnimation.value),
                                                  spreadRadius: 2 + (2 * _metaBallsAnimation.value),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Friends Tab
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
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            EvaIcons.peopleOutline,
                                                            color: _tabController.index == 0
                                                                ? Colors.white
                                                                : Colors.white.withOpacity(0.6),
                                                            size: 20,
                                                          ),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            'Friends',
                                                            style: TextStyle(
                                                              color: _tabController.index == 0
                                                                  ? Colors.white
                                                                  : Colors.white.withOpacity(0.6),
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                // Posts Tab
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
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            EvaIcons.imageOutline,
                                                            color: _tabController.index == 1
                                                                ? Colors.white
                                                                : Colors.white.withOpacity(0.6),
                                                            size: 20,
                                                          ),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            'Posts',
                                                            style: TextStyle(
                                                              color: _tabController.index == 1
                                                                  ? Colors.white
                                                                  : Colors.white.withOpacity(0.6),
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.w600,
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
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Кнопка плюсика/геолокации или крестика в зависимости от выбранного маркера и вкладки
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _selectedMarker != null
                            ? // Кнопка "✕" когда маркер выбран
                            Container(
                                key: const ValueKey('close_button'),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _onDeselectMarker,
                                    borderRadius: BorderRadius.circular(26),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      child: const Icon(EvaIcons.close, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ),
                              )
                            : // Кнопка геолокации для Friends или "+" для Posts
                            _currentTabIndex == 0
                                ? Container(
                                    key: const ValueKey('location_button'),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: _onLocationUpdateButtonTapped,
                                        borderRadius: BorderRadius.circular(26),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          child: const Icon(EvaIcons.navigation2Outline, color: Colors.white, size: 20),
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    key: const ValueKey('plus_button'),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: _onPlusButtonTapped,
                                        borderRadius: BorderRadius.circular(26),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          child: const Icon(EvaIcons.plusCircleOutline, color: Colors.white, size: 20),
                                        ),
                                      ),
                                    ),
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
    );
  }
}

// Состояния уведомления
enum _LocationNotificationState {
  updating,
  gettingData,
  completed,
}

// Уведомление загрузки с glow эффектом
class _LoadingNotification extends StatefulWidget {
  final String message;
  final VoidCallback? onDismiss;

  const _LoadingNotification({
    required this.message,
    this.onDismiss,
  });

  @override
  State<_LoadingNotification> createState() => _LoadingNotificationState();
}

class _LoadingNotificationState extends State<_LoadingNotification>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _glowController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _scaleAnimation;

  // Получаем цвет для glow эффекта (как у панели Friends/Posts)
  Color _getMetaBallColor(double animationValue) {
    final hue = (animationValue * 360) % 360;
    return HSVColor.fromAHSV(1.0, hue, 0.8, 1.0).toColor();
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _slideAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: Curves.easeInOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: true,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(_slideAnimation),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_glowAnimation, _glowController]),
                  builder: (context, child) {
                    final glowColor = _getMetaBallColor(_glowController.value);
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          // Glow эффект как у панели Friends/Posts
                          BoxShadow(
                            color: glowColor.withOpacity(0.4 * _glowAnimation.value),
                            blurRadius: 12 + (8 * _glowAnimation.value),
                            spreadRadius: 2 + (2 * _glowAnimation.value),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Индикатор загрузки
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Текст
                      DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          height: 1.0,
                        ),
                        child: Text(
                          widget.message,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Красивое уведомление об обновлении геолокации с glow эффектом
class _LocationUpdatedNotification extends StatefulWidget {
  final _LocationNotificationState initialState;
  final VoidCallback? onDismiss;

  const _LocationUpdatedNotification({
    this.initialState = _LocationNotificationState.updating,
    this.onDismiss,
  });

  @override
  State<_LocationUpdatedNotification> createState() => _LocationUpdatedNotificationState();
}

class _LocationUpdatedNotificationState extends State<_LocationUpdatedNotification>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _glowController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _scaleAnimation;
  
  _LocationNotificationState _currentState = _LocationNotificationState.updating;
  
  // Получаем цвет для glow эффекта (как у панели Friends/Posts)
  Color _getMetaBallColor(double animationValue) {
    final hue = (animationValue * 360) % 360;
    return HSVColor.fromAHSV(1.0, hue, 0.8, 1.0).toColor();
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _slideAnimation = Tween<double>(begin: -100.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: Curves.easeInOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
    
    // Устанавливаем начальное состояние
    _currentState = widget.initialState;
    
    // Переход между состояниями
    _updateState();
  }
  
  void _updateState() {
    // Переход от updating к gettingData
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _currentState = _LocationNotificationState.gettingData;
        });
        
        // Переход от gettingData к completed
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _currentState = _LocationNotificationState.completed;
            });
            
            // Автоматически скрываем через 2 секунды после завершения
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                _controller.reverse().then((_) {
                  widget.onDismiss?.call();
                });
              }
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _glowController.dispose();
    super.dispose();
  }
  
  String _getStateText() {
    switch (_currentState) {
      case _LocationNotificationState.updating:
        return 'Updating location...';
      case _LocationNotificationState.gettingData:
        return 'Getting data...';
      case _LocationNotificationState.completed:
        return 'Location updated!';
    }
  }
  
  Widget _getStateIcon() {
    switch (_currentState) {
      case _LocationNotificationState.updating:
      case _LocationNotificationState.gettingData:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      case _LocationNotificationState.completed:
        return const Icon(
          EvaIcons.checkmarkCircle2Outline,
          color: Colors.white,
          size: 20,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: true,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(_slideAnimation),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_glowAnimation, _glowController]),
                  builder: (context, child) {
                    final glowColor = _getMetaBallColor(_glowController.value);
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          // Glow эффект как у панели Friends/Posts
                          BoxShadow(
                            color: glowColor.withOpacity(0.4 * _glowAnimation.value),
                            blurRadius: 12 + (8 * _glowAnimation.value),
                            spreadRadius: 2 + (2 * _glowAnimation.value),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Иконка или индикатор загрузки
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: _getStateIcon(),
                      ),
                      const SizedBox(width: 10),
                      // Текст
                      DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          height: 1.0,
                        ),
                        child: Text(
                          _getStateText(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Анимированный диалог для ошибок геолокации
class _AnimatedLocationDialog extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? description;
  final String primaryButtonText;
  final String? secondaryButtonText;
  final VoidCallback onPrimaryPressed;
  final VoidCallback? onSecondaryPressed;

  const _AnimatedLocationDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.description,
    required this.primaryButtonText,
    this.secondaryButtonText,
    required this.onPrimaryPressed,
    this.onSecondaryPressed,
  });

  @override
  State<_AnimatedLocationDialog> createState() => _AnimatedLocationDialogState();
}

class _AnimatedLocationDialogState extends State<_AnimatedLocationDialog>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _iconPulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _iconPulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1C1C1E),
                  const Color(0xFF1C1C1E).withOpacity(0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.iconColor.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Анимированная иконка с пульсацией
                  AnimatedBuilder(
                    animation: Listenable.merge([_iconPulseAnimation, _fadeAnimation]),
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _iconPulseAnimation.value,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                widget.iconColor.withOpacity(0.2 * _fadeAnimation.value),
                                widget.iconColor.withOpacity(0.05 * _fadeAnimation.value),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.iconColor.withOpacity(0.3 * _fadeAnimation.value),
                                blurRadius: 20 * _iconPulseAnimation.value,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.iconColor,
                            size: 40,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  // Заголовок с анимацией появления
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
                      )),
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Сообщение с анимацией появления
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
                      )),
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.5,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  
                  // Описание (если есть) с анимацией
                  if (widget.description != null) ...[
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.2),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _controller,
                          curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
                        )),
                        child: Text(
                          widget.description!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 28),
                  
                  // Кнопки
                  Row(
                    children: [
                      if (widget.secondaryButtonText != null) ...[
                        Expanded(
                          child: TextButton(
                            onPressed: widget.onSecondaryPressed,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              widget.secondaryButtonText!,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: widget.secondaryButtonText != null ? 1 : 1,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.3),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: _controller,
                              curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
                            )),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    widget.iconColor,
                                    widget.iconColor.withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.iconColor.withOpacity(0.4),
                                    blurRadius: 12,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: widget.onPrimaryPressed,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    alignment: Alignment.center,
                                    child: Text(
                                      widget.primaryButtonText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// CustomPainter для glow эффекта по бокам
class _GlowSidePainter extends CustomPainter {
  final double rotation;
  final double opacity;

  _GlowSidePainter({
    required this.rotation,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 30.0);

    // Левая сторона - закат
    final leftGradient = ui.Gradient.linear(
      Offset(0, size.height / 2),
      Offset(size.width * 0.15, size.height / 2),
      [
        const Color(0xFFFF6B35).withOpacity(opacity),
        Colors.transparent,
      ],
    );

    // Правая сторона - фиолетовый
    final rightGradient = ui.Gradient.linear(
      Offset(size.width, size.height / 2),
      Offset(size.width * 0.85, size.height / 2),
      [
        const Color(0xFF9C27B0).withOpacity(opacity),
        Colors.transparent,
      ],
    );

    // Вращающийся эффект - рисуем несколько слоев с разными углами
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);

    // Левая сторона
    paint.shader = leftGradient;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * 0.2, size.height),
      paint,
    );

    // Правая сторона
    paint.shader = rightGradient;
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.8, 0, size.width * 0.2, size.height),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowSidePainter oldDelegate) {
    return oldDelegate.rotation != rotation || oldDelegate.opacity != opacity;
  }
}

// CustomPainter для рисования пульсирующих волн
class WavePainter extends CustomPainter {
  final Offset center;
  final double waveProgress;
  final double pulseProgress;

  WavePainter({
    required this.center,
    required this.waveProgress,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, ui.Size size) {
    // Рисуем несколько концентрических волн, расходящихся от центра маркера
    final maxRadius = 150.0; // Увеличенный радиус
    final waveCount = 3; // Количество одновременно видимых волн
    final baseRadius = 60.0; // Базовый радиус от центра маркера (увеличен)
    
    for (int i = 0; i < waveCount; i++) {
      // Каждая волна начинается с задержкой (0, 0.33, 0.66)
      final waveOffset = (waveProgress + i * (1.0 / waveCount)) % 1.0;
      // Радиус увеличивается от базового до максимального
      final radius = baseRadius + (maxRadius - baseRadius) * waveOffset;
      // Прозрачность уменьшается по мере удаления (от 0.7 до 0) - увеличена
      final opacity = (1.0 - waveOffset) * 0.7;
      
      if (opacity > 0.01 && radius > baseRadius) {
        final paint = Paint()
          ..color = const Color(0xFF0095F6).withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0 - (waveOffset * 2.5) // Увеличена толщина (было 3.0 - waveOffset * 2.0)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5.0); // Увеличено размытие
        
        canvas.drawCircle(center, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) {
    return oldDelegate.waveProgress != waveProgress ||
           oldDelegate.pulseProgress != pulseProgress ||
           oldDelegate.center != center;
  }
}

