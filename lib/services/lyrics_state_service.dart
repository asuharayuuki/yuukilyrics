import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../models/lyric_ast.dart';
import '../parser/lrc_parser.dart';
import 'auto_tagger.dart';
import 'singer_markers.dart';
import 'text_file_decoder.dart';
import 'yahoo_furigana_client.dart';

export 'auto_tagger.dart' show TextToken;

/// How [LyricsStateService.autoRubyAndTagDocument] finished.
enum AutoRubyOutcome {
  completed,

  /// Stopped by the caller; readings fetched before the stop were applied.
  cancelled,

  /// The document was replaced mid-request, so nothing was applied.
  documentChanged,
}

class AutoRubyProgress {
  final int completedBatches;
  final int totalBatches;

  /// True once all requests are done and the document is being updated.
  final bool applying;

  const AutoRubyProgress({
    required this.completedBatches,
    required this.totalBatches,
    this.applying = false,
  });

  double get fraction =>
      totalBatches == 0 ? 1 : (completedBatches / totalBatches).clamp(0, 1);
}

/// Represents one taggable slot in the document.
class TaggingSlot {
  final int lineIndex;
  final int nodeIndex;
  final int slotIndex; // which time-tag slot within this node (0-based)
  final bool isRuby;

  const TaggingSlot({
    required this.lineIndex,
    required this.nodeIndex,
    required this.slotIndex,
    required this.isRuby,
  });

  @override
  bool operator ==(Object other) =>
      other is TaggingSlot &&
      other.lineIndex == lineIndex &&
      other.nodeIndex == nodeIndex &&
      other.slotIndex == slotIndex;

  @override
  int get hashCode => Object.hash(lineIndex, nodeIndex, slotIndex);
}

class LyricsStateService extends ChangeNotifier {
  LyricDocument? _document;
  String _rawText = '';

  List<int>? _selectionPath; // [lineIndex, nodeIndex]
  TaggingSlot? _activeCursor;
  List<TaggingSlot> _allSlots = [];

  LyricDocument? get document => _document;
  String get rawText => _rawText;
  List<int>? get selectionPath => _selectionPath;
  TaggingSlot? get activeCursor => _activeCursor;

  /// Offset applied when recording timestamps, in milliseconds.
  /// Default -230ms to compensate for human reaction time
  /// (same as RhythmicaLyrics: タイムタグ打ち込み時にずらす時間 = -23 × 10ms).
  int taggingOffsetMs = -230;
  bool _hapticFeedbackEnabled = false;
  bool get hapticFeedbackEnabled => _hapticFeedbackEnabled;
  String? parseError;

  void toggleHapticFeedback() {
    _hapticFeedbackEnabled = !_hapticFeedbackEnabled;
    notifyListeners();
  }

  Duration _applyOffset(Duration position) {
    final ms = (position.inMilliseconds + taggingOffsetMs).clamp(
      0,
      double.maxFinite.toInt(),
    );
    return Duration(milliseconds: ms);
  }

  /// Shift all timestamps in the document by [offsetMs].
  void shiftAllTimestamps(int offsetMs) {
    if (_document == null) return;

    for (final line in _document!.lines) {
      for (final node in line.nodes) {
        if (node is LyricTimeTag && node.time.isNotEmpty) {
          final current = LyricTimeTag.parseDuration(node.time);
          if (current != null) {
            final ms = (current.inMilliseconds + offsetMs).clamp(
              0,
              double.maxFinite.toInt(),
            );
            node.time = LyricTimeTag.formatDuration(Duration(milliseconds: ms));
          }
        } else if (node is LyricRuby) {
          for (final rn in node.rubyNodes) {
            if (rn is LyricTimeTag && rn.time.isNotEmpty) {
              final current = LyricTimeTag.parseDuration(rn.time);
              if (current != null) {
                final ms = (current.inMilliseconds + offsetMs).clamp(
                  0,
                  double.maxFinite.toInt(),
                );
                rn.time = LyricTimeTag.formatDuration(
                  Duration(milliseconds: ms),
                );
              }
            }
          }
        }
      }
    }

    _syncRawText();
    notifyListeners();
  }

  bool _isGlobalTimeShiftMode = false;
  bool get isGlobalTimeShiftMode => _isGlobalTimeShiftMode;

  Duration? _globalTimeShiftBaseTime;
  Duration? get globalTimeShiftBaseTime => _globalTimeShiftBaseTime;

  Duration? _globalTimeShiftTargetTime;

  void setGlobalTimeShiftTargetTime(Duration target) {
    _globalTimeShiftTargetTime = target;
  }

  void toggleGlobalTimeShiftMode(Duration currentPosition) {
    if (_isGlobalTimeShiftMode) {
      if (_globalTimeShiftBaseTime != null &&
          _globalTimeShiftTargetTime != null) {
        final offset =
            _globalTimeShiftTargetTime!.inMilliseconds -
            _globalTimeShiftBaseTime!.inMilliseconds;
        if (offset != 0) {
          shiftAllTimestamps(offset);
        }
      }
      _isGlobalTimeShiftMode = false;
      _globalTimeShiftBaseTime = null;
      _globalTimeShiftTargetTime = null;
    } else {
      _isGlobalTimeShiftMode = true;
      _globalTimeShiftBaseTime = currentPosition;
      _globalTimeShiftTargetTime = currentPosition;
    }
    notifyListeners();
  }

  // ─── Document Loading ──────────────────────────────────────────

  /// Replaces the current lyrics with [text].
  ///
  /// The text is parsed before any state changes, so if parsing throws, the
  /// previous document, raw text and selection stay intact and the error
  /// propagates to the caller.
  void loadLrcText(String text) {
    final cleanText = TextFileDecoder.stripBom(
      text,
    ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final document = LrcParser.parseDocument(cleanText);
    _rawText = cleanText;
    _document = document;
    _selectionPath = null;
    _activeCursor = null;
    parseError = null;
    _rebuildSlotList();
    notifyListeners();
  }

  void updateFromRawText(String text) {
    final cleanText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    _rawText = cleanText;
    try {
      _document = LrcParser.parseDocument(cleanText);
      _rebuildSlotList();
      parseError = null;
    } catch (e) {
      parseError = e.toString();
    }
    notifyListeners();
  }

  void _syncRawText() {
    if (_document != null) {
      _rawText = _document!.toLrcString();
      // Normalize AST based strictly on text representation
      _document = LrcParser.parseDocument(_rawText);
    }
    _rebuildSlotList();
  }

  // ─── Selection ─────────────────────────────────────────────────

  /// When a user taps a character in the lyrics editor, we:
  /// 1) Mark it as selected (for toolbar actions)
  /// 2) Move the active tagging cursor to its first slot (if tagging mode is active)
  void setSelection(
    int lineIndex,
    int nodeIndex, [
    int charOffset = 0,
    int? tagNodeIndex,
    int selectedTextLength = 1,
  ]) {
    if (_document == null ||
        lineIndex < 0 ||
        lineIndex >= _document!.lines.length ||
        nodeIndex < 0 ||
        nodeIndex >= _document!.lines[lineIndex].nodes.length) {
      _selectionPath = null;
      notifyListeners();
      return;
    }
    _selectionPath = [
      lineIndex,
      nodeIndex,
      charOffset,
      tagNodeIndex ?? -1,
      selectedTextLength,
    ];

    // Also jump the active cursor to the first slot of this node
    if (_activeCursor != null) {
      final match = _allSlots
          .where(
            (s) =>
                s.lineIndex == lineIndex &&
                (s.nodeIndex == nodeIndex ||
                    (tagNodeIndex != null && s.nodeIndex == tagNodeIndex)),
          )
          .firstOrNull;
      if (match != null) {
        _activeCursor = match;
      }
    }

    notifyListeners();
  }

  void clearSelection() {
    _selectionPath = null;
    notifyListeners();
  }

  LyricNode? getSelectedNode() {
    if (!_selectionIsValid()) return null;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    if (li >= 0 && li < _document!.lines.length) {
      final nodes = _document!.lines[li].nodes;
      if (ni >= 0 && ni < nodes.length) return nodes[ni];
    }
    return null;
  }

  bool _selectionIsValid() {
    if (_document == null ||
        _selectionPath == null ||
        _selectionPath!.length < 2) {
      return false;
    }
    final lineIndex = _selectionPath![0];
    final nodeIndex = _selectionPath![1];
    return lineIndex >= 0 &&
        lineIndex < _document!.lines.length &&
        nodeIndex >= 0 &&
        nodeIndex < _document!.lines[lineIndex].nodes.length;
  }

  String? matchingPrefixAtSelection(Iterable<String> prefixes) {
    if (!_selectionIsValid()) return null;
    final lineIndex = _selectionPath![0];
    if (lineIndex < 0 || lineIndex >= _document!.lines.length) return null;

    final candidates =
        prefixes
            .map((prefix) => prefix.trim())
            .where((prefix) => prefix.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    if (candidates.isEmpty) return null;

    final selectedLine = _document!.lines[lineIndex];
    final selectedRawOffset = _rawOffsetForSelection(selectedLine);
    final selectedRawText = selectedLine.toLrcString();
    final selectedPrefix = candidates
        .where(
          (candidate) =>
              selectedRawText.startsWith(candidate, selectedRawOffset),
        )
        .firstOrNull;
    if (selectedPrefix != null) return selectedPrefix;

    // Scan like the ASS exporter does, so the highlighted marker is the one
    // that colors the selection. Picking the occurrence that starts last
    // would read the `B` inside a preceding `A/B` as the active singer.
    final markers = SingerMarkers(candidates);
    for (var index = lineIndex; index >= 0; index--) {
      final plainText = index == lineIndex
          ? _plainTextBeforeSelection(_document!.lines[index])
          : _plainText(_document!.lines[index]);
      final match = markers.lastMarker(plainText);
      if (match != null) return match;
    }
    return null;
  }

  bool togglePrefixBeforeSelection(
    String prefix,
    Iterable<String> knownPrefixes,
  ) {
    if (!_selectionIsValid()) return false;
    final lineIndex = _selectionPath![0];
    if (lineIndex < 0 || lineIndex >= _document!.lines.length) return false;

    final normalizedPrefix = prefix.trim();
    if (normalizedPrefix.isEmpty) return false;

    final line = _document!.lines[lineIndex];
    final nodeIndex = _selectionPath![1];
    if (nodeIndex < 0 || nodeIndex >= line.nodes.length) return false;

    final selectedRawOffset = _rawOffsetForSelection(line);
    var insertionOffset = selectedRawOffset;
    final tagNodeIndex = _selectionPath!.length > 3 ? _selectionPath![3] : -1;
    if (tagNodeIndex >= 0 && tagNodeIndex < nodeIndex) {
      insertionOffset = _rawOffsetBeforeNode(line, tagNodeIndex);
    }
    final candidates =
        knownPrefixes
            .map((candidate) => candidate.trim())
            .where((candidate) => candidate.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    final activeCursorIndex = _activeCursor == null
        ? -1
        : _allSlots.indexOf(_activeCursor!);

    final rawLine = line.toLrcString();
    final selectedPrefix = candidates
        .where((candidate) => rawLine.startsWith(candidate, selectedRawOffset))
        .firstOrNull;
    final textBeforeInsertion = rawLine.substring(0, insertionOffset);
    final precedingPrefix = selectedPrefix == null
        ? candidates.where(textBeforeInsertion.endsWith).firstOrNull
        : null;
    final existingPrefix = selectedPrefix ?? precedingPrefix;
    final replacement = existingPrefix == normalizedPrefix
        ? ''
        : normalizedPrefix;
    final replaceStart = selectedPrefix != null
        ? selectedRawOffset
        : precedingPrefix == null
        ? insertionOffset
        : insertionOffset - precedingPrefix.length;
    final replaceEnd = selectedPrefix != null
        ? selectedRawOffset + selectedPrefix.length
        : insertionOffset;
    final selectionDelta = replacement.length - (existingPrefix?.length ?? 0);
    _document!.lines[lineIndex] = LrcParser.parseLine(
      rawLine.substring(0, replaceStart) +
          replacement +
          rawLine.substring(replaceEnd),
    );
    _syncRawText();
    if (activeCursorIndex >= 0 && activeCursorIndex < _allSlots.length) {
      _activeCursor = _allSlots[activeCursorIndex];
    }
    _selectAtRawOffset(
      lineIndex,
      selectedPrefix != null
          ? replaceStart
          : selectedRawOffset + selectionDelta,
    );
    notifyListeners();
    return true;
  }

  int _rawOffsetForSelection(LyricLine line) {
    final nodeIndex = _selectionPath![1];
    var offset = _rawOffsetBeforeNode(line, nodeIndex);
    final node = line.nodes[nodeIndex];
    if (node is LyricText && _selectionPath!.length > 2) {
      offset += _selectionPath![2].clamp(0, node.text.length);
    }
    return offset;
  }

  int _rawOffsetBeforeNode(LyricLine line, int nodeIndex) {
    var offset = 0;
    for (var index = 0; index < nodeIndex; index++) {
      offset += line.nodes[index].toLrcString().length;
    }
    return offset;
  }

  String _plainText(LyricLine line) {
    final buffer = StringBuffer();
    for (final node in line.nodes) {
      if (node is LyricText) {
        buffer.write(node.text);
      } else if (node is LyricRuby) {
        buffer.write(node.baseText);
      }
    }
    return buffer.toString();
  }

  String _plainTextBeforeSelection(LyricLine line) {
    final buffer = StringBuffer();
    final selectedNodeIndex = _selectionPath![1];
    for (var index = 0; index < line.nodes.length; index++) {
      if (index > selectedNodeIndex) break;
      final node = line.nodes[index];
      if (node is LyricText) {
        if (index == selectedNodeIndex) {
          final offset = _selectionPath!.length > 2
              ? _selectionPath![2].clamp(0, node.text.length)
              : 0;
          buffer.write(node.text.substring(0, offset));
        } else {
          buffer.write(node.text);
        }
      } else if (node is LyricRuby && index < selectedNodeIndex) {
        buffer.write(node.baseText);
      }
    }
    return buffer.toString();
  }

  void _selectAtRawOffset(int lineIndex, int rawOffset) {
    if (_document == null || lineIndex >= _document!.lines.length) return;
    final nodes = _document!.lines[lineIndex].nodes;
    var offset = 0;
    for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex++) {
      final node = nodes[nodeIndex];
      final length = node.toLrcString().length;
      if (node is LyricText && rawOffset < offset + length) {
        final charOffset = (rawOffset - offset).clamp(0, node.text.length);
        var tagNodeIndex = -1;
        if (charOffset == 0) {
          for (var previous = nodeIndex - 1; previous >= 0; previous--) {
            final previousNode = nodes[previous];
            if (previousNode is LyricTimeTag && previousNode.type != 10) {
              tagNodeIndex = previous;
              break;
            }
            if (previousNode is LyricText || previousNode is LyricRuby) break;
          }
        }
        _selectionPath = [lineIndex, nodeIndex, charOffset, tagNodeIndex];
        return;
      }
      if (node is LyricRuby && rawOffset <= offset) {
        _selectionPath = [lineIndex, nodeIndex, 0, -1];
        return;
      }
      offset += length;
    }
  }

  // ─── Slot List ─────────────────────────────────────────────────
  // Builds a flat, ordered list of all taggable slots in the document.
  // For LyricRuby: nodeIndex = the ruby node's index in line.nodes
  // For standalone tags: nodeIndex = the LyricTimeTag's index in line.nodes

  void _rebuildSlotList() {
    _allSlots = [];
    if (_document == null) return;
    for (int li = 0; li < _document!.lines.length; li++) {
      final line = _document!.lines[li];
      for (int ni = 0; ni < line.nodes.length; ni++) {
        final node = line.nodes[ni];
        if (node is LyricRuby) {
          final head = node.rubyNodes
              .whereType<LyricTimeTag>()
              .where((tag) => tag.type != 10)
              .firstOrNull;
          final count = head == null ? 0 : _standaloneCheckCount(head);
          for (var slotIdx = 0; slotIdx < count; slotIdx++) {
            _allSlots.add(
              TaggingSlot(
                lineIndex: li,
                nodeIndex: ni,
                slotIndex: slotIdx,
                isRuby: true,
              ),
            );
          }
        } else if (node is LyricTimeTag && node.type != 10) {
          final count = _standaloneCheckCount(node);
          for (var slotIdx = 0; slotIdx < count; slotIdx++) {
            _allSlots.add(
              TaggingSlot(
                lineIndex: li,
                nodeIndex: ni,
                slotIndex: slotIdx,
                isRuby: false,
              ),
            );
          }
        }
      }
    }
  }

  // ─── Tagging Cursor Navigation ─────────────────────────────────

  void startTagging() {
    if (_allSlots.isEmpty) return;
    _activeCursor = _allSlots.first;
    notifyListeners();
  }

  void stopTagging() {
    _activeCursor = null;
    notifyListeners();
  }

  void setActiveCursorByTap(int lineIndex, int nodeIndex, int slotIndex) {
    final match = _allSlots
        .where(
          (s) =>
              s.lineIndex == lineIndex &&
              s.nodeIndex == nodeIndex &&
              s.slotIndex == slotIndex,
        )
        .firstOrNull;
    if (match != null) {
      _activeCursor = match;
      notifyListeners();
    }
  }

  void _advanceActiveCursor() {
    if (_activeCursor == null || _allSlots.isEmpty) return;
    final idx = _allSlots.indexOf(_activeCursor!);
    if (idx >= 0 && idx + 1 < _allSlots.length) {
      _activeCursor = _allSlots[idx + 1];
    } else {
      _activeCursor = null; // end of document
    }
  }

  // ─── Timestamp Recording ───────────────────────────────────────

  bool get activeCursorHasEndTag {
    if (_document == null || _activeCursor == null) return false;
    final slot = _activeCursor!;
    final line = _document!.lines[slot.lineIndex];
    final insertAfter = _endTagInsertAfter(slot, line);
    if (insertAfter == -1) return false;
    final nextIndex = insertAfter + 1;
    return nextIndex < line.nodes.length &&
        line.nodes[nextIndex] is LyricTimeTag &&
        (line.nodes[nextIndex] as LyricTimeTag).type == 10;
  }

  void recordTimestamp(Duration position, {bool advance = true}) {
    if (_document == null || _activeCursor == null) return;
    final slot = _activeCursor!;
    final adjusted = _applyOffset(position);
    final timeStr = LyricTimeTag.formatDuration(adjusted);
    final line = _document!.lines[slot.lineIndex];

    if (slot.isRuby) {
      final ruby = line.nodes[slot.nodeIndex] as LyricRuby;
      final tags = ruby.rubyNodes
          .whereType<LyricTimeTag>()
          .where((tag) => tag.type != 10)
          .toList();
      while (tags.length <= slot.slotIndex) {
        tags.add(LyricTimeTag(type: null, time: ''));
      }
      tags[slot.slotIndex].time = timeStr;

      final rubyText = ruby.rubyNodes
          .whereType<LyricText>()
          .map((text) => text.text)
          .join();
      final tag10List = ruby.rubyNodes
          .whereType<LyricTimeTag>()
          .where((tag) => tag.type == 10)
          .toList();
      final newNodes = _rebuildRubyNodes(tags, rubyText)..addAll(tag10List);
      line.nodes[slot.nodeIndex] = LyricRuby(
        baseText: ruby.baseText,
        rubyNodes: newNodes,
        joinNext: ruby.joinNext,
      );
    } else if (slot.slotIndex == 0) {
      final tag = line.nodes[slot.nodeIndex];
      if (tag is LyricTimeTag) {
        tag.time = timeStr;
      }
    } else {
      final tag = line.nodes[slot.nodeIndex];
      final textIndex = slot.nodeIndex + 1;
      if (tag is! LyricTimeTag ||
          textIndex >= line.nodes.length ||
          line.nodes[textIndex] is! LyricText) {
        return;
      }
      final textNode = line.nodes[textIndex] as LyricText;
      final tokens = tokenizeTextAdvanced(textNode.text);
      if (tokens.isEmpty || tokens.first.text.isEmpty) return;
      final baseText = tokens.first.text;
      final rightText = textNode.text.substring(baseText.length);
      final checkCount = _standaloneCheckCount(tag);
      final tags = <LyricTimeTag>[
        LyricTimeTag(type: checkCount, time: tag.time),
        for (var index = 1; index < checkCount; index++)
          LyricTimeTag(type: null, time: ''),
      ];
      tags[slot.slotIndex].time = timeStr;
      final replacement = <LyricNode>[
        LyricRuby(baseText: baseText, rubyNodes: tags),
        if (rightText.isNotEmpty) LyricText(rightText),
      ];
      line.nodes.replaceRange(slot.nodeIndex, textIndex + 1, replacement);
    }

    _syncRawText();
    if (advance) _advanceActiveCursor();
    notifyListeners();
  }

  /// Records a Tag-10 end marker after the current active slot.
  ///
  /// For Ruby: Tag-10 goes right after the LyricRuby node in line.nodes.
  /// For standalone kana: a standalone tag [T] is followed by text [TXT],
  ///   so Tag-10 goes after the text node (nodeIndex + 1).
  void recordEndTag(Duration position, {bool forceInsert = false}) {
    if (_document == null || _activeCursor == null) return;
    final slot = _activeCursor!;
    final adjusted = _applyOffset(position);
    final timeStr = LyricTimeTag.formatDuration(adjusted);
    final line = _document!.lines[slot.lineIndex];
    final insertAfter = _endTagInsertAfter(slot, line);

    if (insertAfter != -1) {
      final nextIdx = insertAfter + 1;
      if (nextIdx < line.nodes.length &&
          line.nodes[nextIdx] is LyricTimeTag &&
          (line.nodes[nextIdx] as LyricTimeTag).type == 10) {
        (line.nodes[nextIdx] as LyricTimeTag).time = timeStr;
      } else if (forceInsert) {
        line.nodes.insert(nextIdx, LyricTimeTag(type: 10, time: timeStr));
      }
    }

    _syncRawText();
    _advanceActiveCursor();
    notifyListeners();
  }

  int _endTagInsertAfter(TaggingSlot slot, LyricLine line) {
    if (slot.isRuby) {
      final ruby = line.nodes[slot.nodeIndex] as LyricRuby;
      final head = ruby.rubyNodes
          .whereType<LyricTimeTag>()
          .where((tag) => tag.type != 10)
          .firstOrNull;
      final count = head == null ? 0 : _standaloneCheckCount(head);
      return slot.slotIndex == count - 1 ? slot.nodeIndex : -1;
    }

    var insertAfter = slot.nodeIndex + 1;
    while (insertAfter < line.nodes.length &&
        line.nodes[insertAfter] is LyricText) {
      insertAfter++;
    }
    insertAfter--;
    return insertAfter < slot.nodeIndex ? slot.nodeIndex : insertAfter;
  }

  // ─── Cursor Count Manipulation ─────────────────────────────────

  void addCursorToSelected() {
    if (!_selectionIsValid()) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];

    if (node is LyricRuby) {
      final newNodes = List<LyricNode>.from(node.rubyNodes);
      final headIndex = newNodes.indexWhere(
        (rubyNode) => rubyNode is LyricTimeTag && rubyNode.type != 10,
      );
      if (headIndex == -1) {
        newNodes.insert(0, LyricTimeTag(type: 1, time: ''));
      } else {
        final head = newNodes[headIndex] as LyricTimeTag;
        final count = _standaloneCheckCount(head);
        if (count >= 7) return;
        head.type = count + 1;
      }
      line.nodes[ni] = LyricRuby(
        baseText: node.baseText,
        rubyNodes: newNodes,
        joinNext: node.joinNext,
      );
      _syncRawText();
      notifyListeners();
      return;
    }

    if (node is LyricText) {
      final charOffset = _selectionPath!.length > 2 ? _selectionPath![2] : 0;
      final tagNodeIndex = _selectionPath!.length > 3 ? _selectionPath![3] : -1;
      final text = node.text;

      if (text.isEmpty) return;

      // Has a preceding tag and we tapped the first char
      if (charOffset == 0 &&
          tagNodeIndex != -1 &&
          tagNodeIndex < line.nodes.length) {
        final precedingNode = line.nodes[tagNodeIndex];
        if (precedingNode is LyricTimeTag && precedingNode.type != 10) {
          final count = _standaloneCheckCount(precedingNode);
          if (count >= 7) return;
          precedingNode.type = count + 1;
          _syncRawText();
          notifyListeners();
          return;
        }
      }

      // No preceding tag OR clicked in the middle of text
      if (charOffset == 0) {
        line.nodes.insert(ni, LyricTimeTag(type: 1, time: ''));
        _selectionPath = [li, ni + 1, 0, ni];
      } else if (charOffset > 0 && charOffset < text.length) {
        final leftText = text.substring(0, charOffset);
        final rightText = text.substring(charOffset);
        line.nodes[ni] = LyricText(leftText);
        line.nodes.insert(ni + 1, LyricTimeTag(type: 1, time: ''));
        line.nodes.insert(ni + 2, LyricText(rightText));
        _selectionPath = [li, ni + 2, 0, ni + 1];
      } else {
        line.nodes.insert(ni, LyricTimeTag(type: 1, time: ''));
        _selectionPath = [li, ni + 1, 0, ni];
      }

      _syncRawText();
      notifyListeners();
      return;
    }

    if (node is LyricTimeTag) {
      if (node.type == 10) return;
      final count = _standaloneCheckCount(node);
      if (count >= 7) return;
      node.type = count + 1;
      _syncRawText();
      notifyListeners();
      return;
    }
  }

  void removeCursorFromSelected() {
    if (!_selectionIsValid()) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];
    if (node is LyricRuby) {
      final newNodes = List<LyricNode>.from(node.rubyNodes);
      final headIndex = newNodes.indexWhere(
        (rubyNode) => rubyNode is LyricTimeTag && rubyNode.type != 10,
      );
      if (headIndex == -1) return;
      final head = newNodes[headIndex] as LyricTimeTag;
      final count = _standaloneCheckCount(head);
      if (count == 0) return;

      if (count > 1) {
        head.type = count - 1;
      } else if (head.time.isNotEmpty) {
        head.type = null;
      } else {
        newNodes.removeAt(headIndex);
      }

      final hasRubyText = newNodes.any(
        (rubyNode) => rubyNode is LyricText && rubyNode.text.isNotEmpty,
      );
      final remainingTags = newNodes
          .whereType<LyricTimeTag>()
          .where((tag) => tag.type != 10)
          .toList();
      final tag10List = newNodes
          .whereType<LyricTimeTag>()
          .where((tag) => tag.type == 10)
          .toList();

      if (!hasRubyText &&
          remainingTags.length <= 1 &&
          !_isRubyUnitConnected(line, ni, node)) {
        final replacement = <LyricNode>[
          ...remainingTags,
          LyricText(node.baseText),
          ...tag10List,
        ];
        final textNodeIndex = ni + remainingTags.length;
        line.nodes.replaceRange(ni, ni + 1, replacement);
        _selectionPath = [
          li,
          textNodeIndex,
          0,
          remainingTags.isEmpty ? -1 : ni,
          node.baseText.length,
        ];
      } else {
        line.nodes[ni] = LyricRuby(
          baseText: node.baseText,
          rubyNodes: newNodes,
          joinNext: node.joinNext,
        );
        _selectionPath = [li, ni, 0, -1, node.baseText.length];
      }
    } else if (node is LyricTimeTag && node.type != 10) {
      _decrementStandaloneCheck(line, ni);
      _selectionPath = null;
    } else if (node is LyricText) {
      final tagNodeIndex = _selectionPath!.length > 3 ? _selectionPath![3] : -1;
      if (tagNodeIndex != -1 &&
          tagNodeIndex < line.nodes.length &&
          line.nodes[tagNodeIndex] is LyricTimeTag &&
          (line.nodes[tagNodeIndex] as LyricTimeTag).type != 10) {
        final tagKept = _decrementStandaloneCheck(line, tagNodeIndex);
        final newTextIndex = tagKept ? ni : ni - 1;
        _selectionPath = [
          li,
          newTextIndex,
          0,
          tagKept ? tagNodeIndex : -1,
          _selectionPath!.length > 4 ? _selectionPath![4] : 1,
        ];
      }
    }

    _syncRawText();
    notifyListeners();
  }

  /// Marks the selected logical unit as connected to the next one.
  ///
  /// RhythmicaLyrics keeps both units independent and only stores a trailing
  /// full-width plus marker on the left unit. [LyricLine.toLrcString] performs
  /// the temporary `{base|ruby}` grouping when the document is serialized.
  void mergeSelectedWithNext() {
    if (!_selectionIsValid()) return;
    final li = _selectionPath![0];
    var ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni < 0 || ni >= line.nodes.length) return;

    var current = line.nodes[ni];
    if (current is LyricText) {
      final start = (_selectionPath!.length > 2 ? _selectionPath![2] : 0).clamp(
        0,
        current.text.length,
      );
      final end = _selectedTextEnd(current.text, start);
      if (start >= end) return;

      final prefix = current.text.substring(0, start);
      final selectedText = current.text.substring(start, end);
      final suffix = current.text.substring(end);
      final rubyNodes = <LyricNode>[];
      var replaceStart = ni;
      final tagNodeIndex = _selectionPath!.length > 3 ? _selectionPath![3] : -1;
      if (start == 0 &&
          tagNodeIndex == ni - 1 &&
          tagNodeIndex >= 0 &&
          line.nodes[tagNodeIndex] is LyricTimeTag &&
          (line.nodes[tagNodeIndex] as LyricTimeTag).type != 10) {
        rubyNodes.add(line.nodes[tagNodeIndex]);
        replaceStart = tagNodeIndex;
      }

      final replacement = <LyricNode>[];
      if (prefix.isNotEmpty) replacement.add(LyricText(prefix));
      ni = replaceStart + replacement.length;
      replacement.add(LyricRuby(baseText: selectedText, rubyNodes: rubyNodes));
      if (suffix.isNotEmpty) replacement.add(LyricText(suffix));
      line.nodes.replaceRange(
        replaceStart,
        _selectionPath![1] + 1,
        replacement,
      );
      current = line.nodes[ni];
    }

    if (current is! LyricRuby) return;
    final chainStart = ni;
    ni = _rubyChainEndIndex(line, ni);
    current = line.nodes[ni];
    if (current is! LyricRuby || current.joinNext) return;
    if (current.rubyNodes.any(
      (node) => node is LyricTimeTag && node.type == 10,
    )) {
      return;
    }

    final nextIndex = ni + 1;
    if (nextIndex >= line.nodes.length) return;
    var targetIndex = nextIndex;
    LyricTimeTag? precedingTag;
    if (line.nodes[targetIndex] is LyricTimeTag) {
      final tag = line.nodes[targetIndex] as LyricTimeTag;
      if (tag.type == 10) return;
      precedingTag = tag;
      targetIndex++;
      if (targetIndex >= line.nodes.length) return;
    }

    final nextNode = line.nodes[targetIndex];
    LyricRuby nextRuby;
    if (nextNode is LyricRuby) {
      nextRuby = LyricRuby(
        baseText: nextNode.baseText,
        rubyNodes: [?precedingTag, ...nextNode.rubyNodes],
        joinNext: nextNode.joinNext,
      );
      line.nodes.replaceRange(nextIndex, targetIndex + 1, [nextRuby]);
    } else if (nextNode is LyricText) {
      final tokens = tokenizeTextAdvanced(nextNode.text);
      if (tokens.isEmpty || tokens.first.text.isEmpty) return;
      final nextText = tokens.first.text;
      final suffix = nextNode.text.substring(nextText.length);
      nextRuby = LyricRuby(baseText: nextText, rubyNodes: [?precedingTag]);
      line.nodes.replaceRange(nextIndex, targetIndex + 1, [
        nextRuby,
        if (suffix.isNotEmpty) LyricText(suffix),
      ]);
    } else {
      return;
    }

    line.nodes[ni] = LyricRuby(
      baseText: current.baseText,
      rubyNodes: current.rubyNodes,
      joinNext: true,
    );
    final selectedTextLength =
        line.nodes
            .sublist(chainStart, ni + 1)
            .whereType<LyricRuby>()
            .fold<int>(0, (length, ruby) => length + ruby.baseText.length) +
        nextRuby.baseText.length;
    _selectionPath = [li, chainStart, 0, -1, selectedTextLength];

    _syncRawText();
    notifyListeners();
  }

  /// Sets the reading of the selected text, turning it into ruby if needed.
  ///
  /// A singer marker at the start of the selection stays outside the ruby
  /// base: inside it, the exporter could no longer find the marker and would
  /// draw it as lyrics in the wrong color.
  void updateRubyText(String newRubyText, {SingerMarkers? markers}) {
    if (!_selectionIsValid()) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];

    if (node is! LyricRuby) {
      if (newRubyText.isEmpty) return;

      final rubyNodes = <LyricNode>[];
      String baseText = '';
      int removeCount = 1;

      if (node is LyricTimeTag) {
        if (node.type == 10) return;
        rubyNodes.add(node);
        if (ni + 1 < line.nodes.length && line.nodes[ni + 1] is LyricText) {
          baseText = (line.nodes[ni + 1] as LyricText).text;
          removeCount = 2;
        }
        rubyNodes.add(LyricText(newRubyText));
        line.nodes[ni] = LyricRuby(baseText: baseText, rubyNodes: rubyNodes);
        if (removeCount == 2) {
          line.nodes.removeAt(ni + 1);
        }
      } else if (node is LyricText) {
        final charOffset = _selectionPath!.length > 2 ? _selectionPath![2] : 0;
        final text = node.text;

        if (charOffset >= 0 && charOffset < text.length) {
          final selectedEnd = _selectedTextEnd(text, charOffset);
          var start = charOffset;
          final marker = markers?.markerAt(text, start);
          if (marker != null) start += marker.length;
          // Only a marker was selected; it cannot carry a reading.
          if (start >= selectedEnd) return;
          final targetText = text.substring(start, selectedEnd);
          final leftText = text.substring(0, start);
          final rightText = text.substring(selectedEnd);

          bool hasPrecedingTag =
              (start == 0 &&
              ni > 0 &&
              line.nodes[ni - 1] is LyricTimeTag &&
              (line.nodes[ni - 1] as LyricTimeTag).type != 10);
          LyricTimeTag? precedingTag;
          if (hasPrecedingTag) {
            precedingTag = line.nodes[ni - 1] as LyricTimeTag;
          }

          final rubyNodes = <LyricNode>[];
          if (precedingTag != null) rubyNodes.add(precedingTag);
          rubyNodes.add(LyricText(newRubyText));

          final ruby = LyricRuby(baseText: targetText, rubyNodes: rubyNodes);

          int startIndex = hasPrecedingTag ? ni - 1 : ni;
          int endIndex = ni + 1;

          final replacement = <LyricNode>[];
          if (leftText.isNotEmpty) replacement.add(LyricText(leftText));
          replacement.add(ruby);
          if (rightText.isNotEmpty) replacement.add(LyricText(rightText));

          line.nodes.replaceRange(startIndex, endIndex, replacement);

          int newNi = startIndex + (leftText.isNotEmpty ? 1 : 0);
          _selectionPath = [li, newNi, 0, -1, targetText.length];
        } else {
          baseText = text;
          rubyNodes.add(LyricText(newRubyText));
          line.nodes[ni] = LyricRuby(baseText: baseText, rubyNodes: rubyNodes);
        }
      }

      _syncRawText();
      notifyListeners();
      return;
    }

    final rubyNode = node;
    final tags = rubyNode.rubyNodes
        .whereType<LyricTimeTag>()
        .where((t) => t.type != 10)
        .toList();
    final tag10List = rubyNode.rubyNodes
        .whereType<LyricTimeTag>()
        .where((t) => t.type == 10)
        .toList();
    final int tagCount = tags.length;

    if (newRubyText.isNotEmpty) {
      final newNodes = _rebuildRubyNodes(tags, newRubyText);
      if (tag10List.isNotEmpty) newNodes.add(tag10List.first);
      line.nodes[ni] = LyricRuby(
        baseText: rubyNode.baseText,
        rubyNodes: newNodes,
        joinNext: rubyNode.joinNext,
      );
    } else {
      if (_isRubyUnitConnected(line, ni, rubyNode)) {
        line.nodes[ni] = LyricRuby(
          baseText: rubyNode.baseText,
          rubyNodes: [...tags, ...tag10List],
          joinNext: rubyNode.joinNext,
        );
      } else if (tagCount == 0) {
        line.nodes[ni] = LyricText(rubyNode.baseText);
      } else if (tagCount == 1) {
        final replacementNodes = <LyricNode>[];
        for (final rn in tags) {
          replacementNodes.add(LyricTimeTag(type: 1, time: rn.time));
        }
        replacementNodes.add(LyricText(rubyNode.baseText));
        line.nodes.replaceRange(ni, ni + 1, replacementNodes);
      } else {
        // Empty ruby with multiple tags doesn't really make sense, but keep tags
        line.nodes[ni] = LyricRuby(
          baseText: rubyNode.baseText,
          rubyNodes: tags + tag10List,
          joinNext: rubyNode.joinNext,
        );
      }
    }

    _syncRawText();
    notifyListeners();
  }

  int _selectedTextEnd(String text, int start) {
    final selectedLength = _selectionPath != null && _selectionPath!.length > 4
        ? _selectionPath![4]
        : 1;
    final safeLength = selectedLength < 1 ? 1 : selectedLength;
    final end = start + safeLength;
    return end > text.length ? text.length : end;
  }

  int _standaloneCheckCount(LyricTimeTag tag) {
    final type = tag.type;
    if (type == null || type == 10) return 0;
    return type.clamp(0, 7);
  }

  bool _decrementStandaloneCheck(LyricLine line, int tagIndex) {
    final tag = line.nodes[tagIndex] as LyricTimeTag;
    final count = _standaloneCheckCount(tag);
    if (count == 0) return true;
    if (count > 1) {
      tag.type = count - 1;
      return true;
    }
    if (tag.time.isNotEmpty) {
      tag.type = null;
      return true;
    }
    line.nodes.removeAt(tagIndex);
    return false;
  }

  void toggleEndTag() {
    if (!_selectionIsValid()) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];

    int endTagTargetIdx;
    if (node is LyricRuby) {
      endTagTargetIdx = _rubyChainEndIndex(line, ni) + 1;
    } else {
      endTagTargetIdx = ni + 1;
      if (node is LyricTimeTag &&
          endTagTargetIdx < line.nodes.length &&
          line.nodes[endTagTargetIdx] is LyricText) {
        endTagTargetIdx++;
      }
    }

    bool hasEndTag = false;
    if (endTagTargetIdx < line.nodes.length &&
        line.nodes[endTagTargetIdx] is LyricTimeTag &&
        (line.nodes[endTagTargetIdx] as LyricTimeTag).type == 10) {
      hasEndTag = true;
    }

    if (hasEndTag) {
      line.nodes.removeAt(endTagTargetIdx);
    } else {
      line.nodes.insert(endTagTargetIdx, LyricTimeTag(type: 10, time: ''));
    }

    _syncRawText();
    notifyListeners();
  }

  void splitSelectedNode() {
    if (!_selectionIsValid()) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];
    if (node is LyricRuby) {
      final chainEnd = _rubyChainEndIndex(line, ni);
      if (chainEnd > ni) {
        final boundaryIndex = chainEnd - 1;
        final boundary = line.nodes[boundaryIndex] as LyricRuby;
        line.nodes[boundaryIndex] = LyricRuby(
          baseText: boundary.baseText,
          rubyNodes: boundary.rubyNodes,
        );
        final selectedTextLength = line.nodes
            .sublist(ni, boundaryIndex + 1)
            .whereType<LyricRuby>()
            .fold<int>(0, (length, ruby) => length + ruby.baseText.length);
        _collapseUnadornedRubyNodes(line);
        _selectionPath = [li, ni, 0, -1, selectedTextLength];
        _syncRawText();
        notifyListeners();
        return;
      }
    }

    if (node is LyricRuby && node.joinNext) {
      line.nodes[ni] = LyricRuby(
        baseText: node.baseText,
        rubyNodes: node.rubyNodes,
      );
      _collapseUnadornedRubyNodes(line);
      _selectionPath = [li, ni, 0, -1, node.baseText.length];
      _syncRawText();
      notifyListeners();
      return;
    }

    if (node is LyricRuby && node.baseText.length > 1) {
      final replacementNodes = <LyricNode>[];

      final baseChars = node.baseText.characters.toList();
      final joinedSegments = _splitRubyNodesAtJoinMarkers(node.rubyNodes);
      if (joinedSegments != null && joinedSegments.length == baseChars.length) {
        for (int i = 0; i < baseChars.length; i++) {
          final rubyNodes = joinedSegments[i];
          replacementNodes.add(
            rubyNodes.isEmpty
                ? LyricText(baseChars[i])
                : LyricRuby(baseText: baseChars[i], rubyNodes: rubyNodes),
          );
        }
        line.nodes.replaceRange(ni, ni + 1, replacementNodes);
        _selectionPath = [li, ni, 0];
        _syncRawText();
        notifyListeners();
        return;
      }

      final tags = <LyricTimeTag>[];
      final texts = <String>[];
      for (final rn in node.rubyNodes) {
        if (rn is LyricTimeTag && rn.type != 10) {
          tags.add(rn);
        } else if (rn is LyricText) {
          texts.add(rn.text);
        }
      }
      final combinedRubyText = texts.join().replaceAll('＋', '');
      final rubyChars = combinedRubyText.characters.toList();

      int tagsPerChar = baseChars.isEmpty ? 0 : tags.length ~/ baseChars.length;
      int tagsRemainder = baseChars.isEmpty
          ? 0
          : tags.length % baseChars.length;
      int rubyPerChar = baseChars.isEmpty
          ? 0
          : rubyChars.length ~/ baseChars.length;
      int rubyRemainder = baseChars.isEmpty
          ? 0
          : rubyChars.length % baseChars.length;

      int tagIdx = 0;
      int rubyIdx = 0;

      for (int i = 0; i < baseChars.length; i++) {
        final nodeTagsCount = tagsPerChar + (i < tagsRemainder ? 1 : 0);
        final nodeRubyCount = rubyPerChar + (i < rubyRemainder ? 1 : 0);

        final nodeTags = tags.sublist(tagIdx, tagIdx + nodeTagsCount);
        final nodeRuby = rubyChars
            .sublist(rubyIdx, rubyIdx + nodeRubyCount)
            .join();

        final newRubyNodes = <LyricNode>[];
        if (nodeTags.isNotEmpty) {
          newRubyNodes.add(
            LyricTimeTag(type: nodeTags.length, time: nodeTags[0].time),
          );
          if (nodeRuby.isNotEmpty) newRubyNodes.add(LyricText(nodeRuby));
          for (int j = 1; j < nodeTags.length; j++) {
            newRubyNodes.add(LyricTimeTag(type: null, time: nodeTags[j].time));
          }
        } else {
          if (nodeRuby.isNotEmpty) newRubyNodes.add(LyricText(nodeRuby));
        }

        if (newRubyNodes.isEmpty) {
          replacementNodes.add(LyricText(baseChars[i]));
        } else {
          replacementNodes.add(
            LyricRuby(baseText: baseChars[i], rubyNodes: newRubyNodes),
          );
        }

        tagIdx += nodeTagsCount;
        rubyIdx += nodeRubyCount;
      }

      line.nodes.replaceRange(ni, ni + 1, replacementNodes);
      _syncRawText();
      notifyListeners();
    }
  }

  int _rubyChainEndIndex(LyricLine line, int startIndex) {
    var index = startIndex;
    while (index >= 0 && index < line.nodes.length) {
      final node = line.nodes[index];
      if (node is! LyricRuby || !node.joinNext) break;
      if (index + 1 >= line.nodes.length ||
          line.nodes[index + 1] is! LyricRuby) {
        break;
      }
      index++;
    }
    return index;
  }

  bool _isRubyUnitConnected(LyricLine line, int nodeIndex, LyricRuby node) {
    if (node.joinNext) return true;
    return nodeIndex > 0 &&
        line.nodes[nodeIndex - 1] is LyricRuby &&
        (line.nodes[nodeIndex - 1] as LyricRuby).joinNext;
  }

  void _collapseUnadornedRubyNodes(LyricLine line) {
    for (var index = 0; index < line.nodes.length; index++) {
      final node = line.nodes[index];
      if (node is! LyricRuby || node.joinNext || node.rubyNodes.isNotEmpty) {
        continue;
      }
      final isTailOfJoin =
          index > 0 &&
          line.nodes[index - 1] is LyricRuby &&
          (line.nodes[index - 1] as LyricRuby).joinNext;
      if (!isTailOfJoin) {
        line.nodes[index] = LyricText(node.baseText);
      }
    }
  }

  List<List<LyricNode>>? _splitRubyNodesAtJoinMarkers(
    List<LyricNode> rubyNodes,
  ) {
    final segments = <List<LyricNode>>[<LyricNode>[]];
    bool foundMarker = false;

    for (final node in rubyNodes) {
      if (node is! LyricText || !node.text.contains('＋')) {
        segments.last.add(node);
        continue;
      }

      final parts = node.text.split('＋');
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          segments.last.add(LyricText(parts[i]));
        }
        if (i < parts.length - 1) {
          foundMarker = true;
          segments.add(<LyricNode>[]);
        }
      }
    }

    return foundMarker ? segments : null;
  }

  /// Helper to properly interleave tags and characters for LyricRuby
  List<LyricNode> _rebuildRubyNodes(List<LyricTimeTag> tags, String text) {
    final chars = text.characters.toList();
    final nodes = <LyricNode>[];

    if (tags.isEmpty) {
      if (text.isNotEmpty) nodes.add(LyricText(text));
      return nodes;
    }

    int tagIdx = 0;
    int charIdx = 0;

    while (tagIdx < tags.length || charIdx < chars.length) {
      if (tagIdx < tags.length) {
        nodes.add(tags[tagIdx]);
        tagIdx++;
      }
      if (charIdx < chars.length) {
        if (tagIdx == tags.length) {
          nodes.add(LyricText(chars.sublist(charIdx).join('')));
          charIdx = chars.length;
        } else {
          nodes.add(LyricText(chars[charIdx]));
          charIdx++;
        }
      }
    }
    return nodes;
  }

  /// Splits [text] into taggable tokens. See [AutoTagger.tokenize].
  List<TextToken> tokenizeTextAdvanced(String text) =>
      AutoTagger.tokenize(text);

  // ─── Auto Ruby & Tag (Combined) ──────────────────────────────

  /// Fetches furigana for every untagged text node and then adds check tags.
  ///
  /// [onProgress] reports each batch; [isCancelled] is polled between
  /// batches. When cancelled, readings already fetched are still applied and
  /// auto-tagged, so stopping keeps the work done so far. If the document is
  /// replaced while a request is in flight, nothing is changed and
  /// [AutoRubyOutcome.documentChanged] is returned. Network and API errors
  /// are rethrown without modifying the document.
  ///
  /// Text matching [markers] (singer line-color prefixes) is never sent for
  /// a reading and never tagged, so a marker such as `結城` keeps working.
  Future<AutoRubyOutcome> autoRubyAndTagDocument({
    YahooFuriganaClient client = const YahooFuriganaClient(),
    SingerMarkers? markers,
    void Function(AutoRubyProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final document = _document;
    if (document == null) return AutoRubyOutcome.completed;
    bool cancelled() => isCancelled?.call() ?? false;

    final singerMarkers = markers ?? SingerMarkers.none;
    final jobs = <_RubyJob>[];
    final needsReading = RegExp(r'[a-zA-Z\u4E00-\u9FAF]');
    for (int li = 0; li < document.lines.length; li++) {
      final line = document.lines[li];
      for (int ni = 0; ni < line.nodes.length; ni++) {
        final node = line.nodes[ni];
        if (node is! LyricText) continue;
        final segments = singerMarkers.split(node.text);
        for (var si = 0; si < segments.length; si++) {
          final segment = segments[si];
          if (!segment.isMarker && needsReading.hasMatch(segment.text)) {
            jobs.add(_RubyJob(li, ni, si, segment.text));
          }
        }
      }
    }

    // Batch requests so each stays well below the API's input limit.
    const maxCharsPerBatch = 2000;
    final batches = <List<_RubyJob>>[];
    var currentBatch = <_RubyJob>[];
    var currentBatchChars = 0;
    for (final job in jobs) {
      if (currentBatchChars + job.text.length > maxCharsPerBatch &&
          currentBatch.isNotEmpty) {
        batches.add(currentBatch);
        currentBatch = [];
        currentBatchChars = 0;
      }
      currentBatch.add(job);
      currentBatchChars += job.text.length + 1;
    }
    if (currentBatch.isNotEmpty) batches.add(currentBatch);

    // line -> (node, segment) -> fetched nodes
    final jobResults = <int, Map<(int, int), List<LyricNode>>>{};
    var wasCancelled = false;
    for (var i = 0; i < batches.length; i++) {
      if (cancelled()) {
        wasCancelled = true;
        break;
      }
      onProgress?.call(
        AutoRubyProgress(completedBatches: i, totalBatches: batches.length),
      );
      final batch = batches[i];
      final batchResults = await client.fetchBatch(
        batch.map((job) => job.text).toList(),
      );
      // Indices in the jobs refer to the document as it was when we started.
      if (!identical(_document, document)) {
        return AutoRubyOutcome.documentChanged;
      }
      for (var j = 0; j < batch.length; j++) {
        final job = batch[j];
        (jobResults[job.lineIndex] ??= {})[(job.nodeIndex, job.segmentIndex)] =
            batchResults[j];
      }
    }
    if (!wasCancelled && cancelled()) wasCancelled = true;

    onProgress?.call(
      AutoRubyProgress(
        completedBatches: jobResults.isEmpty ? 0 : batches.length,
        totalBatches: batches.length,
        applying: true,
      ),
    );

    for (int li = 0; li < document.lines.length; li++) {
      final lineResults = jobResults[li];
      if (lineResults == null) continue;
      final line = document.lines[li];
      final newNodes = <LyricNode>[];
      for (int ni = 0; ni < line.nodes.length; ni++) {
        final node = line.nodes[ni];
        if (node is! LyricText ||
            !lineResults.keys.any((key) => key.$1 == ni)) {
          newNodes.add(node);
          continue;
        }
        final segments = singerMarkers.split(node.text);
        for (var si = 0; si < segments.length; si++) {
          final segment = segments[si];
          final rubyNodes = lineResults[(ni, si)];
          if (rubyNodes == null ||
              rubyNodes.isEmpty ||
              _rubyResultSurface(rubyNodes) != segment.text) {
            newNodes.add(LyricText(segment.text));
            continue;
          }
          // Move a timed check that precedes the word onto its first ruby.
          if ((rubyNodes.first, newNodes.lastOrNull) case (
            LyricRuby ruby,
            LyricTimeTag(type: final type, time: final time),
          ) when type != 10 && time.isNotEmpty) {
            final start = ruby.rubyNodes.first as LyricTimeTag;
            ruby.rubyNodes[0] = LyricTimeTag(type: start.type, time: time);
            newNodes.removeLast();
          }
          newNodes.addAll(rubyNodes);
        }
      }
      line.nodes
        ..clear()
        ..addAll(newNodes);
    }

    if (wasCancelled) {
      // Only tag lines whose readings all arrived. Tagging the rest would
      // split their kanji into per-character checks and spoil a later retry.
      final jobCounts = <int, int>{};
      for (final job in jobs) {
        jobCounts[job.lineIndex] = (jobCounts[job.lineIndex] ?? 0) + 1;
      }
      AutoTagger.tagLines([
        for (final MapEntry(key: li, value: results) in jobResults.entries)
          if (results.length == jobCounts[li]) document.lines[li],
      ], markers: singerMarkers);
    } else {
      AutoTagger.tagLines(document.lines, markers: singerMarkers);
    }

    _syncRawText();
    _rebuildSlotList();
    notifyListeners();
    return wasCancelled ? AutoRubyOutcome.cancelled : AutoRubyOutcome.completed;
  }

  String _rubyResultSurface(List<LyricNode> nodes) => nodes.map((node) {
    return switch (node) {
      LyricRuby() => node.baseText,
      LyricText() => node.text,
      _ => '',
    };
  }).join();
}

/// One lyric (non-marker) segment of a text node that needs a reading.
class _RubyJob {
  final int lineIndex;
  final int nodeIndex;
  final int segmentIndex;
  final String text;
  _RubyJob(this.lineIndex, this.nodeIndex, this.segmentIndex, this.text);
}
