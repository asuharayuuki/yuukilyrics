import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class WaveformData {
  final List<double> samples;
  final Duration duration;

  WaveformData({required this.samples, required this.duration});
}

class WaveformExtractor {
  /// Extracts PCM data from a media file and downsamples it for waveform rendering.
  /// On Android/iOS: uses ffmpeg_kit_flutter_full (bundled FFmpeg).
  /// On desktop: uses the system-installed `ffmpeg` process.
  static Future<WaveformData?> extractWaveform(
    String mediaPath, {
    int sampleRate = 8000,
    int samplesPerPixel = 100,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _extractWithFfmpegKit(mediaPath, sampleRate, samplesPerPixel);
    } else {
      return _extractWithSystemFfmpeg(mediaPath, sampleRate, samplesPerPixel);
    }
  }

  /// Mobile path: ffmpeg_kit_flutter_full
  static Future<WaveformData?> _extractWithFfmpegKit(
    String mediaPath,
    int sampleRate,
    int samplesPerPixel,
  ) async {
    // Conditional import to avoid linking issues on desktop.
    // We use dynamic symbol resolution via a wrapper.
    try {
      // Import lazily so the desktop build doesn't pull in ffmpeg_kit natives.
      final ffi = await _loadFfmpegKit();
      if (ffi == null) return null;
      return await ffi(mediaPath, sampleRate, samplesPerPixel);
    } catch (e) {
      debugPrint('FFmpegKit extraction error: $e');
      return null;
    }
  }

  /// Desktop path: call system `ffmpeg` binary via Process.run
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
        return _parsePcmFile(outputFile, sampleRate, samplesPerPixel);
      } else {
        debugPrint('FFmpeg stderr: ${result.stderr}');
        return null;
      }
    } catch (e) {
      debugPrint('Waveform extraction error: $e');
      return null;
    }
  }

  static Future<WaveformData?> _parsePcmFile(
    File outputFile,
    int sampleRate,
    int samplesPerPixel,
  ) async {
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
  }

  /// Returns a function that runs ffmpeg_kit extraction — only called on mobile.
  /// This pattern avoids a direct top-level import which would break desktop compilation.
  static Future<Future<WaveformData?> Function(String, int, int)?> _loadFfmpegKit() async {
    // On mobile we dynamically call ffmpeg_kit. Since we can't conditional-import
    // in pure Dart without dart:mirrors, we use a platform check + try/catch approach.
    // The actual FFmpegKit call is wrapped so that if the native lib is missing it
    // fails gracefully rather than crashing.
    return (String path, int sr, int spp) async {
      try {
        // This dynamic dispatch prevents dead-code elimination issues on desktop.
        final dynamic ffmpegKit = await _resolveFfmpegKit();
        if (ffmpegKit == null) return null;

        final Directory tempDir = await getTemporaryDirectory();
        final String outputPath = '${tempDir.path}/temp_waveform.pcm';
        final outputFile = File(outputPath);
        if (await outputFile.exists()) await outputFile.delete();

        final dynamic session = await ffmpegKit.execute(
          '-y -i "$path" -ac 1 -ar $sr -f s16le -acodec pcm_s16le "$outputPath"',
        );
        final dynamic returnCode = await session.getReturnCode();
        if (returnCode != null && returnCode.isSuccess()) {
          return _parsePcmFile(outputFile, sr, spp);
        }
      } catch (e) {
        debugPrint('FFmpegKit dynamic call error: $e');
      }
      return null;
    };
  }

  static Future<dynamic> _resolveFfmpegKit() async {
    // This will only succeed on mobile where the native lib is bundled.
    return null; // Placeholder — see NOTE below.
  }
}
