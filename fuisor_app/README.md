# 📱 Fuisor Flutter App

Instagram-like social media mobile application built with Flutter.

## 🚀 Features

### ✅ **Implemented**
- **🔐 Authentication**: Login/Signup with email or username
- **📱 Instagram-like UI**: Clean, modern interface
- **🏠 Home Feed**: View posts from followed users
- **👤 User Profiles**: View user information and stats
- **📸 Post Cards**: Display posts with media, likes, and comments
- **💬 Comments System**: View and add comments
- **❤️ Like System**: Like/unlike posts
- **📖 Stories Widget**: Instagram-style stories section
- **🔍 Search Screen**: Search functionality (UI ready)
- **➕ Create Post**: Post creation interface (UI ready)
- **🔔 Activity**: Notifications screen (UI ready)

### 🚧 **In Development**
- **📷 Camera Integration**: Take photos and videos
- **📁 Media Upload**: Upload images and videos
- **👥 User Following**: Follow/unfollow users
- **#️⃣ Hashtags**: Hashtag support
- **👤 User Mentions**: Tag users in posts
- **💬 Comment Replies**: Nested comments
- **🔔 Push Notifications**: Real-time notifications

## 🛠️ Tech Stack

- **Framework**: Flutter 3.9.2+
- **State Management**: Provider
- **HTTP Client**: http package
- **Image Handling**: cached_network_image, image_picker
- **Navigation**: Material Navigation
- **Storage**: shared_preferences
- **Video**: video_player
- **Icons**: font_awesome_flutter
- **Animations**: flutter_staggered_animations

## 📦 Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^1.1.0
  provider: ^6.1.1
  cached_network_image: ^3.3.0
  image_picker: ^1.0.4
  go_router: ^12.1.3
  shared_preferences: ^2.2.2
  video_player: ^2.8.1
  font_awesome_flutter: ^10.6.0
  flutter_staggered_animations: ^1.1.1
  pull_to_refresh: ^2.0.0
  infinite_scroll_pagination: ^4.0.0
  intl: ^0.19.0
```

## 🏗️ Project Structure

```
lib/
├── models/           # Data models
│   └── user.dart
├── services/         # API services
│   └── api_service.dart
├── providers/        # State management
│   ├── auth_provider.dart
│   └── posts_provider.dart
├── screens/          # UI screens
│   ├── login_screen.dart
│   ├── signup_screen.dart
│   ├── main_screen.dart
│   ├── home_screen.dart
│   ├── search_screen.dart
│   ├── create_post_screen.dart
│   ├── activity_screen.dart
│   └── profile_screen.dart
├── widgets/          # Reusable widgets
│   ├── post_card.dart
│   └── stories_widget.dart
└── main.dart         # App entry point
```

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.9.2 or higher
- Dart SDK
- Android Studio / VS Code
- Backend API deployed at `https://fuisor2.vercel.app` (or local development server)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd fuisor_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

## 📱 Screenshots

### Login Screen
- Clean, Instagram-inspired design
- Email/Username login support
- Form validation
- Error handling

### Home Feed
- Instagram-like post cards
- Stories section
- Pull-to-refresh
- Infinite scroll
- Like and comment functionality

### Profile Screen
- User stats (posts, followers, following)
- Profile picture
- Bio section
- Logout functionality

## 🔌 API Integration

The app connects to the Fuisor backend API:

- **Production Base URL**: `https://fuisor2.vercel.app/api`
- **Local Development**: `http://localhost:3000/api` (configure in `lib/services/api_service.dart`)
- **Authentication**: JWT tokens
- **Endpoints**: All REST API endpoints supported

### Key API Features Used:
- ✅ User authentication (login/signup)
- ✅ Posts feed
- ✅ User profiles
- ✅ Comments system
- ✅ Like system
- ✅ Media support

## 🎨 UI/UX Features

### Design Principles
- **Instagram-inspired**: Clean, modern interface
- **Responsive**: Works on all screen sizes
- **Intuitive**: Familiar navigation patterns
- **Fast**: Optimized performance

### Key UI Components
- **Post Cards**: Instagram-style post display
- **Stories**: Circular story indicators
- **Bottom Navigation**: 5-tab navigation
- **Pull-to-Refresh**: Native refresh behavior
- **Loading States**: Smooth loading indicators

## 🔧 Development

### Running in Debug Mode
```bash
flutter run --debug
```

### Building for Release
```bash
flutter build apk --release
```

### Hot Reload
- Press `r` in terminal
- Or use IDE hot reload button

## 📋 TODO

### High Priority
- [ ] Implement camera integration
- [ ] Add media upload functionality
- [ ] Implement user following system
- [ ] Add hashtag support
- [ ] Implement user mentions

### Medium Priority
- [ ] Add push notifications
- [ ] Implement comment replies
- [ ] Add post editing
- [ ] Add user search
- [ ] Implement stories functionality

### Low Priority
- [ ] Add dark mode
- [ ] Implement offline support
- [ ] Add analytics
- [ ] Performance optimizations

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## 🎯 Status

**Current Status**: 🟡 **In Development**

- ✅ **UI Complete**: All screens designed
- ✅ **Authentication**: Login/Signup working
- ✅ **API Integration**: Connected to backend
- 🚧 **Core Features**: In development
- 📱 **Ready for Testing**: Basic functionality works

**The app is ready for basic testing and can be run immediately!** 🚀