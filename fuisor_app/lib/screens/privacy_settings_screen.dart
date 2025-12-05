import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../utils/email_utils.dart';
import '../widgets/animated_app_bar_title.dart';
import '../widgets/app_notification.dart';
import 'change_password_screen.dart';

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
    // Optimistically update UI
    setState(() {
      showActivityStatus = value;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        throw Exception('No access token');
      }

      _apiService.setAccessToken(accessToken);
      await _apiService.updateOnlineStatusSetting(value);

      if (mounted) {
        AppNotification.showSuccess(
          context,
          value ? 'Activity status enabled' : 'Activity status disabled',
        );
      }
    } catch (e) {
      print('Error updating activity status: $e');
      // Revert change on error
      setState(() {
        showActivityStatus = !value;
      });

      if (mounted) {
        AppNotification.showError(context, 'Failed to update setting');
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
          title: const AnimatedAppBarTitle(
            text: 'Privacy',
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
        title: const AnimatedAppBarTitle(
          text: 'Privacy',
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
            subtitle: 'Allow others to see when you are active. If disabled, you will not be able to see the exact activity time of others.',
            value: showActivityStatus,
            onChanged: _updateActivityStatus,
          ),

          const _Divider(),
          const _SectionHeader(title: 'Account Security'),
          _NavTile(
            icon: EvaIcons.lockOutline,
            title: 'Change Password',
            subtitle: 'Update your password using email verification',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChangePasswordScreen(),
                ),
              );
            },
          ),
          Builder(
            builder: (context) {
              final authProvider = context.watch<AuthProvider>();
              final userEmail = authProvider.currentUser?.email ?? '';
              final maskedEmail = EmailUtils.maskEmail(userEmail);
              
              return Container(
                color: const Color(0xFF0F0F0F),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(
                      EvaIcons.emailOutline,
                      color: Color(0xFF8E8E8E),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Email Address',
                            style: TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            maskedEmail,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
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
              AppNotification.showInfo(context, 'Data download feature coming soon!');
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
              AppNotification.showError(context, 'Account deletion feature coming soon!');
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
  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
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
                style: const TextStyle(
                  color: Color(0xFF8E8E8E),
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
