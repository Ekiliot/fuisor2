import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/animated_app_bar_title.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../widgets/app_notification.dart';
import 'privacy_settings_screen.dart';
import 'storage_settings_screen.dart';
import 'notification_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notificationsEnabled = true;
  bool useCellularData = false;
  bool locationSharingEnabled = false;
  bool _isLoadingLocationSetting = false;
  bool _isLoadingNotificationSetting = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadLocationSharingSetting();
    _loadNotificationSetting();
  }

  Future<void> _loadNotificationSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('notifications_enabled') ?? true;
      setState(() {
        notificationsEnabled = enabled;
      });
    } catch (e) {
      print('SettingsScreen: Error loading notification setting: $e');
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    if (_isLoadingNotificationSetting) return;

    setState(() {
      _isLoadingNotificationSetting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', value);

      final fcmService = FCMService();

      if (value) {
        // Включаем уведомления
        if (!fcmService.isInitialized) {
          await fcmService.initialize();
        }

        // Отправляем токен на сервер
        final accessToken = prefs.getString('access_token');
        if (accessToken != null && fcmService.fcmToken != null) {
          await fcmService.sendTokenToServer(accessToken);
        }
      } else {
        // Отключаем уведомления - удаляем токен с сервера
        final accessToken = prefs.getString('access_token');
        if (accessToken != null) {
          try {
            await fcmService.deleteToken();
            
            // Также удаляем токен с сервера
            _apiService.setAccessToken(accessToken);
            await _apiService.sendFCMToken(''); // Отправляем пустую строку для удаления
          } catch (e) {
            print('SettingsScreen: Error deleting FCM token: $e');
          }
        }
      }

      setState(() {
        notificationsEnabled = value;
        _isLoadingNotificationSetting = false;
      });

      if (mounted) {
        AppNotification.showSuccess(
          context,
          value ? 'Notifications enabled' : 'Notifications disabled',
        );
      }
    } catch (e) {
      print('SettingsScreen: Error toggling notifications: $e');
      setState(() {
        notificationsEnabled = !value; // Откатываем изменение
        _isLoadingNotificationSetting = false;
      });

      if (mounted) {
        AppNotification.showError(context, 'Error: ${e.toString()}');
      }
    }
  }

  Future<void> _loadLocationSharingSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      
      // TODO: Загрузить текущее значение location_sharing_enabled из API
      // Пока используем значение по умолчанию false
      // В будущем можно добавить endpoint для получения настроек пользователя
    } catch (e) {
      print('SettingsScreen: Error loading location sharing setting: $e');
    }
  }

  Future<void> _toggleLocationSharing(bool value) async {
    if (_isLoadingLocationSetting) return;

    setState(() {
      _isLoadingLocationSetting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        setState(() {
          locationSharingEnabled = false;
          _isLoadingLocationSetting = false;
        });
        return;
      }

      _apiService.setAccessToken(accessToken);
      await _apiService.setLocationSharing(value);

      setState(() {
        locationSharingEnabled = value;
        _isLoadingLocationSetting = false;
      });

      if (mounted) {
        AppNotification.showSuccess(
          context,
              value 
                ? 'Location sharing enabled. Friends can see your location.'
                : 'Location sharing disabled.',
        );
      }
    } catch (e) {
      print('SettingsScreen: Error toggling location sharing: $e');
      setState(() {
        locationSharingEnabled = !value; // Откатываем изменение
        _isLoadingLocationSetting = false;
      });

      if (mounted) {
        AppNotification.showError(context, 'Error: ${e.toString()}');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(String title, String subtitle) {
    if (_searchQuery.isEmpty) return true;
    final query = _searchQuery.toLowerCase();
    return title.toLowerCase().contains(query) || 
           subtitle.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final hasSearchQuery = _searchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const AnimatedAppBarTitle(
          text: 'Settings',
        ),
        centerTitle: true,
      ),
      body: _buildSettingsList(hasSearchQuery),
    );
  }

  Widget _buildSettingsList(bool hasSearchQuery) {
    final widgets = <Widget>[];

    // Search bar (в начале списка, как в списке чатов)
    widgets.add(_buildSearchBar());

    // General section
    final generalSettings = [
      _SettingItem(
        section: 'General',
        icon: EvaIcons.bellOutline,
        title: 'Notifications',
        subtitle: 'Enable or disable all notifications',
        type: _SettingType.switch_,
        switchValue: notificationsEnabled,
        isLoading: _isLoadingNotificationSetting,
        onSwitchChanged: _toggleNotifications,
      ),
      _SettingItem(
        section: 'General',
        icon: EvaIcons.settingsOutline,
        title: 'Notification Settings',
        subtitle: 'Customize notification preferences',
        type: _SettingType.navigation,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const NotificationSettingsScreen(),
            ),
          );
        },
      ),
      _SettingItem(
        section: 'General',
        icon: EvaIcons.wifiOff,
        title: 'Use cellular data',
        subtitle: 'Allow media loading on mobile data',
        type: _SettingType.switch_,
        switchValue: useCellularData,
        onSwitchChanged: (v) => setState(() => useCellularData = v),
      ),
    ];

    // Storage section
    final storageSettings = [
      _SettingItem(
        section: 'Storage',
        icon: EvaIcons.hardDriveOutline,
        title: 'Storage Settings',
        subtitle: 'Manage cache and storage data',
        type: _SettingType.navigation,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const StorageSettingsScreen(),
            ),
          );
        },
      ),
    ];

    // Privacy section
    final privacySettings = [
      _SettingItem(
        section: 'Privacy',
        icon: EvaIcons.lockOutline,
        title: 'Blocked accounts',
        subtitle: 'Manage the users you have blocked',
        type: _SettingType.navigation,
        onTap: () {},
      ),
      _SettingItem(
        section: 'Privacy',
        icon: EvaIcons.shieldOutline,
        title: 'Privacy Settings',
        subtitle: 'Control who can see your content and interact with you',
        type: _SettingType.navigation,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const PrivacySettingsScreen(),
            ),
          );
        },
      ),
      _SettingItem(
        section: 'Privacy',
        icon: EvaIcons.navigation2Outline,
        title: 'Location sharing',
        subtitle: 'Share your location with friends on the map',
        type: _SettingType.switch_,
        switchValue: locationSharingEnabled,
        onSwitchChanged: _toggleLocationSharing,
      ),
    ];

    // About section
    final aboutSettings = [
      _SettingItem(
        section: 'About',
        icon: EvaIcons.infoOutline,
        title: 'About SONET',
        subtitle: 'Version, licenses and legal',
        type: _SettingType.navigation,
        onTap: () {},
      ),
    ];

    // Filter settings based on search query
    final allSettings = [
      ...generalSettings,
      ...storageSettings,
      ...privacySettings,
      ...aboutSettings,
    ];

    final filteredSettings = hasSearchQuery
        ? allSettings.where((setting) => 
            _matchesSearch(setting.title, setting.subtitle)).toList()
        : allSettings;

    if (hasSearchQuery && filteredSettings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                EvaIcons.searchOutline,
                size: 64,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                'No settings found',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try searching for something else',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group settings by section if not searching
    if (!hasSearchQuery) {
      String? currentSection;
      for (final setting in filteredSettings) {
        if (currentSection != setting.section) {
          if (currentSection != null) {
            widgets.add(const _Divider());
          }
          currentSection = setting.section;
          widgets.add(_SectionHeader(title: setting.section));
        }
        widgets.add(_buildSettingWidget(setting));
      }
    } else {
      // Show all filtered settings without section headers
      for (final setting in filteredSettings) {
        widgets.add(_buildSettingWidget(setting));
      }
    }

    return ListView(children: widgets);
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
        decoration: InputDecoration(
          hintText: 'Search settings...',
          hintStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: const Icon(
            EvaIcons.searchOutline,
            color: Color(0xFF8E8E8E),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    EvaIcons.closeCircle,
                    color: Color(0xFF8E8E8E),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF262626),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSettingWidget(_SettingItem item) {
    switch (item.type) {
      case _SettingType.switch_:
        return _SwitchTile(
          icon: item.icon,
          title: item.title,
          subtitle: item.subtitle,
          value: item.switchValue ?? false,
          isLoading: item.isLoading ?? false,
          onChanged: item.onSwitchChanged ?? (v) {},
        );
      case _SettingType.navigation:
        return _NavTile(
          icon: item.icon,
          title: item.title,
          subtitle: item.subtitle,
          onTap: item.onTap ?? () {},
        );
    }
  }
}

enum _SettingType {
  switch_,
  navigation,
}

class _SettingItem {
  final String section;
  final IconData icon;
  final String title;
  final String subtitle;
  final _SettingType type;
  final bool? switchValue;
  final bool? isLoading;
  final ValueChanged<bool>? onSwitchChanged;
  final VoidCallback? onTap;

  _SettingItem({
    required this.section,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.type,
    this.switchValue,
    this.isLoading,
    this.onSwitchChanged,
    this.onTap,
  });
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.5,
      color: Color(0xFF262626),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final bool isLoading;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.isLoading = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F0F),
      child: ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 12),
              ),
        trailing: CupertinoSwitch(
          value: value,
          onChanged: isLoading ? null : onChanged,
          activeColor: const Color(0xFF0095F6),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F0F),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 12),
              ),
        trailing: const Icon(EvaIcons.arrowRightOutline, color: Colors.white, size: 18),
      ),
    );
  }
}
