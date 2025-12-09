import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  bool _hasPermission = false;

  bool get isInitialized => _isInitialized;
  bool get hasPermission => _hasPermission;

  /// Инициализация сервиса уведомлений
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Настройка для Android
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // Настройка для iOS
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Создаем канал уведомлений для Android
    await createNotificationChannel();

    _isInitialized = true;
    print('NotificationService: Initialized with notification channel');
  }

  /// Запрос разрешения на уведомления
  Future<bool> requestPermission() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // Для Android 13+ нужно запрашивать POST_NOTIFICATIONS
      final status = await Permission.notification.request();
      
      if (status.isGranted) {
        _hasPermission = true;
        print('NotificationService: Permission granted');
        return true;
      } else if (status.isPermanentlyDenied) {
        print('NotificationService: Permission permanently denied');
        _hasPermission = false;
        return false;
      } else {
        print('NotificationService: Permission denied');
        _hasPermission = false;
        return false;
      }
    } catch (e) {
      print('NotificationService: Error requesting permission: $e');
      _hasPermission = false;
      return false;
    }
  }

  /// Проверка разрешения на уведомления
  Future<bool> checkPermission() async {
    try {
      final status = await Permission.notification.status;
      _hasPermission = status.isGranted;
      return _hasPermission;
    } catch (e) {
      print('NotificationService: Error checking permission: $e');
      return false;
    }
  }

  /// Показать локальное уведомление
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_hasPermission) {
      print('NotificationService: No permission to show notification');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'sonet_notifications',
      'Sonet Notifications',
      channelDescription: 'Notifications for messages, likes, comments, and other events',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );

    print('NotificationService: Notification shown - $title');
  }

  /// Обработка нажатия на уведомление
  void _onNotificationTap(NotificationResponse response) {
    print('NotificationService: Notification tapped - ${response.payload}');
    // TODO: Обработать навигацию при нажатии на уведомление
  }

  /// Создать канал уведомлений (Android)
  Future<void> createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      'sonet_notifications',
      'Sonet Notifications',
      description: 'Notifications for messages, likes, comments, and other events',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(androidChannel);
      print('NotificationService: Notification channel created: ${androidChannel.id}');
    } else {
      print('NotificationService: Android plugin not available');
    }
  }

  /// Отменить все уведомления
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    print('NotificationService: All notifications cancelled');
  }

  /// Отменить конкретное уведомление
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    print('NotificationService: Notification $id cancelled');
  }
}

