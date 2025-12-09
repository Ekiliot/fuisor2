import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VideoCompressor {
  /// Сжимает видео в AV1 кодек с разрешением 1080p
  /// Возвращает путь к сжатому файлу или null, если сжатие не требуется/не удалось
  static Future<String?> compressVideoToAV1({
    required String inputPath,
    required int maxSizeBytes, // Максимальный размер в байтах (4.5 МБ = 4.5 * 1024 * 1024)
  }) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        print('VideoCompressor: Input file does not exist: $inputPath');
        return null;
      }

      final fileSize = await inputFile.length();
      print('VideoCompressor: Input file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

      // Если файл меньше максимального размера, сжатие не требуется
      if (fileSize <= maxSizeBytes) {
        print('VideoCompressor: File size is within limit, compression not needed');
        return inputPath;
      }

      print('VideoCompressor: Starting compression to AV1 1080p...');

      // Создаем временный файл для выходного видео
      final tempDir = await getTemporaryDirectory();
      final outputFileName = 'compressed_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final outputPath = '${tempDir.path}/$outputFileName';

      // FFmpeg команда для сжатия в AV1 с разрешением 1080p
      // Используем libsvtav1 для кодирования в AV1 (если доступен)
      // Если AV1 не поддерживается, используем libx264 как fallback
      // -vf scale=1920:1080:force_original_aspect_ratio=decrease - устанавливает максимальное разрешение 1080p
      // -c:v libsvtav1 - кодек AV1 (или libx264 для H.264)
      // -crf 30 - качество (меньше = лучше качество, но больше размер)
      // -preset 6 - скорость кодирования (для AV1: 0-13, для H.264: ultrafast-veryslow)
      // -c:a copy - копируем аудио без перекодирования
      
      // Пробуем сначала AV1, если не сработает - используем H.264
      String command = '-i "$inputPath" '
          '-vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" '
          '-c:v libsvtav1 '
          '-crf 30 '
          '-preset 6 '
          '-b:v 0 '
          '-c:a copy '
          '-movflags +faststart '
          '-y '
          '"$outputPath"';

      print('VideoCompressor: FFmpeg command: $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final compressedSize = await outputFile.length();
          final compressionRatio = ((1 - compressedSize / fileSize) * 100).toStringAsFixed(1);
          
          print('VideoCompressor: Compression successful!');
          print('VideoCompressor: Original size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
          print('VideoCompressor: Compressed size: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
          print('VideoCompressor: Compression ratio: $compressionRatio%');

          // Проверяем, что сжатый файл меньше исходного
          if (compressedSize < fileSize) {
            return outputPath;
          } else {
            print('VideoCompressor: Compressed file is larger than original, using original');
            await outputFile.delete();
            return inputPath;
          }
        } else {
          print('VideoCompressor: Output file was not created');
          return null;
        }
      } else {
        final output = await session.getOutput();
        print('VideoCompressor: AV1 compression failed, trying H.264 fallback...');
        print('VideoCompressor: Return code: $returnCode');
        print('VideoCompressor: Output: $output');
        
        // Пробуем H.264 как fallback
        final h264Command = '-i "$inputPath" '
            '-vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" '
            '-c:v libx264 '
            '-crf 23 '
            '-preset medium '
            '-profile:v high '
            '-level 4.0 '
            '-c:a copy '
            '-movflags +faststart '
            '-y '
            '"$outputPath"';
        
        print('VideoCompressor: Trying H.264 compression...');
        final h264Session = await FFmpegKit.execute(h264Command);
        final h264ReturnCode = await h264Session.getReturnCode();
        
        if (ReturnCode.isSuccess(h264ReturnCode)) {
          final outputFile = File(outputPath);
          if (await outputFile.exists()) {
            final compressedSize = await outputFile.length();
            print('VideoCompressor: H.264 compression successful!');
            print('VideoCompressor: Compressed size: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
            
            if (compressedSize < fileSize) {
              return outputPath;
            } else {
              print('VideoCompressor: H.264 compressed file is larger than original, using original');
              await outputFile.delete();
              return inputPath;
            }
          }
        }
        
        // Если оба метода не сработали, возвращаем исходный файл
        print('VideoCompressor: Both AV1 and H.264 compression failed, using original file');
        return inputPath;
      }
    } catch (e, stackTrace) {
      print('VideoCompressor: Error compressing video: $e');
      print('VideoCompressor: Stack trace: $stackTrace');
      // В случае ошибки возвращаем исходный файл
      return inputPath;
    }
  }

  /// Проверяет, нужно ли сжимать видео
  static Future<bool> needsCompression({
    required String filePath,
    required int maxSizeBytes,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final fileSize = await file.length();
      return fileSize > maxSizeBytes;
    } catch (e) {
      print('VideoCompressor: Error checking file size: $e');
      return false;
    }
  }
}

