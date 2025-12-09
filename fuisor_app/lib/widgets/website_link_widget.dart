import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_notification.dart';

class WebsiteLinkWidget extends StatelessWidget {
  final String? websiteUrl;
  final bool isOwnProfile;
  final VoidCallback? onEdit;

  const WebsiteLinkWidget({
    super.key,
    this.websiteUrl,
    this.isOwnProfile = false,
    this.onEdit,
  });

  IconData _getIconForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return EvaIcons.globe2Outline;

    final host = uri.host.toLowerCase();
    
    // Telegram
    if (host.contains('t.me') || host.contains('telegram')) {
      return EvaIcons.paperPlaneOutline;
    }
    
    // YouTube
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return EvaIcons.playCircleOutline;
    }
    
    // Twitter/X
    if (host.contains('twitter.com') || host.contains('x.com')) {
      return EvaIcons.twitterOutline;
    }
    
    // LinkedIn
    if (host.contains('linkedin.com')) {
      return EvaIcons.linkedinOutline;
    }
    
    // Default globe icon
    return EvaIcons.globe2Outline;
  }

  Future<void> _showWarningDialog(BuildContext context, String url) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF262626),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Заголовок с градиентом
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF0095F6).withOpacity(0.2),
                        const Color(0xFF0095F6).withOpacity(0.05),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Иконка предупреждения
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0095F6).withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0095F6).withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          EvaIcons.alertTriangleOutline,
                          size: 32,
                          color: Color(0xFF0095F6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Внимание!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                // Контент
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Вы собираетесь покинуть приложение',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'И перейти на внешний сайт. Интернет - это дикое место, так что будьте осторожны!',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF8E8E8E),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // URL блок
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262626),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF404040),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              EvaIcons.link2Outline,
                              size: 18,
                              color: const Color(0xFF0095F6).withOpacity(0.8),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                url,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF0095F6),
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Шуточные предупреждения
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262626).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF404040).withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  EvaIcons.infoOutline,
                                  size: 16,
                                  color: const Color(0xFF8E8E8E),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Возможные риски:',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF8E8E8E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildRiskItem('• Потеря продуктивности 😅'),
                            _buildRiskItem('• Непредсказуемый контент 🎲'),
                            _buildRiskItem('• Внезапное желание вернуться 🔙'),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Серьезное предупреждение в конце
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              EvaIcons.shieldOffOutline,
                              size: 16,
                              color: Colors.orange.withOpacity(0.8),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Мы не несем ответственности за содержимое внешних сайтов',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.withOpacity(0.9),
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Кнопки
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF8E8E8E),
                            side: const BorderSide(
                              color: Color(0xFF404040),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Отмена',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0095F6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text(
                                'Продолжить',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                EvaIcons.arrowForwardOutline,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shouldOpen == true) {
      try {
        await _openUrl(url);
      } catch (e) {
        if (context.mounted) {
          AppNotification.showError(
            context,
            'Не удалось открыть ссылку: ${e.toString()}',
          );
        }
      }
    }
  }

  Widget _buildRiskItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF8E8E8E),
          height: 1.4,
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      // Нормализуем URL (добавляем https:// если нужно)
      String normalizedUrl = url.trim();
      if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
        normalizedUrl = 'https://$normalizedUrl';
      }
      
      final uri = Uri.parse(normalizedUrl);
      debugPrint('Attempting to open URL: $normalizedUrl');
      
      // Пробуем открыть URL с разными режимами
      bool launched = false;
      
      // Сначала пробуем externalApplication (внешний браузер)
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          debugPrint('URL opened successfully in external application');
          return;
        }
      } catch (e) {
        debugPrint('Failed to launch in external application: $e');
      }
      
      // Если не получилось, пробуем platformDefault
      if (!launched) {
        try {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
          );
          if (launched) {
            debugPrint('URL opened successfully in platform default mode');
            return;
          }
        } catch (e) {
          debugPrint('Failed to launch in platform default mode: $e');
        }
      }
      
      // Если всё ещё не получилось, пробуем inAppWebView
      if (!launched) {
        try {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.inAppWebView,
          );
          if (launched) {
            debugPrint('URL opened successfully in in-app web view');
            return;
          }
        } catch (e) {
          debugPrint('Failed to launch in in-app web view: $e');
        }
      }
      
      // Если ничего не помогло, показываем ошибку
      if (!launched) {
        throw Exception('Не удалось открыть ссылку. Пожалуйста, проверьте URL и попробуйте снова.');
      }
    } catch (e) {
      debugPrint('Error opening URL: $e');
      // Показываем пользователю ошибку через SnackBar
      // Для этого нужно передать BuildContext, но он недоступен здесь
      // Поэтому просто логируем ошибку
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (websiteUrl == null || websiteUrl!.isEmpty) {
      if (isOwnProfile && onEdit != null) {
        return GestureDetector(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF0095F6),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  EvaIcons.link2Outline,
                  size: 16,
                  color: Color(0xFF0095F6),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Add Link',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF0095F6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF0095F6).withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Кликабельная часть с ссылкой
            Expanded(
              child: GestureDetector(
                onTap: () => _showWarningDialog(context, websiteUrl!),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getIconForUrl(websiteUrl!),
                      size: 16,
                      color: const Color(0xFF0095F6),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        websiteUrl!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF0095F6),
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFF0095F6),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Иконка редактирования (только для своего профиля)
            if (isOwnProfile && onEdit != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (onEdit != null) onEdit!();
                },
                behavior: HitTestBehavior.opaque,
                child: const Icon(
                  EvaIcons.editOutline,
                  size: 14,
                  color: Color(0xFF8E8E8E),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

