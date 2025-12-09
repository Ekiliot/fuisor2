import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recommendation_provider.dart';
import '../screens/recommendation_settings_screen.dart';
import 'app_notification.dart';

class RecommendationPromptSheet extends StatelessWidget {
  const RecommendationPromptSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final recProvider = Provider.of<RecommendationProvider>(context, listen: false);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Icon
          Icon(
            Icons.explore,
            size: 64,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Improve Recommendations?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            'Get posts, news and events around you. Don\'t miss anything interesting!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Manual setup button
          ElevatedButton(
            onPressed: () async {
              if (!context.mounted) return;
              Navigator.pop(context);
              await recProvider.markPromptShown();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RecommendationSettingsScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Configure Manually',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Auto-detect button
          OutlinedButton(
            onPressed: () async {
              if (!context.mounted) return;
              Navigator.pop(context);
              try {
                await recProvider.autoDetectAndSave();
                if (context.mounted) {
                  AppNotification.showSuccess(context, 'Location detected automatically');
                }
              } catch (e) {
                if (context.mounted) {
                  AppNotification.showError(context, 'Error: ${e.toString()}');
                }
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).primaryColor,
              side: BorderSide(color: Theme.of(context).primaryColor),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Auto Detect',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Later button
          TextButton(
            onPressed: () async {
              await recProvider.markPromptShown();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: Text(
              'Later',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

