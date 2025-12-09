import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class RecommendationProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  RecommendationSettings? _settings;
  List<LocationSuggestion> _suggestions = [];
  bool _isLoading = false;
  String? _error;
  Timer? _explorerModeTimer;
  Timer? _suggestionsRefreshTimer;

  RecommendationSettings? get settings => _settings;
  List<LocationSuggestion> get suggestions => _suggestions;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isExplorerModeActive => _settings?.isExplorerModeActive ?? false;

  /// Helper method to set access token
  Future<void> _setAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    if (accessToken != null) {
      _apiService.setAccessToken(accessToken);
    }
  }

  /// Load recommendation settings from API
  Future<void> loadSettings() async {
    try {
      _isLoading = true;
      _error = null;
      // Отложим notifyListeners до следующего кадра
      Future.microtask(() => notifyListeners());

      await _setAccessToken();
      _settings = await _apiService.getRecommendationSettings();
      
      // Start explorer mode timer if active
      if (_settings!.isExplorerModeActive) {
        _startExplorerModeTimer();
      }

      _isLoading = false;
      // Отложим notifyListeners до следующего кадра
      Future.microtask(() => notifyListeners());
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      // Отложим notifyListeners до следующего кадра
      Future.microtask(() => notifyListeners());
      print('Error loading recommendation settings: $e');
    }
  }

  /// Update recommendation settings
  Future<void> updateSettings(RecommendationSettings settings) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _setAccessToken();
      await _apiService.updateRecommendationSettings(settings);
      _settings = settings;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      print('Error updating recommendation settings: $e');
      rethrow;
    }
  }

  /// Auto-detect location and save to settings
  Future<LocationInfo> autoDetectAndSave() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Get current location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Auto-detect location via API
      await _setAccessToken();
      final locationInfo = await _apiService.autoDetectLocation(
        position.latitude,
        position.longitude,
      );

      // Reload settings to get updated data
      await loadSettings();

      _isLoading = false;
      notifyListeners();

      return locationInfo;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      print('Error auto-detecting location: $e');
      rethrow;
    }
  }

  /// Mark prompt as shown
  Future<void> markPromptShown() async {
    try {
      await _setAccessToken();
      await _apiService.markRecommendationPromptShown();
      if (_settings != null) {
        _settings = _settings!.copyWith(promptShown: true);
        notifyListeners();
      }
    } catch (e) {
      print('Error marking prompt as shown: $e');
    }
  }

  /// Toggle explorer mode
  Future<void> toggleExplorerMode(bool enabled) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _setAccessToken();
      final result = await _apiService.toggleExplorerMode(enabled);
      
      if (_settings != null) {
        DateTime? expiresAt;
        if (result['expiresAt'] != null) {
          expiresAt = DateTime.parse(result['expiresAt']);
        }

        _settings = _settings!.copyWith(
          explorerModeEnabled: enabled,
          explorerModeExpiresAt: expiresAt,
        );

        if (enabled && expiresAt != null) {
          _startExplorerModeTimer();
        } else {
          _stopExplorerModeTimer();
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      print('Error toggling explorer mode: $e');
      rethrow;
    }
  }

  /// Load location suggestions
  Future<void> loadLocationSuggestions() async {
    try {
      await _setAccessToken();
      _suggestions = await _apiService.getLocationSuggestions();
      // Отложим notifyListeners до следующего кадра
      Future.microtask(() => notifyListeners());
    } catch (e) {
      print('Error loading location suggestions: $e');
    }
  }

  /// Start explorer mode timer (auto-disable after expiration)
  void _startExplorerModeTimer() {
    _stopExplorerModeTimer(); // Cancel existing timer if any

    if (_settings?.explorerModeExpiresAt == null) return;

    final now = DateTime.now();
    final expiresAt = _settings!.explorerModeExpiresAt!;
    
    if (expiresAt.isBefore(now)) {
      // Already expired
      _settings = _settings!.copyWith(
        explorerModeEnabled: false,
        explorerModeExpiresAt: null,
      );
      notifyListeners();
      return;
    }

    final duration = expiresAt.difference(now);
    
    _explorerModeTimer = Timer(duration, () {
      // Auto-disable explorer mode
      if (_settings != null) {
        _settings = _settings!.copyWith(
          explorerModeEnabled: false,
          explorerModeExpiresAt: null,
        );
        notifyListeners();
      }
    });

    // Also set up a periodic timer to notify UI updates (for countdown)
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!isExplorerModeActive) {
        timer.cancel();
      } else {
        notifyListeners(); // Update UI to show remaining time
      }
    });
  }

  /// Stop explorer mode timer
  void _stopExplorerModeTimer() {
    _explorerModeTimer?.cancel();
    _explorerModeTimer = null;
  }

  /// Start weekly suggestions refresh timer
  void startSuggestionsRefreshTimer() {
    _stopSuggestionsRefreshTimer();

    // Refresh suggestions weekly
    _suggestionsRefreshTimer = Timer.periodic(
      const Duration(days: 7),
      (timer) {
        loadLocationSuggestions();
      },
    );

    // Load initial suggestions
    loadLocationSuggestions();
  }

  /// Stop suggestions refresh timer
  void _stopSuggestionsRefreshTimer() {
    _suggestionsRefreshTimer?.cancel();
    _suggestionsRefreshTimer = null;
  }

  @override
  void dispose() {
    _stopExplorerModeTimer();
    _stopSuggestionsRefreshTimer();
    super.dispose();
  }
}

