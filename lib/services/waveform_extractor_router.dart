import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'waveform_extractor.dart';
import 'waveform_extractor_mobile.dart';

class WaveformExtractorRouter {
  static Future<WaveformData?> extractWaveform(
    String mediaPath, {
    int sampleRate = 8000,
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
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String outputPath = '${tempDir.path}/temp_waveform.pcm';

      final outputFile = File(outputPath);
      if (await outputFile.exists()) await outputFile.delete();

      final result = await Process.run('ffmpeg', [
        '-y',
        '-i', mediaPath,
        '-ac', '1',
        '-ar', sampleRate.toString(),
        '-f', 's16le',
        '-acodec', 'pcm_s16le',
        outputPath,
      ]);

      if (result.exitCode == 0) {
        if (!await outputFile.exists()) return null;

        final bytes = await outputFile.readAsBytes();
        final intData = Int16List.view(bytes.buffer);

        List<double> downsampled = [];
        for (int i = 0; i < intData.length; i += samplesPerPixel) {
          int end = (i + samplesPerPixel).clamp(0, intData.length);
          double maxAmp = 0;
          for (int j = i; j < end; j++) {
            final amp = intData[j].abs() / 32768.0;
            if (amp > maxAmp) maxAmp = amp;
          }
          downsampled.add(maxAmp);
        }

        final durationInSeconds = intData.length / sampleRate;
        await outputFile.delete();

        return WaveformData(
          samples: downsampled,
          duration: Duration(milliseconds: (durationInSeconds * 1000).toInt()),
        );
      } else {
        debugPrint('FFmpeg stderr: ${result.stderr}');
        return null;
      }
    } catch (e) {
      debugPrint('Waveform extraction error: $e');
      return null;
    }
  }
}
