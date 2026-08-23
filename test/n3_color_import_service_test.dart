import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/color_preset_asset.dart';
import 'package:yuukilyrics/services/n3_color_import_service.dart';

void main() {
  test('imports six N3 brushes and ignores both outline 2 brushes', () {
    Map<String, dynamic> color(String hex) {
      final value = int.parse(hex, radix: 16);
      return {
        'R': ((value >> 16) & 0xFF) / 255,
        'G': ((value >> 8) & 0xFF) / 255,
        'B': (value & 0xFF) / 255,
        'A': 1,
      };
    }

    Map<String, dynamic> solid(String hex) => {
      'SelectedBrushTypeIndex': 0,
      'SolidColor': {'Web16': hex, 'DxColor': color(hex)},
      'GradientStops': <Object>[],
    };

    final brushes = [
      solid('110000'),
      solid('220000'),
      solid('FF00FF'), // sung outline 2: ignored
      solid('330000'),
      solid('440000'),
      solid('550000'),
      solid('00FFFF'), // unsung outline 2: ignored
      {
        'SelectedBrushTypeIndex': 2,
        'SolidColor': {'Web16': '660000', 'DxColor': color('660000')},
        'GradientStops': [
          {'Position': 0, 'Color': color('660000')},
          {'Position': 0.5, 'Color': color('000066')},
        ],
      },
    ];
    final json = jsonEncode({
      'LyricsFonts': [
        {'SettingsName': 'N3 scheme', 'BrushInfos': brushes},
      ],
    });
    final archive = Archive()..add(ArchiveFile.string('0', json));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    final presets = N3ColorImportService().importBytes(bytes);

    expect(presets, hasLength(1));
    final preset = presets.single;
    expect(preset.name, 'N3 scheme');
    expect(preset.sungTextColor.color0, 0xFF110000);
    expect(preset.sungOutlineColor.color0, 0xFF220000);
    expect(preset.sungDecorationColor.color0, 0xFF330000);
    expect(preset.unsungTextColor.color0, 0xFF440000);
    expect(preset.unsungOutlineColor.color0, 0xFF550000);
    expect(preset.unsungDecorationColor.mode, ColorFillMode.millefeuille);
    expect(
      preset.unsungDecorationColor.toMarkdown(),
      'm(0:#660000,50:#000066)',
    );
  });
}
