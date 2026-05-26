import 'dart:io';
import 'dart:typed_data';

class WaveformData {
  final List<double> samples;
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
}
