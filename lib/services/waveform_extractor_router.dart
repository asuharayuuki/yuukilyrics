import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'waveform_extractor.dart';
import 'waveform_extractor_mobile.dart';
import 'ffmpeg_service.dart';

class WaveformExtractorRouter {
  static Future<WaveformData?> extractWaveform(
    String mediaPath, {
    int sampleRate = 16000,
    int samplesPerPixel = 100,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Mobile: use bundled FFmpegKit
      return MobileWaveformExtractor.extract(mediaPath, sampleRate, samplesPerPixel);
    } else {
      // Desktop: use system ffmpeg
      return _extractWithSystemFfmpeg(mediaPath, sampleRate, samplesPerPixel);
    }
  }

  static Future<WaveformData?> _extractWithSystemFfmpeg(
    String mediaPath,
    int sampleRate,
    int samplesPerPixel,
  ) async {
    final Directory tempDir = await getTemporaryDirectory();
    final String outputPath = '${tempDir.path}/temp_waveform.pcm';

    final outputFile = File(outputPath);
    if (await outputFile.exists()) await outputFile.delete();

    String ffmpegCommand = 'ffmpeg';
    if (Platform.isWindows) {
      ffmpegCommand = await FfmpegService().windowsFfmpegPath;
    }

    final result = await Process.run(ffmpegCommand, [
      '-y',
      '-i', mediaPath,
      '-ac', '1',
      '-ar', sampleRate.toString(),
      '-f', 's16le',
      '-acodec', 'pcm_s16le',
      outputPath,
    ]);

    if (result.exitCode == 0) {
      return WaveformExtractor.parsePcmFile(outputFile, sampleRate, samplesPerPixel);
    } else {
      debugPrint('FFmpeg stderr: ${result.stderr}');
      throw Exception('FFmpeg 处理失败: ${result.stderr}');
    }
  }
}
