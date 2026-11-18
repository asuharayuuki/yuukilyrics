import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:http/http.dart' as http;

import '../models/lyric_ast.dart';

/// Client for the Yahoo! JAPAN furigana API that converts its words into
/// ruby nodes with RhythmicaLyrics check counts.
///
/// Pass [httpClient] to control transport (e.g. a `MockClient` in tests);
/// otherwise `package:http`'s default client is used.
class YahooFuriganaClient {
  static const defaultAppId = String.fromEnvironment(
    'YAHOO_API_KEY',
    defaultValue:
        'dmVyPTIwMjUwNyZpZD16dUUwckt6Z0lJJmhhc2g9T0dWaFlqWmtNV1kyWWpFM01tVTRZZw', // Fallback for now so the app still works for the user
  );

  final String appId;
  final http.Client? httpClient;

  const YahooFuriganaClient({this.appId = defaultAppId, this.httpClient});

  /// Splits furigana into mora units, merging small kana, long vowel marks,
  /// and dakuten with the preceding mora.
  /// Based on RhythmicaLyrics SakuraYomiBunkai (routin_func.hsp:7077).
  List<String> _splitIntoMorae(String furigana) {
    final result = <String>[];
    final smallKana = RegExp(r'[ぁぃぅぇぉっゃゅょァィゥェォッャュョ]');
    final longVoiced = RegExp(r'[ー゛]');

    for (final ch in furigana.characters) {
      if (result.isNotEmpty &&
          (smallKana.hasMatch(ch) || longVoiced.hasMatch(ch))) {
        result.last += ch; // merge into preceding mora
      } else {
        result.add(ch);
      }
    }
    return result;
  }

  int _calculateTagCount(String surface, String furigana) {
    if (RegExp(r'^[a-zA-Z0-9]+$').hasMatch(surface)) return 1;
    return _splitIntoMorae(furigana).length;
  }

  /// Expands ruby nodes into interleaved [tag][text][tag][text]... structure.
  /// Based on RhythmicaLyrics SakuraYomiBunkai decomposition.
  List<LyricNode> _expandRubyNodes(int type, String surface, String furigana) {
    final morae = _splitIntoMorae(furigana);
    if (type <= 1 || morae.length <= 1) {
      return [LyricTimeTag(type: type, time: ''), LyricText(furigana)];
    }
    final expanded = <LyricNode>[];
    expanded.add(
      LyricTimeTag(type: type, time: ''),
    ); // first tag carries the type
    for (int i = 0; i < morae.length; i++) {
      expanded.add(LyricText(morae[i]));
      if (i < morae.length - 1) {
        expanded.add(LyricTimeTag(type: null, time: ''));
      }
    }
    return expanded;
  }

  List<({String surface, String? furigana})> _splitYahooWord(
    String surface,
    String? furigana,
    Object? subwords,
  ) {
    final wholeWord = [(surface: surface, furigana: furigana)];
    if (furigana == null ||
        furigana == surface ||
        subwords is! List ||
        subwords.isEmpty) {
      return wholeWord;
    }

    final parts = <({String surface, String? furigana})>[];
    for (final subword in subwords) {
      if (subword is! Map || subword['surface'] is! String) return wholeWord;
      final base = subword['surface'] as String;
      final reading = subword['furigana'];
      if (base.isEmpty ||
          (reading != null && (reading is! String || reading.isEmpty))) {
        return wholeWord;
      }
      parts.add((surface: base, furigana: reading as String?));
    }
    // Keep an indivisible reading on the whole word if Yahoo's subwords
    // cannot reconstruct both the original surface and its reading.
    if (parts.map((part) => part.surface).join() != surface ||
        parts.map((part) => part.furigana ?? part.surface).join() != furigana) {
      return wholeWord;
    }
    return parts;
  }

  /// Annotates each of [texts] with furigana. Returns one node list per
  /// input, whose concatenated surface equals the input text.
  Future<List<List<LyricNode>>> fetchBatch(List<String> texts) async {
    final joinedText = texts.join('\n');
    final url = Uri.parse(
      'https://jlp.yahooapis.jp/FuriganaService/V2/furigana',
    );
    final requestBody = {
      "id": "yuukilyrics",
      "jsonrpc": "2.0",
      "method": "jlp.furiganaservice.furigana",
      "params": {"q": joinedText, "grade": 1},
    };

    final post = httpClient?.post ?? http.post;
    final response = await post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Yahoo AppID: $appId',
      },
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid Yahoo API response.');
      }
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) {
        throw const FormatException('Yahoo API result is missing.');
      }
      final wordsValue = result['word'];
      if (wordsValue is! List) {
        throw const FormatException('Yahoo API word list is missing.');
      }
      final words = wordsValue;

      final wordsWithReadings = <({String surface, String? furigana})>[];
      final smallKanaRegex = RegExp(r'^[ぁぃぅぇぉっゃゅょァィゥェォッャュョー゛]+');

      for (final value in words) {
        if (value is! Map) {
          throw const FormatException('Invalid Yahoo API word entry.');
        }
        final surfaceValue = value['surface'];
        final furiganaValue = value['furigana'];
        if (surfaceValue is! String ||
            (furiganaValue != null && furiganaValue is! String)) {
          throw const FormatException('Invalid Yahoo API word fields.');
        }
        wordsWithReadings.addAll(
          _splitYahooWord(
            surfaceValue,
            furiganaValue as String?,
            value['subword'],
          ),
        );
      }

      final processedWords = <({String surface, String? furigana})>[];
      for (final (surface: surface, furigana: furigana) in wordsWithReadings) {
        final match = smallKanaRegex.firstMatch(surface);
        if (match != null && processedWords.isNotEmpty) {
          final kana = match.group(0)!;
          final prev = processedWords.last;
          if (!prev.surface.contains('\n') &&
              (furigana == null || furigana.startsWith(kana))) {
            processedWords.last = (
              surface: prev.surface + kana,
              furigana: prev.furigana == null ? null : prev.furigana! + kana,
            );
            final remainder = surface.substring(kana.length);
            if (remainder.isNotEmpty) {
              processedWords.add((
                surface: remainder,
                furigana: furigana?.substring(kana.length),
              ));
            }
            continue;
          }
        }
        processedWords.add((surface: surface, furigana: furigana));
      }

      final batchResults = <List<LyricNode>>[];
      var currentNodes = <LyricNode>[];

      for (final (surface: surface, furigana: furigana) in processedWords) {
        if (surface.contains('\n')) {
          final parts = surface.split('\n');
          for (int i = 0; i < parts.length; i++) {
            final part = parts[i];
            if (part.isNotEmpty) {
              currentNodes.add(LyricText(part));
            }
            if (i < parts.length - 1) {
              batchResults.add(currentNodes);
              currentNodes = [];
            }
          }
        } else {
          if (furigana != null && furigana.isNotEmpty && furigana != surface) {
            final int type = _calculateTagCount(surface, furigana);
            currentNodes.add(
              LyricRuby(
                baseText: surface,
                rubyNodes: _expandRubyNodes(type, surface, furigana),
              ),
            );
          } else {
            currentNodes.add(LyricText(surface));
          }
        }
      }
      batchResults.add(currentNodes);
      if (batchResults.length != texts.length) {
        throw FormatException(
          'Yahoo API returned ${batchResults.length} lines for '
          '${texts.length} inputs.',
        );
      }
      return batchResults;
    }
    throw HttpException(
      'Yahoo API request failed with status ${response.statusCode}.',
      uri: url,
    );
  }
}
