import 'package:characters/characters.dart';

import '../models/lyric_ast.dart';
import 'singer_markers.dart';

class TextToken {
  final String text;
  final bool addTag10;
  TextToken(this.text, this.addTag10);
}

/// Adds RhythmicaLyrics-style check tags to untagged lyric text.
///
/// Pure functions over the lyric AST; no editor state is involved.
class AutoTagger {
  AutoTagger._();

  /// Inserts check tags in place for every line in [lines]: a `[1]` before
  /// each readable token or untagged ruby, `[10]` between non-Latin words
  /// separated by spaces, and a line-end `[10]`.
  ///
  /// Text matching one of [markers] (singer line-color prefixes) is not
  /// lyrics: it gets no check of its own, is never split, and is placed
  /// before the check of the syllable that follows it.
  static void tagLines(List<LyricLine> lines, {SingerMarkers? markers}) {
    final singerMarkers = markers ?? SingerMarkers.none;
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
          for (final segment in singerMarkers.split(node.text)) {
            if (segment.isMarker) {
              _addMarker(newNodes, segment.text);
            } else if (segment.text.isNotEmpty) {
              _addLyricText(newNodes, segment.text);
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
          (n) =>
              n is LyricRuby ||
              (n is LyricText &&
                  singerMarkers.stripMarkers(n.text).trim().isNotEmpty),
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

  /// Puts [marker] before a directly preceding check, so the check keeps
  /// timing the next visible syllable instead of the invisible marker.
  static void _addMarker(List<LyricNode> nodes, String marker) {
    final last = nodes.lastOrNull;
    if (last is LyricTimeTag && last.type != 10) {
      nodes.insert(nodes.length - 1, LyricText(marker));
    } else {
      nodes.add(LyricText(marker));
    }
  }

  static void _addLyricText(List<LyricNode> nodes, String text) {
    final isCovered =
        nodes.isNotEmpty &&
        nodes.last is LyricTimeTag &&
        (nodes.last as LyricTimeTag).type != 10;

    final tokens = tokenize(text);
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];

      // Do not add tag for purely whitespace or punctuation tokens
      bool hasReadableText = RegExp(
        r'[a-zA-Z0-9\uFF10-\uFF19\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF\u3400-\u4DBF]',
      ).hasMatch(token.text);
      if (!hasReadableText) {
        nodes.add(LyricText(token.text));
        if (token.addTag10) {
          nodes.add(LyricTimeTag(type: 10, time: ''));
        }
        continue;
      }

      if (i == 0 && isCovered) {
        nodes.add(LyricText(token.text));
      } else {
        nodes.add(LyricTimeTag(type: 1, time: ''));
        nodes.add(LyricText(token.text));
      }
      if (token.addTag10) {
        nodes.add(LyricTimeTag(type: 10, time: ''));
      }
    }
  }

  static List<LyricNode> _insertTag10AtSpaces(List<LyricNode> inputNodes) {
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

  static List<TextToken> tokenize(String text) {
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
}
