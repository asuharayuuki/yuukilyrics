part of '../ass_exporter.dart';

// ASS color conversion, gradients, glow layers and karaoke sweeps.

String _colorToAss(Color color) {
  int r = (color.r * 255.0).round().clamp(0, 255);
  int g = (color.g * 255.0).round().clamp(0, 255);
  int b = (color.b * 255.0).round().clamp(0, 255);
  String hexR = r.toRadixString(16).padLeft(2, '0').toUpperCase();
  String hexG = g.toRadixString(16).padLeft(2, '0').toUpperCase();
  String hexB = b.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '&H00$hexB$hexG$hexR&';
}

Color _colorAt(AssColorValue value, double position) {
  if (!value.isGradient) return value.color0;
  final stops = value.effectiveStops;
  if (position <= stops.first.position) return stops.first.color;
  if (value.isMillefeuille) {
    var result = stops.first.color;
    for (final stop in stops) {
      if (stop.position > position) break;
      result = stop.color;
    }
    return result;
  }
  for (var index = 1; index < stops.length; index++) {
    final right = stops[index];
    if (position > right.position) continue;
    final left = stops[index - 1];
    final width = right.position - left.position;
    if (width <= 0) return right.color;
    final amount = ((position - left.position) / width).clamp(0.0, 1.0);
    return Color.lerp(left.color, right.color, amount) ?? left.color;
  }
  return stops.last.color;
}

String _assColorAt(AssColorValue value, double position) {
  return _colorToAss(_colorAt(value, position));
}

Color _blurredColorAt(
  AssColorValue value,
  double position,
  double normalizedSigma,
) {
  if (!value.isGradient || normalizedSigma <= 0) {
    return _colorAt(value, position);
  }

  // N3 draws the complete multi-colour outline into a transparent bitmap
  // and applies one Gaussian blur to that bitmap. ASS cannot blur a group of
  // separately coloured events, so pre-convolve the vertical colour field
  // before emitting narrow clipped bands. This is especially important for
  // mille-feuille brushes: their hard source transitions become softly
  // blended by N3's decoration blur instead of remaining visible as stripes.
  const sampleRadius = 3.0;
  const sampleCount = 17;
  var alpha = 0.0;
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var totalWeight = 0.0;
  for (var index = 0; index < sampleCount; index++) {
    final unit = index / (sampleCount - 1) * 2 - 1;
    final sigmaOffset = unit * sampleRadius;
    final weight = exp(-0.5 * sigmaOffset * sigmaOffset);
    final color = _colorAt(
      value,
      (position + sigmaOffset * normalizedSigma).clamp(0.0, 1.0),
    );
    alpha += color.a * weight;
    red += color.r * weight;
    green += color.g * weight;
    blue += color.b * weight;
    totalWeight += weight;
  }
  return Color.from(
    alpha: alpha / totalWeight,
    red: red / totalWeight,
    green: green / totalWeight,
    blue: blue / totalWeight,
  );
}

(double, double) _n3GradientRange({
  required double centerY,
  required double fontSize,
  required double outlineWidth,
}) {
  // NicoKaraMaker3 SetMultiColorAreas uses DrawTop + EdgeSize / 2 and
  // DrawBottom - EdgeSize / 2 for text, outline and decoration brushes.
  final halfHeight = max(0.5, (fontSize - outlineWidth) / 2);
  return (centerY - halfHeight, centerY + halfHeight);
}

List<_GradientBand> _gradientBands({
  required double clipTop,
  required double clipBottom,
  required double gradientTop,
  required double gradientBottom,
  required bool enabled,
  bool smooth = true,
  Iterable<double> breakpoints = const [],
}) {
  if (!enabled || gradientBottom <= gradientTop) {
    return [_GradientBand(top: clipTop, bottom: clipBottom, position: 0.5)];
  }

  final height = gradientBottom - gradientTop;
  // Fixed 24-way quantisation leaves roughly 5 px stripes at the normal
  // 1080p lyric size. Keep smooth bands close to two output pixels while
  // bounding event growth for unusually large text.
  final bandCount = (height / 2).ceil().clamp(24, 96);
  final boundaries = <double>{
    if (smooth)
      for (var index = 0; index <= bandCount; index++) index / bandCount
    else ...{0.0, 1.0},
    ...breakpoints.map((value) => value.clamp(0.0, 1.0)),
  }.toList()..sort();
  return List.generate(boundaries.length - 1, (index) {
    final start = boundaries[index];
    final end = boundaries[index + 1];
    final top = index == 0 ? clipTop : gradientTop + height * start;
    final bottom = index == boundaries.length - 2
        ? clipBottom
        : gradientTop + height * end;
    return _GradientBand(top: top, bottom: bottom, position: (start + end) / 2);
  });
}

void _writeGlowLayers({
  required StringBuffer sb,
  required String rawText,
  required String style,
  required String alignmentTag,
  required double posX,
  required double posY,
  required double visualY,
  required double fontSize,
  required double baseOutlineWidth,
  required double decorationWidth,
  required int blurLevel,
  required int tStart,
  required int tEnd,
  required Duration displayStart,
  required Duration displayEnd,
  required AssColorValue color,
  required bool fadesIn,
}) {
  if (decorationWidth <= 0) return;

  final hasGradient = color.isGradient;
  final gradientRange = _n3GradientRange(
    centerY: visualY,
    fontSize: fontSize,
    outlineWidth: baseOutlineWidth,
  );
  final bands = _gradientBands(
    clipTop: visualY - fontSize * 1.5,
    clipBottom: visualY + fontSize * 1.5,
    gradientTop: gradientRange.$1,
    gradientBottom: gradientRange.$2,
    enabled: hasGradient,
    // N3 blurs the complete mille-feuille result. It therefore needs dense
    // sampling here even though the source brush itself has hard stops.
    smooth: true,
    breakpoints: color.effectiveStops.map((stop) => stop.position),
  );
  final numLayers = blurLevel + 1;

  for (int layerIndex = 0; layerIndex < numLayers; layerIndex++) {
    final layerWidth =
        decorationWidth - layerIndex * decorationWidth / numLayers;
    final borderWidth = baseOutlineWidth + layerWidth / 2;

    for (final band in bands) {
      final sampledColor = _blurredColorAt(
        color,
        band.position,
        layerWidth / (gradientRange.$2 - gradientRange.$1),
      );
      final assColor = _colorToAss(sampledColor);
      final clipTag = hasGradient
          ? '\\clip(0,${band.top.toStringAsFixed(1)},10000,${band.bottom.toStringAsFixed(1)})'
          : '';
      final initialAlpha = fadesIn ? 'FF' : '00';
      final finalAlpha = fadesIn ? '00' : 'FF';
      final tags =
          '\\1c$assColor\\3c$assColor'
          '\\1a&H$initialAlpha&\\3a&H$initialAlpha&'
          '\\bord${borderWidth.toStringAsFixed(1)}'
          '\\blur${layerWidth.toStringAsFixed(1)}'
          '$clipTag'
          '\\t($tStart,$tEnd,\\1a&H$finalAlpha&\\3a&H$finalAlpha&)';

      sb.writeln(
        'Dialogue: 0,${_formatTime(displayStart)},${_formatTime(displayEnd)},$style,,0,0,0,,{$alignmentTag\\pos(${posX.toStringAsFixed(1)},${posY.toStringAsFixed(1)})$tags}$rawText',
      );
    }
  }
}

String _buildSegmentedSweepTags({
  required bool reverse,
  required double fullLeft,
  required double fullRight,
  required double initialX,
  required double top,
  required double bottom,
  required List<_WipeSegment> segments,
  required int tEnd,
}) {
  String clip(double left, double right) =>
      '\\clip(${left.toStringAsFixed(1)},${top.toStringAsFixed(1)},${right.toStringAsFixed(1)},${bottom.toStringAsFixed(1)})';

  final tags = StringBuffer(
    reverse ? clip(fullLeft, fullRight) : clip(initialX, initialX),
  );
  if (segments.isNotEmpty) {
    final first = segments.first;
    tags.write(
      '\\t(${first.start},${first.start + 1},${reverse ? clip(first.left, fullRight) : clip(fullLeft, first.left)})',
    );
    for (final segment in segments) {
      tags.write(
        '\\t(${segment.start + 1},${segment.end},${reverse ? clip(segment.right, fullRight) : clip(fullLeft, segment.right)})',
      );
    }
  }
  tags.write(
    reverse
        ? '\\t($tEnd,${tEnd + 1},\\clip(0,0,0,0))'
        : '\\t($tEnd,${tEnd + 1},${clip(fullLeft, fullRight)})',
  );
  return tags.toString();
}

void _writeGradientSweepDialogue({
  required StringBuffer sb,
  required String rawText,
  required String style,
  required String alignmentTag,
  required double posX,
  required double posY,
  required double visualY,
  required double fontSize,
  required double outlineWidth,
  required AssColorValue textColor,
  required AssColorValue outlineColor,
  required double fullLeft,
  required double fullRight,
  required double initialX,
  required List<_WipeSegment> segments,
  required int tEnd,
  required bool reverse,
  required Duration displayStart,
  required Duration displayEnd,
}) {
  final hasGradient = textColor.isGradient || outlineColor.isGradient;
  final gradientRange = _n3GradientRange(
    centerY: visualY,
    fontSize: fontSize,
    outlineWidth: outlineWidth,
  );
  final bands = _gradientBands(
    clipTop: visualY - fontSize * 1.5,
    clipBottom: visualY + fontSize * 1.5,
    gradientTop: gradientRange.$1,
    gradientBottom: gradientRange.$2,
    enabled: hasGradient,
    smooth:
        textColor.mode == AssColorMode.gradient ||
        outlineColor.mode == AssColorMode.gradient,
    breakpoints: {
      ...textColor.effectiveStops.map((stop) => stop.position),
      ...outlineColor.effectiveStops.map((stop) => stop.position),
    },
  );

  for (final band in bands) {
    final colors =
        '\\1c${_assColorAt(textColor, band.position)}'
        '\\3c${_assColorAt(outlineColor, band.position)}';
    final sweep = _buildSegmentedSweepTags(
      reverse: reverse,
      fullLeft: fullLeft,
      fullRight: fullRight,
      initialX: initialX,
      top: band.top,
      bottom: band.bottom,
      segments: segments,
      tEnd: tEnd,
    );
    sb.writeln(
      'Dialogue: 1,${_formatTime(displayStart)},${_formatTime(displayEnd)},$style,,0,0,0,,{$alignmentTag\\pos(${posX.toStringAsFixed(1)},${posY.toStringAsFixed(1)})$colors$sweep}$rawText',
    );
  }
}

class _GradientBand {
  final double top;
  final double bottom;
  final double position;

  const _GradientBand({
    required this.top,
    required this.bottom,
    required this.position,
  });
}

class _WipeSegment {
  final int start;
  final int end;
  final double left;
  final double right;

  const _WipeSegment({
    required this.start,
    required this.end,
    required this.left,
    required this.right,
  });
}
