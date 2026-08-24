import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/ass_exporter.dart';
import 'package:yuukilyrics/services/font_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'wide ruby above a narrow base does not overlap the next ruby',
    () async {
      final document = LyricDocument(
        lines: [
          LyricLine(
            nodes: [
              LyricRuby(
                baseText: '1',
                rubyNodes: [
                  LyricTimeTag(type: 2, time: '02:08:16'),
                  LyricText('い'),
                  LyricTimeTag(time: '02:08:32'),
                  LyricText('ち'),
                ],
              ),
              LyricRuby(
                baseText: '番',
                rubyNodes: [
                  LyricTimeTag(type: 2, time: '02:08:45'),
                  LyricText('ば'),
                  LyricTimeTag(time: '02:08:64'),
                  LyricText('ん'),
                ],
              ),
              LyricTimeTag(type: 10, time: '02:08:82'),
            ],
          ),
        ],
      );
      final settings = AssExportSettings(
        fontName: FontService.bundledFontFamily,
        isBold: true,
        singerColors: const [],
        showSingerPrefixesInAss: false,
        sungTextColor: const AssColorValue.solid(Color(0xFF012595)),
        sungOutlineColor: const AssColorValue.solid(Color(0xFFFFFFFF)),
        sungDecorationColor: const AssColorValue.solid(Color(0xFFE1E196)),
        unsungTextColor: const AssColorValue.solid(Color(0xFFEBEBEB)),
        unsungOutlineColor: const AssColorValue.solid(Color(0xFF000000)),
        unsungDecorationColor: const AssColorValue.solid(Color(0xFFE1E196)),
        fontSize: 85,
        pagingMode: AssPagingMode.emptyLineDelimited,
        interludeThresholdSeconds: 100,
        horizontalMargin: 50,
        outlineWidth: 2,
        blurLevel: 0,
        resolutionHeight: 1080,
      );

      final ass = await AssExporter.generateAss(document, settings);
      final rubyCenters = <String, double>{};
      for (final character in ['い', 'ち', 'ば', 'ん']) {
        final matches = RegExp(
          '\\\\pos\\(([0-9.]+),[0-9.]+\\)[^\\r\\n]*\\}$character\\r?\$',
          multiLine: true,
        ).allMatches(ass);
        final centers = matches
            .map((match) => double.parse(match.group(1)!))
            .toSet();
        expect(
          centers,
          hasLength(1),
          reason: 'missing ruby position for $character',
        );
        rubyCenters[character] = centers.single;
      }

      final firstRubyAdvance = rubyCenters['ち']! - rubyCenters['い']!;
      final gapToNextRuby = rubyCenters['ば']! - rubyCenters['ち']!;
      // Different kana have slightly different side bearings, so compare the
      // cross-node distance with the normal in-run advance using a small glyph
      // tolerance. Before the fix this distance collapses to roughly half.
      expect(gapToNextRuby, greaterThanOrEqualTo(firstRubyAdvance * 0.9));
    },
  );
}
