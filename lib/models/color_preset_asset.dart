class ColorPresetValue {
  final int color0;
  final int color100;
  final bool isGradient;

  const ColorPresetValue.solid(int color)
    : color0 = color,
      color100 = color,
      isGradient = false;

  const ColorPresetValue.gradient({
    required this.color0,
    required this.color100,
  }) : isGradient = true;

  String toMarkdown() {
    final top = _formatColor(color0);
    return isGradient ? '$top/${_formatColor(color100)}' : top;
  }

  static ColorPresetValue? tryParse(String source) {
    final match = RegExp(
      r'^#([0-9a-fA-F]{6})(?:/#([0-9a-fA-F]{6}))?$',
    ).firstMatch(source.trim());
    if (match == null) return null;

    int parse(String value) => 0xFF000000 | int.parse(value, radix: 16);
    final top = parse(match.group(1)!);
    final bottom = match.group(2);
    return bottom == null
        ? ColorPresetValue.solid(top)
        : ColorPresetValue.gradient(color0: top, color100: parse(bottom));
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
