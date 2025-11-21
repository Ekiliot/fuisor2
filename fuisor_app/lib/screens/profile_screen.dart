import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../providers/posts_provider.dart';
import '../services/api_service.dart';
import 'dart:ui';
import '../widgets/post_grid_widget.dart';
import '../widgets/profile_menu_sheet.dart';
import '../widgets/profile_skeleton.dart';
import '../widgets/animated_app_bar_title.dart';
import '../widgets/website_link_widget.dart';
import '../widgets/add_website_dialog.dart';
import '../models/user.dart';
import 'edit_profile_screen.dart';
import 'followers_list_screen.dart';
import 'saved_posts_screen.dart';
import 'liked_posts_screen.dart';
import 'chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  final ScrollController _scrollController = ScrollController();
  User? _viewingUser;
  bool _isLoadingUser = false;
  bool _isLoadingUserData = false; // Защита от параллельных запросов
  bool _isFollowing = false;
  bool _isCheckingFollowStatus = false;
  late TabController _tabController;
  double? _savedScrollPosition; // Сохранение позиции скролла при refresh
  String? _previousUserId; // Для отслеживания изменения userId
  bool _isSwitchingProfile = false; // Флаг переключения между профилями

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _previousUserId = widget.userId; // Сохраняем начальный userId
    // Загружаем посты пользователя при инициализации
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ждем инициализации AuthProvider
      await _waitForAuthProvider();
      
      final authProvider = context.read<AuthProvider>();
      final postsProvider = context.read<PostsProvider>();
      
      print('ProfileScreen: Initializing...');
      print('ProfileScreen: Viewing profile for userId: ${widget.userId ?? 'current user'}');
      print('ProfileScreen: Current user: ${authProvider.currentUser?.id}');
      print('ProfileScreen: Current user name: ${authProvider.currentUser?.name}');
      print('ProfileScreen: Current user username: ${authProvider.currentUser?.username}');
      
      // Determine which user's posts to load
      // Обрабатываем случай, когда widget.userId может быть пустой строкой
      final providedUserId = (widget.userId != null && widget.userId!.isNotEmpty) 
          ? widget.userId 
          : null;
      final targetUserId = providedUserId ?? authProvider.currentUser?.id;
      
      if (targetUserId != null && targetUserId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        
        print('ProfileScreen: Loading posts for user: $targetUserId');
        
        // Загружаем пользователя и посты параллельно
        final futures = <Future>[];
        
        // Load the user's profile if viewing another user
        if (providedUserId != null && providedUserId != authProvider.currentUser?.id) {
          if (!_isLoadingUserData) {
            _isLoadingUserData = true;
            setState(() {
              _isLoadingUser = true;
            });
            
            futures.add(_loadUserData(providedUserId));
          }
        }
        
        // Загружаем посты параллельно с данными пользователя
        futures.add(postsProvider.loadUserPosts(
          userId: targetUserId,
          refresh: true,
          accessToken: accessToken,
        ));
        
        // Ждем завершения всех загрузок
        await Future.wait(futures);
      } else {
        print('ProfileScreen: No current user found or user ID is empty');
        // Попробуем загрузить профиль
        try {
          print('ProfileScreen: Attempting to refresh profile...');
          await authProvider.refreshProfile();
          
          // Проверяем еще раз после refreshProfile
          if (authProvider.currentUser != null && authProvider.currentUser!.id.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            final accessToken = prefs.getString('access_token');
            
            print('ProfileScreen: Retrying to load posts for user: ${authProvider.currentUser!.id}');
            
            await postsProvider.loadUserPosts(
              userId: authProvider.currentUser!.id,
              refresh: true,
              accessToken: accessToken,
            );
          } else {
            print('ProfileScreen: Still no user after refreshProfile');
            // Попробуем загрузить из SharedPreferences напрямую
            final prefs = await SharedPreferences.getInstance();
            final userDataString = prefs.getString('userData');
            if (userDataString != null) {
              print('ProfileScreen: Found user data in SharedPreferences, parsing...');
              final userData = jsonDecode(userDataString);
              final user = User.fromJson(userData);
              print('ProfileScreen: Parsed user ID: ${user.id}');
              
              // Устанавливаем пользователя в AuthProvider
              authProvider.setCurrentUser(user);
              
              final accessToken = prefs.getString('access_token');
              await postsProvider.loadUserPosts(
                userId: user.id,
                refresh: true,
                accessToken: accessToken,
              );
            }
          }
        } catch (e) {
          print('ProfileScreen: Failed to refresh profile: $e');
        }
      }
    });
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если userId изменился, показываем скелетон и перезагружаем данные
    if (oldWidget.userId != widget.userId) {
      _handleUserIdChange();
    }
  }

  void _handleUserIdChange() async {
    // Показываем скелетон при переключении профилей
    setState(() {
      _isSwitchingProfile = true;
      _viewingUser = null; // Очищаем данные предыдущего пользователя
      _previousUserId = widget.userId;
    });

    // Ждем небольшую задержку для плавной анимации
    await Future.delayed(const Duration(milliseconds: 100));

    // Загружаем данные нового профиля
    await _waitForAuthProvider();
    
    final authProvider = context.read<AuthProvider>();
    final postsProvider = context.read<PostsProvider>();
    
    final providedUserId = (widget.userId != null && widget.userId!.isNotEmpty) 
        ? widget.userId 
        : null;
    final targetUserId = providedUserId ?? authProvider.currentUser?.id;
    
    if (targetUserId != null && targetUserId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      final futures = <Future>[];
      
      // Load the user's profile if viewing another user
      if (providedUserId != null && providedUserId != authProvider.currentUser?.id) {
        if (!_isLoadingUserData) {
          _isLoadingUserData = true;
          setState(() {
            _isLoadingUser = true;
          });
          
          futures.add(_loadUserData(providedUserId));
        }
      }
      
      // Загружаем посты параллельно с данными пользователя
      futures.add(postsProvider.loadUserPosts(
        userId: targetUserId,
        refresh: true,
        accessToken: accessToken,
      ));
      
      // Ждем завершения всех загрузок
      await Future.wait(futures);
    }
    
    if (mounted) {
      setState(() {
        _isSwitchingProfile = false;
      });
    }
  }

  // Загрузить данные пользователя
  Future<void> _loadUserData(String userId) async {
    try {
      final apiService = ApiService();
      final user = await apiService.getUser(userId);
      
      if (mounted) {
        setState(() {
          _viewingUser = user;
          _isLoadingUser = false;
        });
        
        // Check if current user is following this user
        await _checkFollowStatus(userId);
      }
    } catch (e) {
      print('ProfileScreen: Error loading user: $e');
      if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    } finally {
      _isLoadingUserData = false;
    }
  }

  // Загрузить данные пользователя с обработкой ошибок и восстановлением старых данных
  Future<void> _loadUserDataWithErrorHandling(String userId, User? oldUser) async {
    try {
      final apiService = ApiService();
      final user = await apiService.getUser(userId);
      
      if (mounted) {
        setState(() {
          _viewingUser = user; // Заменяем только после успешной загрузки
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      print('ProfileScreen: Error refreshing user: $e');
      // При ошибке восстанавливаем старые данные
      if (mounted) {
        setState(() {
          if (oldUser != null) {
            _viewingUser = oldUser; // Восстанавливаем старые данные
            print('ProfileScreen: User refresh failed, restored old user data');
          }
          _isLoadingUser = false;
        });
      }
    } finally {
      _isLoadingUserData = false;
    }
  }

  // Ждать инициализации AuthProvider
  Future<void> _waitForAuthProvider() async {
    int attempts = 0;
    const maxAttempts = 10;
    
    while (attempts < maxAttempts) {
      final authProvider = context.read<AuthProvider>();
      
      if (authProvider.currentUser != null && authProvider.currentUser!.id.isNotEmpty) {
        print('ProfileScreen: AuthProvider initialized after ${attempts + 1} attempts');
        return;
      }
      
      print('ProfileScreen: Waiting for AuthProvider... attempt ${attempts + 1}');
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }
    
    print('ProfileScreen: AuthProvider not initialized after $maxAttempts attempts');
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    try {
      // Сохраняем позицию скролла перед refresh
      if (_scrollController.hasClients) {
        _savedScrollPosition = _scrollController.position.pixels;
      }
      
      final authProvider = context.read<AuthProvider>();
      final postsProvider = context.read<PostsProvider>();
      
      // Determine which user's profile to refresh
      final targetUserId = widget.userId ?? authProvider.currentUser?.id;
      
      if (targetUserId == null) {
        print('ProfileScreen: Cannot refresh posts - no valid user ID');
        return;
      }
      
      // Сохраняем старые данные для восстановления при ошибке
      User? oldUser;
      if (widget.userId != null && widget.userId != authProvider.currentUser?.id) {
        oldUser = _viewingUser; // Сохраняем старые данные
      }
      
      // Загружаем пользователя и посты параллельно
      final futures = <Future>[];
      
      // Reload user data if viewing another user's profile
      if (widget.userId != null && widget.userId != authProvider.currentUser?.id) {
        if (!_isLoadingUserData) {
          _isLoadingUserData = true;
          setState(() {
            _isLoadingUser = true;
          });
          
          futures.add(_loadUserDataWithErrorHandling(widget.userId!, oldUser));
        }
      } else {
        // Refresh current user's profile
        futures.add(authProvider.refreshProfile());
      }
      
      // Загружаем посты пользователя параллельно
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      print('ProfileScreen: Refreshing posts for user: $targetUserId');
      
      futures.add(postsProvider.loadUserPosts(
        userId: targetUserId,
        refresh: true,
        accessToken: accessToken,
      ));
      
      // Ждем завершения всех загрузок
      await Future.wait(futures);
      
      if (mounted) {
        _refreshController.refreshCompleted();
        
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
        
        // Показываем уведомление об успешном обновлении
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated!'),
            backgroundColor: Color(0xFF0095F6),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _refreshController.refreshFailed();
        
        // Показываем уведомление об ошибке
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _checkFollowStatus(String userId) async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser == null) return;
    
    setState(() {
      _isCheckingFollowStatus = true;
    });
    
    try {
      // Get access token
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        throw Exception('No access token');
      }
      
      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      final isFollowing = await apiService.checkFollowStatus(userId);
      setState(() {
        _isFollowing = isFollowing;
        _isCheckingFollowStatus = false;
      });
    } catch (e) {
      print('ProfileScreen: Error checking follow status: $e');
      setState(() {
        _isCheckingFollowStatus = false;
      });
    }
  }

  Future<void> _startChat(String userId) async {
    try {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to send messages'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (userId == authProvider.currentUser!.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot start chat with yourself'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get access token
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        throw Exception('No access token');
      }

      final apiService = ApiService();
      apiService.setAccessToken(accessToken);

      // Создаем или получаем существующий чат
      final chat = await apiService.createChat(userId);

      if (mounted) {
        // Открываем экран чата
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(chat: chat),
          ),
        );
      }
    } catch (e) {
      print('ProfileScreen: Error starting chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start chat: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleFollow(String userId) async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser == null) return;
    
    try {
      // Get access token
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) {
        throw Exception('No access token');
      }
      
      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      
      if (_isFollowing) {
        await apiService.unfollowUser(userId);
        setState(() {
          _isFollowing = false;
        });
      } else {
        await apiService.followUser(userId);
        setState(() {
          _isFollowing = true;
        });
      }
      
      // Refresh user data to update followers count
      if (mounted && _viewingUser != null) {
        final user = await apiService.getUser(userId);
        setState(() {
          _viewingUser = user;
        });
      }
    } catch (e) {
      print('ProfileScreen: Error toggling follow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${_isFollowing ? 'unfollow' : 'follow'}: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: RepaintBoundary(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
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
        leading: widget.userId != null
            ? IconButton(
                icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Builder(
          builder: (context) {
            final currentUser = context.watch<AuthProvider>().currentUser;
            // Определяем, открыт ли чужой профиль
            final isViewingOtherUser = widget.userId != null && 
                                       widget.userId != currentUser?.id;
            
            // Если идет переключение профилей, показываем скелетон в заголовке
            if (_isSwitchingProfile) {
              return const AnimatedAppBarTitle(
                text: 'Loading...',
              );
            }
            
            // Для чужого профиля показываем только _viewingUser
            if (isViewingOtherUser) {
              if (_viewingUser != null) {
                final displayText = _viewingUser!.name.isNotEmpty
                    ? '@${_viewingUser!.username} • ${_viewingUser!.name}'
                    : '@${_viewingUser!.username}';
                return AnimatedAppBarTitle(
                  text: displayText,
                );
              } else {
                // Показываем скелетон, если данные еще не загружены
                return const AnimatedAppBarTitle(
                  text: 'Loading...',
                );
              }
            }
            
            // Для своего профиля показываем currentUser
            if (currentUser != null) {
              final displayText = currentUser.name.isNotEmpty
                  ? '@${currentUser.username} • ${currentUser.name}'
                  : '@${currentUser.username}';
              return AnimatedAppBarTitle(
                text: displayText,
              );
            }
            
            return const AnimatedAppBarTitle(
              text: 'Profile',
            );
          },
        ),
        actions: [
          // Only show menu button for current user's own profile
          if (widget.userId == null)
            IconButton(
              icon: const Icon(EvaIcons.menu, color: Colors.white),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (context) => const ProfileMenuSheet(),
                );
              },
            ),
        ],
      ),
      body: Selector<AuthProvider, User?>(
        selector: (_, provider) => provider.currentUser,
        builder: (context, currentUser, child) {
          // Определяем, открыт ли чужой профиль
          final isViewingOtherUser = widget.userId != null && 
                                     widget.userId != currentUser?.id;
          
          // Показываем ошибку только если нет ни текущего пользователя, ни просматриваемого
          if (currentUser == null && _viewingUser == null && !_isLoadingUser) {
            return const Center(
              child: Text(
                'Please log in',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          // Если открыт чужой профиль, НЕ показываем данные текущего пользователя
          // Показываем только данные чужого пользователя или скелетон
          User? user;
          bool shouldShowSkeleton = false;
          
          // Если идет переключение между профилями, всегда показываем скелетон
          if (_isSwitchingProfile) {
            shouldShowSkeleton = true;
          } else if (isViewingOtherUser) {
            // Для чужого профиля показываем только _viewingUser, не currentUser
            user = _viewingUser;
            
            // Если данные еще не загружены, показываем скелетон
            if (user == null) {
              shouldShowSkeleton = true;
            }
          } else {
            // Для своего профиля показываем currentUser
            user = currentUser;
            
            if (user == null) {
              return const Center(
                child: Text(
                  'Please log in',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }
          }

          // Показываем скелетон с анимацией
          if (shouldShowSkeleton) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: const ProfileSkeleton(key: ValueKey('skeleton')),
            );
          }

          // Проверяем, что user не null перед использованием
            if (user == null) {
              return const Center(
                child: Text(
                'User not found',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.05),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  )),
                  child: child,
                ),
              );
            },
            child: SmartRefresher(
              key: ValueKey('profile_${user.id}'), // Ключ для перезапуска анимации при смене пользователя
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
            child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                // Profile Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Square Avatar (80x80) on the left
                      Container(
                        width: 80,
                        height: 80,
                                    decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF262626),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: user.avatarUrl!,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    width: 80,
                                    height: 80,
                                    color: const Color(0xFF262626),
                                    child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        color: Color(0xFF0095F6),
                                        ),
                                      ),
                                    ),
                                  errorWidget: (context, url, error) => const Icon(
                                    EvaIcons.personOutline,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                )
                              : const Icon(
                                  EvaIcons.personOutline,
                                    color: Colors.white,
                                  size: 40,
                                  ),
                                ),
                      ),
                      const SizedBox(width: 16),
                      // Stats card on the right, same height as avatar, centered vertically
                      Expanded(
                        child: Container(
                          height: 80, // Same height as avatar
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF262626),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 1,
                                  ),
                              ],
                            ),
                          child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                            crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                              _buildAnimatedStatColumn('Posts', user.postsCount),
                              _buildAnimatedStatColumn(
                            'Followers',
                            user.followersCount,
                            onTap: () {
                                  final userId = user!.id;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => FollowersListScreen(
                                    userId: userId,
                                    title: 'Followers',
                                    isFollowers: true,
                                  ),
                                ),
                              );
                            },
                          ),
                              _buildAnimatedStatColumn(
                            'Following',
                            user.followingCount,
                            onTap: () {
                                  final userId = user!.id;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => FollowersListScreen(
                                    userId: userId,
                                    title: 'Following',
                                    isFollowers: false,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bio Section (if exists) - в карточке как статистика
                if (user.bio != null && user.bio!.isNotEmpty || 
                    user.websiteUrl != null && user.websiteUrl!.isNotEmpty ||
                    (widget.userId == null || widget.userId == context.read<AuthProvider>().currentUser?.id))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF262626),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (user.bio != null && user.bio!.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                user.bio!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.left,
                              ),
                            ),
                          if (user.bio != null && user.bio!.isNotEmpty && 
                              (user.websiteUrl != null && user.websiteUrl!.isNotEmpty ||
                               widget.userId == null || widget.userId == context.read<AuthProvider>().currentUser?.id))
                            const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final authProvider = context.read<AuthProvider>();
                              final isOwnProfile = widget.userId == null || widget.userId == authProvider.currentUser?.id;
                              return WebsiteLinkWidget(
                                websiteUrl: user.websiteUrl,
                                isOwnProfile: isOwnProfile,
                                onEdit: isOwnProfile ? () async {
                                  final result = await showDialog<String>(
                                    context: context,
                                    builder: (context) => AddWebsiteDialog(
                                      initialUrl: user.websiteUrl,
                                    ),
                                  );
                                  
                                  if (result != null && mounted) {
                                    final authProvider = context.read<AuthProvider>();
                                    final success = await authProvider.updateProfile(
                                      websiteUrl: result.isEmpty ? null : result,
                                    );
                                    
                                    if (success && mounted) {
                                      await authProvider.refreshProfile();
                                    }
                                  }
                                } : null,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // Edit Profile Button (only for current user)
                if (widget.userId == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const EditProfileScreen(),
                            ),
                          );
                          if (result == true && mounted) {
                            // Refresh profile data after editing
                            final authProvider = context.read<AuthProvider>();
                            await authProvider.refreshProfile();
                            // Also refresh user posts
                            final postsProvider = context.read<PostsProvider>();
                            final prefs = await SharedPreferences.getInstance();
                            final accessToken = prefs.getString('access_token');
                            final userId = user!.id; // user гарантированно не null здесь
                            if (userId.isNotEmpty) {
                              await postsProvider.loadUserPosts(
                                userId: userId,
                                refresh: true,
                                accessToken: accessToken,
                              );
                            }
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0095F6),
                          side: const BorderSide(color: Color(0xFF262626)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Message and Follow/Unfollow Buttons (only for other users' profiles)
                Builder(
                  builder: (context) {
                    final authProvider = context.read<AuthProvider>();
                    if (widget.userId != null && widget.userId != authProvider.currentUser?.id) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            // Message button
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _startChat(widget.userId!),
                                icon: const Icon(
                                  EvaIcons.paperPlaneOutline,
                                  size: 18,
                                  color: Color(0xFF0095F6),
                                ),
                                label: const Text(
                                  'Message',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Color(0xFF0095F6),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF262626)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Follow/Unfollow button
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isCheckingFollowStatus
                                    ? null
                                    : () => _toggleFollow(widget.userId!),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFollowing
                                      ? const Color(0xFF262626)
                                      : const Color(0xFF0095F6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: _isCheckingFollowStatus
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Text(
                                        _isFollowing ? 'Unfollow' : 'Follow',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                const SizedBox(height: 20),

                // Tabs (only for own profile) - стиль как в камере (person/people)
                Builder(
                  builder: (context) {
                    final authProvider = context.read<AuthProvider>();
                    if (widget.userId == null || widget.userId == authProvider.currentUser?.id) {
                      return Column(
                        children: [
                          AnimatedBuilder(
                            animation: _tabController,
                            builder: (context, child) {
                              return Center(
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Posts Tab (person style)
                                      GestureDetector(
                                        onTap: () {
                                          if (_tabController.index != 0) {
                                            _tabController.animateTo(0);
                                          }
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _tabController.index == 0
                                                ? Colors.white.withOpacity(0.2)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(25),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                EvaIcons.gridOutline,
                                                color: _tabController.index == 0
                                                    ? Colors.white
                                                    : Colors.white.withOpacity(0.6),
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Saved Posts Tab (people style)
                                      GestureDetector(
                                        onTap: () {
                                          if (_tabController.index != 1) {
                                            _tabController.animateTo(1);
                                          }
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _tabController.index == 1
                                                ? Colors.white.withOpacity(0.2)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(25),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                EvaIcons.bookmarkOutline,
                                                color: _tabController.index == 1
                                                    ? Colors.white
                                                    : Colors.white.withOpacity(0.6),
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Liked Posts Tab
                                      GestureDetector(
                                        onTap: () {
                                          if (_tabController.index != 2) {
                                            _tabController.animateTo(2);
                                          }
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _tabController.index == 2
                                                ? Colors.white.withOpacity(0.2)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(25),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                EvaIcons.heartOutline,
                                                color: _tabController.index == 2
                                                    ? Colors.white
                                                    : Colors.white.withOpacity(0.6),
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Tab View and Posts Grid
                Builder(
                  builder: (context) {
                    final authProvider = context.read<AuthProvider>();
                    // Own profile - show tabs
                    if (widget.userId == null || widget.userId == authProvider.currentUser?.id) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Posts Tab
                            Selector<PostsProvider, Map<String, dynamic>>(
                              selector: (_, provider) => {
                                'userPosts': provider.userPosts,
                                'isLoading': provider.isLoading,
                                'isRefreshingUserPosts': provider.isRefreshingUserPosts,
                                'hasMoreUserPosts': provider.hasMoreUserPosts,
                              },
                              shouldRebuild: (prev, next) {
                                return prev['userPosts'] != next['userPosts'] ||
                                       prev['isLoading'] != next['isLoading'] ||
                                       prev['isRefreshingUserPosts'] != next['isRefreshingUserPosts'] ||
                                       prev['hasMoreUserPosts'] != next['hasMoreUserPosts'];
                              },
                              builder: (context, data, child) {
                                final userPosts = (data['userPosts'] as List).cast<Post>();
                                final isLoading = data['isLoading'] as bool;
                                final isRefreshingUserPosts = data['isRefreshingUserPosts'] as bool;
                                final hasMoreUserPosts = data['hasMoreUserPosts'] as bool;
                                
                                final postsProvider = context.read<PostsProvider>();
                                return PostGridWidget(
                                  posts: userPosts,
                                  isLoading: isLoading && !isRefreshingUserPosts,
                                  hasMorePosts: hasMoreUserPosts,
                                  onLoadMore: () async {
                                    await _waitForAuthProvider();
                                    
                                    final authProvider = context.read<AuthProvider>();
                                    if (authProvider.currentUser != null && authProvider.currentUser!.id.isNotEmpty) {
                                      final prefs = await SharedPreferences.getInstance();
                                      final accessToken = prefs.getString('access_token');
                                      
                                      await postsProvider.loadUserPosts(
                                        userId: authProvider.currentUser!.id,
                                        refresh: false,
                                        accessToken: accessToken,
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                            // Saved Posts Tab
                            const SavedPostsScreen(),
                            // Liked Posts Tab
                            const LikedPostsScreen(),
                          ],
                        ),
                      );
                    } else {
                      // Other user's profile - show posts grid
                      return Selector<PostsProvider, Map<String, dynamic>>(
                        selector: (_, provider) => {
                          'userPosts': provider.userPosts,
                          'isLoading': provider.isLoading,
                          'isRefreshingUserPosts': provider.isRefreshingUserPosts,
                          'hasMoreUserPosts': provider.hasMoreUserPosts,
                        },
                        shouldRebuild: (prev, next) {
                          return prev['userPosts'] != next['userPosts'] ||
                                 prev['isLoading'] != next['isLoading'] ||
                                 prev['isRefreshingUserPosts'] != next['isRefreshingUserPosts'] ||
                                 prev['hasMoreUserPosts'] != next['hasMoreUserPosts'];
                        },
                        builder: (context, data, child) {
                          final userPosts = (data['userPosts'] as List).cast<Post>();
                          final isLoading = data['isLoading'] as bool;
                          final isRefreshingUserPosts = data['isRefreshingUserPosts'] as bool;
                          final hasMoreUserPosts = data['hasMoreUserPosts'] as bool;
                          
                          final postsProvider = context.read<PostsProvider>();
                          return PostGridWidget(
                            posts: userPosts,
                            isLoading: isLoading && !isRefreshingUserPosts,
                            hasMorePosts: hasMoreUserPosts,
                            onLoadMore: () async {
                              await _waitForAuthProvider();
                              
                              if (widget.userId != null) {
                                final prefs = await SharedPreferences.getInstance();
                                final accessToken = prefs.getString('access_token');
                                
                                await postsProvider.loadUserPosts(
                                  userId: widget.userId!,
                                  refresh: false,
                                  accessToken: accessToken,
                                );
                              }
                            },
                          );
                        },
                      );
                    }
                  },
                ),
              ],
            ),
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedStatColumn(String label, int count, {VoidCallback? onTap}) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: count),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Text(
              value.toString(),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
                fontSize: 16,
            color: Colors.white,
                height: 1.2,
          ),
            );
          },
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF8E8E8E),
            height: 1.2,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: column,
        ),
      );
    }

    return column;
  }
}
