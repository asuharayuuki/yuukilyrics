import 'dart:core';

class _TextToken {
  final String text;
  final bool addTag10;
  _TextToken(this.text, this.addTag10);
  @override
  String toString() => text;
}

List<_TextToken> _tokenizeTextAdvanced(String text) {
  if (text.isEmpty) return [];
  
  final tokens = <_TextToken>[];
  final buffer = StringBuffer();
  
  final RegExp asciiRegex = RegExp(r'[a-zA-Z0-9]');
  final RegExp cjkRegex = RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF\u3400-\u4DBF]');
  final RegExp spaceRegex = RegExp(r'[ \u3000]');
  
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
      while (i < text.length && !asciiRegex.hasMatch(text[i]) && !cjkRegex.hasMatch(text[i])) {
        buffer.write(text[i]);
        i++;
      }
      tokens.add(_TextToken(buffer.toString(), false));
      buffer.clear();
    } else if (cjkRegex.hasMatch(char)) {
      buffer.write(char);
      i++;
      
      final smallKanaRegex = RegExp(r'[ぁぃぅぇぉっゃゅょァィゥェォッャュョー゛]');
      while (i < text.length && smallKanaRegex.hasMatch(text[i])) {
        buffer.write(text[i]);
        i++;
      }
      
      while (i < text.length && !asciiRegex.hasMatch(text[i]) && !cjkRegex.hasMatch(text[i])) {
        buffer.write(text[i]);
        i++;
      }
      
      tokens.add(_TextToken(buffer.toString(), false));
      buffer.clear();
    } else {
      buffer.write(char);
      i++;
    }
  }
  
  if (buffer.isNotEmpty) {
    if (tokens.isNotEmpty) {
      final last = tokens.removeLast();
      tokens.add(_TextToken(last.text + buffer.toString(), last.addTag10));
    } else {
      tokens.add(_TextToken(buffer.toString(), false));
    }
  }
  
  return tokens;
}

void main() {
  print(_tokenizeTextAdvanced("らって"));
  print(_tokenizeTextAdvanced("たって"));
}
