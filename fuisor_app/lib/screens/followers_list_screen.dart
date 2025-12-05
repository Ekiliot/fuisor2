import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../widgets/safe_avatar.dart';
import '../widgets/animated_app_bar_title.dart';
import 'profile_screen.dart';
import '../widgets/app_notification.dart';

class FollowersListScreen extends StatefulWidget {
  final String userId;
  final String title; // "Followers" or "Following"
  final bool isFollowers; // true = followers, false = following

  const FollowersListScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.isFollowers,
  });

  @override
  State<FollowersListScreen> createState() => _FollowersListScreenState();
}

class _FollowersListScreenState extends State<FollowersListScreen> {
  final ApiService _apiService = ApiService();
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  final ScrollController _scrollController = ScrollController();

  List<User> _users = [];
  bool _isLoading = false;
  bool _isInitialLoading = true;
  bool _hasMoreUsers = true;
  int _currentPage = 1;
  String? _error;
  
  // Track follow status for each user (userId -> isFollowing)
  final Map<String, bool> _followStatus = {};
  final Map<String, bool> _isTogglingFollow = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _setupApiService();
  }

  Future<void> _setupApiService() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    if (accessToken != null) {
      _apiService.setAccessToken(accessToken);
    }
    _loadUsers(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMoreUsers) {
        _loadMoreUsers();
      }
    }
  }

  Future<void> _loadUsers({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _currentPage = 1;
      _hasMoreUsers = true;
      _users = [];
      _isInitialLoading = true;
    } else {
      _isLoading = true;
    }

    _error = null;
    if (mounted) setState(() {});

    try {
      final response = widget.isFollowers
          ? await _apiService.getFollowers(widget.userId, page: _currentPage, limit: 20)
          : await _apiService.getFollowing(widget.userId, page: _currentPage, limit: 20);

      final List<dynamic> usersData = widget.isFollowers
          ? (response['followers'] ?? [])
          : (response['following'] ?? []);
          
      final List<User> newUsers = usersData
          .map((json) => User.fromJson(json))
          .toList();

      if (refresh) {
        _users = newUsers;
      } else {
        _users.addAll(newUsers);
      }

      // Check follow status for all new users
      await _checkFollowStatuses(newUsers);

      _hasMoreUsers = newUsers.length >= 20;
      _currentPage++;
    } catch (e) {
      print('Error loading users: $e');
      _error = e.toString();
      if (!refresh) {
        _hasMoreUsers = false;
      }
    } finally {
      _isLoading = false;
      _isInitialLoading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMoreUsers() async {
    await _loadUsers(refresh: false);
  }

  Future<void> _onRefresh() async {
    await _loadUsers(refresh: true);
    _refreshController.refreshCompleted();
  }

  Future<void> _checkFollowStatuses(List<User> users) async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser == null) return;
    
    final currentUserId = authProvider.currentUser!.id;
    
    for (final user in users) {
      // Skip checking for current user
      if (user.id == currentUserId) {
        _followStatus[user.id] = false; // No button for current user
        continue;
      }
      
      try {
        final isFollowing = await _apiService.checkFollowStatus(user.id);
        setState(() {
          _followStatus[user.id] = isFollowing;
        });
      } catch (e) {
        print('Error checking follow status for ${user.id}: $e');
        setState(() {
          _followStatus[user.id] = false;
        });
      }
    }
  }

  Future<void> _toggleFollow(User user) async {
    if (_isTogglingFollow[user.id] == true) return;
    
    setState(() {
      _isTogglingFollow[user.id] = true;
    });
    
    try {
      final wasFollowing = _followStatus[user.id] ?? false;
      
      if (wasFollowing) {
        await _apiService.unfollowUser(user.id);
      } else {
        await _apiService.followUser(user.id);
      }
      
      setState(() {
        _followStatus[user.id] = !wasFollowing;
      });
    } catch (e) {
      print('Error toggling follow: $e');
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to ${_followStatus[user.id] == true ? 'unfollow' : 'follow'}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingFollow[user.id] = false;
        });
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
        title: AnimatedAppBarTitle(
          text: widget.title,
        ),
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF0095F6),
        ),
      );
    }

    if (_error != null && _users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              EvaIcons.alertCircleOutline,
              size: 64,
              color: Color(0xFF8E8E8E),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load ${widget.title.toLowerCase()}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _loadUsers(refresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isFollowers ? EvaIcons.peopleOutline : EvaIcons.personDoneOutline,
              size: 80,
              color: const Color(0xFF8E8E8E),
            ),
            const SizedBox(height: 16),
            Text(
              'No ${widget.title.toLowerCase()} yet',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return SmartRefresher(
      controller: _refreshController,
      enablePullDown: true,
      onRefresh: _onRefresh,
      header: const WaterDropHeader(
        waterDropColor: Color(0xFF0095F6),
        complete: SizedBox.shrink(),
      ),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _users.length + (_isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _users.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF0095F6),
                ),
              ),
            );
          }

          final user = _users[index];
          return _buildUserItem(user);
        },
      ),
    );
  }

  Widget _buildUserItem(User user) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ProfileScreen(userId: user.id),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // User avatar
            SafeAvatar(
              imageUrl: user.avatarUrl,
              radius: 24,
            ),
            const SizedBox(width: 12),
            
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (user.name.isNotEmpty)
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8E8E),
                      ),
                    ),
                ],
              ),
            ),
            
            // Follow/Unfollow button or nothing if current user
            Builder(
              builder: (context) {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                final currentUserId = authProvider.currentUser?.id;
                
                // Don't show button for current user
                if (user.id == currentUserId) {
                  return const SizedBox.shrink();
                }
                
                final isFollowing = _followStatus[user.id] ?? false;
                final isToggling = _isTogglingFollow[user.id] ?? false;
                
                return ElevatedButton(
                  onPressed: isToggling ? null : () => _toggleFollow(user),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFollowing
                        ? const Color(0xFF262626)
                        : const Color(0xFF0095F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  ),
                  child: isToggling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          isFollowing ? 'Unfollow' : 'Follow',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

