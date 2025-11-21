import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/animated_app_bar_title.dart';
import 'hashtag_feed_screen.dart';

class HashtagScreen extends StatefulWidget {
  final String hashtag;

  const HashtagScreen({
    super.key,
    required this.hashtag,
  });

  @override
  State<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends State<HashtagScreen> {
  final ApiService _apiService = ApiService();
  List<Post> _posts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  final int _limit = 10;

  @override
  void initState() {
    super.initState();
    _loadHashtagPosts();
  }

  Future<void> _loadHashtagPosts({bool loadMore = false}) async {
    try {
      if (loadMore) {
        setState(() {
          _isLoadingMore = true;
        });
      } else {
        setState(() {
          _isLoading = true;
          _error = null;
        });
      }

      // Get access token from AuthProvider
      final authProvider = context.read<AuthProvider>();
      final accessToken = await authProvider.getAccessToken();
      
      if (accessToken == null) {
        throw Exception('No access token available');
      }

      // Set token in ApiService
      _apiService.setAccessToken(accessToken);

      print('HashtagScreen: Loading posts for hashtag: ${widget.hashtag}');
      print('HashtagScreen: Page: $_currentPage, Limit: $_limit');
      
      final posts = await _apiService.getPostsByHashtag(
        widget.hashtag,
        page: _currentPage,
        limit: _limit,
      );
      
      print('HashtagScreen: Received ${posts.length} posts');

      setState(() {
        if (loadMore) {
          _posts.addAll(posts);
        } else {
          _posts = posts;
        }
        _isLoading = false;
        _isLoadingMore = false;
        _currentPage++;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refreshPosts() async {
    setState(() {
      _currentPage = 1;
    });
    await _loadHashtagPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            EvaIcons.arrowBack,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: AnimatedAppBarTitle(
          text: '#${widget.hashtag}',
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        EvaIcons.alertCircleOutline,
                        color: Colors.red,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading hashtag posts',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _refreshPosts,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0095F6),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshPosts,
                  color: const Color(0xFF0095F6),
                  backgroundColor: const Color(0xFF000000),
                  child: CustomScrollView(
                    slivers: [
                      // Hashtag header
                      SliverToBoxAdapter(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Hashtag icon and name
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0095F6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    EvaIcons.hash,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '#${widget.hashtag}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${_posts.length} ${_posts.length == 1 ? 'post' : 'posts'}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Posts grid
                      if (_posts.isEmpty)
                        const SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  Icon(
                                    EvaIcons.imageOutline,
                                    color: Colors.grey,
                                    size: 64,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No posts found',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Be the first to post with this hashtag!',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2,
                            childAspectRatio: 1,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final post = _posts[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => HashtagFeedScreen(
                                        hashtag: widget.hashtag,
                                      ),
                                    ),
                                  );
                                },
                                child: CachedNetworkImage(
                                  imageUrl: post.mediaUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: const Color(0xFF1A1A1A),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF0095F6),
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: const Color(0xFF1A1A1A),
                                    child: const Icon(
                                      EvaIcons.imageOutline,
                                      color: Colors.grey,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: _posts.length,
                          ),
                        ),
                      // Load more indicator
                      if (_isLoadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF0095F6),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
