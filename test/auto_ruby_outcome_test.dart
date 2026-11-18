import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/services/lyrics_state_service.dart';
import 'package:yuukilyrics/services/yahoo_furigana_client.dart';

YahooFuriganaClient _client(MockClientHandler handler) =>
    YahooFuriganaClient(httpClient: MockClient(handler));

/// Answers every furigana request by giving each input line one word whose
/// reading is "よみ".
http.Response _echoReadings(http.Request request) {
  final body = jsonDecode(request.body) as Map;
  final lines = ((body['params'] as Map)['q'] as String).split('\n');
  final words = <Map<String, String>>[];
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) words.add({'surface': '\n'});
    words.add({'surface': lines[i], 'furigana': 'よみ'});
  }
  return http.Response(
    jsonEncode({
      'result': {'word': words},
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  // Each line is long enough that the two land in separate API batches.
  final firstLine = '漢' * 1500;
  final secondLine = '字' * 1000;

  test(
    'stopping keeps fetched readings and leaves later lines alone',
    () async {
      final lyrics = LyricsStateService()
        ..loadLrcText('$firstLine\n$secondLine');
      addTearDown(lyrics.dispose);
      var requests = 0;

      final outcome = await lyrics.autoRubyAndTagDocument(
        client: _client((request) async {
          requests++;
          return _echoReadings(request);
        }),
        isCancelled: () => requests >= 1,
      );

      expect(outcome, AutoRubyOutcome.cancelled);
      expect(requests, 1);
      final lines = lyrics.document!.lines;
      final ruby = lines[0].nodes.whereType<LyricRuby>().single;
      expect(ruby.baseText, firstLine);
      expect((lines[0].nodes.last as LyricTimeTag).type, 10);
      // The second line was never fetched, so it must not be split into
      // per-character checks.
      expect(lines[1].nodes, hasLength(1));
      expect((lines[1].nodes.single as LyricText).text, secondLine);
    },
  );

  test('a document replaced mid-request is not modified', () async {
    final lyrics = LyricsStateService()..loadLrcText('漢字');
    addTearDown(lyrics.dispose);

    final outcome = await lyrics.autoRubyAndTagDocument(
      client: _client((request) async {
        lyrics.loadLrcText('[00:01:00]別の歌詞');
        return _echoReadings(request);
      }),
    );

    expect(outcome, AutoRubyOutcome.documentChanged);
    expect(lyrics.rawText, '[00:01:00]別の歌詞');
  });

  test('API errors are rethrown without touching the document', () async {
    final lyrics = LyricsStateService()..loadLrcText('漢字');
    addTearDown(lyrics.dispose);

    await expectLater(
      lyrics.autoRubyAndTagDocument(
        client: _client((_) async => http.Response('', 500)),
      ),
      throwsA(isA<HttpException>()),
    );
    expect(lyrics.rawText, '漢字');
  });
}
