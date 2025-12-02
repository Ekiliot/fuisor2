import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/user.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ApiService {
  // Локальный API URL
  // Для веб-версии и iOS симулятора: 'http://localhost:3000/api'
  // Для Android эмулятора: 'http://10.0.2.2:3000/api'
  // Для реального устройства: 'http://192.168.X.X:3000/api' (замените X.X на IP вашего ПК)
  // Production API URL (Vercel): 'https://fuisor2.vercel.app/api'
  static const String baseUrl = 'https://fuisor2.vercel.app/api';
  String? _accessToken;

  void setAccessToken(String? token) {
    print('ApiService: Setting access token: ${token != null ? "Present (${token.substring(0, 20)}...)" : "Cleared"}');
    _accessToken = token;
  }

  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  // Auth endpoints
  Future<AuthResponse> login(String emailOrUsername, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: _headers,
        body: jsonEncode({
          'email_or_username': emailOrUsername,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AuthResponse.fromJson(data);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Login failed');
      }
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Invalid response format from server');
      }
      rethrow;
    }
  }

  Future<bool> checkUsernameAvailability(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/check-username?username=$username'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['available'] ?? false;
      } else {
        // Если endpoint не существует, возвращаем true (не блокируем)
        return true;
      }
    } catch (e) {
      // В случае ошибки возвращаем true, чтобы не блокировать регистрацию
      return true;
    }
  }

  Future<bool> checkEmailAvailability(String email) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/check-email?email=${Uri.encodeComponent(email)}'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['available'] ?? false;
      } else {
        // Если endpoint не существует, возвращаем true (не блокируем)
        return true;
      }
    } catch (e) {
      // В случае ошибки возвращаем true, чтобы не блокировать регистрацию
      return true;
    }
  }

  Future<void> signup(String email, String password, String username, String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'username': username,
        'name': name,
      }),
    );

    if (response.statusCode != 201) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? error['message'] ?? 'Signup failed');
    }
  }

  Future<void> logout() async {
    await http.post(
      Uri.parse('$baseUrl/auth/logout'),
      headers: _headers,
    );
    _accessToken = null;
  }

  // Password change endpoints
  Future<void> requestPasswordChangeOTP() async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password/request-otp'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? error['message'] ?? 'Failed to request OTP');
    }
  }

  Future<void> changePassword(String otpCode, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password/change'),
      headers: _headers,
      body: jsonEncode({
        'otp_code': otpCode,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode == 200) {
      return;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? error['message'] ?? 'Failed to change password');
    }
  }

  // Posts endpoints
  Future<List<Post>> getPosts({int page = 1, int limit = 10}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts?page=$page&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['posts'] as List)
          .map((post) => Post.fromJson(post))
          .toList();
    } else {
      throw Exception('Failed to load posts');
    }
  }

  Future<List<Post>> getFeed({int page = 1, int limit = 10}) async {
    print('ApiService: Getting feed...');
    print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');
    print('ApiService: Headers: $_headers');
    
    final response = await http.get(
      Uri.parse('$baseUrl/posts/feed?page=$page&limit=$limit'),
      headers: _headers,
    );

    print('ApiService: Feed response status: ${response.statusCode}');
    print('ApiService: Feed response body: ${response.body}');

    // Проверяем ошибки аутентификации
    if (response.statusCode == 401 || response.statusCode == 403) {
      print('ApiService: Authentication error in feed request');
      await _handleAuthError(response);
      throw Exception('Authentication failed - token may be expired');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['posts'] as List)
          .map((post) => Post.fromJson(post))
          .toList();
    } else {
      throw Exception('Failed to load feed');
    }
  }

  Future<List<Post>> getVideoPosts({int page = 1, int limit = 10}) async {
    print('ApiService: Getting video posts...');
    print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');
    
    final response = await http.get(
      Uri.parse('$baseUrl/posts/feed?page=$page&limit=$limit&media_type=video'),
      headers: _headers,
    );

    print('ApiService: Video posts response status: ${response.statusCode}');

    // Проверяем ошибки аутентификации
    if (response.statusCode == 401 || response.statusCode == 403) {
      print('ApiService: Authentication error in video posts request');
      await _handleAuthError(response);
      throw Exception('Authentication failed - token may be expired');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Сервер теперь фильтрует по media_type, поэтому все посты уже видео
      final videoPosts = (data['posts'] as List)
          .map((post) => Post.fromJson(post))
          .toList();
      print('ApiService: Loaded ${videoPosts.length} video posts (recommendations)');
      return videoPosts;
    } else {
      throw Exception('Failed to load video posts');
    }
  }

  Future<List<Post>> getFollowingVideoPosts({int page = 1, int limit = 10}) async {
    print('ApiService: Getting following video posts...');
    print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');
    
    // Для подписок передаем media_type=video и following_only=true
    final response = await http.get(
      Uri.parse('$baseUrl/posts/feed?page=$page&limit=$limit&media_type=video&following_only=true'),
      headers: _headers,
    );

    print('ApiService: Following video posts response status: ${response.statusCode}');

    // Проверяем ошибки аутентификации
    if (response.statusCode == 401 || response.statusCode == 403) {
      print('ApiService: Authentication error in following video posts request');
      await _handleAuthError(response);
      throw Exception('Authentication failed - token may be expired');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Сервер теперь фильтрует по media_type, поэтому все посты уже видео
      final videoPosts = (data['posts'] as List)
          .map((post) => Post.fromJson(post))
          .toList();
      print('ApiService: Loaded ${videoPosts.length} following video posts');
      return videoPosts;
    } else {
      throw Exception('Failed to load following video posts');
    }
  }

  Future<Post> getPost(String postId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return Post.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load post');
    }
  }


  Future<Map<String, dynamic>> likePost(String postId) async {
    print('ApiService: Liking post $postId');
    print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');
    print('ApiService: Request URL: $baseUrl/posts/$postId/like');
    print('ApiService: Request headers: $_headers');
    
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/like'),
      headers: _headers,
    );

    print('ApiService: Like post response status: ${response.statusCode}');
    print('ApiService: Like post response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('ApiService: Post liked/unliked successfully: ${data['message']}');
      print('ApiService: Updated isLiked: ${data['isLiked']}');
      print('ApiService: Updated likesCount: ${data['likesCount']}');
      return {
        'isLiked': data['isLiked'] ?? false,
        'likesCount': data['likesCount'] ?? 0,
      };
    } else {
      final error = jsonDecode(response.body);
      print('ApiService: Error liking post: ${error['error'] ?? error['message']}');
      throw Exception(error['error'] ?? error['message'] ?? 'Failed to like post');
    }
  }

  Future<void> deletePost(String postId) async {
    print('ApiService: Deleting post $postId');
    print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');
    
    final response = await http.delete(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers,
    );

    print('ApiService: Delete post response status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('ApiService: Post deleted successfully: ${data['message']}');
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? error['message'] ?? 'Failed to delete post');
    }
  }

  Future<bool> savePost(String postId) async {
    print('ApiService: Saving post $postId');
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/save'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['saved'] ?? true;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? error['message'] ?? 'Failed to save post');
    }
  }

  Future<bool> unsavePost(String postId) async {
    print('ApiService: Unsaving post $postId');
    final response = await http.delete(
      Uri.parse('$baseUrl/posts/$postId/save'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['saved'] ?? false;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? error['message'] ?? 'Failed to unsave post');
    }
  }

  Future<Map<String, dynamic>> getSavedPosts({int page = 1, int limit = 20}) async {
    try {
      final url = '$baseUrl/users/me/saved?page=$page&limit=$limit';
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to load saved posts');
      }
    } catch (e) {
      throw Exception('Failed to load saved posts: $e');
    }
  }

  Future<Map<String, dynamic>> getLikedPosts({int page = 1, int limit = 20}) async {
    try {
      final url = '$baseUrl/users/me/liked?page=$page&limit=$limit';
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to load liked posts');
      }
    } catch (e) {
      throw Exception('Failed to load liked posts: $e');
    }
  }

  // Comment likes endpoints
  Future<Map<String, dynamic>> likeComment(String postId, String commentId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId/like'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to like comment');
    }
  }

  Future<Map<String, dynamic>> dislikeComment(String postId, String commentId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId/dislike'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to dislike comment');
    }
  }

  Future<Map<String, dynamic>> getComments(String postId, {int page = 1, int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts/$postId/comments?page=$page&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'comments': (data['comments'] as List)
            .map((json) => Comment.fromJson(json))
            .toList(),
        'total': data['total'],
        'page': data['page'],
        'totalPages': data['totalPages'],
      };
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to load comments');
    }
  }

  Future<Comment> addComment(String postId, String content, {String? parentCommentId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments'),
      headers: _headers,
      body: jsonEncode({
        'content': content,
        if (parentCommentId != null) 'parent_comment_id': parentCommentId,
      }),
    );

    if (response.statusCode == 201) {
      return Comment.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to add comment');
    }
  }

  Future<Comment> updateComment(String postId, String commentId, String content) async {
    final response = await http.put(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId'),
      headers: _headers,
      body: jsonEncode({
        'content': content,
      }),
    );

    if (response.statusCode == 200) {
      return Comment.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? error['message'] ?? 'Failed to update comment');
    }
  }

  Future<void> deleteComment(String postId, String commentId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/posts/$postId/comments/$commentId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete comment');
    }
  }

  // User endpoints
  Future<User> getUser(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load user');
    }
  }

  Future<User> getUserByUsername(String username) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/username/$username'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load user by username');
    }
  }

  Future<List<Post>> getUserPosts(String userId, {int page = 1, int limit = 10}) async {
    print('ApiService: Getting user posts for userId: $userId');
    print('ApiService: Page: $page, Limit: $limit');
    print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');
    
    final url = '$baseUrl/users/$userId/posts?page=$page&limit=$limit';
    print('ApiService: URL: $url');
    
    final response = await http.get(
      Uri.parse(url),
      headers: _headers,
    );

    print('ApiService: User posts response status: ${response.statusCode}');
    print('ApiService: User posts response body: ${response.body}');

    // Проверяем ошибки аутентификации
    if (response.statusCode == 401 || response.statusCode == 403) {
      print('ApiService: Authentication error in user posts request');
      await _handleAuthError(response);
      throw Exception('Authentication failed - token may be expired');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final posts = (data['posts'] as List)
          .map((post) => Post.fromJson(post))
          .toList();
      print('ApiService: Loaded ${posts.length} user posts');
      return posts;
    } else {
      print('ApiService: Error loading user posts: ${response.statusCode}');
      throw Exception('Failed to load user posts');
    }
  }

  // Hashtag endpoints
  Future<List<Post>> getPostsByHashtag(String hashtag, {int page = 1, int limit = 10}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts/hashtag/$hashtag?page=$page&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['posts'] as List)
          .map((post) => Post.fromJson(post))
          .toList();
    } else {
      throw Exception('Failed to load hashtag posts');
    }
  }

  Future<Map<String, dynamic>> getHashtagInfo(String hashtag) async {
    try {
      print('ApiService: Getting hashtag info for: #$hashtag');
      
      final response = await http.get(
        Uri.parse('$baseUrl/hashtags/$hashtag'),
        headers: _headers,
      );

      print('ApiService: Hashtag info response status: ${response.statusCode}');
      print('ApiService: Hashtag info response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('ApiService: Hashtag info loaded successfully');
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to load hashtag info');
      }
    } catch (e) {
      print('ApiService: Exception: $e');
      throw Exception('Failed to load hashtag info: $e');
    }
  }

  // Mentions endpoints
  Future<List<Post>> getMentionedPosts({int page = 1, int limit = 10}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/posts/mentions?page=$page&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['posts'] as List)
          .map((post) => Post.fromJson(post))
          .toList();
    } else {
      throw Exception('Failed to load mentioned posts');
    }
  }

  // Update user profile
  Future<User> updateProfile({
    String? name,
    String? username,
    String? bio,
    String? websiteUrl,
    Uint8List? avatarBytes,
    String? avatarFileName,
  }) async {
    try {
      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/users/profile'),
      );

      // Add headers
      request.headers.addAll(_headers);

      // Add text fields
      if (name != null && name.isNotEmpty) request.fields['name'] = name;
      if (username != null && username.isNotEmpty) request.fields['username'] = username;
      if (bio != null) request.fields['bio'] = bio; // Allow empty bio
      if (websiteUrl != null) request.fields['website_url'] = websiteUrl; // Allow empty website_url

      // Add avatar file if provided
      if (avatarBytes != null && avatarFileName != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'avatar',
            avatarBytes,
            filename: avatarFileName,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Profile update response status: ${response.statusCode}');
      print('Profile update response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Parsed response data: $responseData');
        return User.fromJson(responseData);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to update profile');
      }
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  // Получить текущего пользователя
  Future<User> getCurrentUser() async {
    print('ApiService: Getting current user...');
    print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');
    print('ApiService: Headers: $_headers');
    
    final response = await http.get(
      Uri.parse('$baseUrl/users/profile'),
      headers: _headers,
    );

    print('ApiService: Current user response status: ${response.statusCode}');
    print('ApiService: Current user response body: ${response.body}');

    // Проверяем ошибки аутентификации
    if (response.statusCode == 401 || response.statusCode == 403) {
      print('ApiService: Authentication error in getCurrentUser request');
      await _handleAuthError(response);
      throw Exception('Authentication failed - token may be expired');
    }

    if (response.statusCode == 200) {
      final userData = jsonDecode(response.body);
      print('ApiService: Current user loaded successfully');
      return User.fromJson(userData);
    } else {
      print('ApiService: Error loading current user: ${response.statusCode}');
      throw Exception('Failed to load current user');
    }
  }

  // Создать новый пост (теперь принимает URL вместо файлов)
  // Upload media file (image or video) through API
  Future<String> uploadMedia({
    required Uint8List fileBytes,
    required String fileName,
    required String mediaType, // 'image' or 'video'
  }) async {
    try {
      print('ApiService: Uploading media through API...');
      print('ApiService: File name: $fileName');
      print('ApiService: File size: ${fileBytes.length} bytes (${(fileBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
      print('ApiService: Media type: $mediaType');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/posts/upload-media'),
      );

      // Add headers
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }

      // Add media type
      request.fields['mediaType'] = mediaType;

      // Determine content type
      String? contentType;
      final fileNameLower = fileName.toLowerCase();
      if (fileNameLower.endsWith('.jpg') || fileNameLower.endsWith('.jpeg')) {
        contentType = 'image/jpeg';
      } else if (fileNameLower.endsWith('.png')) {
          contentType = 'image/png';
        } else if (fileNameLower.endsWith('.gif')) {
          contentType = 'image/gif';
        } else if (fileNameLower.endsWith('.webp')) {
          contentType = 'image/webp';
        } else if (fileNameLower.endsWith('.mp4')) {
          contentType = 'video/mp4';
        } else if (fileNameLower.endsWith('.webm')) {
          contentType = 'video/webm';
      } else if (fileNameLower.endsWith('.mov')) {
          contentType = 'video/quicktime';
        } else if (fileNameLower.endsWith('.avi')) {
          contentType = 'video/x-msvideo';
        }

      // Add file
        request.files.add(
          http.MultipartFile.fromBytes(
            'media',
          fileBytes,
          filename: fileName,
          contentType: contentType != null ? MediaType.parse(contentType) : null,
          ),
        );

      print('ApiService: Sending upload request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('ApiService: Upload response status: ${response.statusCode}');
      print('ApiService: Upload response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final mediaUrl = data['mediaUrl'] as String;
        print('ApiService: Media uploaded successfully, URL: $mediaUrl');
        return mediaUrl;
      } else if (response.statusCode == 413) {
        // Request Entity Too Large - пробрасываем специальное исключение для fallback
        print('ApiService: Upload failed with 413 - file too large for Vercel');
        throw Exception('FILE_TOO_LARGE_FOR_VERCEL');
      } else {
        try {
          final error = jsonDecode(response.body);
          print('ApiService: Upload error: $error');
          throw Exception(error['error'] ?? 'Failed to upload media');
        } catch (jsonError) {
          print('ApiService: Upload error (not JSON): ${response.body}');
          // Проверяем, содержит ли ответ текст об ошибке размера
          if (response.body.toString().contains('Request Entity Too Large') || 
              response.body.toString().contains('FUNCTION_PAYLOAD_TOO_LARGE')) {
            throw Exception('FILE_TOO_LARGE_FOR_VERCEL');
          }
          throw Exception('Failed to upload media: ${response.statusCode}');
        }
      }
    } catch (e, stackTrace) {
      print('ApiService: Exception uploading media: $e');
      print('ApiService: Stack trace: $stackTrace');
      throw Exception('Failed to upload media: $e');
    }
  }

  // Upload thumbnail through API
  Future<String> uploadThumbnail({
    required Uint8List thumbnailBytes,
    required String fileName,
  }) async {
    try {
      print('ApiService: Uploading thumbnail through API...');
      print('ApiService: File name: $fileName');
      print('ApiService: File size: ${thumbnailBytes.length} bytes');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/posts/upload-thumbnail'),
      );

      // Add headers
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }

      // Determine content type (thumbnails are always images)
      String contentType = 'image/jpeg';
      final fileNameLower = fileName.toLowerCase();
      if (fileNameLower.endsWith('.png')) {
        contentType = 'image/png';
      } else if (fileNameLower.endsWith('.webp')) {
        contentType = 'image/webp';
      }

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'thumbnail',
          thumbnailBytes,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );

      print('ApiService: Sending thumbnail upload request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('ApiService: Thumbnail upload response status: ${response.statusCode}');
      print('ApiService: Thumbnail upload response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final thumbnailUrl = data['thumbnailUrl'] as String;
        print('ApiService: Thumbnail uploaded successfully, URL: $thumbnailUrl');
        return thumbnailUrl;
      } else {
        try {
          final error = jsonDecode(response.body);
          print('ApiService: Thumbnail upload error: $error');
          throw Exception(error['error'] ?? 'Failed to upload thumbnail');
        } catch (jsonError) {
          print('ApiService: Thumbnail upload error (not JSON): ${response.body}');
          throw Exception('Failed to upload thumbnail: ${response.statusCode}');
        }
      }
    } catch (e, stackTrace) {
      print('ApiService: Exception uploading thumbnail: $e');
      print('ApiService: Stack trace: $stackTrace');
      throw Exception('Failed to upload thumbnail: $e');
    }
  }

  Future<Post> createPost({
    required String caption,
    required String mediaUrl,
    required String mediaType,
    String? thumbnailUrl,
    List<String>? mentions,
    List<String>? hashtags,
    double? latitude,
    double? longitude,
    String? visibility,
    int? expiresInHours,
  }) async {
    try {
      print('ApiService: Creating post with media URL: $mediaUrl');
      print('ApiService: Media type: $mediaType');
      print('ApiService: Thumbnail URL: ${thumbnailUrl ?? "None"}');
      print('ApiService: Caption: $caption');
      print('ApiService: Visibility: ${visibility ?? "default"}');
      print('ApiService: Expires in hours: ${expiresInHours ?? "none"}');
      print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');

      final requestBody = {
        'caption': caption,
        'media_url': mediaUrl,
        'media_type': mediaType,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        if (mentions != null && mentions.isNotEmpty) 'mentions': mentions,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (visibility != null) 'visibility': visibility,
        if (expiresInHours != null) 'expires_in_hours': expiresInHours,
      };
      
      print('ApiService: Request body: ${jsonEncode(requestBody)}');

      // Теперь отправляем простой JSON запрос с URL
      final response = await http.post(
        Uri.parse('$baseUrl/posts'),
        headers: _headers,
        body: jsonEncode(requestBody),
      );

      print('ApiService: Response status: ${response.statusCode}');
      print('ApiService: Response body: ${response.body}');

      // Обработка ошибки 413 - Request Entity Too Large (теперь не должна возникать)
      if (response.statusCode == 413) {
        print('ApiService: Request too large (413)');
        throw Exception('File size is too large. Please use a smaller video file.');
      }

      if (response.statusCode == 201) {
        try {
        final responseData = jsonDecode(response.body);
        print('ApiService: Post created successfully');
        return Post.fromJson(responseData);
        } catch (e) {
          print('ApiService: Error parsing response JSON: $e');
          throw Exception('Failed to parse server response');
        }
      } else {
        // Пытаемся декодировать как JSON, но если не получается - используем текст ответа
        try {
        final error = jsonDecode(response.body);
        print('ApiService: Error response: $error');
          throw Exception(error['error'] ?? error['message'] ?? 'Failed to create post');
        } catch (jsonError) {
          // Если не JSON, используем текст ответа
          print('ApiService: Error response (not JSON): ${response.body}');
          throw Exception(response.body.isNotEmpty 
              ? response.body 
              : 'Failed to create post (status: ${response.statusCode})');
        }
      }
    } catch (e, stackTrace) {
      print('ApiService: Exception creating post: $e');
      print('ApiService: Exception type: ${e.runtimeType}');
      print('ApiService: Stack trace: $stackTrace');
      throw Exception('Failed to create post: $e');
    }
  }

  Future<Post> updatePost({
    required String postId,
    required String caption,
  }) async {
    try {
      print('ApiService: Updating post $postId...');
      print('ApiService: Access token: ${_accessToken != null ? "Present (${_accessToken!.substring(0, 20)}...)" : "Missing"}');
      
      final response = await http.put(
        Uri.parse('$baseUrl/posts/$postId'),
        headers: _headers,
        body: jsonEncode({
          'caption': caption,
        }),
      );

      print('ApiService: Update response status: ${response.statusCode}');
      print('ApiService: Update response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('ApiService: Post updated successfully');
        return Post.fromJson(responseData);
      } else {
        final error = jsonDecode(response.body);
        print('ApiService: Error response: $error');
        throw Exception(error['error'] ?? 'Failed to update post');
      }
    } catch (e) {
      print('ApiService: Exception: $e');
      throw Exception('Failed to update post: $e');
    }
  }

  // Обработать ошибку аутентификации
  Future<bool> _handleAuthError(http.Response response) async {
    if (response.statusCode == 401 || response.statusCode == 403) {
      print('ApiService: Authentication error detected (${response.statusCode})');
      print('ApiService: Response body: ${response.body}');
      
      // Здесь можно добавить логику обновления токена
      // Пока что просто возвращаем false
      return false;
    }
    return false;
  }

  // Follow/Unfollow endpoints
  Future<void> followUser(String userId) async {
    try {
      print('ApiService: Following user $userId...');
      final response = await http.post(
        Uri.parse('$baseUrl/follow/$userId'),
        headers: _headers,
      );

      print('ApiService: Follow response status: ${response.statusCode}');
      print('ApiService: Follow response body: ${response.body}');

      if (response.statusCode == 201) {
        print('ApiService: User followed successfully');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to follow user');
      }
    } catch (e) {
      print('ApiService: Exception: $e');
      throw Exception('Failed to follow user: $e');
    }
  }

  Future<void> unfollowUser(String userId) async {
    try {
      print('ApiService: Unfollowing user $userId...');
      final response = await http.delete(
        Uri.parse('$baseUrl/follow/$userId'),
        headers: _headers,
      );

      print('ApiService: Unfollow response status: ${response.statusCode}');
      print('ApiService: Unfollow response body: ${response.body}');

      if (response.statusCode == 200) {
        print('ApiService: User unfollowed successfully');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to unfollow user');
      }
    } catch (e) {
      print('ApiService: Exception: $e');
      throw Exception('Failed to unfollow user: $e');
    }
  }

  Future<bool> checkFollowStatus(String userId) async {
    try {
      print('ApiService: Checking follow status for user $userId...');
      final response = await http.get(
        Uri.parse('$baseUrl/follow/status/$userId'),
        headers: _headers,
      );

      print('ApiService: Follow status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['isFollowing'] ?? false;
      } else {
        throw Exception('Failed to check follow status');
      }
    } catch (e) {
      print('ApiService: Exception: $e');
      throw Exception('Failed to check follow status: $e');
    }
  }

  Future<Map<String, dynamic>> getFollowers(String userId, {int page = 1, int limit = 20}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/follow/followers/$userId?page=$page&limit=$limit'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load followers');
      }
    } catch (e) {
      throw Exception('Failed to load followers: $e');
    }
  }

  Future<Map<String, dynamic>> getFollowing(String userId, {int page = 1, int limit = 20}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/follow/following/$userId?page=$page&limit=$limit'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load following');
      }
    } catch (e) {
      throw Exception('Failed to load following: $e');
    }
  }

  // Notifications endpoints
  Future<Map<String, dynamic>> getNotifications({int page = 1, int limit = 20}) async {
    try {
      print('ApiService: Getting notifications (page $page)...');
      final response = await http.get(
        Uri.parse('$baseUrl/notifications?page=$page&limit=$limit'),
        headers: _headers,
      );

      print('ApiService: Notifications response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to load notifications');
      }
    } catch (e) {
      print('ApiService: Exception: $e');
      throw Exception('Failed to load notifications: $e');
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/notifications/$notificationId/read'),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark notification as read');
      }
    } catch (e) {
      throw Exception('Failed to mark notification as read: $e');
    }
  }

  Future<void> markAllNotificationsAsRead() async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/notifications/read-all'),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark all notifications as read');
      }
    } catch (e) {
      throw Exception('Failed to mark all notifications as read: $e');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/notifications/$notificationId'),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete notification');
      }
    } catch (e) {
      throw Exception('Failed to delete notification: $e');
    }
  }

  // Search endpoints
  Future<Map<String, dynamic>> search(String query, {String type = 'all', int page = 1, int limit = 20}) async {
    try {
      print('ApiService: Searching for "$query" (type: $type)...');
      print('ApiService: Access token: ${_accessToken != null ? "Present" : "Missing"}');
      
      final url = '$baseUrl/search?q=${Uri.encodeComponent(query)}&type=$type&page=$page&limit=$limit';
      print('ApiService: Search URL: $url');
      print('ApiService: Headers: $_headers');
      
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      print('ApiService: Search response status: ${response.statusCode}');
      final previewLen = response.body.length < 200 ? response.body.length : 200;
      print('ApiService: Search response body: ${response.body.substring(0, previewLen)}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to search');
      }
    } catch (e) {
      print('ApiService: Exception: $e');
      throw Exception('Failed to search: $e');
    }
  }

  Future<List<User>> searchUsers(String query, {int limit = 20}) async {
    try {
      final url = '$baseUrl/search/users?q=${Uri.encodeComponent(query)}&limit=$limit';
      print('ApiService: Search users URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> usersData = data['users'] ?? [];
        return usersData.map((json) => User.fromJson(json)).toList();
      } else {
        throw Exception('Failed to search users');
      }
    } catch (e) {
      throw Exception('Failed to search users: $e');
    }
  }

  // ==============================================
  // Direct Messages endpoints
  // ==============================================

  /// Получить все чаты текущего пользователя
  Future<List<Chat>> getChats({bool includeArchived = false}) async {
    try {
      final uri = includeArchived 
          ? Uri.parse('$baseUrl/messages/chats?includeArchived=true')
          : Uri.parse('$baseUrl/messages/chats');
      
      final response = await http.get(
        uri,
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> chatsData = data['chats'] ?? [];
        return chatsData.map((json) => Chat.fromJson(json)).toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to load chats');
      }
    } catch (e) {
      throw Exception('Failed to load chats: $e');
    }
  }

  /// Архивировать/разархивировать чат
  Future<bool> pinChat(String chatId, bool isPinned) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/messages/chats/$chatId/pin'),
        headers: _headers,
        body: jsonEncode({ 'isPinned': isPinned }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('ApiService: Failed to pin chat: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('ApiService: Error pinning chat: $e');
      return false;
    }
  }

  Future<bool> archiveChat(String chatId, bool isArchived) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/messages/chats/$chatId/archive'),
        headers: _headers,
        body: jsonEncode({
          'isArchived': isArchived,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['isArchived'] ?? false;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to archive chat');
      }
    } catch (e) {
      throw Exception('Failed to archive chat: $e');
    }
  }

  /// Создать новый прямой чат с пользователем или получить существующий
  Future<Chat> createChat(String otherUserId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/chats'),
        headers: _headers,
        body: jsonEncode({
          'otherUserId': otherUserId,
        }),
      );

      // Принимаем и 200 (чат существует) и 201 (чат создан)
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return Chat.fromJson(data['chat']);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to create chat');
      }
    } catch (e) {
      throw Exception('Failed to create chat: $e');
    }
  }

  /// Получить конкретный чат
  Future<Chat> getChat(String chatId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/chats/$chatId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Chat.fromJson(data['chat']);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to load chat');
      }
    } catch (e) {
      throw Exception('Failed to load chat: $e');
    }
  }

  /// Получить сообщения чата
  Future<Map<String, dynamic>> getMessages(String chatId, {int page = 1, int limit = 50}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages?page=$page&limit=$limit'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> messagesData = data['messages'] ?? [];
        final messages = messagesData.map((json) => Message.fromJson(json)).toList();
        return {
          'messages': messages,
          'page': data['page'] ?? page,
          'limit': data['limit'] ?? limit,
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to load messages');
      }
    } catch (e) {
      throw Exception('Failed to load messages: $e');
    }
  }

  /// Отправить сообщение
  Future<Message> sendMessage(String chatId, String content) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages'),
        headers: _headers,
        body: jsonEncode({
          'content': content,
          'messageType': 'text', // Указываем тип сообщения как текст
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return Message.fromJson(data['message']);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to send message');
      }
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  /// Отметить сообщение как прочитанное
  Future<void> markMessageAsRead(String chatId, String messageId) async {
    try {
      print('ApiService: Marking message as read - chatId: ${chatId.substring(0, 8)}..., messageId: ${messageId.substring(0, 8)}...');
      final response = await http.put(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages/$messageId/read'),
        headers: _headers,
      );

      print('ApiService: Mark message as read response - status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        print('ApiService: Error marking message as read: ${error['error']}');
        throw Exception(error['error'] ?? 'Failed to mark message as read');
      }
      
      final responseData = jsonDecode(response.body);
      print('ApiService: Message marked as read successfully - response: $responseData');
    } catch (e) {
      print('ApiService: Exception marking message as read: $e');
      throw Exception('Failed to mark message as read: $e');
    }
  }

  /// Удалить сообщение (soft delete)
  Future<Message> deleteMessage(String chatId, String messageId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages/$messageId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['message'] != null) {
          return Message.fromJson(data['message']);
        }
        throw Exception('Invalid response: message field is missing');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to delete message');
      }
    } catch (e) {
      throw Exception('Failed to delete message: $e');
    }
  }

  // ==============================================
  // ONLINE STATUS
  // ==============================================

  /// Отправить heartbeat для обновления онлайн-статуса
  Future<void> sendHeartbeat() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/heartbeat'),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        print('ApiService: Heartbeat failed - ${response.statusCode}');
      }
    } catch (e) {
      print('ApiService: Heartbeat error: $e');
      // Не выбрасываем исключение, чтобы не прерывать работу приложения
    }
  }

  Future<void> setOfflineStatus() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/set-offline'),
        headers: _headers,
      );
      
      if (response.statusCode != 200) {
        print('ApiService: Set offline failed - ${response.statusCode}');
      } else {
        print('ApiService: User set to offline successfully');
      }
    } catch (e) {
      print('ApiService: Set offline error: $e');
    }
  }

  /// Получить статус пользователя (онлайн/офлайн)
  Future<Map<String, dynamic>> getUserStatus(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId/status'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get user status');
      }
    } catch (e) {
      throw Exception('Failed to get user status: $e');
    }
  }

  /// Обновить настройку приватности онлайн-статуса
  Future<void> updateOnlineStatusSetting(bool showOnlineStatus) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/settings/online-status'),
        headers: _headers,
        body: jsonEncode({'show_online_status': showOnlineStatus}),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to update setting');
      }
    } catch (e) {
      throw Exception('Failed to update online status setting: $e');
    }
  }

  // ==============================================
  // Voice Messages
  // ==============================================

  /// Загрузить голосовое сообщение
  Future<Map<String, dynamic>> uploadVoiceMessage({
    required String chatId,
    required String filePath,
    required int duration,
  }) async {
    try {
      final uploadStartTime = DateTime.now();
      print('📤 [API Upload] Начало загрузки голосового сообщения');
      print('📤 [API Upload] ChatId: $chatId');
      print('📤 [API Upload] Длительность записи: $duration сек');
      print('📤 [API Upload] Путь к файлу: $filePath');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/messages/chats/$chatId/upload'),
      );
      
      request.headers['Authorization'] = 'Bearer $_accessToken';
      request.fields['messageType'] = 'voice';
      request.fields['duration'] = duration.toString();
      
      // Проверяем, blob URL или файловый путь
      if (filePath.startsWith('blob:')) {
        print('📤 [API Upload] Обнаружен blob URL (Web), получение данных...');
        
        // Для веба - получаем данные из blob URL
        final blobResponse = await http.get(Uri.parse(filePath));
        final bytes = blobResponse.bodyBytes;
        
        print('📤 [API Upload] Размер blob: ${bytes.length} байт (${(bytes.length / 1024).toStringAsFixed(2)} KB)');
        
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
          contentType: MediaType('audio', 'mp4'), // M4A использует контейнер MP4
        ));
      } else {
        print('📤 [API Upload] Обнаружен файловый путь (Mobile), использование fromPath');
        
        // Для мобильных - используем fromPath
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: 'voice.m4a',
          contentType: MediaType('audio', 'mp4'), // M4A использует контейнер MP4
        ));
      }

      print('📤 [API Upload] Отправка multipart запроса на $baseUrl/messages/chats/$chatId/upload...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final uploadEndTime = DateTime.now();
      final uploadDuration = uploadEndTime.difference(uploadStartTime).inMilliseconds;

      print('📤 [API Upload] Ответ получен');
      print('📤 [API Upload] Статус ответа: ${response.statusCode}');
      print('📤 [API Upload] Время загрузки: ${uploadDuration}ms (${(uploadDuration / 1000).toStringAsFixed(2)} сек)');
      print('📤 [API Upload] Тело ответа: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('📤 [API Upload] ✅ Загрузка успешна!');
        print('📤 [API Upload] MediaUrl: ${data['mediaUrl']}');
        print('📤 [API Upload] MediaSize: ${data['mediaSize']} байт');
        print('📤 [API Upload] MediaDuration: ${data['mediaDuration']} сек');
        return data;
      } else {
        final error = jsonDecode(response.body);
        print('📤 [API Upload] ❌ ОШИБКА загрузки: ${error['error'] ?? 'Unknown error'}');
        throw Exception(error['error'] ?? 'Failed to upload voice message');
      }
    } catch (e) {
      print('📤 [API Upload] ❌ ИСКЛЮЧЕНИЕ при загрузке: $e');
      throw Exception('Failed to upload voice message: $e');
    }
  }

  /// Отправить видео сообщение (Shorts)
  Future<Message> sendVideoMessage({
    required String chatId,
    required String postId,
    required String mediaUrl,
    required String thumbnailUrl,
  }) async {
    try {
      print('ApiService: Sending video message');
      print('ApiService: ChatId: $chatId');
      print('ApiService: PostId: $postId');
      print('ApiService: MediaUrl: $mediaUrl');
      print('ApiService: ThumbnailUrl: $thumbnailUrl');

      final requestBody = {
        'messageType': 'video',
        'mediaUrl': mediaUrl,
        'thumbnailUrl': thumbnailUrl,
        'postId': postId, // ID поста для открытия в Shorts
      };

      print('ApiService: Request body: ${jsonEncode(requestBody)}');
      print('ApiService: Sending POST to $baseUrl/messages/chats/$chatId/messages...');

      final response = await http.post(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages'),
        headers: _headers,
        body: jsonEncode(requestBody),
      );

      print('ApiService: Response status: ${response.statusCode}');
      print('ApiService: Response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('ApiService: ✅ Video message sent successfully!');
        print('ApiService: Message data: $data');

        final message = Message.fromJson(data['message']);
        print('ApiService: Created Message object');
        return message;
      } else {
        final error = jsonDecode(response.body);
        print('ApiService: ❌ Error sending video message: ${error['error'] ?? 'Unknown error'}');
        throw Exception(error['error'] ?? 'Failed to send video message');
      }
    } catch (e) {
      print('ApiService: ❌ Exception sending video message: $e');
      throw Exception('Failed to send video message: $e');
    }
  }

  /// Отправить голосовое сообщение
  Future<Message> sendVoiceMessage({
    required String chatId,
    required String mediaUrl,
    required int duration,
    required int size,
  }) async {
    try {
      final sendStartTime = DateTime.now();
      print('💬 [API Send] Начало отправки голосового сообщения');
      print('💬 [API Send] ChatId: $chatId');
      print('💬 [API Send] MediaUrl: $mediaUrl');
      print('💬 [API Send] Длительность: $duration сек');
      print('💬 [API Send] Размер файла: $size байт (${(size / 1024).toStringAsFixed(2)} KB)');
      
      final requestBody = {
          'messageType': 'voice',  // бэкенд читает как messageType
          'mediaUrl': mediaUrl,    // бэкенд читает как mediaUrl
          'mediaDuration': duration,  // бэкенд читает как mediaDuration
          'mediaSize': size,       // бэкенд читает как mediaSize
      };
      
      print('💬 [API Send] Тело запроса: ${jsonEncode(requestBody)}');
      print('💬 [API Send] Отправка POST на $baseUrl/messages/chats/$chatId/messages...');
      
      final response = await http.post(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages'),
        headers: _headers,
        body: jsonEncode(requestBody),
      );
      
      final sendEndTime = DateTime.now();
      final sendDuration = sendEndTime.difference(sendStartTime).inMilliseconds;

      print('💬 [API Send] Ответ получен');
      print('💬 [API Send] Статус ответа: ${response.statusCode}');
      print('💬 [API Send] Время отправки: ${sendDuration}ms (${(sendDuration / 1000).toStringAsFixed(2)} сек)');
      print('💬 [API Send] Тело ответа: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('💬 [API Send] ✅ Сообщение успешно отправлено!');
        print('💬 [API Send] Данные ответа: $data');
        
        final message = Message.fromJson(data['message']);
        print('💬 [API Send] Создан объект Message:');
        print('💬 [API Send]   - ID: ${message.id}');
        print('💬 [API Send]   - Тип: ${message.messageType}');
        print('💬 [API Send]   - MediaUrl: ${message.mediaUrl}');
        print('💬 [API Send]   - Длительность: ${message.mediaDuration} сек');
        print('💬 [API Send]   - Размер: ${message.mediaSize} байт');
        print('💬 [API Send]   - Отправитель: ${message.senderId}');
        print('💬 [API Send]   - Время создания: ${message.createdAt}');
        return message;
      } else {
        final error = jsonDecode(response.body);
        print('💬 [API Send] ❌ ОШИБКА отправки: ${error['error'] ?? 'Unknown error'}');
        throw Exception(error['error'] ?? 'Failed to send voice message');
      }
    } catch (e) {
      print('💬 [API Send] ❌ ИСКЛЮЧЕНИЕ при отправке: $e');
      throw Exception('Failed to send voice message: $e');
    }
  }

  /// Получить signed URL для приватного медиа файла
  Future<String> getMediaSignedUrl({
    required String chatId,
    required String mediaPath,
  }) async {
    try {
      print('🔐 [API SignedURL] Запрос signed URL для медиа файла');
      print('🔐 [API SignedURL] ChatId: $chatId');
      print('🔐 [API SignedURL] MediaPath: $mediaPath');
      
      // Передаем путь к файлу как query параметр
      final encodedPath = Uri.encodeQueryComponent(mediaPath);
      final url = '$baseUrl/messages/chats/$chatId/media/signed-url?path=$encodedPath';
      
      print('🔐 [API SignedURL] URL запроса: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      print('🔐 [API SignedURL] Статус ответа: ${response.statusCode}');
      print('🔐 [API SignedURL] Тело ответа: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🔐 [API SignedURL] ✅ Signed URL получен успешно');
        return data['signedUrl'];
      } else {
        final error = jsonDecode(response.body);
        print('🔐 [API SignedURL] ❌ ОШИБКА: ${error['error'] ?? 'Unknown error'}');
        throw Exception(error['error'] ?? 'Failed to get signed URL');
      }
    } catch (e) {
      print('🔐 [API SignedURL] ❌ ИСКЛЮЧЕНИЕ: $e');
      throw Exception('Failed to get signed URL: $e');
    }
  }

  /// Загрузить фото или видео для сообщения
  Future<Map<String, dynamic>> uploadChatMedia({
    required String chatId,
    required String filePath,
    required String messageType, // 'image' or 'video'
  }) async {
    try {
      print('📤 [API Upload] Начало загрузки медиа для сообщения');
      print('📤 [API Upload] ChatId: $chatId');
      print('📤 [API Upload] MessageType: $messageType');
      print('📤 [API Upload] Путь к файлу: $filePath');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/messages/chats/$chatId/upload'),
      );
      
      request.headers['Authorization'] = 'Bearer $_accessToken';
      request.fields['messageType'] = messageType;
      
      // Определяем content type
      String? contentType;
      String fileName;
      if (filePath.startsWith('blob:')) {
        // Для веба - получаем данные из blob URL
        final blobResponse = await http.get(Uri.parse(filePath));
        final bytes = blobResponse.bodyBytes;
        
        // Определяем тип по первым байтам или расширению
        if (messageType == 'image') {
          contentType = 'image/jpeg';
          fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        } else {
          contentType = 'video/mp4';
          fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        }
        
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ));
      } else {
        // Для мобильных - используем fromPath
        final extension = filePath.split('.').last.toLowerCase();
        
        if (messageType == 'image') {
          if (extension == 'png') {
            contentType = 'image/png';
          } else if (extension == 'gif') {
            contentType = 'image/gif';
          } else {
            contentType = 'image/jpeg';
          }
          fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.$extension';
        } else {
          if (extension == 'mov') {
            contentType = 'video/quicktime';
          } else if (extension == 'webm') {
            contentType = 'video/webm';
          } else {
            contentType = 'video/mp4';
          }
          fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.$extension';
        }
        
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ));
      }

      print('📤 [API Upload] Отправка multipart запроса...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📤 [API Upload] Статус ответа: ${response.statusCode}');
      print('📤 [API Upload] Тело ответа: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('📤 [API Upload] ✅ Загрузка успешна!');
        print('📤 [API Upload] MediaUrl: ${data['mediaUrl']}');
        return data;
      } else {
        // Обрабатываем ошибки, которые могут не быть в формате JSON
        String errorMessage = 'Failed to upload media';
        
        if (response.statusCode == 413 || response.statusCode == 507) {
          // Request Entity Too Large или Insufficient Storage
          errorMessage = 'File is too large. Please select a smaller file (max 4.5MB recommended).';
        } else {
          // Пытаемся распарсить JSON ошибку
          try {
            final error = jsonDecode(response.body);
            errorMessage = error['error'] ?? response.body.isNotEmpty ? response.body : errorMessage;
          } catch (e) {
            // Если ответ не JSON, используем текст ответа или стандартное сообщение
            errorMessage = response.body.isNotEmpty ? response.body : 'Failed to upload media (Status: ${response.statusCode})';
          }
        }
        
        print('📤 [API Upload] ❌ ОШИБКА загрузки: $errorMessage');
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('📤 [API Upload] ❌ ИСКЛЮЧЕНИЕ при загрузке: $e');
      throw Exception('Failed to upload media: $e');
    }
  }

  /// Отправить фото сообщение
  Future<Message> sendImageMessage({
    required String chatId,
    required String mediaUrl,
  }) async {
    try {
      print('📷 [API Send] Отправка фото сообщения');
      print('📷 [API Send] ChatId: $chatId');
      print('📷 [API Send] MediaUrl: $mediaUrl');
      
      final requestBody = {
        'messageType': 'image',
        'mediaUrl': mediaUrl,
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages'),
        headers: _headers,
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final message = Message.fromJson(data['message']);
        print('📷 [API Send] ✅ Фото сообщение отправлено успешно!');
        return message;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to send image message');
      }
    } catch (e) {
      print('📷 [API Send] ❌ ИСКЛЮЧЕНИЕ при отправке: $e');
      throw Exception('Failed to send image message: $e');
    }
  }

  /// Отправить видео сообщение (не Shorts, обычное видео)
  Future<Message> sendVideoChatMessage({
    required String chatId,
    required String mediaUrl,
    String? thumbnailUrl,
    int? duration,
    int? size,
  }) async {
    try {
      print('🎥 [API Send] Отправка видео сообщения');
      print('🎥 [API Send] ChatId: $chatId');
      print('🎥 [API Send] MediaUrl: $mediaUrl');
      print('🎥 [API Send] ThumbnailUrl: $thumbnailUrl');
      
      final requestBody = {
        'messageType': 'video',
        'mediaUrl': mediaUrl,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        if (duration != null) 'mediaDuration': duration,
        if (size != null) 'mediaSize': size,
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages'),
        headers: _headers,
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final message = Message.fromJson(data['message']);
        print('🎥 [API Send] ✅ Видео сообщение отправлено успешно!');
        return message;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to send video message');
      }
    } catch (e) {
      print('🎥 [API Send] ❌ ИСКЛЮЧЕНИЕ при отправке: $e');
      throw Exception('Failed to send video message: $e');
    }
  }

  /// Переключить лайк на сообщении
  Future<Message> toggleMessageLike(String chatId, String messageId) async {
    try {
      print('❤️ [API Like] Переключение лайка на сообщении');
      print('❤️ [API Like] ChatId: $chatId');
      print('❤️ [API Like] MessageId: $messageId');
      
      final response = await http.put(
        Uri.parse('$baseUrl/messages/chats/$chatId/messages/$messageId/like'),
        headers: _headers,
      );

      print('❤️ [API Like] Статус ответа: ${response.statusCode}');
      print('❤️ [API Like] Тело ответа: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('❤️ [API Like] Данные ответа: $data');
        
        if (data['message'] == null) {
          print('❤️ [API Like] ❌ ОШИБКА: Поле "message" отсутствует в ответе');
          throw Exception('Invalid response: message field is missing');
        }
        
        final message = Message.fromJson(data['message']);
        print('❤️ [API Like] ✅ Лайк переключен успешно!');
        print('❤️ [API Like] isLiked: ${message.isLiked}');
        return message;
      } else {
        final error = jsonDecode(response.body);
        print('❤️ [API Like] ❌ ОШИБКА: ${error['error'] ?? 'Unknown error'}');
        throw Exception(error['error'] ?? 'Failed to toggle message like');
      }
    } catch (e) {
      print('❤️ [API Like] ❌ ИСКЛЮЧЕНИЕ: $e');
      throw Exception('Failed to toggle message like: $e');
    }
  }

  /// Получить signed URL для приватного медиа файла поста
  /// Получить signed URL для приватного медиа файла поста
  /// Возвращает Map с signedUrl и postId
  Future<Map<String, String?>> getPostMediaSignedUrl({
    required String mediaPath,
    String? postId, // Добавляем опциональный postId
  }) async {
    try {
      print('🔐 [API Post SignedURL] Запрос signed URL для медиа поста');
      print('🔐 [API Post SignedURL] MediaPath: $mediaPath, PostId: $postId');
      
      // Извлекаем имя файла из полного URL или пути
      String fileName;
      if (mediaPath.contains('/')) {
        // Если это полный URL, извлекаем имя файла
        // Формат может быть: https://.../storage/v1/object/public/post-media/post_xxx.mp4
        // или просто путь: post_xxx.mp4
        final parts = mediaPath.split('/');
        fileName = parts.last.split('?').first; // Убираем query параметры если есть
      } else {
        fileName = mediaPath;
      }
      
      print('🔐 [API Post SignedURL] Извлеченное имя файла: $fileName');
      
      final encodedPath = Uri.encodeQueryComponent(fileName);
      String url = '$baseUrl/posts/media/signed-url?path=$encodedPath';
      
      // Добавляем postId если передан
      if (postId != null) {
        url += '&postId=${Uri.encodeQueryComponent(postId)}';
      }
      
      print('🔐 [API Post SignedURL] URL запроса: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );

      print('🔐 [API Post SignedURL] Статус ответа: ${response.statusCode}');
      print('🔐 [API Post SignedURL] Тело ответа: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🔐 [API Post SignedURL] ✅ Signed URL получен успешно');
        return {
          'signedUrl': data['signedUrl'],
          'postId': data['postId'] ?? postId ?? '', // Возвращаем postId из ответа или используем переданный
        };
      } else {
        final error = jsonDecode(response.body);
        print('🔐 [API Post SignedURL] ❌ ОШИБКА: ${error['error'] ?? 'Unknown error'}');
        throw Exception(error['error'] ?? 'Failed to get signed URL');
      }
    } catch (e) {
      print('🔐 [API Post SignedURL] ❌ ИСКЛЮЧЕНИЕ: $e');
      throw Exception('Failed to get signed URL: $e');
    }
  }

  // ==============================================
  // Geolocation endpoints
  // ==============================================

  /// Get geo-posts within map bounds
  Future<List<Post>> getGeoPosts({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/posts/geo/map?swLat=$swLat&swLng=$swLng&neLat=$neLat&neLng=$neLng',
        ),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final posts = (data['posts'] as List)
            .map((json) => Post.fromJson(json))
            .toList();
        return posts;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to get geo posts');
      }
    } catch (e) {
      print('ApiService: Error getting geo posts: $e');
      rethrow;
    }
  }

  /// Get active stories for a specific user
  Future<List<Post>> getUserStories(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/posts/stories/user/$userId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final stories = (data['stories'] as List)
            .map((json) => Post.fromJson(json))
            .toList();
        return stories;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to get user stories');
      }
    } catch (e) {
      print('ApiService: Error getting user stories: $e');
      rethrow;
    }
  }

  /// Get users with active stories from following list
  Future<Map<String, dynamic>> getUsersWithStories() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/posts/stories/users'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final users = (data['users'] as List)
            .map((json) => User.fromJson(json))
            .toList();
        final currentUserHasStories = data['currentUserHasStories'] ?? false;
        
        return {
          'users': users,
          'currentUserHasStories': currentUserHasStories,
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to get users with stories');
      }
    } catch (e) {
      print('ApiService: Error getting users with stories: $e');
      rethrow;
    }
  }

  /// Update user's current location
  Future<void> updateLocation({
    required double latitude,
    required double longitude,
  }) async {
    try {
      print('ApiService: Updating location to $baseUrl/users/location');
      print('ApiService: Latitude: $latitude, Longitude: $longitude');
      print('ApiService: Headers: ${_headers.containsKey('Authorization') ? 'Authorization present' : 'No Authorization'}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/users/location'),
        headers: _headers,
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      print('ApiService: Response status: ${response.statusCode}');
      print('ApiService: Response body: ${response.body}');

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to update location');
      }
      
      print('ApiService: ✅ Location updated successfully');
    } catch (e) {
      print('ApiService: ❌ Error updating location: $e');
      rethrow;
    }
  }

  /// Get friends' locations (only if location sharing is enabled)
  Future<List<Map<String, dynamic>>> getFriendsLocations() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/friends/locations'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['friends'] ?? []);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to get friends locations');
      }
    } catch (e) {
      print('ApiService: Error getting friends locations: $e');
      rethrow;
    }
  }

  /// Toggle location sharing
  Future<void> setLocationSharing(bool enabled) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/location/sharing'),
        headers: _headers,
        body: jsonEncode({
          'enabled': enabled,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to set location sharing');
      }
    } catch (e) {
      print('ApiService: Error setting location sharing: $e');
      rethrow;
    }
  }

  /// Get location visibility setting
  Future<Map<String, dynamic>> getLocationVisibility() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/location/visibility'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to get location visibility');
      }
    } catch (e) {
      print('ApiService: Error getting location visibility: $e');
      rethrow;
    }
  }

  /// Update location visibility setting
  Future<void> updateLocationVisibility(String visibility) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/location/visibility'),
        headers: _headers,
        body: jsonEncode({
          'location_visibility': visibility,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to update location visibility');
      }
    } catch (e) {
      print('ApiService: Error updating location visibility: $e');
      rethrow;
    }
  }

  /// Get close friends list
  Future<List<Map<String, dynamic>>> getCloseFriends() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/close-friends'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['close_friends'] ?? []);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to get close friends');
      }
    } catch (e) {
      print('ApiService: Error getting close friends: $e');
      rethrow;
    }
  }

  /// Add user to close friends
  Future<void> addCloseFriend(String friendId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/close-friends/$friendId'),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to add close friend');
      }
    } catch (e) {
      print('ApiService: Error adding close friend: $e');
      rethrow;
    }
  }

  /// Remove user from close friends
  Future<void> removeCloseFriend(String friendId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/users/close-friends/$friendId'),
        headers: _headers,
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to remove close friend');
      }
    } catch (e) {
      print('ApiService: Error removing close friend: $e');
      rethrow;
    }
  }
}
