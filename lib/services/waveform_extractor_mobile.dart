import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_waveform/just_waveform.dart';

import '../services/waveform_extractor.dart';

/// Mobile waveform extractor using just_waveform.
/// Used on Android, iOS, and macOS platforms.
class MobileWaveformExtractor {
  static Future<WaveformData?> extract(
    String mediaPath,
    int sampleRate,
    int samplesPerPixel,
  ) async {
    try {
      final audioFile = File(mediaPath);
      final tempDir = await getTemporaryDirectory();
      final waveFile = File('${tempDir.path}/temp_waveform.wave');

      if (await waveFile.exists()) {
        await waveFile.delete();
      }

      final progressStream = JustWaveform.extract(
        audioInFile: audioFile,
        waveOutFile: waveFile,
        zoom: WaveformZoom.pixelsPerSecond(sampleRate ~/ samplesPerPixel),
      );

      Waveform? extractedWaveform;
      await for (final progress in progressStream) {
        if (progress.progress == 1.0) {
          extractedWaveform = progress.waveform;
        }
      }

      if (extractedWaveform == null) return null;

      List<double> downsampled = [];
      for (final sample in extractedWaveform.data) {
        // data contains min/max pairs (int values).
        // Since it returns signed 16-bit PCM values or similar depending on extraction,
        // we take the absolute value and normalize by 32768.
        final amp = sample.abs() / 32768.0;
        downsampled.add(amp);
      }

      // just_waveform creates min/max pairs, so the resulting array is 2x the number of pixels.
      // Our visualizer expects a single max amplitude per pixel, so we downsample the min/max pairs.
      List<double> finalDownsampled = [];
      for (int i = 0; i < downsampled.length; i += 2) {
        double minAmp = downsampled[i];
        double maxAmp = (i + 1 < downsampled.length) ? downsampled[i + 1] : minAmp;
        finalDownsampled.add(maxAmp > minAmp ? maxAmp : minAmp);
      }

      return WaveformData(
        samples: finalDownsampled,
        duration: extractedWaveform.duration,
      );
    } catch (e) {
      debugPrint('Mobile waveform extraction error: $e');
      return null;
    }
  }
}
