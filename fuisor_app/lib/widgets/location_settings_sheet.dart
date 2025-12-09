import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_notification.dart';

class LocationSettingsSheet extends StatefulWidget {
  const LocationSettingsSheet({Key? key}) : super(key: key);

  @override
  State<LocationSettingsSheet> createState() => _LocationSettingsSheetState();
}

class _LocationSettingsSheetState extends State<LocationSettingsSheet> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  bool _locationSharingEnabled = false;
  String _locationVisibility = 'mutual_followers';
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        throw Exception('No access token');
      }

      _apiService.setAccessToken(accessToken);
      final settings = await _apiService.getLocationVisibility();

      setState(() {
        _locationSharingEnabled = settings['location_sharing_enabled'] ?? false;
        _locationVisibility = settings['location_visibility'] ?? 'mutual_followers';
        _isLoading = false;
      });
    } catch (e) {
      print('LocationSettingsSheet: Error loading settings: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to load settings: $e',
        );
      }
    }
  }

  Future<void> _updateLocationSharing(bool enabled) async {
    if (_isUpdating) return;

    try {
      setState(() {
        _isUpdating = true;
      });

      await _apiService.setLocationSharing(enabled);

      setState(() {
        _locationSharingEnabled = enabled;
        _isUpdating = false;
      });

      if (mounted) {
        AppNotification.showSuccess(
          context,
          enabled ? 'Location sharing enabled' : 'Location sharing disabled',
        );
      }
    } catch (e) {
      print('LocationSettingsSheet: Error updating location sharing: $e');
      setState(() {
        _isUpdating = false;
      });

      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to update: $e',
        );
      }
    }
  }

  Future<void> _updateLocationVisibility(String visibility) async {
    if (_isUpdating || _locationVisibility == visibility) return;

    try {
      setState(() {
        _isUpdating = true;
      });

      await _apiService.updateLocationVisibility(visibility);

      setState(() {
        _locationVisibility = visibility;
        _isUpdating = false;
      });

      if (mounted) {
        AppNotification.showSuccess(
          context,
          'Visibility setting updated',
        );
      }
    } catch (e) {
      print('LocationSettingsSheet: Error updating visibility: $e');
      setState(() {
        _isUpdating = false;
      });

      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to update: $e',
        );
      }
    }
  }

  String _getVisibilityTitle(String visibility) {
    switch (visibility) {
      case 'nobody':
        return 'Nobody';
      case 'mutual_followers':
        return 'Mutual Followers';
      case 'followers':
        return 'Followers';
      case 'close_friends':
        return 'Close Friends';
      default:
        return 'Unknown';
    }
  }

  String _getVisibilityDescription(String visibility) {
    switch (visibility) {
      case 'nobody':
        return 'Nobody can see your location';
      case 'mutual_followers':
        return 'Only people you follow who follow you back';
      case 'followers':
        return 'All your followers can see your location';
      case 'close_friends':
        return 'Only people in your close friends list';
      default:
        return '';
    }
  }

  IconData _getVisibilityIcon(String visibility) {
    switch (visibility) {
      case 'nobody':
        return EvaIcons.eyeOffOutline;
      case 'mutual_followers':
        return EvaIcons.peopleOutline;
      case 'followers':
        return EvaIcons.personAddOutline;
      case 'close_friends':
        return EvaIcons.starOutline;
      default:
        return EvaIcons.settingsOutline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(
                      EvaIcons.settingsOutline,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Location Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        EvaIcons.close,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0095F6),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          // Location Sharing Toggle
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF262626),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  EvaIcons.navigationOutline,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Location Sharing',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _locationSharingEnabled
                                            ? 'Your location is being shared'
                                            : 'Location sharing is disabled',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF8E8E8E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _locationSharingEnabled,
                                  onChanged: _isUpdating
                                      ? null
                                      : (value) => _updateLocationSharing(value),
                                  activeColor: const Color(0xFF0095F6),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Visibility Options
                          if (_locationSharingEnabled) ...[
                            const Text(
                              'Who can see your location',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Nobody
                            _buildVisibilityOption(
                              'nobody',
                              _getVisibilityTitle('nobody'),
                              _getVisibilityDescription('nobody'),
                              _getVisibilityIcon('nobody'),
                            ),

                            const SizedBox(height: 12),

                            // Mutual Followers
                            _buildVisibilityOption(
                              'mutual_followers',
                              _getVisibilityTitle('mutual_followers'),
                              _getVisibilityDescription('mutual_followers'),
                              _getVisibilityIcon('mutual_followers'),
                            ),

                            const SizedBox(height: 12),

                            // Followers
                            _buildVisibilityOption(
                              'followers',
                              _getVisibilityTitle('followers'),
                              _getVisibilityDescription('followers'),
                              _getVisibilityIcon('followers'),
                            ),

                            const SizedBox(height: 12),

                            // Close Friends
                            _buildVisibilityOption(
                              'close_friends',
                              _getVisibilityTitle('close_friends'),
                              _getVisibilityDescription('close_friends'),
                              _getVisibilityIcon('close_friends'),
                            ),

                            const SizedBox(height: 24),
                          ],

                          // Info text
                          if (!_locationSharingEnabled)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF262626),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    EvaIcons.infoOutline,
                                    color: Color(0xFF8E8E8E),
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Enable location sharing to choose who can see your location',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF8E8E8E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisibilityOption(
    String value,
    String title,
    String description,
    IconData icon,
  ) {
    final isSelected = _locationVisibility == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isUpdating
            ? null
            : () => _updateLocationVisibility(value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF0095F6).withOpacity(0.2)
                : const Color(0xFF262626),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0095F6)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF0095F6).withOpacity(0.3)
                      : const Color(0xFF404040),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? const Color(0xFF0095F6)
                      : Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFF0095F6)
                            : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8E8E),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  EvaIcons.checkmarkCircle2,
                  color: Color(0xFF0095F6),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

