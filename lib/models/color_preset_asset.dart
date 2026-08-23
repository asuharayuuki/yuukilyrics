enum ColorFillMode { solid, gradient, millefeuille }

class ColorPresetStop {
  final double position;
  final int color;

  const ColorPresetStop({required this.position, required this.color});
}

class ColorPresetValue {
  final ColorFillMode mode;
  final List<ColorPresetStop> stops;

  ColorPresetValue._({
    required this.mode,
    required Iterable<ColorPresetStop> stops,
  }) : stops = List.unmodifiable(_normalize(stops));

  factory ColorPresetValue.solid(int color) => ColorPresetValue._(
    mode: ColorFillMode.solid,
    stops: [ColorPresetStop(position: 0, color: color)],
  );

  factory ColorPresetValue.gradient({
    required int color0,
    required int color100,
  }) => ColorPresetValue.withStops(
    mode: ColorFillMode.gradient,
    stops: [
      ColorPresetStop(position: 0, color: color0),
      ColorPresetStop(position: 1, color: color100),
    ],
  );

  factory ColorPresetValue.withStops({
    required ColorFillMode mode,
    required Iterable<ColorPresetStop> stops,
  }) {
    final normalized = _normalize(stops);
    if (normalized.isEmpty) {
      throw ArgumentError('At least one color stop is required.');
    }
    return ColorPresetValue._(mode: mode, stops: normalized);
  }

  int get color0 => stops.first.color;
  int get color100 => stops.last.color;
  bool get isGradient => mode != ColorFillMode.solid;
  bool get isMillefeuille => mode == ColorFillMode.millefeuille;

  String toMarkdown() {
    final top = _formatColor(color0);
    if (mode == ColorFillMode.solid) return top;
    if (mode == ColorFillMode.gradient &&
        stops.length == 2 &&
        stops.first.position == 0 &&
        stops.last.position == 1) {
      return '$top/${_formatColor(color100)}';
    }
    final prefix = mode == ColorFillMode.gradient ? 'g' : 'm';
    return '$prefix(${stops.map((stop) => '${_formatPosition(stop.position)}:${_formatColor(stop.color)}').join(',')})';
  }

  static ColorPresetValue? tryParse(String source) {
    final value = source.trim();
    final match = RegExp(
      r'^#([0-9a-fA-F]{6})(?:/#([0-9a-fA-F]{6}))?$',
    ).firstMatch(value);

    int parse(String value) => 0xFF000000 | int.parse(value, radix: 16);
    if (match != null) {
      final top = parse(match.group(1)!);
      final bottom = match.group(2);
      return bottom == null
          ? ColorPresetValue.solid(top)
          : ColorPresetValue.gradient(color0: top, color100: parse(bottom));
    }

    final extended = RegExp(r'^([gGmM])\((.*)\)$').firstMatch(value);
    if (extended == null) return null;
    final stops = <ColorPresetStop>[];
    for (final field in extended.group(2)!.split(',')) {
      final stopMatch = RegExp(
        r'^\s*(100(?:\.0+)?|\d{1,2}(?:\.\d+)?)\s*:\s*#([0-9a-fA-F]{6})\s*$',
      ).firstMatch(field);
      if (stopMatch == null) return null;
      final percent = double.tryParse(stopMatch.group(1)!);
      if (percent == null || percent < 0 || percent > 100) return null;
      stops.add(
        ColorPresetStop(
          position: percent / 100,
          color: parse(stopMatch.group(2)!),
        ),
      );
    }
    if (stops.isEmpty) return null;
    return ColorPresetValue.withStops(
      mode: extended.group(1)!.toLowerCase() == 'g'
          ? ColorFillMode.gradient
          : ColorFillMode.millefeuille,
      stops: stops,
    );
  }

  static List<ColorPresetStop> _normalize(Iterable<ColorPresetStop> source) {
    final indexed = source.indexed.toList()
      ..sort((a, b) {
        final result = a.$2.position.compareTo(b.$2.position);
        return result != 0 ? result : a.$1.compareTo(b.$1);
      });
    return indexed
        .map(
          (entry) => ColorPresetStop(
            position: entry.$2.position.clamp(0.0, 1.0),
            color: entry.$2.color,
          ),
        )
        .toList(growable: false);
  }

  static String _formatPosition(double position) {
    final percent = position * 100;
    if (percent == percent.roundToDouble()) return percent.round().toString();
    return percent.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _formatColor(int color) =>
      '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class ColorPresetAsset {
  final String name;
  final ColorPresetValue sungTextColor;
  final ColorPresetValue sungOutlineColor;
  final ColorPresetValue sungDecorationColor;
  final ColorPresetValue unsungTextColor;
  final ColorPresetValue unsungOutlineColor;
  final ColorPresetValue unsungDecorationColor;

  const ColorPresetAsset({
    required this.name,
    required this.sungTextColor,
    required this.sungOutlineColor,
    required this.sungDecorationColor,
    required this.unsungTextColor,
    required this.unsungOutlineColor,
    required this.unsungDecorationColor,
  });

  ColorPresetAsset renamed(String newName) => ColorPresetAsset(
    name: newName,
    sungTextColor: sungTextColor,
    sungOutlineColor: sungOutlineColor,
    sungDecorationColor: sungDecorationColor,
    unsungTextColor: unsungTextColor,
    unsungOutlineColor: unsungOutlineColor,
    unsungDecorationColor: unsungDecorationColor,
  );

  List<String> toMarkdownFields() => [
    name,
    sungTextColor.toMarkdown(),
    sungOutlineColor.toMarkdown(),
    sungDecorationColor.toMarkdown(),
    unsungTextColor.toMarkdown(),
    unsungOutlineColor.toMarkdown(),
    unsungDecorationColor.toMarkdown(),
  ];
}
