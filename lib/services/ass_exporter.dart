import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../models/lyric_ast.dart';
import '../models/ass_export_settings.dart';
import 'font_service.dart';
import 'open_type_font.dart';

part 'ass_exporter/document.dart';
part 'ass_exporter/blocks.dart';
part 'ass_exporter/block_writer.dart';
part 'ass_exporter/line_writer.dart';
part 'ass_exporter/avatars.dart';
part 'ass_exporter/colors.dart';
part 'ass_exporter/text_layout.dart';

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

class AssExporter {
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
            if (settings.latinFont != null) LyricText(' ABC 123'),
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
      latinFont: settings.latinFont,
      fadeLyricLines: settings.fadeLyricLines,
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
    final latinFont = rawSettings.latinFont;
    final latinFontFace =
        latinFont != null &&
            (latinFont.path != rawSettings.customFontPath ||
                latinFont.faceIndex != rawSettings.fontFaceIndex)
        ? await FontService().loadSelectedFace(
            fontFilePath: latinFont.path,
            faceIndex: latinFont.faceIndex,
          )
        : null;
    AssExportSettings settings = AssExportSettings(
      fontName: rawSettings.customFontPath == null
          ? selectedFontFace.info.assFontName
          : selectedFontFace.info.assFaceName,
      customFontPath: rawSettings.customFontPath,
      fontFaceIndex: rawSettings.fontFaceIndex,
      latinFont: latinFont,
      fadeLyricLines: rawSettings.fadeLyricLines,
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
      latinFontFace: latinFontFace,
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
      final renderLine = _mergeJoinedRubyChains(processed.line);
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
}
