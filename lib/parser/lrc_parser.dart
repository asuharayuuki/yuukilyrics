import '../models/lyric_ast.dart';
import 'package:characters/characters.dart';

class LrcParser {
  /// Parses a single line of extended LRC string into a LyricLine.
  static LyricLine parseLine(String line) {
    final List<LyricNode> nodes = [];
    int cursor = 0;

    while (cursor < line.length) {
      if (line[cursor] == '[') {
        final tagResult = _parseTimeTag(line, cursor);
        if (tagResult != null) {
          nodes.add(tagResult.node);
          cursor = tagResult.endIndex;
          continue;
        }
      } else if (line[cursor] == '{') {
        final rubyResult = _parseRuby(line, cursor);
        if (rubyResult != null) {
          nodes.addAll(rubyResult.node);
          cursor = rubyResult.endIndex;
          continue;
        }
      }

      // If not a tag or ruby, or parsing failed, it's text.
      // Find the next '[' or '{' strictly after the current cursor
      int nextBracket = line.indexOf('[', cursor + 1);
      int nextBrace = line.indexOf('{', cursor + 1);

      int nextSpec = -1;
      if (nextBracket != -1 && nextBrace != -1) {
        nextSpec = nextBracket < nextBrace ? nextBracket : nextBrace;
      } else if (nextBracket != -1) {
        nextSpec = nextBracket;
      } else if (nextBrace != -1) {
        nextSpec = nextBrace;
      }

      if (nextSpec == -1) {
        if (cursor < line.length) {
          nodes.add(LyricText(line.substring(cursor)));
        }
        break;
      } else {
        if (nextSpec > cursor) {
          nodes.add(LyricText(line.substring(cursor, nextSpec)));
        }
        cursor = nextSpec;
      }
    }

    return LyricLine(nodes: nodes);
  }

  static _ParseResult<LyricTimeTag>? _parseTimeTag(String line, int start) {
    int end = line.indexOf(']', start);
    if (end == -1) return null;

    String content = line.substring(start + 1, end);
    int pipeIndex = content.indexOf('|');

    if (pipeIndex != -1) {
      final typeText = content.substring(0, pipeIndex);
      final type = RegExp(r'^\d+$').hasMatch(typeText)
          ? int.tryParse(typeText)
          : null;
      String time = content.substring(pipeIndex + 1);
      if (type == null ||
          (time.isNotEmpty && LyricTimeTag.parseDuration(time) == null)) {
        return null;
      }
      return _ParseResult(LyricTimeTag(type: type, time: time), end + 1);
    } else {
      if (content.isEmpty) {
        return _ParseResult(LyricTimeTag(time: ''), end + 1);
      }
      final type = RegExp(r'^\d+$').hasMatch(content)
          ? int.tryParse(content)
          : null;
      if (type != null) {
        return _ParseResult(LyricTimeTag(type: type, time: ''), end + 1);
      }
      if (LyricTimeTag.parseDuration(content) != null) {
        return _ParseResult(LyricTimeTag(time: content), end + 1);
      }
      return null;
    }
  }

  static _ParseResult<List<LyricNode>>? _parseRuby(String line, int start) {
    int end = line.indexOf('}', start);
    if (end == -1) return null;

    String content = line.substring(start + 1, end);
    int pipeIndex = content.indexOf('|');

    if (pipeIndex != -1) {
      String baseText = content.substring(0, pipeIndex);
      String rubyContent = content.substring(pipeIndex + 1);

      final rubyLine = parseLine(rubyContent);
      final segments = <List<LyricNode>>[<LyricNode>[]];
      var hasJoinMarker = false;
      for (final node in rubyLine.nodes) {
        if (node is! LyricText || !node.text.contains('＋')) {
          segments.last.add(node);
          continue;
        }

        final parts = node.text.split('＋');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            segments.last.add(LyricText(parts[i]));
          }
          if (i < parts.length - 1) {
            hasJoinMarker = true;
            segments.add(<LyricNode>[]);
          }
        }
      }

      final baseUnits = baseText.characters.toList();
      final canSplitJoinedBase =
          baseUnits.isNotEmpty && baseUnits.every(_isWideRubyBaseUnit);
      if (hasJoinMarker &&
          canSplitJoinedBase &&
          segments.length == baseUnits.length) {
        return _ParseResult([
          for (var i = 0; i < baseUnits.length; i++)
            LyricRuby(
              baseText: baseUnits[i],
              rubyNodes: _fixRubySegment(segments[i]),
              joinNext: i < baseUnits.length - 1,
            ),
        ], end + 1);
      }

      return _ParseResult([
        LyricRuby(
          baseText: baseText,
          rubyNodes: _fixRubySegment(rubyLine.nodes),
        ),
      ], end + 1);
    }

    return null;
  }

  static bool _isWideRubyBaseUnit(String unit) {
    if (unit.isEmpty) return false;
    final code = unit.runes.first;
    return (code >= 0x3000 && code <= 0x9FFF) ||
        (code >= 0xF900 && code <= 0xFAFF) ||
        (code >= 0xFF00 && code <= 0xFFEF) ||
        (code >= 0x1F000 && code <= 0x1FAFF) ||
        (code >= 0x20000 && code <= 0x3FFFF) ||
        code == 0x25CF;
  }

  static List<LyricNode> _fixRubySegment(List<LyricNode> nodes) {
    // In RhythmicaLyrics the first tag's type stores t_kazu directly. Untyped
    // tags are real time-only tags (t_kazu == 0), not omitted check counts.
    return List<LyricNode>.from(nodes);
  }

  /// Parses a full multiline extended LRC document.
  static LyricDocument parseDocument(String document) {
    List<LyricLine> lines = [];
    for (String line in document.split('\n')) {
      // Remove trailing whitespace (like spaces/tabs at end of line)
      line = line.trimRight();
      lines.add(parseLine(line));
    }
    return LyricDocument(lines: lines);
  }
}

class _ParseResult<T> {
  final T node;
  final int endIndex;
  _ParseResult(this.node, this.endIndex);
}
