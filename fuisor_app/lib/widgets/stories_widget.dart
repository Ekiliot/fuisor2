import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/camera_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/geo_stories_viewer.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import 'cached_network_image_with_signed_url.dart';

class StoriesWidget extends StatefulWidget {
  const StoriesWidget({super.key});

  @override
  State<StoriesWidget> createState() => _StoriesWidgetState();
}

class _StoriesWidgetState extends State<StoriesWidget> with WidgetsBindingObserver {
  List<User> _usersWithStories = [];
  bool _isLoading = true;
  User? _currentUser;
  bool _currentUserHasStories = false;
  AuthProvider? _authProvider; // Сохраняем ссылку на provider

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Сохраняем ссылку на AuthProvider в didChangeDependencies
    if (_authProvider == null) {
      _authProvider = context.read<AuthProvider>();
      _authProvider?.addListener(_onAuthChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reload stories when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      print('StoriesWidget: App resumed, reloading stories');
      // Always reload when app resumes to catch new stories
      _loadStories();
    }
  }

  void _onAuthChanged() {
    // Reload stories when user changes
    _loadStories();
  }

  Future<void> _openStoriesViewer(String userId) async {
    try {
      print('StoriesWidget: Loading stories for user: $userId');
      
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        print('StoriesWidget: No access token');
        return;
      }

      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      
      final stories = await apiService.getUserStories(userId);
      
      if (stories.isEmpty) {
        print('StoriesWidget: No active stories found');
        // Если нет активных сторис, открываем профиль
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ProfileScreen(userId: userId),
            ),
          );
        }
        return;
      }

      print('StoriesWidget: Found ${stories.length} active stories');
      
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => GeoStoriesViewer(
              initialPost: stories.first,
              posts: stories,
            ),
          ),
        );
      }
    } catch (e) {
      print('StoriesWidget: Error opening stories viewer: $e');
      if (mounted) {
        // При ошибке открываем профиль
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: userId),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Используем сохраненную ссылку вместо context.read
    _authProvider?.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _loadStories() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current user from AuthProvider
      final authProvider = context.read<AuthProvider>();
      _currentUser = authProvider.currentUser;

      // Get access token
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Get users with active stories
      final apiService = ApiService();
      apiService.setAccessToken(accessToken);
      final result = await apiService.getUsersWithStories();

      final users = result['users'] as List<User>;
      final currentUserHasStories = result['currentUserHasStories'] as bool;

      print('StoriesWidget: Loaded ${users.length} users with stories');
      print('StoriesWidget: Current user has stories: $currentUserHasStories');

      if (mounted) {
        setState(() {
          _usersWithStories = users;
          _currentUserHasStories = currentUserHasStories;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('StoriesWidget: Error loading stories: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      margin: const EdgeInsets.only(top: 0, bottom: 8),
      child: _isLoading
          ? _buildLoadingShimmer()
          : ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: 1 + _usersWithStories.length, // 1 for "Your Story" + users with stories
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildAddStoryItem(context);
          }
                final user = _usersWithStories[index - 1];
                return _buildStoryItem(user);
        },
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: 8, // Show 8 shimmer items
      itemBuilder: (context, index) {
        return _ShimmerStoryItem(key: ValueKey('shimmer_$index'));
      },
    );
  }

  Widget _buildAddStoryItem(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        // Если у текущего пользователя есть сторис - показываем их
        // Иначе открываем камеру для создания нового сторис
        if (_currentUserHasStories && _currentUser != null) {
          print('StoriesWidget: Opening current user stories');
          await _openStoriesViewer(_currentUser!.id);
        } else {
          print('StoriesWidget: Opening camera to create story');
          await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const CameraScreen(),
          ),
        );
          // Reload stories when returning from camera (with longer delay to allow DB to update)
          print('StoriesWidget: Returned from camera, reloading stories');
          if (mounted) {
            // Увеличиваем задержку до 1.5 секунд для надежности
            await Future.delayed(const Duration(milliseconds: 1500));
            print('StoriesWidget: Delay finished, calling _loadStories');
            await _loadStories();
          }
        }
      },
      child: Container(
      width: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Stack(
            children: [
                // Avatar with gradient border if user has active stories
                if (_currentUserHasStories)
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF833AB4),
                          Color(0xFFE1306C),
                          Color(0xFFFD1D1D),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF000000),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: _currentUser != null && _currentUser!.avatarUrl != null && _currentUser!.avatarUrl!.isNotEmpty
                          ? ClipOval(
                              child: CachedNetworkImageWithSignedUrl(
                                imageUrl: _currentUser!.avatarUrl!,
                                postId: null, // Not a post, so no postId
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                placeholder: (context) => Container(
                                  width: 56,
                                  height: 56,
                                  color: const Color(0xFF262626),
                                  child: const Icon(
                                    EvaIcons.personOutline,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 56,
                                  height: 56,
                                  color: const Color(0xFF262626),
                                  child: const Icon(
                                    EvaIcons.personOutline,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            )
                          : const CircleAvatar(
                              backgroundColor: Color(0xFF262626),
                              child: Icon(
                                EvaIcons.personOutline,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                    ),
                  )
                else
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF262626),
                    width: 2,
                  ),
                ),
                    child: _currentUser != null && _currentUser!.avatarUrl != null && _currentUser!.avatarUrl!.isNotEmpty
                        ? ClipOval(
                            child: CachedNetworkImageWithSignedUrl(
                              imageUrl: _currentUser!.avatarUrl!,
                              postId: null, // Not a post, so no postId
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              placeholder: (context) => Container(
                                color: const Color(0xFF262626),
                                child: const Icon(
                                  EvaIcons.personOutline,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: const Color(0xFF262626),
                                child: const Icon(
                                  EvaIcons.personOutline,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                          )
                        : const CircleAvatar(
                  backgroundColor: Color(0xFF262626),
                  child: Icon(
                    EvaIcons.personOutline,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
                // Показываем кнопку "+" только если нет активных сторис
                if (!_currentUserHasStories)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0095F6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    EvaIcons.plus,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
            Text(
              _currentUser?.name.isNotEmpty == true 
                  ? _currentUser!.name 
                  : (_currentUser?.username ?? 'Your Story'),
              style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildStoryItem(User user) {
    final hasStories = user.hasStories == true;
    
    return GestureDetector(
      onTap: () async {
        // Если у пользователя есть сторис - открываем просмотр сторис
        if (hasStories) {
          await _openStoriesViewer(user.id);
        } else {
          // Если нет сторис - открываем профиль
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ProfileScreen(userId: user.id),
            ),
          );
        }
      },
      child: Container(
      width: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
            // Avatar with gradient border (only for users with stories)
            if (hasStories)
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF833AB4),
                  Color(0xFFE1306C),
                  Color(0xFFFD1D1D),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF000000),
              ),
              padding: const EdgeInsets.all(2),
                  child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImageWithSignedUrl(
                            imageUrl: user.avatarUrl!,
                            postId: null, // Not a post, so no postId
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            placeholder: (context) => Container(
                              width: 56,
                              height: 56,
                              color: const Color(0xFF262626),
                              child: const Icon(
                                EvaIcons.personOutline,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 56,
                              height: 56,
                              color: const Color(0xFF262626),
                              child: const Icon(
                                EvaIcons.personOutline,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        )
                      : const CircleAvatar(
                backgroundColor: Color(0xFF262626),
                child: Icon(
                  EvaIcons.personOutline,
                  color: Colors.white,
                  size: 24,
                ),
              ),
                ),
              )
            else
              // Avatar without gradient border (for users without stories)
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF262626),
                    width: 2,
                  ),
                ),
                child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                    ? ClipOval(
                        child: CachedNetworkImageWithSignedUrl(
                          imageUrl: user.avatarUrl!,
                          postId: null, // Not a post, so no postId
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          placeholder: (context) => Container(
                            color: const Color(0xFF262626),
                            child: const Icon(
                              EvaIcons.personOutline,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF262626),
                            child: const Icon(
                              EvaIcons.personOutline,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      )
                    : const CircleAvatar(
                        backgroundColor: Color(0xFF262626),
                        child: Icon(
                          EvaIcons.personOutline,
                          color: Colors.white,
                          size: 30,
                        ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
              user.name.isNotEmpty ? user.name : user.username,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      ),
    );
  }
}

// Shimmer animation for loading state
class _ShimmerStoryItem extends StatefulWidget {
  const _ShimmerStoryItem({super.key});

  @override
  State<_ShimmerStoryItem> createState() => _ShimmerStoryItemState();
}

class _ShimmerStoryItemState extends State<_ShimmerStoryItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 70,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              // Shimmer circle
              Opacity(
                opacity: _animation.value,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(
                          const Color(0xFF1A1A1A),
                          const Color(0xFF2A2A2A),
                          _animation.value,
                        )!,
                        Color.lerp(
                          const Color(0xFF2A2A2A),
                          const Color(0xFF1A1A1A),
                          _animation.value,
                        )!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Shimmer text
              Opacity(
                opacity: _animation.value,
                child: Container(
                  width: 50,
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(
                          const Color(0xFF1A1A1A),
                          const Color(0xFF2A2A2A),
                          _animation.value,
                        )!,
                        Color.lerp(
                          const Color(0xFF2A2A2A),
                          const Color(0xFF1A1A1A),
                          _animation.value,
                        )!,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
