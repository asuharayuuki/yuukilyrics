part of '../ass_exporter.dart';

// Writing one lyric line's base, ruby and karaoke sweep events.

void _writeLine(
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
    final fade = _lyricFade(settings.fadeLyricLines, displayStart, displayEnd);

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
              alignmentTag: '$fade${placement.alignmentTag}',
              posX: placement.centerX,
              posY: y + placement.centerYOffset,
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
              alignmentTag: '$fade${placement.alignmentTag}',
              posX: placement.centerX,
              posY: y + placement.centerYOffset,
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
              alignmentTag: '$fade${placement.alignmentTag}',
              posX: placement.centerX,
              posY: y + placement.centerYOffset,
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
              gradientOutlineWidth: baseOutW,
            );

            _writeSyllableClip(
              sb: sb,
              rawText: placement.text,
              style: 'DefaultSung',
              alignmentTag: '$fade${placement.alignmentTag}',
              posX: placement.centerX,
              posY: y + placement.centerYOffset,
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
              gradientOutlineWidth: baseOutW,
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
              alignmentTag: '$fade${placement.alignmentTag}',
              posX: placement.centerX,
              posY: y + placement.centerYOffset,
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
              alignmentTag: '$fade${placement.alignmentTag}',
              posX: placement.centerX,
              posY: y + placement.centerYOffset,
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
            double rSliceLeftX = currentRubyX + rw * accumulatedBasePercentage;
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
              alignmentTag: '$fade${placement.alignmentTag}',
              posX: placement.centerX,
              posY: y + placement.centerYOffset,
              visualY: y,
              fontSize: fs,
              outlineWidth: baseOutW,
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
              alignmentTag: '$fade${placement.alignmentTag}',
              posX: placement.centerX,
              posY: y + placement.centerYOffset,
              visualY: y,
              fontSize: fs,
              outlineWidth: baseOutW,
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
                alignmentTag: '$fade${placement.alignmentTag}',
                posX: placement.centerX,
                posY: rubyY + placement.centerYOffset,
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
                alignmentTag: '$fade${placement.alignmentTag}',
                posX: placement.centerX,
                posY: rubyY + placement.centerYOffset,
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
                alignmentTag: '$fade${placement.alignmentTag}',
                posX: placement.centerX,
                posY: rubyY + placement.centerYOffset,
                visualY: rubyY,
                fontSize: rubyFs,
                outlineWidth: rubyBaseOutW,
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
                alignmentTag: '$fade${placement.alignmentTag}',
                posX: placement.centerX,
                posY: rubyY + placement.centerYOffset,
                visualY: rubyY,
                fontSize: rubyFs,
                outlineWidth: rubyBaseOutW,
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

void _writeSyllableClip({
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
  double gradientOutlineWidth = 0,
  bool reverseClip = false,
  double clipHeightFactor = 1.5,
}) {
  double clipTop = y - fs * clipHeightFactor;
  double clipBottom = y + fs * clipHeightFactor;
  double kLeft = x - outW * 4.0;
  double kRight = x + w + outW * 4.0;
  final gradientRange = _n3GradientRange(
    centerY: y,
    fontSize: fs,
    outlineWidth: gradientOutlineWidth,
  );
  final bands = _gradientBands(
    clipTop: clipTop,
    clipBottom: clipBottom,
    gradientTop: gradientRange.$1,
    gradientBottom: gradientRange.$2,
    enabled: textColor.isGradient || outlineColor.isGradient,
    smooth:
        textColor.mode == AssColorMode.gradient ||
        outlineColor.mode == AssColorMode.gradient,
    breakpoints: {
      ...textColor.effectiveStops.map((stop) => stop.position),
      ...outlineColor.effectiveStops.map((stop) => stop.position),
    },
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
