import 'package:flutter/material.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import '../screens/camera_screen.dart';

class StoriesWidget extends StatelessWidget {
  const StoriesWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      margin: const EdgeInsets.only(top: 0, bottom: 8), // Stories ближе к header
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: 10, // Mock data without Geo button
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildAddStoryItem(context);
          }
          return _buildStoryItem(index);
        },
      ),
    );
  }

  Widget _buildAddStoryItem(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const CameraScreen(),
          ),
        );
      },
      child: Container(
      width: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Stack(
            children: [
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
                child: const CircleAvatar(
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
          const Text(
            'Your Story',
            style: TextStyle(
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


  Widget _buildStoryItem(int index) {
    return Container(
      width: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
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
              child: const CircleAvatar(
                backgroundColor: Color(0xFF262626),
                child: Icon(
                  EvaIcons.personOutline,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'User $index',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
