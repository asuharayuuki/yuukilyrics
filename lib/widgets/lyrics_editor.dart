import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/lyrics_state_service.dart';
import '../services/media_player_service.dart';
import '../models/lyric_ast.dart';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'lrc_syntax_controller.dart';

// ─── CharCell: the smallest rendering unit ─────────────────────────────────
class CharCell {
  final String text;
  final String? ruby; // the combined ruby text
  final int lineIndex;
  final int nodeIndex; // index in line.nodes
  final int? tagNodeIndex; // index of preceding standalone time tag node, if any
  final int charOffset; // offset within text node
  final List<Duration?> startTimes; // one start time for each cursor dot
  final Duration? karaokeStartTime; // for karaoke wipe start
  final bool hasEndTag; // show Tag-10 marker
  final bool isEndTagUntagged; // is the Tag-10 missing a timestamp?
  final Duration? endTime; // for karaoke: when this cell ends

  CharCell({
    required this.text,
    this.ruby,
    required this.lineIndex,
    required this.nodeIndex,
    this.tagNodeIndex,
    this.charOffset = 0,
    required this.startTimes,
    this.karaokeStartTime,
    this.hasEndTag = false,
    this.isEndTagUntagged = false,
    this.endTime,
  });
}

// ─── LyricsEditor Widget ─────────────────────────────────────────────────
class LyricsEditor extends StatefulWidget {
  final bool isTextMode;
  final LyricsStateService lyricsState;
  final MediaPlayerService? mediaPlayer; // optional, for karaoke preview

  const LyricsEditor({
    super.key,
    required this.isTextMode,
    required this.lyricsState,
    this.mediaPlayer,
  });

  @override
  State<LyricsEditor> createState() => _LyricsEditorState();
}

class _LyricsEditorState extends State<LyricsEditor> {
  late LrcSyntaxController _textController;
  late FocusNode _textFocusNode;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int _currentActiveLine = -1;
  int _lastActiveCursorLine = -1;

  // Code editor scroll synchronization & text listener
  late ScrollController _textScrollController;
  late ScrollController _gutterScrollController;

  @override
  void initState() {
    super.initState();
    _textFocusNode = FocusNode();
    _textController = LrcSyntaxController(text: widget.lyricsState.rawText);
    _textScrollController = ScrollController();
    _gutterScrollController = ScrollController();

    _textScrollController.addListener(_syncGutterScroll);
    _textController.addListener(_onTextChanged);

    widget.lyricsState.addListener(_onStateChanged);
    widget.mediaPlayer?.addListener(_onPositionChanged);
  }

  @override
  void dispose() {
    _textScrollController.removeListener(_syncGutterScroll);
    _textController.removeListener(_onTextChanged);
    widget.lyricsState.removeListener(_onStateChanged);
    widget.mediaPlayer?.removeListener(_onPositionChanged);
    _textFocusNode.dispose();
    _textController.dispose();
    _textScrollController.dispose();
    _gutterScrollController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncGutterScroll() {
    if (_gutterScrollController.hasClients) {
      _gutterScrollController.jumpTo(_textScrollController.offset);
    }
  }

  void _onTextChanged() {
    if (mounted) {
      // Only rebuild if we are in text mode, otherwise standard mode handles its own state
      if (widget.isTextMode) {
        setState(() {});
      }
    }
  }

  @override
  void didUpdateWidget(LyricsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTextMode != oldWidget.isTextMode) {
      if (widget.isTextMode) {
        // Switching TO Text Mode
        final sel = widget.lyricsState.selectionPath;
        if (sel != null && widget.lyricsState.document != null) {
          int offset = _getOffsetForNode(sel[0], sel[1]);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _textController.selection = TextSelection.collapsed(offset: offset);
            _textFocusNode.requestFocus();
          });
        }
      } else {
        // Switching TO Standard Mode
        
        int offset = _textController.selection.baseOffset;
        if (offset >= 0 && widget.lyricsState.document != null) {
          final sel = _getNodeForOffset(offset);
          if (sel != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.lyricsState.setSelection(sel[0], sel[1]);
              _scrollToLine(sel[0], 0.3);
            });
          }
        }
      }
    }
  }

  int _getOffsetForNode(int lineIndex, int nodeIndex) {
    final doc = widget.lyricsState.document!;
    int offset = 0;
    for (int i = 0; i < doc.lines.length; i++) {
      if (i == lineIndex) {
        final line = doc.lines[i];
        for (int j = 0; j < line.nodes.length; j++) {
          if (j == nodeIndex) return offset;
          offset += line.nodes[j].toLrcString().length;
        }
        return offset;
      } else {
        offset += doc.lines[i].toLrcString().length + 1; // +1 for \n
      }
    }
    return offset;
  }

  List<int>? _getNodeForOffset(int targetOffset) {
    final doc = widget.lyricsState.document!;
    int offset = 0;
    for (int i = 0; i < doc.lines.length; i++) {
      final lineStr = doc.lines[i].toLrcString();
      if (offset + lineStr.length + 1 > targetOffset) {
        // Target is in this line
        final line = doc.lines[i];
        for (int j = 0; j < line.nodes.length; j++) {
          final nodeStr = line.nodes[j].toLrcString();
          if (offset + nodeStr.length > targetOffset ||
              j == line.nodes.length - 1) {
            return [i, j];
          }
          offset += nodeStr.length;
        }
        return [i, 0];
      }
      offset += lineStr.length + 1;
    }
    return null;
  }

  String _lastRawText = "";
  double? _cachedCharWidth;
  List<Duration?> _cachedLineStartTimes = [];

  void _onStateChanged() {
    final cleanText = widget.lyricsState.rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (_textController.text != cleanText) {
      _textController.text = cleanText;
    }

    if (_lastRawText != cleanText) {
      _lastRawText = cleanText;
      final doc = widget.lyricsState.document;
      if (doc != null) {
        _cachedLineStartTimes = doc.lines.map((l) => _getLineStartTime(l)).toList();
      } else {
        _cachedLineStartTimes = [];
      }
      if (mounted && !widget.isTextMode) {
        setState(() {}); // Rebuild list structure only when text actually changes
      }
    }

    // Auto-scroll to follow active tagging cursor line if tagging is active
    final ac = widget.lyricsState.activeCursor;
    if (ac != null) {
      final lineIdx = ac.lineIndex;
      if (lineIdx != _lastActiveCursorLine) {
        _lastActiveCursorLine = lineIdx;
        _scrollToLine(lineIdx, 0.3);
      }
    } else {
      _lastActiveCursorLine = -1;
    }
  }

  void _onPositionChanged() {

    final pos = widget.mediaPlayer?.position;
    final doc = widget.lyricsState.document;
    if (pos != null && doc != null && doc.lines.isNotEmpty) {
      int newActiveLine = -1;
      final count = _cachedLineStartTimes.length;
      for (int i = count - 1; i >= 0; i--) {
        final lineStartTime = _cachedLineStartTimes[i];
        if (lineStartTime != null && pos >= lineStartTime) {
          newActiveLine = i;
          break;
        }
      }
      if (newActiveLine != -1 && newActiveLine != _currentActiveLine) {
        setState(() {
          _currentActiveLine = newActiveLine;
        });
        
        // If tagging mode is active, do NOT auto-scroll based on audio playback time
        // to avoid layout fights/conflicts with manual scrolling or cursor scrolling.
        if (widget.lyricsState.activeCursor == null) {
          _scrollToLine(newActiveLine, 0.1);
        }
      }
    }
  }

  void _scrollToLine(int lineIdx, double targetAlignment) {
    if (!_scrollController.hasClients) return;

    final key = _lineKeys[lineIdx];
    final context = key?.currentContext;
    
    if (context != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        final viewport = RenderAbstractViewport.of(box);
        final targetOffset = viewport.getOffsetToReveal(box, 0.0).offset;
        final viewportHeight = _scrollController.position.viewportDimension;
        
        // 直接让当前行出现在视图上部 (targetAlignment，如 30%)
        double desiredScroll = targetOffset - (viewportHeight * targetAlignment);
        
        // 限制滚动边界：顶部钉死在0，底部钉死在 maxScrollExtent，不再反弹
        desiredScroll = desiredScroll.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        
        _scrollController.animateTo(
          desiredScroll,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }
    
    // 降级：如果跳到了视野外尚未构建的行，按照平均高度估算并滚动
    double estimatedScroll = lineIdx * 60.0;
    estimatedScroll = estimatedScroll.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      estimatedScroll,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  Duration? _getLineStartTime(LyricLine line) {
    for (final node in line.nodes) {
      if (node is LyricTimeTag) {
        return _parseTime(node.time);
      } else if (node is LyricRuby) {
        for (final rn in node.rubyNodes) {
          if (rn is LyricTimeTag) return _parseTime(rn.time);
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: widget.isTextMode ? EdgeInsets.zero : const EdgeInsets.all(16.0),
      child: widget.isTextMode ? _buildTextMode() : _buildStandardMode(),
    );
  }

  // ─── Text Mode ──────────────────────────────────────────────────────────
  Widget _buildTextMode() {
    final text = _textController.text;
    final lineCount = text.split('\n').length;

    const TextStyle editorTextStyle = TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: [
        'Courier New',
        'Courier',
        // --- Windows Japanese Monospaced ---
        'MS Gothic',
        'ＭＳ ゴシック',
        'Yu Gothic',
        'Meiryo',
        // --- macOS / iOS Japanese Monospaced ---
        'Osaka-Mono',
        'Hiragino Kaku Gothic ProN',
        // --- Android / CJK generic ---
        'Noto Sans Mono CJK JP',
        'Noto Sans Mono CJK SC',
        'Noto Sans Mono CJK TC',
        // --- Chinese Fallbacks ---
        'NSimSun',
        'ＭＳ 明朝',
        'PingFang SC',
        'Microsoft YaHei',
        'メイリオ',
        'monospace',
      ],
      fontSize: 14,
      height: 1.5,
    );

    // Dynamic gutter width computation based on line digits
    final double gutterWidth = (lineCount.toString().length * 9.0) + 24.0;

    // Calculate exact visual ruler location at 80 characters using TextPainter
    if (_cachedCharWidth == null) {
      final textPainter = TextPainter(
        text: const TextSpan(text: 'A', style: editorTextStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      _cachedCharWidth = textPainter.width;
    }
    final double rulerOffset = 80 * _cachedCharWidth! + 16.0; // 16.0 matches left padding of text field

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Line Numbers Gutter
          Container(
            width: gutterWidth,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _gutterScrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(lineCount, (index) {
                      return Container(
                        height: 21.0, // perfect pixel match (14 * 1.5 = 21.0)
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text(
                          '${index + 1}',
                          style: editorTextStyle.copyWith(
                            color: Colors.white.withAlpha(80),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // Gutter Right Divider
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1.0,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          // Scrollable Editor View
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: IntrinsicWidth(
                        child: Stack(
                          children: [
                            // 80-Character Ruler Guide
                            Positioned(
                              left: rulerOffset,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 1.0,
                                color: Colors.white.withAlpha(15),
                              ),
                            ),
                            // Editor Input Field
                            TextField(
                              controller: _textController,
                              focusNode: _textFocusNode,
                              scrollController: _textScrollController,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              selectionHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
                              selectionWidthStyle: ui.BoxWidthStyle.tight,
                              style: editorTextStyle.copyWith(
                                color: Colors.white.withAlpha(220),
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 12.0,
                                  horizontal: 16.0,
                                ),
                                hintText: 'Ciallo～(∠・ω< )⌒☆',
                                isDense: true,
                              ),
                              onChanged: widget.lyricsState.updateFromRawText,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Standard (Tagging + Karaoke) Mode ──────────────────────────────────
  Widget _buildStandardMode() {
    final doc = widget.lyricsState.document;
    if (doc == null || doc.lines.isEmpty) {
      return Center(
        child: Text(
          'Ciallo～(∠・ω< )⌒☆',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withAlpha(100)),
        ),
      );
    }

    return ListView.builder(
      itemCount: doc.lines.length,
      padding: EdgeInsets.zero,
      controller: _scrollController,
      itemBuilder: (context, lineIndex) {
        final key = _lineKeys.putIfAbsent(lineIndex, () => GlobalKey());

        return ListenableBuilder(
          key: key,
          listenable: widget.lyricsState,
          builder: (context, _) {
            final currentDoc = widget.lyricsState.document;
            if (currentDoc == null || lineIndex >= currentDoc.lines.length) {
              return const SizedBox(height: 8);
            }
            final line = currentDoc.lines[lineIndex];
            // Check if line has any visible content
            bool hasContent = line.nodes.any(
              (n) =>
                  n is LyricRuby ||
                  n is LyricTimeTag ||
                  (n is LyricText && n.text.trim().isNotEmpty),
            );
            if (line.nodes.isEmpty || !hasContent) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              );
            }

            final cells = _buildCharCells(line.nodes, lineIndex);
            if (cells.isEmpty) return const SizedBox(height: 8);
            
            bool isLineActive = false;
            if (_currentActiveLine != -1 && (lineIndex - _currentActiveLine).abs() <= 1) {
              isLineActive = true;
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
              child: Row(
                children: [
                  Flexible(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 0,
                      runSpacing: 10.0,
                      children: cells.map((cell) => _buildCharCell(cell, isLineActive)).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Build CharCells from AST nodes ─────────────────────────────────────
  List<CharCell> _buildCharCells(List<LyricNode> nodes, int lineIndex) {
    final cells = <CharCell>[];

    // We iterate through nodes and expand them into per-character cells.
    // We need to track the "current time" for karaoke by looking at time tags.
    Duration? currentTime;
    int? pendingTagNodeIndex;

    for (int ni = 0; ni < nodes.length; ni++) {
      final node = nodes[ni];

      if (node is LyricTimeTag) {
        if (node.type == 10) {
          // Tag-10: mark the LAST cell as having an end marker
          if (cells.isNotEmpty) {
            final lastIdx = cells.length - 1;
            cells[lastIdx] = CharCell(
              text: cells[lastIdx].text,
              ruby: cells[lastIdx].ruby,
              lineIndex: cells[lastIdx].lineIndex,
              nodeIndex: cells[lastIdx].nodeIndex,
              tagNodeIndex: cells[lastIdx].tagNodeIndex,
              charOffset: cells[lastIdx].charOffset,
              startTimes: cells[lastIdx].startTimes,
              karaokeStartTime: cells[lastIdx].karaokeStartTime,
              hasEndTag: true,
              isEndTagUntagged: node.time.isEmpty,
              endTime: _parseTime(node.time),
            );
          }
        } else {
          currentTime = _parseTime(node.time);
          pendingTagNodeIndex = ni;
        }
      } else if (node is LyricText) {
        final text = node.text;
        
        final tokens = widget.lyricsState.tokenizeTextAdvanced(text);
        int charOffset = 0;
        
        for (int ci = 0; ci < tokens.length; ci++) {
          final tokenText = tokens[ci].text;
          // Only the first character block gets the cursor dot
          final isFirstChar = (ci == 0 && pendingTagNodeIndex != null);

          cells.add(
            CharCell(
              text: tokenText,
              lineIndex: lineIndex,
              nodeIndex: ni,
              tagNodeIndex: isFirstChar ? pendingTagNodeIndex : null,
              charOffset: charOffset,
              startTimes: isFirstChar ? [currentTime] : [],
              karaokeStartTime: isFirstChar ? currentTime : null,
            ),
          );
          charOffset += tokenText.length;
        }
        // After consuming text, clear the pending tag
        pendingTagNodeIndex = null;
        currentTime = null;
      } else if (node is LyricRuby) {
        final internalTags = <LyricTimeTag>[];
        final internalTexts = <String>[];
        Duration? rubyEndTime;
        bool hasEndTag = false;
        bool isEndTagUntagged = false;

        for (final rn in node.rubyNodes) {
          if (rn is LyricTimeTag) {
            if (rn.type == 10) {
              rubyEndTime = _parseTime(rn.time);
              hasEndTag = true;
              isEndTagUntagged = rn.time.isEmpty;
            } else {
              internalTags.add(rn);
            }
          } else if (rn is LyricText) {
            // Collect ruby text, omitting segment dividers
            internalTexts.add(rn.text.replaceAll('＋', ''));
          }
        }

        cells.add(
          CharCell(
            text: node.baseText,
            ruby: internalTexts.join(),
            lineIndex: lineIndex,
            nodeIndex: ni,
            charOffset: 0,
            startTimes: internalTags.map((t) => _parseTime(t.time)).toList(),
            karaokeStartTime: internalTags.isNotEmpty
                ? _parseTime(internalTags.first.time)
                : null,
            hasEndTag: hasEndTag,
            isEndTagUntagged: isEndTagUntagged,
            endTime: rubyEndTime,
          ),
        );
      }
    }

    // Post-pass: fill in endTime for cells that don't have it
    // endTime = startTime of the next cell that has a startTime
    for (int i = 0; i < cells.length; i++) {
      if (cells[i].startTimes.isNotEmpty && cells[i].endTime == null) {
        // Find next cell with a startTime
        Duration? nextStart;
        for (int j = i + 1; j < cells.length; j++) {
          if (cells[j].startTimes.isNotEmpty && cells[j].startTimes.first != null) {
            nextStart = cells[j].startTimes.first;
            break;
          }
          // Also check if any cell between has an endTime (Tag-10)
          if (cells[j].endTime != null) {
            nextStart = cells[j].endTime;
            break;
          }
        }
        if (nextStart != null) {
          cells[i] = CharCell(
            text: cells[i].text,
            ruby: cells[i].ruby,
            lineIndex: cells[i].lineIndex,
            nodeIndex: cells[i].nodeIndex,
            tagNodeIndex: cells[i].tagNodeIndex,
            charOffset: cells[i].charOffset,
            startTimes: cells[i].startTimes,
            karaokeStartTime: cells[i].karaokeStartTime,
            hasEndTag: cells[i].hasEndTag,
            isEndTagUntagged: cells[i].isEndTagUntagged,
            endTime: nextStart,
          );
        }
      }
    }

    // Post-pass 2: for multi-char text nodes without individual times,
    // interpolate startTime/endTime from the owning cell
    for (int i = 0; i < cells.length; i++) {
      if (cells[i].startTimes.isEmpty && i > 0) {
        // Find the nearest preceding cell with a startTime
        int prevIdx = i - 1;
        while (prevIdx >= 0 && cells[prevIdx].startTimes.isEmpty) {
          prevIdx--;
        }
        if (prevIdx >= 0 &&
            cells[prevIdx].startTimes.isNotEmpty &&
            cells[prevIdx].startTimes.first != null &&
            cells[prevIdx].endTime != null &&
            cells[prevIdx].nodeIndex == cells[i].nodeIndex) {
          // Count how many chars share this time span
          int spanStart = prevIdx;
          int spanEnd = i;
          while (spanEnd + 1 < cells.length &&
              cells[spanEnd + 1].startTimes.isEmpty &&
              cells[spanEnd + 1].nodeIndex == cells[i].nodeIndex) {
            spanEnd++;
          }
          final totalChars = spanEnd - spanStart + 1;
          final tStart = cells[spanStart].startTimes.first!;
          final tEnd = cells[spanStart].endTime!;
          final spanMs = tEnd.inMilliseconds - tStart.inMilliseconds;

          for (int j = spanStart; j <= spanEnd; j++) {
            final charIdx = j - spanStart;
            final cStart = Duration(
              milliseconds:
                  tStart.inMilliseconds + (spanMs * charIdx ~/ totalChars),
            );
            final cEnd = Duration(
              milliseconds:
                  tStart.inMilliseconds +
                  (spanMs * (charIdx + 1) ~/ totalChars),
            );
            cells[j] = CharCell(
              text: cells[j].text,
              ruby: cells[j].ruby,
              lineIndex: cells[j].lineIndex,
              nodeIndex: cells[j].nodeIndex,
              tagNodeIndex: cells[j].tagNodeIndex,
              charOffset: cells[j].charOffset,
              startTimes: cells[j].startTimes,
              karaokeStartTime: cStart,
              hasEndTag: cells[j].hasEndTag,
              isEndTagUntagged: cells[j].isEndTagUntagged,
              endTime: cEnd,
            );
          }
        }
      }
    }

    return cells;
  }

  Duration? _parseTime(String timeStr) {
    if (timeStr.isEmpty) return null;
    // Format: mm:ss:xx (hundredths)
    final parts = timeStr.split(':');
    if (parts.length != 3) return null;
    final mm = int.tryParse(parts[0]);
    final ss = int.tryParse(parts[1]);
    final xx = int.tryParse(parts[2]);
    if (mm == null || ss == null || xx == null) return null;
    return Duration(minutes: mm, seconds: ss, milliseconds: xx * 10);
  }

  // ─── Build one character cell widget ────────────────────────────────────
  Widget _buildCharCell(CharCell cell, bool isLineActive) {
    return _buildCharCellContent(cell, isLineActive);
  }

  Widget _buildCharCellContent(CharCell cell, bool isLineActive) {
    final cs = Theme.of(context).colorScheme;

    // Check if this cell's node is the active cursor target
    bool isActiveCursorNode = false;
    final ac = widget.lyricsState.activeCursor;
    if (ac != null) {
      isActiveCursorNode = ac.lineIndex == cell.lineIndex &&
          (ac.nodeIndex == cell.nodeIndex ||
              (cell.tagNodeIndex != null && ac.nodeIndex == cell.tagNodeIndex));
    }

    final globalStartTime = cell.karaokeStartTime;

    final isSelected =
        widget.lyricsState.selectionPath != null &&
        widget.lyricsState.selectionPath![0] == cell.lineIndex &&
        widget.lyricsState.selectionPath![1] == cell.nodeIndex &&
        (widget.lyricsState.selectionPath!.length < 3 ||
            widget.lyricsState.selectionPath![2] == cell.charOffset);

    final bool isMobile = Platform.isAndroid || Platform.isIOS;

    return Listener(
      onPointerDown: (_) {
        widget.lyricsState.setSelection(
          cell.lineIndex,
          cell.nodeIndex,
          cell.charOffset,
          cell.tagNodeIndex,
        );
      },
      child: GestureDetector(
        onDoubleTap: (!isMobile && globalStartTime != null)
            ? () {
                widget.mediaPlayer?.seek(globalStartTime);
                widget.mediaPlayer?.play();
              }
            : null,
        onLongPress: (globalStartTime != null)
            ? () {
                widget.mediaPlayer?.seek(globalStartTime);
                widget.mediaPlayer?.play();
              }
            : null,
      child: Container(
        decoration: BoxDecoration(
          color: (isSelected || isActiveCursorNode)
              ? cs.primary.withAlpha(30)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: (isSelected || isActiveCursorNode)
              ? Border.all(color: cs.primary.withAlpha(120), width: 1)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ruby reading
              SizedBox(
                height: 14,
                child: (cell.ruby != null && cell.ruby!.isNotEmpty)
                    ? Center(
                        child: Text(
                          cell.ruby!,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? cs.primary
                                : Colors.white.withAlpha(140),
                            height: 1.0,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : null,
              ),

              // Main character (with karaoke highlighting)
              _buildKaraokeChar(cell, isSelected, isActiveCursorNode, isLineActive),

              const SizedBox(height: 2),

              // Cursor dot + Tag-10 row
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    ...List.generate(cell.startTimes.length, (slotIdx) {
                      final isThisSlotActive =
                          isActiveCursorNode && ac?.slotIndex == slotIdx;
                      final isUntagged = cell.startTimes[slotIdx] == null;

                      Color baseColor;
                      if (isThisSlotActive) {
                        baseColor = Colors.amberAccent;
                      } else if (isSelected || isActiveCursorNode) {
                        baseColor = isUntagged
                            ? Colors.white.withAlpha(60)
                            : cs.primary;
                      } else {
                        baseColor = isUntagged
                            ? Colors.white.withAlpha(60)
                            : cs.primary.withAlpha(180);
                      }

                      return Listener(
                        onPointerDown: (_) => widget.lyricsState.setActiveCursorByTap(
                          cell.lineIndex,
                          cell.nodeIndex,
                          slotIdx,
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(right: 2),
                          width: 8,
                          height: 4,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: isThisSlotActive
                                ? [
                                    BoxShadow(
                                      color: Colors.amberAccent.withAlpha(160),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    }),
                    if (cell.hasEndTag)
                      Container(
                        margin: const EdgeInsets.only(left: 1),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: cell.isEndTagUntagged
                              ? Colors.deepOrangeAccent.withAlpha(80)
                              : Colors.deepOrangeAccent,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  // ─── Karaoke character with gradient wipe ───────────────────────────────
  Widget _buildKaraokeChar(
    CharCell cell,
    bool isSelected,
    bool isActiveCursorNode,
    bool isLineActive,
  ) {
    if (widget.mediaPlayer == null) {
      return Text(
        cell.text,
        style: TextStyle(
          fontSize: 24,
          height: 1.1,
          color: (isSelected || isActiveCursorNode) ? Colors.white : Colors.white.withAlpha(220),
        ),
      );
    }

    Widget buildContent(Duration currentPos, bool isPlaying) {
      final globalStartTime = cell.karaokeStartTime;

      Color charColor = Colors.white.withAlpha(220);
      if (globalStartTime != null) {
        if (cell.endTime != null && currentPos >= cell.endTime!) {
          charColor = Theme.of(context).colorScheme.primary;
        } else if (currentPos >= globalStartTime) {
          charColor = Theme.of(context).colorScheme.primary.withAlpha(220);
        }
      }
      if (isSelected || isActiveCursorNode) {
        charColor = Colors.white;
      }

      // If we have timing, show partial highlight (wipe effect)
      if (globalStartTime != null &&
          cell.endTime != null &&
          currentPos >= globalStartTime &&
          currentPos < cell.endTime!) {
      double progress = 0.0;
      if (cell.startTimes.length > 1) {
        int activeInterval = 0;
        Duration? iStart;
        for (int i = 0; i < cell.startTimes.length; i++) {
          if (cell.startTimes[i] != null && currentPos >= cell.startTimes[i]!) {
            activeInterval = i;
            iStart = cell.startTimes[i];
          }
        }
        
        iStart ??= globalStartTime;
        
        Duration? iEnd;
        for (int i = activeInterval + 1; i < cell.startTimes.length; i++) {
          if (cell.startTimes[i] != null) {
            iEnd = cell.startTimes[i];
            break;
          }
        }
        iEnd ??= cell.endTime!;
        
        final totalMs = iEnd.inMilliseconds - iStart.inMilliseconds;
        final elapsed = currentPos.inMilliseconds - iStart.inMilliseconds;
        final intervalProgress = totalMs > 0 ? (elapsed / totalMs).clamp(0.0, 1.0) : 0.0;
        
        progress = (activeInterval + intervalProgress) / cell.startTimes.length;
      } else {
        final totalMs = cell.endTime!.inMilliseconds - globalStartTime.inMilliseconds;
        final elapsed = currentPos.inMilliseconds - globalStartTime.inMilliseconds;
        progress = totalMs > 0 ? (elapsed / totalMs).clamp(0.0, 1.0) : 0.0;
      }

      final cs = Theme.of(context).colorScheme;
      return Stack(
        children: [
          Text(
            cell.text,
            style: TextStyle(
              fontSize: 24,
              height: 1.1,
              color: Colors.white.withAlpha(220),
            ),
          ),
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Text(
                cell.text,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.1,
                  color: cs.primary,
                ),
              ),
            ),
          ),
        ],
      );
    }

      return Text(
        cell.text,
        style: TextStyle(
          fontSize: 24,
          height: 1.1,
          color: charColor,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      );
    }

    if (!isLineActive) {
      return buildContent(widget.mediaPlayer!.position, widget.mediaPlayer!.isPlaying);
    }

    return AnimatedBuilder(
      animation: widget.mediaPlayer!,
      builder: (context, child) {
        return buildContent(widget.mediaPlayer!.position, widget.mediaPlayer!.isPlaying);
      },
    );
  }
}
