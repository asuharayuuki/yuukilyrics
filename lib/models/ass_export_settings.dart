import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show Color;

import 'font_library_asset.dart';

// Settings and color types shared by the ASS export screen and the ASS
// exporter. Kept free of UI code so services can depend on them.

enum AssPagingMode { auto2Lines, emptyLineDelimited }

enum AssLineAlignment { left, center, right }

const List<AssLineAlignment> kDefaultTwoLineAlignments = [
  AssLineAlignment.left,
  AssLineAlignment.right,
];

const List<AssLineAlignment> kDefaultThreeLineAlignments = [
  AssLineAlignment.left,
  AssLineAlignment.center,
  AssLineAlignment.right,
];

const List<AssLineAlignment> kDefaultFourLineAlignments = [
  AssLineAlignment.left,
  AssLineAlignment.left,
  AssLineAlignment.center,
  AssLineAlignment.right,
];

enum AssColorMode { solid, gradient, millefeuille }

@immutable
class AssColorStop {
  final double position;
  final Color color;

  const AssColorStop({required this.position, required this.color});
}

enum SingerColorPreset {
  none,
  blue,
  standard,
  chorus,
  blue2,
  purple,
  bluePurple,
  ciel,
  sooda,
  kusou,
  lachenalia,
}

@immutable
class AssColorValue {
  final AssColorMode mode;
  final Color color0;
  final Color color100;
  final List<AssColorStop> stops;

  const AssColorValue.solid(Color color)
    : mode = AssColorMode.solid,
      color0 = color,
      color100 = color,
      stops = const [];

  const AssColorValue.gradient({required this.color0, required this.color100})
    : mode = AssColorMode.gradient,
      stops = const [];

  AssColorValue.withStops({
    required this.mode,
    required List<AssColorStop> stops,
  }) : assert(mode != AssColorMode.solid),
       stops = List.unmodifiable(_normalizeAssStops(stops)),
       color0 = _normalizeAssStops(stops).first.color,
       color100 = _normalizeAssStops(stops).last.color;

  bool get isGradient => mode != AssColorMode.solid;
  bool get isMillefeuille => mode == AssColorMode.millefeuille;

  List<AssColorStop> get effectiveStops => stops.isNotEmpty
      ? stops
      : [
          AssColorStop(position: 0, color: color0),
          AssColorStop(position: 1, color: color100),
        ];
}

List<AssColorStop> _normalizeAssStops(Iterable<AssColorStop> source) {
  final indexed = source.indexed.toList()
    ..sort((a, b) {
      final result = a.$2.position.compareTo(b.$2.position);
      return result != 0 ? result : a.$1.compareTo(b.$1);
    });
  if (indexed.isEmpty) {
    throw ArgumentError('At least one color stop is required.');
  }
  return indexed
      .map(
        (entry) => AssColorStop(
          position: entry.$2.position.clamp(0.0, 1.0),
          color: entry.$2.color,
        ),
      )
      .toList(growable: false);
}

class SingerColorInfo {
  String prefix;
  SingerColorPreset preset;
  AssColorValue sungTextColor;
  AssColorValue sungOutlineColor;
  AssColorValue sungDecorationColor;
  AssColorValue unsungTextColor;
  AssColorValue unsungOutlineColor;
  AssColorValue unsungDecorationColor;

  SingerColorInfo({
    required this.prefix,
    this.preset = SingerColorPreset.none,
    required this.sungTextColor,
    required this.sungOutlineColor,
    required this.sungDecorationColor,
    required this.unsungTextColor,
    required this.unsungOutlineColor,
    required this.unsungDecorationColor,
  });

  SingerColorInfo copy() {
    return SingerColorInfo(
      prefix: prefix,
      preset: preset,
      sungTextColor: sungTextColor,
      sungOutlineColor: sungOutlineColor,
      sungDecorationColor: sungDecorationColor,
      unsungTextColor: unsungTextColor,
      unsungOutlineColor: unsungOutlineColor,
      unsungDecorationColor: unsungDecorationColor,
    );
  }
}

@immutable
class AssExportSettings {
  final String fontName;
  final String? customFontPath;
  final int fontFaceIndex;
  final FontFaceSelection? latinFont;
  final bool fadeLyricLines;
  final bool isBold;
  final List<SingerColorInfo> singerColors;
  final bool showSingerPrefixesInAss;
  final AssColorValue sungTextColor;
  final AssColorValue sungOutlineColor;
  final AssColorValue sungDecorationColor;
  final AssColorValue unsungTextColor;
  final AssColorValue unsungOutlineColor;
  final AssColorValue unsungDecorationColor;
  final int fontSize;
  final double? letterSpacingEm;
  final AssPagingMode pagingMode;
  final List<AssLineAlignment> twoLineAlignments;
  final List<AssLineAlignment> threeLineAlignments;
  final List<AssLineAlignment> fourLineAlignments;
  final int interludeThresholdSeconds;
  final int horizontalMargin;
  final int outlineWidth;
  final int? fontOutlineWidth;
  final int? rubyFontSize;
  final int? rubyOutlineWidth;
  final int? rubyBaseGap;
  final int? lineSpacing;
  final int lyricsBottomMargin;
  final int? singerAvatarSize;
  final int singerAvatarGap;
  final Map<String, String> singerAvatarPaths;
  final int blurLevel;
  final int resolutionHeight;

  AssExportSettings({
    required this.fontName,
    this.customFontPath,
    this.fontFaceIndex = 0,
    this.latinFont,
    this.fadeLyricLines = false,
    required this.isBold,
    required this.singerColors,
    required this.showSingerPrefixesInAss,
    required this.sungTextColor,
    required this.sungOutlineColor,
    required this.sungDecorationColor,
    required this.unsungTextColor,
    required this.unsungOutlineColor,
    required this.unsungDecorationColor,
    required this.fontSize,
    this.letterSpacingEm,
    required this.pagingMode,
    this.twoLineAlignments = kDefaultTwoLineAlignments,
    this.threeLineAlignments = kDefaultThreeLineAlignments,
    this.fourLineAlignments = kDefaultFourLineAlignments,
    required this.interludeThresholdSeconds,
    required this.horizontalMargin,
    required this.outlineWidth,
    this.fontOutlineWidth,
    this.rubyFontSize,
    this.rubyOutlineWidth,
    this.rubyBaseGap,
    this.lineSpacing,
    this.lyricsBottomMargin = 50,
    this.singerAvatarSize,
    this.singerAvatarGap = 0,
    this.singerAvatarPaths = const {},
    required this.blurLevel,
    required this.resolutionHeight,
  });
}
