import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'api_service.dart';

/// Обработчик уведомлений когда приложение в фоне
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('FCMService: Background message received: ${message.messageId}');
  print('FCMService: Data: ${message.data}');
  print('FCMService: Notification: ${message.notification?.title}');
  
  // Показываем локальное уведомление
  final notificationService = NotificationService();
  await notificationService.initialize();
  
  if (message.notification != null) {
    await notificationService.showNotification(
      id: message.hashCode,
      title: message.notification!.title ?? 'New notification',
      body: message.notification!.body ?? '',
      payload: jsonEncode(message.data),
    );
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  FirebaseMessaging? _firebaseMessaging;
  final NotificationService _notificationService = NotificationService();
  
  String? _fcmToken;
  bool _isInitialized = false;
  
  String? get fcmToken => _fcmToken;
  bool get isInitialized => _isInitialized;
  
  FirebaseMessaging get firebaseMessaging {
    if (_firebaseMessaging == null) {
      throw StateError('FCMService not initialized. Call initialize() first.');
    }
    return _firebaseMessaging!;
  }

  /// Инициализация FCM сервиса
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Firebase должен быть инициализирован в main.dart перед вызовом этого метода
      // Проверяем, что Firebase инициализирован
      try {
        Firebase.app(); // Проверка, что Firebase инициализирован
      } catch (e) {
        print('FCMService: Firebase not initialized. Attempting to initialize...');
        await Firebase.initializeApp();
      }

      // Инициализируем FirebaseMessaging ПОСЛЕ инициализации Firebase
      _firebaseMessaging = FirebaseMessaging.instance;

      // Запрашиваем разрешение на уведомления
      NotificationSettings settings = await firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('FCMService: Notification permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('FCMService: User granted notification permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('FCMService: User granted provisional notification permission');
      } else {
        print('FCMService: User declined or has not accepted notification permission');
      }

      // Настраиваем обработчики сообщений
      _setupMessageHandlers();

      // Получаем FCM токен
      await _getFCMToken();

      _isInitialized = true;
      print('FCMService: Initialized successfully');
    } catch (e, stackTrace) {
      print('FCMService: Error initializing: $e');
      print('FCMService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Настройка обработчиков сообщений
  void _setupMessageHandlers() {
    if (_firebaseMessaging == null) return;
    
    // Когда приложение открыто (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('FCMService: Foreground message received: ${message.messageId}');
      print('FCMService: Data: ${message.data}');
      print('FCMService: Notification: ${message.notification?.title}');

      // Показываем локальное уведомление
      if (message.notification != null) {
        _notificationService.showNotification(
          id: message.hashCode,
          title: message.notification!.title ?? 'New notification',
          body: message.notification!.body ?? '',
          payload: jsonEncode(message.data),
        );
      }
    });

    // Когда пользователь нажимает на уведомление (приложение в фоне/закрыто)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCMService: Message opened app: ${message.messageId}');
      print('FCMService: Data: ${message.data}');
      _handleNotificationTap(message.data);
    });

    // Проверяем, было ли приложение открыто из закрытого состояния через уведомление
    firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('FCMService: App opened from terminated state via notification');
        print('FCMService: Data: ${message.data}');
        _handleNotificationTap(message.data);
      }
    });

    // Устанавливаем фоновый обработчик
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  /// Получение FCM токена
  Future<String?> _getFCMToken() async {
    try {
      _fcmToken = await firebaseMessaging.getToken();
      print('FCMService: FCM Token obtained: ${_fcmToken?.substring(0, 20)}...');

      // Сохраняем токен локально
      if (_fcmToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', _fcmToken!);
      }

      // Слушаем обновления токена
      firebaseMessaging.onTokenRefresh.listen((String newToken) {
        print('FCMService: FCM Token refreshed: ${newToken.substring(0, 20)}...');
        _fcmToken = newToken;
        
        // Сохраняем новый токен
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('fcm_token', newToken);
        });

        // Отправляем новый токен на сервер (если пользователь авторизован)
        _sendTokenToServer(newToken);
      });

      return _fcmToken;
    } catch (e) {
      print('FCMService: Error getting FCM token: $e');
      return null;
    }
  }

  /// Отправка FCM токена на сервер
  Future<void> sendTokenToServer(String? accessToken) async {
    if (_fcmToken == null) {
      print('FCMService: No FCM token available, skipping server update');
      return;
    }

    if (accessToken == null) {
      print('FCMService: No access token, skipping server update');
      return;
    }

    await _sendTokenToServer(_fcmToken!, accessToken);
  }

  Future<void> _sendTokenToServer(String token, [String? accessToken]) async {
    try {
      // Если accessToken не передан, пытаемся получить из SharedPreferences
      String? authToken = accessToken;
      if (authToken == null) {
        final prefs = await SharedPreferences.getInstance();
        authToken = prefs.getString('access_token');
      }

      if (authToken == null) {
        print('FCMService: No access token available for sending FCM token');
        return;
      }

      final apiService = ApiService();
      apiService.setAccessToken(authToken);
      
      await apiService.sendFCMToken(token);
      print('FCMService: FCM token sent to server successfully');
    } catch (e) {
      print('FCMService: Error sending FCM token to server: $e');
    }
  }

  /// Обработка нажатия на уведомление
  void _handleNotificationTap(Map<String, dynamic> data) {
    print('FCMService: Handling notification tap with data: $data');
    
    final type = data['type'] as String?;
    if (type == null) return;

    // TODO: Реализовать навигацию в зависимости от типа уведомления
    // Например:
    // - notification -> открыть экран уведомлений
    // - message -> открыть чат
    // - post -> открыть пост
    // - story -> открыть stories
  }

  /// Удаление FCM токена (при выходе)
  Future<void> deleteToken() async {
    try {
      if (_firebaseMessaging == null) return;
      await firebaseMessaging.deleteToken();
      _fcmToken = null;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcm_token');
      
      print('FCMService: FCM token deleted');
    } catch (e) {
      print('FCMService: Error deleting FCM token: $e');
    }
  }
}
