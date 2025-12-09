import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class ImageCompressor {
  /// Сжимает изображение в WebP с динамическим качеством
  /// Возвращает сжатые байты или null, если сжатие не требуется/не удалось
  static Future<Uint8List?> compressImageToWebP({
    required Uint8List imageBytes,
    int? targetSizeBytes, // Целевой размер в байтах (опционально)
  }) async {
    try {
      final fileSize = imageBytes.length;
      final fileSizeMB = fileSize / (1024 * 1024);
      
      print('ImageCompressor: Input file size: ${fileSizeMB.toStringAsFixed(2)} MB');

      // Если файл меньше 1 МБ, сжатие не требуется
      if (fileSize < 1024 * 1024) {
        print('ImageCompressor: File size is less than 1 MB, compression not needed');
        return null;
      }

      // Определяем качество на основе размера файла
      int quality;
      if (fileSizeMB <= 1.0) {
        quality = 100;
      } else if (fileSizeMB <= 2.0) {
        quality = 95;
      } else if (fileSizeMB <= 3.0) {
        quality = 90;
      } else if (fileSizeMB <= 4.5) {
        // Линейная интерполяция между 3 МБ (90) и 4.5 МБ (75)
        quality = 90 - ((fileSizeMB - 3.0) / 1.5 * 15).round();
        quality = quality.clamp(75, 90);
      } else {
        // Для файлов больше 4.5 МБ вычисляем качество так, чтобы получилось ~4 МБ
        quality = _calculateQualityForTargetSize(fileSize, targetSizeBytes ?? 4 * 1024 * 1024);
      }

      print('ImageCompressor: Calculated quality: $quality%');

      // Сохраняем временный файл для компрессии
      // Определяем формат по первым байтам (магические числа)
      String inputExtension = 'jpg';
      if (imageBytes.length >= 8) {
        // PNG: 89 50 4E 47
        if (imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47) {
          inputExtension = 'png';
        }
        // WebP: RIFF...WEBP
        else if (imageBytes.length >= 12 &&
                 imageBytes[0] == 0x52 && imageBytes[1] == 0x49 && imageBytes[2] == 0x46 && imageBytes[3] == 0x46 &&
                 imageBytes[8] == 0x57 && imageBytes[9] == 0x45 && imageBytes[10] == 0x42 && imageBytes[11] == 0x50) {
          inputExtension = 'webp';
        }
        // GIF: GIF87a или GIF89a
        else if (imageBytes[0] == 0x47 && imageBytes[1] == 0x49 && imageBytes[2] == 0x46) {
          inputExtension = 'gif';
        }
      }
      
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempInputFile = File('${tempDir.path}/temp_input_$timestamp.$inputExtension');
      await tempInputFile.writeAsBytes(imageBytes);

      // Сжимаем в WebP с заданным качеством
      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        tempInputFile.absolute.path,
        '${tempDir.path}/compressed_$timestamp.webp',
        quality: quality,
        format: CompressFormat.webp,
      );

      // Удаляем временный входной файл
      try {
        await tempInputFile.delete();
      } catch (e) {
        print('ImageCompressor: Error deleting temp input file: $e');
      }

      if (compressedFile == null) {
        print('ImageCompressor: Failed to compress image');
        return null;
      }

      final compressedBytes = await compressedFile.readAsBytes();

      // Удаляем временный сжатый файл
      try {
        final compressedFileToDelete = File(compressedFile.path);
        if (await compressedFileToDelete.exists()) {
          await compressedFileToDelete.delete();
        }
      } catch (e) {
        print('ImageCompressor: Error deleting temp compressed file: $e');
      }

      final compressedSize = compressedBytes.length;
      final compressedSizeMB = compressedSize / (1024 * 1024);
      final compressionRatio = ((1 - compressedSize / fileSize) * 100).toStringAsFixed(1);

      print('ImageCompressor: Compression successful!');
      print('ImageCompressor: Original size: ${fileSizeMB.toStringAsFixed(2)} MB');
      print('ImageCompressor: Compressed size: ${compressedSizeMB.toStringAsFixed(2)} MB');
      print('ImageCompressor: Compression ratio: $compressionRatio%');

      // Если сжатый файл больше исходного, возвращаем исходный
      if (compressedSize >= fileSize) {
        print('ImageCompressor: Compressed file is larger than original, using original');
        return null;
      }

      // Если файл больше 4.5 МБ и сжатый файл все еще больше 4.5 МБ, пробуем еще раз с меньшим качеством
      if (fileSizeMB > 4.5 && compressedSizeMB > 4.5) {
        print('ImageCompressor: Compressed file still exceeds 4.5 MB, trying lower quality...');
        int lowerQuality = (quality * 0.8).round().clamp(50, quality);
        
        // Создаем новый временный файл для повторной попытки
        // Используем тот же формат, что и для первого сжатия
        final retryTimestamp = DateTime.now().millisecondsSinceEpoch;
        final retryInputFile = File('${tempDir.path}/retry_input_$retryTimestamp.$inputExtension');
        await retryInputFile.writeAsBytes(imageBytes);
        
        final retryFile = await FlutterImageCompress.compressAndGetFile(
          retryInputFile.absolute.path,
          '${tempDir.path}/retry_compressed_$retryTimestamp.webp',
          quality: lowerQuality,
          format: CompressFormat.webp,
        );
        
        // Удаляем временные файлы
        try {
          await retryInputFile.delete();
        } catch (e) {
          // Игнорируем ошибки удаления
        }
        
        if (retryFile != null) {
          final retryBytes = await retryFile.readAsBytes();
          final retrySizeMB = retryBytes.length / (1024 * 1024);
          
          try {
            final retryFileToDelete = File(retryFile.path);
            if (await retryFileToDelete.exists()) {
              await retryFileToDelete.delete();
            }
          } catch (e) {
            // Игнорируем ошибки удаления
          }
          
          if (retryBytes.length < compressedBytes.length) {
            print('ImageCompressor: Retry with quality $lowerQuality: ${retrySizeMB.toStringAsFixed(2)} MB');
            return retryBytes;
          }
        }
      }

      return compressedBytes;
    } catch (e, stackTrace) {
      print('ImageCompressor: Error compressing image: $e');
      print('ImageCompressor: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Вычисляет качество для достижения целевого размера
  static int _calculateQualityForTargetSize(int originalSize, int targetSize) {
    // Начинаем с качества 70 и итеративно подбираем
    int quality = 70;
    int minQuality = 50;
    int maxQuality = 85;
    
    // Примерная оценка: каждые 5 единиц качества дают примерно 10-15% изменения размера
    // Используем бинарный поиск для более точного результата
    double ratio = targetSize / originalSize;
    
    if (ratio >= 0.9) {
      quality = 85;
    } else if (ratio >= 0.7) {
      quality = 75;
    } else if (ratio >= 0.5) {
      quality = 65;
    } else {
      quality = 55;
    }
    
    return quality.clamp(minQuality, maxQuality);
  }

  /// Сжимает изображение из файла
  static Future<Uint8List?> compressImageFile({
    required String filePath,
    int? targetSizeBytes,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('ImageCompressor: File does not exist: $filePath');
        return null;
      }

      final imageBytes = await file.readAsBytes();
      return await compressImageToWebP(
        imageBytes: imageBytes,
        targetSizeBytes: targetSizeBytes,
      );
    } catch (e) {
      print('ImageCompressor: Error reading file: $e');
      return null;
    }
  }
}

