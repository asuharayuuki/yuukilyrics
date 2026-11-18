part of '../ass_exporter.dart';

// Header, timing helpers, singer prefixes and joined ruby chains.

void _writeInterludePrompt({
  required StringBuffer sb,
  required String text,
  required double centerX,
  required double centerY,
  required Duration displayStart,
  required Duration displayEnd,
  required AssExportSettings settings,
  required _AssTextMetrics textMetrics,
}) {
  final fontSize = settings.fontSize.toDouble();
  final placements = _layoutAssText(
    text: text,
    centerX: centerX,
    fontSize: fontSize,
    spacing: _resolveSpacing(fontSize, settings.letterSpacingEm),
    textMetrics: textMetrics,
  );
  for (final placement in placements) {
    sb.writeln(
      'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},Interlude,,0,0,0,,{${placement.alignmentTag}\\pos(${placement.centerX.toStringAsFixed(1)},${(centerY + placement.centerYOffset).toStringAsFixed(1)})\\fad(500,500)\\c&HFFFFFF&}${placement.text}',
    );
  }
}

_ProcessedSingerLine _replaceSingerPrefixes({
  required LyricLine sourceLine,
  required int? initialSingerIndex,
  required List<_SingerPrefixMatch> sortedSingers,
  required bool showPrefixes,
}) {
  final nodes = <LyricNode>[];
  var currentSingerIndex = initialSingerIndex;
  var leadingSingerIndex = initialSingerIndex;
  var hasVisibleLyrics = false;

  for (final node in sourceLine.nodes) {
    // Older edits could pull a marker into a ruby base (`{A歌|か}`). Split it
    // off so it still switches the color instead of being drawn as lyrics.
    if (node is LyricRuby && sortedSingers.isNotEmpty) {
      final match = sortedSingers
          .where((s) => node.baseText.startsWith(s.singer.prefix))
          .firstOrNull;
      if (match != null && node.baseText.length > match.singer.prefix.length) {
        currentSingerIndex = match.singerIndex;
        if (!hasVisibleLyrics) leadingSingerIndex = currentSingerIndex;
        nodes.add(
          _SingerMarkerNode(
            singerIndex: currentSingerIndex,
            isLeading: !hasVisibleLyrics,
            displayText: showPrefixes ? match.singer.prefix : '',
          ),
        );
        nodes.add(
          LyricRuby(
            baseText: node.baseText.substring(match.singer.prefix.length),
            rubyNodes: node.rubyNodes,
            joinNext: node.joinNext,
          ),
        );
        hasVisibleLyrics = true;
        continue;
      }
    }
    if (node is! LyricText || sortedSingers.isEmpty) {
      nodes.add(node);
      if (node is LyricRuby) hasVisibleLyrics = true;
      continue;
    }

    var cursor = 0;
    while (cursor < node.text.length) {
      _SingerPrefixMatch? nextMatch;
      var nextOffset = node.text.length;
      for (final candidate in sortedSingers) {
        final offset = node.text.indexOf(candidate.singer.prefix, cursor);
        if (offset >= 0 && offset < nextOffset) {
          nextMatch = candidate;
          nextOffset = offset;
        }
      }

      if (nextMatch == null) {
        final suffix = node.text.substring(cursor);
        if (suffix.isNotEmpty) {
          nodes.add(LyricText(suffix));
          hasVisibleLyrics = true;
        }
        break;
      }

      if (nextOffset > cursor) {
        nodes.add(LyricText(node.text.substring(cursor, nextOffset)));
        hasVisibleLyrics = true;
      }
      currentSingerIndex = nextMatch.singerIndex;
      if (!hasVisibleLyrics) leadingSingerIndex = currentSingerIndex;
      nodes.add(
        _SingerMarkerNode(
          singerIndex: currentSingerIndex,
          isLeading: !hasVisibleLyrics,
          displayText: showPrefixes ? nextMatch.singer.prefix : '',
        ),
      );
      cursor = nextOffset + nextMatch.singer.prefix.length;
    }
  }

  return _ProcessedSingerLine(
    line: LyricLine(nodes: nodes),
    leadingSingerIndex: leadingSingerIndex,
    trailingSingerIndex: currentSingerIndex,
  );
}

LyricLine _mergeJoinedRubyChains(LyricLine sourceLine) {
  final nodes = <LyricNode>[];
  var index = 0;

  while (index < sourceLine.nodes.length) {
    final node = sourceLine.nodes[index];
    if (node is! LyricRuby || !node.joinNext) {
      nodes.add(node);
      index++;
      continue;
    }

    final chain = <LyricRuby>[node];
    var nextIndex = index + 1;
    while (chain.last.joinNext && nextIndex < sourceLine.nodes.length) {
      final next = sourceLine.nodes[nextIndex];
      if (next is! LyricRuby) break;
      chain.add(next);
      nextIndex++;
    }

    // An unterminated chain has no complete visual grouping. Preserve it as
    // authored instead of silently consuming unrelated following nodes.
    if (chain.length == 1 || chain.last.joinNext) {
      nodes.add(node);
      index++;
      continue;
    }

    final rubyNodes = <LyricNode>[];
    for (var chainIndex = 0; chainIndex < chain.length; chainIndex++) {
      if (chainIndex > 0) rubyNodes.add(LyricText('＋'));
      rubyNodes.addAll(chain[chainIndex].rubyNodes);
    }
    nodes.add(
      LyricRuby(
        baseText: chain.map((ruby) => ruby.baseText).join(),
        rubyNodes: rubyNodes,
      ),
    );
    index = nextIndex;
  }

  return LyricLine(nodes: nodes);
}

void _writeHeader(
  StringBuffer sb,
  AssExportSettings settings, {
  required _AssTextMetrics textMetrics,
  required bool includeSingerAvatarStyle,
}) {
  int playResX = AssExporter.getPlayResX(settings);
  int playResY = AssExporter.getPlayResY(settings);

  sb.writeln('[Script Info]');
  sb.writeln('ScriptType: v4.00+');
  sb.writeln('PlayResX: $playResX');
  sb.writeln('PlayResY: $playResY');
  sb.writeln('WrapStyle: 0');
  sb.writeln('ScaledBorderAndShadow: yes');
  sb.writeln('');

  String sungTextColor = _colorToAss(settings.sungTextColor.color0);
  String sungOutlineColor = _colorToAss(settings.sungOutlineColor.color0);
  String unsungTextColor = _colorToAss(settings.unsungTextColor.color0);
  String unsungOutlineColor = _colorToAss(settings.unsungOutlineColor.color0);
  int fs = settings.fontSize;
  final assFs = _formatAssNumber(textMetrics.assFontSize(fs.toDouble()));
  String fn = settings.fontName;

  int rubyFs = _resolveRubyFontSize(
    fs.toDouble(),
    settings.rubyFontSize,
  ).round();
  final assRubyFs = _formatAssNumber(
    textMetrics.assFontSize(rubyFs.toDouble()),
  );

  double spacing = _resolveSpacing(fs.toDouble(), settings.letterSpacingEm);
  double rubySpacing = _resolveRubySpacing(
    rubyFs.toDouble(),
    settings.letterSpacingEm,
  );
  double interludeSpacing = _resolveSpacing(fs.toDouble(), null);
  String assSpacing = _formatAssNumber(spacing);
  String assRubySpacing = _formatAssNumber(rubySpacing);
  String assInterludeSpacing = _formatAssNumber(interludeSpacing);

  int baseOutW = _resolveFontOutlineWidth(
    fs.toDouble(),
    settings.fontOutlineWidth,
  ).round();
  int rubyBaseOutW = _resolveRubyBaseOutlineWidth(
    baseOutW.toDouble(),
    fs.toDouble(),
    rubyFs.toDouble(),
    settings.rubyOutlineWidth,
  ).round();

  String boldFlag = settings.isBold ? '-1' : '0';

  sb.writeln('[V4+ Styles]');
  sb.writeln(
    'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
  );
  sb.writeln(
    'Style: DefaultUnsung,$fn,$assFs,$unsungTextColor,&H00FFFFFF,$unsungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assSpacing,0,1,$baseOutW,0,5,0,0,0,1',
  );
  sb.writeln(
    'Style: DefaultSung,$fn,$assFs,$sungTextColor,&H00FFFFFF,$sungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assSpacing,0,1,$baseOutW,0,5,0,0,0,1',
  );
  sb.writeln(
    'Style: RubyUnsung,$fn,$assRubyFs,$unsungTextColor,&H00FFFFFF,$unsungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assRubySpacing,0,1,$rubyBaseOutW,0,5,0,0,0,1',
  );
  sb.writeln(
    'Style: RubySung,$fn,$assRubyFs,$sungTextColor,&H00FFFFFF,$sungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assRubySpacing,0,1,$rubyBaseOutW,0,5,0,0,0,1',
  );
  sb.writeln(
    'Style: Interlude,$fn,$assFs,$sungTextColor,&H00FFFFFF,$unsungOutlineColor,&H80000000,$boldFlag,0,0,0,100,100,$assInterludeSpacing,0,1,$baseOutW,0,5,0,0,0,1',
  );
  sb.writeln(
    'Style: CountdownVector,Arial,1,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,5,0,0,0,1',
  );
  if (includeSingerAvatarStyle) {
    sb.writeln(
      'Style: SingerAvatar,Arial,1,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1',
    );
  }

  sb.writeln('');
  sb.writeln('[Events]');
  sb.writeln(
    'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
  );
}

String _formatTime(Duration d) {
  int h = d.inHours;
  int m = d.inMinutes.remainder(60);
  int s = d.inSeconds.remainder(60);
  int cs = (d.inMilliseconds.remainder(1000) ~/ 10);
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
}

Duration _parseTime(String timeStr) {
  return LyricTimeTag.parseDuration(timeStr) ?? Duration.zero;
}

String _lyricFade(bool enabled, Duration start, Duration end) {
  if (!enabled) return '';
  // ASS event times are written in centiseconds.
  final centiseconds = end.inMilliseconds ~/ 10 - start.inMilliseconds ~/ 10;
  final milliseconds = min(200, centiseconds * 5);
  return milliseconds > 0 ? '\\fad($milliseconds,$milliseconds)' : '';
}
