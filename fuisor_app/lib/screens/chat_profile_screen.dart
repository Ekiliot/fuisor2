import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart' show Post;
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/safe_avatar.dart';
import '../widgets/voice_message_player.dart';
import '../widgets/app_notification.dart';
import 'profile_screen.dart';
import 'full_screen_image_viewer.dart';
import 'full_screen_video_viewer.dart';
import 'post_detail_screen.dart';

class ChatProfileScreen extends StatefulWidget {
  final Chat chat;

  const ChatProfileScreen({
    super.key,
    required this.chat,
  });

  @override
  State<ChatProfileScreen> createState() => _ChatProfileScreenState();
}

class _ChatProfileScreenState extends State<ChatProfileScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  
  List<Message> _photoMessages = [];
  List<Message> _videoMessages = [];
  List<Message> _voiceMessages = [];
  List<Message> _linkMessages = [];
  List<Message> _postMessages = [];
  Map<String, Post> _postsCache = {}; // Кеш постов по postId
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadChatMedia();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadChatMedia() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      
      // Загружаем все сообщения чата через пагинацию
      List<Message> allMessages = [];
      int page = 1;
      const int limit = 100; // Загружаем по 100 сообщений за раз
      bool hasMore = true;
      
      while (hasMore) {
        final response = await _apiService.getMessages(widget.chat.id, page: page, limit: limit);
        final List<dynamic> messagesData = response['messages'] ?? [];
        final List<Message> pageMessages = messagesData.map((json) => Message.fromJson(json)).toList();
        
        if (pageMessages.isEmpty) {
          hasMore = false;
        } else {
          allMessages.addAll(pageMessages);
          // Если получили меньше сообщений, чем лимит, значит это последняя страница
          if (pageMessages.length < limit) {
            hasMore = false;
          } else {
            page++;
          }
        }
      }
      
      // Фильтруем удаленные сообщения (не показываем сообщения, удаленные текущим пользователем)
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.id;
      final activeMessages = allMessages.where((m) => 
        m.deletedAt == null || 
        (m.deletedByIds != null && currentUserId != null && !m.deletedByIds!.contains(currentUserId))
      ).toList();
      
      setState(() {
        // Фильтруем по типам
        _photoMessages = activeMessages.where((m) => 
          m.mediaUrl != null && m.messageType == 'image'
        ).toList();
        
        _videoMessages = activeMessages.where((m) => 
          m.mediaUrl != null && m.messageType == 'video'
        ).toList();
        
        _voiceMessages = activeMessages.where((m) => 
          m.mediaUrl != null && m.messageType == 'voice'
        ).toList();
        
        // Сообщения со ссылками (содержат http:// или https://)
        _linkMessages = activeMessages.where((m) => 
          m.content != null && 
          (m.content!.contains('http://') || m.content!.contains('https://'))
        ).toList();
        
        // Сообщения с постами (если есть postId)
        _postMessages = activeMessages.where((m) => 
          m.postId != null && m.postId!.isNotEmpty
        ).toList();
        
        _isLoading = false;
      });
      
      // Загружаем информацию о постах
      await _loadPostsInfo();
    } catch (e) {
      print('Error loading chat media: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPostsInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      
      if (accessToken == null) return;

      _apiService.setAccessToken(accessToken);
      
      // Получаем уникальные postId из сообщений
      final postIds = _postMessages
          .where((m) => m.postId != null && m.postId!.isNotEmpty)
          .map((m) => m.postId!)
          .toSet()
          .toList();
      
      // Загружаем информацию о каждом посте
      final Map<String, Post> postsCache = {};
      for (final postId in postIds) {
        try {
          final post = await _apiService.getPost(postId);
          postsCache[postId] = post;
        } catch (e) {
          print('Error loading post $postId: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _postsCache = postsCache;
        });
      }
    } catch (e) {
      print('Error loading posts info: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // Прозрачная шапка с размытием
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.black.withOpacity(0.3),
                      ],
                    ),
                  ),
                  child: FlexibleSpaceBar(
                    background: _buildProfileHeader(),
                    collapseMode: CollapseMode.parallax,
                  ),
                ),
              ),
            ),
            leading: IconButton(
              icon: const Icon(EvaIcons.arrowBack, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(EvaIcons.moreVerticalOutline, color: Colors.white),
                onPressed: () {
                  // Дополнительные опции
                },
              ),
            ],
          ),
          
          // Custom Tabs (как в профиле)
          SliverToBoxAdapter(
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, child) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Фото Tab
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_tabController.index != 0) {
                              _tabController.animateTo(0);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _tabController.index == 0
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Center(
                              child: Icon(
                                EvaIcons.image,
                                color: _tabController.index == 0
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Видео Tab
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_tabController.index != 1) {
                              _tabController.animateTo(1);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _tabController.index == 1
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Center(
                              child: Icon(
                                EvaIcons.video,
                                color: _tabController.index == 1
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Голосовые Tab
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_tabController.index != 2) {
                              _tabController.animateTo(2);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _tabController.index == 2
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Center(
                              child: Icon(
                                EvaIcons.mic,
                                color: _tabController.index == 2
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Ссылки Tab
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_tabController.index != 3) {
                              _tabController.animateTo(3);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _tabController.index == 3
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Center(
                              child: Icon(
                                EvaIcons.link2,
                                color: _tabController.index == 3
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Посты Tab
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_tabController.index != 4) {
                              _tabController.animateTo(4);
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _tabController.index == 4
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Center(
                              child: Icon(
                                EvaIcons.gridOutline,
                                color: _tabController.index == 4
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          // Контент вкладок
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF0095F6),
                ),
              ),
            )
          else
            SliverFillRemaining(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPhotoGrid(),
                  _buildVideoGrid(),
                  _buildVoiceList(),
                  _buildLinkList(),
                  _buildPostGrid(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final user = widget.chat.otherUser;
    
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Аватар
          GestureDetector(
            onTap: () {
              if (user != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(userId: user.id),
                  ),
                );
              }
            },
            child: SafeAvatar(
              imageUrl: widget.chat.displayAvatar,
              radius: 45,
            ),
          ),
          const SizedBox(height: 12),
          
          // Имя
          Text(
            widget.chat.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          
          // Username
          if (user?.username != null)
            Text(
              '@${user!.username}',
              style: const TextStyle(
                color: Color(0xFF8E8E8E),
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 12),
          
          // Кнопки действий (scrollable для предотвращения переполнения)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(
                  icon: EvaIcons.personOutline,
                  label: 'Профиль',
                  onTap: () {
                    if (user != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfileScreen(userId: user.id),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: EvaIcons.bellOff,
                  label: 'Заглушить',
                  onTap: () {
                    // TODO: Mute chat
                  },
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: EvaIcons.searchOutline,
                  label: 'Поиск',
                  onTap: () {
                    // TODO: Search in chat
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF3A3A3A),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGrid() {
    if (_photoMessages.isEmpty) {
      return _buildEmptyState(
        icon: EvaIcons.image,
        message: 'Нет фотографий',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1, // Квадратные элементы
      ),
      itemCount: _photoMessages.length,
      itemBuilder: (context, index) {
        final message = _photoMessages[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (message.mediaUrl != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FullScreenImageViewer(
                      imageUrl: message.mediaUrl!,
                      chatId: widget.chat.id,
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: message.mediaUrl != null
                    ? CachedNetworkImage(
                        imageUrl: message.mediaUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0095F6),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            EvaIcons.image,
                            color: Color(0xFF8E8E8E),
                            size: 32,
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          EvaIcons.image,
                          color: Color(0xFF8E8E8E),
                          size: 32,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoGrid() {
    if (_videoMessages.isEmpty) {
      return _buildEmptyState(
        icon: EvaIcons.video,
        message: 'Нет видео',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1, // Квадратные элементы
      ),
      itemCount: _videoMessages.length,
      itemBuilder: (context, index) {
        final message = _videoMessages[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (message.mediaUrl != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FullScreenVideoViewer(
                      videoUrl: message.mediaUrl!,
                      chatId: widget.chat.id,
                      thumbnailUrl: message.thumbnailUrl,
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (message.thumbnailUrl != null)
                      CachedNetworkImage(
                        imageUrl: message.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0095F6),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            EvaIcons.video,
                            color: Color(0xFF8E8E8E),
                            size: 32,
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: Icon(
                          EvaIcons.video,
                          color: Color(0xFF8E8E8E),
                          size: 32,
                        ),
                      ),
                    // Gradient overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.3),
                            ],
                            stops: const [0.6, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Play icon overlay
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          EvaIcons.playCircleOutline,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    // Duration badge
                    if (message.mediaDuration != null)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 0.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Text(
                            _formatDuration(message.mediaDuration!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceList() {
    if (_voiceMessages.isEmpty) {
      return _buildEmptyState(
        icon: EvaIcons.mic,
        message: 'Нет голосовых сообщений',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _voiceMessages.length,
      itemBuilder: (context, index) {
        final message = _voiceMessages[index];
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUserId = authProvider.currentUser?.id;
        final isOwnMessage = message.senderId == currentUserId;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF262626),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF3A3A3A),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SafeAvatar(
                    imageUrl: isOwnMessage 
                      ? null 
                      : widget.chat.displayAvatar,
                    radius: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOwnMessage ? 'Вы' : widget.chat.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _formatDate(message.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF8E8E8E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (message.mediaUrl != null)
                VoiceMessagePlayer(
                  audioUrl: message.mediaUrl,
                  chatId: widget.chat.id,
                  duration: message.mediaDuration ?? 0,
                  isOwnMessage: isOwnMessage,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLinkList() {
    if (_linkMessages.isEmpty) {
      return _buildEmptyState(
        icon: EvaIcons.link2,
        message: 'Нет ссылок',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _linkMessages.length,
      itemBuilder: (context, index) {
        final message = _linkMessages[index];
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUserId = authProvider.currentUser?.id;
        final isOwnMessage = message.senderId == currentUserId;
        
        // Извлекаем URL из текста
        final RegExp urlRegex = RegExp(
          r'https?://[^\s]+',
          caseSensitive: false,
        );
        final match = urlRegex.firstMatch(message.content ?? '');
        final url = match?.group(0) ?? '';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF262626),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF3A3A3A),
              width: 0.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                if (url.isNotEmpty) {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      AppNotification.showError(context, 'Failed to open link');
                    }
                  }
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SafeAvatar(
                          imageUrl: isOwnMessage 
                            ? null 
                            : widget.chat.displayAvatar,
                          radius: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isOwnMessage ? 'Вы' : widget.chat.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _formatDate(message.createdAt),
                          style: const TextStyle(
                            color: Color(0xFF8E8E8E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          EvaIcons.link2,
                          color: Color(0xFF0095F6),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            url,
                            style: const TextStyle(
                              color: Color(0xFF0095F6),
                              fontSize: 14,
                              decoration: TextDecoration.underline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (message.content != null && message.content != url)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          message.content!.replaceAll(url, '').trim(),
                          style: const TextStyle(
                            color: Color(0xFFE0E0E0),
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostGrid() {
    if (_postMessages.isEmpty) {
      return _buildEmptyState(
        icon: EvaIcons.gridOutline,
        message: 'Нет постов',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1, // Квадратные элементы
      ),
      itemCount: _postMessages.length,
      itemBuilder: (context, index) {
        final message = _postMessages[index];
        final post = message.postId != null ? _postsCache[message.postId!] : null;
        
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              if (message.postId != null) {
                // Загружаем пост, если его еще нет в кеше
                Post? postToShow = _postsCache[message.postId!];
                if (postToShow == null) {
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    final accessToken = prefs.getString('access_token');
                    if (accessToken != null) {
                      _apiService.setAccessToken(accessToken);
                      postToShow = await _apiService.getPost(message.postId!);
                      setState(() {
                        _postsCache[message.postId!] = postToShow!;
                      });
                    }
                  } catch (e) {
                    print('Error loading post: $e');
                    return;
                  }
                }
                
                if (postToShow != null && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostDetailScreen(
                        initialPostId: postToShow!.id,
                        initialPosts: [postToShow],
                      ),
                    ),
                  );
                }
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: post != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Превью медиа поста
                          if (post.thumbnailUrl != null)
                            CachedNetworkImage(
                              imageUrl: post.thumbnailUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[800],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF0095F6),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => _buildPostPlaceholder(post),
                            )
                          else if (post.mediaType == 'image')
                            CachedNetworkImage(
                              imageUrl: post.mediaUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[800],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF0095F6),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => _buildPostPlaceholder(post),
                            )
                          else
                            _buildPostPlaceholder(post),
                          // Иконка типа медиа
                          if (post.mediaType == 'video')
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  EvaIcons.video,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                        ],
                      )
                    : _buildPostPlaceholder(null),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostPlaceholder(Post? post) {
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Icon(
          post?.mediaType == 'video' ? EvaIcons.video : EvaIcons.gridOutline,
          color: const Color(0xFF8E8E8E),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: const Color(0xFF8E8E8E),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF8E8E8E),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн. назад';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}

// Делегат для закрепления TabBar

