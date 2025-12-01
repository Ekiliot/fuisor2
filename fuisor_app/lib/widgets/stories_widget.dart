import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/camera_screen.dart';
import '../screens/profile_screen.dart';
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
  DateTime? _lastLoadTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStories();
    
    // Listen to auth provider changes
    final authProvider = context.read<AuthProvider>();
    authProvider.addListener(_onAuthChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reload stories when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      // Only reload if more than 5 seconds have passed since last load
      if (_lastLoadTime == null || 
          DateTime.now().difference(_lastLoadTime!) > const Duration(seconds: 5)) {
        _loadStories();
      }
    }
  }

  void _onAuthChanged() {
    // Reload stories when user changes
    _loadStories();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final authProvider = context.read<AuthProvider>();
    authProvider.removeListener(_onAuthChanged);
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
      final users = await apiService.getUsersWithStories();

      // Check if current user has active stories
      final currentUserHasStories = users.any((u) => u.id == _currentUser?.id && u.hasStories == true);

      if (mounted) {
        setState(() {
          _usersWithStories = users;
          _currentUserHasStories = currentUserHasStories;
          _isLoading = false;
          _lastLoadTime = DateTime.now();
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
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
                strokeWidth: 2,
              ),
            )
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

  Widget _buildAddStoryItem(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const CameraScreen(),
          ),
        );
        // Reload stories when returning from camera
        if (mounted) {
          _loadStories();
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
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: user.id),
          ),
        );
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
