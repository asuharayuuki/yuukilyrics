import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/services/ffmpeg_service.dart';

void main() {
  group('FfmpegProgressParser', () {
    test('reads time= from a single chunk', () {
      final parser = FfmpegProgressParser();
      expect(
        parser.feed('frame=  10 fps=0.0 time=00:00:05.50 bitrate=1k\r'),
        5.5,
      );
    });

    test('reads a time= token split across chunks', () {
      final parser = FfmpegProgressParser();
      expect(parser.feed('frame= 120 fps=30 ti'), isNull);
      expect(parser.feed('me=00:01:0'), isNull);
      expect(parser.feed('2.25 bitrate=900k\r'), 62.25);
    });

    test('reports the latest of several updates in one chunk', () {
      final parser = FfmpegProgressParser();
      expect(parser.feed('time=00:00:01.00 x\rtime=00:00:02.00 x\r'), 2.0);
    });

    test('ignores time=N/A', () {
      final parser = FfmpegProgressParser();
      expect(parser.feed('size=N/A time=N/A bitrate=N/A\r'), isNull);
    });
  });

  group('progressFraction', () {
    test('scales and clamps elapsed time', () {
      expect(FfmpegService.progressFraction(0.25, 0.5), 0.5);
      expect(FfmpegService.progressFraction(10, 5), 1.0);
    });

    test('returns null when the duration is unknown or zero', () {
      expect(FfmpegService.progressFraction(1, null), isNull);
      expect(FfmpegService.progressFraction(1, 0), isNull);
    });
  });

  test('parseTimestamp keeps fractional seconds', () {
    expect(FfmpegService.parseTimestamp('01', '02', '03.50'), 3723.5);
  });
}
