import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/lyric_ast.dart';
import '../parser/lrc_parser.dart';

class TextToken {
  final String text;
  final bool addTag10;
  TextToken(this.text, this.addTag10);
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

  void loadLrcText(String text) {
    final cleanText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    _rawText = cleanText;
    _selectionPath = null;
    _activeCursor = null;
    try {
      _document = LrcParser.parseDocument(cleanText);
      _rebuildSlotList();
    } catch (e) {
      debugPrint('LRC Parse Error: $e');
    }
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

    for (var index = lineIndex; index >= 0; index--) {
      final plainText = index == lineIndex
          ? _plainTextBeforeSelection(_document!.lines[index])
          : _plainText(_document!.lines[index]);
      String? match;
      var matchOffset = -1;
      for (final candidate in candidates) {
        final offset = plainText.lastIndexOf(candidate);
        if (offset > matchOffset) {
          match = candidate;
          matchOffset = offset;
        }
      }
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

  void updateRubyText(String newRubyText) {
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
          final targetText = text.substring(charOffset, selectedEnd);
          final leftText = text.substring(0, charOffset);
          final rightText = text.substring(selectedEnd);

          bool hasPrecedingTag =
              (charOffset == 0 &&
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

  // ─── Auto Tagging ──────────────────────────────────────────────

  void _runAutoTagOnNewNodes(List<LyricLine> lines) {
    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];

      // Pass 1: Insert [10] at spaces if surrounded by non-English
      final preprocessedNodes = _insertTag10AtSpaces(line.nodes);

      final newNodes = <LyricNode>[];

      for (int ni = 0; ni < preprocessedNodes.length; ni++) {
        final node = preprocessedNodes[ni];

        if (node is LyricRuby) {
          bool hasTags = node.rubyNodes.any(
            (rn) => rn is LyricTimeTag && rn.type != 10,
          );
          if (!hasTags) {
            LyricTimeTag? precedingTag;
            if (newNodes.isNotEmpty &&
                newNodes.last is LyricTimeTag &&
                (newNodes.last as LyricTimeTag).type != 10) {
              precedingTag = newNodes.removeLast() as LyricTimeTag;
            }

            final newRubyNodes = <LyricNode>[
              precedingTag ?? LyricTimeTag(type: 1, time: ''),
              ...node.rubyNodes,
            ];
            newNodes.add(
              LyricRuby(
                baseText: node.baseText,
                rubyNodes: newRubyNodes,
                joinNext: node.joinNext,
              ),
            );
          } else {
            // Even if it has tags, if there is a redundant empty tag right before it, absorb or discard it
            if (newNodes.isNotEmpty && newNodes.last is LyricTimeTag) {
              final lastTag = newNodes.last as LyricTimeTag;
              if (lastTag.type != 10 && lastTag.time.isEmpty) {
                newNodes.removeLast();
              }
            }
            newNodes.add(node);
          }
        } else if (node is LyricText) {
          bool isCovered =
              newNodes.isNotEmpty &&
              newNodes.last is LyricTimeTag &&
              (newNodes.last as LyricTimeTag).type != 10;

          final tokens = tokenizeTextAdvanced(node.text);
          for (int i = 0; i < tokens.length; i++) {
            final token = tokens[i];

            // Do not add tag for purely whitespace or punctuation tokens
            bool hasReadableText = RegExp(
              r'[a-zA-Z0-9\uFF10-\uFF19\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF\u3400-\u4DBF]',
            ).hasMatch(token.text);
            if (!hasReadableText) {
              newNodes.add(LyricText(token.text));
              if (token.addTag10) {
                newNodes.add(LyricTimeTag(type: 10, time: ''));
              }
              continue;
            }

            if (i == 0 && isCovered) {
              newNodes.add(LyricText(token.text));
            } else {
              newNodes.add(LyricTimeTag(type: 1, time: ''));
              newNodes.add(LyricText(token.text));
            }
            if (token.addTag10) {
              newNodes.add(LyricTimeTag(type: 10, time: ''));
            }
          }
        } else {
          newNodes.add(node);
        }
      }

      if (newNodes.isNotEmpty) {
        bool alreadyHasEndTag =
            newNodes.last is LyricTimeTag &&
            (newNodes.last as LyricTimeTag).type == 10;

        // Only add line-end [10] if the line contains actual non-whitespace text
        bool hasContent = newNodes.any(
          (n) => n is LyricRuby || (n is LyricText && n.text.trim().isNotEmpty),
        );
        if (hasContent && !alreadyHasEndTag) {
          newNodes.add(LyricTimeTag(type: 10, time: ''));
        }
      }

      final mergedNodes = <LyricNode>[];
      for (final n in newNodes) {
        if (mergedNodes.isNotEmpty &&
            mergedNodes.last is LyricText &&
            n is LyricText) {
          final lastText = mergedNodes.removeLast() as LyricText;
          mergedNodes.add(LyricText(lastText.text + n.text));
        } else {
          mergedNodes.add(n);
        }
      }

      line.nodes.clear();
      line.nodes.addAll(mergedNodes);
    }
  }

  List<LyricNode> _insertTag10AtSpaces(List<LyricNode> inputNodes) {
    final List<LyricNode> splitNodes = [];
    final spaceRegex = RegExp(r'[ \u3000]+');

    for (final node in inputNodes) {
      if (node is LyricText) {
        final text = node.text;
        int lastIndex = 0;
        for (final match in spaceRegex.allMatches(text)) {
          if (match.start > lastIndex) {
            splitNodes.add(LyricText(text.substring(lastIndex, match.start)));
          }
          splitNodes.add(LyricText(match.group(0)!));
          lastIndex = match.end;
        }
        if (lastIndex < text.length) {
          splitNodes.add(LyricText(text.substring(lastIndex)));
        }
      } else {
        splitNodes.add(node);
      }
    }

    final List<LyricNode> result = [];
    final asciiRegex = RegExp(r'[a-zA-Z]');

    for (int i = 0; i < splitNodes.length; i++) {
      final node = splitNodes[i];
      if (node is LyricText && spaceRegex.hasMatch(node.text)) {
        String? prevChar;
        for (int j = result.length - 1; j >= 0; j--) {
          final pNode = result[j];
          if (pNode is LyricText && pNode.text.trim().isNotEmpty) {
            prevChar = pNode.text.characters.last;
            break;
          } else if (pNode is LyricRuby && pNode.baseText.isNotEmpty) {
            prevChar = pNode.baseText.characters.last;
            break;
          }
        }

        String? nextChar;
        for (int j = i + 1; j < splitNodes.length; j++) {
          final nNode = splitNodes[j];
          if (nNode is LyricText && nNode.text.trim().isNotEmpty) {
            nextChar = nNode.text.characters.first;
            break;
          } else if (nNode is LyricRuby && nNode.baseText.isNotEmpty) {
            nextChar = nNode.baseText.characters.first;
            break;
          }
        }

        bool prevIsAscii = prevChar != null && asciiRegex.hasMatch(prevChar);
        bool nextIsAscii = nextChar != null && asciiRegex.hasMatch(nextChar);

        if (prevChar != null &&
            nextChar != null &&
            !prevIsAscii &&
            !nextIsAscii) {
          bool alreadyHas10 =
              result.isNotEmpty &&
              result.last is LyricTimeTag &&
              (result.last as LyricTimeTag).type == 10;
          if (!alreadyHas10) {
            result.add(LyricTimeTag(type: 10, time: ''));
          }
        }

        result.add(node);
      } else {
        result.add(node);
      }
    }

    return result;
  }

  List<TextToken> tokenizeTextAdvanced(String text) {
    if (text.isEmpty) return [];

    final units = text.characters.toList();
    final tokens = <TextToken>[];
    final buffer = StringBuffer();

    final RegExp asciiRegex = RegExp(r'[a-zA-Z0-9\uFF21-\uFF3A\uFF41-\uFF5A]');
    final RegExp fullWidthDigitRegex = RegExp(r'[\uFF10-\uFF19]');
    final RegExp cjkRegex = RegExp(
      r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF\u3400-\u4DBF]',
    );
    final RegExp punctRegex = RegExp(
      r'[、。！？，．：；（）「」『』〜ー…\s\u3000-\u303F\uFF00-\uFF0F\uFF1A-\uFF20\uFF3B-\uFF40\uFF5B-\uFF65]',
    );
    bool isCjk(String value) {
      if (cjkRegex.hasMatch(value)) return true;
      final rune = value.runes.first;
      return (rune >= 0x20000 && rune <= 0x3FFFF);
    }

    int i = 0;
    while (i < units.length) {
      final char = units[i];
      if (fullWidthDigitRegex.hasMatch(char)) {
        tokens.add(TextToken(char, false));
        i++;
      } else if (asciiRegex.hasMatch(char)) {
        buffer.write(char);
        i++;
        while (i < units.length &&
            asciiRegex.hasMatch(units[i]) &&
            !fullWidthDigitRegex.hasMatch(units[i])) {
          buffer.write(units[i]);
          i++;
        }
        while (i < units.length &&
            (punctRegex.hasMatch(units[i]) ||
                (!asciiRegex.hasMatch(units[i]) &&
                    !isCjk(units[i]) &&
                    !fullWidthDigitRegex.hasMatch(units[i])))) {
          buffer.write(units[i]);
          i++;
        }
        tokens.add(TextToken(buffer.toString(), false));
        buffer.clear();
      } else if (isCjk(char)) {
        buffer.write(char);
        i++;

        final smallKanaRegex = RegExp(r'[ぁぃぅぇぉっゃゅょァィゥェォッャュョー゛]');
        while (i < units.length && smallKanaRegex.hasMatch(units[i])) {
          buffer.write(units[i]);
          i++;
        }

        while (i < units.length &&
            (punctRegex.hasMatch(units[i]) ||
                (!asciiRegex.hasMatch(units[i]) &&
                    !isCjk(units[i]) &&
                    !fullWidthDigitRegex.hasMatch(units[i])))) {
          buffer.write(units[i]);
          i++;
        }

        tokens.add(TextToken(buffer.toString(), false));
        buffer.clear();
      } else {
        buffer.write(char);
        i++;
      }
    }

    if (buffer.isNotEmpty) {
      if (tokens.isNotEmpty) {
        final last = tokens.removeLast();
        tokens.add(TextToken(last.text + buffer.toString(), false));
      } else {
        tokens.add(TextToken(buffer.toString(), false));
      }
    }

    return tokens;
  }

  // ─── Auto Ruby & Tag (Combined) ──────────────────────────────

  static String yahooAppId = const String.fromEnvironment(
    'YAHOO_API_KEY',
    defaultValue:
        'dmVyPTIwMjUwNyZpZD16dUUwckt6Z0lJJmhhc2g9T0dWaFlqWmtNV1kyWWpFM01tVTRZZw', // Fallback for now so the app still works for the user
  );
  bool _autoRubyCancelled = false;

  Future<void> autoRubyAndTagDocument(BuildContext context) async {
    if (_document == null) return;
    final l10n = context.l10n;
    _autoRubyCancelled = false;

    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>(l10n.preparing);

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.autoRubyAndChecks),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, progress, child) =>
                    LinearProgressIndicator(value: progress),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (context, status, child) =>
                    Text(status, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _autoRubyCancelled = true;
              },
              child: Text(l10n.stop),
            ),
          ],
        );
      },
    );

    final jobs = <_RubyJob>[];
    for (int li = 0; li < _document!.lines.length; li++) {
      final line = _document!.lines[li];
      for (int ni = 0; ni < line.nodes.length; ni++) {
        final node = line.nodes[ni];
        if (node is LyricText) {
          final hasKanjiOrEng = RegExp(
            r'[a-zA-Z\u4E00-\u9FAF]',
          ).hasMatch(node.text);
          if (hasKanjiOrEng) {
            jobs.add(_RubyJob(li, ni, node));
          }
        }
      }
    }

    // Process jobs in batches
    final jobResults = <int, Map<int, List<LyricNode>>>{};
    const maxCharsPerBatch = 2000;
    List<_RubyJob> currentBatch = [];
    int currentBatchChars = 0;

    final batches = <List<_RubyJob>>[];
    for (var job in jobs) {
      if (currentBatchChars + job.node.text.length > maxCharsPerBatch &&
          currentBatch.isNotEmpty) {
        batches.add(currentBatch);
        currentBatch = [];
        currentBatchChars = 0;
      }
      currentBatch.add(job);
      currentBatchChars += job.node.text.length + 1;
    }
    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }

    int completedBatches = 0;
    for (var batch in batches) {
      if (_autoRubyCancelled) break;

      progressNotifier.value = completedBatches / batches.length;
      statusNotifier.value = l10n.fetchingRubyProgress(
        completedBatches + 1,
        batches.length,
      );

      final texts = batch.map((j) => j.node.text).toList();
      late final List<List<LyricNode>> batchResults;
      try {
        batchResults = await _fetchRubyBatch(texts);
      } catch (error) {
        debugPrint('Yahoo API Error: $error');
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
        progressNotifier.dispose();
        statusNotifier.dispose();
        return;
      }

      for (int i = 0; i < batch.length; i++) {
        final job = batch[i];
        jobResults.putIfAbsent(job.lineIndex, () => {});
        jobResults[job.lineIndex]![job.nodeIndex] = batchResults[i];
      }

      completedBatches++;
    }

    if (!_autoRubyCancelled) {
      progressNotifier.value = 1.0;
      statusNotifier.value = l10n.updatingLyrics;

      for (int li = 0; li < _document!.lines.length; li++) {
        final line = _document!.lines[li];
        final newNodes = <LyricNode>[];
        for (int ni = 0; ni < line.nodes.length; ni++) {
          final node = line.nodes[ni];
          if (jobResults.containsKey(li) && jobResults[li]!.containsKey(ni)) {
            final rubyNodes = jobResults[li]![ni];
            if (rubyNodes != null && rubyNodes.isNotEmpty) {
              newNodes.addAll(rubyNodes);
            } else {
              newNodes.add(node);
            }
          } else {
            newNodes.add(node);
          }
        }
        line.nodes.clear();
        line.nodes.addAll(newNodes);
      }
    }

    // Apply auto-tagging (even on partial results if cancelled)
    _runAutoTagOnNewNodes(_document!.lines);

    _syncRawText();
    _rebuildSlotList();
    notifyListeners();

    // Close progress dialog
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _autoRubyCancelled
                ? l10n.autoRubyCancelled
                : l10n.autoRubyCompleted,
          ),
        ),
      );
    }

    progressNotifier.dispose();
    statusNotifier.dispose();
  }

  /// Splits furigana into mora units, merging small kana, long vowel marks,
  /// and dakuten with the preceding mora.
  /// Based on RhythmicaLyrics SakuraYomiBunkai (routin_func.hsp:7077).
  List<String> _splitIntoMorae(String furigana) {
    final result = <String>[];
    final smallKana = RegExp(r'[ぁぃぅぇぉっゃゅょァィゥェォッャュョ]');
    final longVoiced = RegExp(r'[ー゛]');

    for (final ch in furigana.characters) {
      if (result.isNotEmpty &&
          (smallKana.hasMatch(ch) || longVoiced.hasMatch(ch))) {
        result.last += ch; // merge into preceding mora
      } else {
        result.add(ch);
      }
    }
    return result;
  }

  int _calculateTagCount(String surface, String furigana) {
    if (RegExp(r'^[a-zA-Z0-9]+$').hasMatch(surface)) return 1;
    return _splitIntoMorae(furigana).length;
  }

  /// Expands ruby nodes into interleaved [tag][text][tag][text]... structure.
  /// Based on RhythmicaLyrics SakuraYomiBunkai decomposition.
  List<LyricNode> _expandRubyNodes(int type, String surface, String furigana) {
    final morae = _splitIntoMorae(furigana);
    if (type <= 1 || morae.length <= 1) {
      return [LyricTimeTag(type: type, time: ''), LyricText(furigana)];
    }
    final expanded = <LyricNode>[];
    expanded.add(
      LyricTimeTag(type: type, time: ''),
    ); // first tag carries the type
    for (int i = 0; i < morae.length; i++) {
      expanded.add(LyricText(morae[i]));
      if (i < morae.length - 1) {
        expanded.add(LyricTimeTag(type: null, time: ''));
      }
    }
    return expanded;
  }

  Future<List<List<LyricNode>>> _fetchRubyBatch(List<String> texts) async {
    final joinedText = texts.join('\n');
    final url = Uri.parse(
      'https://jlp.yahooapis.jp/FuriganaService/V2/furigana',
    );
    final requestBody = {
      "id": "yuukilyrics",
      "jsonrpc": "2.0",
      "method": "jlp.furiganaservice.furigana",
      "params": {"q": joinedText, "grade": 1},
    };

    final response = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'Yahoo AppID: $yahooAppId',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid Yahoo API response.');
      }
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) {
        throw const FormatException('Yahoo API result is missing.');
      }
      final wordsValue = result['word'];
      if (wordsValue is! List) {
        throw const FormatException('Yahoo API word list is missing.');
      }
      final words = wordsValue;

      final processedWords = <Map<String, dynamic>>[];
      final smallKanaRegex = RegExp(r'^[ぁぃぅぇぉっゃゅょァィゥェォッャュョー゛]+');

      for (final value in words) {
        if (value is! Map) {
          throw const FormatException('Invalid Yahoo API word entry.');
        }
        final surfaceValue = value['surface'];
        final furiganaValue = value['furigana'];
        if (surfaceValue is! String ||
            (furiganaValue != null && furiganaValue is! String)) {
          throw const FormatException('Invalid Yahoo API word fields.');
        }
        final surface = surfaceValue;
        final furigana = furiganaValue as String?;
        final subword = value['subword'];

        final match = smallKanaRegex.firstMatch(surface);
        if (match != null && processedWords.isNotEmpty) {
          final kana = match.group(0)!;
          final prev = processedWords.last;

          prev['surface'] = (prev['surface'] as String) + kana;
          if (prev['furigana'] != null) {
            prev['furigana'] = (prev['furigana'] as String) + kana;
          }

          final remainder = surface.substring(kana.length);
          if (remainder.isNotEmpty) {
            final remainingFurigana =
                furigana != null && furigana.startsWith(kana)
                ? furigana.substring(kana.length)
                : furigana;
            processedWords.add({
              'surface': remainder,
              'furigana': remainingFurigana,
              'subword': subword,
            });
          }
        } else {
          processedWords.add({
            'surface': surface,
            'furigana': furigana,
            'subword': subword,
          });
        }
      }

      final batchResults = <List<LyricNode>>[];
      var currentNodes = <LyricNode>[];

      for (var w in processedWords) {
        final surface = w['surface'] as String;
        final furigana = w['furigana'] as String?;
        final subword = w['subword'];

        if (surface.contains('\n')) {
          final parts = surface.split('\n');
          for (int i = 0; i < parts.length; i++) {
            final part = parts[i];
            if (part.isNotEmpty) {
              currentNodes.add(LyricText(part));
            }
            if (i < parts.length - 1) {
              batchResults.add(currentNodes);
              currentNodes = [];
            }
          }
        } else {
          if (subword != null &&
              subword is List &&
              furigana != null &&
              furigana != surface) {
            final int type = _calculateTagCount(surface, furigana);
            currentNodes.add(
              LyricRuby(
                baseText: surface,
                rubyNodes: _expandRubyNodes(type, surface, furigana),
              ),
            );
          } else if (furigana != null && furigana != surface) {
            final int type = _calculateTagCount(surface, furigana);
            currentNodes.add(
              LyricRuby(
                baseText: surface,
                rubyNodes: _expandRubyNodes(type, surface, furigana),
              ),
            );
          } else {
            currentNodes.add(LyricText(surface));
          }
        }
      }
      batchResults.add(currentNodes);
      if (batchResults.length != texts.length) {
        throw FormatException(
          'Yahoo API returned ${batchResults.length} lines for '
          '${texts.length} inputs.',
        );
      }
      return batchResults;
    }
    throw HttpException(
      'Yahoo API request failed with status ${response.statusCode}.',
      uri: url,
    );
  }
}

class _RubyJob {
  final int lineIndex;
  final int nodeIndex;
  final LyricText node;
  _RubyJob(this.lineIndex, this.nodeIndex, this.node);
}
