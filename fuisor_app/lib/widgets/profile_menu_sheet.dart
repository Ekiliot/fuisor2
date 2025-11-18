import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/safe_avatar.dart';
import '../screens/login_screen.dart';
import '../screens/settings_screen.dart';

class ProfileMenuSheet extends StatelessWidget {
  const ProfileMenuSheet({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final user = authProvider.currentUser;
        
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
              
              const SizedBox(height: 20),
              
              // Profile Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    SafeAvatar(
                      imageUrl: user?.avatarUrl,
                      radius: 30,
                      backgroundColor: const Color(0xFF404040),
                      fallbackIcon: EvaIcons.personOutline,
                      iconColor: Colors.white,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@${user?.username ?? 'unknown'}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF8E8E8E),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      EvaIcons.arrowRightOutline,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Menu Items
              _buildMenuItem(
                icon: EvaIcons.settingsOutline,
                title: 'Settings',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              
              _buildMenuItem(
                icon: EvaIcons.trendingUpOutline,
                title: 'Analytics',
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to analytics screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Analytics coming soon!'),
                      backgroundColor: Color(0xFF0095F6),
                    ),
                  );
                },
              ),
              
              const Divider(
                color: Color(0xFF404040),
                height: 1,
                thickness: 0.5,
              ),
              
              _buildMenuItem(
                icon: EvaIcons.logOutOutline,
                title: 'Log Out',
                textColor: Colors.red,
                onTap: () async {
                  Navigator.pop(context);
                  
                  // Show confirmation dialog
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A1A),
                      title: const Text(
                        'Log Out',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        'Are you sure you want to log out?',
                        style: TextStyle(color: Colors.white),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Color(0xFF8E8E8E)),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Log Out',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  
                  if (shouldLogout == true) {
                    await authProvider.logout();
                    if (context.mounted) {
                      // Clear entire navigation stack and go to login
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  }
                },
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(
                icon,
                color: textColor ?? Colors.white,
                size: 24,
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: textColor ?? Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
