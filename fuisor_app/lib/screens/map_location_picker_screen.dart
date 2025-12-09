import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'dart:async';
import '../models/user.dart';
import '../services/geocoding_service.dart';

class MapLocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const MapLocationPickerScreen({
    Key? key,
    this.initialLatitude,
    this.initialLongitude,
  }) : super(key: key);

  @override
  State<MapLocationPickerScreen> createState() => _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  MapboxMap? _mapboxMap;
  double? _selectedLatitude;
  double? _selectedLongitude;
  bool _isLoading = false;
  LocationInfo? _locationInfo;
  bool _hasUserSelectedLocation = false; // Флаг для отслеживания выбора пользователем

  @override
  void initState() {
    super.initState();
    _loadInitialLocation();
  }

  Future<void> _loadInitialLocation() async {
    // Если пользователь уже выбрал место на карте, не переопределяем его
    if (_hasUserSelectedLocation) {
      return;
    }
    
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLatitude = widget.initialLatitude;
      _selectedLongitude = widget.initialLongitude;
      await _updateLocationInfo(widget.initialLatitude!, widget.initialLongitude!);
    } else {
      // Загружаем текущее местоположение только при первой загрузке
      try {
        geo.LocationPermission permission = await geo.Geolocator.checkPermission();
        if (permission == geo.LocationPermission.denied) {
          permission = await geo.Geolocator.requestPermission();
        }

        if (permission == geo.LocationPermission.denied ||
            permission == geo.LocationPermission.deniedForever) {
          // Используем координаты по умолчанию (Кишинев)
          _selectedLatitude = 47.0104;
          _selectedLongitude = 28.8601;
          await _updateLocationInfo(_selectedLatitude!, _selectedLongitude!);
          return;
        }

        geo.Position position = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high,
        );

        _selectedLatitude = position.latitude;
        _selectedLongitude = position.longitude;
        await _updateLocationInfo(position.latitude, position.longitude);
        
        // Перемещаем карту к текущему местоположению только если пользователь еще не выбирал
        if (_mapboxMap != null && !_hasUserSelectedLocation) {
          final point = Point(
            coordinates: Position(
              position.longitude,
              position.latitude,
            ),
          );
          await _mapboxMap!.flyTo(
            CameraOptions(
              center: point,
              zoom: 15.0,
            ),
            MapAnimationOptions(duration: 1000, startDelay: 0),
          );
        }
      } catch (e) {
        print('Error loading current location: $e');
        // Используем координаты по умолчанию
        _selectedLatitude = 47.0104;
        _selectedLongitude = 28.8601;
        await _updateLocationInfo(_selectedLatitude!, _selectedLongitude!);
      }
    }
  }

  Future<void> _updateLocationInfo(double latitude, double longitude) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final location = await GeocodingService.getLocationFromCoordinates(
        latitude,
        longitude,
      );

      setState(() {
        _locationInfo = location;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error updating location info: $e');
    }
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  Future<void> _updateLocationFromMapCenter() async {
    if (_mapboxMap == null) return;
    
    try {
      // Получаем размер экрана для определения центра
      final screenSize = MediaQuery.of(context).size;
      final centerX = screenSize.width / 2;
      final centerY = screenSize.height / 2;
      
      // Получаем координаты центра экрана на карте
      final coordinate = await _mapboxMap!.coordinateForPixel(
        ScreenCoordinate(
          x: centerX,
          y: centerY,
        ),
      );
      
      final coordinates = coordinate.coordinates;
        double latitude;
        double longitude;
        
        try {
          // Position из mapbox_maps_flutter содержит координаты как список [longitude, latitude]
          // Пробуем разные варианты извлечения координат
          if (coordinates is List && coordinates.length >= 2) {
            // Пробуем как список
            longitude = (coordinates[0] as num).toDouble();
            latitude = (coordinates[1] as num).toDouble();
          } else {
            // Position - это объект, но координаты доступны через индексацию
            // Пробуем получить через динамический доступ
            final pos = coordinates as dynamic;
            try {
              // Пробуем получить через индексацию [0] и [1]
              longitude = (pos[0] as num).toDouble();
              latitude = (pos[1] as num).toDouble();
            } catch (e) {
              // Если индексация не работает, пробуем как Map
              try {
                final coordsMap = coordinates as Map<String, dynamic>;
                longitude = (coordsMap['longitude'] ?? coordsMap['lng'] ?? 0.0) as double;
                latitude = (coordsMap['latitude'] ?? coordsMap['lat'] ?? 0.0) as double;
              } catch (e2) {
                print('Error parsing coordinates: $e2, type: ${coordinates.runtimeType}');
                return; // Выходим, если не можем получить координаты
              }
            }
          }
          
          // Обновляем координаты и информацию о локации
          if ((latitude != _selectedLatitude) || (longitude != _selectedLongitude)) {
            _selectedLatitude = latitude;
            _selectedLongitude = longitude;
            _hasUserSelectedLocation = true;
            // Обновляем информацию о локации с небольшой задержкой, чтобы не делать слишком много запросов
            _debounceUpdateLocation(latitude, longitude);
          }
        } catch (e) {
          print('Error parsing camera coordinates: $e, type: ${coordinates.runtimeType}');
        }
    } catch (e) {
      print('Error getting map center coordinates: $e');
    }
  }

  Timer? _updateLocationTimer;
  
  void _debounceUpdateLocation(double latitude, double longitude) {
    // Отменяем предыдущий таймер, если он есть
    _updateLocationTimer?.cancel();
    
    // Устанавливаем новый таймер с задержкой 500ms
    _updateLocationTimer = Timer(const Duration(milliseconds: 500), () {
      _updateLocationInfo(latitude, longitude);
    });
  }

  Future<void> _onMapTap(TapDownDetails details) async {
    if (_mapboxMap == null) return;

    try {
      // Получаем координаты точки нажатия
      final coordinate = await _mapboxMap!.coordinateForPixel(
        ScreenCoordinate(
          x: details.localPosition.dx,
          y: details.localPosition.dy,
        ),
      );
      
      {
        // coordinate - это Point, извлекаем координаты
        // Position содержит координаты как [longitude, latitude]
        final coordinates = coordinate.coordinates;
        // Position может быть списком или объектом, пробуем разные варианты
        double latitude;
        double longitude;
        
        try {
          // Пробуем как список
          if (coordinates is List && coordinates.length >= 2) {
            longitude = (coordinates[0] as num).toDouble();
            latitude = (coordinates[1] as num).toDouble();
          } else {
            // Пробуем как объект с полями
            final coordsMap = coordinates as Map<String, dynamic>;
            longitude = (coordsMap['longitude'] ?? coordsMap['lng'] ?? coordsMap[0] ?? 0.0) as double;
            latitude = (coordsMap['latitude'] ?? coordsMap['lat'] ?? coordsMap[1] ?? 0.0) as double;
          }
          
          _selectedLatitude = latitude;
          _selectedLongitude = longitude;
          _hasUserSelectedLocation = true; // Отмечаем, что пользователь выбрал место
          await _updateLocationInfo(latitude, longitude);
        } catch (e) {
          print('Error parsing coordinates: $e, coordinates: $coordinates');
        }
      }
    } catch (e) {
      print('Error getting coordinate for pixel: $e');
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      setState(() {
        _isLoading = true;
      });

      geo.LocationPermission permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      if (permission == geo.LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Location permission denied forever. Please enable in settings.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      geo.Position position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );

      _selectedLatitude = position.latitude;
      _selectedLongitude = position.longitude;

      await _updateLocationInfo(position.latitude, position.longitude);

      // Перемещаем карту к текущему местоположению
      if (_mapboxMap != null) {
        final point = Point(
          coordinates: Position(
            position.longitude,
            position.latitude,
          ),
        );
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: point,
            zoom: 15.0,
          ),
          MapAnimationOptions(duration: 1000, startDelay: 0),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _confirmSelection() {
    if (_selectedLatitude == null || _selectedLongitude == null || _locationInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a location on the map'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'latitude': _selectedLatitude,
      'longitude': _selectedLongitude,
      'locationInfo': _locationInfo,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Choose location',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(EvaIcons.checkmark, color: Colors.white),
              onPressed: _confirmSelection,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Карта с обработчиком нажатий
          GestureDetector(
            onTapDown: _onMapTap,
            child: Listener(
              onPointerMove: (_) => _updateLocationFromMapCenter(),
              onPointerUp: (_) => _updateLocationFromMapCenter(),
              child: MapWidget(
                key: const ValueKey("mapWidget"),
                cameraOptions: CameraOptions(
                  center: (_selectedLatitude != null && _selectedLongitude != null)
                      ? Point(
                          coordinates: Position(
                            _selectedLongitude!,
                            _selectedLatitude!,
                          ),
                        )
                      : Point(
                          coordinates: Position(28.8601, 47.0104), // Кишинев по умолчанию
                        ),
                  zoom: 13.0,
                ),
                styleUri: MapboxStyles.MAPBOX_STREETS,
              onMapCreated: _onMapCreated,
              ),
            ),
          ),

          // Информация о выбранной локации (наверху, под AppBar)
          if (_locationInfo != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          EvaIcons.pinOutline,
                          color: Color(0xFF0095F6),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_locationInfo!.city != null)
                                Text(
                                  _locationInfo!.city!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (_locationInfo!.district != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _locationInfo!.district!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (_locationInfo!.street != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _locationInfo!.street!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Индикатор центра карты (маркер)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  EvaIcons.pin,
                  color: Color(0xFF0095F6),
                  size: 40,
                ),
                SizedBox(height: 2),
                Icon(
                  EvaIcons.arrowDownward,
                  color: Color(0xFF0095F6),
                  size: 20,
                ),
              ],
            ),
          ),

          // Кнопки (компактные, внизу)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    width: 200,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _isLoading ? null : _useCurrentLocation,
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(EvaIcons.navigationOutline, size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'My location',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    width: 200,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isLoading
                          ? const Color(0xFF8E8E8E)
                          : const Color(0xFF0095F6),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: _isLoading
                          ? []
                          : [
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
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: _isLoading ? null : _confirmSelection,
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(EvaIcons.checkmark, size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Select',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
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
        ],
      ),
    );
  }

  @override
  void dispose() {
    _updateLocationTimer?.cancel();
    _mapboxMap = null;
    super.dispose();
  }
}
