import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/news.dart';
import '../models/user.dart';

class NewsCardSquare extends StatelessWidget {
  final News news;
  final VoidCallback? onTap;

  const NewsCardSquare({
    super.key,
    required this.news,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF262626),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: news.coverImageUrl != null && news.coverImageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: news.coverImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: const Color(0xFF262626),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF0095F6),
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFF262626),
                          child: const Icon(
                            EvaIcons.imageOutline,
                            color: Color(0xFF8E8E8E),
                            size: 32,
                          ),
                        ),
                      )
                    : Container(
                        color: const Color(0xFF262626),
                        child: const Icon(
                          EvaIcons.fileTextOutline,
                          color: Color(0xFF8E8E8E),
                          size: 32,
                        ),
                      ),
              ),
            ),
            // Content
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category badge
                    if (news.category != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0095F6).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          news.category!.nameEn,
                          style: const TextStyle(
                            color: Color(0xFF0095F6),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (news.category != null) const SizedBox(height: 8),
                    // Title
                    Text(
                      news.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    // Author and coauthor
                    Row(
                      children: [
                        // Author avatar
                        if (news.user != null)
                          CircleAvatar(
                            radius: 10,
                            backgroundImage: news.user!.avatarUrl != null
                                ? NetworkImage(news.user!.avatarUrl!)
                                : null,
                            child: news.user!.avatarUrl == null
                                ? const Icon(
                                    EvaIcons.personOutline,
                                    size: 12,
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
                                left: 8,
                                child: CircleAvatar(
                                  radius: 10,
                                  backgroundImage: news.coauthor!.avatarUrl != null
                                      ? NetworkImage(news.coauthor!.avatarUrl!)
                                      : null,
                                  child: news.coauthor!.avatarUrl == null
                                      ? const Icon(
                                          EvaIcons.personOutline,
                                          size: 12,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: const Color(0xFF262626),
                                child: const Icon(
                                  EvaIcons.personOutline,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(width: 8),
                        // Author name
                        Expanded(
                          child: Text(
                            news.user?.username ?? 'Unknown',
                            style: const TextStyle(
                              color: Color(0xFF8E8E8E),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Stats
                    Row(
                      children: [
                        const Icon(
                          EvaIcons.eyeOutline,
                          size: 12,
                          color: Color(0xFF8E8E8E),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${news.viewsCount}',
                          style: const TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          EvaIcons.heartOutline,
                          size: 12,
                          color: Color(0xFF8E8E8E),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${news.likesCount}',
                          style: const TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          EvaIcons.messageCircleOutline,
                          size: 12,
                          color: Color(0xFF8E8E8E),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${news.commentsCount}',
                          style: const TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

