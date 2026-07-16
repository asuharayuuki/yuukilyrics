import 'package:flutter/material.dart';

class LrcSyntaxController extends TextEditingController {
  LrcSyntaxController({super.text});

  static final RegExp _syntaxRegex = RegExp(r'(\[.*?\])|([{}|＋])');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> children = [];
    final textStr = value.text;
    final cs = Theme.of(context).colorScheme;
    int lastMatchEnd = 0;

    // State machine to color text inside ruby blocks
    bool inRubyBlock = false;
    bool pastPipe = false;

    // Helper to add text with the current state's color
    void addText(String text) {
      if (text.isEmpty) return;
      TextStyle? currentStyle = style; // Default text color for Standalone and Base Kanji
      
      if (inRubyBlock && pastPipe) {
        // Ruby phonetic text (Furigana)
        currentStyle = style?.copyWith(color: cs.primary);
      }
      
      children.add(TextSpan(text: text, style: currentStyle));
    }

    // Dimmed style for all metadata (tags, brackets, dividers)
    final metadataStyle = style?.copyWith(color: cs.outline);

    for (final match in _syntaxRegex.allMatches(textStr)) {
      final preText = textStr.substring(lastMatchEnd, match.start);
      addText(preText);

      final matchStr = match.group(0)!;
      if (matchStr.startsWith('[')) {
        // Time Tags (completely dimmed as they are less important)
        children.add(TextSpan(text: matchStr, style: metadataStyle));
      } else {
        // Ruby Punctuation and Kana Separator
        if (matchStr == '{') {
          inRubyBlock = true;
          pastPipe = false;
        } else if (matchStr == '|') {
          pastPipe = true;
        } else if (matchStr == '}') {
          inRubyBlock = false;
          pastPipe = false;
        }
        
        children.add(TextSpan(text: matchStr, style: metadataStyle));
      }

      lastMatchEnd = match.end;
    }

    final postText = textStr.substring(lastMatchEnd);
    addText(postText);

    return TextSpan(style: style, children: children);
  }
}
