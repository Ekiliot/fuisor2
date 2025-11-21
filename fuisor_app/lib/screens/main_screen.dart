import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'dart:ui';
import 'home_screen.dart';
import 'search_screen.dart';
import 'create_post_screen.dart';
import 'media_selection_screen.dart';
import 'shorts_screen.dart';
import 'profile_screen.dart';
import '../models/user.dart' show Post;

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
  
  // Глобальный ключ для доступа к MainScreenState из других экранов
  static final GlobalKey<MainScreenState> globalKey = GlobalKey<MainScreenState>();
}

class MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<ShortsScreenState> _shortsScreenKey = GlobalKey<ShortsScreenState>();
  DateTime? _lastShortsTapTime;
  DateTime? _lastSearchTapTime;
  static const _doubleTapDelay = Duration(milliseconds: 300);
  
  @override
  void initState() {
    super.initState();
  }
  
  // Метод для переключения на Shorts с конкретным постом
  void switchToShortsWithPost(Post post) {
    setState(() {
      _currentIndex = 3; // Переключаемся на Shorts
    });
    // Передаем пост в ShortsScreen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortsScreenKey.currentState?.navigateToPost(post);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomeScreen(),
          const SearchScreen(),
          const CreatePostScreen(),
          ShortsScreen(key: _shortsScreenKey), // Используем ключ для доступа к состоянию
          const ProfileScreen(),
        ],
      ),
      extendBody: _currentIndex != 3, // Контент заезжает под navbar, кроме Shorts
      bottomNavigationBar: RepaintBoundary(
        child: ClipRect(
          child: _currentIndex == 3
              ? Container(
                  // Без blur для Shorts, чтобы не перекрывать видео
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: _buildBottomNavigationBar(),
                )
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4), // Оптимизированный blur
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withOpacity(0.1),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: _buildBottomNavigationBar(),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      backgroundColor: Colors.transparent,
      onTap: (index) async {
            // Если уходим с экрана Shorts (index 3), останавливаем все видео
            if (_currentIndex == 3 && index != 3) {
              await _shortsScreenKey.currentState?.pauseAllVideos();
            }

            // Если возвращаемся на Shorts, возобновляем видео
            if (_currentIndex != 3 && index == 3) {
              setState(() {
                _currentIndex = index;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _shortsScreenKey.currentState?.initializeScreen();
              });
              return;
            }

            if (index == 1) {
              // Кнопка поиска - проверяем двойное нажатие
              final now = DateTime.now();
              if (_lastSearchTapTime != null &&
                  now.difference(_lastSearchTapTime!) < _doubleTapDelay &&
                  _currentIndex == 1) {
                // Двойное нажатие на уже открытом экране поиска - ничего не делаем
                return;
              } else {
                // Обычное нажатие - переключаемся на поиск
                setState(() {
                  _currentIndex = index;
                });
              }
              _lastSearchTapTime = now;
            } else if (index == 2) {
              // Кнопка создания поста - открываем MediaSelectionScreen
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const MediaSelectionScreen(),
                ),
              );
            } else if (index == 3) {
              // Кнопка Shorts - проверяем двойное нажатие
              final now = DateTime.now();
              if (_lastShortsTapTime != null &&
                  now.difference(_lastShortsTapTime!) < _doubleTapDelay &&
                  _currentIndex == 3) {
                // Двойное нажатие на уже открытом экране Shorts - обновляем
                _shortsScreenKey.currentState?.refreshFeed();
              } else {
                // Обычное нажатие - переключаемся на Shorts
                setState(() {
                  _currentIndex = index;
                });
                // Инициализируем экран Shorts при первом открытии
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _shortsScreenKey.currentState?.initializeScreen();
                });
              }
              _lastShortsTapTime = now;
            } else {
              setState(() {
                _currentIndex = index;
              });
            }
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.white,
          unselectedItemColor: const Color(0xFF8E8E8E),
          selectedFontSize: 0,
          unselectedFontSize: 0,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(EvaIcons.homeOutline, size: 28),
              activeIcon: Icon(EvaIcons.home, size: 28),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(EvaIcons.searchOutline, size: 28),
              activeIcon: Icon(EvaIcons.search, size: 28),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(EvaIcons.plusSquareOutline, size: 28),
              activeIcon: Icon(EvaIcons.plusSquare, size: 28),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(EvaIcons.videoOutline, size: 28),
              activeIcon: Icon(EvaIcons.video, size: 28),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(EvaIcons.personOutline, size: 28),
              activeIcon: Icon(EvaIcons.person, size: 28),
              label: '',
            ),
          ],
    );
  }
}
