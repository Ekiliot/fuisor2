import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class GeocodingService {
  // Production API URL (должен совпадать с ApiService.baseUrl)
  static const String baseUrl = 'https://api.sonetapp.tech/api';
  
  // Кэш для городов (обновляется раз в час)
  static List<String>? _cachedCities;
  static DateTime? _citiesCacheTime;
  static const Duration _cacheDuration = Duration(hours: 1);

  // Кэш для районов по городам
  static final Map<String, List<String>> _cachedDistricts = {};
  static final Map<String, DateTime> _districtsCacheTime = {};
  
  /// Очищает весь кэш (для отладки)
  static void clearCache() {
    _cachedCities = null;
    _citiesCacheTime = null;
    _cachedDistricts.clear();
    _districtsCacheTime.clear();
    print('GeocodingService: Cache cleared');
  }
  /// Получает информацию о локации из координат используя OpenStreetMap Nominatim
  static Future<LocationInfo?> getLocationFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      // Прямой запрос к OpenStreetMap Nominatim API
      // Используем румынский язык (ro) как основной, чтобы все локации сохранялись на румынском
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&addressdetails=1&accept-language=ro'
      );
      
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'FuisorApp/1.0', // Требуется Nominatim
        },
      );

      if (response.statusCode != 200) {
        print('GeocodingService: Nominatim API error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;
      
      if (address == null) {
        print('GeocodingService: No address data in response');
        return null;
      }

      // Отладочный вывод для диагностики
      print('GeocodingService: Address data: $address');

      // Извлекаем страну
      final country = address['country'] as String?;

      // Извлекаем город (пробуем разные поля)
      final city = address['city'] as String? ?? 
                   address['town'] as String? ?? 
                   address['municipality'] as String? ??
                   address['village'] as String?;

      // Извлекаем район (пробуем разные поля)
      // В Молдове/Кишиневе район может быть в разных полях
      String? district = address['suburb'] as String? ??
                         address['neighbourhood'] as String? ??
                         address['quarter'] as String? ??
                         address['city_district'] as String? ??
                         address['district'] as String? ??
                         address['residential'] as String? ??
                         address['subdistrict'] as String?;
      
      // Если район не найден в стандартных полях, пробуем извлечь из display_name
      if (district == null || district.isEmpty) {
        final displayName = data['display_name'] as String?;
        if (displayName != null) {
          // Пробуем найти известные районы Кишинева в display_name (на румынском)
          final displayLower = displayName.toLowerCase();
          if (displayLower.contains('ботаника') || displayLower.contains('botanica')) {
            district = 'Botanica';
          } else if (displayLower.contains('центр') || displayLower.contains('centru')) {
            district = 'Centru';
          } else if (displayLower.contains('ришкановка') || displayLower.contains('riscani')) {
            district = 'Rîșcani';
          } else if (displayLower.contains('чеканы') || displayLower.contains('ciocana')) {
            district = 'Ciocana';
          } else if (displayLower.contains('буюканы') || displayLower.contains('buiucani')) {
            district = 'Buiucani';
          }
        }
      }

      // Извлекаем название улицы (тип + название, но без номера дома)
      // Номер дома находится в отдельном поле house_number, так что road уже не содержит его
      final street = address['road'] as String?;

      // Извлекаем полный адрес (название улицы с номером дома)
      final addressFull = address['display_name'] as String?;

      return LocationInfo(
        country: country,
        city: city,
        district: district,
        street: street, // Полное название улицы (тип + название, без номера дома)
        address: addressFull,
      );
    } catch (e) {
      print('GeocodingService: Error geocoding: $e');
      return null;
    }
  }

  /// Получает список городов Молдовы из нашей базы данных (таблица locations)
  /// Использует кэширование (обновляется раз в час)
  static Future<List<String>> getCitiesInMoldova() async {
    print('GeocodingService: getCitiesInMoldova called');
    
    // Проверяем кэш (только если он не пустой и не устарел)
    if (_cachedCities != null && 
        _cachedCities!.isNotEmpty &&
        _citiesCacheTime != null && 
        DateTime.now().difference(_citiesCacheTime!) < _cacheDuration) {
      print('GeocodingService: Returning cached cities: ${_cachedCities!.length}');
      return _cachedCities!;
    }

    print('GeocodingService: Loading cities from API...');
    
    try {
      // Загружаем города из нашего API (из таблицы locations)
      final url = Uri.parse('$baseUrl/users/locations/cities?country=Moldova');
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token'); // Исправлено: было auth_token
      
      if (token == null) {
        print('GeocodingService: No access token, returning empty list');
        return [];
      }
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final cities = (data['cities'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [];
        
        print('GeocodingService: Loaded ${cities.length} cities from API');
        
        // Сохраняем в кэш
        _cachedCities = cities;
        _citiesCacheTime = DateTime.now();
        
        return cities;
      } else {
        print('GeocodingService: API returned status ${response.statusCode}');
      }
    } catch (e) {
      print('GeocodingService: Error loading cities from API: $e');
    }

    // Если API не сработал, возвращаем пустой список
    print('GeocodingService: Returning empty list');
    return [];
  }

  /// Получает список районов для конкретного города используя Nominatim Search API
  /// Использует кэширование (обновляется раз в час)
  static Future<List<String>> getDistrictsForCity(String city) async {
    final cityKey = city.toLowerCase();
    
    // Проверяем кэш
    if (_cachedDistricts.containsKey(cityKey) && 
        _districtsCacheTime.containsKey(cityKey) &&
        DateTime.now().difference(_districtsCacheTime[cityKey]!) < _cacheDuration) {
      return _cachedDistricts[cityKey]!;
    }

    try {
      // Загружаем районы из нашего API (из таблицы locations)
      final url = Uri.parse(
        '$baseUrl/users/locations/districts?city=${Uri.encodeComponent(city)}&country=Moldova'
      );
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token'); // Исправлено: было auth_token
      
      if (token == null) {
        print('GeocodingService: No access token for districts');
        return [];
      }
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final districts = (data['districts'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [];
        
        print('GeocodingService: Loaded ${districts.length} districts for $city from API');
        
        // Сохраняем в кэш
        _cachedDistricts[cityKey] = districts;
        _districtsCacheTime[cityKey] = DateTime.now();
        
        return districts;
      } else {
        print('GeocodingService: API returned status ${response.statusCode}');
      }
    } catch (e) {
      print('GeocodingService: Error loading districts from API: $e');
    }

    // Если API не сработал, возвращаем пустой список
    print('GeocodingService: Returning empty districts list for $city');
    return [];
  }
}

