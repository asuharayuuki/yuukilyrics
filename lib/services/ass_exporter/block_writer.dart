part of '../ass_exporter.dart';

// Writing a page: countdown, inline singer markers and avatars.

// Fixed 1080p geometry measured from the default Kosugi Maru countdown.
// These values are intentionally independent of every lyric font setting.
const double _countdownCircleDiameter = 44.0;
const double _countdownOutlineWidth = 7.0;
const double _countdownCenterSpacing = 65.0;
const double _countdownCenterOffsetY = 142.5;
const double _countdownCellCenterOffset = 25.5;
const double _countdownClipHalfHeight = 51.0;
const String _countdownCircleDrawing =
    'm 22 0 b 34 0 44 10 44 22 '
    'b 44 34 34 44 22 44 '
    'b 10 44 0 34 0 22 '
    'b 0 10 10 0 22 0';

void _writeBlock(
  StringBuffer sb,
  AssBlock block,
  AssExportSettings settings,
  Map<int, Duration> yEndTimes,
  Duration lastInterludeEnd,
  Map<String, _AssAvatarDrawing> avatarDrawings,
  _AssTextMetrics textMetrics,
) {
  if (block.lines.isEmpty) return;

  int playResX = AssExporter.getPlayResX(settings);
  int playResY = AssExporter.getPlayResY(settings);

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

  // N3's SmartHorizon.Multi balances the page as three horizontal columns.
  // It uses the widest left-, center-, and right-aligned line and applies one
  // shared offset to every left/right line. Pairing individual lines makes
  // three-line pages ignore the center column and gives two left lines on a
  // four-line page different starting positions.
  var maxLeftWidth = 0.0;
  var maxCenterWidth = 0.0;
  var maxRightWidth = 0.0;
  var hasLeft = false;
  var hasRight = false;
  for (var index = 0; index < block.lines.length; index++) {
    switch (lineAlignments[index]) {
      case AssLineAlignment.left:
        hasLeft = true;
        maxLeftWidth = max(maxLeftWidth, lineLayoutWidths[index]);
      case AssLineAlignment.center:
        maxCenterWidth = max(maxCenterWidth, lineLayoutWidths[index]);
      case AssLineAlignment.right:
        hasRight = true;
        maxRightWidth = max(maxRightWidth, lineLayoutWidths[index]);
    }
  }

  var smartHorizonOffset = 0.0;
  if (hasLeft && hasRight) {
    final emptySpace =
        playResX -
        hMargin * 2 -
        maxLeftWidth -
        maxCenterWidth -
        maxRightWidth +
        fs;
    if (emptySpace > 0) smartHorizonOffset = emptySpace / 2;
  }

  final lineBoxLefts = List<double>.filled(
    block.lines.length,
    hMargin + smartHorizonOffset,
  );
  final lineBoxRights = List<double>.filled(
    block.lines.length,
    playResX - hMargin - smartHorizonOffset,
  );

  final layoutSpacingEm = settings.letterSpacingEm ?? 0;
  final defaultRubyFontSize = _resolveRubyFontSize(fs, null);
  final rubyFontSize = _resolveRubyFontSize(fs, settings.rubyFontSize);
  final automaticLineSpacing =
      fs * 2 +
      textMetrics.baseLayoutEdgeWidth +
      fs * layoutSpacingEm * 2 +
      (rubyFontSize - defaultRubyFontSize);
  final lineSpacing = settings.lineSpacing?.toDouble() ?? automaticLineSpacing;

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
  final double yLast = textMetrics.assCenterYForDrawBottom(lastDrawBottom, fs);
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
      final candidateStartY = startY - shift * (lineSpacing + avatarSlotHeight);
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

      Duration displayStart = rowStartTime - const Duration(milliseconds: 3000);
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
        final fade = _lyricFade(
          settings.fadeLyricLines,
          displayStarts[rowIndex],
          displayEnds[rowIndex],
        );
        _writeSingerAvatars(
          sb: sb,
          avatars: avatars,
          left: startXs[rowIndex],
          top: avatarTop,
          gap: avatarHorizontalGap,
          displayStart: displayStarts[rowIndex],
          displayEnd: displayEnds[rowIndex],
          fade: fade,
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
            fade: fade,
          );
        }
      }
    }
  }
}

List<_InlineSingerMarkerPlacement> _inlineSingerMarkerPlacements({
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

List<_AssAvatarDrawing> _avatarsForSinger(
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

void _writeSingerAvatars({
  required StringBuffer sb,
  required List<_AssAvatarDrawing> avatars,
  required double left,
  required double top,
  required double gap,
  required Duration displayStart,
  required Duration displayEnd,
  required String fade,
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
          '$fade\\an7\\pos(${currentX.toStringAsFixed(1)},${top.toStringAsFixed(1)})'
          '\\p1\\fscx${scale.toStringAsFixed(3)}\\fscy${scale.toStringAsFixed(3)}'
          '\\bord0\\shad0\\blur0\\1c${_colorToAss(layer.color)}\\1a&H$alpha&';
      sb.writeln(
        'Dialogue: 2,${_formatTime(displayStart)},${_formatTime(displayEnd)},SingerAvatar,,0,0,0,,{$tags}${layer.drawing}',
      );
    }
    currentX += avatar.width + gap;
  }
}
