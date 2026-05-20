abstract class LyricNode {
  String toLrcString();
}

class LyricTimeTag extends LyricNode {
  int? type;
  String time; // mutable for in-place tagging

  LyricTimeTag({this.type, required this.time});

  bool get isEmpty => time.isEmpty;

  /// Converts duration to mm:ss:xx (hundredths of second) format.
  static String formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final xx = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '$mm:$ss:$xx';
  }

  @override
  String toLrcString() {
    if (type != null) {
      if (time.isEmpty) return '[$type]';
      return '[$type|$time]';
    } else {
      if (time.isEmpty) return '[]';
      return '[$time]';
    }
  }
}

class LyricText extends LyricNode {
  final String text;

  LyricText(this.text);

  @override
  String toLrcString() => text;
}

class LyricRuby extends LyricNode {
  final String baseText;
  final List<LyricNode> rubyNodes; // mutable list for in-place editing

  LyricRuby({required this.baseText, required this.rubyNodes});

  @override
  String toLrcString() {
    // If NO tags have timestamps, and the first tag has a type, output the clean version!
    bool hasAnyTime = rubyNodes.whereType<LyricTimeTag>().any((t) => t.type != 10 && t.time.isNotEmpty);
    if (!hasAnyTime) {
      final firstTag = rubyNodes.whereType<LyricTimeTag>().where((t) => t.type != 10).firstOrNull;
      if (firstTag != null && firstTag.type != null) {
        String fullText = rubyNodes.whereType<LyricText>().map((e) => e.text).join('');
        final tag10 = rubyNodes.where((n) => n is LyricTimeTag && n.type == 10).firstOrNull;
        
        String res = '{$baseText|[${firstTag.type}]$fullText}';
        if (tag10 != null) res += tag10.toLrcString();
        return res;
      }
    }

    final rubyStr = rubyNodes.map((e) => e.toLrcString()).join('');
    return '{$baseText|$rubyStr}';
  }
}

class LyricLine {
  final List<LyricNode> nodes; // mutable list for in-place editing

  LyricLine({required this.nodes});

  String toLrcString() {
    return nodes.map((e) => e.toLrcString()).join('');
  }
}

class LyricDocument {
  final List<LyricLine> lines;

  LyricDocument({required this.lines});

  String toLrcString() {
    return lines.map((e) => e.toLrcString()).join('\n');
  }
}
