import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../models/user.dart';
import '../widgets/safe_avatar.dart';

class GeoPostsWidget extends StatefulWidget {
  final List<Post>? posts; // Будет использоваться когда появится API

  const GeoPostsWidget({
    super.key,
    this.posts,
  });

  @override
  State<GeoPostsWidget> createState() => _GeoPostsWidgetState();
}

class _GeoPostsWidgetState extends State<GeoPostsWidget>
    with TickerProviderStateMixin {
  late AnimationController _gradientController;

  @override
  void initState() {
    super.initState();
    // Анимация для переливающихся градиентов (более плавная)
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _gradientController.dispose();
    super.dispose();
  }

  // Временные моковые данные для демонстрации
  // В будущем это будет заменено на реальные данные из API
  List<Map<String, dynamic>> get _mockGeoPosts {
    final now = DateTime.now();
    return [
      {
        'id': '1',
        'mediaUrl':
            'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400&h=600&fit=crop',
        'mediaType': 'image',
        'city': 'Москва',
        'distance': '2.5 км',
        'isNew': true,
        'createdAt': now.subtract(const Duration(hours: 1)), // 1 час назад
        'user': {
          'name': 'Анна Иванова',
          'avatarUrl': null,
        },
      },
      {
        'id': '2',
        'mediaUrl':
            'https://images.unsplash.com/photo-1501594907352-04cda38ebc29?w=400&h=600&fit=crop',
        'mediaType': 'image',
        'city': 'Санкт-Петербург',
        'distance': '15 км',
        'isNew': true,
        'createdAt': now.subtract(const Duration(hours: 3)), // 3 часа назад
        'user': {
          'name': 'Дмитрий Петров',
          'avatarUrl': null,
        },
      },
      {
        'id': '3',
        'mediaUrl':
            'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=400&h=600&fit=crop',
        'mediaType': 'image',
        'city': 'Казань',
        'distance': '8.3 км',
        'isNew': false,
        'createdAt': now.subtract(const Duration(days: 1)), // 1 день назад
        'user': {
          'name': 'Мария Смирнова',
          'avatarUrl': null,
        },
      },
      {
        'id': '4',
        'mediaUrl':
            'https://images.unsplash.com/photo-1499781350541-7783f6c6a0c8?w=400&h=600&fit=crop',
        'mediaType': 'image',
        'city': 'Екатеринбург',
        'distance': '22 км',
        'isNew': false,
        'createdAt': now.subtract(const Duration(days: 2)), // 2 дня назад
        'user': {
          'name': 'Алексей Козлов',
          'avatarUrl': null,
        },
      },
      {
        'id': '5',
        'mediaUrl':
            'https://images.unsplash.com/photo-1509641498745-13c26fd1ed89?w=400&h=600&fit=crop',
        'mediaType': 'image',
        'city': 'Новосибирск',
        'distance': '5.1 км',
        'isNew': true,
        'createdAt': now.subtract(const Duration(hours: 6)), // 6 часов назад
        'user': {
          'name': 'Ольга Волкова',
          'avatarUrl': null,
        },
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Используем моковые данные пока нет API
    final geoPosts = _mockGeoPosts;

    if (geoPosts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 320,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок секции
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  EvaIcons.navigation2Outline,
                  size: 20,
                  color: Colors.white.withOpacity(0.9),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Geo Posts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Горизонтальная карусель
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: geoPosts.length,
              itemBuilder: (context, index) {
                final post = geoPosts[index];
                final createdAt = post['createdAt'] as DateTime? ?? DateTime.now();
                return _GeoPostCard(
                  post: post,
                  isNew: post['isNew'] as bool? ?? false,
                  createdAt: createdAt,
                  gradientController: _gradientController,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GeoPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool isNew;
  final DateTime createdAt;
  final AnimationController gradientController;

  const _GeoPostCard({
    required this.post,
    required this.isNew,
    required this.createdAt,
    required this.gradientController,
  });

  // Сокращает имя до формата "Имя Ф."
  String _shortenName(String fullName) {
    final parts = fullName.trim().split(' ');
    if (parts.length < 2) return fullName;
    return '${parts[0]} ${parts[1][0]}.';
  }

  // Форматирует время публикации в формат "22h" или "5m"
  String _formatTimeAgo() {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    final minutes = diff.inMinutes;
    final hours = diff.inHours;
    final days = diff.inDays;

    if (minutes < 60) {
      return '${minutes}m';
    } else if (hours < 24) {
      return '${hours}h';
    } else {
      return '${days}d';
    }
  }

  // Вычисляет интенсивность свечения на основе времени публикации
  // Чем новее пост, тем ярче свечение (1.0 = максимум, 0.3 = минимум для старых)
  double _calculateGlowIntensity() {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    final hoursAgo = diff.inHours;

    // Если пост очень новый (меньше 1 часа) - максимум свечения
    if (hoursAgo < 1) return 1.0;

    // Если пост новый (1-6 часов) - высокая интенсивность
    if (hoursAgo < 6) return 0.85;

    // Если пост относительно новый (6-24 часа) - средняя интенсивность
    if (hoursAgo < 24) return 0.65;

    // Если пост старый (больше 24 часов) - низкая интенсивность
    if (hoursAgo < 48) return 0.45;

    // Очень старый пост - минимальная интенсивность
    return 0.3;
  }

  @override
  Widget build(BuildContext context) {
    final mediaUrl = post['mediaUrl'] as String?;
    final mediaType = post['mediaType'] as String? ?? 'image';
    final city = post['city'] as String? ?? '';
    final distance = post['distance'] as String? ?? '';
    final user = post['user'] as Map<String, dynamic>?;
    final fullName = user?['name'] as String? ?? 'User';
    final shortName = _shortenName(fullName);
    final userAvatarUrl = user?['avatarUrl'] as String?;
    final glowIntensity = _calculateGlowIntensity();

    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Карточка с медиа (более длинная)
          SizedBox(
            height: 235,
            child: _buildAnimatedGlowCard(
              glowIntensity: glowIntensity,
              isNew: isNew,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Медиа контент
                    _buildMediaContent(mediaUrl, mediaType),
                    // Градиентный оверлей снизу
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Аватарка и имя в верхнем левом углу
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _buildUserInfo(shortName, userAvatarUrl),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Город и расстояние под фотографией
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
            child: _buildLocationInfo(city, distance, _formatTimeAgo()),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(String? mediaUrl, String mediaType) {
    if (mediaUrl == null || mediaUrl.isEmpty) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child: Icon(
            EvaIcons.imageOutline,
            color: Colors.grey,
            size: 40,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: mediaUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => Container(
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF9B59B6),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child: Icon(
            EvaIcons.imageOutline,
            color: Colors.grey,
            size: 40,
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedGlowCard({
    required double glowIntensity,
    required bool isNew,
    required Widget child,
  }) {
    if (!isNew) {
      return child;
    }

    return AnimatedBuilder(
      animation: gradientController,
      builder: (context, _) {
        final glowColor = _getGlowColor(gradientController.value);
        
        return Stack(
          children: [
            // Тень снизу под фото
            Positioned(
              bottom: -8,
              left: 0,
              right: 0,
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withOpacity(0.6 * glowIntensity),
                      blurRadius: 12 * glowIntensity,
                      spreadRadius: 2 * glowIntensity,
                    ),
                  ],
                ),
              ),
            ),
            // Контейнер с градиентной рамкой по краям
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  width: 2.5,
                  color: Colors.transparent,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    child,
                    // Градиентная рамка по краям
                    CustomPaint(
                      painter: _GradientBorderPainter(
                        animationValue: gradientController.value,
                        glowIntensity: glowIntensity,
                      ),
                      child: Container(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getGlowColor(double animationValue) {
    final colors = [
      const Color(0xFFFF6B6B),
      const Color(0xFFFF8E53),
      const Color(0xFFFFD93D),
      const Color(0xFF9B59B6),
      const Color(0xFF8E44AD),
      const Color(0xFF6C5CE7),
    ];
    
    // Используем синусоидальную функцию для более плавного перехода
    final angle = animationValue * 2 * math.pi;
    final normalizedValue = (math.sin(angle) + 1) / 2; // Преобразуем sin от -1..1 к 0..1
    final offset = normalizedValue * (colors.length - 1);
    
    final startIndex = offset.floor().clamp(0, colors.length - 1);
    final endIndex = ((offset.floor() + 1) % colors.length).clamp(0, colors.length - 1);
    
    // Используем плавную кривую для интерполяции
    final t = offset - offset.floor();
    final smoothT = _easeInOutCubic(t);
    
    return Color.lerp(colors[startIndex], colors[endIndex], smoothT)!;
  }

  // Функция для плавной кривой easeInOutCubic
  double _easeInOutCubic(double t) {
    if (t < 0.5) {
      return 4 * t * t * t;
    } else {
      return 1 - math.pow(-2 * t + 2, 3) / 2;
    }
  }

  Widget _buildUserInfo(String userName, String? avatarUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SafeAvatar(
                imageUrl: avatarUrl,
                radius: 10,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationInfo(String city, String distance, String timeAgo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Город слева
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    EvaIcons.pinOutline,
                    size: 12,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      city,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Время публикации справа
            Text(
              timeAgo,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          distance,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _GradientBorderPainter extends CustomPainter {
  final double animationValue;
  final double glowIntensity;

  _GradientBorderPainter({
    required this.animationValue,
    this.glowIntensity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Цвета заката и фиолетового с анимацией
    final colors = [
      const Color(0xFFFF6B6B), // Красный заката
      const Color(0xFFFF8E53), // Оранжевый
      const Color(0xFFFFD93D), // Желтый
      const Color(0xFF9B59B6), // Фиолетовый
      const Color(0xFF8E44AD), // Темно-фиолетовый
      const Color(0xFF6C5CE7), // Индиго
      const Color(0xFF5F27CD), // Фиолетово-синий
      const Color(0xFFFF6B6B), // Возврат к красному
    ];

    // Используем синусоидальную функцию для более плавного перехода между цветами
    // Преобразуем animationValue (0-1) в полный цикл (0-2π)
    final angle = animationValue * 2 * math.pi;
    
    // Используем sin для плавного перехода между индексами цветов
    final normalizedValue = (math.sin(angle) + 1) / 2; // Преобразуем sin от -1..1 к 0..1
    final offset = normalizedValue * (colors.length - 1);
    
    final startIndex = offset.floor().clamp(0, colors.length - 1);
    final endIndex = ((offset.floor() + 1) % colors.length).clamp(0, colors.length - 1);
    
    // Используем плавную кривую для интерполяции (easeInOut)
    final t = offset - offset.floor();
    final smoothT = _easeInOutCubic(t);

    final startColor = colors[startIndex];
    final endColor = colors[endIndex];
    var animatedColor = Color.lerp(startColor, endColor, smoothT)!;

    // Применяем интенсивность свечения (делаем тусклее для старых постов)
    animatedColor = Color.fromRGBO(
      (animatedColor.red * glowIntensity).round(),
      (animatedColor.green * glowIntensity).round(),
      (animatedColor.blue * glowIntensity).round(),
      animatedColor.opacity * glowIntensity,
    );

    // Плавная интерполяция для промежуточных цветов
    final nextIndex1 = (startIndex + 1) % colors.length;
    final nextIndex2 = (startIndex + 2) % colors.length;
    
    final nextColor1 = Color.lerp(colors[startIndex], colors[nextIndex1], smoothT)!;
    final nextColor2 = Color.lerp(colors[nextIndex1], colors[nextIndex2], smoothT * 0.7)!;
    
    final color1 = Color.fromRGBO(
      (nextColor1.red * glowIntensity).round(),
      (nextColor1.green * glowIntensity).round(),
      (nextColor1.blue * glowIntensity).round(),
      nextColor1.opacity * glowIntensity,
    );
    
    final color2 = Color.fromRGBO(
      (nextColor2.red * glowIntensity).round(),
      (nextColor2.green * glowIntensity).round(),
      (nextColor2.blue * glowIntensity).round(),
      nextColor2.opacity * glowIntensity,
    );

    // Плавное вращение градиента с использованием синусоидальной функции
    final rotationAngle = angle * 0.5; // Замедляем вращение для плавности

    // Создаем градиент для рамки
    final gradient = SweepGradient(
      center: Alignment.center,
      colors: [
        animatedColor,
        color1,
        color2,
        animatedColor,
      ],
      stops: const [0.0, 0.33, 0.66, 1.0],
      transform: GradientRotation(rotationAngle),
    );

    paint.shader = gradient.createShader(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );

    final rect = Rect.fromLTWH(1.25, 1.25, size.width - 2.5, size.height - 2.5);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14.75));

    canvas.drawRRect(rrect, paint);
  }

  // Функция для плавной кривой easeInOutCubic
  double _easeInOutCubic(double t) {
    if (t < 0.5) {
      return 4 * t * t * t;
    } else {
      return 1 - math.pow(-2 * t + 2, 3) / 2;
    }
  }

  @override
  bool shouldRepaint(_GradientBorderPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.glowIntensity != glowIntensity;
  }
}

