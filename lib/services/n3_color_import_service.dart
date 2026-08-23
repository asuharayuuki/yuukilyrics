import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/color_preset_asset.dart';

class N3ColorImportService {
  static const _brushIndexes = [0, 1, 3, 4, 5, 7];

  List<ColorPresetAsset> importBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final projectEntry = archive
        .where((entry) => entry.isFile && entry.name == '0')
        .firstOrNull;
    if (projectEntry == null || projectEntry.size > 64 * 1024 * 1024) {
      throw const FormatException(
        'Invalid N3 project: project data is missing.',
      );
    }
    var projectJson = utf8.decode(projectEntry.content, allowMalformed: false);
    if (projectJson.startsWith('\uFEFF')) {
      projectJson = projectJson.substring(1);
    }
    final decoded = jsonDecode(projectJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid N3 project data.');
    }
    final fonts = decoded['LyricsFonts'];
    if (fonts is! List) {
      throw const FormatException('N3 color settings are missing.');
    }

    final result = <ColorPresetAsset>[];
    final usedNames = <String>{};
    for (var index = 0; index < fonts.length; index++) {
      final font = fonts[index];
      if (font is! Map<String, dynamic>) continue;
      final brushes = font['BrushInfos'];
      if (brushes is! List || brushes.length < 8) continue;
      final colors = <ColorPresetValue>[];
      for (final brushIndex in _brushIndexes) {
        final brush = brushes[brushIndex];
        if (brush is! Map<String, dynamic>) {
          throw FormatException(
            'Invalid brush $brushIndex in N3 color settings.',
          );
        }
        colors.add(_parseBrush(brush));
      }
      var name = (font['SettingsName'] as String?)?.trim() ?? '';
      if (name.isEmpty) name = 'N3 ${index + 1}';
      final baseName = name;
      var suffix = 2;
      while (!usedNames.add(name.toLowerCase())) {
        name = '$baseName ($suffix)';
        suffix++;
      }
      result.add(
        ColorPresetAsset(
          name: name,
          sungTextColor: colors[0],
          sungOutlineColor: colors[1],
          sungDecorationColor: colors[2],
          unsungTextColor: colors[3],
          unsungOutlineColor: colors[4],
          unsungDecorationColor: colors[5],
        ),
      );
    }
    if (result.isEmpty) {
      throw const FormatException('No N3 color settings were found.');
    }
    return result;
  }

  ColorPresetValue _parseBrush(Map<String, dynamic> brush) {
    final type = (brush['SelectedBrushTypeIndex'] as num?)?.toInt() ?? 0;
    if (type == 0) return ColorPresetValue.solid(_parseSolidColor(brush));
    final rawStops = brush['GradientStops'];
    if (rawStops is! List || rawStops.isEmpty) {
      return ColorPresetValue.solid(_parseSolidColor(brush));
    }
    final stops = <ColorPresetStop>[];
    for (final rawStop in rawStops) {
      if (rawStop is! Map<String, dynamic>) continue;
      final position = (rawStop['Position'] as num?)?.toDouble();
      final color = rawStop['Color'];
      if (position == null || color is! Map<String, dynamic>) continue;
      stops.add(
        ColorPresetStop(position: position, color: _parseFloatColor(color)),
      );
    }
    if (stops.isEmpty) return ColorPresetValue.solid(_parseSolidColor(brush));
    return ColorPresetValue.withStops(
      mode: type == 2 ? ColorFillMode.millefeuille : ColorFillMode.gradient,
      stops: stops,
    );
  }

  int _parseSolidColor(Map<String, dynamic> brush) {
    final solid = brush['SolidColor'];
    if (solid is Map<String, dynamic>) {
      final web16 = solid['Web16'];
      if (web16 is String && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(web16)) {
        return 0xFF000000 | int.parse(web16, radix: 16);
      }
      final dxColor = solid['DxColor'];
      if (dxColor is Map<String, dynamic>) {
        return _parseFloatColor(dxColor);
      }
    }
    throw const FormatException('Invalid N3 solid color.');
  }

  int _parseFloatColor(Map<String, dynamic> color) {
    int channel(String name) {
      final value = (color[name] as num?)?.toDouble();
      if (value == null) {
        throw FormatException('Invalid N3 color channel $name.');
      }
      return (value.clamp(0.0, 1.0) * 255).round();
    }

    return 0xFF000000 | channel('R') << 16 | channel('G') << 8 | channel('B');
  }
}
