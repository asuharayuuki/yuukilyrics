import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/parser/lrc_parser.dart';

void main() {
  group('LyricTimeTag', () {
    test('formats durations using accumulated minutes', () {
      expect(
        LyricTimeTag.formatDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 450),
        ),
        '62:03:45',
      );
    });

    test('strictly parses supported time formats', () {
      expect(
        LyricTimeTag.parseDuration('62:03:45'),
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 450),
      );
      expect(
        LyricTimeTag.parseDuration('02:03.4'),
        const Duration(minutes: 2, seconds: 3, milliseconds: 400),
      );
      expect(LyricTimeTag.parseDuration('02:60:00'), isNull);
      expect(LyricTimeTag.parseDuration('aa:03:00'), isNull);
      expect(LyricTimeTag.parseDuration('1:2:3:4'), isNull);
    });
  });

  group('LrcParser', () {
    test('keeps unsupported bracket expressions as literal text', () {
      const source = '[ar:Artist][Chorus]歌词 [Live] 版本[01:99:00][-1|01:02:03]';
      final line = LrcParser.parseLine(source);

      expect(line.nodes, everyElement(isA<LyricText>()));
      expect(line.toLrcString(), source);
    });

    test('parses valid typed and untyped tags and round-trips them', () {
      const source = '[3|62:03:45]歌[10|62:04:00][]';
      final line = LrcParser.parseLine(source);

      expect(line.nodes.whereType<LyricTimeTag>(), hasLength(3));
      expect(line.toLrcString(), source);
    });
  });
}
