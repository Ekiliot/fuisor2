import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class ExportService {
  static Future<String?> exportVideo({
    required String inputPath,
    required String outputPath,
    required double startSeconds,
    required double durationSeconds,
  }) async {
    // FFmpeg command to trim video
    // -ss: start time
    // -t: duration
    // -i: input file
    // -c copy: copy stream (fast, no re-encoding)
    // -y: overwrite output
    final String command = '-ss $startSeconds -t $durationSeconds -i "$inputPath" -c copy -y "$outputPath"';

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
}
