import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../services/waveform_extractor.dart';

/// Mobile waveform extractor using FFmpegKit.
/// Used on Android and iOS platforms.
class MobileWaveformExtractor {
  static Future<WaveformData?> extract(
    String mediaPath,
    int sampleRate,
    int samplesPerPixel,
  ) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String outputPath = '${tempDir.path}/temp_waveform.pcm';
      final outputFile = File(outputPath);

      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      final session = await FFmpegKit.execute(
        '-y -i "$mediaPath" -ac 1 -ar $sampleRate -f s16le -acodec pcm_s16le "$outputPath"',
      );
      final returnCode = await session.getReturnCode();

      if (returnCode != null && ReturnCode.isSuccess(returnCode)) {
        return WaveformExtractor.parsePcmFile(outputFile, sampleRate, samplesPerPixel);
      } else {
        debugPrint('Mobile FFmpeg extraction failed: $returnCode');
        return null;
      }
    } catch (e) {
      debugPrint('Mobile waveform extraction error: $e');
      return null;
    }
  }
}
