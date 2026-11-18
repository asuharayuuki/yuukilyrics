part of '../ass_exporter.dart';

// Glyph metrics, spacing, line wrapping and text placement.

double _getCharWidth(
  String text,
  double fontSize,
  double spacing,
  _AssTextMetrics textMetrics,
) {
  return textMetrics.layoutWidth(text, fontSize, spacing);
}

bool _isWideGrapheme(String char) {
  if (char.isEmpty) return false;
  final code = char.runes.first;
  return (code >= 0x3000 && code <= 0x9FFF) ||
      (code >= 0xF900 && code <= 0xFAFF) ||
      (code >= 0xFF00 && code <= 0xFFEF) ||
      (code >= 0x1F000 && code <= 0x1FAFF) ||
      (code >= 0x20000 && code <= 0x3FFFF) ||
      code == 0x25CF;
}

double _spacingForGrapheme(String char, double wideSpacing) {
  if (_isWideGrapheme(char)) return wideSpacing;
  return 0;
}

double _trailingSpacing(String text, double wideSpacing) {
  if (text.characters.isEmpty) return 0;
  return _spacingForGrapheme(text.characters.last, wideSpacing);
}

List<String> _splitAssTextRuns(String text) {
  final runs = <String>[];
  final narrowRun = StringBuffer();

  void flushNarrowRun() {
    if (narrowRun.isEmpty) return;
    runs.add(narrowRun.toString());
    narrowRun.clear();
  }

  for (final char in text.characters) {
    if (_isWideGrapheme(char)) {
      flushNarrowRun();
      runs.add(char);
    } else {
      narrowRun.write(char);
    }
  }
  flushNarrowRun();
  return runs;
}

List<String> _splitTextForLineWrap(String text, _AssTextMetrics textMetrics) {
  final units = <String>[];
  for (final run in _splitAssTextRuns(text)) {
    if (_isWideGrapheme(run)) {
      if (units.isNotEmpty && _isKinsoku(run)) {
        units[units.length - 1] += run;
      } else {
        units.add(run);
      }
      continue;
    }

    for (final token in textMetrics.tokenize(run)) {
      if (units.isNotEmpty &&
          !token.isWord &&
          !token.isWhitespace &&
          token.text.characters.every(_isKinsoku)) {
        units[units.length - 1] += token.text;
      } else {
        units.add(token.text);
      }
    }
  }
  return units;
}

List<_AssTextPlacement> _layoutAssText({
  required String text,
  required double centerX,
  required double fontSize,
  required double spacing,
  required _AssTextMetrics textMetrics,
}) => textMetrics.layoutText(
  text,
  centerX: centerX,
  fontSize: fontSize,
  spacing: spacing,
);

_AssTextPlacement? _firstVisibleAssPlacement({
  required List<LyricNode> row,
  required double fontSize,
  required double spacing,
  required double? letterSpacingEm,
  required int? rubyFontSize,
  required _AssTextMetrics textMetrics,
}) {
  double currentX = 0;
  for (final node in row) {
    String? text;
    double width = 0;
    if (node is LyricText) {
      text = node.text;
      width = _getCharWidth(text, fontSize, spacing, textMetrics);
    } else if (node is LyricRuby) {
      text = node.baseText;
      width = _getRubyNodeWidth(
        node,
        fontSize,
        spacing,
        letterSpacingEm,
        rubyFontSize,
        textMetrics,
      );
    }
    if (text == null) continue;

    final placements = _layoutAssText(
      text: text,
      centerX: currentX + width / 2,
      fontSize: fontSize,
      spacing: spacing,
      textMetrics: textMetrics,
    );
    if (placements.isNotEmpty) return placements.first;
    currentX += width;
  }
  return null;
}

double _resolveSpacing(double fontSize, double? letterSpacingEm) {
  if (letterSpacingEm == null) return 0;
  return fontSize * letterSpacingEm;
}

double _resolveRubySpacing(double rubyFontSize, double? letterSpacingEm) {
  if (letterSpacingEm == null) {
    return _resolveSpacing(rubyFontSize, null);
  }
  return rubyFontSize * letterSpacingEm;
}

double _resolveRubyFontSize(double fontSize, int? rubyFontSize) {
  return rubyFontSize?.toDouble() ?? (fontSize * 36 / 75).roundToDouble();
}

double _resolveFontOutlineWidth(double fontSize, int? fontOutlineWidth) {
  if (fontOutlineWidth != null) return fontOutlineWidth.toDouble();
  final width = (fontSize * 7 / 85).roundToDouble();
  return width < 1 ? 1.0 : width;
}

double _resolveRubyBaseOutlineWidth(
  double baseOutlineWidth,
  double fontSize,
  double rubyFontSize,
  int? rubyOutlineWidth,
) {
  if (rubyOutlineWidth != null) return rubyOutlineWidth.toDouble();
  final defaultRubyFontSize = _resolveRubyFontSize(fontSize, null);
  final scale = defaultRubyFontSize > 0
      ? rubyFontSize / defaultRubyFontSize
      : 1.0;
  final width = (baseOutlineWidth * 5 / 7 * scale).roundToDouble();
  return width < 1 ? 1.0 : width;
}

String _formatAssNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

Duration _getLineStartTime(LyricLine line) {
  for (var node in line.nodes) {
    if (node is LyricTimeTag && node.time.isNotEmpty) {
      return _parseTime(node.time);
    }
    if (node is LyricRuby) {
      for (var rNode in node.rubyNodes) {
        if (rNode is LyricTimeTag && rNode.time.isNotEmpty) {
          return _parseTime(rNode.time);
        }
      }
    }
  }
  return Duration.zero;
}

Duration _getLineEndTime(LyricLine line, Duration defaultStart) {
  Duration lastTime = defaultStart;
  for (var node in line.nodes) {
    if (node is LyricTimeTag && node.time.isNotEmpty) {
      lastTime = _parseTime(node.time);
    }
    if (node is LyricRuby) {
      for (var rNode in node.rubyNodes) {
        if (rNode is LyricTimeTag && rNode.time.isNotEmpty) {
          lastTime = _parseTime(rNode.time);
        }
      }
    }
  }
  return lastTime;
}

double _getTextContentWidth(
  String text,
  double fontSize,
  double spacing,
  _AssTextMetrics textMetrics,
) {
  if (text.characters.isEmpty) return 0;
  return _getCharWidth(text, fontSize, spacing, textMetrics) -
      _trailingSpacing(text, spacing);
}

double _getRubyNodeWidth(
  LyricRuby node,
  double fs,
  double spacing,
  double? letterSpacingEm,
  int? customRubyFontSize,
  _AssTextMetrics textMetrics,
) {
  final baseContentW = _getTextContentWidth(
    node.baseText,
    fs,
    spacing,
    textMetrics,
  );

  double rubyFs = _resolveRubyFontSize(fs, customRubyFontSize);
  double rubySpacing = _resolveRubySpacing(rubyFs, letterSpacingEm);
  final rubyText = StringBuffer();

  for (var rNode in node.rubyNodes) {
    if (rNode is LyricText) {
      rubyText.write(rNode.text.replaceAll('＋', ''));
    }
  }
  final rubyVisibleText = rubyText.toString();
  final rubyContentW = _getTextContentWidth(
    rubyVisibleText,
    rubyFs,
    rubySpacing,
    textMetrics,
  );
  final baseBlockSpacing = _trailingSpacing(node.baseText, spacing);
  final rubyBlockSpacing = _trailingSpacing(rubyVisibleText, rubySpacing);
  final baseBlockW = baseContentW > 0 ? baseContentW + baseBlockSpacing : 0.0;
  final rubyBlockW = rubyContentW > 0 ? rubyContentW + rubyBlockSpacing : 0.0;
  // N3 resolves interference between adjacent ruby runs by moving the later
  // base/ruby group to the right. Reserving the wider block is the ASS layout
  // equivalent: a narrow base such as "1" must not advance by less than its
  // wider ruby (for example "いち"), or the following ruby will overlap it.
  return baseBlockW > rubyBlockW ? baseBlockW : rubyBlockW;
}

double _getLineWidth(
  LyricLine line,
  double fs,
  double spacing,
  double? letterSpacingEm,
  int? rubyFontSize,
  _AssTextMetrics textMetrics,
) {
  double w = 0;
  for (var node in line.nodes) {
    if (node is LyricText) {
      w += _getCharWidth(node.text, fs, spacing, textMetrics);
    } else if (node is LyricRuby) {
      w += _getRubyNodeWidth(
        node,
        fs,
        spacing,
        letterSpacingEm,
        rubyFontSize,
        textMetrics,
      );
    }
  }
  return w;
}

List<LyricNode> _splitTextNodesForAssGrid(
  List<LyricNode> nodes,
  Map<LyricNode, Duration> nodeStartTimes,
  Map<LyricNode, Duration> nodeEndTimes,
  double fs,
  double spacing,
  _AssTextMetrics textMetrics,
) {
  final result = <LyricNode>[];

  for (final node in nodes) {
    if (node is _SingerMarkerNode) {
      result.add(node);
      continue;
    }
    if (node is! LyricText) {
      result.add(node);
      continue;
    }

    final runs = _splitAssTextRuns(node.text);
    if (runs.length <= 1) {
      result.add(node);
      continue;
    }

    final widths = runs
        .map((run) => _getCharWidth(run, fs, spacing, textMetrics))
        .toList();
    final totalWidth = widths.fold(0.0, (sum, width) => sum + width);
    final start = nodeStartTimes[node];
    final end = nodeEndTimes[node];
    int totalMs = start != null && end != null
        ? (end - start).inMilliseconds
        : 0;
    if (totalMs < 0) totalMs = 0;
    double accumulatedWidth = 0;

    for (int i = 0; i < runs.length; i++) {
      final splitNode = LyricText(runs[i]);
      result.add(splitNode);

      if (start != null && end != null && totalWidth > 0) {
        final partStartMs = (totalMs * accumulatedWidth / totalWidth).round();
        accumulatedWidth += widths[i];
        final partEndMs = i == runs.length - 1
            ? totalMs
            : (totalMs * accumulatedWidth / totalWidth).round();
        nodeStartTimes[splitNode] = start + Duration(milliseconds: partStartMs);
        nodeEndTimes[splitNode] = start + Duration(milliseconds: partEndMs);
      }
    }
  }

  return result;
}

bool _isKinsoku(String char) {
  if (char.isEmpty) return false;
  return 'ぁぃぅぇぉっゃゅょゎ゛゜ゝゞァィゥェォッャュョヮヵヶ・ーヽヾ！％），．：；？］｝｡｣､･、。々〉》」』】〕!%),.:;?]}'
      .contains(char);
}

class _AssTextPlacement {
  final String text;
  final double centerX;
  final double visualLeft;
  final String alignmentTag;
  final double centerYOffset;

  const _AssTextPlacement({
    required this.text,
    required this.centerX,
    required this.visualLeft,
    required this.alignmentTag,
    required this.centerYOffset,
  });
}

class _AssTextMetrics {
  final OpenTypeFontFace fontFace;
  final OpenTypeFontFace? latinFontFace;
  final double baseFontSize;
  final double baseOutlineWidth;
  final double baseLayoutEdgeWidth;
  final double rubyFontSize;
  final double rubyOutlineWidth;
  final double rubyLayoutEdgeWidth;
  final Map<String, double> _widthCache = {};
  final Map<String, _N3GlyphLayout> _glyphLayoutCache = {};

  _AssTextMetrics({
    required this.fontFace,
    this.latinFontFace,
    required this.baseFontSize,
    required this.baseOutlineWidth,
    required this.baseLayoutEdgeWidth,
    required this.rubyFontSize,
    required this.rubyOutlineWidth,
    required this.rubyLayoutEdgeWidth,
  });

  static bool _isWhitespace(String char) {
    return char == ' ' || char == '\t';
  }

  List<_AssNarrowToken> tokenize(String text) {
    final tokens = <_AssNarrowToken>[];
    final buffer = StringBuffer();
    bool? currentWhitespace;

    void flush() {
      if (buffer.isEmpty || currentWhitespace == null) return;
      final tokenText = buffer.toString();
      tokens.add(
        _AssNarrowToken(
          text: tokenText,
          isWord: currentWhitespace == false,
          isWhitespace: currentWhitespace,
        ),
      );
      buffer.clear();
    }

    for (final char in text.characters) {
      final whitespace = _isWhitespace(char);
      if (currentWhitespace != whitespace) {
        flush();
        currentWhitespace = whitespace;
      }
      buffer.write(char);
    }
    flush();
    return tokens;
  }

  double layoutWidth(String text, double fontSize, double spacing) {
    final key = 'layout\u0000$fontSize\u0000$spacing\u0000$text';
    final cached = _widthCache[key];
    if (cached != null) return cached;

    var width = 0.0;
    for (final char in text.characters) {
      width += _glyphLayout(char, fontSize).drawWidth + spacing;
    }
    _widthCache[key] = width;
    return width;
  }

  double assFontSize(double fontSize, [OpenTypeFontFace? selectedFace]) {
    // N3 treats the requested size as an em; libass normalizes it to the
    // hhea line box, so compensate with metrics from the selected font file.
    final face = selectedFace ?? fontFace;
    final metricsHeight = face.ascent + face.descent;
    if (face.unitsPerEm <= 0 || metricsHeight <= 0) return fontSize;
    return fontSize * metricsHeight / face.unitsPerEm;
  }

  static double _baselineFromCenter(OpenTypeFontFace face, double fontSize) =>
      fontSize * (face.ascent - face.descent) / (2 * face.unitsPerEm);

  static final _latinOrDigit = RegExp(
    r'^[\p{Script=Latin}\p{Nd}]',
    unicode: true,
  );

  OpenTypeFontFace _faceFor(String char) {
    final alternate = latinFontFace;
    if (alternate != null &&
        _latinOrDigit.hasMatch(char) &&
        alternate.metricsForCodePoint(char.runes.first).glyphId != 0) {
      return alternate;
    }
    return fontFace;
  }

  double assCenterYForDrawBottom(double drawBottom, double fontSize) {
    final metricsHeight = fontFace.ascent + fontFace.descent;
    if (fontFace.unitsPerEm <= 0 || metricsHeight <= 0) {
      return drawBottom - fontSize / 2 - _layoutEdgeWidth(fontSize) / 2;
    }
    final directWriteDescent = fontSize * fontFace.descent / metricsHeight;
    final assBaselineFromCenter = _baselineFromCenter(fontFace, fontSize);
    return drawBottom -
        directWriteDescent -
        _layoutEdgeWidth(fontSize) / 2 -
        assBaselineFromCenter;
  }

  double drawBottomForAssCenter(double centerY, double fontSize) {
    final offset = assCenterYForDrawBottom(0, fontSize);
    return centerY - offset;
  }

  double rubyCenterYFromBaseCenter(
    double baseCenterY, {
    required double baseFontSize,
    required double rubyFontSize,
    required double rubyGap,
  }) {
    final baseDrawBottom = drawBottomForAssCenter(baseCenterY, baseFontSize);
    final rubyDrawBottom =
        baseDrawBottom -
        baseFontSize -
        _layoutEdgeWidth(baseFontSize) -
        rubyGap;
    return assCenterYForDrawBottom(rubyDrawBottom, rubyFontSize);
  }

  List<_AssTextPlacement> layoutText(
    String text, {
    required double centerX,
    required double fontSize,
    required double spacing,
  }) {
    final totalWidth = layoutWidth(text, fontSize, spacing);
    final left = centerX - totalWidth / 2;
    final placements = <_AssTextPlacement>[];
    double cursor = 0;

    for (final char in text.characters) {
      final glyph = _glyphLayout(char, fontSize);
      final cellLeft = left + cursor;
      if (!_isWhitespace(char) && glyph.hasOutline) {
        final face = _faceFor(char);
        final usesAlternate = face != fontFace;
        final fontOverride = usesAlternate
            ? '\\fn${face.info.assFaceName.replaceAll(RegExp(r'[\\{}\r\n]'), '')}'
            : '';
        final fillLeft =
            cellLeft + glyph.geometryLeftOffset + glyph.edgeSize / 2;
        final center = fillLeft - glyph.xMin + glyph.advanceWidth / 2;
        placements.add(
          _AssTextPlacement(
            text: char,
            centerX: center,
            visualLeft: fillLeft - _outlineWidth(fontSize),
            centerYOffset: usesAlternate
                ? _baselineFromCenter(fontFace, fontSize) -
                      _baselineFromCenter(face, fontSize)
                : 0,
            alignmentTag:
                '$fontOverride\\fsp0'
                '\\fs${_formatNumber(assFontSize(fontSize, face))}\\an5',
          ),
        );
      }
      cursor += glyph.drawWidth + spacing;
    }
    return placements;
  }

  double tokenAdvance(_AssNarrowToken token, double fontSize) {
    return tokenWidth(token, fontSize);
  }

  double tokenWidth(_AssNarrowToken token, double fontSize) {
    return layoutWidth(token.text, fontSize, 0);
  }

  String formatForAss(_AssNarrowToken token, double fontSize) {
    if (token.isWhitespace) return token.text;
    return token.text;
  }

  _N3GlyphLayout _glyphLayout(String char, double fontSize) {
    final key = '$fontSize\u0000$char';
    return _glyphLayoutCache.putIfAbsent(key, () {
      final edgeSize = _layoutEdgeWidth(fontSize);
      if (_isWhitespace(char)) {
        final multiplier = char == ' ' ? 0.2 : 0.5;
        return _N3GlyphLayout.empty(fontSize * multiplier + edgeSize, edgeSize);
      }

      var geometryWidth = 0.0;
      var geometryLeftOffset = 0.0;
      var xMin = double.infinity;
      var advanceWidth = 0.0;
      var hasOutline = false;
      var cursor = 0.0;
      final face = _faceFor(char);
      final scale = fontSize / face.unitsPerEm;
      for (final rune in char.runes) {
        final metrics = face.metricsForCodePoint(rune);
        final advance = metrics.advanceWidth * scale;
        if (metrics.hasOutline && metrics.advanceWidth > 0) {
          var leftBearing = metrics.leftSideBearing;
          var rightBearing = metrics.rightSideBearing;
          if (leftBearing < 0) leftBearing = 0;
          if (rightBearing < 0) rightBearing = 0;
          final inkWidth = ((metrics.xMax - metrics.xMin) * scale)
              .truncateToDouble();
          final glyphGeometryWidth =
              (inkWidth *
                      (leftBearing + metrics.advanceWidth + rightBearing) /
                      metrics.advanceWidth)
                  .truncateToDouble();
          final glyphLeftOffset =
              (inkWidth * leftBearing / metrics.advanceWidth)
                  .truncateToDouble();
          if (!hasOutline) {
            geometryLeftOffset = glyphLeftOffset;
            xMin = cursor + metrics.xMin * scale;
          }
          geometryWidth += glyphGeometryWidth;
          hasOutline = true;
        }
        cursor += advance;
        advanceWidth += advance;
      }

      if (!hasOutline) {
        return _N3GlyphLayout.empty(fontSize * 0.5 + edgeSize, edgeSize);
      }
      return _N3GlyphLayout(
        geometryWidth: geometryWidth,
        geometryLeftOffset: geometryLeftOffset,
        edgeSize: edgeSize,
        xMin: xMin,
        advanceWidth: advanceWidth,
        hasOutline: true,
      );
    });
  }

  double _layoutEdgeWidth(double fontSize) {
    if ((fontSize - rubyFontSize).abs() < 0.01) return rubyLayoutEdgeWidth;
    if ((fontSize - baseFontSize).abs() < 0.01 || baseFontSize <= 0) {
      return baseLayoutEdgeWidth;
    }
    return baseLayoutEdgeWidth * fontSize / baseFontSize;
  }

  double _outlineWidth(double fontSize) {
    if ((fontSize - rubyFontSize).abs() < 0.01) return rubyOutlineWidth;
    if ((fontSize - baseFontSize).abs() < 0.01 || baseFontSize <= 0) {
      return baseOutlineWidth;
    }
    return baseOutlineWidth * fontSize / baseFontSize;
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\\.$'), '');
  }
}

class _N3GlyphLayout {
  final double geometryWidth;
  final double geometryLeftOffset;
  final double edgeSize;
  final double xMin;
  final double advanceWidth;
  final bool hasOutline;

  const _N3GlyphLayout({
    required this.geometryWidth,
    required this.geometryLeftOffset,
    required this.edgeSize,
    required this.xMin,
    required this.advanceWidth,
    required this.hasOutline,
  });

  const _N3GlyphLayout.empty(double width, this.edgeSize)
    : geometryWidth = width - edgeSize,
      geometryLeftOffset = 0,
      xMin = 0,
      advanceWidth = 0,
      hasOutline = false;

  double get drawWidth => geometryWidth + edgeSize;
}

class _AssNarrowToken {
  final String text;
  final bool isWord;
  final bool isWhitespace;

  const _AssNarrowToken({
    required this.text,
    required this.isWord,
    required this.isWhitespace,
  });
}

class _Atom {
  final LyricNode originalNode;
  final String? textChar;
  final double width;
  final Duration activeTime;
  final Duration nextTime;
  final int cost;
  final double accumulatedWidth;

  _Atom(
    this.originalNode,
    this.textChar,
    this.width,
    this.activeTime,
    this.nextTime,
    this.cost,
    this.accumulatedWidth,
  );
}
