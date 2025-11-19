import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../providers/posts_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/post_card.dart';
import '../widgets/stories_widget.dart';
import '../widgets/geo_posts_widget.dart';
import '../widgets/skeleton_post_card.dart';
import 'activity_screen.dart';
import 'chats_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  double? _savedScrollPosition; // Сохранение позиции скролла при refresh
  bool _isRefreshing = false; // Отслеживание состояния refresh для отключения blur

  late AnimationController _geoAnimationController1;
  late AnimationController _geoAnimationController2;
  late Animation<double> _geoAnimation1;
  late Animation<double> _geoAnimation2;

  @override
  void initState() {
    super.initState();

    // Инициализация контроллеров анимации для Geo кнопки
    _geoAnimationController1 = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();

    _geoAnimationController2 = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    )..repeat();

    _geoAnimation1 = Tween<double>(
      begin: 0.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _geoAnimationController1,
      curve: Curves.linear,
    ));

    _geoAnimation2 = Tween<double>(
      begin: 0.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _geoAnimationController2,
      curve: Curves.linear,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final accessToken = await _getAccessTokenFromAuthProvider();
      context.read<PostsProvider>().loadFeed(refresh: true, accessToken: accessToken);

      // Load notifications to update unread count
      final authProvider = context.read<AuthProvider>();
      context.read<NotificationsProvider>().loadNotifications(refresh: true, authProvider: authProvider);
    });

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshController.dispose();
    _geoAnimationController1.dispose();
    _geoAnimationController2.dispose();
    super.dispose();
  }

  void _onScroll() async {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final postsProvider = context.read<PostsProvider>();
      // Проверяем, есть ли еще посты для загрузки
      if (postsProvider.hasMorePosts && !postsProvider.isLoading) {
        final accessToken = await _getAccessTokenFromAuthProvider();
        postsProvider.loadFeed(accessToken: accessToken);
      }
    }
  }

  Future<void> _onRefresh() async {
    try {
      // Устанавливаем состояние refresh для отключения blur
      setState(() {
        _isRefreshing = true;
      });
      
      // Сохраняем позицию скролла перед refresh
      if (_scrollController.hasClients) {
        _savedScrollPosition = _scrollController.position.pixels;
      }
      
      final postsProvider = context.read<PostsProvider>();
      final accessToken = await _getAccessTokenFromAuthProvider();
      await postsProvider.loadFeed(refresh: true, accessToken: accessToken);
      
      if (mounted) {
        _refreshController.refreshCompleted();
        
        // Отключаем состояние refresh после небольшой задержки
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _isRefreshing = false;
            });
          }
        });
        
        // Восстанавливаем позицию скролла после обновления UI
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && 
              _scrollController.hasClients && 
              _savedScrollPosition != null &&
              _savedScrollPosition! > 0) {
            // Плавно прокручиваем к сохраненной позиции
            _scrollController.animateTo(
              _savedScrollPosition!,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feed updated!'),
            backgroundColor: Color(0xFF0095F6),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _refreshController.refreshFailed();
        
        // Сбрасываем состояние refresh при ошибке
        setState(() {
          _isRefreshing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update feed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Получить токен из AuthProvider
  Future<String?> _getAccessTokenFromAuthProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token');
    } catch (e) {
      print('Error getting access token: $e');
      return null;
    }
  }

  // Создание анимированной кнопки Geo для header
  Widget _buildGeoHeaderButton() {
    return AnimatedBuilder(
      animation: Listenable.merge([_geoAnimation1, _geoAnimation2]),
      builder: (context, child) {
        // Преобразуем значения анимации в радианы для синусоидальных функций
        final angle1 = _geoAnimation1.value * 2 * math.pi;
        final angle2 = _geoAnimation2.value * 2 * math.pi;

        final primaryOffset = Offset(
          15 * math.sin(angle1),
          8 * math.sin(angle1 + 1.57),
        );

        final secondaryOffset = Offset(
          -12 * math.sin(angle2 + 0.78),
          6 * math.sin(angle2 + 3.14),
        );

        return Container(
          width: 80,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // Анимированная тень
            boxShadow: [
              BoxShadow(
                color: Color(0xFFFF6B35).withOpacity(math.max(0.0, math.min(1.0, 0.4 + 0.3 * math.sin(angle1)))),
                blurRadius: math.max(0.0, 8 + 3 * math.sin(angle1)),
                spreadRadius: math.max(0.0, 1 + 0.8 * math.sin(angle1)),
                offset: Offset(1.5 * math.sin(angle1 + 1.57), 1.5 * math.cos(angle1 + 1.57)),
              ),
              BoxShadow(
                color: Color(0xFF9C27B0).withOpacity(math.max(0.0, math.min(1.0, 0.3 + 0.25 * math.sin(angle2)))),
                blurRadius: math.max(0.0, 6 + 2.5 * math.sin(angle2)),
                spreadRadius: math.max(0.0, 0.5 + 0.4 * math.sin(angle2)),
                offset: Offset(0.8 * math.sin(angle2 + 0.78), 0.8 * math.cos(angle2 + 0.78)),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                // TODO: Navigate to map screen
                print('Geo header button tapped!');
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    // Основной слой градиента с движением
                    Transform.translate(
                      offset: primaryOffset,
                      child: Container(
                        width: 80,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFF6B35), // Оранжевый закат
                              const Color(0xFFF7931E), // Красный закат
                              const Color(0xFFFF4081), // Розовый
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),

                    // Второй слой для более fluid эффекта
                    Transform.translate(
                      offset: secondaryOffset,
                      child: Container(
                        width: 80,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF9C27B0).withOpacity(0.7), // Фиолетовый
                              const Color(0xFFFF4081).withOpacity(0.7), // Розовый
                              const Color(0xFFF7931E).withOpacity(0.7), // Красный
                            ],
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                          ),
                        ),
                      ),
                    ),

                    // Третий статический слой для глубины
                    Container(
                      width: 80,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: RadialGradient(
                          colors: [
                            Colors.transparent,
                            const Color(0xFFFF6B35).withOpacity(0.3),
                            const Color(0xFF9C27B0).withOpacity(0.5),
                          ],
                          stops: const [0.0, 0.6, 1.0],
                          center: Alignment.center,
                        ),
                      ),
                    ),

                    // Blur слой сверху
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                        child: Container(
                          width: 80,
                          height: 36,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),

                    // Текст "Geo" и иконка по центру
                    const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            EvaIcons.pin,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Geo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
      },
    );
  }

  // Вычисляем позиции для гео-постов (через каждые 3-5 обычных постов)
  // Возвращает виртуальные позиции (с учетом того, что Stories занимает индекс 0)
  List<int> _calculateGeoPostsPositions(int totalPosts) {
    if (totalPosts == 0) return [];
    
    final positions = <int>[];
    final intervals = [3, 4, 5, 3, 4, 5]; // Паттерн: через 3, 4, 5, 3, 4, 5 постов
    int postsSinceLastGeo = 0; // Счетчик постов после последнего гео-поста
    int intervalIndex = 0;
    int virtualIndex = 1; // Начинаем с 1, так как index 0 занят Stories
    
    // Проходим по всем постам
    for (int postIndex = 0; postIndex < totalPosts; postIndex++) {
      postsSinceLastGeo++;
      
      // Если прошло нужное количество постов, вставляем гео-пост
      if (postsSinceLastGeo >= intervals[intervalIndex]) {
        // virtualIndex уже указывает на следующую позицию после последнего поста
        positions.add(virtualIndex);
        virtualIndex++; // Гео-пост занимает одну позицию
        postsSinceLastGeo = 0; // Сбрасываем счетчик
        intervalIndex = (intervalIndex + 1) % intervals.length; // Следующий интервал
      }
      
      virtualIndex++; // Обычный пост занимает одну позицию
    }
    
    return positions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Контент заезжает под header
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        toolbarHeight: 60, // Чуть выше стандартного
        flexibleSpace: RepaintBoundary(
          child: ClipRect(
            child: _isRefreshing
                ? Container(
                    // Без blur во время refresh для устранения артефактов
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.1),
                          width: 0.5,
                        ),
                      ),
                    ),
                  )
                : BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4), // Оптимизированный blur
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3), // Более прозрачный
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withOpacity(0.1),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        title: Text(
          'Fuisor',
          style: GoogleFonts.delaGothicOne(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        actions: [
          // Geo button
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildGeoHeaderButton(),
          ),
          // Messages icon
          IconButton(
            icon: const Icon(EvaIcons.paperPlaneOutline, size: 28),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ChatsListScreen(),
                ),
              );
            },
          ),
          Consumer<NotificationsProvider>(
            builder: (context, notificationsProvider, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(EvaIcons.heartOutline, size: 28),
                    onPressed: () async {
                      final authProvider = context.read<AuthProvider>();
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ActivityScreen(),
                        ),
                      );
                      // Refresh notifications count when returning from Activity screen
                      context.read<NotificationsProvider>().loadNotifications(refresh: true, authProvider: authProvider);
                    },
                  ),
                  if (notificationsProvider.unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFED4956),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          notificationsProvider.unreadCount > 99 
                              ? '99+' 
                              : notificationsProvider.unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Selector<PostsProvider, Map<String, dynamic>>(
        selector: (_, provider) => {
          'feedPosts': provider.feedPosts,
          'isInitialLoading': provider.isInitialLoading,
          'isLoading': provider.isLoading,
          'isRefreshing': provider.isRefreshing,
          'error': provider.error,
        },
        shouldRebuild: (prev, next) {
          // Перестраиваем только если изменились важные данные
          return prev['feedPosts'] != next['feedPosts'] ||
                 prev['isInitialLoading'] != next['isInitialLoading'] ||
                 prev['isLoading'] != next['isLoading'] ||
                 prev['isRefreshing'] != next['isRefreshing'] ||
                 prev['error'] != next['error'];
        },
        builder: (context, data, child) {
          final feedPosts = data['feedPosts'] as List;
          final isInitialLoading = data['isInitialLoading'] as bool;
          final isLoading = data['isLoading'] as bool;
          final isRefreshing = data['isRefreshing'] as bool;
          final error = data['error'] as String?;
          
          // Показываем скелетон только при ПЕРВОЙ загрузке И пустом списке
          if (isInitialLoading && feedPosts.isEmpty) {
            return ListView.builder(
              itemCount: 4, // Показываем Stories, GeoPosts и 2 скелетона
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const StoriesWidget();
                }
                if (index == 1) {
                  return const SizedBox.shrink(); // GeoPosts не показываем при загрузке
                }
                return const ShimmerSkeletonPostCard();
              },
            );
          }

          // При ошибке показываем пустой экран с инструкцией pull-to-refresh
          // Только если не идет загрузка и список пустой
          if (error != null && feedPosts.isEmpty && !isLoading && !isRefreshing) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    EvaIcons.refreshOutline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Пустой список (только если не идет загрузка)
          if (feedPosts.isEmpty && !isLoading && !isRefreshing) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    EvaIcons.refreshOutline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No posts yet',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Основной контент - показываем даже если идет загрузка (для плавности)
          final postsProvider = context.read<PostsProvider>();
          
          // Вычисляем позиции для гео-постов (через каждые 3-5 обычных постов)
          final geoPostsPositions = _calculateGeoPostsPositions(feedPosts.length);
          final totalItems = 1 + feedPosts.length + geoPostsPositions.length; // Stories + Posts + GeoPosts
          
          return ClipRect(
            child: SmartRefresher(
              controller: _refreshController,
              onRefresh: _onRefresh,
              enablePullDown: true,
              enablePullUp: false,
              header: const WaterDropHeader(
                waterDropColor: Color(0xFF0095F6),
                complete: Icon(
                  EvaIcons.checkmarkCircle,
                  color: Color(0xFF0095F6),
                  size: 20,
                ),
                failed: Icon(
                  EvaIcons.closeCircle,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              child: ListView.builder(
                controller: _scrollController,
                clipBehavior: Clip.antiAlias, // Плавная обрезка
                physics: const BouncingScrollPhysics(), // Плавный скроллинг с отскоком
                cacheExtent: 1000, // Увеличенная предзагрузка для плавности
                addAutomaticKeepAlives: false, // Оптимизация памяти
                addRepaintBoundaries: false, // Используем ручные RepaintBoundary
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 20, // Pull to refresh виден ниже header
                ),
                itemCount: totalItems,
              itemBuilder: (context, index) {
                // Stories всегда на первой позиции
                if (index == 0) {
                  return RepaintBoundary(
                    child: const StoriesWidget(),
                  );
                }
                
                // Проверяем, является ли эта позиция гео-постом
                final adjustedIndex = index - 1; // Убираем Stories из индекса
                if (geoPostsPositions.contains(adjustedIndex)) {
                  return RepaintBoundary(
                    child: const GeoPostsWidget(),
                  );
                }
                
                // Вычисляем индекс поста с учетом вставленных гео-постов
                final postIndex = adjustedIndex - 
                    geoPostsPositions.where((pos) => pos < adjustedIndex).length;
                
                if (postIndex >= feedPosts.length) {
                  return isLoading && !isRefreshing
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF0095F6),
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                }

                return RepaintBoundary(
                  child: PostCard(
                    post: feedPosts[postIndex],
                    onLike: () => postsProvider.likePost(
                      feedPosts[postIndex].id,
                    ),
                    onComment: (content, parentCommentId) =>
                        postsProvider.addComment(
                      feedPosts[postIndex].id,
                      content,
                      parentCommentId: parentCommentId,
                    ),
                  ),
                );
              },
              ),
            ),
          );
        },
      ),
    );
  }
}
