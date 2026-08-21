import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TypographySettingsData {
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
    'version': 1,
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
    final temporary = File('$path.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
    if (await destination.exists()) await destination.delete();
    await temporary.rename(path);
  }
}
