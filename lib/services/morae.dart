import 'package:characters/characters.dart';

/// Characters that never start a mora of their own: small kana, the long
/// vowel mark and the apostrophe RhythmicaLyrics uses in readings.
const _joinsPrevious = {
  'ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ', 'っ', 'ゃ', 'ゅ', 'ょ', 'ゎ', //
  'ァ', 'ィ', 'ゥ', 'ェ', 'ォ', 'ッ', 'ャ', 'ュ', 'ョ', 'ヮ', 'ヵ', 'ヶ', //
  'ー', '’',
};

/// Splits a ruby reading into morae, the units that each take one check.
///
/// Mirrors RhythmicaLyrics' SakuraYomiBunkai (routin_func.hsp) with its
/// default settings: small kana (including っ/ッ), `ー` and `’` join the
/// preceding character, so `きょう` is `きょ|う` and `ちゃっ` is one mora.
/// As in RhythmicaLyrics, joining only happens after a full-width
/// character; after ASCII or half-width kana every character stands alone.
List<String> splitMorae(String reading) {
  final morae = <String>[];
  var previousIsWide = false;
  for (final char in reading.characters) {
    if (morae.isNotEmpty && previousIsWide && _joinsPrevious.contains(char)) {
      morae.last += char;
    } else {
      morae.add(char);
    }
    previousIsWide = _isWide(char);
  }
  return morae;
}

bool _isWide(String char) {
  final code = char.runes.first;
  if (code < 0x80) return false;
  // Half-width katakana and punctuation (single-byte in Shift_JIS).
  if (code >= 0xFF61 && code <= 0xFF9F) return false;
  return true;
}
