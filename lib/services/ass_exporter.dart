import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../models/lyric_ast.dart';
import '../screens/ass_export_screen.dart';
import 'font_service.dart';
import 'open_type_font.dart';

class AssLineData {
  final LyricLine astLine;
  final List<List<LyricNode>> rows;
  final List<double> rowWidths;
  final double width;
  final Duration startTime;
  final Duration endTime;
  final List<int?> rowLeadingSingerIndices;
  final Map<LyricNode, Duration> nodeStartTimes;
  final Map<LyricNode, Duration> nodeEndTimes;

  AssLineData({
    required this.astLine,
    required this.rows,
    required this.rowWidths,
    required this.width,
    required this.startTime,
    required this.endTime,
    required this.rowLeadingSingerIndices,
    required this.nodeStartTimes,
    required this.nodeEndTimes,
  });
}

class _SingerMarkerNode extends LyricText {
  final int singerIndex;
  final bool isLeading;

  _SingerMarkerNode({
    required this.singerIndex,
    required this.isLeading,
    required String displayText,
  }) : super(displayText);
}

class _InlineSingerMarkerPlacement {
  final int singerIndex;
  final double left;

  const _InlineSingerMarkerPlacement({
    required this.singerIndex,
    required this.left,
  });
}

class _SingerPrefixMatch {
  final int singerIndex;
  final SingerColorInfo singer;

  const _SingerPrefixMatch(this.singerIndex, this.singer);
}

class _ProcessedSingerLine {
  final LyricLine line;
  final int? leadingSingerIndex;
  final int? trailingSingerIndex;

  const _ProcessedSingerLine({
    required this.line,
    required this.leadingSingerIndex,
    required this.trailingSingerIndex,
  });
}

class AssBlock {
  final List<AssLineData> lines;
  AssBlock(this.lines);

  double get maxWidth {
    if (lines.isEmpty) return 0;
    return lines.map((e) => e.width).reduce((a, b) => a > b ? a : b);
  }
}

class _AssAvatarLayer {
  final Color color;
  final int opacity;
  final String drawing;

  const _AssAvatarLayer({
    required this.color,
    required this.opacity,
    required this.drawing,
  });
}

class _AssAvatarDrawing {
  final double width;
  final double height;
  final double drawingScale;
  final List<_AssAvatarLayer> layers;

  const _AssAvatarDrawing({
    required this.width,
    required this.height,
    required this.drawingScale,
    required this.layers,
  });
}

class AssExporter {
  // Fixed 1080p geometry measured from the default Kosugi Maru countdown.
  // These values are intentionally independent of every lyric font setting.
  static const double _countdownCircleDiameter = 44.0;
  static const double _countdownOutlineWidth = 7.0;
  static const double _countdownCenterSpacing = 65.0;
  static const double _countdownCenterOffsetY = 142.5;
  static const double _countdownCellCenterOffset = 25.5;
  static const double _countdownClipHalfHeight = 51.0;
  static const String _countdownCircleDrawing =
      'm 22 0 b 34 0 44 10 44 22 '
      'b 44 34 34 44 22 44 '
      'b 10 44 0 34 0 22 '
      'b 0 10 10 0 22 0';

  static int getPlayResX(AssExportSettings settings) =>
      (1920.0 * (settings.resolutionHeight / 1080.0)).round();
  static int getPlayResY(AssExportSettings settings) =>
      settings.resolutionHeight;

  static Future<String> generateTypographyPreviewAss(
    AssExportSettings settings,
  ) {
    LyricRuby ruby(String baseText, String rubyText, String time) {
      return LyricRuby(
        baseText: baseText,
        rubyNodes: [
          LyricTimeTag(time: time),
          LyricText(rubyText),
        ],
      );
    }

    SingerColorInfo? previewSinger;
    for (final singer in settings.singerColors) {
      if (singer.prefix
          .split('/')
          .map((part) => part.trim())
          .any(settings.singerAvatarPaths.containsKey)) {
        previewSinger = singer;
        break;
      }
    }
    if (previewSinger == null && settings.singerAvatarPaths.isNotEmpty) {
      previewSinger = SingerColorInfo(
        prefix: settings.singerAvatarPaths.keys.first,
        sungTextColor: settings.sungTextColor,
        sungOutlineColor: settings.sungOutlineColor,
        sungDecorationColor: settings.sungDecorationColor,
        unsungTextColor: settings.unsungTextColor,
        unsungOutlineColor: settings.unsungOutlineColor,
        unsungDecorationColor: settings.unsungDecorationColor,
      );
    }

    final document = LyricDocument(
      lines: [
        LyricLine(
          nodes: [
            LyricTimeTag(time: '00:02:00'),
            if (previewSinger != null) LyricText(previewSinger.prefix),
            ruby('明日', 'あした', '00:02:00'),
            LyricText('の'),
            ruby('街道', 'かいどう', '00:03:00'),
            LyricTimeTag(time: '00:04:00'),
          ],
        ),
        LyricLine(
          nodes: [
            LyricTimeTag(time: '00:02:10'),
            ruby('未来', 'みらい', '00:02:10'),
            LyricText('へ'),
            ruby('歌', 'うた', '00:03:10'),
            LyricText('う'),
            LyricTimeTag(time: '00:04:10'),
          ],
        ),
      ],
    );
    if (previewSinger == null) return generateAss(document, settings);
    final previewSingers = List<SingerColorInfo>.from(settings.singerColors);
    if (!previewSingers.contains(previewSinger)) {
      previewSingers.add(previewSinger);
    }
    final previewSettings = AssExportSettings(
      fontName: settings.fontName,
      customFontPath: settings.customFontPath,
      fontFaceIndex: settings.fontFaceIndex,
      isBold: settings.isBold,
      singerColors: previewSingers,
      showSingerPrefixesInAss: false,
      sungTextColor: settings.sungTextColor,
      sungOutlineColor: settings.sungOutlineColor,
      sungDecorationColor: settings.sungDecorationColor,
      unsungTextColor: settings.unsungTextColor,
      unsungOutlineColor: settings.unsungOutlineColor,
      unsungDecorationColor: settings.unsungDecorationColor,
      fontSize: settings.fontSize,
      letterSpacingEm: settings.letterSpacingEm,
      pagingMode: settings.pagingMode,
      twoLineAlignments: settings.twoLineAlignments,
      threeLineAlignments: settings.threeLineAlignments,
      fourLineAlignments: settings.fourLineAlignments,
      interludeThresholdSeconds: settings.interludeThresholdSeconds,
      horizontalMargin: settings.horizontalMargin,
      outlineWidth: settings.outlineWidth,
      fontOutlineWidth: settings.fontOutlineWidth,
      rubyFontSize: settings.rubyFontSize,
      rubyOutlineWidth: settings.rubyOutlineWidth,
      rubyBaseGap: settings.rubyBaseGap,
      lineSpacing: settings.lineSpacing,
      lyricsBottomMargin: settings.lyricsBottomMargin,
      singerAvatarSize: settings.singerAvatarSize,
      singerAvatarGap: settings.singerAvatarGap,
      singerAvatarPaths: settings.singerAvatarPaths,
      blurLevel: settings.blurLevel,
      resolutionHeight: settings.resolutionHeight,
    );
    return generateAss(document, previewSettings);
  }

  static Future<String> generateAss(
    LyricDocument doc,
    AssExportSettings rawSettings,
  ) async {
    double scale = rawSettings.resolutionHeight / 1080.0;
    final selectedFontFace = await FontService().loadSelectedFace(
      fontFilePath: rawSettings.customFontPath,
      faceIndex: rawSettings.fontFaceIndex,
    );
    AssExportSettings settings = AssExportSettings(
      fontName: selectedFontFace.info.assFontName,
      customFontPath: rawSettings.customFontPath,
      fontFaceIndex: rawSettings.fontFaceIndex,
      isBold: rawSettings.isBold,
      singerColors: rawSettings.singerColors,
      showSingerPrefixesInAss: rawSettings.showSingerPrefixesInAss,
      sungTextColor: rawSettings.sungTextColor,
      sungOutlineColor: rawSettings.sungOutlineColor,
      sungDecorationColor: rawSettings.sungDecorationColor,
      unsungTextColor: rawSettings.unsungTextColor,
      unsungOutlineColor: rawSettings.unsungOutlineColor,
      unsungDecorationColor: rawSettings.unsungDecorationColor,
      fontSize: (rawSettings.fontSize * scale).round(),
      letterSpacingEm: rawSettings.letterSpacingEm,
      pagingMode: rawSettings.pagingMode,
      twoLineAlignments: rawSettings.twoLineAlignments,
      threeLineAlignments: rawSettings.threeLineAlignments,
      fourLineAlignments: rawSettings.fourLineAlignments,
      interludeThresholdSeconds: rawSettings.interludeThresholdSeconds,
      horizontalMargin: (rawSettings.horizontalMargin * scale).round(),
      outlineWidth: (rawSettings.outlineWidth * scale).round(),
      fontOutlineWidth: rawSettings.fontOutlineWidth == null
          ? null
          : (rawSettings.fontOutlineWidth! * scale).round(),
      rubyFontSize: rawSettings.rubyFontSize == null
          ? null
          : (rawSettings.rubyFontSize! * scale).round(),
      rubyOutlineWidth: rawSettings.rubyOutlineWidth == null
          ? null
          : (rawSettings.rubyOutlineWidth! * scale).round(),
      rubyBaseGap: rawSettings.rubyBaseGap == null
          ? null
          : (rawSettings.rubyBaseGap! * scale).round(),
      lineSpacing: rawSettings.lineSpacing == null
          ? null
          : (rawSettings.lineSpacing! * scale).round(),
      lyricsBottomMargin: (rawSettings.lyricsBottomMargin * scale).round(),
      singerAvatarSize: rawSettings.singerAvatarSize == null
          ? null
          : (rawSettings.singerAvatarSize! * scale).round(),
      singerAvatarGap: (rawSettings.singerAvatarGap * scale).round(),
      singerAvatarPaths: rawSettings.singerAvatarPaths,
      blurLevel: rawSettings.blurLevel,
      resolutionHeight: rawSettings.resolutionHeight,
    );

    final baseFontSize = settings.fontSize.toDouble();
    final rubyFontSize = _resolveRubyFontSize(
      baseFontSize,
      settings.rubyFontSize,
    );
    final baseOutlineWidth = _resolveFontOutlineWidth(
      baseFontSize,
      settings.fontOutlineWidth,
    );
    final rubyOutlineWidth = _resolveRubyBaseOutlineWidth(
      baseOutlineWidth,
      baseFontSize,
      rubyFontSize,
      settings.rubyOutlineWidth,
    );
    final textMetrics = _AssTextMetrics(
      fontFace: selectedFontFace,
      baseFontSize: baseFontSize,
      baseOutlineWidth: baseOutlineWidth,
      baseLayoutEdgeWidth: settings.fontOutlineWidth == null
          ? (baseFontSize * 13 / 85).roundToDouble()
          : baseOutlineWidth * 2,
      rubyFontSize: rubyFontSize,
      rubyOutlineWidth: rubyOutlineWidth,
      rubyLayoutEdgeWidth: settings.rubyOutlineWidth == null
          ? (rubyFontSize * 10 / 40).roundToDouble()
          : rubyOutlineWidth * 2,
    );
    final avatarDrawings = await _loadSingerAvatarDrawings(settings);
    final sb = StringBuffer();
    _writeHeader(
      sb,
      settings,
      textMetrics: textMetrics,
      includeSingerAvatarStyle: avatarDrawings.isNotEmpty,
    );

    // Replace singer markers and pre-calculate the singer active at each line.
    Map<LyricLine, int> lineSingerMap = {};
    int? currentSingerIdx;

    final sortedSingers = <_SingerPrefixMatch>[];
    for (var index = 0; index < settings.singerColors.length; index++) {
      final singer = settings.singerColors[index];
      if (singer.prefix.isNotEmpty) {
        sortedSingers.add(_SingerPrefixMatch(index, singer));
      }
    }
    sortedSingers.sort(
      (a, b) => b.singer.prefix.length.compareTo(a.singer.prefix.length),
    );

    final renderLines = <LyricLine>[];
    for (final sourceLine in doc.lines) {
      final processed = _replaceSingerPrefixes(
        sourceLine: sourceLine,
        initialSingerIndex: currentSingerIdx,
        sortedSingers: sortedSingers,
        showPrefixes: settings.showSingerPrefixesInAss,
      );
      final renderLine = processed.line;
      renderLines.add(renderLine);
      currentSingerIdx = processed.trailingSingerIndex;
      if (processed.leadingSingerIndex != null) {
        lineSingerMap[renderLine] = processed.leadingSingerIndex!;
      }
    }

    final renderDocument = LyricDocument(lines: renderLines);
    final blocks = _groupLinesIntoBlocks(
      renderDocument,
      settings,
      textMetrics,
      lineSingerMap,
    );

    Map<int, Duration> yEndTimes = {};
    Duration lastInterludeEnd = Duration.zero;

    for (int i = 0; i < blocks.length; i++) {
      var block = blocks[i];

      if (lastInterludeEnd != Duration.zero && block.lines.isNotEmpty) {
        Duration nextLyricStart = block.lines.first.startTime;
        Duration gap = nextLyricStart - lastInterludeEnd;

        if (gap.inMilliseconds > settings.interludeThresholdSeconds * 1000) {
          Duration prevDisplayEnd =
              lastInterludeEnd + const Duration(milliseconds: 200);
          Duration promptStart = prevDisplayEnd + const Duration(seconds: 1);
          Duration promptEnd = promptStart + const Duration(seconds: 3);

          int waitSeconds = gap.inSeconds + 1;
          String interludeText = '間奏 $waitSeconds 秒';
          int playResX = getPlayResX(settings);
          int playResY = getPlayResY(settings);
          _writeInterludePrompt(
            sb: sb,
            text: interludeText,
            centerX: playResX / 2,
            centerY: playResY * 0.9,
            displayStart: promptStart,
            displayEnd: promptEnd,
            settings: settings,
            textMetrics: textMetrics,
          );
        }
      }

      _writeBlock(
        sb,
        block,
        settings,
        yEndTimes,
        lastInterludeEnd,
        avatarDrawings,
        textMetrics,
      );

      if (block.lines.isNotEmpty) {
        Duration maxEnd = Duration.zero;
        for (var l in block.lines) {
          if (l.endTime > maxEnd) maxEnd = l.endTime;
        }
        lastInterludeEnd = maxEnd;
      }
    }

    return sb.toString();
  }

  static void _writeInterludePrompt({
    required StringBuffer sb,
    required String text,
    required double centerX,
    required double centerY,
    required Duration displayStart,
    required Duration displayEnd,
    required AssExportSettings settings,
    required _AssTextMetrics textMetrics,
  }) {
    final fontSize = settings.fontSize.toDouble();
    final placements = _layoutAssText(
      text: text,
      centerX: centerX,
      fontSize: fontSize,
      spacing: _resolveSpacing(fontSize, settings.letterSpacingEm),
      textMetrics: textMetrics,
    );
    for (final placement in placements) {
      sb.writeln(
        'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},Interlude,,0,0,0,,{${placement.alignmentTag}\\pos(${placement.centerX.toStringAsFixed(1)},${centerY.toStringAsFixed(1)})\\fad(500,500)\\c&HFFFFFF&}${placement.text}',
      );
    }
  }

  static _ProcessedSingerLine _replaceSingerPrefixes({
    required LyricLine sourceLine,
    required int? initialSingerIndex,
    required List<_SingerPrefixMatch> sortedSingers,
    required bool showPrefixes,
  }) {
    final nodes = <LyricNode>[];
    var currentSingerIndex = initialSingerIndex;
    var leadingSingerIndex = initialSingerIndex;
    var hasVisibleLyrics = false;

    for (final node in sourceLine.nodes) {
      if (node is! LyricText || sortedSingers.isEmpty) {
        nodes.add(node);
        if (node is LyricRuby) hasVisibleLyrics = true;
        continue;
      }

      var cursor = 0;
      while (cursor < node.text.length) {
        _SingerPrefixMatch? nextMatch;
        var nextOffset = node.text.length;
        for (final candidate in sortedSingers) {
          final offset = node.text.indexOf(candidate.singer.prefix, cursor);
          if (offset >= 0 && offset < nextOffset) {
            nextMatch = candidate;
            nextOffset = offset;
          }
        }

        if (nextMatch == null) {
          final suffix = node.text.substring(cursor);
          if (suffix.isNotEmpty) {
            nodes.add(LyricText(suffix));
            hasVisibleLyrics = true;
          }
          break;
        }

        if (nextOffset > cursor) {
          nodes.add(LyricText(node.text.substring(cursor, nextOffset)));
          hasVisibleLyrics = true;
        }
        currentSingerIndex = nextMatch.singerIndex;
        if (!hasVisibleLyrics) leadingSingerIndex = currentSingerIndex;
        nodes.add(
          _SingerMarkerNode(
            singerIndex: currentSingerIndex,
            isLeading: !hasVisibleLyrics,
            displayText: showPrefixes ? nextMatch.singer.prefix : '',
          ),
        );
        cursor = nextOffset + nextMatch.singer.prefix.length;
      }
    }

    return _ProcessedSingerLine(
      line: LyricLine(nodes: nodes),
      leadingSingerIndex: leadingSingerIndex,
      trailingSingerIndex: currentSingerIndex,
    );
  }

  static double _resolveSingerAvatarSize(AssExportSettings settings) =>
      settings.singerAvatarSize?.toDouble() ?? settings.fontSize * 0.6;

  static Future<Map<String, _AssAvatarDrawing>> _loadSingerAvatarDrawings(
    AssExportSettings settings,
  ) async {
    if (settings.singerAvatarPaths.isEmpty) return const {};
    final result = <String, _AssAvatarDrawing>{};
    final targetSize = _resolveSingerAvatarSize(settings);
    final referencedSingers = <String>{
      for (final singer in settings.singerColors)
        for (final part in singer.prefix.split('/'))
          if (part.trim().isNotEmpty) part.trim(),
    };
    for (final entry in settings.singerAvatarPaths.entries) {
      if (!referencedSingers.contains(entry.key)) continue;
      try {
        final drawing = await _decodeAvatarDrawing(entry.value, targetSize);
        if (drawing != null) result[entry.key] = drawing;
      } catch (_) {
        // A missing or damaged external file must not abort subtitle export.
      }
    }
    return result;
  }

  static Future<_AssAvatarDrawing?> _decodeAvatarDrawing(
    String path,
    double requestedSize,
  ) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();

    ui.Codec? sourceCodec;
    ui.Image? sourceImage;
    int sourceWidth;
    int sourceHeight;
    try {
      sourceCodec = await ui.instantiateImageCodec(bytes);
      final frame = await sourceCodec.getNextFrame();
      sourceImage = frame.image;
      sourceWidth = sourceImage.width;
      sourceHeight = sourceImage.height;
    } finally {
      sourceImage?.dispose();
      sourceCodec?.dispose();
    }
    if (sourceWidth <= 0 || sourceHeight <= 0) return null;

    final sampleLongSide = min(requestedSize.round(), 72).clamp(1, 72).toInt();
    final isWide = sourceWidth >= sourceHeight;
    final sampleWidth = isWide
        ? sampleLongSide
        : max(1, (sampleLongSide * sourceWidth / sourceHeight).round());
    final sampleHeight = isWide
        ? max(1, (sampleLongSide * sourceHeight / sourceWidth).round())
        : sampleLongSide;

    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: sampleWidth,
        targetHeight: sampleHeight,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return null;

      final pathsByColor = <int, StringBuffer>{};
      for (var y = 0; y < image.height; y++) {
        var x = 0;
        while (x < image.width) {
          final offset = (y * image.width + x) * 4;
          final key = _quantizedAvatarColorKey(
            rgba.getUint8(offset),
            rgba.getUint8(offset + 1),
            rgba.getUint8(offset + 2),
            rgba.getUint8(offset + 3),
          );
          var runEnd = x + 1;
          while (runEnd < image.width) {
            final nextOffset = (y * image.width + runEnd) * 4;
            final nextKey = _quantizedAvatarColorKey(
              rgba.getUint8(nextOffset),
              rgba.getUint8(nextOffset + 1),
              rgba.getUint8(nextOffset + 2),
              rgba.getUint8(nextOffset + 3),
            );
            if (nextKey != key) break;
            runEnd++;
          }
          if (key != 0) {
            pathsByColor
                .putIfAbsent(key, StringBuffer.new)
                .write('m $x $y l $runEnd $y $runEnd ${y + 1} $x ${y + 1} ');
          }
          x = runEnd;
        }
      }

      final layers = <_AssAvatarLayer>[];
      for (final entry in pathsByColor.entries) {
        final key = entry.key;
        final opacity = (key >> 24) & 0xFF;
        final red = (key >> 16) & 0xFF;
        final green = (key >> 8) & 0xFF;
        final blue = key & 0xFF;
        layers.add(
          _AssAvatarLayer(
            color: Color.fromARGB(255, red, green, blue),
            opacity: opacity,
            drawing: entry.value.toString().trimRight(),
          ),
        );
      }
      layers.sort((a, b) => a.opacity.compareTo(b.opacity));

      final drawingScale = requestedSize / max(image.width, image.height);
      return _AssAvatarDrawing(
        width: image.width * drawingScale,
        height: image.height * drawingScale,
        drawingScale: drawingScale,
        layers: layers,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static int _quantizedAvatarColorKey(int red, int green, int blue, int alpha) {
    if (alpha < 16) return 0;
    int quantizeColor(int value) => ((value * 4 + 127) ~/ 255) * 255 ~/ 4;
    int quantizeAlpha(int value) => ((value * 7 + 127) ~/ 255) * 255 ~/ 7;
    final a = quantizeAlpha(alpha);
    final r = quantizeColor(red);
    final g = quantizeColor(green);
    final b = quantizeColor(blue);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  static void _writeHeader(
    StringBuffer sb,
    AssExportSettings settings, {
    required _AssTextMetrics textMetrics,
    required bool includeSingerAvatarStyle,
  }) {
    int playResX = getPlayResX(settings);
    int playResY = getPlayResY(settings);

    sb.writeln('[Script Info]');
    sb.writeln('ScriptType: v4.00+');
    sb.writeln('PlayResX: $playResX');
    sb.writeln('PlayResY: $playResY');
    sb.writeln('WrapStyle: 0');
    sb.writeln('ScaledBorderAndShadow: yes');
    sb.writeln('');

    String sungTextColor = _colorToAss(settings.sungTextColor.color0);
    String sungOutlineColor = _colorToAss(settings.sungOutlineColor.color0);
    String unsungTextColor = _colorToAss(settings.unsungTextColor.color0);
    String unsungOutlineColor = _colorToAss(settings.unsungOutlineColor.color0);
    int fs = settings.fontSize;
    final assFs = _formatAssNumber(textMetrics.assFontSize(fs.toDouble()));
    String fn = settings.fontName;

    int rubyFs = _resolveRubyFontSize(
      fs.toDouble(),
      settings.rubyFontSize,
    ).round();
    final assRubyFs = _formatAssNumber(
      textMetrics.assFontSize(rubyFs.toDouble()),
    );

    double spacing = _resolveSpacing(fs.toDouble(), settings.letterSpacingEm);
    double rubySpacing = _resolveRubySpacing(
      rubyFs.toDouble(),
      settings.letterSpacingEm,
    );
    double interludeSpacing = _resolveSpacing(fs.toDouble(), null);
    String assSpacing = _formatAssNumber(spacing);
    String assRubySpacing = _formatAssNumber(rubySpacing);
    String assInterludeSpacing = _formatAssNumber(interludeSpacing);

    int baseOutW = _resolveFontOutlineWidth(
      fs.toDouble(),
      settings.fontOutlineWidth,
    ).round();
    int rubyBaseOutW = _resolveRubyBaseOutlineWidth(
      baseOutW.toDouble(),
      fs.toDouble(),
      rubyFs.toDouble(),
      settings.rubyOutlineWidth,
    ).round();

    String boldFlag = settings.isBold ? '-1' : '0';

    sb.writeln('[V4+ Styles]');
    sb.writeln(
      'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
    );
    sb.writeln(
      'Style: DefaultUnsung,$fn,$assFs,$unsungTextColor,&H00FFFFFF,$unsungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assSpacing,0,1,$baseOutW,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: DefaultSung,$fn,$assFs,$sungTextColor,&H00FFFFFF,$sungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assSpacing,0,1,$baseOutW,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: RubyUnsung,$fn,$assRubyFs,$unsungTextColor,&H00FFFFFF,$unsungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assRubySpacing,0,1,$rubyBaseOutW,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: RubySung,$fn,$assRubyFs,$sungTextColor,&H00FFFFFF,$sungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assRubySpacing,0,1,$rubyBaseOutW,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: Interlude,$fn,$assFs,$sungTextColor,&H00FFFFFF,$unsungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assInterludeSpacing,0,1,$baseOutW,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: CountdownVector,Arial,1,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,5,0,0,0,1',
    );
    if (includeSingerAvatarStyle) {
      sb.writeln(
        'Style: SingerAvatar,Arial,1,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1',
      );
    }

    sb.writeln('');
    sb.writeln('[Events]');
    sb.writeln(
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
    );
  }

  static String _colorToAss(Color color) {
    int r = (color.r * 255.0).round().clamp(0, 255);
    int g = (color.g * 255.0).round().clamp(0, 255);
    int b = (color.b * 255.0).round().clamp(0, 255);
    String hexR = r.toRadixString(16).padLeft(2, '0').toUpperCase();
    String hexG = g.toRadixString(16).padLeft(2, '0').toUpperCase();
    String hexB = b.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '&H00$hexB$hexG$hexR&';
  }

  static Color _colorAt(AssColorValue value, double position) {
    if (!value.isGradient) return value.color0;
    return Color.lerp(value.color0, value.color100, position) ?? value.color0;
  }

  static String _assColorAt(AssColorValue value, double position) {
    return _colorToAss(_colorAt(value, position));
  }

  static List<_GradientBand> _gradientBands({
    required double clipTop,
    required double clipBottom,
    required double gradientTop,
    required double gradientBottom,
    required bool enabled,
  }) {
    if (!enabled || gradientBottom <= gradientTop) {
      return [_GradientBand(top: clipTop, bottom: clipBottom, position: 0.5)];
    }

    const bandCount = 16;
    final height = gradientBottom - gradientTop;
    return List.generate(bandCount, (index) {
      final top = index == 0
          ? clipTop
          : gradientTop + height * index / bandCount;
      final bottom = index == bandCount - 1
          ? clipBottom
          : gradientTop + height * (index + 1) / bandCount;
      return _GradientBand(
        top: top,
        bottom: bottom,
        position: index / (bandCount - 1),
      );
    });
  }

  static void _writeGlowLayers({
    required StringBuffer sb,
    required String rawText,
    required String style,
    required String alignmentTag,
    required double posX,
    required double posY,
    required double visualY,
    required double fontSize,
    required double baseOutlineWidth,
    required double decorationWidth,
    required int blurLevel,
    required int tStart,
    required int tEnd,
    required Duration displayStart,
    required Duration displayEnd,
    required AssColorValue color,
    required bool fadesIn,
  }) {
    if (decorationWidth <= 0) return;

    final hasGradient = color.isGradient;
    final bands = _gradientBands(
      clipTop: visualY - fontSize * 1.5,
      clipBottom: visualY + fontSize * 1.5,
      gradientTop: visualY - fontSize * 0.5,
      gradientBottom: visualY + fontSize * 0.5,
      enabled: hasGradient,
    );
    final numLayers = blurLevel + 1;

    for (int layerIndex = 0; layerIndex < numLayers; layerIndex++) {
      final layerWidth =
          decorationWidth - layerIndex * decorationWidth / numLayers;
      final borderWidth = baseOutlineWidth + layerWidth / 2;

      for (final band in bands) {
        final assColor = _assColorAt(color, band.position);
        final clipTag = hasGradient
            ? '\\clip(0,${band.top.toStringAsFixed(1)},10000,${band.bottom.toStringAsFixed(1)})'
            : '';
        final initialAlpha = fadesIn ? 'FF' : '00';
        final finalAlpha = fadesIn ? '00' : 'FF';
        final tags =
            '\\1c$assColor\\3c$assColor'
            '\\1a&H$initialAlpha&\\3a&H$initialAlpha&'
            '\\bord${borderWidth.toStringAsFixed(1)}'
            '\\blur${layerWidth.toStringAsFixed(1)}'
            '$clipTag'
            '\\t($tStart,$tEnd,\\1a&H$finalAlpha&\\3a&H$finalAlpha&)';

        sb.writeln(
          'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},$style,,0,0,0,,{$alignmentTag\\pos(${posX.toStringAsFixed(1)},${posY.toStringAsFixed(1)})$tags}$rawText',
        );
      }
    }
  }

  static String _buildSegmentedSweepTags({
    required bool reverse,
    required double fullLeft,
    required double fullRight,
    required double initialX,
    required double top,
    required double bottom,
    required List<_WipeSegment> segments,
    required int tEnd,
  }) {
    String clip(double left, double right) =>
        '\\clip(${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${right.toStringAsFixed(1)},${bottom.toStringAsFixed(1)})';

    final tags = StringBuffer(
      reverse ? clip(fullLeft, fullRight) : clip(initialX, initialX),
    );
    if (segments.isNotEmpty) {
      final first = segments.first;
      tags.write(
        '\\t(${first.start},${first.start + 1},${reverse ? clip(first.left, fullRight) : clip(fullLeft, first.left)})',
      );
      for (final segment in segments) {
        tags.write(
          '\\t(${segment.start + 1},${segment.end},${reverse ? clip(segment.right, fullRight) : clip(fullLeft, segment.right)})',
        );
      }
    }
    tags.write(
      reverse
          ? '\\t($tEnd,${tEnd + 1},\\clip(0,0,0,0))'
          : '\\t($tEnd,${tEnd + 1},${clip(fullLeft, fullRight)})',
    );
    return tags.toString();
  }

  static void _writeGradientSweepDialogue({
    required StringBuffer sb,
    required String rawText,
    required String style,
    required String alignmentTag,
    required double posX,
    required double posY,
    required double visualY,
    required double fontSize,
    required AssColorValue textColor,
    required AssColorValue outlineColor,
    required double fullLeft,
    required double fullRight,
    required double initialX,
    required List<_WipeSegment> segments,
    required int tEnd,
    required bool reverse,
    required Duration displayStart,
    required Duration displayEnd,
  }) {
    final hasGradient = textColor.isGradient || outlineColor.isGradient;
    final bands = _gradientBands(
      clipTop: visualY - fontSize * 1.5,
      clipBottom: visualY + fontSize * 1.5,
      gradientTop: visualY - fontSize * 0.5,
      gradientBottom: visualY + fontSize * 0.5,
      enabled: hasGradient,
    );

    for (final band in bands) {
      final colors =
          '\\1c${_assColorAt(textColor, band.position)}'
          '\\3c${_assColorAt(outlineColor, band.position)}';
      final sweep = _buildSegmentedSweepTags(
        reverse: reverse,
        fullLeft: fullLeft,
        fullRight: fullRight,
        initialX: initialX,
        top: band.top,
        bottom: band.bottom,
        segments: segments,
        tEnd: tEnd,
      );
      sb.writeln(
        'Dialogue: 1,${_formatTime(displayStart)},${_formatTime(displayEnd)},$style,,0,0,0,,{$alignmentTag\\pos(${posX.toStringAsFixed(1)},${posY.toStringAsFixed(1)})$colors$sweep}$rawText',
      );
    }
  }

  static String _formatTime(Duration d) {
    int h = d.inHours;
    int m = d.inMinutes.remainder(60);
    int s = d.inSeconds.remainder(60);
    int cs = (d.inMilliseconds.remainder(1000) ~/ 10);
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  static Duration _parseTime(String timeStr) {
    try {
      final parts = timeStr.replaceAll('.', ':').split(':');
      int parseMs(String s) {
        if (s.length == 3) return int.parse(s);
        if (s.length == 2) return int.parse(s) * 10;
        if (s.length == 1) return int.parse(s) * 100;
        return int.parse(s.substring(0, 3));
      }

      if (parts.length == 4) {
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        int s = int.parse(parts[2]);
        int ms = parseMs(parts[3]);
        return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
      } else if (parts.length == 3) {
        int m = int.parse(parts[0]);
        int s = int.parse(parts[1]);
        int ms = parseMs(parts[2]);
        return Duration(minutes: m, seconds: s, milliseconds: ms);
      } else if (parts.length == 2) {
        int m = int.parse(parts[0]);
        int s = int.parse(parts[1]);
        return Duration(minutes: m, seconds: s);
      }
    } catch (e) {
      // fallback
    }
    return Duration.zero;
  }

  static double _getCharWidth(
    String text,
    double fontSize,
    double spacing,
    _AssTextMetrics textMetrics,
  ) {
    return textMetrics.layoutWidth(text, fontSize, spacing);
  }

  static bool _isWideGrapheme(String char) {
    if (char.isEmpty) return false;
    final code = char.runes.first;
    return (code >= 0x3000 && code <= 0x9FFF) ||
        (code >= 0xF900 && code <= 0xFAFF) ||
        (code >= 0xFF00 && code <= 0xFFEF) ||
        (code >= 0x1F000 && code <= 0x1FAFF) ||
        (code >= 0x20000 && code <= 0x3FFFF) ||
        code == 0x25CF;
  }

  static double _spacingForGrapheme(String char, double wideSpacing) {
    if (_isWideGrapheme(char)) return wideSpacing;
    return 0;
  }

  static double _trailingSpacing(String text, double wideSpacing) {
    if (text.characters.isEmpty) return 0;
    return _spacingForGrapheme(text.characters.last, wideSpacing);
  }

  static List<String> _splitAssTextRuns(String text) {
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

  static List<String> _splitTextForLineWrap(
    String text,
    _AssTextMetrics textMetrics,
  ) {
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

  static List<_AssTextPlacement> _layoutAssText({
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

  static _AssTextPlacement? _firstVisibleAssPlacement({
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

  static double _resolveSpacing(double fontSize, double? letterSpacingEm) {
    if (letterSpacingEm == null) return 0;
    return fontSize * letterSpacingEm;
  }

  static double _resolveRubySpacing(
    double rubyFontSize,
    double? letterSpacingEm,
  ) {
    if (letterSpacingEm == null) {
      return _resolveSpacing(rubyFontSize, null);
    }
    return rubyFontSize * letterSpacingEm;
  }

  static double _resolveRubyFontSize(double fontSize, int? rubyFontSize) {
    return rubyFontSize?.toDouble() ?? (fontSize * 36 / 75).roundToDouble();
  }

  static double _resolveFontOutlineWidth(
    double fontSize,
    int? fontOutlineWidth,
  ) {
    if (fontOutlineWidth != null) return fontOutlineWidth.toDouble();
    final width = (fontSize * 7 / 85).roundToDouble();
    return width < 1 ? 1.0 : width;
  }

  static double _resolveRubyBaseOutlineWidth(
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

  static String _formatAssNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static Duration _getLineStartTime(LyricLine line) {
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

  static Duration _getLineEndTime(LyricLine line, Duration defaultStart) {
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

  static double _getTextContentWidth(
    String text,
    double fontSize,
    double spacing,
    _AssTextMetrics textMetrics,
  ) {
    if (text.characters.isEmpty) return 0;
    return _getCharWidth(text, fontSize, spacing, textMetrics) -
        _trailingSpacing(text, spacing);
  }

  static double _getRubyNodeWidth(
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
    final naturalBaseRun = node.baseText.characters.every(
      (char) => !_isWideGrapheme(char),
    );
    if (naturalBaseRun) return baseBlockW;
    return baseBlockW > rubyBlockW ? baseBlockW : rubyBlockW;
  }

  static double _getLineWidth(
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

  static List<LyricNode> _splitTextNodesForAssGrid(
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
          nodeStartTimes[splitNode] =
              start + Duration(milliseconds: partStartMs);
          nodeEndTimes[splitNode] = start + Duration(milliseconds: partEndMs);
        }
      }
    }

    return result;
  }

  static bool _isKinsoku(String char) {
    if (char.isEmpty) return false;
    return 'ぁぃぅぇぉっゃゅょゎ゛゜ゝゞァィゥェォッャュョヮヵヶ・ーヽヾ！％），．：；？］｝｡｣､･、。々〉》」』】〕!%),.:;?]}'
        .contains(char);
  }

  static List<AssBlock> _groupLinesIntoBlocks(
    LyricDocument doc,
    AssExportSettings settings,
    _AssTextMetrics textMetrics,
    Map<LyricLine, int> lineSingerMap,
  ) {
    final blocks = <AssBlock>[];
    List<AssLineData> currentBlock = [];
    final fs = settings.fontSize.toDouble();

    for (var line in doc.lines) {
      if (line.nodes.isEmpty || line.toLrcString().trim().isEmpty) {
        if (settings.pagingMode == AssPagingMode.emptyLineDelimited) {
          if (currentBlock.isNotEmpty) {
            blocks.add(AssBlock(List.from(currentBlock)));
            currentBlock.clear();
          }
        }
        continue;
      }

      final startTime = _getLineStartTime(line);
      final endTime = _getLineEndTime(line, startTime);

      double scale = settings.resolutionHeight / 1080.0;
      final double maxLineW = 1800 * scale;

      double lineSpacingVal = _resolveSpacing(fs, settings.letterSpacingEm);
      double width = _getLineWidth(
        line,
        fs,
        lineSpacingVal,
        settings.letterSpacingEm,
        settings.rubyFontSize,
        textMetrics,
      );

      Map<LyricNode, Duration> nodeStartTimes = {};
      Map<LyricNode, Duration> nodeEndTimes = {};

      List<dynamic> timeElements = [];
      for (int i = 0; i < line.nodes.length; i++) {
        var node = line.nodes[i];
        if (node is LyricTimeTag && node.time.isNotEmpty) {
          timeElements.add(_parseTime(node.time));
        } else if (node is LyricRuby) {
          if (node.rubyNodes.isNotEmpty &&
              node.rubyNodes.first is LyricTimeTag) {
            LyricTimeTag firstTag = node.rubyNodes.first as LyricTimeTag;
            if (firstTag.time.isNotEmpty) {
              timeElements.add(_parseTime(firstTag.time));
            }
          }
          double w = _getRubyNodeWidth(
            node,
            fs,
            lineSpacingVal,
            settings.letterSpacingEm,
            settings.rubyFontSize,
            textMetrics,
          );
          timeElements.add(
            _Atom(node, null, w, Duration.zero, Duration.zero, 10, 0),
          );
        } else if (node is LyricText) {
          double w = _getCharWidth(node.text, fs, lineSpacingVal, textMetrics);
          timeElements.add(
            _Atom(node, null, w, Duration.zero, Duration.zero, 10, 0),
          );
        }
      }

      Duration chunkTime = startTime;
      List<_Atom> currentChunk = [];
      for (var el in timeElements) {
        if (el is Duration) {
          if (currentChunk.isNotEmpty) {
            int totalMs = (el - chunkTime).inMilliseconds;
            if (totalMs < 0) totalMs = 0;
            double totalW = 0;
            for (var a in currentChunk) {
              totalW += _timingWidth(a);
            }

            for (var a in currentChunk) {
              int ms = 0;
              if (totalW > 0) {
                ms = (totalMs * (_timingWidth(a) / totalW)).round();
              }
              nodeStartTimes[a.originalNode] = chunkTime;
              chunkTime += Duration(milliseconds: ms);
              nodeEndTimes[a.originalNode] = chunkTime;
            }
            currentChunk.clear();
          }
          chunkTime = el;
        } else if (el is _Atom) {
          currentChunk.add(el);
        }
      }
      if (currentChunk.isNotEmpty) {
        int totalMs = (endTime - chunkTime).inMilliseconds;
        if (totalMs < 0) totalMs = 0;
        double totalW = 0;
        for (var a in currentChunk) {
          totalW += _timingWidth(a);
        }
        for (var a in currentChunk) {
          int ms = 0;
          if (totalW > 0) {
            ms = (totalMs * (_timingWidth(a) / totalW)).round();
          }
          nodeStartTimes[a.originalNode] = chunkTime;
          chunkTime += Duration(milliseconds: ms);
          nodeEndTimes[a.originalNode] = chunkTime;
        }
      }

      List<List<LyricNode>> rows = [];
      List<double> rowWidths = [];

      if (width <= maxLineW) {
        rows.add(line.nodes);
        rowWidths.add(width);
      } else {
        List<dynamic> elements = [];
        for (int i = 0; i < line.nodes.length; i++) {
          var node = line.nodes[i];
          if (node is LyricTimeTag && node.time.isNotEmpty) {
            elements.add(_parseTime(node.time));
          } else if (node is LyricRuby) {
            if (node.rubyNodes.isNotEmpty &&
                node.rubyNodes.first is LyricTimeTag) {
              LyricTimeTag firstTag = node.rubyNodes.first as LyricTimeTag;
              if (firstTag.time.isNotEmpty) {
                elements.add(_parseTime(firstTag.time));
              }
            }
            double w = _getRubyNodeWidth(
              node,
              fs,
              lineSpacingVal,
              settings.letterSpacingEm,
              settings.rubyFontSize,
              textMetrics,
            );
            elements.add(
              _Atom(node, null, w, Duration.zero, Duration.zero, 10, 0),
            );
          } else if (node is _SingerMarkerNode) {
            final w = _getCharWidth(node.text, fs, lineSpacingVal, textMetrics);
            elements.add(
              _Atom(node, null, w, Duration.zero, Duration.zero, 10, 0),
            );
          } else if (node is LyricText) {
            String text = node.text;
            final clusters = _splitTextForLineWrap(text, textMetrics);
            for (int c = 0; c < clusters.length; c++) {
              String cluster = clusters[c];
              double w = _getCharWidth(
                cluster,
                fs,
                lineSpacingVal,
                textMetrics,
              );
              int cost = 20;
              if (c == clusters.length - 1) {
                cost = 10;
              } else if (cluster.endsWith(' ') || cluster.endsWith('　')) {
                cost = 0;
              }

              elements.add(
                _Atom(node, cluster, w, Duration.zero, Duration.zero, cost, 0),
              );
            }
          }
        }

        List<_Atom> atoms = [];
        Duration currentTagTime = startTime;
        double currentAccW = 0;
        List<_Atom> currentChunkAtoms = [];

        for (var el in elements) {
          if (el is Duration) {
            if (currentChunkAtoms.isNotEmpty) {
              Duration endTagTime = el;
              int totalMs = (endTagTime - currentTagTime).inMilliseconds;
              if (totalMs < 0) totalMs = 0;

              double chunkTotalW = 0;
              for (var a in currentChunkAtoms) {
                chunkTotalW += _timingWidth(a);
              }

              for (var a in currentChunkAtoms) {
                int ms = 0;
                if (chunkTotalW > 0) {
                  ms = (totalMs * (_timingWidth(a) / chunkTotalW)).round();
                }
                Duration start = currentTagTime;
                currentTagTime += Duration(milliseconds: ms);

                currentAccW += a.width;
                atoms.add(
                  _Atom(
                    a.originalNode,
                    a.textChar,
                    a.width,
                    start,
                    currentTagTime,
                    a.cost,
                    currentAccW,
                  ),
                );
              }
              currentChunkAtoms.clear();
            }
            currentTagTime = el;
          } else if (el is _Atom) {
            currentChunkAtoms.add(el);
          }
        }

        if (currentChunkAtoms.isNotEmpty) {
          Duration endTagTime = endTime;
          int totalMs = (endTagTime - currentTagTime).inMilliseconds;
          if (totalMs < 0) totalMs = 0;

          double chunkTotalW = 0;
          for (var a in currentChunkAtoms) {
            chunkTotalW += _timingWidth(a);
          }

          for (var a in currentChunkAtoms) {
            int ms = 0;
            if (chunkTotalW > 0) {
              ms = (totalMs * (_timingWidth(a) / chunkTotalW)).round();
            }
            Duration start = currentTagTime;
            currentTagTime += Duration(milliseconds: ms);

            currentAccW += a.width;
            atoms.add(
              _Atom(
                a.originalNode,
                a.textChar,
                a.width,
                start,
                currentTagTime,
                a.cost,
                currentAccW,
              ),
            );
          }
        }

        List<List<_Atom>> rowAtoms = [];
        List<_Atom> remainingAtoms = List.from(atoms);

        while (remainingAtoms.isNotEmpty) {
          double remW =
              remainingAtoms.last.accumulatedWidth -
              (remainingAtoms.first.accumulatedWidth -
                  remainingAtoms.first.width);
          if (remW <= maxLineW) {
            rowAtoms.add(remainingAtoms);
            break;
          }

          int remR = (remW / maxLineW).ceil();
          if (remR < 2) remR = 2;
          double targetW = remW / remR;

          double bestScore = double.infinity;
          int bestIndex = -1;

          double offsetW =
              remainingAtoms.first.accumulatedWidth -
              remainingAtoms.first.width;

          for (int i = 0; i < remainingAtoms.length - 1; i++) {
            var atom = remainingAtoms[i];
            double widthBefore = atom.accumulatedWidth - offsetW;

            if (widthBefore > 0 && widthBefore <= maxLineW) {
              double score = atom.cost + (widthBefore - targetW).abs() * 0.2;
              debugPrint(
                'Atom text: ${atom.textChar}, cost: ${atom.cost}, widthBefore: $widthBefore, score: $score, targetW: $targetW',
              );
              if (score < bestScore) {
                bestScore = score;
                bestIndex = i;
              }
            }
          }
          debugPrint('Selected bestIndex: $bestIndex, bestScore: $bestScore');

          if (bestIndex == -1) {
            for (int i = 0; i < remainingAtoms.length; i++) {
              double widthBefore = remainingAtoms[i].accumulatedWidth - offsetW;
              if (widthBefore <= maxLineW) {
                bestIndex = i;
              } else {
                break;
              }
            }
            if (bestIndex == -1) bestIndex = 0;
          }

          rowAtoms.add(remainingAtoms.sublist(0, bestIndex + 1));
          remainingAtoms = remainingAtoms.sublist(bestIndex + 1);
        }

        for (int r = 0; r < rowAtoms.length; r++) {
          var rAtoms = rowAtoms[r];
          List<LyricNode> row = [];
          if (r > 0 && rAtoms.isNotEmpty && rAtoms[0].textChar != null) {
            row.add(LyricTimeTag(time: _formatTime(rAtoms[0].activeTime)));
          } else if (r > 0 &&
              rAtoms.isNotEmpty &&
              rAtoms[0].originalNode is LyricRuby) {
            row.add(LyricTimeTag(time: _formatTime(rAtoms[0].activeTime)));
          }

          for (int i = 0; i < rAtoms.length; i++) {
            var atom = rAtoms[i];
            if (atom.textChar != null) {
              var newTextNode = LyricText(atom.textChar!);
              row.add(newTextNode);
              nodeStartTimes[newTextNode] = atom.activeTime;
              nodeEndTimes[newTextNode] = atom.nextTime;
            } else {
              row.add(atom.originalNode);
            }
          }

          rows.add(row);
          double rw =
              rAtoms.last.accumulatedWidth -
              (rAtoms.first.accumulatedWidth - rAtoms.first.width);
          rowWidths.add(rw);
        }
      }

      for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        rows[rowIndex] = _splitTextNodesForAssGrid(
          rows[rowIndex],
          nodeStartTimes,
          nodeEndTimes,
          fs,
          lineSpacingVal,
          textMetrics,
        );
      }

      // Wrapped rows keep their source line's alignment slot, but each row gets
      // its own singer state for avatar placement and collision-safe layout.
      var activeSingerIndex = lineSingerMap[line];
      final rowLeadingSingerIndices = <int?>[];
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final normalizedRow = <LyricNode>[];
        var leadingSingerIndex = activeSingerIndex;
        var hasVisibleLyrics = false;

        for (final node in rows[rowIndex]) {
          if (node is _SingerMarkerNode) {
            activeSingerIndex = node.singerIndex;
            final isLeading = !hasVisibleLyrics;
            if (isLeading) leadingSingerIndex = node.singerIndex;
            normalizedRow.add(
              _SingerMarkerNode(
                singerIndex: node.singerIndex,
                isLeading: isLeading,
                displayText: node.text,
              ),
            );
            continue;
          }

          normalizedRow.add(node);
          if (node is LyricRuby ||
              (node is LyricText && node.text.isNotEmpty)) {
            hasVisibleLyrics = true;
          }
        }
        rows[rowIndex] = normalizedRow;
        rowLeadingSingerIndices.add(leadingSingerIndex);
      }

      width = rowWidths.isEmpty ? 0 : rowWidths.reduce((a, b) => a > b ? a : b);
      final lineData = AssLineData(
        astLine: line,
        rows: rows,
        rowWidths: rowWidths,
        width: width,
        startTime: startTime,
        endTime: endTime,
        rowLeadingSingerIndices: rowLeadingSingerIndices,
        nodeStartTimes: nodeStartTimes,
        nodeEndTimes: nodeEndTimes,
      );

      if (currentBlock.isNotEmpty) {
        final gap = startTime - currentBlock.last.endTime;
        final threshold = settings.pagingMode == AssPagingMode.auto2Lines
            ? 4000
            : settings.interludeThresholdSeconds * 1000;
        if (gap.inMilliseconds >= threshold) {
          blocks.add(AssBlock(List.from(currentBlock)));
          currentBlock.clear();
        }
      }

      if (settings.pagingMode == AssPagingMode.auto2Lines) {
        currentBlock.add(lineData);
        if (currentBlock.length == 2) {
          blocks.add(AssBlock(List.from(currentBlock)));
          currentBlock.clear();
        }
      } else {
        currentBlock.add(lineData);
        if (currentBlock.length == 4) {
          blocks.add(AssBlock(List.from(currentBlock)));
          currentBlock.clear();
        }
      }
    }
    if (currentBlock.isNotEmpty) blocks.add(AssBlock(currentBlock));
    return blocks;
  }

  static double _timingWidth(_Atom atom) =>
      atom.originalNode is _SingerMarkerNode ? 0 : atom.width;

  static AssLineAlignment _resolveLineAlignment(
    int slot,
    int totalLines,
    AssExportSettings settings,
  ) {
    if (totalLines <= 1) return AssLineAlignment.center;
    if (settings.pagingMode == AssPagingMode.auto2Lines) {
      return slot == 0 ? AssLineAlignment.left : AssLineAlignment.right;
    }

    final configured = switch (totalLines) {
      2 => settings.twoLineAlignments,
      3 => settings.threeLineAlignments,
      4 => settings.fourLineAlignments,
      _ => const <AssLineAlignment>[],
    };
    if (slot >= 0 && slot < configured.length) return configured[slot];

    final defaults = switch (totalLines) {
      2 => kDefaultTwoLineAlignments,
      3 => kDefaultThreeLineAlignments,
      _ => kDefaultFourLineAlignments,
    };
    final fallbackSlot = slot < 0
        ? 0
        : slot >= defaults.length
        ? defaults.length - 1
        : slot;
    return defaults[fallbackSlot];
  }

  static void _writeBlock(
    StringBuffer sb,
    AssBlock block,
    AssExportSettings settings,
    Map<int, Duration> yEndTimes,
    Duration lastInterludeEnd,
    Map<String, _AssAvatarDrawing> avatarDrawings,
    _AssTextMetrics textMetrics,
  ) {
    if (block.lines.isEmpty) return;

    int playResX = getPlayResX(settings);
    int playResY = getPlayResY(settings);

    final double centerX = playResX / 2;
    final fs = settings.fontSize.toDouble();

    double hMargin = settings.horizontalMargin.toDouble();
    final lineAlignments = <AssLineAlignment>[];
    final lineLayoutWidths = <double>[];
    for (var index = 0; index < block.lines.length; index++) {
      final slot = settings.pagingMode == AssPagingMode.auto2Lines
          ? index % 2
          : index;
      lineAlignments.add(
        _resolveLineAlignment(slot, block.lines.length, settings),
      );
      lineLayoutWidths.add(block.lines[index].width);
    }

    final partners = List<int?>.filled(block.lines.length, null);
    bool areOpposite(int first, int second) {
      final firstAlignment = lineAlignments[first];
      final secondAlignment = lineAlignments[second];
      return (firstAlignment == AssLineAlignment.left &&
              secondAlignment == AssLineAlignment.right) ||
          (firstAlignment == AssLineAlignment.right &&
              secondAlignment == AssLineAlignment.left);
    }

    // Preserve the standard two-line layout for each adjacent left/right pair.
    for (var index = 0; index + 1 < block.lines.length; index += 2) {
      if (areOpposite(index, index + 1)) {
        partners[index] = index + 1;
        partners[index + 1] = index;
      }
    }
    for (var index = 0; index < block.lines.length; index++) {
      if (partners[index] != null ||
          lineAlignments[index] == AssLineAlignment.center) {
        continue;
      }
      int? nearest;
      for (var candidate = 0; candidate < block.lines.length; candidate++) {
        if (candidate == index || !areOpposite(index, candidate)) continue;
        if (nearest == null ||
            (candidate - index).abs() < (nearest - index).abs()) {
          nearest = candidate;
        }
      }
      partners[index] = nearest;
    }

    final lineBoxLefts = <double>[];
    final lineBoxRights = <double>[];
    for (var index = 0; index < block.lines.length; index++) {
      final partner = partners[index];
      final oppositeWidth = partner == null ? 0.0 : lineLayoutWidths[partner];
      final emptySpace =
          playResX - hMargin * 2 - lineLayoutWidths[index] - oppositeWidth + fs;
      final offset = emptySpace > 0 ? emptySpace / 2 : 0.0;
      lineBoxLefts.add(hMargin + offset);
      lineBoxRights.add(playResX - hMargin - offset);
    }

    final layoutSpacingEm = settings.letterSpacingEm ?? 0;
    final defaultRubyFontSize = _resolveRubyFontSize(fs, null);
    final rubyFontSize = _resolveRubyFontSize(fs, settings.rubyFontSize);
    final automaticLineSpacing =
        fs * 2 +
        textMetrics.baseLayoutEdgeWidth +
        fs * layoutSpacingEm * 2 +
        (rubyFontSize - defaultRubyFontSize);
    final lineSpacing =
        settings.lineSpacing?.toDouble() ?? automaticLineSpacing;

    final avatarHorizontalGap = max(4.0, fs * 0.06);
    final avatarVerticalGap =
        settings.singerAvatarGap.toDouble() +
        _resolveFontOutlineWidth(fs, settings.fontOutlineWidth) +
        settings.outlineWidth * 0.5;
    // Reserve one identical avatar area per visual row. Using each bitmap's
    // rendered height would give the same lyric row a different Y coordinate
    // for square, portrait, and landscape avatars.
    final avatarSlotHeight = avatarDrawings.isEmpty
        ? 0.0
        : _resolveSingerAvatarSize(settings) + avatarVerticalGap;

    int totalRows = 0;
    for (var l in block.lines) {
      totalRows += l.rows.length;
    }
    final totalAvatarHeight = totalRows * avatarSlotHeight;

    final lastDrawBottom = playResY - settings.lyricsBottomMargin.toDouble();
    final double yLast = textMetrics.assCenterYForDrawBottom(
      lastDrawBottom,
      fs,
    );
    double startY = yLast - ((totalRows - 1) * lineSpacing) - totalAvatarHeight;

    if (settings.pagingMode == AssPagingMode.emptyLineDelimited &&
        block.lines.length == 1 &&
        totalRows > 0) {
      final line = block.lines.first;
      final expectedDisplayStarts = <Duration>[];
      for (var rowIndex = 0; rowIndex < line.rows.length; rowIndex++) {
        var rowStart = line.startTime;
        for (final node in line.rows[rowIndex]) {
          final nodeStart = line.nodeStartTimes[node];
          if (nodeStart != null) {
            rowStart = nodeStart;
            break;
          }
        }
        final expected = rowStart - const Duration(seconds: 3);
        expectedDisplayStarts.add(
          expected < Duration.zero ? Duration.zero : expected,
        );
      }

      final maximumShift = max(0, 4 - totalRows);
      for (var shift = 0; shift <= maximumShift; shift++) {
        final candidateStartY =
            startY - shift * (lineSpacing + avatarSlotHeight);
        var available = true;
        for (var rowIndex = 0; rowIndex < totalRows; rowIndex++) {
          final candidateY =
              candidateStartY + rowIndex * (lineSpacing + avatarSlotHeight);
          final previousEnd = yEndTimes[candidateY.round()];
          if (previousEnd != null &&
              expectedDisplayStarts[rowIndex] < previousEnd) {
            available = false;
            break;
          }
        }
        if (available) {
          startY = candidateStartY;
          break;
        }
      }
    }

    if (settings.pagingMode == AssPagingMode.auto2Lines && totalRows == 1) {
      Duration expectedDisplayStart =
          block.lines.first.startTime - const Duration(milliseconds: 3000);
      int roundedYLast = (yLast - avatarSlotHeight).round();
      if (yEndTimes.containsKey(roundedYLast)) {
        if (expectedDisplayStart < yEndTimes[roundedYLast]!) {
          startY -= lineSpacing + avatarSlotHeight;
        }
      }
    }

    // Countdown logic
    final stanzaStart = block.lines.first.startTime;
    Duration firstSingStart = stanzaStart;

    Duration preludeStart = firstSingStart - const Duration(milliseconds: 3000);
    if (preludeStart < lastInterludeEnd) preludeStart = lastInterludeEnd;

    Duration maxYEnd = Duration.zero;
    for (var endT in yEndTimes.values) {
      if (endT > maxYEnd) maxYEnd = endT;
    }
    if (preludeStart < maxYEnd) preludeStart = maxYEnd;

    bool isFirstBlock = (lastInterludeEnd == Duration.zero);
    bool hasInterludeText =
        (stanzaStart - lastInterludeEnd).inMilliseconds >
        settings.interludeThresholdSeconds * 1000;

    bool hasCountdown = false;
    if (isFirstBlock || hasInterludeText) {
      if (firstSingStart - preludeStart >= const Duration(seconds: 3)) {
        hasCountdown = true;
        final firstRowWidth = block.lines.first.rowWidths.first;
        final firstAlign = lineAlignments.first;
        double lineStartX = firstAlign == AssLineAlignment.left
            ? lineBoxLefts.first
            : firstAlign == AssLineAlignment.right
            ? lineBoxRights.first - firstRowWidth
            : centerX - firstRowWidth / 2;
        final countdownScale = settings.resolutionHeight / 1080.0;
        final circleDiameter = _countdownCircleDiameter * countdownScale;
        final circleScale = circleDiameter / _countdownCircleDiameter * 100.0;
        final countdownOutlineWidth = _countdownOutlineWidth * countdownScale;
        final centerSpacing = _countdownCenterSpacing * countdownScale;
        final baseOutlineWidth = _resolveFontOutlineWidth(
          settings.fontSize.toDouble(),
          settings.fontOutlineWidth,
        );
        final spacing = _resolveSpacing(fs, settings.letterSpacingEm);
        final firstPlacement = _firstVisibleAssPlacement(
          row: block.lines.first.rows.first,
          fontSize: fs,
          spacing: spacing,
          letterSpacingEm: settings.letterSpacingEm,
          rubyFontSize: settings.rubyFontSize,
          textMetrics: textMetrics,
        );
        double firstOutlinedLeftX = lineStartX - baseOutlineWidth;
        if (firstPlacement != null) {
          firstOutlinedLeftX = lineStartX + firstPlacement.visualLeft;
        }
        final firstCenterX =
            firstOutlinedLeftX + circleDiameter / 2 + countdownOutlineWidth;
        final centerY = startY - _countdownCenterOffsetY * countdownScale;
        final cellCenterOffset = _countdownCellCenterOffset * countdownScale;
        final clipHalfHeight = _countdownClipHalfHeight * countdownScale;
        final vectorTags =
            '\\an5\\fscx${_formatAssNumber(circleScale)}'
            '\\fscy${_formatAssNumber(circleScale)}'
            '\\bord${_formatAssNumber(countdownOutlineWidth)}'
            '\\shad0\\blur0\\be0\\p1';

        final nextSingerIndex = block.lines.first.rowLeadingSingerIndices.first;
        final nextSinger = nextSingerIndex != null
            ? settings.singerColors[nextSingerIndex]
            : null;
        final countdownUnsungTextColor =
            nextSinger?.unsungTextColor ?? settings.unsungTextColor;
        final countdownUnsungOutlineColor =
            nextSinger?.unsungOutlineColor ?? settings.unsungOutlineColor;
        final countdownSungTextColor =
            nextSinger?.sungTextColor ?? settings.sungTextColor;
        final countdownSungOutlineColor =
            nextSinger?.sungOutlineColor ?? settings.sungOutlineColor;

        for (int dotIndex = 0; dotIndex < 3; dotIndex++) {
          final circleCenterX = firstCenterX + centerSpacing * dotIndex;
          final cellLeft = circleCenterX - cellCenterOffset;
          final tStart = dotIndex * 1000;
          final tEnd = tStart + 1000;

          _writeSyllableClip(
            sb: sb,
            rawText: _countdownCircleDrawing,
            style: 'CountdownVector',
            alignmentTag: vectorTags,
            posX: circleCenterX,
            posY: centerY,
            x: cellLeft,
            y: centerY,
            w: centerSpacing,
            outW: countdownOutlineWidth,
            tStart: tStart,
            tEnd: tEnd,
            displayStart: preludeStart,
            displayEnd: firstSingStart,
            fs: clipHalfHeight,
            layer: 0,
            textColor: countdownUnsungTextColor,
            outlineColor: countdownUnsungOutlineColor,
            reverseClip: true,
            clipHeightFactor: 1.0,
          );

          _writeSyllableClip(
            sb: sb,
            rawText: _countdownCircleDrawing,
            style: 'CountdownVector',
            alignmentTag: vectorTags,
            posX: circleCenterX,
            posY: centerY,
            x: cellLeft,
            y: centerY,
            w: centerSpacing,
            outW: countdownOutlineWidth,
            tStart: tStart,
            tEnd: tEnd,
            displayStart: preludeStart,
            displayEnd: firstSingStart,
            fs: clipHalfHeight,
            layer: 0,
            textColor: countdownSungTextColor,
            outlineColor: countdownSungOutlineColor,
            clipHeightFactor: 1.0,
          );
        }
      }
    }

    int currentVisualRow = 0;
    double currentAvatarOffset = 0;
    for (int i = 0; i < block.lines.length; i++) {
      final lineData = block.lines[i];

      List<double> startXs = [];
      List<double> ys = [];
      List<Duration> displayStarts = [];
      List<Duration> displayEnds = [];

      for (int r = 0; r < lineData.rows.length; r++) {
        final rowWidth = lineData.rowWidths[r];
        final y = startY + currentVisualRow * lineSpacing + currentAvatarOffset;

        // Compute per-row start/end times from actual node timing
        Duration rowStartTime = lineData.startTime;
        Duration rowEndTime = lineData.endTime;
        final rowNodes = lineData.rows[r];
        for (var node in rowNodes) {
          if (lineData.nodeStartTimes.containsKey(node)) {
            rowStartTime = lineData.nodeStartTimes[node]!;
            break;
          }
        }
        for (var node in rowNodes.reversed) {
          if (lineData.nodeEndTimes.containsKey(node)) {
            rowEndTime = lineData.nodeEndTimes[node]!;
            break;
          }
        }

        Duration displayStart =
            rowStartTime - const Duration(milliseconds: 3000);
        if (i == 0 && r == 0 && preludeStart < displayStart && hasCountdown) {
          displayStart = preludeStart;
        }
        Duration displayEnd = rowEndTime + const Duration(milliseconds: 200);

        double x = centerX;
        final align = lineAlignments[i];
        if (align == AssLineAlignment.left) {
          x = lineBoxLefts[i];
        } else if (align == AssLineAlignment.right) {
          x = lineBoxRights[i] - rowWidth;
        } else {
          x = centerX - rowWidth / 2;
        }

        int roundedY = y.round();
        if (yEndTimes.containsKey(roundedY) &&
            displayStart < yEndTimes[roundedY]!) {
          displayStart = yEndTimes[roundedY]!;
        }
        if (displayStart < Duration.zero) displayStart = Duration.zero;

        yEndTimes[roundedY] = displayEnd;

        startXs.add(x);
        ys.add(y);
        displayStarts.add(displayStart);
        displayEnds.add(displayEnd);
        currentVisualRow++;
        currentAvatarOffset += avatarSlotHeight;
      }

      int? sIdx = lineData.rowLeadingSingerIndices.first;
      _writeLine(
        sb,
        lineData,
        startXs,
        ys,
        displayStarts,
        displayEnds,
        fs,
        settings,
        sIdx,
        textMetrics,
      );

      for (var rowIndex = 0; rowIndex < lineData.rows.length; rowIndex++) {
        final avatars = _avatarsForSinger(
          settings,
          lineData.rowLeadingSingerIndices[rowIndex],
          avatarDrawings,
        );
        final inlinePlacements = _inlineSingerMarkerPlacements(
          row: lineData.rows[rowIndex],
          startX: startXs[rowIndex],
          fontSize: fs,
          spacing: _resolveSpacing(fs, settings.letterSpacingEm),
          settings: settings,
          textMetrics: textMetrics,
        );
        var hasAvatar = avatars.isNotEmpty;
        if (!hasAvatar) {
          for (final placement in inlinePlacements) {
            if (_avatarsForSinger(
              settings,
              placement.singerIndex,
              avatarDrawings,
            ).isNotEmpty) {
              hasAvatar = true;
              break;
            }
          }
        }

        if (hasAvatar) {
          final avatarTop = ys[rowIndex] + fs * 0.8 + avatarVerticalGap;
          _writeSingerAvatars(
            sb: sb,
            avatars: avatars,
            left: startXs[rowIndex],
            top: avatarTop,
            gap: avatarHorizontalGap,
            displayStart: displayStarts[rowIndex],
            displayEnd: displayEnds[rowIndex],
          );
          for (final placement in inlinePlacements) {
            _writeSingerAvatars(
              sb: sb,
              avatars: _avatarsForSinger(
                settings,
                placement.singerIndex,
                avatarDrawings,
              ),
              left: placement.left,
              top: avatarTop,
              gap: avatarHorizontalGap,
              displayStart: displayStarts[rowIndex],
              displayEnd: displayEnds[rowIndex],
            );
          }
        }
      }
    }
  }

  static List<_InlineSingerMarkerPlacement> _inlineSingerMarkerPlacements({
    required List<LyricNode> row,
    required double startX,
    required double fontSize,
    required double spacing,
    required AssExportSettings settings,
    required _AssTextMetrics textMetrics,
  }) {
    final result = <_InlineSingerMarkerPlacement>[];
    var currentX = startX;
    for (final node in row) {
      if (node is _SingerMarkerNode && !node.isLeading) {
        result.add(
          _InlineSingerMarkerPlacement(
            singerIndex: node.singerIndex,
            left: currentX,
          ),
        );
      }
      if (node is LyricText) {
        currentX += _getCharWidth(node.text, fontSize, spacing, textMetrics);
      } else if (node is LyricRuby) {
        currentX += _getRubyNodeWidth(
          node,
          fontSize,
          spacing,
          settings.letterSpacingEm,
          settings.rubyFontSize,
          textMetrics,
        );
      }
    }
    return result;
  }

  static List<_AssAvatarDrawing> _avatarsForSinger(
    AssExportSettings settings,
    int? singerIndex,
    Map<String, _AssAvatarDrawing> avatarDrawings,
  ) {
    if (singerIndex == null ||
        singerIndex < 0 ||
        singerIndex >= settings.singerColors.length) {
      return const [];
    }
    final result = <_AssAvatarDrawing>[];
    final seen = <String>{};
    for (final part in settings.singerColors[singerIndex].prefix.split('/')) {
      final singerName = part.trim();
      if (singerName.isEmpty || !seen.add(singerName)) continue;
      final drawing = avatarDrawings[singerName];
      if (drawing != null) result.add(drawing);
    }
    return result;
  }

  static void _writeSingerAvatars({
    required StringBuffer sb,
    required List<_AssAvatarDrawing> avatars,
    required double left,
    required double top,
    required double gap,
    required Duration displayStart,
    required Duration displayEnd,
  }) {
    var currentX = left;
    for (final avatar in avatars) {
      final scale = avatar.drawingScale * 100;
      for (final layer in avatar.layers) {
        final alpha = (255 - layer.opacity)
            .clamp(0, 255)
            .toInt()
            .toRadixString(16)
            .padLeft(2, '0')
            .toUpperCase();
        final tags =
            '\\an7\\pos(${currentX.toStringAsFixed(1)},${top.toStringAsFixed(1)})'
            '\\p1\\fscx${scale.toStringAsFixed(3)}\\fscy${scale.toStringAsFixed(3)}'
            '\\bord0\\shad0\\blur0\\1c${_colorToAss(layer.color)}\\1a&H$alpha&';
        sb.writeln(
          'Dialogue: 2,${_formatTime(displayStart)},${_formatTime(displayEnd)},SingerAvatar,,0,0,0,,{$tags}${layer.drawing}',
        );
      }
      currentX += avatar.width + gap;
    }
  }

  static void _writeLine(
    StringBuffer sb,
    AssLineData lineData,
    List<double> startXs,
    List<double> ys,
    List<Duration> displayStarts,
    List<Duration> displayEnds,
    double fs,
    AssExportSettings settings,
    int? sIdx,
    _AssTextMetrics textMetrics,
  ) {
    double rubyFs = _resolveRubyFontSize(fs, settings.rubyFontSize);

    double spacing = _resolveSpacing(fs, settings.letterSpacingEm);
    double rubySpacing = _resolveRubySpacing(rubyFs, settings.letterSpacingEm);
    double outW = settings.outlineWidth.toDouble();
    double rubyOut = (settings.outlineWidth * 5 / 7).roundToDouble();

    double baseOutW = _resolveFontOutlineWidth(fs, settings.fontOutlineWidth);
    double rubyBaseOutW = _resolveRubyBaseOutlineWidth(
      baseOutW,
      fs,
      rubyFs,
      settings.rubyOutlineWidth,
    );

    Duration currentTagTime = lineData.startTime;
    int? currentSingerIndex = sIdx;

    for (int r = 0; r < lineData.rows.length; r++) {
      final rowNodes = lineData.rows[r];
      double currentX = startXs[r];
      final y = ys[r];
      final displayStart = displayStarts[r];
      final displayEnd = displayEnds[r];

      for (int i = 0; i < rowNodes.length; i++) {
        var node = rowNodes[i];
        if (node is LyricTimeTag && node.time.isNotEmpty) {
          currentTagTime = _parseTime(node.time);
        } else if (node is LyricText || node is LyricRuby) {
          if (node is _SingerMarkerNode) {
            currentSingerIndex = node.singerIndex;
          }
          final singer = currentSingerIndex != null
              ? settings.singerColors[currentSingerIndex]
              : null;
          final sungTextColor = singer?.sungTextColor ?? settings.sungTextColor;
          final sungOutlineColor =
              singer?.sungOutlineColor ?? settings.sungOutlineColor;
          final sungDecorationColor =
              singer?.sungDecorationColor ?? settings.sungDecorationColor;
          final unsungTextColor =
              singer?.unsungTextColor ?? settings.unsungTextColor;
          final unsungOutlineColor =
              singer?.unsungOutlineColor ?? settings.unsungOutlineColor;
          final unsungDecorationColor =
              singer?.unsungDecorationColor ?? settings.unsungDecorationColor;
          Duration activeTime = lineData.nodeStartTimes[node] ?? currentTagTime;
          Duration nextTagTime = lineData.nodeEndTimes[node] ?? currentTagTime;
          currentTagTime = nextTagTime;

          double w = 0;
          if (node is LyricText) {
            w = _getCharWidth(node.text, fs, spacing, textMetrics);
          } else if (node is LyricRuby) {
            w = _getRubyNodeWidth(
              node,
              fs,
              spacing,
              settings.letterSpacingEm,
              settings.rubyFontSize,
              textMetrics,
            );
          }

          bool isLastNode = true;
          for (int j = i + 1; j < rowNodes.length; j++) {
            if (rowNodes[j] is LyricText || rowNodes[j] is LyricRuby) {
              isLastNode = false;
              break;
            }
          }
          if (isLastNode) {
            for (int nextR = r + 1; nextR < lineData.rows.length; nextR++) {
              for (var n in lineData.rows[nextR]) {
                if (n is LyricText || n is LyricRuby) {
                  isLastNode = false;
                  break;
                }
              }
              if (!isLastNode) break;
            }
          }

          if (node is LyricText) {
            final textPlacements = _layoutAssText(
              text: node.text,
              centerX: currentX + w / 2,
              fontSize: fs,
              spacing: spacing,
              textMetrics: textMetrics,
            );
            int tStart = (activeTime - displayStart).inMilliseconds;
            int tEnd = (nextTagTime - displayStart).inMilliseconds;

            for (final placement in textPlacements) {
              _writeGlowLayers(
                sb: sb,
                rawText: placement.text,
                style: 'DefaultUnsung',
                alignmentTag: placement.alignmentTag,
                posX: placement.centerX,
                posY: y,
                visualY: y,
                fontSize: fs,
                baseOutlineWidth: baseOutW,
                decorationWidth: outW,
                blurLevel: settings.blurLevel,
                tStart: tStart,
                tEnd: tEnd,
                displayStart: displayStart,
                displayEnd: displayEnd,
                color: unsungDecorationColor,
                fadesIn: false,
              );
              _writeGlowLayers(
                sb: sb,
                rawText: placement.text,
                style: 'DefaultUnsung',
                alignmentTag: placement.alignmentTag,
                posX: placement.centerX,
                posY: y,
                visualY: y,
                fontSize: fs,
                baseOutlineWidth: baseOutW,
                decorationWidth: outW,
                blurLevel: settings.blurLevel,
                tStart: tStart,
                tEnd: tEnd,
                displayStart: displayStart,
                displayEnd: displayEnd,
                color: sungDecorationColor,
                fadesIn: true,
              );

              _writeSyllableClip(
                sb: sb,
                rawText: placement.text,
                style: 'DefaultUnsung',
                alignmentTag: placement.alignmentTag,
                posX: placement.centerX,
                posY: y,
                x: currentX,
                y: y,
                w: w,
                outW: baseOutW + outW,
                tStart: tStart,
                tEnd: tEnd,
                displayStart: displayStart,
                displayEnd: displayEnd,
                fs: fs,
                layer: 1,
                reverseClip: true,
                textColor: unsungTextColor,
                outlineColor: unsungOutlineColor,
              );

              _writeSyllableClip(
                sb: sb,
                rawText: placement.text,
                style: 'DefaultSung',
                alignmentTag: placement.alignmentTag,
                posX: placement.centerX,
                posY: y,
                x: currentX,
                y: y,
                w: w,
                outW: baseOutW + outW,
                tStart: tStart,
                tEnd: tEnd,
                displayStart: displayStart,
                displayEnd: displayEnd,
                fs: fs,
                layer: 1,
                textColor: sungTextColor,
                outlineColor: sungOutlineColor,
              );
            }
          } else if (node is LyricRuby) {
            double cx = currentX + w / 2;
            int tStart = (activeTime - displayStart).inMilliseconds;
            int tEnd = (nextTagTime - displayStart).inMilliseconds;
            final basePlacements = _layoutAssText(
              text: node.baseText,
              centerX: cx,
              fontSize: fs,
              spacing: spacing,
              textMetrics: textMetrics,
            );

            for (final placement in basePlacements) {
              _writeGlowLayers(
                sb: sb,
                rawText: placement.text,
                style: 'DefaultUnsung',
                alignmentTag: placement.alignmentTag,
                posX: placement.centerX,
                posY: y,
                visualY: y,
                fontSize: fs,
                baseOutlineWidth: baseOutW,
                decorationWidth: outW,
                blurLevel: settings.blurLevel,
                tStart: tStart,
                tEnd: tEnd,
                displayStart: displayStart,
                displayEnd: displayEnd,
                color: unsungDecorationColor,
                fadesIn: false,
              );
              _writeGlowLayers(
                sb: sb,
                rawText: placement.text,
                style: 'DefaultUnsung',
                alignmentTag: placement.alignmentTag,
                posX: placement.centerX,
                posY: y,
                visualY: y,
                fontSize: fs,
                baseOutlineWidth: baseOutW,
                decorationWidth: outW,
                blurLevel: settings.blurLevel,
                tStart: tStart,
                tEnd: tEnd,
                displayStart: displayStart,
                displayEnd: displayEnd,
                color: sungDecorationColor,
                fadesIn: true,
              );
            }

            final rubyY = textMetrics.rubyCenterYFromBaseCenter(
              y,
              baseFontSize: fs,
              rubyFontSize: rubyFs,
              rubyGap: settings.rubyBaseGap?.toDouble() ?? 0,
            );
            final rubyText = StringBuffer();
            for (var rNode in node.rubyNodes) {
              if (rNode is LyricText) {
                rubyText.write(rNode.text.replaceAll('＋', ''));
              }
            }
            final visibleText = rubyText.toString();
            final rw = _getCharWidth(
              visibleText,
              rubyFs,
              rubySpacing,
              textMetrics,
            );
            final rubyPlacements = _layoutAssText(
              text: visibleText,
              centerX: cx,
              fontSize: rubyFs,
              spacing: rubySpacing,
              textMetrics: textMetrics,
            );

            double kLeft = currentX - (baseOutW + outW) * 4.0;
            double kRight = currentX + w + (baseOutW + outW) * 4.0;

            List<String> baseChars = node.baseText.characters.toList();
            List<double> baseWidths = baseChars
                .map((c) => _getCharWidth(c, fs, spacing, textMetrics))
                .toList();
            double totalBaseW = baseWidths.fold(0.0, (a, b) => a + b);

            List<Map<String, dynamic>> chunks = [];
            Duration currentChunkStart = activeTime;
            String currentChunkText = '';

            bool hasFirstTag = false;

            for (int rIdx = 0; rIdx < node.rubyNodes.length; rIdx++) {
              var rNode = node.rubyNodes[rIdx];
              if (rNode is LyricTimeTag && rNode.time.isNotEmpty) {
                if (!hasFirstTag) {
                  if (currentChunkText.isEmpty && chunks.isEmpty) {
                    currentChunkStart = _parseTime(rNode.time);
                  } else {
                    chunks.add({
                      'start': currentChunkStart,
                      'end': _parseTime(rNode.time),
                      'text': currentChunkText,
                    });
                    currentChunkStart = _parseTime(rNode.time);
                    currentChunkText = '';
                  }
                  hasFirstTag = true;
                } else {
                  chunks.add({
                    'start': currentChunkStart,
                    'end': _parseTime(rNode.time),
                    'text': currentChunkText,
                  });
                  currentChunkStart = _parseTime(rNode.time);
                  currentChunkText = '';
                }
              } else if (rNode is LyricText) {
                currentChunkText += rNode.text;
              }
            }
            chunks.add({
              'start': currentChunkStart,
              'end': nextTagTime,
              'text': currentChunkText,
            });

            double totalLogicalW = 0;
            for (var chunk in chunks) {
              String text = chunk['text'] as String;
              double chunkLogicalW = 0;
              for (final char in text.characters) {
                if (char == '＋') {
                  chunkLogicalW += _getCharWidth(
                    'あ',
                    rubyFs,
                    rubySpacing,
                    textMetrics,
                  );
                } else {
                  chunkLogicalW += _getCharWidth(
                    char,
                    rubyFs,
                    rubySpacing,
                    textMetrics,
                  );
                }
              }
              chunk['logicalW'] = chunkLogicalW;
              totalLogicalW += chunkLogicalW;
            }

            double currentRubyX = cx - rw / 2;

            double rkLeft = currentRubyX - (rubyBaseOutW + rubyOut) * 4.0;
            double rkRight = currentRubyX + rw + (rubyBaseOutW + rubyOut) * 4.0;

            int numSegments = chunks.length;
            int segmentIdx = 0;
            double accumulatedBasePercentage = 0;
            final baseSegments = <_WipeSegment>[];
            final rubySegments = <_WipeSegment>[];

            for (var chunk in chunks) {
              int rStart =
                  (chunk['start'] as Duration).inMilliseconds -
                  displayStart.inMilliseconds;
              int rEnd =
                  (chunk['end'] as Duration).inMilliseconds -
                  displayStart.inMilliseconds;

              double percentage;
              if (numSegments == baseChars.length && totalBaseW > 0) {
                percentage = baseWidths[segmentIdx] / totalBaseW;
              } else {
                percentage = (totalLogicalW > 0)
                    ? ((chunk['logicalW'] as double) / totalLogicalW)
                    : 1.0;
              }

              double sliceW = w * percentage;
              double sliceLeftX = currentX + w * accumulatedBasePercentage;
              double sliceRightX = sliceLeftX + sliceW;

              double rSliceW = rw * percentage;
              double rSliceLeftX =
                  currentRubyX + rw * accumulatedBasePercentage;
              double rSliceRightX = rSliceLeftX + rSliceW;

              baseSegments.add(
                _WipeSegment(
                  start: rStart,
                  end: rEnd,
                  left: sliceLeftX,
                  right: sliceRightX,
                ),
              );
              rubySegments.add(
                _WipeSegment(
                  start: rStart,
                  end: rEnd,
                  left: rSliceLeftX,
                  right: rSliceRightX,
                ),
              );

              segmentIdx++;
              accumulatedBasePercentage += percentage;
            }

            for (final placement in basePlacements) {
              _writeGradientSweepDialogue(
                sb: sb,
                rawText: placement.text,
                style: 'DefaultUnsung',
                alignmentTag: placement.alignmentTag,
                posX: placement.centerX,
                posY: y,
                visualY: y,
                fontSize: fs,
                textColor: unsungTextColor,
                outlineColor: unsungOutlineColor,
                fullLeft: kLeft,
                fullRight: kRight,
                initialX: currentX,
                segments: baseSegments,
                tEnd: tEnd,
                reverse: true,
                displayStart: displayStart,
                displayEnd: displayEnd,
              );
              _writeGradientSweepDialogue(
                sb: sb,
                rawText: placement.text,
                style: 'DefaultSung',
                alignmentTag: placement.alignmentTag,
                posX: placement.centerX,
                posY: y,
                visualY: y,
                fontSize: fs,
                textColor: sungTextColor,
                outlineColor: sungOutlineColor,
                fullLeft: kLeft,
                fullRight: kRight,
                initialX: currentX,
                segments: baseSegments,
                tEnd: tEnd,
                reverse: false,
                displayStart: displayStart,
                displayEnd: displayEnd,
              );
            }

            if (visibleText.isNotEmpty) {
              for (final placement in rubyPlacements) {
                _writeGlowLayers(
                  sb: sb,
                  rawText: placement.text,
                  style: 'RubyUnsung',
                  alignmentTag: placement.alignmentTag,
                  posX: placement.centerX,
                  posY: rubyY,
                  visualY: rubyY,
                  fontSize: rubyFs,
                  baseOutlineWidth: rubyBaseOutW,
                  decorationWidth: rubyOut,
                  blurLevel: settings.blurLevel,
                  tStart: tStart,
                  tEnd: tEnd,
                  displayStart: displayStart,
                  displayEnd: displayEnd,
                  color: unsungDecorationColor,
                  fadesIn: false,
                );
                _writeGlowLayers(
                  sb: sb,
                  rawText: placement.text,
                  style: 'RubyUnsung',
                  alignmentTag: placement.alignmentTag,
                  posX: placement.centerX,
                  posY: rubyY,
                  visualY: rubyY,
                  fontSize: rubyFs,
                  baseOutlineWidth: rubyBaseOutW,
                  decorationWidth: rubyOut,
                  blurLevel: settings.blurLevel,
                  tStart: tStart,
                  tEnd: tEnd,
                  displayStart: displayStart,
                  displayEnd: displayEnd,
                  color: sungDecorationColor,
                  fadesIn: true,
                );
                _writeGradientSweepDialogue(
                  sb: sb,
                  rawText: placement.text,
                  style: 'RubyUnsung',
                  alignmentTag: placement.alignmentTag,
                  posX: placement.centerX,
                  posY: rubyY,
                  visualY: rubyY,
                  fontSize: rubyFs,
                  textColor: unsungTextColor,
                  outlineColor: unsungOutlineColor,
                  fullLeft: rkLeft,
                  fullRight: rkRight,
                  initialX: currentRubyX,
                  segments: rubySegments,
                  tEnd: tEnd,
                  reverse: true,
                  displayStart: displayStart,
                  displayEnd: displayEnd,
                );
                _writeGradientSweepDialogue(
                  sb: sb,
                  rawText: placement.text,
                  style: 'RubySung',
                  alignmentTag: placement.alignmentTag,
                  posX: placement.centerX,
                  posY: rubyY,
                  visualY: rubyY,
                  fontSize: rubyFs,
                  textColor: sungTextColor,
                  outlineColor: sungOutlineColor,
                  fullLeft: rkLeft,
                  fullRight: rkRight,
                  initialX: currentRubyX,
                  segments: rubySegments,
                  tEnd: tEnd,
                  reverse: false,
                  displayStart: displayStart,
                  displayEnd: displayEnd,
                );
              }
            }
          }
          currentX += w;
        }
      }
    }
  }

  static void _writeSyllableClip({
    required StringBuffer sb,
    required String rawText,
    required String style,
    required String alignmentTag,
    required double posX,
    required double posY,
    required double x,
    required double y,
    required double w,
    required double outW,
    required int tStart,
    required int tEnd,
    required Duration displayStart,
    required Duration displayEnd,
    required double fs,
    required int layer,
    required AssColorValue textColor,
    required AssColorValue outlineColor,
    bool reverseClip = false,
    double clipHeightFactor = 1.5,
  }) {
    double clipTop = y - fs * clipHeightFactor;
    double clipBottom = y + fs * clipHeightFactor;
    double kLeft = x - outW * 4.0;
    double kRight = x + w + outW * 4.0;
    final bands = _gradientBands(
      clipTop: clipTop,
      clipBottom: clipBottom,
      gradientTop: y - fs * 0.5,
      gradientBottom: y + fs * 0.5,
      enabled: textColor.isGradient || outlineColor.isGradient,
    );

    for (final band in bands) {
      final colors =
          '\\1c${_assColorAt(textColor, band.position)}'
          '\\3c${_assColorAt(outlineColor, band.position)}';
      String tags =
          '{$alignmentTag\\pos(${posX.toStringAsFixed(1)},${posY.toStringAsFixed(1)})$colors';

      if (reverseClip) {
        String clipInit =
            '\\clip(${kLeft.toStringAsFixed(1)},${band.top.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${band.bottom.toStringAsFixed(1)})';
        String clipStart =
            '\\clip(${x.toStringAsFixed(1)},${band.top.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${band.bottom.toStringAsFixed(1)})';
        String clipEnd =
            '\\clip(${(x + w).toStringAsFixed(1)},${band.top.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${band.bottom.toStringAsFixed(1)})';
        String clipFinal = '\\clip(0,0,0,0)';

        tags +=
            '$clipInit'
            '\\t($tStart,${tStart + 1},$clipStart)'
            '\\t(${tStart + 1},$tEnd,$clipEnd)'
            '\\t($tEnd,${tEnd + 1},$clipFinal)}';
      } else {
        String clipInit =
            '\\clip(${x.toStringAsFixed(1)},${band.top.toStringAsFixed(1)},${x.toStringAsFixed(1)},${band.bottom.toStringAsFixed(1)})';
        String clipStart =
            '\\clip(${kLeft.toStringAsFixed(1)},${band.top.toStringAsFixed(1)},${x.toStringAsFixed(1)},${band.bottom.toStringAsFixed(1)})';
        String clipEnd =
            '\\clip(${kLeft.toStringAsFixed(1)},${band.top.toStringAsFixed(1)},${(x + w).toStringAsFixed(1)},${band.bottom.toStringAsFixed(1)})';
        String clipFinal =
            '\\clip(${kLeft.toStringAsFixed(1)},${band.top.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${band.bottom.toStringAsFixed(1)})';

        tags +=
            '$clipInit'
            '\\t($tStart,${tStart + 1},$clipStart)'
            '\\t(${tStart + 1},$tEnd,$clipEnd)'
            '\\t($tEnd,${tEnd + 1},$clipFinal)}';
      }

      sb.writeln(
        'Dialogue: $layer,${_formatTime(displayStart)},${_formatTime(displayEnd)},$style,,0,0,0,,$tags$rawText',
      );
    }
  }
}

class _GradientBand {
  final double top;
  final double bottom;
  final double position;

  const _GradientBand({
    required this.top,
    required this.bottom,
    required this.position,
  });
}

class _WipeSegment {
  final int start;
  final int end;
  final double left;
  final double right;

  const _WipeSegment({
    required this.start,
    required this.end,
    required this.left,
    required this.right,
  });
}

class _AssTextPlacement {
  final String text;
  final double centerX;
  final double visualLeft;
  final String alignmentTag;

  const _AssTextPlacement({
    required this.text,
    required this.centerX,
    required this.visualLeft,
    required this.alignmentTag,
  });
}

class _AssTextMetrics {
  final OpenTypeFontFace fontFace;
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

  double assFontSize(double fontSize) {
    // N3 treats the requested size as an em; libass normalizes it to the
    // hhea line box, so compensate with metrics from the selected font file.
    final metricsHeight = fontFace.ascent + fontFace.descent;
    if (fontFace.unitsPerEm <= 0 || metricsHeight <= 0) return fontSize;
    return fontSize * metricsHeight / fontFace.unitsPerEm;
  }

  double assCenterYForDrawBottom(double drawBottom, double fontSize) {
    final metricsHeight = fontFace.ascent + fontFace.descent;
    if (fontFace.unitsPerEm <= 0 || metricsHeight <= 0) {
      return drawBottom - fontSize / 2 - _layoutEdgeWidth(fontSize) / 2;
    }
    final directWriteDescent = fontSize * fontFace.descent / metricsHeight;
    final assBaselineFromCenter =
        fontSize *
        (fontFace.ascent - fontFace.descent) /
        (2 * fontFace.unitsPerEm);
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
        final fillLeft =
            cellLeft + glyph.geometryLeftOffset + glyph.edgeSize / 2;
        final center = fillLeft - glyph.xMin + glyph.advanceWidth / 2;
        placements.add(
          _AssTextPlacement(
            text: char,
            centerX: center,
            visualLeft: fillLeft - _outlineWidth(fontSize),
            alignmentTag:
                '\\fsp0'
                '\\fs${_formatNumber(assFontSize(fontSize))}\\an5',
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
      final scale = fontSize / fontFace.unitsPerEm;
      for (final rune in char.runes) {
        final metrics = fontFace.metricsForCodePoint(rune);
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
