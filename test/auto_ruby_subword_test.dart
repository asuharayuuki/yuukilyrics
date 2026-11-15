import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuukilyrics/l10n/generated/app_localizations.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/services/lyrics_state_service.dart';

void main() {
  testWidgets('auto ruby isolates okurigana and preserves the first time tag', (
    tester,
  ) async {
    final lyrics = LyricsStateService()
      ..loadLrcText('[00:12:30]振る今日[10|00:13:00]');
    addTearDown(lyrics.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => http.runWithClient(
                () => lyrics.autoRubyAndTagDocument(context),
                () => MockClient((request) async {
                  final body = jsonDecode(request.body) as Map;
                  expect((body['params'] as Map)['q'], '振る今日');
                  return http.Response(
                    jsonEncode({
                      'result': {
                        'word': [
                          {
                            'surface': '振る',
                            'furigana': 'ふる',
                            'subword': [
                              {'surface': '振', 'furigana': 'ふ'},
                              {'surface': 'る'},
                            ],
                          },
                          {
                            'surface': '今日',
                            'furigana': 'きょう',
                            'subword': [
                              {'surface': '今', 'furigana': 'いま'},
                              {'surface': '日', 'furigana': 'ひ'},
                            ],
                          },
                        ],
                      },
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  );
                }),
              ),
              child: const Text('Annotate'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Annotate'));
    await tester.pumpAndSettle();

    final nodes = lyrics.document!.lines.single.nodes;
    final ruby = nodes.whereType<LyricRuby>().toList();
    expect(ruby.map((node) => node.baseText), ['振', '今日']);
    expect(ruby.first.rubyNodes.whereType<LyricText>().single.text, 'ふ');
    expect(
      ruby.first.rubyNodes.whereType<LyricTimeTag>().single.time,
      '00:12:30',
    );
    expect(nodes.whereType<LyricText>().single.text, 'る');
    expect((nodes.last as LyricTimeTag).time, '00:13:00');
  });
}
