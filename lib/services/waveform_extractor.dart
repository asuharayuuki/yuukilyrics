import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class WaveformData {
  final Float32List samples;
  final Duration duration;

  WaveformData({required this.samples, required this.duration});
}

class WaveformExtractor {
  static Future<WaveformData?> parsePcmFile(

    File outputFile,
    int sampleRate,
    int samplesPerPixel,
  ) async {
    if (!await outputFile.exists()) return null;

    final bytes = await outputFile.readAsBytes();
    final downsampled = await compute(_downsample, {
      'bytes': bytes,
      'samplesPerPixel': samplesPerPixel,
      'sampleRate': sampleRate,
    });

    final durationInSeconds = (bytes.length ~/ 2) / sampleRate;
    await outputFile.delete();

    return WaveformData(
      samples: downsampled,
      duration: Duration(milliseconds: (durationInSeconds * 1000).toInt()),
    );
  }

  static Float32List _downsample(Map<String, dynamic> args) {
    final Uint8List bytes = args['bytes'];
    final int samplesPerPixel = args['samplesPerPixel'];
    
    // Use proper view respecting offset
    final intData = Int16List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 2);

    final size = (intData.length / samplesPerPixel).ceil();
    Float32List downsampled = Float32List(size);
    int index = 0;
    for (int i = 0; i < intData.length; i += samplesPerPixel) {
      int end = (i + samplesPerPixel).clamp(0, intData.length);
      double maxAmp = 0;
      for (int j = i; j < end; j++) {
        final amp = intData[j].abs() / 32768.0;
        if (amp > maxAmp) maxAmp = amp;
      }
      if (index < size) downsampled[index++] = maxAmp;
    }
    return downsampled;
  }
}
