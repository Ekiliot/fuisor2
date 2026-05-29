import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'dart:async';

class ImageOverlay {
  final String imagePath;
  final double x; // Absolute X position in pixels
  final double y; // Absolute Y position in pixels
  final double startTime; // Start time in seconds
  final double endTime; // End time in seconds

  const ImageOverlay({
    required this.imagePath,
    required this.x,
    required this.y,
    required this.startTime,
    required this.endTime,
  });
}

class ExportService {
  static Future<String?> exportVideo({
    required String inputPath,
    required String outputPath,
    required double startSeconds,
    required double durationSeconds,
    List<ImageOverlay>? imageOverlays, // Support multiple image overlays
    int? videoWidth,
    int? videoHeight,
    String? audioPath,
    double? audioStartTime,
    double? audioEndTime,
    bool muteOriginalAudio = false,
    void Function(double)? onProgress,
  }) async {
    String command;

    final hasAudio = audioPath != null && audioPath.isNotEmpty;
    final hasImages = imageOverlays != null && imageOverlays.isNotEmpty;
    final needsScaling = videoWidth != null && videoHeight != null;

    if (hasImages || hasAudio || needsScaling) {
      List<String> inputs = [];
      List<String> filterParts = [];
      List<String> maps = [];
      
      // Video input (Index 0)
      inputs.add('-ss $startSeconds -t $durationSeconds -i "$inputPath"');
      
      // Audio input (Index 1 if provided)
      if (hasAudio) {
        final audioDuration = (audioEndTime! - audioStartTime!).clamp(0.0, durationSeconds);
        inputs.add('-ss $audioStartTime -t $audioDuration -i "$audioPath"');
      }

      // Add image inputs (Indexes 1/2+)
      int imageInputOffset = hasAudio ? 2 : 1;
      if (hasImages) {
        for (var overlay in imageOverlays) {
          inputs.add('-i "${overlay.imagePath}"');
        }
      }

      String videoOutputLabel = '0:v';
      
      if (needsScaling) {
        videoOutputLabel = 'vscaled';
        filterParts.add("[0:v]scale=$videoWidth:$videoHeight:force_original_aspect_ratio=decrease,pad=$videoWidth:$videoHeight:(ow-iw)/2:(oh-ih)/2:black[$videoOutputLabel]");
      }

      if (hasImages) {
        String currentInput = videoOutputLabel;
        for (int i = 0; i < imageOverlays!.length; i++) {
          final overlay = imageOverlays[i];
          final imgIndex = imageInputOffset + i;
          
          final textStartRelative = overlay.startTime.toStringAsFixed(2);
          final textEndRelative = overlay.endTime.clamp(0.0, durationSeconds).toStringAsFixed(2);
          
          final outputLabel = i == imageOverlays.length - 1 ? 'vout' : 'vimg$i';
          
          filterParts.add("[$currentInput][$imgIndex:v]overlay=x=${overlay.x.round()}:y=${overlay.y.round()}:enable='between(t,$textStartRelative,$textEndRelative)'[$outputLabel]");
          currentInput = outputLabel;
          videoOutputLabel = outputLabel;
        }
      }

      // Audio mixing
      if (hasAudio) {
        if (muteOriginalAudio) {
          maps.add('-map "[$videoOutputLabel]"');
          maps.add('-map 1:a');
        } else {
          filterParts.add('[1:a]volume=1.0[a1]');
          filterParts.add('[0:a][a1]amix=inputs=2:duration=shortest[aout]');
          maps.add('-map "[$videoOutputLabel]"');
          maps.add('-map "[aout]"');
        }
      } else if (hasImages || needsScaling) {
        maps.add('-map "[$videoOutputLabel]"');
        maps.add('-map 0:a?'); // Safely map original audio if it exists!
      }

      command = '${inputs.join(' ')} ';
      
      if (filterParts.isNotEmpty) {
          command += "-filter_complex \"${filterParts.join(';')}\" ";
      }
      command += maps.join(' ');
      
      command += ' -c:v libx264 -preset ultrafast -crf 23 ';
      if (!hasAudio || muteOriginalAudio) {
        command += '-c:a copy ';
      } else {
        command += '-c:a aac '; // Since we mix, we must re-encode audio
      }
      command += '-shortest -y "$outputPath"';
    } else {
      command = '-ss $startSeconds -t $durationSeconds -i "$inputPath" -c copy -y "$outputPath"';
    }

    print('FFmpeg command: $command');

    final completer = Completer<String?>();

    await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          completer.complete(outputPath);
        } else {
          final logs = await session.getLogs();
          for (var log in logs) {
            print(log.getMessage());
          }
          completer.complete(null);
        }
      },
      (log) {},
      (statistics) {
        if (onProgress != null && durationSeconds > 0) {
          final timeInMilliseconds = statistics.getTime();
          if (timeInMilliseconds > 0) {
            final progress = (timeInMilliseconds / 1000.0) / durationSeconds;
            onProgress(progress.clamp(0.0, 1.0));
          }
        }
      },
    );

    return completer.future;
  }
}
