import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/news_provider.dart';
import '../widgets/app_notification.dart';
import 'news_comments_screen.dart';
import 'package:flutter_html/flutter_html.dart';

class NewsDetailScreen extends StatefulWidget {
  final String newsId;

  const NewsDetailScreen({
    super.key,
    required this.newsId,
  });

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    final newsProvider = Provider.of<NewsProvider>(context, listen: false);

    if (accessToken != null) {
      await newsProvider.loadNews(
        widget.newsId,
        accessToken: accessToken,
      );
    }
  }

  Future<void> _toggleLike() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    final newsProvider = Provider.of<NewsProvider>(context, listen: false);

    if (accessToken == null) {
      AppNotification.showError(context, 'Please login to like news');
      return;
    }

    try {
      await newsProvider.likeNews(
        widget.newsId,
        accessToken: accessToken,
      );
    } catch (e) {
      AppNotification.showError(context, 'Failed to like news: $e');
    }
  }

  Future<void> _openExternalLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        AppNotification.showError(context, 'Could not open link');
      }
    } catch (e) {
      AppNotification.showError(context, 'Error opening link: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(EvaIcons.arrowBackOutline, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'News',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Consumer<NewsProvider>(
        builder: (context, newsProvider, child) {
          final news = newsProvider.currentNews;

          if (newsProvider.isLoading && news == null) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0095F6),
              ),
            );
          }

          if (news == null) {
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
                  const Text(
                    'News not found',
                    style: TextStyle(
                      color: Color(0xFF8E8E8E),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go back'),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover image
                if (news.coverImageUrl != null && news.coverImageUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: news.coverImageUrl!,
                    width: double.infinity,
                    height: 250,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 250,
                      color: const Color(0xFF262626),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0095F6),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 250,
                      color: const Color(0xFF262626),
                      child: const Icon(
                        EvaIcons.imageOutline,
                        color: Color(0xFF8E8E8E),
                        size: 48,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (news.category != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0095F6).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                news.category!.nameEn,
                                style: const TextStyle(
                                  color: Color(0xFF0095F6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (news.subcategory != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF262626),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF262626)),
                              ),
                              child: Text(
                                news.subcategory!.nameEn,
                                style: const TextStyle(
                                  color: Color(0xFF8E8E8E),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Title
                      Text(
                        news.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Author and coauthor info
                      Row(
                        children: [
                          // Author avatar
                          if (news.user != null)
                            CircleAvatar(
                              radius: 16,
                              backgroundImage: news.user!.avatarUrl != null
                                  ? NetworkImage(news.user!.avatarUrl!)
                                  : null,
                              child: news.user!.avatarUrl == null
                                  ? const Icon(
                                      EvaIcons.personOutline,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          // Coauthor avatar (overlapping)
                          if (news.coauthor != null) ...[
                            const SizedBox(width: 8),
                            Stack(
                              children: [
                                Positioned(
                                  left: 16,
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundImage: news.coauthor!.avatarUrl != null
                                        ? NetworkImage(news.coauthor!.avatarUrl!)
                                        : null,
                                    child: news.coauthor!.avatarUrl == null
                                        ? const Icon(
                                            EvaIcons.personOutline,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF262626),
                                  child: const Icon(
                                    EvaIcons.personOutline,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  news.user?.username ?? 'Unknown',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (news.coauthor != null)
                                  Text(
                                    'with ${news.coauthor!.username}',
                                    style: const TextStyle(
                                      color: Color(0xFF8E8E8E),
                                      fontSize: 12,
                                    ),
                                  ),
                                Text(
                                  DateFormat('MMM d, y').format(news.createdAt),
                                  style: const TextStyle(
                                    color: Color(0xFF8E8E8E),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Stats
                      Row(
                        children: [
                          const Icon(
                            EvaIcons.eyeOutline,
                            size: 16,
                            color: Color(0xFF8E8E8E),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${news.viewsCount} views',
                            style: const TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(
                            EvaIcons.heartOutline,
                            size: 16,
                            color: Color(0xFF8E8E8E),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${news.likesCount} likes',
                            style: const TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(
                            EvaIcons.messageCircleOutline,
                            size: 16,
                            color: Color(0xFF8E8E8E),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${news.commentsCount} comments',
                            style: const TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _toggleLike,
                              icon: Icon(
                                news.isLiked
                                    ? EvaIcons.heart
                                    : EvaIcons.heartOutline,
                                color: news.isLiked
                                    ? Colors.red
                                    : Colors.white,
                              ),
                              label: Text(
                                news.isLiked ? 'Liked' : 'Like',
                                style: TextStyle(
                                  color: news.isLiked
                                      ? Colors.red
                                      : Colors.white,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: news.isLiked
                                      ? Colors.red
                                      : const Color(0xFF262626),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => NewsCommentsScreen(
                                      newsId: news.id,
                                      news: news,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                EvaIcons.messageCircleOutline,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Comment',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF262626)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // External link button
                      if (news.externalLinkUrl != null &&
                          news.externalLinkUrl!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0095F6),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0095F6).withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => _openExternalLink(news.externalLinkUrl!),
                              child: Center(
                                child: Text(
                                  news.externalLinkText ?? 'Read more',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Content
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF262626)),
                        ),
                        child: Html(
                          data: news.sanitizedContent ?? news.content,
                          style: {
                            "body": Style(
                              color: Colors.white,
                              fontSize: FontSize(16.0),
                              lineHeight: LineHeight(1.6),
                              margin: Margins.zero,
                              padding: HtmlPaddings.zero,
                            ),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

