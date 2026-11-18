part of '../ass_exporter.dart';

// Grouping lyric lines into on-screen pages and line alignment.

List<AssBlock> _groupLinesIntoBlocks(
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
        if (node.rubyNodes.isNotEmpty && node.rubyNodes.first is LyricTimeTag) {
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
            double w = _getCharWidth(cluster, fs, lineSpacingVal, textMetrics);
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
            remainingAtoms.first.accumulatedWidth - remainingAtoms.first.width;

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
        if (node is LyricRuby || (node is LyricText && node.text.isNotEmpty)) {
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

double _timingWidth(_Atom atom) =>
    atom.originalNode is _SingerMarkerNode ? 0 : atom.width;

AssLineAlignment _resolveLineAlignment(
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
