/// One piece of lyric text: either a singer marker or ordinary lyrics.
typedef MarkerSegment = ({String text, bool isMarker});

/// Finds singer markers (line color prefixes such as `A`, `A/B` or `結城`)
/// inside plain lyric text.
///
/// Matching mirrors the ASS exporter: scanning left to right, the earliest
/// occurrence wins, and among markers starting at the same position the
/// longest one wins, so `A/B` is never read as `A` followed by `/B`.
class SingerMarkers {
  final List<String> _markers;

  SingerMarkers(Iterable<String> markers)
    : _markers =
          markers
              .map((m) => m.trim())
              .where((m) => m.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));

  static final none = SingerMarkers(const []);

  bool get isEmpty => _markers.isEmpty;

  /// Splits [text] into marker and lyric segments, in order. Concatenating
  /// the segments' text gives back [text].
  List<MarkerSegment> split(String text) {
    if (_markers.isEmpty || text.isEmpty) {
      return [(text: text, isMarker: false)];
    }
    final segments = <MarkerSegment>[];
    var cursor = 0;
    while (cursor < text.length) {
      final match = _nextMatch(text, cursor);
      if (match == null) {
        segments.add((text: text.substring(cursor), isMarker: false));
        break;
      }
      if (match.start > cursor) {
        segments.add((
          text: text.substring(cursor, match.start),
          isMarker: false,
        ));
      }
      segments.add((text: match.marker, isMarker: true));
      cursor = match.start + match.marker.length;
    }
    return segments;
  }

  /// The marker at [offset] in [text], if one starts exactly there.
  String? markerAt(String text, int offset) {
    for (final marker in _markers) {
      if (text.startsWith(marker, offset)) return marker;
    }
    return null;
  }

  /// The last marker in [text], i.e. the singer in effect at its end.
  String? lastMarker(String text) {
    String? last;
    for (final segment in split(text)) {
      if (segment.isMarker) last = segment.text;
    }
    return last;
  }

  /// Text with all markers removed.
  String stripMarkers(String text) => split(
    text,
  ).where((segment) => !segment.isMarker).map((segment) => segment.text).join();

  ({int start, String marker})? _nextMatch(String text, int from) {
    ({int start, String marker})? best;
    for (final marker in _markers) {
      final start = text.indexOf(marker, from);
      // Markers are sorted longest first, so a later marker only wins by
      // starting strictly earlier.
      if (start >= 0 && (best == null || start < best.start)) {
        best = (start: start, marker: marker);
      }
    }
    return best;
  }
}
