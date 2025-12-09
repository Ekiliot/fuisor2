import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../models/user.dart';
import '../services/geocoding_service.dart';
import 'package:geolocator/geolocator.dart';
import '../screens/map_location_picker_screen.dart';

class LocationSelector extends StatefulWidget {
  final Function(LocationInfo?, Set<String>)? onLocationChanged;
  final LocationInfo? initialLocation;
  final Set<String>? initialVisibility;

  const LocationSelector({
    Key? key,
    this.onLocationChanged,
    this.initialLocation,
    this.initialVisibility,
  }) : super(key: key);

  @override
  State<LocationSelector> createState() => _LocationSelectorState();
}

class _LocationSelectorState extends State<LocationSelector> {
  bool _isPostBoosterEnabled = false;
  bool _isLoadingLocation = false;
  LocationInfo? _locationInfo;
  Set<String> _selectedVisibility = {};
  double? _latitude;
  double? _longitude;
  
  // Чекбоксы
  bool _showCountry = false;
  bool _showCity = false;
  bool _showDistrict = false;
  bool _showStreet = false;
  bool _showAddress = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _locationInfo = widget.initialLocation;
      _isPostBoosterEnabled = true;
    }
    if (widget.initialVisibility != null && widget.initialVisibility!.isNotEmpty) {
      _selectedVisibility = Set<String>.from(widget.initialVisibility!);
      _showCountry = _selectedVisibility.contains('country');
      _showCity = _selectedVisibility.contains('city');
      _showDistrict = _selectedVisibility.contains('district');
      _showStreet = _selectedVisibility.contains('street');
      _showAddress = _selectedVisibility.contains('address');
    }
  }

  Future<void> _requestLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Проверяем разрешения
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied forever');
      }

      // Получаем координаты
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Выполняем геокодирование
      LocationInfo? location = await GeocodingService.getLocationFromCoordinates(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _locationInfo = location;
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isLoadingLocation = false;
      });

      if (location != null && widget.onLocationChanged != null) {
        widget.onLocationChanged!(location, _selectedVisibility);
      }
    } catch (e) {
      setState(() {
        _isLoadingLocation = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _updateVisibility() {
    _selectedVisibility.clear();
    if (_showCountry) _selectedVisibility.add('country');
    if (_showCity) _selectedVisibility.add('city');
    if (_showDistrict) _selectedVisibility.add('district');
    if (_showStreet) _selectedVisibility.add('street');
    if (_showAddress) _selectedVisibility.add('address');

    if (widget.onLocationChanged != null) {
      widget.onLocationChanged!(_locationInfo, _selectedVisibility);
    }
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapLocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _isLoadingLocation = true;
      });

      try {
        final latitude = result['latitude'] as double;
        final longitude = result['longitude'] as double;
        final locationInfo = result['locationInfo'] as LocationInfo?;

        setState(() {
          _latitude = latitude;
          _longitude = longitude;
          _locationInfo = locationInfo;
          _isLoadingLocation = false;
        });

        if (locationInfo != null && widget.onLocationChanged != null) {
          widget.onLocationChanged!(locationInfo, _selectedVisibility);
        }
      } catch (e) {
        setState(() {
          _isLoadingLocation = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Тумблер Geo boost
        ListTile(
          title: const Text(
            'Geo boost',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Show post location',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          trailing: CupertinoSwitch(
            value: _isPostBoosterEnabled,
            onChanged: (value) {
              setState(() {
                _isPostBoosterEnabled = value;
                if (!value) {
                  _locationInfo = null;
                  _selectedVisibility.clear();
                  _showCountry = false;
                  _showCity = false;
                  _showDistrict = false;
                  _showStreet = false;
                  _showAddress = false;
                  if (widget.onLocationChanged != null) {
                    widget.onLocationChanged!(null, {});
                  }
                } else {
                  // Не запрашиваем локацию автоматически, показываем кнопки выбора
                }
              });
            },
            activeColor: const Color(0xFF0095F6),
          ),
        ),

        // Кнопки выбора места (показываются только если тумблер включен)
        if (_isPostBoosterEnabled) ...[
          if (_isLoadingLocation)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_locationInfo == null) ...[
            // Показываем кнопки выбора места, если локация еще не выбрана
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 200,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0095F6),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
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
                          onTap: _requestLocation,
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(EvaIcons.navigationOutline, size: 18, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Use current location',
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
                  const SizedBox(height: 12),
                  Center(
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
                          onTap: _openMapPicker,
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(EvaIcons.mapOutline, size: 18, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Choose on map',
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
          ] else ...[
            // Показываем информацию о выбранной локации и кнопки изменения
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(EvaIcons.pinOutline, color: Colors.white70, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_locationInfo!.city != null)
                            Text(
                              _locationInfo!.city!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (_locationInfo!.district != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _locationInfo!.district!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(EvaIcons.editOutline, size: 18, color: Colors.white70),
                      onPressed: _openMapPicker,
                      tooltip: 'Change location',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'What to show:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: CupertinoCheckbox(
                value: _showCountry,
                onChanged: (value) {
                  setState(() {
                    _showCountry = value ?? false;
                    _updateVisibility();
                  });
                },
                activeColor: const Color(0xFF0095F6),
              ),
              title: const Text('Country', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _showCountry = !_showCountry;
                  _updateVisibility();
                });
              },
            ),
            ListTile(
              leading: CupertinoCheckbox(
                value: _showCity,
                onChanged: (value) {
                  setState(() {
                    _showCity = value ?? false;
                    _updateVisibility();
                  });
                },
                activeColor: const Color(0xFF0095F6),
              ),
              title: const Text('City', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _showCity = !_showCity;
                  _updateVisibility();
                });
              },
            ),
            ListTile(
              leading: CupertinoCheckbox(
                value: _showDistrict,
                onChanged: (value) {
                  setState(() {
                    _showDistrict = value ?? false;
                    _updateVisibility();
                  });
                },
                activeColor: const Color(0xFF0095F6),
              ),
              title: const Text('District', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _showDistrict = !_showDistrict;
                  _updateVisibility();
                });
              },
            ),
            ListTile(
              leading: CupertinoCheckbox(
                value: _showStreet,
                onChanged: (value) {
                  setState(() {
                    _showStreet = value ?? false;
                    _updateVisibility();
                  });
                },
                activeColor: const Color(0xFF0095F6),
              ),
              title: const Text('Street', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _showStreet = !_showStreet;
                  _updateVisibility();
                });
              },
            ),
            ListTile(
              leading: CupertinoCheckbox(
                value: _showAddress,
                onChanged: (value) {
                  setState(() {
                    _showAddress = value ?? false;
                    _updateVisibility();
                  });
                },
                activeColor: const Color(0xFF0095F6),
              ),
              title: const Text('Specific address', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _showAddress = !_showAddress;
                  _updateVisibility();
                });
              },
            ),
          ],
        ],
      ],
    );
  }
}

