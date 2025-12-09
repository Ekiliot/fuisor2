import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class TextOverlay {
  final String text;
  final double x; // Absolute X position in pixels
  final double y; // Absolute Y position in pixels
  final double startTime; // Start time in seconds (relative to trimmed video start)
  final double endTime; // End time in seconds (relative to trimmed video start)
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final Color textColor;
  final Color backgroundColor;

  const TextOverlay({
    required this.text,
    required this.x,
    required this.y,
    required this.startTime,
    required this.endTime,
    this.fontWeight = FontWeight.bold,
    this.fontStyle = FontStyle.normal,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0x4D000000),
  });
}

class ExportService {
  // Cache for font file paths
  static String? _cachedFontPath;
  
  // Get font file path - try multiple system font locations
  static Future<String?> _getFontPath(FontWeight fontWeight, FontStyle fontStyle) async {
    try {
      // Use cached path if available, but prefer NotoSans over Roboto for Cyrillic support
      if (_cachedFontPath != null && await File(_cachedFontPath!).exists()) {
        final cachedFileName = _cachedFontPath!.split('/').last;
        // If we have Roboto cached, try to find NotoSans instead (better Cyrillic support)
        if (cachedFileName.startsWith('Roboto-') && !cachedFileName.startsWith('Noto')) {
          print('ExportService: Cached Roboto font found, but prefer NotoSans for Cyrillic support. Searching for NotoSans...');
          // Continue to search for NotoSans below
        } else {
        return _cachedFontPath;
      }
      }
      
      // Try common Android font paths
      // PRIORITIZE NotoSans - it has excellent Cyrillic support
      // Build list with proper font names matching weight/style
      List<String> fontCandidates = [];
      
      // First priority: Noto Sans (excellent Unicode/Cyrillic support)
      if (fontWeight == FontWeight.bold && fontStyle == FontStyle.italic) {
        fontCandidates.addAll([
          '/system/fonts/NotoSans-BoldItalic.ttf',
          '/system/fonts/NotoSerif-BoldItalic.ttf',
        ]);
      } else if (fontWeight == FontWeight.bold) {
        fontCandidates.addAll([
          '/system/fonts/NotoSans-Bold.ttf',
          '/system/fonts/NotoSerif-Bold.ttf',
        ]);
      } else if (fontStyle == FontStyle.italic) {
        fontCandidates.addAll([
          '/system/fonts/NotoSans-Italic.ttf',
          '/system/fonts/NotoSerif-Italic.ttf',
        ]);
      } else {
        fontCandidates.addAll([
          '/system/fonts/NotoSans-Regular.ttf',
          '/system/fonts/NotoSerif-Regular.ttf',
        ]);
      }
      
      // Second priority: Roboto (may not have full Cyrillic support)
      if (fontWeight == FontWeight.bold && fontStyle == FontStyle.italic) {
        fontCandidates.add('/system/fonts/Roboto-BoldItalic.ttf');
      } else if (fontWeight == FontWeight.bold) {
        fontCandidates.add('/system/fonts/Roboto-Bold.ttf');
      } else if (fontStyle == FontStyle.italic) {
        fontCandidates.add('/system/fonts/Roboto-Italic.ttf');
      } else {
        fontCandidates.add('/system/fonts/Roboto-Regular.ttf');
      }
      
      // Fallbacks (always try NotoSans-Regular as ultimate fallback)
      fontCandidates.addAll([
        '/system/fonts/NotoSans-Regular.ttf', // Best Unicode/Cyrillic support
        '/system/fonts/DroidSans.ttf',        // Older Android fallback
      ]);
      
      // Check each path and try to copy to temp directory if accessible
      for (final path in fontCandidates) {
        try {
          // Add timeout for file operations to prevent hanging
          final systemFont = File(path);
          final exists = await systemFont.exists().timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );
          
          if (exists) {
            print('ExportService: Found system font at: $path');
            
            // Extract actual font filename from path
            final actualFontName = path.split('/').last;
            
            // Try to copy to temp directory for FFmpeg access
            try {
              final tempDir = await getTemporaryDirectory()
                  .timeout(const Duration(seconds: 2));
              final tempFontPath = '${tempDir.path}/$actualFontName';
              final tempFont = File(tempFontPath);
              
              // Copy if not already exists or is different (with timeout)
              final tempExists = await tempFont.exists().timeout(
                const Duration(seconds: 1),
                onTimeout: () => false,
              );
              
              if (!tempExists) {
                final fontBytes = await systemFont.readAsBytes()
                    .timeout(const Duration(seconds: 3));
                await tempFont.writeAsBytes(fontBytes)
                    .timeout(const Duration(seconds: 3));
                print('ExportService: Copied font to temp directory: $tempFontPath');
              } else {
                // Check if sizes match (with timeout)
                try {
                  final tempSize = await tempFont.length().timeout(
                    const Duration(seconds: 1),
                  );
                  final systemSize = await systemFont.length().timeout(
                    const Duration(seconds: 1),
                  );
                  if (tempSize != systemSize) {
                    final fontBytes = await systemFont.readAsBytes()
                        .timeout(const Duration(seconds: 3));
                    await tempFont.writeAsBytes(fontBytes)
                        .timeout(const Duration(seconds: 3));
                    print('ExportService: Updated font in temp directory: $tempFontPath');
                  }
                } catch (e) {
                  // If size check fails, skip copying
                  print('ExportService: Could not check font sizes: $e');
                }
              }
              
              _cachedFontPath = tempFontPath;
              return tempFontPath;
            } catch (copyError) {
              // If copy fails, try to use system path directly
              print('ExportService: Could not copy font, trying system path: $copyError');
              _cachedFontPath = path;
              return path;
            }
          }
        } catch (e) {
          // Continue to next path
          print('ExportService: Error checking font path $path: $e');
        }
      }
      
      // If no system font found, return null to use built-in font
      print('ExportService: No system font found, will use built-in font');
      return null;
    } catch (e) {
      print('ExportService: Error getting font path: $e');
      return null;
    }
  }
  
  static Future<String?> exportVideo({
    required String inputPath,
    required String outputPath,
    required double startSeconds,
    required double durationSeconds,
    List<TextOverlay>? textOverlays, // Support multiple text overlays
    int? videoWidth,
    int? videoHeight,
    String? audioPath,
    double? audioStartTime,
    double? audioEndTime,
    bool muteOriginalAudio = false,
  }) async {
    String command;

    // Determine if we need to process audio
    final hasAudio = audioPath != null && audioPath.isNotEmpty;
    final hasText = textOverlays != null && textOverlays.isNotEmpty;
    final needsScaling = videoWidth != null && videoHeight != null;

    if (hasText || hasAudio || needsScaling) {
      // Complex processing required
      List<String> inputs = [];
      List<String> filterParts = [];
      List<String> maps = [];
      
      // Video input
      inputs.add('-ss $startSeconds -t $durationSeconds -i "$inputPath"');
      
      // Audio input (if provided)
      if (hasAudio) {
        final audioDuration = (audioEndTime! - audioStartTime!).clamp(0, durationSeconds);
        inputs.add('-ss $audioStartTime -t $audioDuration -i "$audioPath"');
      }

      // Determine output label for video
      String videoOutputLabel = '0:v';
      
      // Video scaling to fit portrait format (9:16) - scale to fit, then pad
      if (needsScaling) {
        // Target portrait dimensions (9:16 aspect ratio)
        final targetWidth = videoWidth;
        final targetHeight = videoHeight;
        
        // Scale video to fit within target dimensions while maintaining aspect ratio
        // force_original_aspect_ratio=decrease ensures video fits inside
        videoOutputLabel = 'vscaled';
        filterParts.add("[0:v]scale=$targetWidth:$targetHeight:force_original_aspect_ratio=decrease,pad=$targetWidth:$targetHeight:(ow-iw)/2:(oh-ih)/2:black[$videoOutputLabel]");
      }

      // Text overlay filters (support multiple)
      if (hasText) {
        // Pre-fetch font paths for all unique font combinations to avoid repeated async calls
        final Map<String, String?> fontPathCache = {};
        final Set<String> fontKeys = textOverlays
            .where((overlay) => overlay.text.isNotEmpty)
            .map((overlay) => '${overlay.fontWeight.index}_${overlay.fontStyle.index}')
            .toSet();
        
        // Fetch all unique font paths in parallel with timeout
        await Future.wait(fontKeys.map((key) async {
          final parts = key.split('_');
          final fontWeight = FontWeight.values[int.parse(parts[0])];
          final fontStyle = FontStyle.values[int.parse(parts[1])];
          try {
            // Add timeout to prevent hanging (5 seconds max)
            final fontPath = await _getFontPath(fontWeight, fontStyle)
                .timeout(const Duration(seconds: 5), onTimeout: () {
              print('ExportService: Timeout getting font path for $key');
              return null;
            });
            if (fontPath != null && await File(fontPath).exists()) {
              fontPathCache[key] = fontPath;
            } else {
              fontPathCache[key] = null;
            }
          } catch (e) {
            print('ExportService: Error getting font path for $key: $e');
            fontPathCache[key] = null;
          }
        }));
        
        // Process each text overlay
        String currentInput = videoOutputLabel;
        
        for (int i = 0; i < textOverlays.length; i++) {
          final textOverlay = textOverlays[i];
          if (textOverlay.text.isEmpty) continue;
          
          final textXInt = textOverlay.x.round();
          final textYInt = textOverlay.y.round();
          final textStartRelative = textOverlay.startTime.toStringAsFixed(2);
          final textEndRelative = textOverlay.endTime.clamp(0, durationSeconds).toStringAsFixed(2);
          
          // Convert Flutter color to FFmpeg format
          final textColorHex = _colorToFFmpegHex(textOverlay.textColor);
          final bgColorHex = _colorToFFmpegHex(textOverlay.backgroundColor);
          final bgAlpha = (textOverlay.backgroundColor.alpha / 255.0).toStringAsFixed(2);
          
          // Get font file path from cache (already fetched above)
          final fontKey = '${textOverlay.fontWeight.index}_${textOverlay.fontStyle.index}';
          final fontPath = fontPathCache[fontKey];
          
          // Determine output label
          final outputLabel = i == textOverlays.length - 1 ? 'vout' : 'vtext$i';
          
          // Estimate text dimensions (approximate)
          // We'll use a generous box size to prevent text cutoff
          final estimatedPadding = 20; // Padding around text
          
          // Escape text for FFmpeg command line
          // FFmpeg on Android needs careful handling for Unicode
          // We need to escape special FFmpeg characters but preserve Unicode
          String textForCommand = textOverlay.text;
          
          // First, escape single quotes by replacing ' with '\'' (close quote, escaped quote, open quote)
          textForCommand = textForCommand.replaceAll("'", "'\\''");
          
          // Then escape other special FFmpeg characters
          textForCommand = textForCommand
              .replaceAll('\\', '\\\\')  // Escape backslashes
              .replaceAll('\$', '\\\$')   // Escape dollar signs
              .replaceAll('%', '\\%')    // Escape percent signs
              .replaceAll(':', '\\:')    // Escape colons
              .replaceAll('[', '\\[')    // Escape brackets
              .replaceAll(']', '\\]')     // Escape brackets
              .replaceAll('"', '\\"')     // Escape double quotes
              .replaceAll('\n', '\\n');   // Handle line breaks
          
          print('ExportService: Original text: "${textOverlay.text}"');
          print('ExportService: Escaped text: "$textForCommand"');
          print('ExportService: Font path: ${fontPath ?? "null"}');
          
          String drawtextFilter;
          if (fontPath != null && await File(fontPath).exists()) {
            // Escape the font path for FFmpeg command
            final escapedFontPath = fontPath.replaceAll("'", "\\'").replaceAll(" ", "\\ ");
            // Use text parameter with proper escaping and explicit font
            // The font must support Unicode (Roboto/Noto Sans should work)
            drawtextFilter = 
                "[$currentInput]drawtext=fontfile='$escapedFontPath':"
                "text='$textForCommand':"
                'x=$textXInt:'
                'y=$textYInt:'
                'fontsize=30:'
                'fontcolor=$textColorHex:'
                'box=1:'
                'boxcolor=$bgColorHex@$bgAlpha:'
                'boxborderw=$estimatedPadding:'
                'text_align=center:'
                'fix_bounds=1:'
                'enable=between(t\\,$textStartRelative\\,$textEndRelative)[$outputLabel]';
          } else {
            // Fallback: try to use a Unicode-supporting system font
            // On Android, we can try to specify a font that supports Unicode
            // If no font is found, FFmpeg will use default (may not support Unicode well)
            drawtextFilter = 
                "[$currentInput]drawtext="
                "text='$textForCommand':"
                'x=$textXInt:'
                'y=$textYInt:'
                'fontsize=30:'
                'fontcolor=$textColorHex:'
                'box=1:'
                'boxcolor=$bgColorHex@$bgAlpha:'
                'boxborderw=$estimatedPadding:'
                'text_align=center:'
                'fix_bounds=1:'
                'enable=between(t\\,$textStartRelative\\,$textEndRelative)[$outputLabel]';
          }
          
          filterParts.add(drawtextFilter);
          currentInput = outputLabel;
          videoOutputLabel = outputLabel;
        }
      }

      // Audio mixing
      if (hasAudio) {
        if (muteOriginalAudio) {
          // Replace original audio with new audio
          maps.add('-map "[$videoOutputLabel]"');
          maps.add('-map 1:a');
        } else {
          // Mix original audio with new audio
          filterParts.add('[1:a]volume=1.0[a1]');
          filterParts.add('[0:a][a1]amix=inputs=2:duration=shortest[aout]');
          maps.add('-map "[$videoOutputLabel]"');
          maps.add('-map "[aout]"');
        }
      } else if (hasText || needsScaling) {
        maps.add('-map "[$videoOutputLabel]"');
      }

      // Build command
      command = '${inputs.join(' ')} ';
      
      if (filterParts.isNotEmpty) {
          command += "-filter_complex '${filterParts.join(';')}' ";
          command += maps.join(' ');
      } else {
        command += maps.join(' ');
      }
      
      command += ' -c:v libx264 -preset fast -crf 23 ';
      if (!hasAudio || muteOriginalAudio) {
        command += '-c:a copy ';
      }
      command += '-shortest -y "$outputPath"';
    } else {
      // Simple trim without processing
      command = '-ss $startSeconds -t $durationSeconds -i "$inputPath" -c copy -y "$outputPath"';
    }

    print('FFmpeg command: $command');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      print('Export successful: $outputPath');
      return outputPath;
    } else {
      print('Export failed');
      final logs = await session.getLogs();
      for (var log in logs) {
        print(log.getMessage());
      }
      return null;
    }
  }
  
  // Convert Flutter Color to FFmpeg hex format (0xRRGGBB)
  static String _colorToFFmpegHex(Color color) {
    return '0x${color.red.toRadixString(16).padLeft(2, '0')}'
           '${color.green.toRadixString(16).padLeft(2, '0')}'
           '${color.blue.toRadixString(16).padLeft(2, '0')}';
  }
  
}
