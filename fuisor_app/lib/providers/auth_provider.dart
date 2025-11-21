import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/message_cache_service.dart';
import '../utils/image_cache_utils.dart';

enum LoginButtonState {
  normal,
  loading,
  success,
  error,
}

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  LoginButtonState _loginButtonState = LoginButtonState.normal;
  bool _showErrorAfterAnimation = false;

  // Ключи для SharedPreferences
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userDataKey = 'user_data';

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitialized => _isInitialized;
  LoginButtonState get loginButtonState => _loginButtonState;
  bool get shouldShowError => _showErrorAfterAnimation && _error != null;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // Сохранение сессии в SharedPreferences
  Future<void> _saveSession(String accessToken, String refreshToken, User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessTokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);
      await prefs.setString(_userDataKey, jsonEncode(user.toJson()));
      
      // Устанавливаем токен в ApiService
      _apiService.setAccessToken(accessToken);
    } catch (e) {
      print('Error saving session: $e');
    }
  }

  // Загрузка сессии из SharedPreferences
  Future<void> _loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);
      final userDataString = prefs.getString(_userDataKey);

      print('AuthProvider: Loading session...');
      print('AuthProvider: Access token found: ${accessToken != null ? "Yes (${accessToken.substring(0, 20)}...)" : "No"}');
      print('AuthProvider: User data found: ${userDataString != null ? "Yes" : "No"}');

      if (accessToken != null) {
        // Устанавливаем токен в ApiService
        _apiService.setAccessToken(accessToken);
        print('AuthProvider: Token set in ApiService');
        
        // Парсим данные пользователя если они есть
        if (userDataString != null) {
          final userData = jsonDecode(userDataString);
          _currentUser = User.fromJson(userData);
          print('AuthProvider: User data loaded from session');
          print('AuthProvider: Current user ID: ${_currentUser?.id}');
          print('AuthProvider: Current user name: ${_currentUser?.name}');
          print('AuthProvider: Current user username: ${_currentUser?.username}');
        } else {
          print('AuthProvider: No user data in session, will fetch from API');
        }
        
        _isInitialized = true;
        notifyListeners();
      } else {
        print('AuthProvider: No access token found in session');
        _isInitialized = true;
        notifyListeners();
      }
    } catch (e) {
      print('Error loading session: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  // Очистка сессии
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_userDataKey);
      
      // Очищаем токен в ApiService
      _apiService.setAccessToken(null);
    } catch (e) {
      print('Error clearing session: $e');
    }
  }

  // Инициализация AuthProvider
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadSession();
  }

  void _setLoginButtonState(LoginButtonState state) {
    _loginButtonState = state;
    notifyListeners();
  }

  String _parseLoginError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // Проверяем различные типы ошибок
    if (errorString.contains('invalid username or password') ||
        errorString.contains('invalid email or password') ||
        errorString.contains('invalid credentials') ||
        errorString.contains('неверн')) {
      return 'Invalid email or password. Please check your credentials and try again.';
    }
    
    if (errorString.contains('user not found') ||
        errorString.contains('user does not exist')) {
      return 'User not found. Please check your email or username.';
    }
    
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return 'Network error. Please check your internet connection and try again.';
    }
    
    if (errorString.contains('server') ||
        errorString.contains('500') ||
        errorString.contains('internal')) {
      return 'Server error. Please try again later.';
    }
    
    // Возвращаем общее сообщение об ошибке
    return 'Unable to sign in. Please check your credentials and try again.';
  }

  Future<bool> login(String emailOrUsername, String password) async {
    try {
      _setLoading(true);
      _setError(null);
      _showErrorAfterAnimation = false;
      _setLoginButtonState(LoginButtonState.loading);

      final authResponse = await _apiService.login(emailOrUsername, password);
      _currentUser = authResponse.profile ?? authResponse.user;
      
      // Сохраняем сессию
      await _saveSession(
        authResponse.accessToken,
        authResponse.refreshToken,
        _currentUser!,
      );

      _setLoading(false);
      _setLoginButtonState(LoginButtonState.success);
      
      // Через 1 секунду сбрасываем состояние для следующего использования
      Future.delayed(const Duration(seconds: 1), () {
        if (_loginButtonState == LoginButtonState.success) {
          _setLoginButtonState(LoginButtonState.normal);
        }
      });
      
      return true;
    } catch (e) {
      final errorMessage = _parseLoginError(e);
      _setError(errorMessage);
      _setLoading(false);
      _showErrorAfterAnimation = false; // Скрываем ошибку во время анимации
      _setLoginButtonState(LoginButtonState.error);
      
      // Через 2 секунды возвращаем к нормальному состоянию и показываем ошибку
      Future.delayed(const Duration(seconds: 2), () {
        if (_loginButtonState == LoginButtonState.error) {
          _setLoginButtonState(LoginButtonState.normal);
          // Показываем ошибку только после завершения анимации
          _showErrorAfterAnimation = true;
          notifyListeners();
        }
      });
      
      return false;
    }
  }

  Future<bool> signup(String email, String password, String username, String name) async {
    try {
      _setLoading(true);
      _setError(null);

      await _apiService.signup(email, password, username, name);
      
      // After successful signup, automatically log in
      final loginSuccess = await login(email, password);
      
      _setLoading(false);
      return loginSuccess;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _apiService.logout();
      
      // Очищаем кеш сообщений при выходе
      try {
        await MessageCacheService().clearAllCache();
        print('AuthProvider: Cleared message cache on logout');
      } catch (e) {
        print('AuthProvider: Error clearing message cache: $e');
      }
      
      // Очищаем сессию
      await _clearSession();
      
      _currentUser = null;
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<bool> updateProfile({
    String? name,
    String? username,
    String? bio,
    String? websiteUrl,
    Uint8List? avatarBytes,
    String? avatarFileName,
  }) async {
    try {
      _setLoading(true);
      _setError(null);

      final updatedUser = await _apiService.updateProfile(
        name: name,
        username: username,
        bio: bio,
        websiteUrl: websiteUrl,
        avatarBytes: avatarBytes,
        avatarFileName: avatarFileName,
      );

      _currentUser = updatedUser;
      
      // Обновляем сессию с новыми данными пользователя
      if (_currentUser != null) {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString(_accessTokenKey);
        final refreshToken = prefs.getString(_refreshTokenKey);
        if (accessToken != null && refreshToken != null) {
          await _saveSession(accessToken, refreshToken, _currentUser!);
        }
        
        // Очищаем кэш изображений для обновления аватара
        await ImageCacheUtils.clearImageCache();
      }
      
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  // Обновить данные профиля пользователя
  Future<void> refreshProfile() async {
    try {
      print('AuthProvider: Starting profile refresh...');
      _setLoading(true);
      _setError(null);

      // Проверяем токен перед запросом
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);
      print('AuthProvider: Access token for refresh: ${accessToken != null ? "Present (${accessToken.substring(0, 20)}...)" : "Missing"}');
      
      if (accessToken == null) {
        throw Exception('No access token available for profile refresh');
      }

      // Устанавливаем токен в ApiService
      _apiService.setAccessToken(accessToken);

      // Получаем обновленные данные профиля с сервера
      print('AuthProvider: Calling getCurrentUser()...');
      final updatedUser = await _apiService.getCurrentUser();
      _currentUser = updatedUser;
      
      print('AuthProvider: Profile refreshed successfully');
      print('AuthProvider: Updated user ID: ${_currentUser?.id}');
      print('AuthProvider: Updated user name: ${_currentUser?.name}');
      
      // Обновляем сессию с новыми данными
      if (_currentUser != null) {
        final refreshToken = prefs.getString(_refreshTokenKey);
        if (refreshToken != null) {
          await _saveSession(accessToken, refreshToken, _currentUser!);
          print('AuthProvider: Session updated with new user data');
        }
      }
      
      _setLoading(false);
    } catch (e) {
      print('AuthProvider: Error refreshing profile: $e');
      _setError(e.toString());
      _setLoading(false);
    }
  }

  Future<String?> getAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_accessTokenKey);
    } catch (e) {
      print('Error getting access token: $e');
      return null;
    }
  }

  // Установить текущего пользователя (для отладки)
  void setCurrentUser(User user) {
    print('AuthProvider: Setting current user manually');
    print('AuthProvider: User ID: ${user.id}');
    print('AuthProvider: User name: ${user.name}');
    _currentUser = user;
    notifyListeners();
  }

  // Обновить токен при истечении
  Future<bool> refreshTokenIfExpired() async {
    try {
      print('AuthProvider: Checking if token needs refresh...');
      
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);
      
      if (accessToken == null) {
        print('AuthProvider: No tokens found');
        return false;
      }
      
      // Проверяем, не истек ли токен
      try {
        final tokenData = _decodeJWT(accessToken);
        final exp = tokenData['exp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        
        print('AuthProvider: Token expires at: $exp, current time: $now');
        
        // Если токен истекает в течение 5 минут, обновляем его
        if (now >= exp - 300) {
          print('AuthProvider: Token expires soon, refreshing...');
          await refreshProfile();
          return true;
        } else {
          print('AuthProvider: Token is still valid');
          return false;
        }
      } catch (e) {
        print('AuthProvider: Error decoding token: $e');
        // Если не можем декодировать токен, пытаемся обновить
        await refreshProfile();
        return true;
      }
    } catch (e) {
      print('AuthProvider: Error refreshing token: $e');
      return false;
    }
  }

  // Декодировать JWT токен
  Map<String, dynamic> _decodeJWT(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw Exception('Invalid JWT token');
    }
    
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final resp = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(resp);
  }

  void clearError() {
    _setError(null);
    _showErrorAfterAnimation = false;
    _setLoginButtonState(LoginButtonState.normal);
  }
}
