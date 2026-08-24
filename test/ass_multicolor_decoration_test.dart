import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/ass_exporter.dart';
import 'package:yuukilyrics/services/font_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'mille-feuille decoration uses dense pre-blurred colour bands',
    () async {
      final milleFeuille = AssColorValue.withStops(
        mode: AssColorMode.millefeuille,
        stops: const [
          AssColorStop(position: 0, color: Color(0xFF43A5D9)),
          AssColorStop(position: 0.33, color: Color(0xFFFFC561)),
          AssColorStop(position: 0.66, color: Color(0xFFFCDC59)),
          AssColorStop(position: 1, color: Color(0xFF808080)),
        ],
      );
      final document = LyricDocument(
        lines: [
          LyricLine(
            nodes: [
              LyricTimeTag(time: '00:01:00'),
              LyricText('永'),
              LyricTimeTag(type: 10, time: '00:02:00'),
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
        sungDecorationColor: milleFeuille,
        unsungTextColor: const AssColorValue.solid(Color(0xFFEBEBEB)),
        unsungOutlineColor: const AssColorValue.solid(Color(0xFF000000)),
        unsungDecorationColor: milleFeuille,
        fontSize: 120,
        pagingMode: AssPagingMode.auto2Lines,
        interludeThresholdSeconds: 10,
        horizontalMargin: 100,
        outlineWidth: 10,
        fontOutlineWidth: 10,
        blurLevel: 0,
        resolutionHeight: 1080,
      );

      final ass = await AssExporter.generateAss(document, settings);
      final decorationLines = ass
          .split('\n')
          .where(
            (line) =>
                line.startsWith('Dialogue: 0,') &&
                line.contains(r'\bord15.0\blur10.0') &&
                line.contains(r'\clip(0,'),
          )
          .toList();

      // N3 applies Gaussian blur to the complete hard-banded brush. The ASS
      // approximation therefore samples many narrow, already blended colours
      // instead of emitting only the three large source-colour stripes.
      expect(decorationLines.length, greaterThan(80));
      final colors = decorationLines
          .map(
            (line) => RegExp(r'\\1c(&H[0-9A-F]+&)').firstMatch(line)?.group(1),
          )
          .whereType<String>()
          .toSet();
      expect(colors.length, greaterThan(20));

      final clips = decorationLines
          .map(
            (line) => RegExp(
              r'\\clip\(0,([0-9.]+),10000,([0-9.]+)\)',
            ).firstMatch(line),
          )
          .whereType<RegExpMatch>()
          .map(
            (match) =>
                (double.parse(match.group(1)!), double.parse(match.group(2)!)),
          )
          .where((clip) => clip.$2 - clip.$1 < 10)
          .toList();
      expect(clips, isNotEmpty);
      expect(
        clips.map((clip) => clip.$2 - clip.$1).reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(2.1),
      );
    },
  );

  test('smooth gradient decoration is sampled at output-pixel scale', () async {
    final gradient = AssColorValue.withStops(
      mode: AssColorMode.gradient,
      stops: const [
        AssColorStop(position: 0, color: Color(0xFF2DC3C7)),
        AssColorStop(position: 0.4, color: Color(0xFF27A8AB)),
        AssColorStop(position: 0.6, color: Color(0xFFED9264)),
        AssColorStop(position: 1, color: Color(0xFFE2772B)),
      ],
    );
    final document = LyricDocument(
      lines: [
        LyricLine(
          nodes: [
            LyricTimeTag(time: '00:01:00'),
            LyricText('永'),
            LyricTimeTag(type: 10, time: '00:02:00'),
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
      sungDecorationColor: gradient,
      unsungTextColor: const AssColorValue.solid(Color(0xFFEBEBEB)),
      unsungOutlineColor: const AssColorValue.solid(Color(0xFF000000)),
      unsungDecorationColor: gradient,
      fontSize: 120,
      pagingMode: AssPagingMode.auto2Lines,
      interludeThresholdSeconds: 10,
      horizontalMargin: 100,
      outlineWidth: 10,
      fontOutlineWidth: 10,
      blurLevel: 0,
      resolutionHeight: 1080,
    );

    final ass = await AssExporter.generateAss(document, settings);
    final decorationLines = ass
        .split('\n')
        .where(
          (line) =>
              line.startsWith('Dialogue: 0,') &&
              line.contains(r'\bord15.0\blur10.0') &&
              line.contains(r'\clip(0,'),
        )
        .toList();
    expect(decorationLines.length, greaterThan(80));
    final colors = decorationLines
        .map((line) => RegExp(r'\\1c(&H[0-9A-F]+&)').firstMatch(line)?.group(1))
        .whereType<String>()
        .toSet();
    expect(colors.length, greaterThan(40));
  });
}
