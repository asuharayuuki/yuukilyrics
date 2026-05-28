import 'dart:io';
import 'package:flutter/material.dart';
import '../models/lyric_ast.dart';
import '../widgets/ass_export_dialog.dart';

class AssLineData {
  final LyricLine astLine;
  final List<List<LyricNode>> rows;
  final List<double> rowWidths;
  final double width;
  final Duration startTime;
  final Duration endTime;

  AssLineData({
    required this.astLine,
    required this.rows,
    required this.rowWidths,
    required this.width,
    required this.startTime,
    required this.endTime,
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
  static const int playResX = 1920;
  static const int playResY = 1080;

  static Future<void> export(
    String outputPath,
    LyricDocument doc,
    AssExportSettings settings,
  ) async {
    final sb = StringBuffer();
    _writeHeader(sb, settings);

    final blocks = _groupLinesIntoBlocks(doc, settings);

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
          sb.writeln(
            'Dialogue: 0,${_formatTime(promptStart)},${_formatTime(promptEnd)},DefaultUnsung,,0,0,0,,{\\an5\\pos(${playResX / 2},${playResY * 0.9})\\fad(500,500)\\c&HFFFFFF&}$interludeText',
          );
        }
      }

      _writeBlock(sb, block, settings, yEndTimes, lastInterludeEnd);

      if (block.lines.isNotEmpty) {
        Duration maxEnd = Duration.zero;
        for (var l in block.lines) {
          if (l.endTime > maxEnd) maxEnd = l.endTime;
        }
        lastInterludeEnd = maxEnd;
      }
    }

    final file = File(outputPath);
    await file.writeAsString(sb.toString());
  }

  static void _writeHeader(StringBuffer sb, AssExportSettings settings) {
    sb.writeln('[Script Info]');
    sb.writeln('ScriptType: v4.00+');
    sb.writeln('PlayResX: $playResX');
    sb.writeln('PlayResY: $playResY');
    sb.writeln('WrapStyle: 0');
    sb.writeln('ScaledBorderAndShadow: yes');
    sb.writeln('');

    String c = _colorToAss(settings.primaryColor);
    int fs = settings.fontSize;
    String fn = settings.fontName;

    int outW = (fs * 7 / 75).round();
    int rubyFs = (fs * 36 / 75).round();
    int rubyOut = (fs * 5 / 75).round();

    int spacing = (fs * 12 / 75).round();
    int rubySpacing = (rubyFs * 12 / 75).round();

    sb.writeln('[V4+ Styles]');
    sb.writeln(
      'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
    );
    sb.writeln(
      'Style: DefaultUnsung,$fn,$fs,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,-1,0,0,0,100,100,$spacing,0,1,$outW,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: DefaultSung,$fn,$fs,$c,&H00FFFFFF,&H00FFFFFF,&H80000000,-1,0,0,0,100,100,$spacing,0,1,$outW,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: RubyUnsung,$fn,$rubyFs,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,-1,0,0,0,100,100,$rubySpacing,0,1,$rubyOut,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: RubySung,$fn,$rubyFs,$c,&H00FFFFFF,&H00FFFFFF,&H80000000,-1,0,0,0,100,100,$rubySpacing,0,1,$rubyOut,0,5,0,0,0,1',
    );
    sb.writeln(
      'Style: Interlude,$fn,$fs,$c,&H00FFFFFF,&H00000000,&H80000000,-1,0,0,0,100,100,$spacing,0,1,$outW,0,5,0,0,0,1',
    );

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
      if (parts.length == 4) {
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        int s = int.parse(parts[2]);
        int ms = int.parse(parts[3]) * 10;
        return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
      } else if (parts.length == 3) {
        int m = int.parse(parts[0]);
        int s = int.parse(parts[1]);
        int ms = int.parse(parts[2]) * 10;
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

  static double _getCharWidth(String text, double fontSize, double spacing) {
    double w = 0;
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i);
      if ((code >= 0x3000 && code <= 0x9FFF) ||
          (code >= 0xFF00 && code <= 0xFFEF) ||
          code == 0x25CF) {
        w += fontSize + spacing;
      } else {
        w += fontSize * 0.5 + spacing;
      }
    }
    return w;
  }

  static Duration _getLineStartTime(LyricLine line) {
    for (var node in line.nodes) {
      if (node is LyricTimeTag && node.time.isNotEmpty)
        return _parseTime(node.time);
      if (node is LyricRuby) {
        for (var rNode in node.rubyNodes) {
          if (rNode is LyricTimeTag && rNode.time.isNotEmpty)
            return _parseTime(rNode.time);
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

  static Duration _findNextTimeTagAcrossRows(
    List<List<LyricNode>> rows,
    int startRow,
    int startIndex,
    Duration fallback,
  ) {
    for (int r = startRow; r < rows.length; r++) {
      var row = rows[r];
      int startI = (r == startRow) ? startIndex : 0;
      for (int i = startI; i < row.length; i++) {
        var node = row[i];
        if (node is LyricTimeTag && node.time.isNotEmpty)
          return _parseTime(node.time);
        if (node is LyricRuby) {
          for (var rNode in node.rubyNodes) {
            if (rNode is LyricTimeTag && rNode.time.isNotEmpty)
              return _parseTime(rNode.time);
          }
        }
      }
    }
    return fallback;
  }

  static double _getLineWidth(LyricLine line, double fs, double spacing) {
    double w = 0;
    for (var node in line.nodes) {
      if (node is LyricText) {
        w += _getCharWidth(node.text, fs, spacing);
      } else if (node is LyricRuby) {
        w += _getCharWidth(node.baseText, fs, spacing);
      }
    }
    return w;
  }

  static bool _isKinsoku(String char) {
    if (char.isEmpty) return false;
    return 'ぁぃぅぇぉっゃゅょゎ゛゜ゝゞァィゥェォッャュョヮヵヶ・ーヽヾ！％），．：；？］｝｡｣､･、。々〉》」』】〕'.contains(
      char,
    );
  }

  static List<AssBlock> _groupLinesIntoBlocks(
    LyricDocument doc,
    AssExportSettings settings,
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

      final double maxLineW = 1600;
      double lineSpacingVal = (fs * 12 / 75).roundToDouble();
      double width = _getLineWidth(line, fs, lineSpacingVal);

      List<List<LyricNode>> rows = [];
      List<double> rowWidths = [];

      if (width <= maxLineW) {
        rows.add(line.nodes);
        rowWidths.add(width);
      } else {
        List<_Atom> atoms = [];
        Duration currentTagTime = startTime;
        double currentAccW = 0;

        for (int i = 0; i < line.nodes.length; i++) {
          var node = line.nodes[i];
          if (node is LyricTimeTag && node.time.isNotEmpty) {
            currentTagTime = _parseTime(node.time);
            atoms.add(
              _Atom(
                node,
                null,
                0,
                currentTagTime,
                currentTagTime,
                0,
                currentAccW,
              ),
            );
          } else if (node is LyricTimeTag) {
            atoms.add(
              _Atom(
                node,
                null,
                0,
                currentTagTime,
                currentTagTime,
                0,
                currentAccW,
              ),
            );
          } else if (node is LyricRuby) {
            Duration nextTagTime = _findNextTimeTagAcrossRows(
              [line.nodes],
              0,
              i + 1,
              endTime,
            );
            double w = _getCharWidth(node.baseText, fs, lineSpacingVal);
            currentAccW += w;
            atoms.add(
              _Atom(
                node,
                null,
                w,
                currentTagTime,
                nextTagTime,
                10,
                currentAccW,
              ),
            );
          } else if (node is LyricText) {
            Duration nextTagTime = _findNextTimeTagAcrossRows(
              [line.nodes],
              0,
              i + 1,
              endTime,
            );
            String text = node.text;
            double totalTextW = _getCharWidth(text, fs, lineSpacingVal);
            int totalMs = (nextTagTime - currentTagTime).inMilliseconds;

            double accumulatedTextW = 0;

            List<String> clusters = [];
            for (int c = 0; c < text.length; c++) {
              String char = text[c];
              if (clusters.isNotEmpty && _isKinsoku(char)) {
                clusters[clusters.length - 1] += char;
              } else {
                clusters.add(char);
              }
            }

            for (int c = 0; c < clusters.length; c++) {
              String cluster = clusters[c];
              double w = _getCharWidth(cluster, fs, lineSpacingVal);
              int ms = 0;
              if (totalTextW > 0)
                ms = (totalMs * (accumulatedTextW / totalTextW)).round();
              Duration interpolatedTime =
                  currentTagTime + Duration(milliseconds: ms);

              currentAccW += w;
              accumulatedTextW += w;

              int cost = 20;
              if (c == clusters.length - 1)
                cost = 10;
              else if (cluster.endsWith(' ') || cluster.endsWith('　'))
                cost = 0;

              atoms.add(
                _Atom(
                  node,
                  cluster,
                  w,
                  interpolatedTime,
                  nextTagTime,
                  cost,
                  currentAccW,
                ),
              );
            }
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
              print(
                'Atom text: ${atom.textChar}, cost: ${atom.cost}, widthBefore: $widthBefore, score: $score, targetW: $targetW',
              );
              if (score < bestScore) {
                bestScore = score;
                bestIndex = i;
              }
            }
          }
          print('Selected bestIndex: $bestIndex, bestScore: $bestScore');

          if (bestIndex == -1) {
            for (int i = 0; i < remainingAtoms.length - 1; i++) {
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
          String currentText = '';

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
              currentText += atom.textChar!;
            } else {
              if (currentText.isNotEmpty) {
                row.add(LyricText(currentText));
                currentText = '';
              }
              row.add(atom.originalNode);
            }
          }
          if (currentText.isNotEmpty) {
            row.add(LyricText(currentText));
          }

          rows.add(row);
          double rw =
              rAtoms.last.accumulatedWidth -
              (rAtoms.first.accumulatedWidth - rAtoms.first.width);
          rowWidths.add(rw);
        }
      }

      width = rowWidths.isEmpty ? 0 : rowWidths.reduce((a, b) => a > b ? a : b);

      final lineData = AssLineData(
        astLine: line,
        rows: rows,
        rowWidths: rowWidths,
        width: width,
        startTime: startTime,
        endTime: endTime,
      );

      if (currentBlock.isNotEmpty) {
        Duration gap = startTime - currentBlock.last.endTime;
        if (gap.inMilliseconds >= settings.interludeThresholdSeconds * 1000) {
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

  static void _writeBlock(
    StringBuffer sb,
    AssBlock block,
    AssExportSettings settings,
    Map<int, Duration> yEndTimes,
    Duration lastInterludeEnd,
  ) {
    if (block.lines.isEmpty) return;

    final double centerX = playResX / 2;
    final double maxW = block.maxWidth;
    final double visualGap = settings.fontSize * settings.visualGapMultiplier;
    final double boxLeft = centerX - maxW / 2 - visualGap / 2;
    final double boxRight = centerX + maxW / 2 + visualGap / 2;

    final fs = settings.fontSize.toDouble();
    final lineSpacing = fs + (fs * 0.8) + (fs * 30 / 75);

    int totalRows = 0;
    for (var l in block.lines) {
      totalRows += l.rows.length;
    }

    final double yLast = playResY - 50.0 - fs * 0.8;
    double startY = yLast - ((totalRows - 1) * lineSpacing);
    if (settings.pagingMode == AssPagingMode.auto2Lines && totalRows == 1) {
      startY = yLast - lineSpacing;
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
      if (firstSingStart - preludeStart >= const Duration(milliseconds: 1500)) {
        hasCountdown = true;
        double iconX = boxLeft;
        if (settings.pagingMode != AssPagingMode.auto2Lines && totalRows == 1) {
          iconX = centerX - block.lines.first.rowWidths.first / 2;
        }
        double rubyFs = fs * 36 / 75;
        double iconFs = fs * 0.6;
        double rubyY = startY - fs * 0.9;
        double iconY = rubyY - rubyFs / 2 - iconFs / 2 - 20.0;

        double spacing = (fs * 12 / 75).roundToDouble();
        iconX += (fs - iconFs) / 2;
        double outW = (fs * 7 / 75).roundToDouble();
        double dotW = _getCharWidth('●', iconFs, spacing);
        double totalW = dotW * 3;

        int fillTime = (firstSingStart - preludeStart).inMilliseconds;
        int tStart = 0;
        int tEnd = fillTime;

        double clipTop = iconY - iconFs;
        double clipBottom = iconY + iconFs;
        double cLeft = iconX - outW * 4.0;

        String clipStart =
            '\\clip(${cLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${iconX.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
        String clipEnd =
            '\\clip(${cLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${(iconX + totalW).toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';

        // 1. Unsung Layer (White text, Black outline)
        sb.writeln(
          'Dialogue: 0,${_formatTime(preludeStart)},${_formatTime(firstSingStart)},DefaultUnsung,,0,0,0,,{\\fs${iconFs.toInt()}\\an4\\pos(${iconX.toStringAsFixed(1)},${iconY.toStringAsFixed(1)})}●●●',
        );

        // 2. Sung Layer (Theme text, White outline)
        sb.writeln(
          'Dialogue: 0,${_formatTime(preludeStart)},${_formatTime(firstSingStart)},DefaultSung,,0,0,0,,{\\fs${iconFs.toInt()}\\an4\\pos(${iconX.toStringAsFixed(1)},${iconY.toStringAsFixed(1)})$clipStart\\t($tStart,$tEnd,$clipEnd)}●●●',
        );
      }
    }

    int currentVisualRow = 0;
    for (int i = 0; i < block.lines.length; i++) {
      final lineData = block.lines[i];
      int slot = settings.pagingMode == AssPagingMode.auto2Lines ? i % 2 : i;

      Duration displayStart =
          lineData.startTime - const Duration(milliseconds: 3000);
      if (i == 0 && preludeStart < displayStart && hasCountdown) {
        displayStart = preludeStart;
      }
      Duration displayEnd =
          lineData.endTime + const Duration(milliseconds: 200);

      List<double> startXs = [];
      List<double> ys = [];

      for (int r = 0; r < lineData.rows.length; r++) {
        final rowWidth = lineData.rowWidths[r];
        final y = startY + currentVisualRow * lineSpacing;

        double x = centerX;
        if (settings.pagingMode == AssPagingMode.auto2Lines) {
          if (slot == 0) x = boxLeft;
          if (slot == 1) x = boxRight - rowWidth;
        } else {
          if (block.lines.length == 2) {
            if (slot == 0) x = boxLeft;
            if (slot == 1) x = boxRight - rowWidth;
          } else if (block.lines.length == 3) {
            if (slot == 0) x = boxLeft;
            if (slot == 1) x = boxRight - rowWidth;
            if (slot == 2) x = centerX - rowWidth / 2;
          } else if (block.lines.length >= 4) {
            if (slot == 0) x = boxLeft;
            if (slot == 1) x = boxRight - rowWidth;
            if (slot == 2) x = boxLeft;
            if (slot == 3) x = boxRight - rowWidth;
          } else {
            x = centerX - rowWidth / 2;
          }
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
        currentVisualRow++;
      }

      _writeLine(sb, lineData, startXs, ys, displayStart, displayEnd, fs);
    }
  }

  static void _writeLine(
    StringBuffer sb,
    AssLineData lineData,
    List<double> startXs,
    List<double> ys,
    Duration displayStart,
    Duration displayEnd,
    double fs,
  ) {
    double rubyFs = fs * 36 / 75;

    double spacing = (fs * 12 / 75).roundToDouble();
    double rubySpacing = (rubyFs * 12 / 75).roundToDouble();
    double outW = (fs * 7 / 75).roundToDouble();
    double rubyOut = (fs * 5 / 75).roundToDouble();

    Duration currentTagTime = lineData.startTime;

    for (int r = 0; r < lineData.rows.length; r++) {
      final rowNodes = lineData.rows[r];
      double currentX = startXs[r];
      final y = ys[r];

      for (int i = 0; i < rowNodes.length; i++) {
        var node = rowNodes[i];
        if (node is LyricTimeTag && node.time.isNotEmpty) {
          currentTagTime = _parseTime(node.time);
        } else if (node is LyricText || node is LyricRuby) {
          Duration nextTagTime = _findNextTimeTagAcrossRows(
            lineData.rows,
            r,
            i + 1,
            lineData.endTime,
          );

          double w = 0;
          if (node is LyricText) {
            w = _getCharWidth(node.text, fs, spacing);
          } else if (node is LyricRuby) {
            w = _getCharWidth(node.baseText, fs, spacing);
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
            double cx = currentX + w / 2;
            double adjustedCx = cx + spacing / 2;
            sb.writeln(
              'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},DefaultUnsung,,0,0,0,,{\\an5\\pos(${adjustedCx.toStringAsFixed(1)},${y.toStringAsFixed(1)})}${node.text}',
            );

            int tStart = (currentTagTime - displayStart).inMilliseconds;
            int tEnd = (nextTagTime - displayStart).inMilliseconds;
            _writeSyllableClip(
              sb: sb,
              rawText: node.text,
              style: 'DefaultSung',
              alignmentTag: '\\an5',
              posX: adjustedCx,
              posY: y,
              x: currentX,
              y: y,
              w: w,
              outW: outW,
              tStart: tStart,
              tEnd: tEnd,
              isLastNode: isLastNode,
              displayStart: displayStart,
              displayEnd: displayEnd,
              fs: fs,
            );
          } else if (node is LyricRuby) {
            double cx = currentX + w / 2;
            double adjustedCx = cx + spacing / 2;
            sb.writeln(
              'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},DefaultUnsung,,0,0,0,,{\\an5\\pos(${adjustedCx.toStringAsFixed(1)},${y.toStringAsFixed(1)})}${node.baseText}',
            );

            double rubyY = y - fs * 0.9;

            double rw = 0;
            String rawRubyText = '';
            for (var rNode in node.rubyNodes) {
              if (rNode is LyricText && rNode.text != '＋') {
                rw += _getCharWidth(rNode.text, rubyFs, rubySpacing);
                rawRubyText += rNode.text;
              }
            }

            String scaleTag = '';
            if (rw > w && rw > 0) {
              double scale = (w / rw) * 100;
              scaleTag = '\\fscx${scale.toStringAsFixed(1)}';
            }

            double adjustedRubyCx = cx + rubySpacing / 2;
            String rubyUnsungTags =
                '{\\an5\\pos(${adjustedRubyCx.toStringAsFixed(1)},${rubyY.toStringAsFixed(1)})';
            if (scaleTag.isNotEmpty) rubyUnsungTags += scaleTag;
            rubyUnsungTags += '}';
            sb.writeln(
              'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},RubyUnsung,,0,0,0,,$rubyUnsungTags$rawRubyText',
            );

            Duration rubyCurrentTime = currentTagTime;
            double currentRubyX = cx - rw / 2;
            if (rw > w && rw > 0) {
              currentRubyX = cx - w / 2;
            }

            double accumulatedRw = 0;

            for (int rIdx = 0; rIdx < node.rubyNodes.length; rIdx++) {
              var rNode = node.rubyNodes[rIdx];
              if (rNode is LyricTimeTag && rNode.time.isNotEmpty) {
                rubyCurrentTime = _parseTime(rNode.time);
              } else if (rNode is LyricText && rNode.text != '＋') {
                Duration rNextTime = rubyCurrentTime;
                bool found = false;
                for (int k = rIdx + 1; k < node.rubyNodes.length; k++) {
                  final kNode = node.rubyNodes[k];
                  if (kNode is LyricTimeTag && kNode.time.isNotEmpty) {
                    rNextTime = _parseTime(kNode.time);
                    found = true;
                    break;
                  }
                }
                if (!found) rNextTime = nextTagTime;

                double unscaledRSyllableW = _getCharWidth(
                  rNode.text,
                  rubyFs,
                  rubySpacing,
                );
                double rSyllableW = unscaledRSyllableW;
                if (rw > w && rw > 0) {
                  rSyllableW = rSyllableW * (w / rw);
                }

                int rStart = (rubyCurrentTime - displayStart).inMilliseconds;
                int rEnd = (rNextTime - displayStart).inMilliseconds;

                bool isLastRuby = true;
                for (int k = rIdx + 1; k < node.rubyNodes.length; k++) {
                  final kNode = node.rubyNodes[k];
                  if (kNode is LyricText && kNode.text != '＋') {
                    isLastRuby = false;
                    break;
                  }
                }

                _writeSyllableClip(
                  sb: sb,
                  rawText: rawRubyText,
                  style: 'RubySung',
                  alignmentTag: '\\an5',
                  posX: adjustedRubyCx,
                  posY: rubyY,
                  x: currentRubyX,
                  y: rubyY,
                  w: rSyllableW,
                  outW: rubyOut,
                  tStart: rStart,
                  tEnd: rEnd,
                  isLastNode: isLastRuby,
                  displayStart: displayStart,
                  displayEnd: displayEnd,
                  fs: fs,
                  extraTags: scaleTag,
                );

                double percentage = (rw > 0) ? (unscaledRSyllableW / rw) : 1.0;
                double sliceW = w * percentage;
                double sliceX =
                    currentX + ((rw > 0) ? w * (accumulatedRw / rw) : 0);

                _writeSyllableClip(
                  sb: sb,
                  rawText: node.baseText,
                  style: 'DefaultSung',
                  alignmentTag: '\\an5',
                  posX: adjustedCx,
                  posY: y,
                  x: sliceX,
                  y: y,
                  w: sliceW,
                  outW: outW,
                  tStart: rStart,
                  tEnd: rEnd,
                  isLastNode: isLastNode && isLastRuby,
                  displayStart: displayStart,
                  displayEnd: displayEnd,
                  fs: fs,
                );

                currentRubyX += rSyllableW;
                accumulatedRw += unscaledRSyllableW;
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
    required bool isLastNode,
    required Duration displayStart,
    required Duration displayEnd,
    required double fs,
    String extraTags = '',
  }) {
    double clipTop = y - fs * 1.5;
    double clipBottom = y + fs * 1.5;
    double kLeft = x - outW * 4.0;

    String clipInit =
        '\\clip(${x.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${x.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
    String clipStart =
        '\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${x.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
    String clipEnd =
        '\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${(x + w).toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';

    String tags =
        '{$alignmentTag\\pos(${posX.toStringAsFixed(1)},${posY.toStringAsFixed(1)})$extraTags$clipInit'
        '\\t($tStart,${tStart + 1},$clipStart)'
        '\\t(${tStart + 1},$tEnd,$clipEnd)';

    if (isLastNode) {
      String clipFinal =
          '\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${(x + w + outW * 4.0).toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
      tags += '\\t($tEnd,${tEnd + 1},$clipFinal)';
    }
    tags += '}';

    sb.writeln(
      'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},$style,,0,0,0,,$tags$rawText',
    );
  }
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
