import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/parser/lrc_parser.dart';
import 'package:yuukilyrics/services/lyrics_state_service.dart';
import 'package:yuukilyrics/services/morae.dart';

/// Records one timestamp per slot (1 s, 2 s, ...) and returns the raw text
/// after each. The default -230 ms offset makes 1 s read as 00:00:77.
List<String> _tagAll(String lrc, {int? limit}) {
  final state = LyricsStateService()..loadLrcText(lrc);
  addTearDown(state.dispose);
  state.startTagging();
  final steps = <String>[];
  for (var i = 0; state.activeCursor != null && i < (limit ?? 16); i++) {
    state.recordTimestamp(Duration(seconds: i + 1));
    steps.add(state.rawText);
  }
  return steps;
}

void main() {
  group('splitMorae matches RhythmicaLyrics SakuraYomiBunkai', () {
    final cases = {
      'きょう': ['きょ', 'う'],
      'とうきょう': ['と', 'う', 'きょ', 'う'],
      'ちゃっ': ['ちゃっ'],
      'くゎ': ['くゎ'],
      'いっヶ': ['いっヶ'],
      'らーめん': ['らー', 'め', 'ん'],
      'ろ’': ['ろ’'],
      // Not joined by RhythmicaLyrics.
      'か゛': ['か', '゛'],
      // Joining only follows a full-width character.
      'aー': ['a', 'ー'],
      'ｷｮ': ['ｷ', 'ｮ'],
    };
    cases.forEach((reading, morae) {
      test(reading, () => expect(splitMorae(reading), morae));
    });
  });

  group('timing ruby morae', () {
    test('the second check of きょう times う, not ょう', () {
      expect(_tagAll('{今日|[2]きょう}').last, '{今日|[2|00:00:77]きょ[00:01:77]う}');
    });

    test('each check of とうきょう lands on its own mora', () {
      expect(
        _tagAll('{東京|[4]とうきょう}').last,
        '{東京|[4|00:00:77]と[00:01:77]う[00:02:77]きょ[00:03:77]う}',
      );
    });

    test('a reading timed by character in an old file is corrected', () {
      final state = LyricsStateService()
        ..loadLrcText('{今日|[2|00:00:50]き[00:01:00]ょう}');
      addTearDown(state.dispose);
      state.setActiveCursorByTap(0, 0, 1);
      state.recordTimestamp(const Duration(seconds: 2));
      expect(state.rawText, '{今日|[2|00:00:50]きょ[00:01:77]う}');
    });
  });

  group('no trailing [] placeholders in saved text', () {
    test('a partly timed multi-check word', () {
      final steps = _tagAll('[3]Hello');
      expect(steps, everyElement(isNot(contains('[]'))));
      expect(steps[1], '{Hello|[3|00:00:77][00:01:77]}');
      expect(steps.last, '{Hello|[3|00:00:77][00:01:77][00:02:77]}');
    });

    test('a partly timed ruby', () {
      final steps = _tagAll('{漢字|[3]かんじ}', limit: 2);
      expect(steps.last, '{漢字|[3|00:00:77]か[00:01:77]んじ}');
    });

    test('a placeholder before a timed mora is kept', () {
      final ruby = LrcParser.parseLine('{漢字|[3]か[]ん[00:02:00]じ}');
      expect(ruby.toLrcString(), '{漢字|[3]か[]ん[00:02:00]じ}');
    });

    test('trailing placeholders are dropped', () {
      final ruby = LyricRuby(
        baseText: '漢字',
        rubyNodes: [
          LyricTimeTag(type: 3, time: '00:01:00'),
          LyricText('か'),
          LyricTimeTag(time: ''),
          LyricText('ん'),
          LyricTimeTag(time: ''),
          LyricText('じ'),
        ],
      );
      expect(ruby.toLrcString(), '{漢字|[3|00:01:00]かんじ}');
    });
  });

  test('splitting a ruby node keeps morae whole', () {
    final state = LyricsStateService()..loadLrcText('{東京|とうきょう}');
    addTearDown(state.dispose);
    state.setSelection(0, 0);
    state.splitSelectedNode();
    final rubies = state.document!.lines.single.nodes.whereType<LyricRuby>();
    expect(
      rubies.map(
        (ruby) =>
            '${ruby.baseText}:'
            '${ruby.rubyNodes.whereType<LyricText>().map((t) => t.text).join()}',
      ),
      ['東:とう', '京:きょう'],
    );
  });
}
