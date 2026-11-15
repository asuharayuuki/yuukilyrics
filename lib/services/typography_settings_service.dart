import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/font_library_asset.dart';
import 'atomic_file_writer.dart';

class TypographySettingsData {
  final String fontName;
  final String? customFontPath;
  final int fontFaceIndex;
  final String fontDisplayName;
  final String fontStyleName;
  final FontFaceSelection? latinFont;
  final double fontSize;
  final int letterSpacingStep;
  final double decorationWidth;
  final double? fontOutlineWidth;
  final double? rubyFontSize;
  final double? rubyOutlineWidth;
  final double? rubyBaseGap;
  final double? lineSpacing;
  final double lyricsBottomMargin;
  final double? singerAvatarSize;
  final double singerAvatarGap;

  const TypographySettingsData({
    required this.fontName,
    required this.customFontPath,
    required this.fontFaceIndex,
    required this.fontDisplayName,
    required this.fontStyleName,
    this.latinFont,
    required this.fontSize,
    required this.letterSpacingStep,
    required this.decorationWidth,
    required this.fontOutlineWidth,
    required this.rubyFontSize,
    required this.rubyOutlineWidth,
    required this.rubyBaseGap,
    required this.lineSpacing,
    required this.lyricsBottomMargin,
    required this.singerAvatarSize,
    required this.singerAvatarGap,
  });

  factory TypographySettingsData.fromJson(
    Map<String, dynamic> json, {
    required TypographySettingsData fallback,
  }) {
    return TypographySettingsData(
      fontName: _readString(json, 'fontName', fallback.fontName),
      customFontPath: _readOptionalString(
        json,
        'customFontPath',
        fallback.customFontPath,
      ),
      fontFaceIndex: _readInt(
        json,
        'fontFaceIndex',
        fallback.fontFaceIndex,
        0,
        65535,
      ),
      fontDisplayName: _readString(
        json,
        'fontDisplayName',
        fallback.fontDisplayName,
      ),
      fontStyleName: _readString(json, 'fontStyleName', fallback.fontStyleName),
      latinFont: json.containsKey('latinFont')
          ? _readFontSelection(json['latinFont'])
          : fallback.latinFont,
      fontSize: _readDouble(json, 'fontSize', fallback.fontSize, 20, 200),
      letterSpacingStep: _readInt(
        json,
        'letterSpacingStep',
        fallback.letterSpacingStep,
        0,
        41,
      ),
      decorationWidth: _readDouble(
        json,
        'decorationWidth',
        fallback.decorationWidth,
        0,
        30,
      ),
      fontOutlineWidth: _readOptionalDouble(
        json,
        'fontOutlineWidth',
        fallback.fontOutlineWidth,
        0,
        30,
      ),
      rubyFontSize: _readOptionalDouble(
        json,
        'rubyFontSize',
        fallback.rubyFontSize,
        8,
        120,
      ),
      rubyOutlineWidth: _readOptionalDouble(
        json,
        'rubyOutlineWidth',
        fallback.rubyOutlineWidth,
        0,
        30,
      ),
      rubyBaseGap: _readOptionalDouble(
        json,
        'rubyBaseGap',
        fallback.rubyBaseGap,
        -50,
        150,
      ),
      lineSpacing: _readOptionalDouble(
        json,
        'lineSpacing',
        fallback.lineSpacing,
        20,
        600,
      ),
      lyricsBottomMargin: _readDouble(
        json,
        'lyricsBottomMargin',
        fallback.lyricsBottomMargin,
        0,
        400,
      ),
      singerAvatarSize: _readOptionalDouble(
        json,
        'singerAvatarSize',
        fallback.singerAvatarSize,
        24,
        160,
      ),
      singerAvatarGap: _readDouble(
        json,
        'singerAvatarGap',
        fallback.singerAvatarGap,
        -50,
        50,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 2,
    'fontName': fontName,
    'customFontPath': customFontPath,
    'fontFaceIndex': fontFaceIndex,
    'fontDisplayName': fontDisplayName,
    'fontStyleName': fontStyleName,
    'latinFont': switch (latinFont) {
      final font? => {
        'path': font.path,
        'faceIndex': font.faceIndex,
        'displayName': font.displayName,
        'styleName': font.styleName,
      },
      null => null,
    },
    'fontSize': fontSize,
    'letterSpacingStep': letterSpacingStep,
    'decorationWidth': decorationWidth,
    'fontOutlineWidth': fontOutlineWidth,
    'rubyFontSize': rubyFontSize,
    'rubyOutlineWidth': rubyOutlineWidth,
    'rubyBaseGap': rubyBaseGap,
    'lineSpacing': lineSpacing,
    'lyricsBottomMargin': lyricsBottomMargin,
    'singerAvatarSize': singerAvatarSize,
    'singerAvatarGap': singerAvatarGap,
  };

  static FontFaceSelection? _readFontSelection(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final path = _readOptionalString(value, 'path', null);
    final name = _readString(value, 'displayName', '');
    final faceIndex = _readInt(value, 'faceIndex', -1, 0, 65535);
    if (name.isEmpty ||
        faceIndex < 0 ||
        (path == null && faceIndex != 0) ||
        (value['path'] != null && path == null)) {
      return null;
    }
    return FontFaceSelection(
      path: path,
      faceIndex: faceIndex,
      displayName: name,
      styleName: _readString(value, 'styleName', 'Regular'),
    );
  }

  static String _readString(
    Map<String, dynamic> json,
    String key,
    String fallback,
  ) {
    final value = json[key];
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static String? _readOptionalString(
    Map<String, dynamic> json,
    String key,
    String? fallback,
  ) {
    if (!json.containsKey(key)) return fallback;
    final value = json[key];
    if (value == null) return null;
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static double _readDouble(
    Map<String, dynamic> json,
    String key,
    double fallback,
    double min,
    double max,
  ) {
    final value = json[key];
    if (value is! num) return fallback;
    final result = value.toDouble();
    return result.isFinite && result >= min && result <= max
        ? result
        : fallback;
  }

  static int _readInt(
    Map<String, dynamic> json,
    String key,
    int fallback,
    int min,
    int max,
  ) {
    final value = json[key];
    if (value is! num || value != value.roundToDouble()) return fallback;
    final result = value.toInt();
    return result >= min && result <= max ? result : fallback;
  }

  static double? _readOptionalDouble(
    Map<String, dynamic> json,
    String key,
    double? fallback,
    double min,
    double max,
  ) {
    if (!json.containsKey(key)) return fallback;
    final value = json[key];
    if (value == null) return null;
    if (value is! num) return fallback;
    final result = value.toDouble();
    return result.isFinite && result >= min && result <= max
        ? result
        : fallback;
  }
}

class TypographySettingsService {
  String? _filePath;

  Future<String> getFilePath() async {
    if (_filePath != null) return _filePath!;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'yuukilyrics'));
    if (!await directory.exists()) await directory.create(recursive: true);
    _filePath = p.join(directory.path, 'typography_settings.json');
    return _filePath!;
  }

  Future<TypographySettingsData?> load({
    required TypographySettingsData fallback,
  }) async {
    final file = File(await getFilePath());
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    return TypographySettingsData.fromJson(decoded, fallback: fallback);
  }

  Future<void> save(TypographySettingsData settings) async {
    final path = await getFilePath();
    final destination = File(path);
    await AtomicFileWriter.writeString(
      destination,
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }
}
