import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/ass_exporter.dart';
import 'package:yuukilyrics/services/font_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('blank-line pages use N3 bottom-aligned 3/4-line geometry', () async {
    final twoLinePositions = await _exportPositions(2);
    final threeLinePositions = await _exportPositions(3);
    final fourLinePositions = await _exportPositions(4);

    expect(kDefaultThreeLineAlignments, const [
      AssLineAlignment.left,
      AssLineAlignment.center,
      AssLineAlignment.right,
    ]);
    expect(kDefaultFourLineAlignments, const [
      AssLineAlignment.left,
      AssLineAlignment.left,
      AssLineAlignment.center,
      AssLineAlignment.right,
    ]);

    expect(twoLinePositions, hasLength(2));
    expect(threeLinePositions, hasLength(3));
    expect(fourLinePositions, hasLength(4));

    // N3 SmartHorizon.Multi includes the center column when balancing a page,
    // so the three-line left column sits farther out than the two-line one.
    expect(threeLinePositions[0].$1, lessThan(twoLinePositions[0].$1));
    expect(threeLinePositions[1].$1, closeTo(960, 0.5));
    expect(threeLinePositions[2].$1, greaterThan(960));

    // A four-line page falls back to the three-line N3 layout from the bottom:
    // left, left, center, right. Both left rows share one horizontal column.
    expect(fourLinePositions[0].$1, closeTo(fourLinePositions[1].$1, 0.1));
    expect(fourLinePositions[0].$1, closeTo(threeLinePositions[0].$1, 0.1));
    expect(fourLinePositions[2].$1, closeTo(960, 0.5));
    expect(fourLinePositions[3].$1, greaterThan(960));
  });
}

Future<List<(double, double)>> _exportPositions(int lineCount) async {
  final lines = <LyricLine>[];
  for (var index = 0; index < lineCount; index++) {
    final startSecond = 10 + index;
    lines.add(
      LyricLine(
        nodes: [
          LyricTimeTag(time: '00:$startSecond:00'),
          LyricText('行'),
          LyricTimeTag(type: 10, time: '00:${startSecond + 1}:00'),
        ],
      ),
    );
  }
  lines.add(LyricLine(nodes: const []));

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

  final ass = await AssExporter.generateAss(
    LyricDocument(lines: lines),
    settings,
  );
  final positions =
      RegExp(r'\\pos\(([0-9.]+),([0-9.]+)\)[^\r\n]*\}行\r?$', multiLine: true)
          .allMatches(ass)
          .map(
            (match) =>
                (double.parse(match.group(1)!), double.parse(match.group(2)!)),
          )
          .toSet()
          .toList()
        ..sort((first, second) => first.$2.compareTo(second.$2));
  return positions;
}
