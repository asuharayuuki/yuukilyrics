import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/parser/lrc_parser.dart';

void main() {
  group('ruby round-trip', () {
    for (final source in [
      // A second typed check must survive; collapsing gave `[1]かんじ`,
      // silently dropping a check.
      '{漢字|[1]かん[1]じ}',
      // Text before the first tag must not be moved behind it.
      '{漢字|かん[1]じ}',
      '{漢字|[2]かんじ}',
      '{漢字|[1|00:01:00]かん[00:01:50]じ}',
      '{漢字|[1]かん＋[1]じ}',
    ]) {
      test(source, () {
        expect(LrcParser.parseLine(source).toLrcString(), source);
      });
    }

    test('canonical untimed placeholders are still written compactly', () {
      final ruby = LyricRuby(
        baseText: '漢字',
        rubyNodes: [
          LyricTimeTag(type: 3, time: ''),
          LyricText('か'),
          LyricTimeTag(time: ''),
          LyricText('ん'),
          LyricTimeTag(time: ''),
          LyricText('じ'),
        ],
      );
      expect(ruby.toLrcString(), '{漢字|[3]かんじ}');
    });
  });

  test('negative durations format as zero instead of an unparsable tag', () {
    final formatted = LyricTimeTag.formatDuration(
      const Duration(milliseconds: -1500),
    );
    expect(formatted, '00:00:00');
    expect(LyricTimeTag.parseDuration(formatted), Duration.zero);
  });
}
