
import 'package:flutter/material.dart';
import 'package:characters/characters.dart';
import '../models/lyric_ast.dart';
import '../screens/ass_export_screen.dart';

class AssLineData {
  final LyricLine astLine;
  final List<List<LyricNode>> rows;
  final List<double> rowWidths;
  final double width;
  final Duration startTime;
  final Duration endTime;
  final Map<LyricNode, Duration> nodeStartTimes;
  final Map<LyricNode, Duration> nodeEndTimes;

  AssLineData({
    required this.astLine,
    required this.rows,
    required this.rowWidths,
    required this.width,
    required this.startTime,
    required this.endTime,
    required this.nodeStartTimes,
    required this.nodeEndTimes,
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

  static Future<String> generateAss(
    LyricDocument doc,
    AssExportSettings settings,
  ) async {
    final sb = StringBuffer();
    _writeHeader(sb, settings);

    // Pre-calculate line singer mapping
    Map<LyricLine, int> lineSingerMap = {};
    int? currentSingerIdx;
    
    // Sort singer colors by prefix length descending
    List<SingerColorInfo> sortedSingers = List.from(settings.singerColors);
    sortedSingers.sort((a, b) => b.prefix.length.compareTo(a.prefix.length));
    
    for (var line in doc.lines) {
      String plainText = _getPlainText(line);
      for (int i = 0; i < sortedSingers.length; i++) {
        if (plainText.startsWith(sortedSingers[i].prefix)) {
          currentSingerIdx = settings.singerColors.indexOf(sortedSingers[i]);
          break;
        }
      }
      if (currentSingerIdx != null) {
        lineSingerMap[line] = currentSingerIdx;
      }
    }

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

      _writeBlock(sb, block, settings, yEndTimes, lastInterludeEnd, lineSingerMap);

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

  static String _getPlainText(LyricLine line) {
    final sb = StringBuffer();
    for (var node in line.nodes) {
      if (node is LyricText) {
        sb.write(node.text);
      } else if (node is LyricRuby) {
        sb.write(node.baseText);
      }
    }
    return sb.toString();
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

    int outW = settings.outlineWidth;
    int rubyFs = (fs * 36 / 75).round();
    int rubyOut = (settings.outlineWidth * 5 / 7).round();

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
      int _parseMs(String s) {
        if (s.length == 3) return int.parse(s);
        if (s.length == 2) return int.parse(s) * 10;
        if (s.length == 1) return int.parse(s) * 100;
        return int.parse(s.substring(0, 3));
      }
      if (parts.length == 4) {
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        int s = int.parse(parts[2]);
        int ms = _parseMs(parts[3]);
        return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
      } else if (parts.length == 3) {
        int m = int.parse(parts[0]);
        int s = int.parse(parts[1]);
        int ms = _parseMs(parts[2]);
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
    for (final char in text.characters) {
      if (char.isEmpty) continue;
      bool isWide = false;
      if (char.length > 1) {
        isWide = true;
      } else {
        int code = char.codeUnitAt(0);
        if ((code >= 0x3000 && code <= 0x9FFF) ||
            (code >= 0xFF00 && code <= 0xFFEF) ||
            code == 0x25CF) {
          isWide = true;
        }
      }
      if (isWide) {
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



  static double _getRubyNodeWidth(LyricRuby node, double fs, double spacing) {
    double baseW = _getCharWidth(node.baseText, fs, spacing);
    
    double rubyFs = fs * 36 / 75;
    double rubySpacing = (rubyFs * 12 / 75).roundToDouble();
    double rubyW = 0;
    
    for (var rNode in node.rubyNodes) {
      if (rNode is LyricText) {
        rubyW += _getCharWidth(rNode.text.replaceAll('＋', ''), rubyFs, rubySpacing);
      }
    }
    
    return baseW > rubyW ? baseW : rubyW;
  }

  static double _getLineWidth(LyricLine line, double fs, double spacing) {
    double w = 0;
    for (var node in line.nodes) {
      if (node is LyricText) {
        w += _getCharWidth(node.text, fs, spacing);
      } else if (node is LyricRuby) {
        w += _getRubyNodeWidth(node, fs, spacing);
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

      final double maxLineW = 1800;
      double lineSpacingVal = (fs * 12 / 75).roundToDouble();
      double width = _getLineWidth(line, fs, lineSpacingVal);

      Map<LyricNode, Duration> nodeStartTimes = {};
      Map<LyricNode, Duration> nodeEndTimes = {};
      
      List<dynamic> timeElements = [];
      for (int i = 0; i < line.nodes.length; i++) {
        var node = line.nodes[i];
        if (node is LyricTimeTag && node.time.isNotEmpty) {
          timeElements.add(_parseTime(node.time));
        } else if (node is LyricRuby) {
          if (node.rubyNodes.isNotEmpty && node.rubyNodes.first is LyricTimeTag) {
            LyricTimeTag firstTag = node.rubyNodes.first as LyricTimeTag;
            if (firstTag.time.isNotEmpty) {
              timeElements.add(_parseTime(firstTag.time));
            }
          }
          double w = _getRubyNodeWidth(node, fs, lineSpacingVal);
          timeElements.add(_Atom(node, null, w, Duration.zero, Duration.zero, 10, 0));
        } else if (node is LyricText) {
          double w = _getCharWidth(node.text, fs, lineSpacingVal);
          timeElements.add(_Atom(node, null, w, Duration.zero, Duration.zero, 10, 0));
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
            for (var a in currentChunk) totalW += a.width;
            
            for (var a in currentChunk) {
              int ms = 0;
              if (totalW > 0) ms = (totalMs * (a.width / totalW)).round();
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
        for (var a in currentChunk) totalW += a.width;
        for (var a in currentChunk) {
          int ms = 0;
          if (totalW > 0) ms = (totalMs * (a.width / totalW)).round();
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
            if (node.rubyNodes.isNotEmpty && node.rubyNodes.first is LyricTimeTag) {
              LyricTimeTag firstTag = node.rubyNodes.first as LyricTimeTag;
              if (firstTag.time.isNotEmpty) {
                elements.add(_parseTime(firstTag.time));
              }
            }
            double w = _getRubyNodeWidth(node, fs, lineSpacingVal);
            elements.add(_Atom(node, null, w, Duration.zero, Duration.zero, 10, 0));
          } else if (node is LyricText) {
            String text = node.text;
            List<String> clusters = [];
            for (final char in text.characters) {
              if (clusters.isNotEmpty && _isKinsoku(char)) {
                clusters[clusters.length - 1] += char;
              } else {
                clusters.add(char);
              }
            }
            for (int c = 0; c < clusters.length; c++) {
              String cluster = clusters[c];
              double w = _getCharWidth(cluster, fs, lineSpacingVal);
              int cost = 20;
              if (c == clusters.length - 1)
                cost = 10;
              else if (cluster.endsWith(' ') || cluster.endsWith('　'))
                cost = 0;
              
              elements.add(_Atom(node, cluster, w, Duration.zero, Duration.zero, cost, 0));
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
              for (var a in currentChunkAtoms) chunkTotalW += a.width;
              
              for (var a in currentChunkAtoms) {
                int ms = 0;
                if (chunkTotalW > 0) {
                  ms = (totalMs * (a.width / chunkTotalW)).round();
                }
                Duration start = currentTagTime;
                currentTagTime += Duration(milliseconds: ms);
                
                currentAccW += a.width;
                atoms.add(_Atom(
                  a.originalNode,
                  a.textChar,
                  a.width,
                  start,
                  currentTagTime,
                  a.cost,
                  currentAccW,
                ));
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
            for (var a in currentChunkAtoms) chunkTotalW += a.width;
            
            for (var a in currentChunkAtoms) {
              int ms = 0;
              if (chunkTotalW > 0) {
                ms = (totalMs * (a.width / chunkTotalW)).round();
              }
              Duration start = currentTagTime;
              currentTagTime += Duration(milliseconds: ms);
              
              currentAccW += a.width;
              atoms.add(_Atom(
                a.originalNode,
                a.textChar,
                a.width,
                start,
                currentTagTime,
                a.cost,
                currentAccW,
              ));
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

      width = rowWidths.isEmpty ? 0 : rowWidths.reduce((a, b) => a > b ? a : b);

      final lineData = AssLineData(
        astLine: line,
        rows: rows,
        rowWidths: rowWidths,
        width: width,
        startTime: startTime,
        endTime: endTime,
        nodeStartTimes: nodeStartTimes,
        nodeEndTimes: nodeEndTimes,
      );

      if (currentBlock.isNotEmpty) {
        Duration gap = startTime - currentBlock.last.endTime;
        int threshold = settings.pagingMode == AssPagingMode.auto2Lines
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

  static void _writeBlock(
    StringBuffer sb,
    AssBlock block,
    AssExportSettings settings,
    Map<int, Duration> yEndTimes,
    Duration lastInterludeEnd,
    Map<LyricLine, int> lineSingerMap,
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
      Duration expectedDisplayStart = block.lines.first.startTime - const Duration(milliseconds: 3000);
      int roundedYLast = yLast.round();
      if (yEndTimes.containsKey(roundedYLast)) {
        if (expectedDisplayStart < yEndTimes[roundedYLast]!) {
          startY = yLast - lineSpacing;
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
      if (firstSingStart - preludeStart >= const Duration(milliseconds: 1500)) {
        hasCountdown = true;
        double iconX = boxLeft;
        if ((settings.pagingMode != AssPagingMode.auto2Lines && totalRows == 1) ||
            (settings.pagingMode == AssPagingMode.auto2Lines && block.lines.length == 1)) {
          iconX = centerX - block.lines.first.rowWidths.first / 2;
        }
        double rubyFs = fs * 36 / 75;
        double iconFs = fs * 0.6;
        double rubyY = startY - fs * 0.9;
        double iconY = rubyY - rubyFs / 2 - iconFs / 2 - 20.0;

        double spacing = (fs * 12 / 75).roundToDouble();
        iconX += (fs - iconFs) / 2;
        double outW = settings.outlineWidth.toDouble();
        double dotW = _getCharWidth('●', iconFs, spacing);
        double totalW = dotW * 3;

        int fillTime = (firstSingStart - preludeStart).inMilliseconds;
        int tStart = 0;
        int tEnd = fillTime;

        double clipTop = iconY - iconFs;
        double clipBottom = iconY + iconFs;
        double cLeft = iconX - outW * 4.0;

        double cRight = iconX + totalW + outW * 4.0;
        
        String clipInit =
            '\\clip(${iconX.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${iconX.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
        String clipStart =
            '\\clip(${cLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${iconX.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
        String clipEnd =
            '\\clip(${cLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${(iconX + totalW).toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
        String clipFinal =
            '\\clip(${cLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${cRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';

        String rClipInit =
            '\\clip(${cLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${cRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
        String rClipStart =
            '\\clip(${iconX.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${cRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
        String rClipEnd =
            '\\clip(${(iconX + totalW).toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${cRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
        String rClipFinal = '\\clip(0,0,0,0)';

        // 1. Unsung Layer (White text, Black outline)
        sb.writeln(
          'Dialogue: 0,${_formatTime(preludeStart)},${_formatTime(firstSingStart)},DefaultUnsung,,0,0,0,,{\\fs${iconFs.toInt()}\\an4\\pos(${iconX.toStringAsFixed(1)},${iconY.toStringAsFixed(1)})$rClipInit\\t($tStart,${tStart + 1},$rClipStart)\\t(${tStart + 1},$tEnd,$rClipEnd)\\t($tEnd,${tEnd + 1},$rClipFinal)}●●●',
        );

        // 2. Sung Layer (Theme text, White outline)
        sb.writeln(
          'Dialogue: 0,${_formatTime(preludeStart)},${_formatTime(firstSingStart)},DefaultSung,,0,0,0,,{\\fs${iconFs.toInt()}\\an4\\pos(${iconX.toStringAsFixed(1)},${iconY.toStringAsFixed(1)})$clipInit\\t($tStart,${tStart + 1},$clipStart)\\t(${tStart + 1},$tEnd,$clipEnd)\\t($tEnd,${tEnd + 1},$clipFinal)}●●●',
        );
      }
    }

    int currentVisualRow = 0;
    for (int i = 0; i < block.lines.length; i++) {
      final lineData = block.lines[i];
      int slot = settings.pagingMode == AssPagingMode.auto2Lines ? i % 2 : i;

      List<double> startXs = [];
      List<double> ys = [];
      List<Duration> displayStarts = [];
      List<Duration> displayEnds = [];

      for (int r = 0; r < lineData.rows.length; r++) {
        final rowWidth = lineData.rowWidths[r];
        final y = startY + currentVisualRow * lineSpacing;

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
        if (settings.pagingMode == AssPagingMode.auto2Lines) {
          if (block.lines.length == 1) {
            x = centerX - rowWidth / 2;
          } else {
            if (slot == 0) x = boxLeft;
            if (slot == 1) x = boxRight - rowWidth;
          }
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

        // Clamp x to keep text within screen bounds
        const double screenMargin = 30.0;
        if (x < screenMargin) x = screenMargin;
        if (x + rowWidth > playResX - screenMargin) {
          x = playResX - screenMargin - rowWidth;
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
      }

      int? sIdx = lineSingerMap[lineData.astLine];
      _writeLine(sb, lineData, startXs, ys, displayStarts, displayEnds, fs, settings, sIdx);
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
  ) {
    double rubyFs = fs * 36 / 75;

    double spacing = (fs * 12 / 75).roundToDouble();
    double rubySpacing = (rubyFs * 12 / 75).roundToDouble();
    double outW = settings.outlineWidth.toDouble();
    double rubyOut = (settings.outlineWidth * 5 / 7).roundToDouble();

    Duration currentTagTime = lineData.startTime;

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
          String unsungOutlineColor = sIdx != null ? _colorToAss(settings.singerColors[sIdx].edgeColor) : _colorToAss(settings.edgeColor);
          String sungOutlineColor = sIdx != null ? _colorToAss(settings.singerColors[sIdx].edgeColor) : '&H96E1FF&';
          Duration activeTime = lineData.nodeStartTimes[node] ?? currentTagTime;
          Duration nextTagTime = lineData.nodeEndTimes[node] ?? currentTagTime;
          currentTagTime = nextTagTime;

          double w = 0;
          if (node is LyricText) {
            w = _getCharWidth(node.text, fs, spacing);
          } else if (node is LyricRuby) {
            w = _getRubyNodeWidth(node, fs, spacing);
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
            int tStart = (activeTime - displayStart).inMilliseconds;
            int tEnd = (nextTagTime - displayStart).inMilliseconds;

            String glowUnsungTags = '\\1a&HFF&\\3a&H00&\\3c$unsungOutlineColor\\bord${(outW + 4).toStringAsFixed(1)}\\blur10\\t($tStart,$tEnd,\\3a&HFF&)';
            String glowSungTags = '\\1a&HFF&\\3a&HFF&\\3c$sungOutlineColor\\bord${(outW + 4).toStringAsFixed(1)}\\blur10\\t($tStart,$tEnd,\\3a&H00&)';
            sb.writeln(
              'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},DefaultUnsung,,0,0,0,,{\\an5\\pos(${adjustedCx.toStringAsFixed(1)},${y.toStringAsFixed(1)})$glowUnsungTags}${node.text}',
            );
            sb.writeln(
              'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},DefaultUnsung,,0,0,0,,{\\an5\\pos(${adjustedCx.toStringAsFixed(1)},${y.toStringAsFixed(1)})$glowSungTags}${node.text}',
            );

            _writeSyllableClip(
              sb: sb,
              rawText: node.text,
              style: 'DefaultUnsung',
              alignmentTag: '\\an5',
              posX: adjustedCx,
              posY: y,
              x: currentX,
              y: y,
              w: w,
              outW: outW,
              tStart: tStart,
              tEnd: tEnd,
              displayStart: displayStart,
              displayEnd: displayEnd,
              fs: fs,
              layer: 1,
              reverseClip: true,
            );

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
              displayStart: displayStart,
              displayEnd: displayEnd,
              fs: fs,
              layer: 1,
            );
          } else if (node is LyricRuby) {
            double cx = currentX + w / 2;
            double adjustedCx = cx + spacing / 2;
            int tStart = (activeTime - displayStart).inMilliseconds;
            int tEnd = (nextTagTime - displayStart).inMilliseconds;

            String baseGlowUnsungTags = '\\1a&HFF&\\3a&H00&\\3c$unsungOutlineColor\\bord${(outW + 4).toStringAsFixed(1)}\\blur10\\t($tStart,$tEnd,\\3a&HFF&)';
            String baseGlowSungTags = '\\1a&HFF&\\3a&HFF&\\3c$sungOutlineColor\\bord${(outW + 4).toStringAsFixed(1)}\\blur10\\t($tStart,$tEnd,\\3a&H00&)';
            sb.writeln(
              'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},DefaultUnsung,,0,0,0,,{\\an5\\pos(${adjustedCx.toStringAsFixed(1)},${y.toStringAsFixed(1)})$baseGlowUnsungTags}${node.baseText}',
            );
            sb.writeln(
              'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},DefaultUnsung,,0,0,0,,{\\an5\\pos(${adjustedCx.toStringAsFixed(1)},${y.toStringAsFixed(1)})$baseGlowSungTags}${node.baseText}',
            );

            double rubyY = y - fs * 0.9;
            double rw = 0;
            for (var rNode in node.rubyNodes) {
              if (rNode is LyricText) {
                String visibleText = rNode.text.replaceAll('＋', '');
                rw += _getCharWidth(visibleText, rubyFs, rubySpacing);
              }
            }


            double clipTop = y - fs * 1.5;
            double clipBottom = y + fs * 1.5;
            double kLeft = currentX - outW * 4.0;
            double kRight = currentX + w + outW * 4.0;

            String baseSungSweep = '\\clip(${currentX.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${currentX.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
            String baseUnsungSweep = '\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';

            double rClipTop = rubyY - rubyFs * 1.5;
            double rClipBottom = rubyY + rubyFs * 1.5;


            bool isFirstSegment = true;
            
            List<String> baseChars = node.baseText.characters.toList();
            List<double> baseWidths = baseChars.map((c) => _getCharWidth(c, fs, spacing)).toList();
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

            String visibleText = '';
            double totalLogicalW = 0;
            for (var chunk in chunks) {
              String text = chunk['text'] as String;
              double chunkLogicalW = 0;
              for (int c = 0; c < text.length; c++) {
                if (text[c] == '＋') {
                  chunkLogicalW += _getCharWidth('あ', rubyFs, rubySpacing);
                } else {
                  visibleText += text[c];
                  chunkLogicalW += _getCharWidth(text[c], rubyFs, rubySpacing);
                }
              }
              chunk['logicalW'] = chunkLogicalW;
              totalLogicalW += chunkLogicalW;
            }

            double currentRubyX = cx - rw / 2;
            double adjustedRubyCx = cx + rubySpacing / 2;

            double rkLeft = currentRubyX - rubyOut * 4.0;
            double rkRight = currentRubyX + rw + rubyOut * 4.0;

            String rubySungSweep = '\\clip(${currentRubyX.toStringAsFixed(1)},${rClipTop.toStringAsFixed(1)},${currentRubyX.toStringAsFixed(1)},${rClipBottom.toStringAsFixed(1)})';
            String rubyUnsungSweep = '\\clip(${rkLeft.toStringAsFixed(1)},${rClipTop.toStringAsFixed(1)},${rkRight.toStringAsFixed(1)},${rClipBottom.toStringAsFixed(1)})';

            int numSegments = chunks.length;
            int segmentIdx = 0;
            double accumulatedBasePercentage = 0;

            for (var chunk in chunks) {
                int rStart = (chunk['start'] as Duration).inMilliseconds - displayStart.inMilliseconds;
                int rEnd = (chunk['end'] as Duration).inMilliseconds - displayStart.inMilliseconds;

                double percentage;
                if (numSegments == baseChars.length && totalBaseW > 0) {
                  percentage = baseWidths[segmentIdx] / totalBaseW;
                } else {
                  percentage = (totalLogicalW > 0) ? ((chunk['logicalW'] as double) / totalLogicalW) : 1.0;
                }

                double sliceW = w * percentage;
                double sliceLeftX = currentX + w * accumulatedBasePercentage;
                double sliceRightX = sliceLeftX + sliceW;

                double rSliceW = rw * percentage;
                double rSliceLeftX = currentRubyX + rw * accumulatedBasePercentage;
                double rSliceRightX = rSliceLeftX + rSliceW;

                if (isFirstSegment) {
                  baseSungSweep += '\\t($rStart,${rStart + 1},\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${sliceLeftX.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)}))';
                  baseUnsungSweep += '\\t($rStart,${rStart + 1},\\clip(${sliceLeftX.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)}))';
                  
                  rubySungSweep += '\\t($rStart,${rStart + 1},\\clip(${rkLeft.toStringAsFixed(1)},${rClipTop.toStringAsFixed(1)},${rSliceLeftX.toStringAsFixed(1)},${rClipBottom.toStringAsFixed(1)}))';
                  rubyUnsungSweep += '\\t($rStart,${rStart + 1},\\clip(${rSliceLeftX.toStringAsFixed(1)},${rClipTop.toStringAsFixed(1)},${rkRight.toStringAsFixed(1)},${rClipBottom.toStringAsFixed(1)}))';
                  
                  isFirstSegment = false;
                }
                
                baseSungSweep += '\\t(${rStart + 1},$rEnd,\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${sliceRightX.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)}))';
                baseUnsungSweep += '\\t(${rStart + 1},$rEnd,\\clip(${sliceRightX.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)}))';

                rubySungSweep += '\\t(${rStart + 1},$rEnd,\\clip(${rkLeft.toStringAsFixed(1)},${rClipTop.toStringAsFixed(1)},${rSliceRightX.toStringAsFixed(1)},${rClipBottom.toStringAsFixed(1)}))';
                rubyUnsungSweep += '\\t(${rStart + 1},$rEnd,\\clip(${rSliceRightX.toStringAsFixed(1)},${rClipTop.toStringAsFixed(1)},${rkRight.toStringAsFixed(1)},${rClipBottom.toStringAsFixed(1)}))';

                segmentIdx++;
                accumulatedBasePercentage += percentage;
            }

            baseSungSweep += '\\t($tEnd,${tEnd + 1},\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)}))';
            baseUnsungSweep += '\\t($tEnd,${tEnd + 1},\\clip(0,0,0,0))';

            rubySungSweep += '\\t($tEnd,${tEnd + 1},\\clip(${rkLeft.toStringAsFixed(1)},${rClipTop.toStringAsFixed(1)},${rkRight.toStringAsFixed(1)},${rClipBottom.toStringAsFixed(1)}))';
            rubyUnsungSweep += '\\t($tEnd,${tEnd + 1},\\clip(0,0,0,0))';

            sb.writeln('Dialogue: 1,${_formatTime(displayStart)},${_formatTime(displayEnd)},DefaultUnsung,,0,0,0,,{\\an5\\pos(${adjustedCx.toStringAsFixed(1)},${y.toStringAsFixed(1)})$baseUnsungSweep}${node.baseText}');
            sb.writeln('Dialogue: 1,${_formatTime(displayStart)},${_formatTime(displayEnd)},DefaultSung,,0,0,0,,{\\an5\\pos(${adjustedCx.toStringAsFixed(1)},${y.toStringAsFixed(1)})$baseSungSweep}${node.baseText}');

            if (visibleText.isNotEmpty) {
              String rubyGlowUnsungTags = '\\1a&HFF&\\3a&H00&\\3c$unsungOutlineColor\\bord${(rubyOut + 2).toStringAsFixed(1)}\\blur10\\t($tStart,$tEnd,\\3a&HFF&)';
              String rubyGlowSungTags = '\\1a&HFF&\\3a&HFF&\\3c$sungOutlineColor\\bord${(rubyOut + 2).toStringAsFixed(1)}\\blur10\\t($tStart,$tEnd,\\3a&H00&)';

              sb.writeln('Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},RubyUnsung,,0,0,0,,{\\an5\\pos(${adjustedRubyCx.toStringAsFixed(1)},${rubyY.toStringAsFixed(1)})$rubyGlowUnsungTags}$visibleText');
              sb.writeln('Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},RubyUnsung,,0,0,0,,{\\an5\\pos(${adjustedRubyCx.toStringAsFixed(1)},${rubyY.toStringAsFixed(1)})$rubyGlowSungTags}$visibleText');

              sb.writeln('Dialogue: 1,${_formatTime(displayStart)},${_formatTime(displayEnd)},RubyUnsung,,0,0,0,,{\\an5\\pos(${adjustedRubyCx.toStringAsFixed(1)},${rubyY.toStringAsFixed(1)})$rubyUnsungSweep}$visibleText');
              sb.writeln('Dialogue: 1,${_formatTime(displayStart)},${_formatTime(displayEnd)},RubySung,,0,0,0,,{\\an5\\pos(${adjustedRubyCx.toStringAsFixed(1)},${rubyY.toStringAsFixed(1)})$rubySungSweep}$visibleText');
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
    bool reverseClip = false,
  }) {
    double clipTop = y - fs * 1.5;
    double clipBottom = y + fs * 1.5;
    double kLeft = x - outW * 4.0;
    double kRight = x + w + outW * 4.0;

    String tags =
        '{$alignmentTag\\pos(${posX.toStringAsFixed(1)},${posY.toStringAsFixed(1)})';

    if (reverseClip) {
      String clipInit =
          '\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
      String clipStart =
          '\\clip(${x.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
      String clipEnd =
          '\\clip(${(x + w).toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
      String clipFinal = '\\clip(0,0,0,0)';

      tags += '$clipInit'
          '\\t($tStart,${tStart + 1},$clipStart)'
          '\\t(${tStart + 1},$tEnd,$clipEnd)'
          '\\t($tEnd,${tEnd + 1},$clipFinal)}';
    } else {
      String clipInit =
          '\\clip(${x.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${x.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
      String clipStart =
          '\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${x.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
      String clipEnd =
          '\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${(x + w).toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';
      String clipFinal =
          '\\clip(${kLeft.toStringAsFixed(1)},${clipTop.toStringAsFixed(1)},${kRight.toStringAsFixed(1)},${clipBottom.toStringAsFixed(1)})';

      tags += '$clipInit'
          '\\t($tStart,${tStart + 1},$clipStart)'
          '\\t(${tStart + 1},$tEnd,$clipEnd)'
          '\\t($tEnd,${tEnd + 1},$clipFinal)}';
    }

    sb.writeln(
      'Dialogue: $layer,${_formatTime(displayStart)},${_formatTime(displayEnd)},$style,,0,0,0,,$tags$rawText',
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