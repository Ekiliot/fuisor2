import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../providers/posts_provider.dart';
import '../services/api_service.dart';
import '../widgets/safe_avatar.dart';
import '../widgets/post_grid_widget.dart';
import '../widgets/profile_menu_sheet.dart';
import '../models/user.dart';
import 'edit_profile_screen.dart';
import 'followers_list_screen.dart';
import 'saved_posts_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      final targetUserId = widget.userId ?? authProvider.currentUser?.id;
      
      if (targetUserId != null && targetUserId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final accessToken = prefs.getString('access_token');
        
        print('ProfileScreen: Loading posts for user: $targetUserId');
        
        // Загружаем пользователя и посты параллельно
        final futures = <Future>[];
        
        // Load the user's profile if viewing another user
        if (widget.userId != null && widget.userId != authProvider.currentUser?.id) {
          if (!_isLoadingUserData) {
            _isLoadingUserData = true;
            setState(() {
              _isLoadingUser = true;
            });
            
            futures.add(_loadUserData(widget.userId!));
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
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: widget.userId != null
            ? IconButton(
                icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            final displayUser = _viewingUser ?? authProvider.currentUser;
            return Text(
              '@${displayUser?.username ?? 'Profile'}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
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
          if (isViewingOtherUser) {
            // Для чужого профиля показываем только _viewingUser, не currentUser
            user = _viewingUser;
            
            // Если данные еще не загружены, показываем скелетон
            if (user == null && _isLoadingUser) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
            
            // Если данные не загружены и загрузка не идет, показываем ошибку
            if (user == null) {
              return const Center(
                child: Text(
                  'User not found',
                  style: TextStyle(color: Colors.white),
                ),
              );
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

          return SmartRefresher(
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
                  child: Column(
                    children: [
                      // Name and Profile Picture Row
                      Row(
                        children: [
                          // Profile Picture with loading indicator
                          Stack(
                            children: [
                              SafeAvatar(
                                imageUrl: user.avatarUrl,
                                radius: 40,
                                backgroundColor: const Color(0xFF262626),
                                fallbackIcon: EvaIcons.personOutline,
                                iconColor: Colors.white,
                              ),
                              if (_isLoadingUser)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 20),
                          // Name next to profile picture
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_isLoadingUser)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0095F6)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Stats Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatColumn('Posts', user.postsCount),
                          _buildStatColumn(
                            'Followers',
                            user.followersCount,
                            onTap: () {
                              final userId = user!.id; // user гарантированно не null здесь
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
                          _buildStatColumn(
                            'Following',
                            user.followingCount,
                            onTap: () {
                              final userId = user!.id; // user гарантированно не null здесь
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
                    ],
                  ),
                ),

                // Bio Section (if exists)
                if (user.bio != null && user.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      user.bio!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
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

                // Tabs (only for own profile)
                Builder(
                  builder: (context) {
                    final authProvider = context.read<AuthProvider>();
                    if (widget.userId == null || widget.userId == authProvider.currentUser?.id) {
                      return Column(
                        children: [
                          TabBar(
                            controller: _tabController,
                            indicatorColor: Colors.white,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.grey,
                            tabs: const [
                              Tab(
                                icon: Icon(EvaIcons.gridOutline),
                              ),
                              Tab(
                                icon: Icon(EvaIcons.bookmarkOutline),
                              ),
                            ],
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
          );
        },
      ),
    );
  }

  Widget _buildStatColumn(String label, int count, {VoidCallback? onTap}) {
    final column = Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E8E),
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        child: column,
      );
    }

    return column;
  }
}
