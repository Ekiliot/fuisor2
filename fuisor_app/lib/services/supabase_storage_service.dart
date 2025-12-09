import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';

class SupabaseStorageService {
  static String? _supabaseUrl;
  static String? _supabaseAnonKey;
  
  // Security constants
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB максимум
  static const List<String> allowedImageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
  static const List<String> allowedVideoExtensions = ['mp4', 'webm', 'mov', 'avi'];
  static const List<String> allowedMimeTypes = [
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'video/mp4', 'video/webm', 'video/quicktime', 'video/x-msvideo'
  ];
  
  // Получить Supabase credentials из API
  static Future<Map<String, String>> _getSupabaseCredentials() async {
    try {
      // Если уже загружены, возвращаем кеш
      if (_supabaseUrl != null && _supabaseAnonKey != null) {
        return {
          'url': _supabaseUrl!,
          'anonKey': _supabaseAnonKey!,
        };
      }
      
      // Получаем из API
      final response = await http.get(
        Uri.parse('https://fuisor2.vercel.app/api/auth/supabase-config'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _supabaseUrl = data['supabaseUrl'];
        _supabaseAnonKey = data['supabaseAnonKey'];
        
        return {
          'url': _supabaseUrl!,
          'anonKey': _supabaseAnonKey!,
        };
      } else {
        throw Exception('Failed to get Supabase credentials: ${response.statusCode}');
      }
    } catch (e) {
      print('SupabaseStorageService: Error getting credentials: $e');
      throw Exception('Failed to get Supabase credentials: $e');
    }
  }
  
  // Вспомогательные методы для валидации
  static String _sanitizeFileName(String fileName) {
    // Удаляем path traversal и опасные символы
    return fileName
      .replaceAll(RegExp(r'\.\.'), '') // Удаляем ..
      .replaceAll(RegExp(r'[<>:"|?*]'), '') // Удаляем опасные символы
      .replaceAll(RegExp(r'^/'), '') // Удаляем ведущий слеш
      .trim();
  }
  
  static String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }
  
  // Загрузить медиа файл в Supabase Storage используя REST API
  static Future<String> uploadMedia({
    required Uint8List fileBytes,
    required String fileName,
    required String bucketName,
    String? accessToken,
    String? mediaType, // 'image' or 'video' для валидации
  }) async {
    try {
      print('SupabaseStorageService: Uploading file to bucket: $bucketName');
      print('SupabaseStorageService: File name: $fileName');
      print('SupabaseStorageService: File size: ${fileBytes.length} bytes');
      
      // 1. ВАЛИДАЦИЯ РАЗМЕРА
      if (fileBytes.length > maxFileSize) {
        throw Exception('File size (${(fileBytes.length / 1024 / 1024).toStringAsFixed(2)} MB) exceeds maximum allowed size (50 MB)');
      }
      
      // 2. ВАЛИДАЦИЯ ИМЕНИ ФАЙЛА (защита от path traversal)
      final sanitizedFileName = _sanitizeFileName(fileName);
      if (sanitizedFileName != fileName) {
        throw Exception('Invalid file name: contains illegal characters (path traversal detected)');
      }
      
      // 3. ВАЛИДАЦИЯ РАСШИРЕНИЯ
      final fileExt = _getFileExtension(sanitizedFileName);
      final allowedExts = [...allowedImageExtensions, ...allowedVideoExtensions];
      if (fileExt.isEmpty || !allowedExts.contains(fileExt)) {
        throw Exception('File type not allowed. Allowed extensions: ${allowedExts.join(", ")}');
      }
      
      // 4. ВАЛИДАЦИЯ ТИПА МЕДИА (если передан)
      if (mediaType != null) {
        if (mediaType == 'image' && !allowedImageExtensions.contains(fileExt)) {
          throw Exception('File extension ($fileExt) does not match media type (image). Allowed: ${allowedImageExtensions.join(", ")}');
        }
        if (mediaType == 'video' && !allowedVideoExtensions.contains(fileExt)) {
          throw Exception('File extension ($fileExt) does not match media type (video). Allowed: ${allowedVideoExtensions.join(", ")}');
        }
      }
      
      print('SupabaseStorageService: Security validation passed');
      
      final credentials = await _getSupabaseCredentials();
      final supabaseUrl = credentials['url']!;
      final supabaseAnonKey = credentials['anonKey']!;
      
      // Используем REST API Supabase для загрузки
      // Формат: POST /storage/v1/object/{bucket}/{path}
      // URL должен быть закодирован правильно
      // Используем sanitized имя файла для безопасности
      final encodedFileName = Uri.encodeComponent(sanitizedFileName);
      final uploadUrl = '$supabaseUrl/storage/v1/object/$bucketName/$encodedFileName';
      
      print('SupabaseStorageService: Upload URL: $uploadUrl');
      
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      
      // Устанавливаем заголовки для Supabase Storage API
      // Для аутентифицированных пользователей используем access token
      if (accessToken != null) {
        request.headers['Authorization'] = 'Bearer $accessToken';
        request.headers['apikey'] = supabaseAnonKey;
      } else {
        // Для неаутентифицированных используем anon key
        request.headers['Authorization'] = 'Bearer $supabaseAnonKey';
        request.headers['apikey'] = supabaseAnonKey;
      }
      // Не устанавливаем Content-Type - он будет установлен автоматически для multipart
      
      // Определяем content type по расширению файла
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
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: sanitizedFileName, // Используем sanitized имя
          contentType: contentType != null ? MediaType.parse(contentType) : null,
        ),
      );
      
      print('SupabaseStorageService: Sending upload request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('SupabaseStorageService: Response status: ${response.statusCode}');
      print('SupabaseStorageService: Response body: ${response.body}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('SupabaseStorageService: Upload successful');
        
        // Supabase может вернуть путь в ответе, или мы формируем его сами
        String filePath = sanitizedFileName;
        try {
          // Пытаемся получить путь из ответа (если это JSON)
          final responseData = jsonDecode(response.body);
          if (responseData is Map && responseData.containsKey('path')) {
            final returnedPath = responseData['path'] as String;
            // Проверяем что возвращенный путь безопасен
            if (_sanitizeFileName(returnedPath) == returnedPath) {
              filePath = returnedPath;
            }
          } else if (responseData is Map && responseData.containsKey('Key')) {
            final returnedKey = responseData['Key'] as String;
            if (_sanitizeFileName(returnedKey) == returnedKey) {
              filePath = returnedKey;
            }
          } else if (responseData is String && responseData.isNotEmpty) {
            if (_sanitizeFileName(responseData) == responseData) {
              filePath = responseData;
            }
          }
        } catch (e) {
          // Если ответ не JSON, используем sanitized имя файла
          print('SupabaseStorageService: Response is not JSON, using sanitized filename');
        }
        
        // Bucket не публичный, поэтому возвращаем путь к файлу
        // Signed URL будет получен через API при необходимости
        // Формат пути: просто имя файла (например, post_userId_timestamp.mp4)
        print('SupabaseStorageService: File path: $filePath');
        print('SupabaseStorageService: Note - Bucket is private, signed URL must be obtained via API');
        
        // Возвращаем путь к файлу, который будет использоваться для получения signed URL
        return filePath;
      } else {
        print('SupabaseStorageService: Upload failed: ${response.statusCode}');
        print('SupabaseStorageService: Response: ${response.body}');
        throw Exception('Failed to upload file: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      if (e.toString().contains('File size') || 
          e.toString().contains('Invalid file name') || 
          e.toString().contains('File type not allowed') ||
          e.toString().contains('does not match media type')) {
        print('SupabaseStorageService: Security validation failed: $e');
      } else {
        print('SupabaseStorageService: Error uploading file: $e');
      }
      print('SupabaseStorageService: Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  // Загрузить thumbnail
  static Future<String?> uploadThumbnail({
    required Uint8List thumbnailBytes,
    required String fileName,
    String? accessToken,
  }) async {
    try {
      return await uploadMedia(
        fileBytes: thumbnailBytes,
        fileName: fileName,
        bucketName: 'post-media',
        accessToken: accessToken,
      );
    } catch (e) {
      print('SupabaseStorageService: Error uploading thumbnail: $e');
      return null;
    }
  }

  // Загрузить медиа для сообщений в dm_media bucket
  static Future<String> uploadChatMedia({
    required Uint8List fileBytes,
    required String userId,
    required String chatId,
    required String fileExtension,
    String? accessToken,
    String? mediaType, // 'image' or 'video' для валидации
  }) async {
    try {
      print('SupabaseStorageService: Uploading chat media to dm_media bucket');
      print('SupabaseStorageService: UserId: $userId, ChatId: $chatId');
      print('SupabaseStorageService: File size: ${fileBytes.length} bytes');
      
      // Формируем путь в формате userId/chatId/timestamp.ext
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$userId/$chatId/$timestamp.$fileExtension';
      
      print('SupabaseStorageService: File path: $fileName');
      
      return await uploadMedia(
        fileBytes: fileBytes,
        fileName: fileName,
        bucketName: 'dm_media',
        accessToken: accessToken,
        mediaType: mediaType,
      );
    } catch (e) {
      print('SupabaseStorageService: Error uploading chat media: $e');
      rethrow;
    }
  }
}

