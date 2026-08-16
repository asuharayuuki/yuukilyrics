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
    final xx = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(
      2,
      '0',
    );
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
  final bool joinNext;

  LyricRuby({
    required this.baseText,
    required this.rubyNodes,
    this.joinNext = false,
  });

  String rubyContentToLrcString() {
    final contentNodes = rubyNodes
        .where((node) => node is! LyricTimeTag || node.type != 10)
        .toList();

    // If NO tags have timestamps, and the first tag has a type, output the clean version!
    bool hasAnyTime = contentNodes.whereType<LyricTimeTag>().any(
      (t) => t.time.isNotEmpty,
    );
    if (!hasAnyTime) {
      final firstTag = contentNodes.whereType<LyricTimeTag>().firstOrNull;
      if (firstTag != null && firstTag.type != null) {
        final fullText = contentNodes
            .whereType<LyricText>()
            .map((e) => e.text)
            .join();
        return '[${firstTag.type}]$fullText';
      }
    }

    return rubyNodes.map((e) => e.toLrcString()).join();
  }

  String endTagsToLrcString() {
    final hasTimedRubyTag = rubyNodes.whereType<LyricTimeTag>().any(
      (tag) => tag.type != 10 && tag.time.isNotEmpty,
    );
    final hasTypedRubyTag = rubyNodes.whereType<LyricTimeTag>().any(
      (tag) => tag.type != 10 && tag.type != null,
    );
    if (hasTimedRubyTag || !hasTypedRubyTag) return '';
    return rubyNodes
        .whereType<LyricTimeTag>()
        .where((tag) => tag.type == 10)
        .map((tag) => tag.toLrcString())
        .join();
  }

  @override
  String toLrcString() {
    return '{$baseText|${rubyContentToLrcString()}}${endTagsToLrcString()}';
  }
}

class LyricLine {
  @override
  String toString() => toLrcString();

  final List<LyricNode> nodes; // mutable list for in-place editing

  LyricLine({required this.nodes});

  String toLrcString() {
    final buffer = StringBuffer();
    var index = 0;
    while (index < nodes.length) {
      final node = nodes[index];
      if (node is! LyricRuby || !node.joinNext) {
        buffer.write(node.toLrcString());
        index++;
        continue;
      }

      final chain = <LyricRuby>[node];
      while (chain.last.joinNext && index + chain.length < nodes.length) {
        final next = nodes[index + chain.length];
        if (next is! LyricRuby) break;
        chain.add(next);
      }

      if (chain.length == 1 || chain.last.joinNext) {
        buffer.write(node.toLrcString());
        index++;
        continue;
      }

      buffer
        ..write('{')
        ..write(chain.map((ruby) => ruby.baseText).join())
        ..write('|')
        ..write(chain.map((ruby) => ruby.rubyContentToLrcString()).join('＋'))
        ..write('}')
        ..write(chain.map((ruby) => ruby.endTagsToLrcString()).join());
      index += chain.length;
    }
    return buffer.toString();
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
