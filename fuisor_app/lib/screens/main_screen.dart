import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'create_post_screen.dart';
import 'media_selection_screen.dart';
import 'shorts_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<ShortsScreenState> _shortsScreenKey = GlobalKey<ShortsScreenState>();
  DateTime? _lastShortsTapTime;
  static const _doubleTapDelay = Duration(milliseconds: 300);

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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Color(0xFF262626),
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
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

            if (index == 2) {
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
          backgroundColor: const Color(0xFF000000),
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
        ),
      ),
    );
  }
}
