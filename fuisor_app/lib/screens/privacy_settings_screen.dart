import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool privateAccount = false;
  bool showActivityStatus = true;
  bool allowComments = true;
  bool allowMentions = true;
  bool allowTags = true;
  bool allowStoryReplies = true;
  bool hideFromSearchEngines = false;
  
  bool _isLoading = true;
  bool _isSavingActivityStatus = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      _apiService.setAccessToken(accessToken);
      
      setState(() {
        showActivityStatus = true; // По умолчанию
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading settings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateActivityStatus(bool value) async {
    setState(() {
      _isSavingActivityStatus = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        throw Exception('No access token');
      }

      _apiService.setAccessToken(accessToken);
      await _apiService.updateOnlineStatusSetting(value);

      setState(() {
        showActivityStatus = value;
        _isSavingActivityStatus = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value 
                ? 'Статус активности включен' 
                : 'Статус активности отключен',
            ),
            backgroundColor: const Color(0xFF262626),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error updating activity status: $e');
      setState(() {
        _isSavingActivityStatus = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось обновить настройку'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF000000),
        appBar: AppBar(
          backgroundColor: const Color(0xFF000000),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Privacy Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF0095F6),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Privacy Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Account Privacy'),
          _SwitchTile(
            icon: EvaIcons.lockOutline,
            title: 'Private Account',
            subtitle: 'Only people you approve can see your posts and stories',
            value: privateAccount,
            onChanged: (v) => setState(() => privateAccount = v),
          ),
          _SwitchTile(
            icon: EvaIcons.eyeOutline,
            title: 'Show Activity Status',
            subtitle: _isSavingActivityStatus 
              ? 'Сохранение...'
              : 'Позволить другим видеть когда вы активны. Если отключено, вы не сможете видеть точное время активности других.',
            value: showActivityStatus,
            onChanged: _isSavingActivityStatus ? null : _updateActivityStatus,
            isLoading: _isSavingActivityStatus,
          ),

          const _Divider(),
          const _SectionHeader(title: 'Interactions'),
          _SwitchTile(
            icon: EvaIcons.messageCircleOutline,
            title: 'Allow Comments',
            subtitle: 'Let people comment on your posts',
            value: allowComments,
            onChanged: (v) => setState(() => allowComments = v),
          ),
          _SwitchTile(
            icon: EvaIcons.atOutline,
            title: 'Allow Mentions',
            subtitle: 'Let people mention you in posts and comments',
            value: allowMentions,
            onChanged: (v) => setState(() => allowMentions = v),
          ),
          _SwitchTile(
            icon: EvaIcons.hashOutline,
            title: 'Allow Tags',
            subtitle: 'Let people tag you in posts',
            value: allowTags,
            onChanged: (v) => setState(() => allowTags = v),
          ),
          _SwitchTile(
            icon: EvaIcons.messageSquareOutline,
            title: 'Allow Story Replies',
            subtitle: 'Let people reply to your stories',
            value: allowStoryReplies,
            onChanged: (v) => setState(() => allowStoryReplies = v),
          ),

          const _Divider(),
          const _SectionHeader(title: 'Data & Privacy'),
          _SwitchTile(
            icon: EvaIcons.searchOutline,
            title: 'Hide from Search Engines',
            subtitle: 'Prevent search engines from indexing your profile',
            value: hideFromSearchEngines,
            onChanged: (v) => setState(() => hideFromSearchEngines = v),
          ),
          _NavTile(
            icon: EvaIcons.downloadOutline,
            title: 'Download Your Data',
            subtitle: 'Get a copy of your data',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Data download feature coming soon!'),
                  backgroundColor: Color(0xFF0095F6),
                ),
              );
            },
          ),
          _NavTile(
            icon: EvaIcons.trashOutline,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account',
            onTap: () {
              _showDeleteAccountDialog();
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to permanently delete your account? This action cannot be undone.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF8E8E8E)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Account deletion feature coming soon!'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
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
  final ValueChanged<bool>? onChanged;
  final bool isLoading;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.isLoading = false,
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
                style: TextStyle(
                  color: isLoading ? const Color(0xFF0095F6) : const Color(0xFF8E8E8E),
                  fontSize: 12,
                ),
              ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
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
