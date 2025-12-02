import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'providers/auth_provider.dart';
import 'providers/posts_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/online_status_provider.dart';
import 'services/api_service.dart';
import 'services/cache_service.dart';
import 'services/message_cache_service.dart';
import 'services/notification_service.dart';
import 'services/fcm_service.dart';
import 'utils/themes.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
// import 'screens/splash_screen.dart'; // Используем только нативный splash screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация Mapbox с токеном доступа
  const mapboxToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'pk.eyJ1IjoiZWtpbGlvdCIsImEiOiJjbWk0cWozY3UxdG5xMmxxejRzMzA1cmtrIn0.C82cxRLUdU-AgJ7409Uaaw',
  );
  MapboxOptions.setAccessToken(mapboxToken);
  
  // Инициализация Hive для кеша сообщений
  await Hive.initFlutter();
  
  // Инициализация кеша (используем синглтон)
  await CacheService().init();
  
  // Инициализация кеша сообщений
  await MessageCacheService().init();
  
  // Инициализация сервиса уведомлений
  final notificationService = NotificationService();
  await notificationService.initialize();
  
  // Инициализация FCM сервиса
  final fcmService = FCMService();
  try {
    await fcmService.initialize();
  } catch (e) {
    print('Warning: FCM initialization failed: $e');
    print('Make sure google-services.json is configured correctly');
  }
  
  runApp(const SonetApp());
}

class SonetApp extends StatelessWidget {
  const SonetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PostsProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider(apiService)),
        ChangeNotifierProvider(create: (_) => OnlineStatusProvider()),
      ],
      child: MaterialApp(
        title: 'Sonet',
        debugShowCheckedModeBanner: false,
        theme: AppThemes.darkTheme,
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Инициализируем AuthProvider при запуске
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {

    return Consumer2<AuthProvider, OnlineStatusProvider>(
      builder: (context, authProvider, onlineStatusProvider, child) {
        // Показываем загрузку пока не инициализирован
        if (!authProvider.isInitialized) {
          return const Scaffold(
            backgroundColor: Color(0xFF000000),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            ),
          );
        }
        
        // После инициализации показываем соответствующий экран
        if (authProvider.isAuthenticated) {
          // Запускаем heartbeat если пользователь авторизован
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final prefs = await SharedPreferences.getInstance();
            final accessToken = prefs.getString('access_token');
            if (accessToken != null) {
              onlineStatusProvider.startHeartbeat(accessToken);
              
              // Отправляем FCM токен на сервер после входа
              final fcmService = FCMService();
              if (fcmService.isInitialized && fcmService.fcmToken != null) {
                print('AuthWrapper: Sending FCM token to server...');
                await fcmService.sendTokenToServer(accessToken);
              }
            }
          });
          
          return MainScreen(key: MainScreen.globalKey);
        } else {
          // Останавливаем heartbeat если пользователь вышел
          onlineStatusProvider.stopHeartbeat();
          
          // Удаляем FCM токен при выходе
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final fcmService = FCMService();
            if (fcmService.isInitialized) {
              await fcmService.deleteToken();
            }
          });
          
          return const LoginScreen();
        }
      },
    );
  }
}