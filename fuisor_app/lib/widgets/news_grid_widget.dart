import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../models/news.dart';
import 'news_card_square.dart';
import 'news_card_rectangle.dart';

enum NewsLayoutType { square, rectangle }

class NewsGridWidget extends StatefulWidget {
  final List<News> news;
  final VoidCallback? onLoadMore;
  final bool isLoading;
  final bool hasMoreNews;
  final Function(News)? onNewsTap;

  const NewsGridWidget({
    super.key,
    required this.news,
    this.onLoadMore,
    this.isLoading = false,
    this.hasMoreNews = true,
    this.onNewsTap,
  });

  @override
  State<NewsGridWidget> createState() => _NewsGridWidgetState();
}

class _NewsGridWidgetState extends State<NewsGridWidget> {
  NewsLayoutType _layoutType = NewsLayoutType.square;

  void _toggleLayout() {
    setState(() {
      _layoutType = _layoutType == NewsLayoutType.square
          ? NewsLayoutType.rectangle
          : NewsLayoutType.square;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.news.isEmpty && !widget.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              EvaIcons.fileTextOutline,
              size: 64,
              color: Color(0xFF8E8E8E),
            ),
            const SizedBox(height: 16),
            const Text(
              'No news yet',
              style: TextStyle(
                color: Color(0xFF8E8E8E),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Layout toggle button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  _layoutType == NewsLayoutType.square
                      ? EvaIcons.gridOutline
                      : EvaIcons.listOutline,
                  color: Colors.white,
                ),
                onPressed: _toggleLayout,
                tooltip: _layoutType == NewsLayoutType.square
                    ? 'Switch to list view'
                    : 'Switch to grid view',
              ),
            ],
          ),
        ),
        // News list/grid
        Expanded(
          child: _layoutType == NewsLayoutType.square
              ? _buildSquareGrid()
              : _buildRectangleList(),
        ),
        // Loading indicator
        if (widget.isLoading)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(
              color: Color(0xFF0095F6),
            ),
          ),
        // Load more button
        if (!widget.isLoading && widget.hasMoreNews && widget.onLoadMore != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: OutlinedButton(
              onPressed: widget.onLoadMore,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF262626)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Load more',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSquareGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: widget.news.length,
      itemBuilder: (context, index) {
        final news = widget.news[index];
        return NewsCardSquare(
          news: news,
          onTap: () => widget.onNewsTap?.call(news),
        );
      },
    );
  }

  Widget _buildRectangleList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: widget.news.length,
      itemBuilder: (context, index) {
        final news = widget.news[index];
        return NewsCardRectangle(
          news: news,
          onTap: () => widget.onNewsTap?.call(news),
        );
      },
    );
  }
}

