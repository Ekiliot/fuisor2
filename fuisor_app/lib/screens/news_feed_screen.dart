import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/news_provider.dart';
import '../models/news.dart';
import '../widgets/news_grid_widget.dart';
import 'news_detail_screen.dart';

class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  final ScrollController _scrollController = ScrollController();
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    final newsProvider = Provider.of<NewsProvider>(context, listen: false);

    if (accessToken != null) {
      await newsProvider.loadCategories(accessToken: accessToken);
      await newsProvider.loadNewsFeed(
        refresh: true,
        accessToken: accessToken,
      );
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    final newsProvider = Provider.of<NewsProvider>(context, listen: false);

    if (!newsProvider.isLoading &&
        newsProvider.hasMoreNews &&
        accessToken != null) {
      await newsProvider.loadNewsFeed(
        refresh: false,
        categoryId: _selectedCategoryId,
        accessToken: accessToken,
      );
    }
  }

  Future<void> _onRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    final newsProvider = Provider.of<NewsProvider>(context, listen: false);

    if (accessToken != null) {
      await newsProvider.loadNewsFeed(
        refresh: true,
        categoryId: _selectedCategoryId,
        accessToken: accessToken,
      );
    }

    _refreshController.refreshCompleted();
  }

  Future<void> _onCategorySelected(String? categoryId) async {
    setState(() {
      _selectedCategoryId = categoryId;
    });

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    final newsProvider = Provider.of<NewsProvider>(context, listen: false);

    newsProvider.setSelectedCategory(categoryId);

    if (accessToken != null) {
      await newsProvider.loadNewsFeed(
        refresh: true,
        categoryId: categoryId,
        accessToken: accessToken,
      );
    }
  }

  void _onNewsTap(News news) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NewsDetailScreen(newsId: news.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NewsProvider>(
      builder: (context, newsProvider, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF000000),
          body: Column(
            children: [
              // Category filter chips
              if (newsProvider.categories.isNotEmpty)
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      // All categories chip
                      _CategoryChip(
                        label: 'All',
                        isSelected: _selectedCategoryId == null,
                        onTap: () => _onCategorySelected(null),
                      ),
                      const SizedBox(width: 8),
                      // Category chips
                      ...newsProvider.categories.map((category) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _CategoryChip(
                            label: category.nameEn,
                            isSelected: _selectedCategoryId == category.id,
                            onTap: () => _onCategorySelected(category.id),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              // News grid
              Expanded(
                child: newsProvider.isInitialLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0095F6),
                        ),
                      )
                    : SmartRefresher(
                        controller: _refreshController,
                        onRefresh: _onRefresh,
                        enablePullDown: true,
                        enablePullUp: false,
                        header: const ClassicHeader(
                          refreshingText: 'Refreshing...',
                          completeText: 'Refresh completed',
                          releaseText: 'Release to refresh',
                          idleText: 'Pull to refresh',
                          textStyle: TextStyle(color: Colors.white),
                        ),
                        child: NewsGridWidget(
                          news: newsProvider.news,
                          isLoading: newsProvider.isLoading,
                          hasMoreNews: newsProvider.hasMoreNews,
                          onLoadMore: _loadMore,
                          onNewsTap: _onNewsTap,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0095F6)
              : const Color(0xFF262626),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0095F6)
                : const Color(0xFF262626),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF8E8E8E),
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

