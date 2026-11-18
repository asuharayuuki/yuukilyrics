import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' show shiftJis;

enum TextFileEncoding { utf8, utf16le, utf16be, shiftJis }

class DecodedTextFile {
  final String text;
  final TextFileEncoding encoding;

  const DecodedTextFile(this.text, this.encoding);
}

/// Decodes lyric text files from the encodings Japanese tools commonly
/// produce, without ever substituting replacement characters.
///
/// Detection order: a UTF-8 or UTF-16 byte order mark, then strict UTF-8,
/// then strict Shift_JIS (CP932). A leading BOM is never part of the result.
class TextFileDecoder {
  TextFileDecoder._();

  /// Throws [FormatException] when the bytes match none of the supported
  /// encodings, rather than returning garbled text.
  static DecodedTextFile decode(List<int> bytes) {
    if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
      return DecodedTextFile(
        utf8.decode(bytes.sublist(3)),
        TextFileEncoding.utf8,
      );
    }
    if (_startsWith(bytes, const [0xFF, 0xFE])) {
      return DecodedTextFile(
        _decodeUtf16(bytes, 2, Endian.little),
        TextFileEncoding.utf16le,
      );
    }
    if (_startsWith(bytes, const [0xFE, 0xFF])) {
      return DecodedTextFile(
        _decodeUtf16(bytes, 2, Endian.big),
        TextFileEncoding.utf16be,
      );
    }

    try {
      return DecodedTextFile(
        stripBom(utf8.decode(bytes)),
        TextFileEncoding.utf8,
      );
    } on FormatException {
      // Not UTF-8; try Shift_JIS below.
    }

    try {
      final text = shiftJis.decode(bytes);
      return DecodedTextFile(stripBom(text), TextFileEncoding.shiftJis);
    } catch (_) {
      // The decoder throws RangeError on a truncated trailing lead byte and
      // FormatException on bytes outside its table (e.g. IBM extension kanji
      // with lead bytes 0xFA-0xFC).
    }

    throw const FormatException(
      'Unsupported text encoding. Save the file as UTF-8 and try again.',
    );
  }

  /// Removes a leading U+FEFF, e.g. from pasted text.
  static String stripBom(String text) =>
      text.startsWith(_bom) ? text.substring(1) : text;

  static const _bom = '\u{FEFF}';

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _decodeUtf16(List<int> bytes, int start, Endian endian) {
    if ((bytes.length - start).isOdd) {
      throw const FormatException('Truncated UTF-16 text.');
    }
    final units = Uint16List((bytes.length - start) ~/ 2);
    for (var i = 0; i < units.length; i++) {
      final a = bytes[start + i * 2];
      final b = bytes[start + i * 2 + 1];
      units[i] = endian == Endian.little ? a | (b << 8) : (a << 8) | b;
    }
    return String.fromCharCodes(units);
  }
}
