import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pretty_animated_text/pretty_animated_text.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'dart:convert';
import '../models/user.dart';
import '../providers/recommendation_provider.dart';
import '../providers/posts_provider.dart';
import '../services/geocoding_service.dart';
import '../widgets/app_notification.dart';

class RecommendationSettingsScreen extends StatefulWidget {
  const RecommendationSettingsScreen({super.key});

  @override
  State<RecommendationSettingsScreen> createState() => _RecommendationSettingsScreenState();
}

class _RecommendationSettingsScreenState extends State<RecommendationSettingsScreen> {
  bool _enabled = false;
  bool _autoLocation = false;
  bool _explorerMode = false;
  List<LocationInfo> _locations = [];
  double _radius = 0;
  bool _isLoading = false;
  Set<String> _dismissedSuggestions = {}; // Скрытые рекомендации

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
      _loadDismissedSuggestions();
    });
  }

  Future<void> _loadDismissedSuggestions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissedJson = prefs.getString('dismissed_location_suggestions');
      if (dismissedJson != null) {
        final List<dynamic> dismissed = jsonDecode(dismissedJson);
        setState(() {
          _dismissedSuggestions = dismissed.map((e) => e.toString()).toSet();
        });
      }
    } catch (e) {
      print('Error loading dismissed suggestions: $e');
    }
  }

  Future<void> _dismissSuggestion(LocationSuggestion suggestion) async {
    try {
      final key = '${suggestion.country}|${suggestion.city}|${suggestion.district}';
      setState(() {
        _dismissedSuggestions.add(key);
      });
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'dismissed_location_suggestions',
        jsonEncode(_dismissedSuggestions.toList()),
      );
    } catch (e) {
      print('Error dismissing suggestion: $e');
    }
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    
    final recProvider = Provider.of<RecommendationProvider>(context, listen: false);
    await recProvider.loadSettings();
    await recProvider.loadLocationSuggestions();
    
    if (!mounted) return;
    
    if (recProvider.settings != null) {
      final settings = recProvider.settings!;
      // Тумблер включен, если активен режим исследователя, есть выбранные локации или включено автоопределение
      final shouldBeEnabled = settings.explorerModeEnabled || 
                              settings.locations.isNotEmpty || 
                              settings.autoLocation ||
                              settings.enabled;
      
      if (mounted) {
        setState(() {
          _enabled = shouldBeEnabled;
          _autoLocation = settings.autoLocation;
          _explorerMode = settings.explorerModeEnabled;
          _locations = List.from(settings.locations);
          _radius = (settings.radius ?? 0).toDouble();
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    try {
      final recProvider = Provider.of<RecommendationProvider>(context, listen: false);
      final postsProvider = Provider.of<PostsProvider>(context, listen: false);
      
      final newSettings = RecommendationSettings(
        locations: _locations,
        radius: _radius.toInt(),
        autoLocation: _autoLocation,
        enabled: _enabled,
        promptShown: true,
      );

      await recProvider.updateSettings(newSettings);
      
      // Reload feed with new settings
      postsProvider.loadFeed(refresh: true);

      if (mounted) {
        AppNotification.showSuccess(context, 'Settings saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'Error: ${e.toString()}');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addLocation() {
    if (_locations.length >= 3) {
      AppNotification.showInfo(context, 'Maximum 3 locations');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          onLocationsSelected: (selectedLocations) {
            setState(() {
              // Добавляем только новые локации, которых еще нет
              for (final location in selectedLocations) {
                if (!_locations.any((loc) => 
                    loc.city == location.city && 
                    loc.district == location.district)) {
                  if (_locations.length < 3) {
                    _locations.add(location);
                  }
                }
              }
            });
          },
        ),
      ),
    );
  }

  void _removeLocation(int index) {
    setState(() {
      _locations.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: BlurText(
          text: 'Recommendation',
          duration: const Duration(seconds: 1),
          type: AnimationType.word,
          textStyle: GoogleFonts.delaGothicOne(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
      ),
      body: Consumer<RecommendationProvider>(
        builder: (context, recProvider, child) {
          if (recProvider.isLoading && !_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main toggle
                _buildSection(
                  title: 'Personalized Recommendations',
                  child: ListTile(
                    title: const Text('Enable', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'Posts from selected locations',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    trailing: CupertinoSwitch(
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                  ),
                ),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.1),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        )),
                        child: child,
                      ),
                    );
                  },
                  child: _enabled
                      ? Column(
                          key: const ValueKey('enabled_content'),
                          children: [
                            const SizedBox(height: 24),

                            // Explorer mode
                            _buildSection(
                    title: 'Explorer Mode',
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(EvaIcons.compassOutline, color: Colors.blue),
                          title: const Text('Explorer', style: TextStyle(color: Colors.white)),
                          subtitle: recProvider.isExplorerModeActive
                              ? Text(
                                  'Remaining: ${recProvider.settings?.explorerModeRemainingMinutes ?? 0} min',
                                  style: TextStyle(color: Colors.blue[300]),
                                )
                              : Text(
                                  'Discover new content from around the world',
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                          trailing: CupertinoSwitch(
                            value: _explorerMode,
                            onChanged: (value) async {
                              if (value) {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: Colors.grey[900],
                                    title: const Text('Explorer Mode', style: TextStyle(color: Colors.white)),
                                    content: const Text(
                                      'Activate for 15 minutes?\n\nYou will see random posts from around the world.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      // Cancel button
                                      Container(
                                        width: 120,
                                        height: 48,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[800],
                                          borderRadius: BorderRadius.circular(24),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(24),
                                            onTap: () => Navigator.pop(context, false),
                                            child: const Center(
                                              child: Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.5,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Activate button
                                      Container(
                                        width: 120,
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
                                            onTap: () => Navigator.pop(context, true),
                                            child: const Center(
                                              child: Text(
                                                'Activate',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.5,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed == true) {
                                  await recProvider.toggleExplorerMode(true);
                                  setState(() => _explorerMode = true);
                                }
                              } else {
                                await recProvider.toggleExplorerMode(false);
                                setState(() => _explorerMode = false);
                              }
                            },
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, -0.05),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOut,
                                )),
                                child: child,
                              ),
                            );
                          },
                          child: recProvider.isExplorerModeActive
                              ? Padding(
                                  key: const ValueKey('explorer_info'),
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'Explorer mode: World (50%), Moldova (30%), nearby districts (20%)',
                                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                  ),
                                )
                              : const SizedBox.shrink(key: ValueKey('no_explorer_info')),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Smart suggestions
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.1),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          )),
                          child: child,
                        ),
                      );
                    },
                    child: recProvider.suggestions.isNotEmpty &&
                            recProvider.suggestions.any((suggestion) {
                              final key = '${suggestion.country}|${suggestion.city}|${suggestion.district}';
                              return !_dismissedSuggestions.contains(key);
                            })
                        ? Column(
                            key: const ValueKey('suggestions'),
                            children: [
                              _buildSection(
                                title: 'Recommended Locations',
                                child: Column(
                                  children: recProvider.suggestions
                                      .where((suggestion) {
                                        final key = '${suggestion.country}|${suggestion.city}|${suggestion.district}';
                                        return !_dismissedSuggestions.contains(key);
                                      })
                                      .map((suggestion) {
                                        return TweenAnimationBuilder<double>(
                                          duration: const Duration(milliseconds: 300),
                                          tween: Tween(begin: 0.0, end: 1.0),
                                          builder: (context, value, child) {
                                            return Opacity(
                                              opacity: value,
                                              child: Transform.translate(
                                                offset: Offset(0, 10 * (1 - value)),
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: ListTile(
                                            title: Text(
                                              '${suggestion.district}, ${suggestion.city}',
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                            subtitle: Text(
                                              'You interacted with ${suggestion.interactionCount} posts from here',
                                              style: TextStyle(color: Colors.grey[400]),
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                InkWell(
                                                  onTap: () {
                                                    if (_locations.length < 3) {
                                                      setState(() {
                                                        _locations.add(LocationInfo(
                                                          country: suggestion.country,
                                                          city: suggestion.city,
                                                          district: suggestion.district,
                                                        ));
                                                      });
                                                    }
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    child: Icon(EvaIcons.plusCircleOutline, color: Colors.blue, size: 20),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () {
                                                    _dismissSuggestion(suggestion);
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    child: Icon(EvaIcons.closeCircleOutline, color: Colors.red, size: 20),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          )
                        : const SizedBox.shrink(key: ValueKey('no_suggestions')),
                  ),

                  // Location mode
                  _buildSection(
                    title: 'Detection Mode',
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Automatic Detection', style: TextStyle(color: Colors.white)),
                          leading: CupertinoCheckbox(
                            value: _autoLocation == true,
                            onChanged: (value) => setState(() => _autoLocation = true),
                            activeColor: const Color(0xFF0095F6),
                            checkColor: Colors.white,
                          ),
                          onTap: () => setState(() => _autoLocation = true),
                        ),
                        ListTile(
                          title: const Text('Manual Selection', style: TextStyle(color: Colors.white)),
                          leading: CupertinoCheckbox(
                            value: _autoLocation == false,
                            onChanged: (value) => setState(() => _autoLocation = false),
                            activeColor: const Color(0xFF0095F6),
                            checkColor: Colors.white,
                          ),
                          onTap: () => setState(() => _autoLocation = false),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Manual location selection
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.1),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          )),
                          child: child,
                        ),
                      );
                    },
                    child: !_autoLocation
                        ? Column(
                            key: const ValueKey('manual_selection'),
                            children: [
                              _buildSection(
                                title: 'Selected Locations (${_locations.length}/3)',
                                child: Column(
                                  children: [
                                    ..._locations.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final location = entry.value;
                                      return TweenAnimationBuilder<double>(
                                        duration: const Duration(milliseconds: 300),
                                        tween: Tween(begin: 0.0, end: 1.0),
                                        builder: (context, value, child) {
                                          return Opacity(
                                            opacity: value,
                                            child: Transform.translate(
                                              offset: Offset(0, 10 * (1 - value)),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: ListTile(
                                          title: Text(
                                            location.toString(),
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(EvaIcons.minusCircleOutline, color: Colors.red),
                                            onPressed: () => _removeLocation(index),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    if (_locations.length < 3)
                                      TweenAnimationBuilder<double>(
                                        duration: const Duration(milliseconds: 300),
                                        tween: Tween(begin: 0.0, end: 1.0),
                                        builder: (context, value, child) {
                                          return Opacity(
                                            opacity: value,
                                            child: Transform.translate(
                                              offset: Offset(0, 10 * (1 - value)),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: ListTile(
                                          leading: const Icon(EvaIcons.pinOutline, color: Colors.blue),
                                          title: const Text('Add Location', style: TextStyle(color: Colors.blue)),
                                          onTap: _addLocation,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          )
                        : const SizedBox.shrink(key: ValueKey('auto_selection')),
                  ),

                  // Radius slider
                  _buildSection(
                    title: 'Search Radius',
                    child: Column(
                      children: [
                        Slider(
                          value: _radius,
                          min: 0,
                          max: 100000,
                          divisions: 20,
                          label: _radius == 0 ? '0 m' : '${(_radius / 1000).toStringAsFixed(0)} km',
                          onChanged: (value) => setState(() => _radius = value),
                        ),
                        Text(
                          _radius == 0 ? 'Radius: 0 m' : 'Radius: ${(_radius / 1000).toStringAsFixed(0)} km',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Show posts within radius from selected location',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('disabled_content')),
                ),

                const SizedBox(height: 32),

                // Save button
                Center(
                  child: Container(
                    width: 200,
                    height: 56,
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
                        onTap: _isLoading ? null : _saveSettings,
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Save',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// Экран выбора локаций с чекбоксами
class LocationPickerScreen extends StatefulWidget {
  final Function(List<LocationInfo>) onLocationsSelected;

  const LocationPickerScreen({super.key, required this.onLocationsSelected});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  List<String> _cities = [];
  Map<String, List<String>> _districtsByCity = {};
  Map<String, bool> _selectedCities = {};
  Map<String, Map<String, bool>> _selectedDistricts = {}; // city -> {district -> selected}
  bool _isLoadingCities = true;
  Map<String, bool> _loadingDistricts = {};

  @override
  void initState() {
    super.initState();
    // Очищаем кэш при первой загрузке экрана, чтобы гарантировать свежие данные
    GeocodingService.clearCache();
    _loadCities();
  }

  Future<void> _loadCities() async {
    print('LocationPickerScreen: Starting to load cities...');
    setState(() => _isLoadingCities = true);
    try {
      final cities = await GeocodingService.getCitiesInMoldova();
      print('LocationPickerScreen: Loaded ${cities.length} cities: $cities');
      if (mounted) {
        setState(() {
          _cities = cities;
          _isLoadingCities = false;
          // Инициализируем карты выбора
          for (final city in cities) {
            _selectedCities[city] = false;
            _selectedDistricts[city] = {};
          }
        });
        print('LocationPickerScreen: State updated with ${_cities.length} cities');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCities = false);
      }
      print('LocationPickerScreen: Error loading cities: $e');
    }
  }

  Future<void> _loadDistricts(String city) async {
    if (_districtsByCity.containsKey(city)) {
      return; // Уже загружены
    }

    setState(() {
      _loadingDistricts[city] = true;
    });

    try {
      final districts = await GeocodingService.getDistrictsForCity(city);
      if (mounted) {
        setState(() {
          _districtsByCity[city] = districts;
          _loadingDistricts[city] = false;
          // Инициализируем чекбоксы для районов
          for (final district in districts) {
            _selectedDistricts[city]![district] = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingDistricts[city] = false);
      }
      print('Error loading districts for $city: $e');
    }
  }

  void _onCityToggled(String city, bool? value) {
    setState(() {
      _selectedCities[city] = value ?? false;
      
      // Если город выбран, загружаем районы
      if (value == true && !_districtsByCity.containsKey(city)) {
        _loadDistricts(city);
      }
      
      // Если город снят, снимаем все районы
      if (value == false) {
        _selectedDistricts[city]?.forEach((key, _) {
          _selectedDistricts[city]![key] = false;
        });
      }
    });
  }

  void _onDistrictToggled(String city, String district, bool? value) {
    setState(() {
      _selectedDistricts[city]![district] = value ?? false;
    });
  }

  void _saveSelectedLocations() {
    final selectedLocations = <LocationInfo>[];
    
    for (final city in _cities) {
      if (_selectedCities[city] == true) {
        // Проверяем, выбраны ли районы для этого города
        final selectedDistricts = _selectedDistricts[city]?.entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toList() ?? [];
        
        if (selectedDistricts.isEmpty) {
          // Если нет выбранных районов, добавляем город без района
          selectedLocations.add(LocationInfo(
            country: 'Moldova',
            city: city,
            district: null,
          ));
        } else {
          // Добавляем локацию для каждого выбранного района
          for (final district in selectedDistricts) {
            selectedLocations.add(LocationInfo(
              country: 'Moldova',
              city: city,
              district: district,
            ));
          }
        }
      }
    }
    
    widget.onLocationsSelected(selectedLocations);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: BlurText(
          text: 'Locations',
          duration: const Duration(seconds: 1),
          type: AnimationType.word,
          textStyle: GoogleFonts.delaGothicOne(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        actions: [
          Container(
            width: 80,
            height: 36,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0095F6),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0095F6).withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _saveSelectedLocations,
                child: const Center(
                  child: Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoadingCities
          ? const Center(child: CircularProgressIndicator())
          : _cities.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(EvaIcons.navigation2Outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'Cities not found',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
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
                            onTap: _loadCities,
                            child: const Center(
                              child: Text(
                                'Retry',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cities.length,
                  itemBuilder: (context, index) {
                    final city = _cities[index];
                    final isCitySelected = _selectedCities[city] ?? false;
                    final districts = _districtsByCity[city] ?? [];
                    final isLoadingDistricts = _loadingDistricts[city] ?? false;
                    
                    return Card(
                      color: Colors.grey[900],
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CupertinoCheckbox(
                            value: isCitySelected,
                            onChanged: (value) => _onCityToggled(city, value),
                            activeColor: const Color(0xFF0095F6),
                            checkColor: Colors.white,
                          ),
                          title: Text(
                            city,
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () => _onCityToggled(city, !isCitySelected),
                        ),
                        children: [
                          if (isLoadingDistricts)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (districts.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                'Districts not found',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            )
                          else
                            ...districts.map((district) {
                              final isDistrictSelected = 
                                  _selectedDistricts[city]?[district] ?? false;
                              
                              return ListTile(
                                contentPadding: const EdgeInsets.only(left: 48, right: 16),
                                leading: CupertinoCheckbox(
                                  value: isDistrictSelected,
                                  onChanged: isCitySelected
                                      ? (value) => _onDistrictToggled(city, district, value)
                                      : null,
                                  activeColor: const Color(0xFF0095F6),
                                  checkColor: Colors.white,
                                ),
                                title: Text(
                                  district,
                                  style: TextStyle(
                                    color: isCitySelected 
                                        ? Colors.white 
                                        : Colors.grey[600],
                                  ),
                                ),
                                onTap: isCitySelected
                                    ? () => _onDistrictToggled(city, district, !isDistrictSelected)
                                    : null,
                              );
                            }).toList(),
                        ],
                        onExpansionChanged: (expanded) {
                          if (expanded && !_districtsByCity.containsKey(city)) {
                            _loadDistricts(city);
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

