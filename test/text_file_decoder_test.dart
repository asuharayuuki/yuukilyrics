import 'dart:convert';

import 'package:charset/charset.dart' show shiftJis;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/services/lyrics_state_service.dart';
import 'package:yuukilyrics/services/text_file_decoder.dart';

void main() {
  const lyrics = '[00:01:00]{歌|[1]うた}を[10|00:02:00]';

  test('strips a UTF-8 byte order mark', () {
    final decoded = TextFileDecoder.decode([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(lyrics),
    ]);
    expect(decoded.text, lyrics);
    expect(decoded.encoding, TextFileEncoding.utf8);
  });

  test('decodes UTF-16 with either byte order mark', () {
    final units = lyrics.codeUnits;
    final le = [
      0xFF,
      0xFE,
      for (final u in units) ...[u & 0xFF, u >> 8],
    ];
    final be = [
      0xFE,
      0xFF,
      for (final u in units) ...[u >> 8, u & 0xFF],
    ];
    expect(TextFileDecoder.decode(le).text, lyrics);
    expect(TextFileDecoder.decode(be).text, lyrics);
  });

  test('falls back to Shift_JIS for non-UTF-8 files', () {
    final decoded = TextFileDecoder.decode(shiftJis.encode(lyrics));
    expect(decoded.text, lyrics);
    expect(decoded.encoding, TextFileEncoding.shiftJis);
  });

  test('rejects undecodable bytes instead of returning garbled text', () {
    // 0x81 is a Shift_JIS lead byte with no trail byte; invalid in UTF-8 too.
    expect(
      () => TextFileDecoder.decode([0x41, 0x81]),
      throwsA(isA<FormatException>()),
    );
  });

  test('loadLrcText drops a leading BOM so it does not become lyric text', () {
    final state = LyricsStateService()..loadLrcText('\u{FEFF}$lyrics');
    addTearDown(state.dispose);
    expect(state.rawText, lyrics);
    expect(state.document!.lines.single.toLrcString(), lyrics);
  });
}
