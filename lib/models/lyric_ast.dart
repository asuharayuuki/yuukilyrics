abstract class LyricNode {
  String toLrcString();
}

class LyricTimeTag extends LyricNode {
  @override
  String toString() => toLrcString();

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

  /// Parses mm:ss:xx or mm:ss.xx back to Duration. Returns null if invalid.
  static Duration? parseDuration(String timeStr) {
    if (timeStr.isEmpty) return null;
    final parts = timeStr.split(RegExp(r'[:.]'));
    if (parts.length >= 2) {
      final mm = int.tryParse(parts[0]) ?? 0;
      final ss = int.tryParse(parts[1]) ?? 0;
      int xx = 0;
      if (parts.length >= 3) {
        String msPart = parts[2];
        if (msPart.length == 2) {
          xx = (int.tryParse(msPart) ?? 0) * 10;
        } else if (msPart.length == 3) {
          xx = int.tryParse(msPart) ?? 0;
        } else {
          xx = (int.tryParse(msPart.padRight(3, '0').substring(0, 3)) ?? 0);
        }
      }
      return Duration(minutes: mm, seconds: ss, milliseconds: xx);
    }
    return null;
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
  @override
  String toString() => toLrcString();

  final String text;

  LyricText(this.text);

  @override
  String toLrcString() => text;
}

class LyricRuby extends LyricNode {
  @override
  String toString() => toLrcString();

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
  @override
  String toString() => toLrcString();

  final List<LyricNode> nodes; // mutable list for in-place editing

  LyricLine({required this.nodes});

  String toLrcString() {
    return nodes.map((e) => e.toLrcString()).join('');
  }
}

class LyricDocument {
  @override
  String toString() => toLrcString();

  final List<LyricLine> lines;

  LyricDocument({required this.lines});

  String toLrcString() {
    return lines.map((e) => e.toLrcString()).join('\n');
  }
}
