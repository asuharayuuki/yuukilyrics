import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/font_library_asset.dart';
import 'package:yuukilyrics/parser/lrc_parser.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/ass_exporter.dart';
import 'package:yuukilyrics/services/font_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final document = LrcParser.parseDocument(
    '[00:02:00]A１か{漢|[1|00:02:80]かん}[10|00:04:00]',
  );

  Iterable<String> lyricEvents(String ass) => ass
      .split('\n')
      .where(
        (line) =>
            line.startsWith('Dialogue:') &&
            (line.contains(',Default') || line.contains(',Ruby')),
      );

  test('each lyric event fades without changing its timing or clip', () async {
    final off = await AssExporter.generateAss(document, _settings());
    final on = await AssExporter.generateAss(document, _settings(fade: true));
    final events = lyricEvents(on).toList();

    expect(events, isNotEmpty);
    expect(events.any((line) => line.contains(',Ruby')), isTrue);
    expect(events.every((line) => line.contains(r'\fad(200,200)')), isTrue);
    expect(
      events.map((line) => line.replaceFirst(r'\fad(200,200)', '')),
      lyricEvents(off),
    );
  });

  test(
    'ASS selects the alternate face for Latin and fullwidth digits',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yuuki-font-test',
      );
      addTearDown(() async {
        final copied = File('${directory.path}/primary.ttf');
        if (await copied.exists()) await copied.delete();
        await directory.delete();
      });
      final primary = await File(
        FontService.bundledFontAsset,
      ).copy('${directory.path}/primary.ttf');
      final face = await FontService().loadSelectedFace();
      final ass = await AssExporter.generateAss(
        document,
        _settings(
          fontPath: primary.path,
          latinFont: const FontFaceSelection(
            path: null,
            faceIndex: 0,
            displayName: FontService.bundledFontFamily,
            styleName: 'Regular',
          ),
        ),
      );

      expect(ass, contains('Style: DefaultUnsung,${face.info.assFaceName},'));
      expect(ass, contains('Style: RubyUnsung,${face.info.assFaceName},'));
      for (final char in ['A', '１', 'か', '漢']) {
        final lines = lyricEvents(ass).where((line) => line.endsWith('}$char'));
        expect(lines, isNotEmpty, reason: char);
        for (final line in lines) {
          if (char == 'A' || char == '１') {
            expect(line, contains('\\fn${face.info.postScriptName}\\'));
          } else {
            expect(line, isNot(contains(r'\fn')));
          }
        }
      }
    },
  );
}

AssExportSettings _settings({
  bool fade = false,
  String? fontPath,
  FontFaceSelection? latinFont,
}) {
  const white = AssColorValue.solid(Colors.white);
  const black = AssColorValue.solid(Colors.black);
  return AssExportSettings(
    fontName: FontService.bundledFontFamily,
    customFontPath: fontPath,
    latinFont: latinFont,
    fadeLyricLines: fade,
    isBold: false,
    singerColors: const [],
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
