import 'package:flutter/material.dart';
import 'dart:convert';
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
  String? parseError;

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
            final ms = (current.inMilliseconds + offsetMs).clamp(0, double.maxFinite.toInt());
            node.time = LyricTimeTag.formatDuration(Duration(milliseconds: ms));
          }
        } else if (node is LyricRuby) {
          for (final rn in node.rubyNodes) {
            if (rn is LyricTimeTag && rn.time.isNotEmpty) {
              final current = LyricTimeTag.parseDuration(rn.time);
              if (current != null) {
                final ms = (current.inMilliseconds + offsetMs).clamp(0, double.maxFinite.toInt());
                rn.time = LyricTimeTag.formatDuration(Duration(milliseconds: ms));
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
      if (_globalTimeShiftBaseTime != null && _globalTimeShiftTargetTime != null) {
        final offset = _globalTimeShiftTargetTime!.inMilliseconds - _globalTimeShiftBaseTime!.inMilliseconds;
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
  ]) {
    _selectionPath = [lineIndex, nodeIndex, charOffset, tagNodeIndex ?? -1];

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
    if (_document == null || _selectionPath == null) return null;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    if (li < _document!.lines.length) {
      final nodes = _document!.lines[li].nodes;
      if (ni < nodes.length) return nodes[ni];
    }
    return null;
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
          int slotIdx = 0;
          for (final rn in node.rubyNodes) {
            if (rn is LyricTimeTag && rn.type != 10) {
              _allSlots.add(
                TaggingSlot(
                  lineIndex: li,
                  nodeIndex: ni,
                  slotIndex: slotIdx++,
                  isRuby: true,
                ),
              );
            }
          }
        } else if (node is LyricTimeTag && node.type != 10) {
          _allSlots.add(
            TaggingSlot(
              lineIndex: li,
              nodeIndex: ni,
              slotIndex: 0,
              isRuby: false,
            ),
          );
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

  void recordTimestamp(Duration position, {bool advance = true}) {
    if (_document == null || _activeCursor == null) return;
    final slot = _activeCursor!;
    final adjusted = _applyOffset(position);
    final timeStr = LyricTimeTag.formatDuration(adjusted);
    final line = _document!.lines[slot.lineIndex];

    if (slot.isRuby) {
      final ruby = line.nodes[slot.nodeIndex] as LyricRuby;
      int tagCount = 0;
      for (final rn in ruby.rubyNodes) {
        if (rn is LyricTimeTag && rn.type != 10) {
          if (tagCount == slot.slotIndex) {
            rn.time = timeStr;
            break;
          }
          tagCount++;
        }
      }
    } else {
      final tag = line.nodes[slot.nodeIndex];
      if (tag is LyricTimeTag) {
        tag.time = timeStr;
      }
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

    // Determine where to insert the Tag-10
    int insertAfter;
    if (slot.isRuby) {
      final ruby = line.nodes[slot.nodeIndex] as LyricRuby;
      int totalTags = ruby.rubyNodes
          .where((rn) => rn is LyricTimeTag && rn.type != 10)
          .length;
      if (slot.slotIndex == totalTags - 1) {
        insertAfter = slot.nodeIndex; // after the LyricRuby
      } else {
        insertAfter = -1; // Not at the end of the ruby block
      }
    } else {
      insertAfter = slot.nodeIndex + 1;
      while (insertAfter < line.nodes.length && line.nodes[insertAfter] is LyricText) {
        insertAfter++;
      }
      insertAfter--; // Step back to the last LyricText
      if (insertAfter < slot.nodeIndex) {
        insertAfter = slot.nodeIndex; // fallback
      }
    }

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

  // ─── Cursor Count Manipulation ─────────────────────────────────

  void addCursorToSelected() {
    if (_document == null || _selectionPath == null) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];

    if (node is LyricRuby) {
      final rubyNode = node;
      final tags = rubyNode.rubyNodes
          .whereType<LyricTimeTag>()
          .where((t) => t.type != 10)
          .toList();
      final tag10List = rubyNode.rubyNodes
          .whereType<LyricTimeTag>()
          .where((t) => t.type == 10)
          .toList();

      final textBuf = StringBuffer();
      for (final rn in rubyNode.rubyNodes) {
        if (rn is LyricText) textBuf.write(rn.text);
      }
      final rubyText = textBuf.toString();

      tags.add(LyricTimeTag(type: null, time: ''));

      if (tags.isNotEmpty) {
        tags[0] = LyricTimeTag(type: tags.length, time: tags[0].time);
      }
      for (int i = 1; i < tags.length; i++) {
        tags[i] = LyricTimeTag(type: null, time: tags[i].time);
      }

      final newNodes = _rebuildRubyNodes(tags, rubyText);
      if (tag10List.isNotEmpty) newNodes.add(tag10List.first);

      line.nodes[ni] = LyricRuby(
        baseText: rubyNode.baseText,
        rubyNodes: newNodes,
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
          final targetChar = text[0];
          final rightText = text.substring(1);

          final rubyNodes = <LyricNode>[
            LyricTimeTag(type: 2, time: precedingNode.time),
            LyricTimeTag(type: null, time: ''),
            LyricText(''),
          ];

          final newRuby = LyricRuby(baseText: targetChar, rubyNodes: rubyNodes);

          final replacement = <LyricNode>[newRuby];
          if (rightText.isNotEmpty) replacement.add(LyricText(rightText));

          // tagNodeIndex could be separated by spaces? Usually they are adjacent.
          line.nodes.replaceRange(tagNodeIndex, ni + 1, replacement);
          _selectionPath = [li, tagNodeIndex, 0, tagNodeIndex];
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
      final rubyNodes = <LyricNode>[];
      String baseText = '';
      int removeCount = 1;

      rubyNodes.add(LyricTimeTag(type: 2, time: node.time));
      if (ni + 1 < line.nodes.length && line.nodes[ni + 1] is LyricText) {
        final textNode = line.nodes[ni + 1] as LyricText;
        if (textNode.text.isNotEmpty) {
          baseText = textNode.text[0];
          final rightText = textNode.text.substring(1);
          if (rightText.isNotEmpty) {
            line.nodes[ni + 1] = LyricText(rightText);
          } else {
            removeCount = 2;
          }
        }
      } else {
        return;
      }

      rubyNodes.add(LyricTimeTag(type: null, time: ''));
      rubyNodes.add(LyricText(''));
      final newRuby = LyricRuby(baseText: baseText, rubyNodes: rubyNodes);

      if (removeCount == 2) {
        line.nodes.replaceRange(ni, ni + 2, [newRuby]);
      } else {
        line.nodes[ni] = newRuby;
      }
      _selectionPath = [li, ni, 0, ni];

      _syncRawText();
      notifyListeners();
      return;
    }
  }

  void removeCursorFromSelected() {
    if (_document == null || _selectionPath == null) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];
    if (node is LyricRuby) {
      final tags = node.rubyNodes
          .whereType<LyricTimeTag>()
          .where((t) => t.type != 10)
          .toList();
      final tag10List = node.rubyNodes
          .whereType<LyricTimeTag>()
          .where((t) => t.type == 10)
          .toList();

      final textBuf = StringBuffer();
      for (final rn in node.rubyNodes) {
        if (rn is LyricText) textBuf.write(rn.text);
      }
      final rubyText = textBuf.toString();

      if (tags.isNotEmpty) {
        tags.removeLast();
        if (tags.isNotEmpty) {
          tags[0] = LyricTimeTag(type: tags.length, time: tags[0].time);
          for (int i = 1; i < tags.length; i++) {
            tags[i] = LyricTimeTag(type: null, time: tags[i].time);
          }
        }

        final newNodes = _rebuildRubyNodes(tags, rubyText);
        if (tag10List.isNotEmpty) newNodes.add(tag10List.first);

        line.nodes[ni] = LyricRuby(
          baseText: node.baseText,
          rubyNodes: newNodes,
        );
        _selectionPath = [li, ni, 0, -1];
      }
    } else if (node is LyricTimeTag && node.type != 10) {
      line.nodes.removeAt(ni);
      _selectionPath = null;
    } else if (node is LyricText) {
      final tagNodeIndex = _selectionPath!.length > 3 ? _selectionPath![3] : -1;
      if (tagNodeIndex != -1 &&
          tagNodeIndex < line.nodes.length &&
          line.nodes[tagNodeIndex] is LyricTimeTag) {
        line.nodes.removeAt(tagNodeIndex);
        _selectionPath = null;
      }
    }

    _syncRawText();
    notifyListeners();
  }

  /// Merges the selected Ruby node with the next unit (Ruby or Text).
  void mergeSelectedWithNext() {
    if (_document == null || _selectionPath == null) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];

    if (ni >= line.nodes.length - 1) return;

    final current = line.nodes[ni];

    LyricRuby currentRuby;
    int currentEndIdx = ni;
    if (current is LyricRuby) {
      currentRuby = current;
    } else {
      final rubyNodes = <LyricNode>[];
      String baseText = '';
      if (current is LyricTimeTag) {
        if (current.type == 10) return;
        rubyNodes.add(current);
        if (ni + 1 < line.nodes.length && line.nodes[ni + 1] is LyricText) {
          baseText = (line.nodes[ni + 1] as LyricText).text;
          currentEndIdx = ni + 1;
        }
      } else if (current is LyricText) {
        baseText = current.text;
      } else {
        return;
      }
      currentRuby = LyricRuby(baseText: baseText, rubyNodes: rubyNodes);
    }

    int nextNi = currentEndIdx + 1;
    while (nextNi < line.nodes.length &&
        line.nodes[nextNi] is LyricTimeTag &&
        (line.nodes[nextNi] as LyricTimeTag).type == 10) {
      nextNi++;
    }
    if (nextNi >= line.nodes.length) return;

    final nextNode = line.nodes[nextNi];
    LyricRuby nextRuby;
    int nextEndIdx = nextNi;

    if (nextNode is LyricRuby) {
      nextRuby = nextNode;
    } else {
      final rubyNodes = <LyricNode>[];
      String baseText = '';
      if (nextNode is LyricTimeTag) {
        if (nextNode.type != 10) {
          rubyNodes.add(nextNode);
        }
        if (nextNi + 1 < line.nodes.length &&
            line.nodes[nextNi + 1] is LyricText) {
          baseText = (line.nodes[nextNi + 1] as LyricText).text;
          nextEndIdx = nextNi + 1;
        }
      } else if (nextNode is LyricText) {
        baseText = nextNode.text;
      }
      nextRuby = LyricRuby(baseText: baseText, rubyNodes: rubyNodes);
    }

    final mergedBase = currentRuby.baseText + nextRuby.baseText;
    final mergedRubyNodes = <LyricNode>[...currentRuby.rubyNodes];

    mergedRubyNodes.removeWhere((rn) => rn is LyricTimeTag && rn.type == 10);

    mergedRubyNodes.add(LyricText('＋'));
    mergedRubyNodes.addAll(nextRuby.rubyNodes);

    line.nodes[ni] = LyricRuby(
      baseText: mergedBase,
      rubyNodes: mergedRubyNodes,
    );
    line.nodes.removeRange(ni + 1, nextEndIdx + 1);

    _syncRawText();
    notifyListeners();
  }

  void updateRubyText(String newRubyText) {
    if (_document == null || _selectionPath == null) return;
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
          final targetChar = text[charOffset];
          final leftText = text.substring(0, charOffset);
          final rightText = text.substring(charOffset + 1);

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

          final ruby = LyricRuby(baseText: targetChar, rubyNodes: rubyNodes);

          int startIndex = hasPrecedingTag ? ni - 1 : ni;
          int endIndex = ni + 1;

          final replacement = <LyricNode>[];
          if (leftText.isNotEmpty) replacement.add(LyricText(leftText));
          replacement.add(ruby);
          if (rightText.isNotEmpty) replacement.add(LyricText(rightText));

          line.nodes.replaceRange(startIndex, endIndex, replacement);

          int newNi = startIndex + (leftText.isNotEmpty ? 1 : 0);
          _selectionPath = [li, newNi, 0];
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
      );
    } else {
      if (tagCount == 0) {
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
        );
      }
    }

    _syncRawText();
    notifyListeners();
  }

  void toggleEndTag() {
    if (_document == null || _selectionPath == null) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];

    int endTagTargetIdx;
    if (node is LyricRuby) {
      endTagTargetIdx = ni + 1;
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

  void linkRubySegments() {
    if (_document == null || _selectionPath == null) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];
    if (node is LyricRuby) {
      int tagCount = 0;
      final newRubyNodes = <LyricNode>[];
      for (final rn in node.rubyNodes) {
        if (rn is LyricTimeTag && rn.type != 10) {
          tagCount++;
          if (tagCount > 1) {
            newRubyNodes.add(LyricTimeTag(type: null, time: rn.time));
          } else {
            newRubyNodes.add(rn);
          }
        } else if (rn is LyricText) {
          newRubyNodes.add(rn);
        } else {
          newRubyNodes.add(rn);
        }
      }

      for (int i = 0; i < newRubyNodes.length; i++) {
        final rn = newRubyNodes[i];
        if (rn is LyricTimeTag && rn.type != 10) {
          newRubyNodes[i] = LyricTimeTag(type: tagCount, time: rn.time);
          break;
        }
      }

      line.nodes[ni] = LyricRuby(
        baseText: node.baseText,
        rubyNodes: newRubyNodes,
      );
      _syncRawText();
      notifyListeners();
    }
  }

  void splitSelectedNode() {
    if (_document == null || _selectionPath == null) return;
    final li = _selectionPath![0];
    final ni = _selectionPath![1];
    final line = _document!.lines[li];
    if (ni >= line.nodes.length) return;

    final node = line.nodes[ni];
    if (node is LyricRuby && node.baseText.length > 1) {
      final replacementNodes = <LyricNode>[];

      final baseChars = node.baseText.characters.toList();
      final tags = <LyricTimeTag>[];
      final texts = <String>[];
      for (final rn in node.rubyNodes) {
        if (rn is LyricTimeTag && rn.type != 10) {
          tags.add(rn);
        } else if (rn is LyricText) {
          texts.add(rn.text);
        }
      }
      final combinedRubyText = texts.join();
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

  /// Helper to properly interleave tags and characters for LyricRuby
  List<LyricNode> _rebuildRubyNodes(List<LyricTimeTag> tags, String text) {
    final chars = text.split('');
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
              LyricRuby(baseText: node.baseText, rubyNodes: newRubyNodes),
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
              r'[a-zA-Z0-9\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF\u3400-\u4DBF]',
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
            prevChar = pNode.text[pNode.text.length - 1];
            break;
          } else if (pNode is LyricRuby) {
            prevChar = pNode.baseText[pNode.baseText.length - 1];
            break;
          }
        }

        String? nextChar;
        for (int j = i + 1; j < splitNodes.length; j++) {
          final nNode = splitNodes[j];
          if (nNode is LyricText && nNode.text.trim().isNotEmpty) {
            nextChar = nNode.text[0];
            break;
          } else if (nNode is LyricRuby) {
            nextChar = nNode.baseText[0];
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

    final tokens = <TextToken>[];
    final buffer = StringBuffer();

    final RegExp asciiRegex = RegExp(
      r'[a-zA-Z0-9\uFF21-\uFF3A\uFF41-\uFF5A\uFF10-\uFF19]',
    );
    final RegExp cjkRegex = RegExp(
      r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF\u3400-\u4DBF]',
    );
    final RegExp punctRegex = RegExp(
      r'[、。！？，．：；（）「」『』〜ー…\s\u3000-\u303F\uFF00-\uFF0F\uFF1A-\uFF20\uFF3B-\uFF40\uFF5B-\uFF65]',
    );

    int i = 0;
    while (i < text.length) {
      final char = text[i];
      if (asciiRegex.hasMatch(char)) {
        buffer.write(char);
        i++;
        while (i < text.length && asciiRegex.hasMatch(text[i])) {
          buffer.write(text[i]);
          i++;
        }
        while (i < text.length &&
            (punctRegex.hasMatch(text[i]) ||
                (!asciiRegex.hasMatch(text[i]) &&
                    !cjkRegex.hasMatch(text[i])))) {
          buffer.write(text[i]);
          i++;
        }
        tokens.add(TextToken(buffer.toString(), false));
        buffer.clear();
      } else if (cjkRegex.hasMatch(char)) {
        buffer.write(char);
        i++;

        final smallKanaRegex = RegExp(r'[ぁぃぅぇぉっゃゅょァィゥェォッャュョー゛]');
        while (i < text.length && smallKanaRegex.hasMatch(text[i])) {
          buffer.write(text[i]);
          i++;
        }

        while (i < text.length &&
            (punctRegex.hasMatch(text[i]) ||
                (!asciiRegex.hasMatch(text[i]) &&
                    !cjkRegex.hasMatch(text[i])))) {
          buffer.write(text[i]);
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
    _autoRubyCancelled = false;

    final totalLines = _document!.lines.length;
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('準備中...');

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('自動ルビ＆チェック付加'),
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
              child: const Text('中止'),
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
          final hasKanjiOrEng = RegExp(r'[a-zA-Z\u4E00-\u9FAF]').hasMatch(node.text);
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
      if (currentBatchChars + job.node.text.length > maxCharsPerBatch && currentBatch.isNotEmpty) {
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
      statusNotifier.value = 'APIリクエスト中... (${completedBatches + 1} / ${batches.length})';

      final texts = batch.map((j) => j.node.text).toList();
      final batchResults = await _fetchRubyBatch(texts);

      if (batchResults != null) {
        // Note: batchResults.length might not exactly equal batch.length if API behaves unexpectedly.
        // We will map as many as returned safely.
        final limit = batchResults.length < batch.length ? batchResults.length : batch.length;
        for (int i = 0; i < limit; i++) {
          final job = batch[i];
          jobResults.putIfAbsent(job.lineIndex, () => {});
          jobResults[job.lineIndex]![job.nodeIndex] = batchResults[i];
        }
      }

      completedBatches++;
    }

    if (!_autoRubyCancelled) {
      progressNotifier.value = 1.0;
      statusNotifier.value = 'AST更新中...';

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
            _autoRubyCancelled ? 'ルビ振りを中止しました（完了した部分は保持されます）' : '自動ルビ＆チェック完了!',
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

    for (int i = 0; i < furigana.length; i++) {
      final ch = furigana[i];
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

  Future<List<List<LyricNode>>?> _fetchRubyBatch(List<String> texts) async {
    try {
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
        final json = jsonDecode(response.body);
        final words = json['result']['word'] as List;

        final processedWords = <Map<String, dynamic>>[];
        final smallKanaRegex = RegExp(r'^[ぁぃぅぇぉっゃゅょァィゥェォッャュョー゛]+');

        for (var w in words) {
          final surface = w['surface'] as String;
          final furigana = w['furigana'] as String?;
          final subword = w['subword'];

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
              processedWords.add({
                'surface': remainder,
                'furigana': furigana?.substring(kana.length),
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
        return batchResults;
      }
    } catch (e) {
      debugPrint('Yahoo API Error: $e');
    }
    return null;
  }
}

class _RubyJob {
  final int lineIndex;
  final int nodeIndex;
  final LyricText node;
  _RubyJob(this.lineIndex, this.nodeIndex, this.node);
}
