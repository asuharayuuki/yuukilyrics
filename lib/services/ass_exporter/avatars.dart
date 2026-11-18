part of '../ass_exporter.dart';

// Singer avatar loading, vector tracing and palette extraction.

class _AssAvatarLayer {
  final Color color;
  final int opacity;
  final String drawing;

  const _AssAvatarLayer({
    required this.color,
    required this.opacity,
    required this.drawing,
  });
}

class _AssAvatarDrawing {
  final double width;
  final double height;
  final double drawingScale;
  final List<_AssAvatarLayer> layers;

  const _AssAvatarDrawing({
    required this.width,
    required this.height,
    required this.drawingScale,
    required this.layers,
  });
}

class _AvatarColorSample {
  final int red;
  final int green;
  final int blue;
  final int weight;
  final double lightness;
  final double greenRed;
  final double blueYellow;

  const _AvatarColorSample({
    required this.red,
    required this.green,
    required this.blue,
    required this.weight,
    required this.lightness,
    required this.greenRed,
    required this.blueYellow,
  });

  int get rgb => (red << 16) | (green << 8) | blue;
}

class _AvatarColorBox {
  final List<_AvatarColorSample> samples;
  final int totalWeight;
  final double lightnessRange;
  final double greenRedRange;
  final double blueYellowRange;

  _AvatarColorBox(this.samples)
    : totalWeight = samples.fold(0, (sum, sample) => sum + sample.weight),
      lightnessRange = _rangeOf(samples, (sample) => sample.lightness),
      greenRedRange = _rangeOf(samples, (sample) => sample.greenRed),
      blueYellowRange = _rangeOf(samples, (sample) => sample.blueYellow);

  double get widestRange =>
      max(lightnessRange, max(greenRedRange, blueYellowRange));

  static double _rangeOf(
    List<_AvatarColorSample> samples,
    double Function(_AvatarColorSample sample) component,
  ) {
    if (samples.length < 2) return 0;
    var minimum = component(samples.first);
    var maximum = minimum;
    for (final sample in samples.skip(1)) {
      final value = component(sample);
      if (value < minimum) minimum = value;
      if (value > maximum) maximum = value;
    }
    return maximum - minimum;
  }
}

class _AvatarPaletteColor {
  final int red;
  final int green;
  final int blue;
  final double lightness;
  final double greenRed;
  final double blueYellow;

  const _AvatarPaletteColor({
    required this.red,
    required this.green,
    required this.blue,
    required this.lightness,
    required this.greenRed,
    required this.blueYellow,
  });

  int get rgb => (red << 16) | (green << 8) | blue;
}

double _resolveSingerAvatarSize(AssExportSettings settings) =>
    settings.singerAvatarSize?.toDouble() ?? settings.fontSize * 0.6;

Future<Map<String, _AssAvatarDrawing>> _loadSingerAvatarDrawings(
  AssExportSettings settings,
) async {
  if (settings.singerAvatarPaths.isEmpty) return const {};
  final result = <String, _AssAvatarDrawing>{};
  final targetSize = _resolveSingerAvatarSize(settings);
  final referencedSingers = <String>{
    for (final singer in settings.singerColors)
      for (final part in singer.prefix.split('/'))
        if (part.trim().isNotEmpty) part.trim(),
  };
  for (final entry in settings.singerAvatarPaths.entries) {
    if (!referencedSingers.contains(entry.key)) continue;
    try {
      final drawing = await _decodeAvatarDrawing(entry.value, targetSize);
      if (drawing != null) result[entry.key] = drawing;
    } catch (_) {
      // A missing or damaged external file must not abort subtitle export.
    }
  }
  return result;
}

Future<_AssAvatarDrawing?> _decodeAvatarDrawing(
  String path,
  double requestedSize,
) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();

  ui.Codec? sourceCodec;
  ui.Image? sourceImage;
  try {
    sourceCodec = await ui.instantiateImageCodec(bytes);
    final frame = await sourceCodec.getNextFrame();
    sourceImage = frame.image;
    final sourceWidth = sourceImage.width;
    final sourceHeight = sourceImage.height;
    if (sourceWidth <= 0 || sourceHeight <= 0) return null;

    // ASS cannot embed a bitmap. Keep one drawing cell per output pixel so
    // small facial features survive conversion; a coarser pixel-art grid
    // merges eyes, mouth, and hair lines at normal avatar sizes.
    final sampleLongSide = min(
      requestedSize.round(),
      160,
    ).clamp(24, 160).toInt();
    final isWide = sourceWidth >= sourceHeight;
    final sampleWidth = isWide
        ? sampleLongSide
        : max(1, (sampleLongSide * sourceWidth / sourceHeight).round());
    final sampleHeight = isWide
        ? max(1, (sampleLongSide * sourceHeight / sourceWidth).round())
        : sampleLongSide;

    // Use high-quality downsampling at the final 1:1 drawing density. Pure
    // nearest-neighbour sampling preserves detail but makes diagonal hair
    // lines and circular silhouettes look harsh; medium filtering smooths
    // those contours without returning to the former low-resolution grid.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      sourceImage,
      Rect.fromLTWH(0, 0, sourceWidth.toDouble(), sourceHeight.toDouble()),
      Rect.fromLTWH(0, 0, sampleWidth.toDouble(), sampleHeight.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(sampleWidth, sampleHeight);
    picture.dispose();
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      image.dispose();
      return null;
    }

    final colorWeights = <int, int>{};
    for (var offset = 0; offset < rgba.lengthInBytes; offset += 4) {
      final alpha = rgba.getUint8(offset + 3);
      // Discard only effectively invisible pixels. Partially covered edge
      // pixels are retained below as a few alpha levels so circular avatars
      // remain smooth on both light and dark video backgrounds.
      if (alpha < 16) continue;
      final rgb =
          (rgba.getUint8(offset) << 16) |
          (rgba.getUint8(offset + 1) << 8) |
          rgba.getUint8(offset + 2);
      colorWeights.update(
        rgb,
        (weight) => weight + alpha,
        ifAbsent: () => alpha,
      );
    }
    // Preserve enough tones for facial features and fine line art. This is
    // still bounded to keep the number of ASS dialogue layers manageable.
    final palette = _buildAvatarPalette(colorWeights, maxColors: 128);
    final backingPalette = _buildAvatarPalette(colorWeights, maxColors: 16);
    final colorCache = <int, int>{};
    final backingColorCache = <int, int>{};
    final pathsByColor = <int, StringBuffer>{};
    final backingPathsByColor = <int, StringBuffer>{};
    final silhouette = StringBuffer();
    for (var y = 0; y < image.height; y++) {
      var x = 0;
      while (x < image.width) {
        final offset = (y * image.width + x) * 4;
        final key = _adaptiveAvatarColorKey(
          rgba.getUint8(offset),
          rgba.getUint8(offset + 1),
          rgba.getUint8(offset + 2),
          rgba.getUint8(offset + 3),
          palette,
          colorCache,
        );
        var runEnd = x + 1;
        while (runEnd < image.width) {
          final nextOffset = (y * image.width + runEnd) * 4;
          final nextKey = _adaptiveAvatarColorKey(
            rgba.getUint8(nextOffset),
            rgba.getUint8(nextOffset + 1),
            rgba.getUint8(nextOffset + 2),
            rgba.getUint8(nextOffset + 3),
            palette,
            colorCache,
          );
          if (nextKey != key) break;
          runEnd++;
        }
        if (key != 0) {
          final rectangle =
              'm $x $y l $runEnd $y $runEnd ${y + 1} $x ${y + 1} ';
          silhouette.write(rectangle);
          final backingKey = _adaptiveAvatarColorKey(
            rgba.getUint8(offset),
            rgba.getUint8(offset + 1),
            rgba.getUint8(offset + 2),
            255,
            backingPalette,
            backingColorCache,
          );
          backingPathsByColor
              .putIfAbsent(backingKey, StringBuffer.new)
              .write(rectangle);
          pathsByColor.putIfAbsent(key, StringBuffer.new).write(rectangle);
        }
        x = runEnd;
      }
    }

    final layers = <_AssAvatarLayer>[];
    for (final entry in pathsByColor.entries) {
      final key = entry.key;
      final opacity = (key >> 24) & 0xFF;
      final red = (key >> 16) & 0xFF;
      final green = (key >> 8) & 0xFF;
      final blue = key & 0xFF;
      layers.add(
        _AssAvatarLayer(
          color: Color.fromARGB(255, red, green, blue),
          opacity: opacity,
          drawing: entry.value.toString().trimRight(),
        ),
      );
    }
    layers.sort((a, b) => a.opacity.compareTo(b.opacity));
    if (silhouette.isNotEmpty && colorWeights.isNotEmpty) {
      // libass anti-aliases every independently coloured vector layer. At
      // shared pixel boundaries that used to expose the video underneath,
      // making an otherwise opaque avatar look grey and peppered with dark
      // dots. Paint an opaque silhouette and a small local-colour backing
      // palette first so only the avatar's outer edge can blend with the
      // video while dark clothing, skin, and hair keep their own base tones.
      var totalWeight = 0;
      var weightedRed = 0;
      var weightedGreen = 0;
      var weightedBlue = 0;
      for (final entry in colorWeights.entries) {
        final weight = entry.value;
        totalWeight += weight;
        weightedRed += ((entry.key >> 16) & 0xFF) * weight;
        weightedGreen += ((entry.key >> 8) & 0xFF) * weight;
        weightedBlue += (entry.key & 0xFF) * weight;
      }
      final backingLayers = <_AssAvatarLayer>[
        _AssAvatarLayer(
          color: Color.fromARGB(
            255,
            (weightedRed / totalWeight).round(),
            (weightedGreen / totalWeight).round(),
            (weightedBlue / totalWeight).round(),
          ),
          opacity: 255,
          drawing: silhouette.toString().trimRight(),
        ),
        for (final entry in backingPathsByColor.entries)
          _AssAvatarLayer(
            color: Color.fromARGB(
              255,
              (entry.key >> 16) & 0xFF,
              (entry.key >> 8) & 0xFF,
              entry.key & 0xFF,
            ),
            opacity: 255,
            drawing: entry.value.toString().trimRight(),
          ),
      ];
      layers.insertAll(0, backingLayers);
    }

    // Keep the ASS drawing scale integral. Fractional scaling would place
    // cell boundaries between output pixels and make libass anti-alias them.
    final drawingScale = max(
      1,
      (requestedSize / max(image.width, image.height)).round(),
    ).toDouble();
    final drawing = _AssAvatarDrawing(
      width: image.width * drawingScale,
      height: image.height * drawingScale,
      drawingScale: drawingScale,
      layers: layers,
    );
    image.dispose();
    return drawing;
  } finally {
    sourceImage?.dispose();
    sourceCodec?.dispose();
  }
}

List<_AvatarPaletteColor> _buildAvatarPalette(
  Map<int, int> colorWeights, {
  required int maxColors,
}) {
  if (colorWeights.isEmpty) return const [];
  final samples = colorWeights.entries
      .map((entry) => _avatarColorSample(entry.key, entry.value))
      .toList();
  if (samples.length <= maxColors) {
    samples.sort((a, b) => b.weight.compareTo(a.weight));
    return samples.map(_paletteColorFromSample).toList(growable: false);
  }

  final boxes = <_AvatarColorBox>[_AvatarColorBox(samples)];
  while (boxes.length < maxColors) {
    var bestIndex = -1;
    var bestScore = -1.0;
    for (var index = 0; index < boxes.length; index++) {
      final box = boxes[index];
      if (box.samples.length < 2 || box.widestRange <= 0) continue;
      final score = box.widestRange * (1 + log(box.totalWeight));
      if (score > bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    if (bestIndex < 0) break;

    final split = _splitAvatarColorBox(boxes.removeAt(bestIndex));
    if (split == null) break;
    boxes
      ..add(split.$1)
      ..add(split.$2);
  }

  final paletteByRgb = <int, _AvatarPaletteColor>{};
  for (final box in boxes) {
    final representative = _representativeAvatarColor(box);
    paletteByRgb[representative.rgb] = representative;
  }
  return paletteByRgb.values.toList(growable: false);
}

(_AvatarColorBox, _AvatarColorBox)? _splitAvatarColorBox(_AvatarColorBox box) {
  if (box.samples.length < 2) return null;
  final samples = List<_AvatarColorSample>.from(box.samples);
  if (box.lightnessRange >= box.greenRedRange &&
      box.lightnessRange >= box.blueYellowRange) {
    samples.sort((a, b) => a.lightness.compareTo(b.lightness));
  } else if (box.greenRedRange >= box.blueYellowRange) {
    samples.sort((a, b) => a.greenRed.compareTo(b.greenRed));
  } else {
    samples.sort((a, b) => a.blueYellow.compareTo(b.blueYellow));
  }

  final halfWeight = box.totalWeight / 2;
  var accumulatedWeight = 0;
  var splitIndex = 1;
  for (var index = 0; index < samples.length - 1; index++) {
    accumulatedWeight += samples[index].weight;
    splitIndex = index + 1;
    if (accumulatedWeight >= halfWeight) break;
  }
  return (
    _AvatarColorBox(samples.sublist(0, splitIndex)),
    _AvatarColorBox(samples.sublist(splitIndex)),
  );
}

_AvatarPaletteColor _representativeAvatarColor(_AvatarColorBox box) {
  var lightness = 0.0;
  var greenRed = 0.0;
  var blueYellow = 0.0;
  for (final sample in box.samples) {
    lightness += sample.lightness * sample.weight;
    greenRed += sample.greenRed * sample.weight;
    blueYellow += sample.blueYellow * sample.weight;
  }
  lightness /= box.totalWeight;
  greenRed /= box.totalWeight;
  blueYellow /= box.totalWeight;

  var closest = box.samples.first;
  var closestDistance = double.infinity;
  for (final sample in box.samples) {
    final dl = sample.lightness - lightness;
    final da = sample.greenRed - greenRed;
    final db = sample.blueYellow - blueYellow;
    final distance = dl * dl + da * da + db * db;
    if (distance < closestDistance) {
      closest = sample;
      closestDistance = distance;
    }
  }
  return _paletteColorFromSample(closest);
}

int _adaptiveAvatarColorKey(
  int red,
  int green,
  int blue,
  int alpha,
  List<_AvatarPaletteColor> palette,
  Map<int, int> colorCache,
) {
  if (alpha < 16) return 0;
  final sourceRgb = (red << 16) | (green << 8) | blue;
  final targetRgb = colorCache.putIfAbsent(sourceRgb, () {
    if (palette.isEmpty) return sourceRgb;
    final source = _avatarColorSample(sourceRgb, 1);
    var closest = palette.first;
    var closestDistance = double.infinity;
    for (final candidate in palette) {
      final dl = source.lightness - candidate.lightness;
      final da = source.greenRed - candidate.greenRed;
      final db = source.blueYellow - candidate.blueYellow;
      final distance = dl * dl + da * da + db * db;
      if (distance < closestDistance) {
        closest = candidate;
        closestDistance = distance;
      }
    }
    return closest.rgb;
  });
  // Keep the body opaque while retaining a small number of coverage levels
  // for anti-aliased edges. Four levels are enough to smooth silhouettes
  // without making the avatar itself look translucent.
  final quantizedAlpha = alpha >= 224
      ? 255
      : ((alpha + 31) ~/ 64 * 64).clamp(64, 192);
  return (quantizedAlpha << 24) | targetRgb;
}

_AvatarColorSample _avatarColorSample(int rgb, int weight) {
  final red = (rgb >> 16) & 0xFF;
  final green = (rgb >> 8) & 0xFF;
  final blue = rgb & 0xFF;
  final perceptual = _rgbToOklab(red, green, blue);
  return _AvatarColorSample(
    red: red,
    green: green,
    blue: blue,
    weight: weight,
    lightness: perceptual.$1,
    greenRed: perceptual.$2,
    blueYellow: perceptual.$3,
  );
}

_AvatarPaletteColor _paletteColorFromSample(_AvatarColorSample sample) =>
    _AvatarPaletteColor(
      red: sample.red,
      green: sample.green,
      blue: sample.blue,
      lightness: sample.lightness,
      greenRed: sample.greenRed,
      blueYellow: sample.blueYellow,
    );

(double, double, double) _rgbToOklab(int red, int green, int blue) {
  double linear(int value) {
    final channel = value / 255.0;
    return channel <= 0.04045
        ? channel / 12.92
        : pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = linear(red);
  final g = linear(green);
  final b = linear(blue);
  final l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  final m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
  final s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
  final lRoot = pow(l, 1 / 3).toDouble();
  final mRoot = pow(m, 1 / 3).toDouble();
  final sRoot = pow(s, 1 / 3).toDouble();
  return (
    0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
    1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
    0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot,
  );
}
