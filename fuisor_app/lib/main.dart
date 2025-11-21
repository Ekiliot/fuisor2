import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/auth_provider.dart';
import 'providers/posts_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/online_status_provider.dart';
import 'services/api_service.dart';
import 'services/cache_service.dart';
import 'utils/themes.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация кеша (используем синглтон)
  await CacheService().init();
  
  runApp(const FuisorApp());
}

class FuisorApp extends StatelessWidget {
  const FuisorApp({super.key});

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
        title: 'Fuișor',
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
            }
          });
          
          return MainScreen(key: MainScreen.globalKey);
        } else {
          // Останавливаем heartbeat если пользователь вышел
          onlineStatusProvider.stopHeartbeat();
          return const LoginScreen();
        }
      },
    );
  }
}