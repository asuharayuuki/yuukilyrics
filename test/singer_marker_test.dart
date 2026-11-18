import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/parser/lrc_parser.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/ass_exporter.dart';
import 'package:yuukilyrics/services/auto_tagger.dart';
import 'package:yuukilyrics/services/font_service.dart';
import 'package:yuukilyrics/services/lyrics_state_service.dart';
import 'package:yuukilyrics/services/singer_markers.dart';
import 'package:yuukilyrics/services/yahoo_furigana_client.dart';

const _red = Color(0xFFFF0000);
const _redAss = '&H000000FF&';

SingerColorInfo _singer(String prefix, Color color) => SingerColorInfo(
  prefix: prefix,
  sungTextColor: AssColorValue.solid(color),
  sungOutlineColor: const AssColorValue.solid(Colors.black),
  sungDecorationColor: AssColorValue.solid(color),
  unsungTextColor: AssColorValue.solid(color),
  unsungOutlineColor: const AssColorValue.solid(Colors.black),
  unsungDecorationColor: AssColorValue.solid(color),
);

AssExportSettings _settings(List<SingerColorInfo> singers) {
  const white = AssColorValue.solid(Colors.white);
  const black = AssColorValue.solid(Colors.black);
  return AssExportSettings(
    fontName: FontService.bundledFontFamily,
    isBold: false,
    singerColors: singers,
    showSingerPrefixesInAss: false,
    sungTextColor: white,
    sungOutlineColor: black,
    sungDecorationColor: white,
    unsungTextColor: white,
    unsungOutlineColor: black,
    unsungDecorationColor: white,
    fontSize: 85,
    pagingMode: AssPagingMode.auto2Lines,
    interludeThresholdSeconds: 100,
    horizontalMargin: 50,
    outlineWidth: 2,
    blurLevel: 0,
    resolutionHeight: 1080,
  );
}

/// Visible glyphs of the unsung layer mapped to their ASS fill color.
Future<Map<String, String?>> _glyphColors(
  String lrc,
  List<SingerColorInfo> singers,
) async {
  final ass = await AssExporter.generateAss(
    LrcParser.parseDocument(lrc),
    _settings(singers),
  );
  return {
    for (final line in ass.split('\n'))
      if (line.startsWith('Dialogue:') && line.contains(',DefaultUnsung,'))
        line.substring(line.lastIndexOf('}') + 1): RegExp(
          r'\1c(&H[0-9A-F]+&)',
        ).firstMatch(line)?.group(1),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final markers = SingerMarkers(['A', 'B', 'A/B', '結城']);

  group('SingerMarkers', () {
    test('prefers the longest marker at the earliest position', () {
      expect(markers.split('A/B歌B'), [
        (text: 'A/B', isMarker: true),
        (text: '歌', isMarker: false),
        (text: 'B', isMarker: true),
      ]);
      expect(markers.lastMarker('A/B'), 'A/B');
      expect(markers.stripMarkers('結城歌'), '歌');
    });
  });

  test('palette highlights a duet marker, not the B inside it', () {
    final state = LyricsStateService()
      ..loadLrcText('A/B[1|00:01:00]歌[1|00:01:50]詞');
    addTearDown(state.dispose);
    state.setSelection(0, 2, 0, 1, 1); // 歌
    expect(state.matchingPrefixAtSelection(['A', 'B', 'A/B']), 'A/B');
  });

  group('auto tagging', () {
    LyricLine tag(String lrc) {
      final line = LrcParser.parseLine(lrc);
      AutoTagger.tagLines([line], markers: markers);
      return line;
    }

    test('gives markers no check of their own and never splits them', () {
      expect(tag('A歌詞').toLrcString(), 'A[1]歌[1]詞[10]');
      // Splitting 結城 into 結 and 城 used to make the exporter lose it.
      expect(tag('結城歌').toLrcString(), '結城[1]歌[10]');
      expect(tag('歌B詞').toLrcString(), '[1]歌B[1]詞[10]');
    });

    test('keeps a timed check on the syllable after the marker', () {
      expect(
        tag('[1|00:01:00]A{歌|うた}').toLrcString(),
        'A{歌|[1|00:01:00]うた}[10]',
      );
    });

    test('a line holding only a marker gets no line-end check', () {
      expect(tag('A').toLrcString(), 'A');
    });
  });

  test('auto ruby never sends a marker for a reading', () async {
    final state = LyricsStateService()..loadLrcText('結城歌');
    addTearDown(state.dispose);
    final queries = <String>[];
    await state.autoRubyAndTagDocument(
      markers: markers,
      client: YahooFuriganaClient(
        httpClient: MockClient((request) async {
          final q =
              ((jsonDecode(request.body) as Map)['params'] as Map)['q']
                  as String;
          queries.add(q);
          return http.Response(
            jsonEncode({
              'result': {
                'word': [
                  {'surface': q, 'furigana': 'うた'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    expect(queries, ['歌']);
    expect(state.rawText, '結城{歌|[2]うた}[10]');
  });

  test('ruby input keeps a selected leading marker outside the ruby', () {
    final state = LyricsStateService()..loadLrcText('A歌詞');
    addTearDown(state.dispose);
    state.setSelection(0, 0, 0, null, 2); // "A歌"
    state.updateRubyText('うた', markers: markers);
    expect(state.rawText, 'A{歌|うた}詞');

    // Selecting only the marker cannot give it a reading.
    final markerOnly = LyricsStateService()..loadLrcText('A歌');
    addTearDown(markerOnly.dispose);
    markerOnly.setSelection(0, 0, 0, null, 1);
    markerOnly.updateRubyText('えー', markers: markers);
    expect(markerOnly.rawText, 'A歌');
  });

  group('ASS export', () {
    final a = _singer('A', _red);

    test('a marker inside a ruby base still colors the line', () async {
      final colors = await _glyphColors('[00:01:00]{A歌|[1]か}[10|00:02:00]', [
        a,
      ]);
      expect(colors, {'歌': _redAss});
    });

    test('a kanji marker colors the line and is not drawn', () async {
      final colors = await _glyphColors(
        '[00:01:00]結城[00:01:10]歌[10|00:02:00]',
        [_singer('結城', _red)],
      );
      expect(colors, {'歌': _redAss});
    });
  });
}
