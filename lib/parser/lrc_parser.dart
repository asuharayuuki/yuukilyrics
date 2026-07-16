import '../models/lyric_ast.dart';

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
          nodes.add(rubyResult.node);
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
      int? type = int.tryParse(content.substring(0, pipeIndex));
      String time = content.substring(pipeIndex + 1);
      return _ParseResult(LyricTimeTag(type: type, time: time), end + 1);
    } else {
      int? type = int.tryParse(content);
      if (type != null) {
        return _ParseResult(LyricTimeTag(type: type, time: ''), end + 1);
      }
      return _ParseResult(LyricTimeTag(time: content), end + 1);
    }
  }

  static _ParseResult<LyricRuby>? _parseRuby(String line, int start) {
    int end = line.indexOf('}', start);
    if (end == -1) return null;

    String content = line.substring(start + 1, end);
    int pipeIndex = content.indexOf('|');
    
    if (pipeIndex != -1) {
      String baseText = content.substring(0, pipeIndex);
      String rubyContent = content.substring(pipeIndex + 1);
      
      // Parse rubyContent recursively into nodes
      LyricLine rubyLine = parseLine(rubyContent);
      
      // Auto-fix missing type for RhythmicaLyrics syntax
      List<List<LyricNode>> segments = [];
      List<LyricNode> currentSegment = [];

      for (final n in rubyLine.nodes) {
        if (n is LyricText && n.text.contains('＋')) {
          List<String> parts = n.text.split('＋');
          for (int i = 0; i < parts.length; i++) {
            if (parts[i].isNotEmpty) {
              currentSegment.add(LyricText(parts[i]));
            }
            if (i < parts.length - 1) {
              segments.add(currentSegment);
              currentSegment = [];
              currentSegment.add(LyricText('＋'));
            }
          }
        } else {
          currentSegment.add(n);
        }
      }
      if (currentSegment.isNotEmpty) {
        segments.add(currentSegment);
      }

      for (final seg in segments) {
        int tagCount = 0;
        LyricTimeTag? firstTag;
        for (final n in seg) {
          if (n is LyricTimeTag && n.type != 10) {
            tagCount++;
            firstTag ??= n;
          }
        }
        if (firstTag != null && firstTag.type == null && tagCount > 0) {
          firstTag.type = tagCount;
        }
      }

      List<LyricNode> fixedNodes = [];
      for (final seg in segments) {
        fixedNodes.addAll(seg);
      }
      rubyLine.nodes.clear();
      rubyLine.nodes.addAll(fixedNodes);
      
      // Expand missing tags based on type indicators
      List<LyricNode> expandedNodes = [];
      List<LyricNode> currentSection = [];
      List<List<LyricNode>> sections = [];
      
      for (final n in rubyLine.nodes) {
        if (n is LyricTimeTag && n.type != null) {
          if (currentSection.isNotEmpty) {
            sections.add(currentSection);
          }
          currentSection = [n];
        } else {
          currentSection.add(n);
        }
      }
      if (currentSection.isNotEmpty) {
        sections.add(currentSection);
      }
      
      for (final sec in sections) {
        if (sec.isEmpty) continue;
        final first = sec.first;
        if (first is LyricTimeTag && first.type != null && first.type != 10) {
           int expected = first.type!;
           if (expected < 0) expected = 0;
           if (expected > 100) expected = 100;
           int existing = sec.whereType<LyricTimeTag>().length;
           if (existing < expected) {
              String fullText = '';
              for (final n in sec) {
                if (n is LyricText) fullText += n.text;
              }
              final chars = fullText.split('');
              
              final tagsQueue = <LyricTimeTag>[];
              for (final n in sec) {
                if (n is LyricTimeTag) tagsQueue.add(n);
              }
              while (tagsQueue.length < expected) {
                tagsQueue.add(LyricTimeTag(type: null, time: ''));
              }
              
              List<LyricNode> newSec = [];
              newSec.add(tagsQueue.removeAt(0)); // The typed tag
              
              for (int i=0; i<chars.length; i++) {
                newSec.add(LyricText(chars[i]));
                if (tagsQueue.isNotEmpty && i < chars.length - 1) {
                  newSec.add(tagsQueue.removeAt(0));
                }
              }
              while (tagsQueue.isNotEmpty) {
                newSec.add(tagsQueue.removeAt(0));
              }
              expandedNodes.addAll(newSec);
           } else {
              expandedNodes.addAll(sec);
           }
        } else {
           expandedNodes.addAll(sec);
        }
      }
      
      return _ParseResult(
        LyricRuby(baseText: baseText, rubyNodes: expandedNodes),
        end + 1,
      );
    }
    
    return null;
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

class _ParseResult<T extends LyricNode> {
  final T node;
  final int endIndex;
  _ParseResult(this.node, this.endIndex);
}
