import '../utils/constants.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../models/lyric_ast.dart';
import '../models/font_library_asset.dart';
import '../models/color_preset_asset.dart';
import '../services/ass_exporter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'ass_preview_screen.dart';

import '../services/font_service.dart';
import '../services/font_library_service.dart';
import '../services/color_preset_library_service.dart';
import '../services/open_type_font.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        FilteringTextInputFormatter,
        FontLoader,
        LengthLimitingTextInputFormatter;
import '../services/ffmpeg_service.dart';
import '../services/singer_avatar_library_service.dart';
import '../services/typography_settings_service.dart';
import 'dart:math';
import '../l10n/l10n.dart';
import '../widgets/font_face_preview_text.dart';
import '../widgets/dual_color_preview.dart';
import '../widgets/saved_color_presets_dialog.dart';

class _FontLibraryChoice {
  final FontLibraryAsset? asset;
  final int? faceIndex;
  final bool useBuiltIn;
  final bool openManager;

  const _FontLibraryChoice.asset(this.asset, this.faceIndex)
    : useBuiltIn = false,
      openManager = false;

  const _FontLibraryChoice.builtIn()
    : asset = null,
      faceIndex = null,
      useBuiltIn = true,
      openManager = false;

  const _FontLibraryChoice.manage()
    : asset = null,
      faceIndex = null,
      useBuiltIn = false,
      openManager = true;
}

String _fontFamilyLabel(OpenTypeFontFaceInfo face) {
  final familyName = face.familyName.trim();
  return familyName.isEmpty ? face.displayName : familyName;
}

String _fontStyleLabel(OpenTypeFontFaceInfo face) {
  final styleName = face.subfamilyName.trim();
  return styleName.isEmpty ? 'Regular' : styleName;
}

enum AssPagingMode { auto2Lines, emptyLineDelimited }

enum AssLineAlignment { left, center, right }

const List<AssLineAlignment> kDefaultTwoLineAlignments = [
  AssLineAlignment.left,
  AssLineAlignment.right,
];

const List<AssLineAlignment> kDefaultThreeLineAlignments = [
  AssLineAlignment.left,
  AssLineAlignment.right,
  AssLineAlignment.center,
];

const List<AssLineAlignment> kDefaultFourLineAlignments = [
  AssLineAlignment.left,
  AssLineAlignment.right,
  AssLineAlignment.left,
  AssLineAlignment.right,
];

enum AssColorMode { solid, gradient }

enum SingerColorPreset {
  none,
  blue,
  standard,
  chorus,
  blue2,
  purple,
  bluePurple,
  ciel,
  sooda,
  kusou,
  lachenalia,
}

@immutable
class AssColorValue {
  final AssColorMode mode;
  final Color color0;
  final Color color100;

  const AssColorValue.solid(Color color)
    : mode = AssColorMode.solid,
      color0 = color,
      color100 = color;

  const AssColorValue.gradient({required this.color0, required this.color100})
    : mode = AssColorMode.gradient;

  bool get isGradient => mode == AssColorMode.gradient;
}

class SingerColorInfo {
  String prefix;
  SingerColorPreset preset;
  AssColorValue sungTextColor;
  AssColorValue sungOutlineColor;
  AssColorValue sungDecorationColor;
  AssColorValue unsungTextColor;
  AssColorValue unsungOutlineColor;
  AssColorValue unsungDecorationColor;

  SingerColorInfo({
    required this.prefix,
    this.preset = SingerColorPreset.none,
    required this.sungTextColor,
    required this.sungOutlineColor,
    required this.sungDecorationColor,
    required this.unsungTextColor,
    required this.unsungOutlineColor,
    required this.unsungDecorationColor,
  });

  SingerColorInfo copy() {
    return SingerColorInfo(
      prefix: prefix,
      preset: preset,
      sungTextColor: sungTextColor,
      sungOutlineColor: sungOutlineColor,
      sungDecorationColor: sungDecorationColor,
      unsungTextColor: unsungTextColor,
      unsungOutlineColor: unsungOutlineColor,
      unsungDecorationColor: unsungDecorationColor,
    );
  }
}

@immutable
class _SingerColorImportParseResult {
  final List<SingerColorInfo> singers;
  final int validLineCount;
  final List<String> errors;

  const _SingerColorImportParseResult({
    required this.singers,
    required this.validLineCount,
    required this.errors,
  });

  int get duplicateCount => validLineCount - singers.length;
}

_SingerColorImportParseResult _parseSingerColorText(
  String source,
  AppLocalizations l10n,
) {
  final singersByName = <String, SingerColorInfo>{};
  final errors = <String>[];
  var validLineCount = 0;
  final lines = source.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'));

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty) continue;

    final fields = _splitSingerColorImportLine(line);
    if (fields == null) {
      errors.add(l10n.singerColorImportSplitError(index + 1));
      continue;
    }
    if (_isSingerColorImportHeader(fields) || _isMarkdownSeparatorRow(fields)) {
      continue;
    }
    if (fields.length != 7) {
      errors.add(
        l10n.singerColorImportColumnCountError(index + 1, fields.length),
      );
      continue;
    }

    final singerName = fields.first.trim();
    if (singerName.isEmpty) {
      errors.add(l10n.singerColorImportSingerRequired(index + 1));
      continue;
    }

    final colors = <AssColorValue>[];
    var invalidColorIndex = -1;
    for (var colorIndex = 1; colorIndex < fields.length; colorIndex++) {
      final color = _tryParseSingerColorValue(fields[colorIndex]);
      if (color == null) {
        invalidColorIndex = colorIndex;
        break;
      }
      colors.add(color);
    }
    if (invalidColorIndex >= 0) {
      final colorNames = [
        '',
        l10n.sungTextColor,
        l10n.sungOutlineColor,
        l10n.sungDecorationColor,
        l10n.unsungTextColor,
        l10n.unsungOutlineColor,
        l10n.unsungDecorationColor,
      ];
      errors.add(
        l10n.singerColorImportInvalidColor(
          index + 1,
          colorNames[invalidColorIndex],
          fields[invalidColorIndex],
        ),
      );
      continue;
    }

    validLineCount++;
    singersByName[singerName] = SingerColorInfo(
      prefix: singerName,
      preset: SingerColorPreset.none,
      sungTextColor: colors[0],
      sungOutlineColor: colors[1],
      sungDecorationColor: colors[2],
      unsungTextColor: colors[3],
      unsungOutlineColor: colors[4],
      unsungDecorationColor: colors[5],
    );
  }

  return _SingerColorImportParseResult(
    singers: singersByName.values.toList(),
    validLineCount: validLineCount,
    errors: errors,
  );
}

List<String>? _splitSingerColorImportLine(String line) {
  if (line.contains('\t')) {
    return line.split('\t').map((field) => field.trim()).toList();
  }
  if (!line.contains('|')) return null;

  var content = line;
  if (content.startsWith('|')) content = content.substring(1);
  if (content.endsWith('|')) content = content.substring(0, content.length - 1);
  return content.split('|').map((field) => field.trim()).toList();
}

bool _isSingerColorImportHeader(List<String> fields) {
  if (fields.length != 7) return false;
  final first = fields.first
      .replaceAll('*', '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();
  return first == '歌手' ||
      first == '歌手名称' ||
      first == '歌手名' ||
      first == 'プリセット名' ||
      first == '预设名称' ||
      first == 'singer';
}

bool _isMarkdownSeparatorRow(List<String> fields) {
  if (fields.length != 7) return false;
  return fields.every((field) {
    final separator = field.replaceAll(':', '').trim();
    return RegExp(r'^-{3,}$').hasMatch(separator);
  });
}

AssColorValue? _tryParseSingerColorValue(String source) {
  final value = source.trim();
  final match = RegExp(
    r'^#([0-9a-fA-F]{6})(?:/#([0-9a-fA-F]{6}))?$',
  ).firstMatch(value);
  if (match == null) return null;

  Color parseColor(String hex) => Color(0xFF000000 | int.parse(hex, radix: 16));
  final topColor = parseColor(match.group(1)!);
  final bottomHex = match.group(2);
  if (bottomHex == null) return AssColorValue.solid(topColor);
  return AssColorValue.gradient(
    color0: topColor,
    color100: parseColor(bottomHex),
  );
}

@immutable
class _SingerColorPalette {
  final AssColorValue sungTextColor;
  final AssColorValue sungOutlineColor;
  final AssColorValue sungDecorationColor;
  final AssColorValue unsungTextColor;
  final AssColorValue unsungOutlineColor;
  final AssColorValue unsungDecorationColor;

  const _SingerColorPalette({
    required this.sungTextColor,
    required this.sungOutlineColor,
    required this.sungDecorationColor,
    required this.unsungTextColor,
    required this.unsungOutlineColor,
    required this.unsungDecorationColor,
  });
}

class AssExportSettings {
  final String fontName;
  final String? customFontPath;
  final int fontFaceIndex;
  final bool isBold;
  final List<SingerColorInfo> singerColors;
  final bool showSingerPrefixesInAss;
  final AssColorValue sungTextColor;
  final AssColorValue sungOutlineColor;
  final AssColorValue sungDecorationColor;
  final AssColorValue unsungTextColor;
  final AssColorValue unsungOutlineColor;
  final AssColorValue unsungDecorationColor;
  final int fontSize;
  final double? letterSpacingEm;
  final AssPagingMode pagingMode;
  final List<AssLineAlignment> twoLineAlignments;
  final List<AssLineAlignment> threeLineAlignments;
  final List<AssLineAlignment> fourLineAlignments;
  final int interludeThresholdSeconds;
  final int horizontalMargin;
  final int outlineWidth;
  final int? fontOutlineWidth;
  final int? rubyFontSize;
  final int? rubyOutlineWidth;
  final int? rubyBaseGap;
  final int? lineSpacing;
  final int lyricsBottomMargin;
  final int? singerAvatarSize;
  final int singerAvatarGap;
  final Map<String, String> singerAvatarPaths;
  final int blurLevel;
  final int resolutionHeight;

  AssExportSettings({
    required this.fontName,
    this.customFontPath,
    this.fontFaceIndex = 0,
    required this.isBold,
    required this.singerColors,
    required this.showSingerPrefixesInAss,
    required this.sungTextColor,
    required this.sungOutlineColor,
    required this.sungDecorationColor,
    required this.unsungTextColor,
    required this.unsungOutlineColor,
    required this.unsungDecorationColor,
    required this.fontSize,
    this.letterSpacingEm,
    required this.pagingMode,
    this.twoLineAlignments = kDefaultTwoLineAlignments,
    this.threeLineAlignments = kDefaultThreeLineAlignments,
    this.fourLineAlignments = kDefaultFourLineAlignments,
    required this.interludeThresholdSeconds,
    required this.horizontalMargin,
    required this.outlineWidth,
    this.fontOutlineWidth,
    this.rubyFontSize,
    this.rubyOutlineWidth,
    this.rubyBaseGap,
    this.lineSpacing,
    this.lyricsBottomMargin = 50,
    this.singerAvatarSize,
    this.singerAvatarGap = 0,
    this.singerAvatarPaths = const {},
    required this.blurLevel,
    required this.resolutionHeight,
  });
}

class AssExportPageState {
  final TypographySettingsService _typographySettingsService =
      TypographySettingsService();
  int _typographyRevision = 0;
  String? _customFontPath;
  String _fontName = FontService.bundledFontFamily;
  String _fontDisplayName = FontService.bundledFontFamily;
  String _fontStyleName = 'Regular';
  int _fontFaceIndex = 0;
  bool _isBold = true;
  final List<SingerColorInfo> _singerColors = [];
  bool _showSingerPrefixesInAss = false;
  AssColorValue _sungTextColor = const AssColorValue.solid(Color(0xFF0000AF));
  AssColorValue _sungOutlineColor = const AssColorValue.solid(
    Color(0xFFFFFFFF),
  );
  AssColorValue _sungDecorationColor = const AssColorValue.solid(
    Color(0xFFFFE196),
  );
  AssColorValue _unsungTextColor = const AssColorValue.solid(Color(0xFFFFFFFF));
  AssColorValue _unsungOutlineColor = const AssColorValue.solid(
    Color(0xFF000000),
  );
  AssColorValue _unsungDecorationColor = const AssColorValue.solid(
    Color(0xFF96BFFF),
  );
  SingerColorPreset _defaultColorPreset = SingerColorPreset.none;
  double _fontSize = 85.0;
  int _letterSpacingStep = 0;
  double _outlineWidth = 10.0;
  double? _fontOutlineWidth;
  double? _rubyFontSize;
  double? _rubyOutlineWidth;
  double? _rubyBaseGap;
  double? _lineSpacing;
  double _lyricsBottomMargin = 50.0;
  double? _singerAvatarSize;
  double _singerAvatarGap = 0.0;
  int _blurLevel = 0;
  int _resolutionHeight = 1080;
  String _resolutionText = '1080';
  String? _sourceResolutionPath;
  AssPagingMode _pagingMode = AssPagingMode.auto2Lines;
  List<AssLineAlignment> _twoLineAlignments = kDefaultTwoLineAlignments;
  List<AssLineAlignment> _threeLineAlignments = kDefaultThreeLineAlignments;
  List<AssLineAlignment> _fourLineAlignments = kDefaultFourLineAlignments;
  double _interludeThreshold = 10.0;
  int _horizontalMargin = 100;
  int? _baselineResolutionHeight;

  TypographySettingsData get _typographySettings => TypographySettingsData(
    fontSize: _fontSize,
    letterSpacingStep: _letterSpacingStep,
    decorationWidth: _outlineWidth,
    fontOutlineWidth: _fontOutlineWidth,
    rubyFontSize: _rubyFontSize,
    rubyOutlineWidth: _rubyOutlineWidth,
    rubyBaseGap: _rubyBaseGap,
    lineSpacing: _lineSpacing,
    lyricsBottomMargin: _lyricsBottomMargin,
    singerAvatarSize: _singerAvatarSize,
    singerAvatarGap: _singerAvatarGap,
  );

  Future<bool> loadTypographySettings() async {
    final revision = _typographyRevision;
    try {
      final loaded = await _typographySettingsService.load(
        fallback: _typographySettings,
      );
      if (loaded == null || revision != _typographyRevision) return false;
      _setTypographySettings(loaded);
      return true;
    } catch (error) {
      debugPrint('Failed to load typography settings: $error');
      return false;
    }
  }

  void applyTypographySettings(TypographySettingsData settings) {
    _typographyRevision++;
    _setTypographySettings(settings);
    unawaited(_saveTypographySettings(settings));
  }

  void _setTypographySettings(TypographySettingsData settings) {
    _fontSize = settings.fontSize;
    _letterSpacingStep = settings.letterSpacingStep;
    _outlineWidth = settings.decorationWidth;
    _fontOutlineWidth = settings.fontOutlineWidth;
    _rubyFontSize = settings.rubyFontSize;
    _rubyOutlineWidth = settings.rubyOutlineWidth;
    _rubyBaseGap = settings.rubyBaseGap;
    _lineSpacing = settings.lineSpacing;
    _lyricsBottomMargin = settings.lyricsBottomMargin;
    _singerAvatarSize = settings.singerAvatarSize;
    _singerAvatarGap = settings.singerAvatarGap;
  }

  Future<void> _saveTypographySettings(TypographySettingsData settings) async {
    try {
      await _typographySettingsService.save(settings);
    } catch (error) {
      debugPrint('Failed to save typography settings: $error');
    }
  }
}

class AssExportScreen extends StatefulWidget {
  final Widget? drawer;
  final Future<void> Function(AssExportSettings settings) onExport;
  final Future<void> Function(AssExportSettings settings)? onExportVideo;
  final String? mediaFilePath;
  final LyricDocument? document;
  final SingerAvatarLibraryService avatarLibrary;
  final FontLibraryService fontLibrary;
  final ColorPresetLibraryService colorPresetLibrary;
  final AssExportPageState pageState;
  final VoidCallback? onManageFonts;

  const AssExportScreen({
    super.key,
    this.drawer,
    required this.onExport,
    this.onExportVideo,
    this.mediaFilePath,
    this.document,
    required this.avatarLibrary,
    required this.fontLibrary,
    required this.colorPresetLibrary,
    required this.pageState,
    this.onManageFonts,
  });

  @override
  State<AssExportScreen> createState() => _AssExportScreenState();
}

class _AssExportScreenState extends State<AssExportScreen> {
  static const Map<SingerColorPreset, _SingerColorPalette> _singerColorPresets =
      {
        SingerColorPreset.blue: _SingerColorPalette(
          sungTextColor: AssColorValue.solid(Color(0xFF0000AF)),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFFE1E196)),
          unsungTextColor: AssColorValue.solid(Color(0xFFE1E1FF)),
          unsungOutlineColor: AssColorValue.solid(Color(0xFF000000)),
          unsungDecorationColor: AssColorValue.solid(Color(0xFF96BFFF)),
        ),
        SingerColorPreset.standard: _SingerColorPalette(
          sungTextColor: AssColorValue.solid(Color(0xFFEB0000)),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFFE1E196)),
          unsungTextColor: AssColorValue.solid(Color(0xFFFFEBEB)),
          unsungOutlineColor: AssColorValue.solid(Color(0xFF030303)),
          unsungDecorationColor: AssColorValue.solid(Color(0xFFE19696)),
        ),
        SingerColorPreset.chorus: _SingerColorPalette(
          sungTextColor: AssColorValue.solid(Color(0xFFFF9B00)),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFFFFE19B)),
          unsungTextColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          unsungOutlineColor: AssColorValue.solid(Color(0xFF3C2300)),
          unsungDecorationColor: AssColorValue.solid(Color(0xFFFFE19B)),
        ),
        SingerColorPreset.blue2: _SingerColorPalette(
          sungTextColor: AssColorValue.solid(Color(0xFF0000AF)),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFF969664)),
          unsungTextColor: AssColorValue.solid(Color(0xFFE1E1FF)),
          unsungOutlineColor: AssColorValue.solid(Color(0xFF00009C)),
          unsungDecorationColor: AssColorValue.solid(Color(0xFF555580)),
        ),
        SingerColorPreset.purple: _SingerColorPalette(
          sungTextColor: AssColorValue.solid(Color(0xFF7732FE)),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFF969664)),
          unsungTextColor: AssColorValue.solid(Color(0xFFE1E1FF)),
          unsungOutlineColor: AssColorValue.solid(Color(0xFF451D94)),
          unsungDecorationColor: AssColorValue.solid(Color(0xFF694A94)),
        ),
        SingerColorPreset.bluePurple: _SingerColorPalette(
          sungTextColor: AssColorValue.gradient(
            color0: Color(0xFF0000AF),
            color100: Color(0xFF7732FE),
          ),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFF969664)),
          unsungTextColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          unsungOutlineColor: AssColorValue.gradient(
            color0: Color(0xFF00009C),
            color100: Color(0xFF451D94),
          ),
          unsungDecorationColor: AssColorValue.gradient(
            color0: Color(0xFF555580),
            color100: Color(0xFF694A94),
          ),
        ),
        SingerColorPreset.ciel: _SingerColorPalette(
          sungTextColor: AssColorValue.solid(Color(0xFF0C46BC)),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFFE1E196)),
          unsungTextColor: AssColorValue.solid(Color(0xFFE1E1FF)),
          unsungOutlineColor: AssColorValue.solid(Color(0xFF0C46BC)),
          unsungDecorationColor: AssColorValue.solid(Color(0xFF9696E1)),
        ),
        SingerColorPreset.sooda: _SingerColorPalette(
          sungTextColor: AssColorValue.solid(Color(0xFF214F7B)),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFFE1E196)),
          unsungTextColor: AssColorValue.solid(Color(0xFFEBEBFF)),
          unsungOutlineColor: AssColorValue.solid(Color(0xFF214F7B)),
          unsungDecorationColor: AssColorValue.solid(Color(0xFFA8DAF5)),
        ),
        SingerColorPreset.kusou: _SingerColorPalette(
          sungTextColor: AssColorValue.gradient(
            color0: Color(0xFF0C46BC),
            color100: Color(0xFF214F7B),
          ),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFFE1E196)),
          unsungTextColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          unsungOutlineColor: AssColorValue.gradient(
            color0: Color(0xFF0C46BC),
            color100: Color(0xFF214F7B),
          ),
          unsungDecorationColor: AssColorValue.gradient(
            color0: Color(0xFF9696E1),
            color100: Color(0xFFA8DAF5),
          ),
        ),
        SingerColorPreset.lachenalia: _SingerColorPalette(
          sungTextColor: AssColorValue.gradient(
            color0: Color(0xFF0572A4),
            color100: Color(0xFF052951),
          ),
          sungOutlineColor: AssColorValue.solid(Color(0xFFFFFFFF)),
          sungDecorationColor: AssColorValue.solid(Color(0xFFE1E196)),
          unsungTextColor: AssColorValue.solid(Color(0xFFDCF0FC)),
          unsungOutlineColor: AssColorValue.solid(Color(0xFF43464A)),
          unsungDecorationColor: AssColorValue.solid(Color(0xFFE19696)),
        ),
      };

  late final AssExportPageState _pageState;
  late final List<TextEditingController> _singerControllers;
  late TextEditingController _resolutionController;
  bool _isExporting = false;
  final Set<String> _loadedPreviewFonts = {};

  String? get _customFontPath => _pageState._customFontPath;
  set _customFontPath(String? value) => _pageState._customFontPath = value;
  String get _fontName => _pageState._fontName;
  set _fontName(String value) => _pageState._fontName = value;
  String get _fontDisplayName => _pageState._fontDisplayName;
  set _fontDisplayName(String value) => _pageState._fontDisplayName = value;
  String get _fontStyleName => _pageState._fontStyleName;
  set _fontStyleName(String value) => _pageState._fontStyleName = value;
  int get _fontFaceIndex => _pageState._fontFaceIndex;
  set _fontFaceIndex(int value) => _pageState._fontFaceIndex = value;
  bool get _isBold => _pageState._isBold;
  set _isBold(bool value) => _pageState._isBold = value;
  List<SingerColorInfo> get _singerColors => _pageState._singerColors;
  bool get _showSingerPrefixesInAss => _pageState._showSingerPrefixesInAss;
  set _showSingerPrefixesInAss(bool value) =>
      _pageState._showSingerPrefixesInAss = value;
  AssColorValue get _sungTextColor => _pageState._sungTextColor;
  set _sungTextColor(AssColorValue value) => _pageState._sungTextColor = value;
  AssColorValue get _sungOutlineColor => _pageState._sungOutlineColor;
  set _sungOutlineColor(AssColorValue value) =>
      _pageState._sungOutlineColor = value;
  AssColorValue get _sungDecorationColor => _pageState._sungDecorationColor;
  set _sungDecorationColor(AssColorValue value) =>
      _pageState._sungDecorationColor = value;
  AssColorValue get _unsungTextColor => _pageState._unsungTextColor;
  set _unsungTextColor(AssColorValue value) =>
      _pageState._unsungTextColor = value;
  AssColorValue get _unsungOutlineColor => _pageState._unsungOutlineColor;
  set _unsungOutlineColor(AssColorValue value) =>
      _pageState._unsungOutlineColor = value;
  AssColorValue get _unsungDecorationColor => _pageState._unsungDecorationColor;
  set _unsungDecorationColor(AssColorValue value) =>
      _pageState._unsungDecorationColor = value;
  SingerColorPreset get _defaultColorPreset => _pageState._defaultColorPreset;
  set _defaultColorPreset(SingerColorPreset value) =>
      _pageState._defaultColorPreset = value;
  double get _fontSize => _pageState._fontSize;
  int get _letterSpacingStep => _pageState._letterSpacingStep;
  double get _outlineWidth => _pageState._outlineWidth;
  double? get _fontOutlineWidth => _pageState._fontOutlineWidth;
  double? get _rubyFontSize => _pageState._rubyFontSize;
  double? get _rubyOutlineWidth => _pageState._rubyOutlineWidth;
  double? get _rubyBaseGap => _pageState._rubyBaseGap;
  double? get _lineSpacing => _pageState._lineSpacing;
  double get _lyricsBottomMargin => _pageState._lyricsBottomMargin;
  double? get _singerAvatarSize => _pageState._singerAvatarSize;
  double get _singerAvatarGap => _pageState._singerAvatarGap;
  int get _blurLevel => _pageState._blurLevel;
  set _blurLevel(int value) => _pageState._blurLevel = value;
  int get _resolutionHeight => _pageState._resolutionHeight;
  set _resolutionHeight(int value) => _pageState._resolutionHeight = value;
  AssPagingMode get _pagingMode => _pageState._pagingMode;
  set _pagingMode(AssPagingMode value) => _pageState._pagingMode = value;
  List<AssLineAlignment> get _twoLineAlignments =>
      _pageState._twoLineAlignments;
  set _twoLineAlignments(List<AssLineAlignment> value) =>
      _pageState._twoLineAlignments = List.unmodifiable(value);
  List<AssLineAlignment> get _threeLineAlignments =>
      _pageState._threeLineAlignments;
  set _threeLineAlignments(List<AssLineAlignment> value) =>
      _pageState._threeLineAlignments = List.unmodifiable(value);
  List<AssLineAlignment> get _fourLineAlignments =>
      _pageState._fourLineAlignments;
  set _fourLineAlignments(List<AssLineAlignment> value) =>
      _pageState._fourLineAlignments = List.unmodifiable(value);
  double get _interludeThreshold => _pageState._interludeThreshold;
  set _interludeThreshold(double value) =>
      _pageState._interludeThreshold = value;
  int get _horizontalMargin => _pageState._horizontalMargin;
  set _horizontalMargin(int value) => _pageState._horizontalMargin = value;
  int? get _baselineResolutionHeight => _pageState._baselineResolutionHeight;
  set _baselineResolutionHeight(int? value) =>
      _pageState._baselineResolutionHeight = value;

  final List<Color> _presetColors = [
    const Color(0xFF0000AF), // Blue (0, 0, 175)
    const Color(0xFFEB0000), // Red
    const Color(0xFFFF7031), // Orange
  ];

  final List<Color> _presetEdgeColors = [
    const Color(0xFF96BFFF), // Blue (150, 191, 255)
    const Color(0xFFE19696), // Red (225, 150, 150)
    const Color(0xFFFFFF96), // Yellow (255, 255, 150)
  ];

  final List<Color> _presetSungOutlineColors = [const Color(0xFFFFFFFF)];

  final List<Color> _presetUnsungOutlineColors = [const Color(0xFF000000)];

  final List<Color> _presetSungDecorationColors = [const Color(0xFFFFE196)];

  final List<Color> _presetUnsungTextColors = [
    const Color(0xFFE1E1FF),
    const Color(0xFFFFEBEB),
    const Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    _pageState = widget.pageState;
    _singerControllers = [
      for (final singer in _singerColors)
        TextEditingController(text: singer.prefix),
    ];
    _resolutionController = TextEditingController(
      text: _pageState._resolutionText,
    );
    _resolutionController.addListener(_onResolutionTextChanged);
    widget.fontLibrary.addListener(_handleFontLibraryChanged);
    widget.fontLibrary.refresh();
    _initVideoResolution();
  }

  @override
  void didUpdateWidget(AssExportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mediaFilePath != oldWidget.mediaFilePath) {
      _initVideoResolution();
    }
    if (widget.fontLibrary != oldWidget.fontLibrary) {
      oldWidget.fontLibrary.removeListener(_handleFontLibraryChanged);
      widget.fontLibrary.addListener(_handleFontLibraryChanged);
      widget.fontLibrary.refresh();
    }
  }

  void _handleFontLibraryChanged() {
    if (!mounted || widget.fontLibrary.isLoading) return;
    final selectedPath = _customFontPath;
    if (selectedPath != null &&
        !widget.fontLibrary.containsPath(selectedPath)) {
      _selectBundledFont();
      return;
    }
    setState(() {});
  }

  void _onResolutionTextChanged() {
    _pageState._resolutionText = _resolutionController.text;
    final h = int.tryParse(_resolutionController.text);
    if (h != null && h != _resolutionHeight) {
      setState(() => _resolutionHeight = h);
    }
  }

  Future<void> _initVideoResolution() async {
    final mediaPath = widget.mediaFilePath;
    if (mediaPath == null || _pageState._sourceResolutionPath == mediaPath) {
      return;
    }
    final res = await FfmpegService().getVideoResolution(mediaPath);
    if (res == null || !mounted || widget.mediaFilePath != mediaPath) return;

    int w = res.width;
    int h = res.height;
    int paddedHeight = (max(h.toDouble(), w * 9.0 / 16.0) / 2.0).ceil() * 2;
    setState(() {
      _pageState._sourceResolutionPath = mediaPath;
      _baselineResolutionHeight = paddedHeight;
      _resolutionHeight = paddedHeight;
      _resolutionController.text = paddedHeight.toString();
    });
  }

  @override
  void dispose() {
    _resolutionController.removeListener(_onResolutionTextChanged);
    _resolutionController.dispose();
    widget.fontLibrary.removeListener(_handleFontLibraryChanged);
    for (var c in _singerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPreview = widget.mediaFilePath != null && widget.document != null;

    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        leading: widget.drawer == null
            ? null
            : Builder(
                builder: (context) => IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                  tooltip: context.l10n.openNavigationMenu,
                ),
              ),
        title: Text(context.l10n.assExport),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: canPreview ? _previewAss : null,
            icon: const Icon(Icons.play_circle_outline),
            tooltip: context.l10n.preview,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isExporting ? null : _showExportOptions,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            tooltip: context.l10n.export,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 32.0;
          return SingleChildScrollView(
            key: const PageStorageKey<String>('ass-export-scroll'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              40,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildColorSection(),
                    const SizedBox(height: 24),
                    _buildTypographySection(),
                    const SizedBox(height: 24),
                    _buildLayoutSection(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorSection() {
    return _buildSection(
      title: context.l10n.colors,
      children: [
        _buildSingerColorCard(
          isDefault: true,
          title: context.l10n.defaultColors,
          sungColor: _sungTextColor,
          unsungColor: _unsungTextColor,
          onTap: _showDefaultColorSettings,
        ),
        for (int i = 0; i < _singerColors.length; i++) ...[
          const SizedBox(height: 6),
          _buildSingerColorCard(
            isDefault: false,
            controller: _singerControllers[i],
            sungColor: _singerColors[i].sungTextColor,
            unsungColor: _singerColors[i].unsungTextColor,
            onTap: () => _showSingerColorSettings(i),
            onDelete: () {
              setState(() {
                _singerColors.removeAt(i);
                _singerControllers[i].dispose();
                _singerControllers.removeAt(i);
              });
              _publishActiveColorPresets();
            },
            onPrefixChanged: (val) {
              _singerColors[i].prefix = val;
              _publishActiveColorPresets();
            },
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showSavedColorPresetsDialog,
                icon: const Icon(Icons.palette_outlined),
                label: Text(context.l10n.savedColorPresets),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _addSingerColor,
                icon: const Icon(Icons.add),
                label: Text(context.l10n.addSinger),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTypographySection() {
    return _buildSection(
      title: context.l10n.textSettings,
      children: [
        _buildFontControl(),
        _buildDivider(),
        _buildSwitchSetting(
          title: context.l10n.bold,
          value: _isBold,
          onChanged: (value) => setState(() => _isBold = value),
        ),
        _buildDivider(),
        _buildActionSetting(
          title: context.l10n.textStyle,
          value: context.l10n.textStyleSummary(
            _fontSize.toInt(),
            _letterSpacingLabel(_letterSpacingStep),
            _outlineWidth.toInt(),
          ),
          onTap: _showTypographySettingsDialog,
        ),
        _buildDivider(),
        _buildSliderSetting(
          title: context.l10n.blur,
          valueLabel: '$_blurLevel',
          value: _blurLevel.toDouble(),
          min: 0,
          max: 2,
          divisions: 2,
          onChanged: (value) => setState(() => _blurLevel = value.toInt()),
        ),
      ],
    );
  }

  Widget _buildLayoutSection() {
    return _buildSection(
      title: context.l10n.screenSettings,
      children: [
        _buildResolutionPicker(),
        _buildDivider(),
        _buildPagingPicker(),
        _buildDivider(),
        _buildSliderSetting(
          title: context.l10n.horizontalMargin,
          valueLabel: '$_horizontalMargin px',
          value: _horizontalMargin.toDouble(),
          min: 0,
          max: 300,
          divisions: 60,
          onChanged: (value) =>
              setState(() => _horizontalMargin = value.toInt()),
        ),
        _buildDivider(),
        _buildSliderSetting(
          title: context.l10n.interludeCountdown,
          valueLabel: context.l10n.secondsValue(_interludeThreshold.toInt()),
          value: _interludeThreshold,
          min: 5,
          max: 60,
          divisions: 55,
          onChanged: (value) => setState(() => _interludeThreshold = value),
        ),
        _buildDivider(),
        _buildSwitchSetting(
          title: context.l10n.showLinePrefix,
          value: _showSingerPrefixesInAss,
          onChanged: (value) =>
              setState(() => _showSingerPrefixesInAss = value),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8, top: 8),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFontControl() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fontDisplayName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fontStyleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: _showFontLibraryPicker,
            icon: const Icon(Icons.font_download_outlined),
            tooltip: context.l10n.chooseFont,
          ),
          if (widget.onManageFonts != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: widget.onManageFonts,
              icon: const Icon(Icons.settings_outlined),
              tooltip: context.l10n.manageFonts,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagingPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<AssPagingMode>(
            initialValue: _pagingMode,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.l10n.subtitleLayout,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: [
              DropdownMenuItem(
                value: AssPagingMode.auto2Lines,
                child: Text(context.l10n.alternatingTwoLines),
              ),
              DropdownMenuItem(
                value: AssPagingMode.emptyLineDelimited,
                child: Text(context.l10n.paragraphsByBlankLine),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _pagingMode = value);
            },
          ),
          if (_pagingMode == AssPagingMode.emptyLineDelimited) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.format_align_left),
              title: Text(context.l10n.lineAlignmentSettings),
              subtitle: Text(context.l10n.lineAlignmentSettingsDescription),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showLineAlignmentSettings,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showLineAlignmentSettings() async {
    final result = await showDialog<_LineAlignmentSettingsValue>(
      context: context,
      builder: (context) => _LineAlignmentSettingsDialog(
        initialValue: _LineAlignmentSettingsValue(
          twoLines: _twoLineAlignments,
          threeLines: _threeLineAlignments,
          fourLines: _fourLineAlignments,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _twoLineAlignments = result.twoLines;
      _threeLineAlignments = result.threeLines;
      _fourLineAlignments = result.fourLines;
    });
  }

  Widget _buildResolutionPicker() {
    final width = (_resolutionHeight * 16 / 9).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.outputResolution,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 360;
              final heightField = DropdownMenu<int>(
                controller: _resolutionController,
                label: Text(context.l10n.heightPixels),
                expandedInsets: EdgeInsets.zero,
                inputDecorationTheme: InputDecorationTheme(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: 720, label: '720'),
                  DropdownMenuEntry(value: 1080, label: '1080'),
                  DropdownMenuEntry(value: 1440, label: '1440'),
                  DropdownMenuEntry(value: 2160, label: '2160'),
                ],
                onSelected: (value) {
                  if (value != null) {
                    _resolutionController.text = value.toString();
                  }
                },
              );
              final widthField = TextField(
                readOnly: true,
                controller: TextEditingController(text: width.toString()),
                decoration: InputDecoration(
                  labelText: context.l10n.widthPixels,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              final resetButton = _baselineResolutionHeight == null
                  ? null
                  : IconButton.filledTonal(
                      onPressed: () {
                        _resolutionController.text = _baselineResolutionHeight!
                            .toString();
                      },
                      icon: const Icon(Icons.restore),
                      tooltip: context.l10n.resetSourceResolution,
                    );
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heightField,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: widthField),
                        if (resetButton != null) ...[
                          const SizedBox(width: 8),
                          resetButton,
                        ],
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heightField),
                  const SizedBox(width: 12),
                  Expanded(child: widthField),
                  if (resetButton != null) ...[
                    const SizedBox(width: 8),
                    resetButton,
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchSetting({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildActionSetting({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        height: 1,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }

  void _addSingerColor() {
    setState(() {
      _singerColors.add(
        SingerColorInfo(
          prefix: '',
          sungTextColor: _sungTextColor,
          sungOutlineColor: _sungOutlineColor,
          sungDecorationColor: _sungDecorationColor,
          unsungTextColor: _unsungTextColor,
          unsungOutlineColor: _unsungOutlineColor,
          unsungDecorationColor: _unsungDecorationColor,
        ),
      );
      _singerControllers.add(TextEditingController(text: ''));
    });
    _publishActiveColorPresets();
  }

  Future<void> _showSavedColorPresetsDialog() async {
    try {
      await widget.colorPresetLibrary.load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.operationFailed(error))),
        );
      }
      return;
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SavedColorPresetsDialog(
        library: widget.colorPresetLibrary,
        onAdd: _addSavedColorPresetToCurrent,
        onRename: _renameSavedColorPreset,
        onDelete: _deleteSavedColorPreset,
        onImport: _showSingerColorImportDialog,
      ),
    );
  }

  Future<void> _addSavedColorPresetToCurrent(ColorPresetAsset preset) async {
    final key = preset.name.trim().toLowerCase();
    final matchingIndexes = <int>[
      for (var index = 0; index < _singerColors.length; index++)
        if (_singerColors[index].prefix.trim().toLowerCase() == key) index,
    ];
    if (matchingIndexes.isNotEmpty) {
      final replace =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(context.l10n.replaceCurrentSingerColorTitle),
              content: Text(
                context.l10n.replaceCurrentSingerColorQuestion(preset.name),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(context.l10n.replace),
                ),
              ],
            ),
          ) ??
          false;
      if (!replace || !mounted) return;
    }

    final singer = _singerFromColorPreset(preset);
    setState(() {
      if (matchingIndexes.isEmpty) {
        _singerColors.add(singer);
        _singerControllers.add(TextEditingController(text: singer.prefix));
      } else {
        for (final index in matchingIndexes) {
          _singerColors[index] = singer.copy();
          _singerControllers[index].text = singer.prefix;
        }
      }
    });
    _publishActiveColorPresets();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          matchingIndexes.isEmpty
              ? context.l10n.colorPresetAddedToCurrent(preset.name)
              : context.l10n.currentSingerColorReplaced(preset.name),
        ),
      ),
    );
  }

  Future<void> _renameSavedColorPreset(ColorPresetAsset preset) async {
    final name = await _showColorPresetNameDialog(
      title: context.l10n.renameColorPreset,
      initialName: preset.name,
    );
    if (name == null || name == preset.name || !mounted) return;
    try {
      await widget.colorPresetLibrary.rename(preset, name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.colorPresetRenamed(name))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed(error))),
      );
    }
  }

  Future<void> _deleteSavedColorPreset(ColorPresetAsset preset) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.deleteColorPreset),
            content: Text(context.l10n.deleteColorPresetQuestion(preset.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l10n.delete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await widget.colorPresetLibrary.delete(preset);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.colorPresetDeleted(preset.name))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed(error))),
      );
    }
  }

  Future<void> _showSingerColorImportDialog() async {
    final savedMarkdown = await widget.colorPresetLibrary.readMarkdown();
    if (!mounted) return;
    final result = await showDialog<_SingerColorImportParseResult>(
      context: context,
      builder: (context) => _SingerColorImportDialog(
        initialText: savedMarkdown.trim().isEmpty
            ? context.l10n.singerColorExample
            : savedMarkdown,
      ),
    );
    if (result == null || !mounted) return;

    try {
      await widget.colorPresetLibrary.saveAll(
        result.singers.map(
          (singer) => _colorPresetFromSinger(singer.prefix, singer),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed(error))),
      );
      return;
    }
    if (!mounted) return;

    var updatedCount = 0;
    var addedCount = 0;
    setState(() {
      for (final imported in result.singers) {
        final matchingIndexes = <int>[];
        for (var index = 0; index < _singerColors.length; index++) {
          if (_singerColors[index].prefix.trim() == imported.prefix) {
            matchingIndexes.add(index);
          }
        }

        if (matchingIndexes.isEmpty) {
          _singerColors.add(imported);
          _singerControllers.add(TextEditingController(text: imported.prefix));
          addedCount++;
          continue;
        }

        for (final index in matchingIndexes) {
          _singerColors[index] = imported.copy();
          _singerControllers[index].text = imported.prefix;
        }
        updatedCount++;
      }
    });
    _publishActiveColorPresets();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.duplicateCount > 0
              ? context.l10n.singerColorImportCompletedWithDuplicates(
                  updatedCount,
                  addedCount,
                  result.errors.length,
                  result.duplicateCount,
                )
              : context.l10n.singerColorImportCompleted(
                  updatedCount,
                  addedCount,
                  result.errors.length,
                ),
        ),
      ),
    );
  }

  String _singerPresetLabel(SingerColorPreset preset) {
    return switch (preset) {
      SingerColorPreset.none => context.l10n.noPreset,
      SingerColorPreset.blue => context.l10n.blueColors,
      SingerColorPreset.standard => context.l10n.standardColors,
      SingerColorPreset.chorus => context.l10n.chorusColors,
      SingerColorPreset.blue2 => context.l10n.blueColors2,
      SingerColorPreset.purple => context.l10n.purple,
      SingerColorPreset.bluePurple => context.l10n.bluePurple,
      SingerColorPreset.ciel => 'CIEL',
      SingerColorPreset.sooda => 'Sooda',
      SingerColorPreset.kusou => context.l10n.kusou,
      SingerColorPreset.lachenalia => 'ラケナリア',
    };
  }

  void _applySingerPreset(SingerColorInfo singer, SingerColorPreset preset) {
    singer.preset = preset;
    final palette = _singerColorPresets[preset];
    if (palette == null) return;

    singer.sungTextColor = palette.sungTextColor;
    singer.sungOutlineColor = palette.sungOutlineColor;
    singer.sungDecorationColor = palette.sungDecorationColor;
    singer.unsungTextColor = palette.unsungTextColor;
    singer.unsungOutlineColor = palette.unsungOutlineColor;
    singer.unsungDecorationColor = palette.unsungDecorationColor;
  }

  ColorPresetValue _toPresetValue(AssColorValue value) {
    return value.isGradient
        ? ColorPresetValue.gradient(
            color0: value.color0.toARGB32(),
            color100: value.color100.toARGB32(),
          )
        : ColorPresetValue.solid(value.color0.toARGB32());
  }

  AssColorValue _fromPresetValue(ColorPresetValue value) {
    return value.isGradient
        ? AssColorValue.gradient(
            color0: Color(value.color0),
            color100: Color(value.color100),
          )
        : AssColorValue.solid(Color(value.color0));
  }

  SingerColorInfo _singerFromColorPreset(ColorPresetAsset preset) {
    return SingerColorInfo(
      prefix: preset.name,
      preset: SingerColorPreset.none,
      sungTextColor: _fromPresetValue(preset.sungTextColor),
      sungOutlineColor: _fromPresetValue(preset.sungOutlineColor),
      sungDecorationColor: _fromPresetValue(preset.sungDecorationColor),
      unsungTextColor: _fromPresetValue(preset.unsungTextColor),
      unsungOutlineColor: _fromPresetValue(preset.unsungOutlineColor),
      unsungDecorationColor: _fromPresetValue(preset.unsungDecorationColor),
    );
  }

  ColorPresetAsset _colorPresetFromSinger(String name, SingerColorInfo singer) {
    return ColorPresetAsset(
      name: name,
      sungTextColor: _toPresetValue(singer.sungTextColor),
      sungOutlineColor: _toPresetValue(singer.sungOutlineColor),
      sungDecorationColor: _toPresetValue(singer.sungDecorationColor),
      unsungTextColor: _toPresetValue(singer.unsungTextColor),
      unsungOutlineColor: _toPresetValue(singer.unsungOutlineColor),
      unsungDecorationColor: _toPresetValue(singer.unsungDecorationColor),
    );
  }

  void _publishActiveColorPresets() {
    widget.colorPresetLibrary.setActivePresets(
      _singerColors
          .where((singer) => singer.prefix.trim().isNotEmpty)
          .map(
            (singer) => _colorPresetFromSinger(singer.prefix.trim(), singer),
          ),
    );
  }

  Future<String?> _showColorPresetNameDialog({
    String? title,
    String initialName = '',
  }) {
    final controller = TextEditingController(text: initialName);
    String? errorText;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title ?? context.l10n.saveColorPreset),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: context.l10n.colorPresetName,
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) {},
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                final validation = widget.colorPresetLibrary.validateName(name);
                if (validation != null) {
                  setDialogState(() {
                    errorText = validation == 'empty'
                        ? context.l10n.colorPresetNameRequired
                        : context.l10n.colorPresetNameInvalid;
                  });
                  return;
                }
                Navigator.pop(dialogContext, name);
              },
              child: Text(context.l10n.confirm),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<ColorPresetAsset?> _saveCurrentColorPreset(
    SingerColorInfo singer,
  ) async {
    final name = await _showColorPresetNameDialog(
      initialName: singer.prefix.trim(),
    );
    if (name == null || !mounted) return null;
    try {
      final saved = await widget.colorPresetLibrary.save(
        _colorPresetFromSinger(name, singer),
      );
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.colorPresetSaved(saved.name))),
      );
      return saved;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.operationFailed(error))),
        );
      }
      return null;
    }
  }

  Future<void> _showDefaultColorSettings() async {
    final edited = SingerColorInfo(
      prefix: '',
      preset: _defaultColorPreset,
      sungTextColor: _sungTextColor,
      sungOutlineColor: _sungOutlineColor,
      sungDecorationColor: _sungDecorationColor,
      unsungTextColor: _unsungTextColor,
      unsungOutlineColor: _unsungOutlineColor,
      unsungDecorationColor: _unsungDecorationColor,
    );
    final result = await _showColorSettingsDialog(
      edited: edited,
      title: context.l10n.defaultColors,
      fillPrefixFromPreset: false,
    );
    if (result != null && mounted) {
      setState(() {
        _defaultColorPreset = result.preset;
        _sungTextColor = result.sungTextColor;
        _sungOutlineColor = result.sungOutlineColor;
        _sungDecorationColor = result.sungDecorationColor;
        _unsungTextColor = result.unsungTextColor;
        _unsungOutlineColor = result.unsungOutlineColor;
        _unsungDecorationColor = result.unsungDecorationColor;
      });
    }
  }

  Future<void> _showSingerColorSettings(int index) async {
    final result = await _showColorSettingsDialog(
      edited: _singerColors[index].copy(),
      title: context.l10n.singerColorsTitle(_singerColors[index].prefix),
      fillPrefixFromPreset: true,
    );
    if (result != null && mounted) {
      setState(() {
        _singerColors[index] = result;
        _singerControllers[index].text = result.prefix;
      });
      _publishActiveColorPresets();
    }
  }

  Future<SingerColorInfo?> _showColorSettingsDialog({
    required SingerColorInfo edited,
    required String title,
    required bool fillPrefixFromPreset,
  }) {
    return showDialog<SingerColorInfo>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.colorPreset,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<SingerColorPreset>(
                            key: ValueKey(edited.preset),
                            initialValue: edited.preset,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            items: [
                              for (final preset in SingerColorPreset.values)
                                DropdownMenuItem(
                                  value: preset,
                                  child: Text(
                                    _singerPresetLabel(preset),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (preset) {
                              if (preset == null) return;
                              setDialogState(
                                () => _applySingerPreset(edited, preset),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          Text(
                            context.l10n.sample,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            height: 110,
                            decoration: BoxDecoration(
                              color: const Color(0xFF101218),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CustomPaint(
                              painter: _AssStyleSamplePainter(
                                colors: edited,
                                fontFamily: _previewFontFamily,
                                isBold: _isBold,
                                assFontSize: _fontSize,
                                baseOutlineWidth: _resolvedFontOutlineWidth,
                                decorationWidth: _outlineWidth,
                                blurLevel: _blurLevel,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            context.l10n.sungColors,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.textColor,
                            value: edited.sungTextColor,
                            presets: _presetColors,
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.sungTextColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.outlineColor,
                            value: edited.sungOutlineColor,
                            presets: _presetSungOutlineColors,
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.sungOutlineColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.decorationColor,
                            value: edited.sungDecorationColor,
                            presets: _presetSungDecorationColors,
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.sungDecorationColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.unsungColors,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.textColor,
                            value: edited.unsungTextColor,
                            presets: _presetUnsungTextColors,
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.unsungTextColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.outlineColor,
                            value: edited.unsungOutlineColor,
                            presets: _presetUnsungOutlineColors,
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.unsungOutlineColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.decorationColor,
                            value: edited.unsungDecorationColor,
                            presets: _presetEdgeColors,
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.unsungDecorationColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                IconButton(
                  tooltip: context.l10n.saveColorPreset,
                  onPressed: () async {
                    final preset = await _saveCurrentColorPreset(edited);
                    if (preset == null || !ctx.mounted) return;
                    if (fillPrefixFromPreset && edited.prefix.trim().isEmpty) {
                      setDialogState(() => edited.prefix = preset.name);
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(context.l10n.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(edited),
                      child: Text(context.l10n.apply),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSingerDialogColorSetting({
    required String label,
    required AssColorValue value,
    required List<Color> presets,
    required StateSetter setDialogState,
    required ValueChanged<AssColorValue> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final selected = await _showColorPicker(
            value,
            presets,
            title: context.l10n.chooseItem(label),
          );
          if (selected != null) {
            setDialogState(() => onChanged(selected));
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: _colorValueDecoration(value, borderWidth: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _representativeColor(AssColorValue value) {
    return Color.lerp(value.color0, value.color100, 0.5) ?? value.color0;
  }

  BoxDecoration _colorValueDecoration(
    AssColorValue value, {
    double borderWidth = 1,
  }) {
    final representative = _representativeColor(value);
    return BoxDecoration(
      color: value.isGradient ? null : value.color0,
      gradient: value.isGradient
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [value.color0, value.color100],
            )
          : null,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: borderWidth),
      boxShadow: [
        BoxShadow(color: representative.withValues(alpha: 0.5), blurRadius: 8),
      ],
    );
  }

  Future<void> _showTypographySettingsDialog() async {
    await widget.avatarLibrary.refresh();
    if (!mounted) return;
    final fontService = FontService();
    String fontSandboxDir;
    try {
      await fontService.prepareFontForRendering(
        fontFilePath: _customFontPath,
        faceIndex: _fontFaceIndex,
      );
      fontSandboxDir = await fontService.getSandboxFontsDir();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.previewFontPreparationFailed(error)),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final result = await showDialog<_TypographySettingsValue>(
      context: context,
      builder: (context) => _TypographySettingsDialog(
        initialValue: _TypographySettingsValue(
          fontSize: _fontSize,
          letterSpacingStep: _letterSpacingStep,
          decorationWidth: _outlineWidth,
          fontOutlineWidth: _fontOutlineWidth,
          rubyFontSize: _rubyFontSize,
          rubyOutlineWidth: _rubyOutlineWidth,
          rubyBaseGap: _rubyBaseGap,
          lineSpacing: _lineSpacing,
          lyricsBottomMargin: _lyricsBottomMargin,
          singerAvatarSize: _singerAvatarSize,
          singerAvatarGap: _singerAvatarGap,
        ),
        baseSettings: _getCurrentSettings(),
        fontSandboxDir: fontSandboxDir,
      ),
    );
    if (result == null || !mounted) return;

    _pageState.applyTypographySettings(
      TypographySettingsData(
        fontSize: result.fontSize,
        letterSpacingStep: result.letterSpacingStep,
        decorationWidth: result.decorationWidth,
        fontOutlineWidth: result.fontOutlineWidth,
        rubyFontSize: result.rubyFontSize,
        rubyOutlineWidth: result.rubyOutlineWidth,
        rubyBaseGap: result.rubyBaseGap,
        lineSpacing: result.lineSpacing,
        lyricsBottomMargin: result.lyricsBottomMargin,
        singerAvatarSize: result.singerAvatarSize,
        singerAvatarGap: result.singerAvatarGap,
      ),
    );
    setState(() {});
  }

  AssExportSettings _getCurrentSettings() {
    return AssExportSettings(
      fontName: _fontName,
      customFontPath: _customFontPath,
      fontFaceIndex: _fontFaceIndex,
      isBold: _isBold,
      singerColors: _singerColors,
      showSingerPrefixesInAss: _showSingerPrefixesInAss,
      sungTextColor: _sungTextColor,
      sungOutlineColor: _sungOutlineColor,
      sungDecorationColor: _sungDecorationColor,
      unsungTextColor: _unsungTextColor,
      unsungOutlineColor: _unsungOutlineColor,
      unsungDecorationColor: _unsungDecorationColor,
      fontSize: _fontSize.toInt(),
      letterSpacingEm: _letterSpacingEm,
      pagingMode: _pagingMode,
      twoLineAlignments: _twoLineAlignments,
      threeLineAlignments: _threeLineAlignments,
      fourLineAlignments: _fourLineAlignments,
      interludeThresholdSeconds: _interludeThreshold.toInt(),
      horizontalMargin: _horizontalMargin,
      outlineWidth: _outlineWidth.toInt(),
      fontOutlineWidth: _fontOutlineWidth?.toInt(),
      rubyFontSize: _rubyFontSize?.toInt(),
      rubyOutlineWidth: _rubyOutlineWidth?.toInt(),
      rubyBaseGap: _rubyBaseGap?.toInt(),
      lineSpacing: _lineSpacing?.toInt(),
      lyricsBottomMargin: _lyricsBottomMargin.toInt(),
      singerAvatarSize: _singerAvatarSize?.toInt(),
      singerAvatarGap: _singerAvatarGap.toInt(),
      singerAvatarPaths: widget.avatarLibrary.assetPathsBySinger,
      blurLevel: _blurLevel,
      resolutionHeight: _resolutionHeight,
    );
  }

  double get _automaticFontOutlineWidth => (_fontSize * 7 / 85).roundToDouble();

  double get _resolvedFontOutlineWidth =>
      _fontOutlineWidth ?? _automaticFontOutlineWidth;

  double? get _letterSpacingEm =>
      _letterSpacingStep == 0 ? null : (_letterSpacingStep - 21) / 100.0;

  String _letterSpacingLabel(int step) {
    if (step == 0) return context.l10n.automatic;
    return '${((step - 21) / 100.0).toStringAsFixed(2)} em';
  }

  bool _isVideo(String? path) {
    if (path == null) return false;
    final ext = path.split('.').last.toLowerCase();
    return kVideoExtensions.contains(ext);
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final isVideo = _isVideo(widget.mediaFilePath);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.description),
                title: Text(ctx.l10n.exportAssSubtitle),
                subtitle: Text(ctx.l10n.exportAssSubtitleDescription),
                onTap: () {
                  Navigator.pop(ctx);
                  _executeExport(widget.onExport);
                },
              ),
              ListTile(
                leading: const Icon(Icons.movie_creation),
                title: Text(ctx.l10n.exportHardsubVideo),
                subtitle: Text(
                  isVideo
                      ? ctx.l10n.exportHardsubVideoDescription
                      : ctx.l10n.exportHardsubVideoUnavailable,
                ),
                enabled: isVideo && widget.onExportVideo != null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (widget.onExportVideo != null) {
                    _executeExport(widget.onExportVideo!);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _executeExport(
    Future<void> Function(AssExportSettings) exportFunc,
  ) async {
    setState(() {
      _isExporting = true;
    });

    try {
      await widget.avatarLibrary.refresh();
      if (!mounted) return;
      final settings = _getCurrentSettings();
      await exportFunc(settings);
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _previewAss() async {
    if (widget.mediaFilePath == null || widget.document == null) return;

    // Generate temp ASS file
    await widget.avatarLibrary.refresh();
    if (!mounted) return;
    final settings = _getCurrentSettings();

    final assContent = await AssExporter.generateAss(
      widget.document!,
      settings,
    );

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/preview_temp.ass');
    await tempFile.writeAsString(assContent);

    String? fontSandboxDir;
    final fontService = FontService();
    await fontService.prepareFontForRendering(
      fontFilePath: settings.customFontPath,
      faceIndex: settings.fontFaceIndex,
    );
    fontSandboxDir = await fontService.getSandboxFontsDir();

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AssPreviewScreen(
            mediaPath: widget.mediaFilePath!,
            assFilePath: tempFile.path,
            fontSandboxDir: fontSandboxDir,
          ),
        ),
      );
      // Clean up temp file after preview is closed
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<void> _showFontLibraryPicker() async {
    await widget.fontLibrary.refresh();
    if (!mounted) return;
    final fontChoices = <_FontLibraryChoice>[
      for (final asset in widget.fontLibrary.assets)
        for (final face in asset.faces)
          _FontLibraryChoice.asset(asset, face.index),
    ];
    final selected = await showModalBottomSheet<_FontLibraryChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.chooseFont,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (widget.onManageFonts != null)
                      IconButton(
                        onPressed: () => Navigator.pop(
                          context,
                          const _FontLibraryChoice.manage(),
                        ),
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: context.l10n.manageFonts,
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount:
                      1 + fontChoices.length + (fontChoices.isEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                        leading: const Icon(Icons.text_fields),
                        title: Text(
                          FontService.bundledFontFamily,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontFamily: 'KosugiMaru'),
                        ),
                        subtitle: const Text('Regular'),
                        trailing: _customFontPath == null
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(
                          context,
                          const _FontLibraryChoice.builtIn(),
                        ),
                      );
                    }
                    if (fontChoices.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.l10n.noImportedFonts,
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final choice = fontChoices[index - 1];
                    final asset = choice.asset!;
                    final face = asset.faces.firstWhere(
                      (item) => item.index == choice.faceIndex,
                    );
                    final isSelected =
                        _customFontPath == asset.path &&
                        _fontFaceIndex == face.index;
                    return ListTile(
                      leading: const Icon(Icons.font_download_outlined),
                      title: FontFacePreviewText(
                        library: widget.fontLibrary,
                        asset: asset,
                        face: face,
                        text: _fontFamilyLabel(face),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        _fontStyleLabel(face),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(context, choice),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected.openManager) {
      widget.onManageFonts?.call();
    } else if (selected.useBuiltIn) {
      _selectBundledFont();
    } else if (selected.asset != null && selected.faceIndex != null) {
      await _selectLibraryFont(selected.asset!, selected.faceIndex!);
    }
  }

  Future<void> _selectLibraryFont(FontLibraryAsset asset, int faceIndex) async {
    if (asset.faces.isEmpty) return;
    final face = asset.faces.firstWhere((item) => item.index == faceIndex);
    try {
      await _loadPreviewFont(asset.path, face.assFontName, face.index);
      if (!mounted) return;
      setState(() {
        _customFontPath = asset.path;
        _fontFaceIndex = face.index;
        _fontName = face.assFontName;
        _fontDisplayName = _fontFamilyLabel(face);
        _fontStyleName = _fontStyleLabel(face);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.fontFaceLoadFailed(error))),
      );
    }
  }

  void _selectBundledFont() {
    setState(() {
      _customFontPath = null;
      _fontFaceIndex = 0;
      _fontName = FontService.bundledFontFamily;
      _fontDisplayName = FontService.bundledFontFamily;
      _fontStyleName = 'Regular';
    });
  }

  String get _previewFontFamily =>
      _customFontPath == null ? 'KosugiMaru' : _fontName;

  Future<void> _loadPreviewFont(
    String path,
    String family,
    int faceIndex,
  ) async {
    final fontKey = '$family|$path|$faceIndex';
    if (_loadedPreviewFonts.contains(fontKey)) return;

    final bytes = await FontService().loadStandaloneFaceBytes(
      fontFilePath: path,
      faceIndex: faceIndex,
    );
    final fontData = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final loader = FontLoader(family)..addFont(Future.value(fontData));
    await loader.load();
    _loadedPreviewFonts.add(fontKey);
  }

  Widget _buildSingerColorCard({
    required bool isDefault,
    String? title,
    TextEditingController? controller,
    required AssColorValue sungColor,
    required AssColorValue unsungColor,
    required VoidCallback onTap,
    VoidCallback? onDelete,
    ValueChanged<String>? onPrefixChanged,
  }) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: EdgeInsets.only(
        left: 12,
        top: 8,
        bottom: 8,
        right: isDefault ? 16 : 8,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: isDefault
                  ? Text(
                      title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : TextField(
                      controller: controller,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: context.l10n.linePrefix,
                        hintStyle: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                      onChanged: onPrefixChanged,
                    ),
            ),
            const SizedBox(width: 16),
            Tooltip(
              message: context.l10n.editColors,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: DualColorPreview(
                  sung: _previewColorValue(sungColor),
                  unsung: _previewColorValue(unsungColor),
                ),
              ),
            ),
            if (!isDefault) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: theme.colorScheme.error,
                onPressed: onDelete,
                tooltip: context.l10n.delete,
              ),
            ],
          ],
        ),
      ),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: isDefault ? InkWell(onTap: onTap, child: content) : content,
    );
  }

  PreviewColorValue _previewColorValue(AssColorValue value) =>
      PreviewColorValue(
        color0: value.color0,
        color100: value.color100,
        isGradient: value.isGradient,
      );

  Future<AssColorValue?> _showColorPicker(
    AssColorValue initialValue,
    List<Color> presets, {
    String? title,
  }) async {
    return showAssColorPickerDialog(
      context,
      initialValue: initialValue,
      suggestedPresets: presets,
      title: title ?? context.l10n.chooseColor,
    );
  }
}

class _SingerColorImportDialog extends StatefulWidget {
  final String initialText;

  const _SingerColorImportDialog({required this.initialText});

  @override
  State<_SingerColorImportDialog> createState() =>
      _SingerColorImportDialogState();
}

class _SingerColorImportDialogState extends State<_SingerColorImportDialog> {
  late final TextEditingController _textController;
  late _SingerColorImportParseResult _parseResult;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _parseResult = const _SingerColorImportParseResult(
      singers: [],
      validLineCount: 0,
      errors: [],
    );
    _textController.addListener(_parseInput);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parseResult = _parseSingerColorText(_textController.text, context.l10n);
  }

  @override
  void dispose() {
    _textController.removeListener(_parseInput);
    _textController.dispose();
    super.dispose();
  }

  void _parseInput() {
    setState(() {
      _parseResult = _parseSingerColorText(_textController.text, context.l10n);
    });
  }

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    _textController.text = data!.text!;
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasInput = _textController.text.trim().isNotEmpty;
    final statusColor = _parseResult.errors.isEmpty
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.upload_file),
          const SizedBox(width: 10),
          Text(context.l10n.singerColorImport),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SizedBox(
          width: double.maxFinite,
          height: min(620.0, MediaQuery.sizeOf(context).height * 0.72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.singerColorImportHelp,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pasteText,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: Text(context.l10n.paste),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: _textController,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: context.l10n.singerColorInputHint,
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasInput
                    ? context.l10n.singerColorImportSummary(
                        _parseResult.validLineCount,
                        _parseResult.singers.length,
                        _parseResult.duplicateCount,
                        _parseResult.errors.length,
                      )
                    : context.l10n.singerColorInputEmpty,
                style: TextStyle(
                  color: hasInput
                      ? statusColor
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_parseResult.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 92),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          _parseResult.errors.join('\n'),
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: _parseResult.singers.isEmpty
              ? null
              : () => Navigator.pop(context, _parseResult),
          icon: const Icon(Icons.download_done, size: 18),
          label: Text(context.l10n.importValidRows),
        ),
      ],
    );
  }
}

class _LineAlignmentSettingsValue {
  final List<AssLineAlignment> twoLines;
  final List<AssLineAlignment> threeLines;
  final List<AssLineAlignment> fourLines;

  _LineAlignmentSettingsValue({
    required Iterable<AssLineAlignment> twoLines,
    required Iterable<AssLineAlignment> threeLines,
    required Iterable<AssLineAlignment> fourLines,
  }) : twoLines = List.unmodifiable(twoLines),
       threeLines = List.unmodifiable(threeLines),
       fourLines = List.unmodifiable(fourLines);
}

class _LineAlignmentSettingsDialog extends StatefulWidget {
  final _LineAlignmentSettingsValue initialValue;

  const _LineAlignmentSettingsDialog({required this.initialValue});

  @override
  State<_LineAlignmentSettingsDialog> createState() =>
      _LineAlignmentSettingsDialogState();
}

class _LineAlignmentSettingsDialogState
    extends State<_LineAlignmentSettingsDialog> {
  late List<AssLineAlignment> _twoLines;
  late List<AssLineAlignment> _threeLines;
  late List<AssLineAlignment> _fourLines;

  @override
  void initState() {
    super.initState();
    _twoLines = List.of(widget.initialValue.twoLines);
    _threeLines = List.of(widget.initialValue.threeLines);
    _fourLines = List.of(widget.initialValue.fourLines);
  }

  void _reset() {
    setState(() {
      _twoLines = List.of(kDefaultTwoLineAlignments);
      _threeLines = List.of(kDefaultThreeLineAlignments);
      _fourLines = List.of(kDefaultFourLineAlignments);
    });
  }

  Widget _buildGroup(String title, List<AssLineAlignment> alignments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var index = 0; index < alignments.length; index++) ...[
          Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(context.l10n.lineNumber(index + 1)),
              ),
              Expanded(
                child: SegmentedButton<AssLineAlignment>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: AssLineAlignment.left,
                      icon: const Icon(Icons.format_align_left),
                      tooltip: context.l10n.alignLeft,
                    ),
                    ButtonSegment(
                      value: AssLineAlignment.center,
                      icon: const Icon(Icons.format_align_center),
                      tooltip: context.l10n.alignCenter,
                    ),
                    ButtonSegment(
                      value: AssLineAlignment.right,
                      icon: const Icon(Icons.format_align_right),
                      tooltip: context.l10n.alignRight,
                    ),
                  ],
                  selected: {alignments[index]},
                  onSelectionChanged: (selection) {
                    setState(() => alignments[index] = selection.single);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          if (index != alignments.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.lineAlignmentSettings),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.lineAlignmentSettingsHelp),
              const SizedBox(height: 20),
              _buildGroup(context.l10n.bottomAlignedTwoLines, _twoLines),
              const SizedBox(height: 20),
              _buildGroup(context.l10n.bottomAlignedThreeLines, _threeLines),
              const SizedBox(height: 20),
              _buildGroup(context.l10n.bottomAlignedFourLines, _fourLines),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: Text(context.l10n.resetDefaults)),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _LineAlignmentSettingsValue(
              twoLines: _twoLines,
              threeLines: _threeLines,
              fourLines: _fourLines,
            ),
          ),
          child: Text(context.l10n.confirm),
        ),
      ],
    );
  }
}

class _TypographySettingsValue {
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

  const _TypographySettingsValue({
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
}

class _TypographySettingsDialog extends StatefulWidget {
  final _TypographySettingsValue initialValue;
  final AssExportSettings baseSettings;
  final String fontSandboxDir;

  const _TypographySettingsDialog({
    required this.initialValue,
    required this.baseSettings,
    required this.fontSandboxDir,
  });

  @override
  State<_TypographySettingsDialog> createState() =>
      _TypographySettingsDialogState();
}

class _TypographySettingsDialogState extends State<_TypographySettingsDialog> {
  late double _fontSize;
  late int _letterSpacingStep;
  late double _decorationWidth;
  double? _fontOutlineWidth;
  double? _rubyFontSize;
  double? _rubyOutlineWidth;
  double? _rubyBaseGap;
  double? _lineSpacing;
  late double _lyricsBottomMargin;
  double? _singerAvatarSize;
  late double _singerAvatarGap;
  Timer? _previewDebounce;
  Uint8List? _previewImage;
  bool _isRenderingPreview = false;
  bool _previewQueued = false;
  int _previewRevision = 0;
  String? _previewError;
  bool _showSingerAvatarInPreview = false;

  @override
  void initState() {
    super.initState();
    final value = widget.initialValue;
    _fontSize = value.fontSize;
    _letterSpacingStep = value.letterSpacingStep;
    _decorationWidth = value.decorationWidth;
    _fontOutlineWidth = value.fontOutlineWidth;
    _rubyFontSize = value.rubyFontSize;
    _rubyOutlineWidth = value.rubyOutlineWidth;
    _rubyBaseGap = value.rubyBaseGap;
    _lineSpacing = value.lineSpacing;
    _lyricsBottomMargin = value.lyricsBottomMargin;
    _singerAvatarSize = value.singerAvatarSize;
    _singerAvatarGap = value.singerAvatarGap;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _schedulePreview(immediate: true);
    });
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  double? get _letterSpacingEm =>
      _letterSpacingStep == 0 ? null : (_letterSpacingStep - 21) / 100.0;

  String get _letterSpacingLabel {
    if (_letterSpacingStep == 0) return context.l10n.automatic;
    return '${((_letterSpacingStep - 21) / 100.0).toStringAsFixed(2)} em';
  }

  double get _automaticRubyFontSize => (_fontSize * 36 / 75).roundToDouble();

  double get _resolvedRubyFontSize => _rubyFontSize ?? _automaticRubyFontSize;

  double get _automaticFontOutlineWidth => (_fontSize * 7 / 85).roundToDouble();

  double get _resolvedFontOutlineWidth =>
      _fontOutlineWidth ?? _automaticFontOutlineWidth;

  double get _automaticRubyOutlineWidth {
    final sizeScale = _automaticRubyFontSize > 0
        ? _resolvedRubyFontSize / _automaticRubyFontSize
        : 1.0;
    return (_resolvedFontOutlineWidth * 5 / 7 * sizeScale).roundToDouble();
  }

  double get _automaticRubyBaseGap {
    final spacingEm = _letterSpacingEm ?? 0;
    return (_fontSize * (0.4 + spacingEm) - _automaticRubyFontSize / 2)
        .roundToDouble();
  }

  double get _automaticLineSpacing {
    final spacingEm = _letterSpacingEm ?? 0;
    return (_fontSize * 2.2 +
            _fontSize * spacingEm * 2 +
            (_resolvedRubyFontSize - _automaticRubyFontSize))
        .roundToDouble();
  }

  double get _automaticSingerAvatarSize => (_fontSize * 0.6).roundToDouble();

  String _automaticLabel(double value) =>
      context.l10n.automaticPixels(value.toInt());

  void _updateSettings(VoidCallback update) {
    setState(update);
    _schedulePreview();
  }

  void _schedulePreview({bool immediate = false}) {
    _previewRevision++;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 280),
      _renderPreview,
    );
  }

  Future<void> _renderPreview() async {
    _previewDebounce = null;
    if (!mounted) return;
    if (_isRenderingPreview) {
      _previewQueued = true;
      return;
    }

    _isRenderingPreview = true;
    do {
      if (_previewQueued) {
        _previewDebounce?.cancel();
        _previewDebounce = null;
      }
      _previewQueued = false;
      final revision = _previewRevision;
      if (mounted) {
        setState(() => _previewError = null);
      }

      try {
        final ass = await AssExporter.generateTypographyPreviewAss(
          _buildPreviewSettings(),
        );
        final image = await FfmpegService().renderAssPreview(
          assContent: ass,
          fontSandboxDir: widget.fontSandboxDir,
        );
        if (mounted && revision == _previewRevision) {
          setState(() => _previewImage = image);
        }
      } catch (error) {
        if (mounted && revision == _previewRevision) {
          setState(() => _previewError = error.toString());
        }
      }
    } while (mounted && _previewQueued);

    _isRenderingPreview = false;
    if (mounted) setState(() {});
  }

  void _showFullPreview() {
    if (_previewImage == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Image.memory(_previewImage!, fit: BoxFit.contain),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AssExportSettings _buildPreviewSettings() {
    final base = widget.baseSettings;
    return AssExportSettings(
      fontName: base.fontName,
      customFontPath: base.customFontPath,
      fontFaceIndex: base.fontFaceIndex,
      isBold: base.isBold,
      singerColors: base.singerColors,
      showSingerPrefixesInAss: base.showSingerPrefixesInAss,
      sungTextColor: base.sungTextColor,
      sungOutlineColor: base.sungOutlineColor,
      sungDecorationColor: base.sungDecorationColor,
      unsungTextColor: base.unsungTextColor,
      unsungOutlineColor: base.unsungOutlineColor,
      unsungDecorationColor: base.unsungDecorationColor,
      fontSize: _fontSize.toInt(),
      letterSpacingEm: _letterSpacingEm,
      pagingMode: base.pagingMode,
      twoLineAlignments: base.twoLineAlignments,
      threeLineAlignments: base.threeLineAlignments,
      fourLineAlignments: base.fourLineAlignments,
      interludeThresholdSeconds: base.interludeThresholdSeconds,
      horizontalMargin: base.horizontalMargin,
      outlineWidth: _decorationWidth.toInt(),
      fontOutlineWidth: _fontOutlineWidth?.toInt(),
      rubyFontSize: _rubyFontSize?.toInt(),
      rubyOutlineWidth: _rubyOutlineWidth?.toInt(),
      rubyBaseGap: _rubyBaseGap?.toInt(),
      lineSpacing: _lineSpacing?.toInt(),
      lyricsBottomMargin: _lyricsBottomMargin.toInt(),
      singerAvatarSize: _singerAvatarSize?.toInt(),
      singerAvatarGap: _singerAvatarGap.toInt(),
      singerAvatarPaths: _showSingerAvatarInPreview
          ? base.singerAvatarPaths
          : const {},
      blurLevel: base.blurLevel,
      resolutionHeight: base.resolutionHeight,
    );
  }

  void _resetToDefaults() {
    _updateSettings(() {
      _fontSize = 85.0;
      _letterSpacingStep = 0;
      _decorationWidth = 10.0;
      _fontOutlineWidth = null;
      _rubyFontSize = null;
      _rubyOutlineWidth = null;
      _rubyBaseGap = null;
      _lineSpacing = null;
      _lyricsBottomMargin = 50.0;
      _singerAvatarSize = null;
      _singerAvatarGap = 0.0;
    });
  }

  _TypographySettingsValue get _value => _TypographySettingsValue(
    fontSize: _fontSize,
    letterSpacingStep: _letterSpacingStep,
    decorationWidth: _decorationWidth,
    fontOutlineWidth: _fontOutlineWidth,
    rubyFontSize: _rubyFontSize,
    rubyOutlineWidth: _rubyOutlineWidth,
    rubyBaseGap: _rubyBaseGap,
    lineSpacing: _lineSpacing,
    lyricsBottomMargin: _lyricsBottomMargin,
    singerAvatarSize: _singerAvatarSize,
    singerAvatarGap: _singerAvatarGap,
  );

  @override
  Widget build(BuildContext context) {
    final dialogHeight = min(760.0, MediaQuery.sizeOf(context).height * 0.82);
    return AlertDialog(
      title: Text(context.l10n.textStyle),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SizedBox(
          width: double.maxFinite,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.l10n.preview,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: context.l10n.resetDefaults,
                    onPressed: _resetToDefaults,
                  ),
                  IconButton(
                    icon: Icon(
                      _showSingerAvatarInPreview
                          ? Icons.account_circle
                          : Icons.account_circle_outlined,
                    ),
                    tooltip: context.l10n.showSingerIcon,
                    onPressed: () => _updateSettings(
                      () => _showSingerAvatarInPreview =
                          !_showSingerAvatarInPreview,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 16 / 4.5,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF101218),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_previewImage != null)
                        GestureDetector(
                          onTap: _showFullPreview,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Image.memory(
                              _previewImage!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      if (_previewImage == null && _previewError == null)
                        const Center(child: CircularProgressIndicator()),
                      if (_previewImage == null && _previewError != null)
                        Center(
                          child: Tooltip(
                            message: _previewError!,
                            child: const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 32,
                            ),
                          ),
                        ),
                      if (_previewImage != null && _isRenderingPreview)
                        const Positioned(
                          top: 10,
                          right: 10,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (_previewImage != null && _previewError != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Tooltip(
                            message: _previewError!,
                            child: const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSlider(
                        label: context.l10n.fontSize,
                        valueLabel: '${_fontSize.toInt()} px',
                        value: _fontSize,
                        min: 20,
                        max: 200,
                        divisions: 180,
                        onChanged: (value) =>
                            _updateSettings(() => _fontSize = value),
                      ),
                      _buildSlider(
                        label: context.l10n.letterSpacing,
                        valueLabel: _letterSpacingLabel,
                        value: _letterSpacingStep.toDouble(),
                        min: 0,
                        max: 41,
                        divisions: 41,
                        onChanged: (value) => _updateSettings(
                          () => _letterSpacingStep = value.round(),
                        ),
                      ),
                      _buildSlider(
                        label: context.l10n.decorationWidth,
                        valueLabel: '${_decorationWidth.toInt()} px',
                        value: _decorationWidth,
                        min: 0,
                        max: 30,
                        divisions: 30,
                        onChanged: (value) =>
                            _updateSettings(() => _decorationWidth = value),
                      ),
                      _buildOptionalSlider(
                        label: context.l10n.textOutlineWidth,
                        value: _fontOutlineWidth,
                        automaticValue: _automaticFontOutlineWidth,
                        min: 0,
                        max: 30,
                        divisions: 30,
                        onChanged: (value) =>
                            _updateSettings(() => _fontOutlineWidth = value),
                      ),
                      _buildOptionalSlider(
                        label: context.l10n.furiganaSize,
                        value: _rubyFontSize,
                        automaticValue: _automaticRubyFontSize,
                        min: 8,
                        max: 120,
                        divisions: 112,
                        onChanged: (value) =>
                            _updateSettings(() => _rubyFontSize = value),
                      ),
                      _buildOptionalSlider(
                        label: context.l10n.furiganaOutlineWidth,
                        value: _rubyOutlineWidth,
                        automaticValue: _automaticRubyOutlineWidth,
                        min: 0,
                        max: 30,
                        divisions: 30,
                        onChanged: (value) =>
                            _updateSettings(() => _rubyOutlineWidth = value),
                      ),
                      _buildOptionalSlider(
                        label: context.l10n.furiganaTextGap,
                        value: _rubyBaseGap,
                        automaticValue: _automaticRubyBaseGap,
                        min: -50,
                        max: 150,
                        divisions: 200,
                        onChanged: (value) =>
                            _updateSettings(() => _rubyBaseGap = value),
                      ),
                      _buildOptionalSlider(
                        label: context.l10n.lineSpacing,
                        value: _lineSpacing,
                        automaticValue: _automaticLineSpacing,
                        min: 20,
                        max: 600,
                        divisions: 580,
                        onChanged: (value) =>
                            _updateSettings(() => _lineSpacing = value),
                      ),
                      _buildSlider(
                        label: context.l10n.subtitleBottomMargin,
                        valueLabel: '${_lyricsBottomMargin.toInt()} px',
                        value: _lyricsBottomMargin,
                        min: 0,
                        max: 400,
                        divisions: 400,
                        onChanged: (value) =>
                            _updateSettings(() => _lyricsBottomMargin = value),
                      ),
                      _buildOptionalSlider(
                        label: context.l10n.singerIconSize,
                        value: _singerAvatarSize,
                        automaticValue: _automaticSingerAvatarSize,
                        min: 24,
                        max: 160,
                        divisions: 136,
                        onChanged: (value) =>
                            _updateSettings(() => _singerAvatarSize = value),
                      ),
                      _buildSlider(
                        label: context.l10n.lyricsIconGap,
                        valueLabel: '${_singerAvatarGap.toInt()} px',
                        value: _singerAvatarGap,
                        min: -50,
                        max: 50,
                        divisions: 100,
                        onChanged: (value) =>
                            _updateSettings(() => _singerAvatarGap = value),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: Text(context.l10n.apply),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label：$valueLabel',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildOptionalSlider({
    required String label,
    required double? value,
    required double automaticValue,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double?> onChanged,
  }) {
    final valueLabel = value == null
        ? _automaticLabel(automaticValue)
        : '${value.toInt()} px';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '$label：$valueLabel',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            value: value != null,
            onChanged: (enabled) => onChanged(enabled ? automaticValue : null),
          ),
          if (value != null)
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: value.toInt().toString(),
              onChanged: (nextValue) => onChanged(nextValue),
            ),
        ],
      ),
    );
  }
}

class _AssStyleSamplePainter extends CustomPainter {
  final SingerColorInfo colors;
  final String fontFamily;
  final bool isBold;
  final double assFontSize;
  final double baseOutlineWidth;
  final double decorationWidth;
  final int blurLevel;

  const _AssStyleSamplePainter({
    required this.colors,
    required this.fontFamily,
    required this.isBold,
    required this.assFontSize,
    required this.baseOutlineWidth,
    required this.decorationWidth,
    required this.blurLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final previewFontSize = min(size.height * 0.62, size.width * 0.30);
    final measured = _measureText('永', previewFontSize);
    final offset = Offset(
      (size.width - measured.width) / 2,
      (size.height - measured.height) / 2,
    );
    final splitX = size.width / 2;

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, splitX, size.height));
    _drawSample(
      canvas: canvas,
      text: '永',
      previewFontSize: previewFontSize,
      measured: measured,
      offset: offset,
      textColor: colors.sungTextColor,
      outlineColor: colors.sungOutlineColor,
      decorationColor: colors.sungDecorationColor,
    );
    canvas.restore();

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(splitX, 0, size.width, size.height));
    _drawSample(
      canvas: canvas,
      text: '永',
      previewFontSize: previewFontSize,
      measured: measured,
      offset: offset,
      textColor: colors.unsungTextColor,
      outlineColor: colors.unsungOutlineColor,
      decorationColor: colors.unsungDecorationColor,
    );
    canvas.restore();
  }

  void _drawSample({
    required Canvas canvas,
    required String text,
    required double previewFontSize,
    required TextPainter measured,
    required Offset offset,
    required AssColorValue textColor,
    required AssColorValue outlineColor,
    required AssColorValue decorationColor,
  }) {
    final bounds = offset & measured.size;
    final scale = previewFontSize / max(assFontSize, 1.0);
    final previewBaseOutlineWidth = max(0.0, baseOutlineWidth * scale);
    final previewDecorationWidth = max(0.0, decorationWidth * scale);

    if (previewDecorationWidth > 0) {
      final layers = blurLevel + 1;
      for (int index = 0; index < layers; index++) {
        final layerWidth =
            previewDecorationWidth - index * previewDecorationWidth / layers;
        final glowPaint = _colorPaint(decorationColor, bounds, opacity: 0.72)
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = (previewBaseOutlineWidth + layerWidth) * 2
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            max(0.8, layerWidth * (0.8 + blurLevel * 0.18)),
          );
        _paintText(canvas, text, previewFontSize, offset, glowPaint);
      }
    }

    final outlinePaint = _colorPaint(outlineColor, bounds)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = previewBaseOutlineWidth * 2;
    _paintText(canvas, text, previewFontSize, offset, outlinePaint);

    final fillPaint = _colorPaint(textColor, bounds)
      ..style = PaintingStyle.fill;
    _paintText(canvas, text, previewFontSize, offset, fillPaint);
  }

  TextPainter _measureText(String text, double fontSize) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  Paint _colorPaint(AssColorValue value, Rect bounds, {double opacity = 1}) {
    final paint = Paint()..isAntiAlias = true;
    if (value.isGradient) {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          value.color0.withValues(alpha: opacity),
          value.color100.withValues(alpha: opacity),
        ],
      ).createShader(bounds);
    } else {
      paint.color = value.color0.withValues(alpha: opacity);
    }
    return paint;
  }

  void _paintText(
    Canvas canvas,
    String text,
    double fontSize,
    Offset offset,
    Paint paint,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          foreground: paint,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AssStyleSamplePainter oldDelegate) => true;
}

Future<AssColorValue?> showAssColorPickerDialog(
  BuildContext context, {
  required AssColorValue initialValue,
  required List<Color> suggestedPresets,
  required String title,
}) {
  return showDialog<AssColorValue>(
    context: context,
    builder: (context) => _ColorPickerDialog(
      initialValue: initialValue,
      suggestedPresets: suggestedPresets,
      title: title,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final AssColorValue initialValue;
  final List<Color> suggestedPresets;
  final String title;

  const _ColorPickerDialog({
    required this.initialValue,
    required this.suggestedPresets,
    required this.title,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late AssColorMode _mode;
  late Color _color0;
  late Color _color100;
  int _activeEndpoint = 0;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialValue.mode;
    _color0 = widget.initialValue.color0;
    _color100 = widget.initialValue.color100;
    _hexController = TextEditingController(text: _colorToHex(_activeColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color _activeColor() {
    return _mode == AssColorMode.solid
        ? _color0
        : (_activeEndpoint == 0 ? _color0 : _color100);
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  Color? _tryParseHexColor(String input) {
    final hex = input.trim().replaceFirst('#', '');
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  void _onColorChanged(Color color) {
    setState(() {
      if (_mode == AssColorMode.solid) {
        _color0 = color;
        _color100 = color;
      } else {
        if (_activeEndpoint == 0) {
          _color0 = color;
        } else {
          _color100 = color;
        }
      }
      _hexController.text = _colorToHex(color);
    });
  }

  void _onHexChanged(String text) {
    final parsed = _tryParseHexColor(text);
    if (parsed != null) {
      setState(() {
        if (_mode == AssColorMode.solid) {
          _color0 = parsed;
          _color100 = parsed;
        } else {
          if (_activeEndpoint == 0) {
            _color0 = parsed;
          } else {
            _color100 = parsed;
          }
        }
      });
    }
  }

  Future<void> _showVisualColorPicker() async {
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) =>
          _VisualColorPickerDialog(initialColor: _activeColor()),
    );
    if (selected != null && mounted) _onColorChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _activeColor();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _mode == AssColorMode.gradient ? null : _color0,
                  gradient: _mode == AssColorMode.gradient
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_color0, _color100],
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SegmentedButton<AssColorMode>(
                style: SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                segments: [
                  ButtonSegment(
                    value: AssColorMode.solid,
                    label: Text(context.l10n.solidColor),
                  ),
                  ButtonSegment(
                    value: AssColorMode.gradient,
                    label: Text(context.l10n.gradient),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _mode = selection.first;
                    if (_mode == AssColorMode.solid) {
                      _color100 = _color0;
                      _activeEndpoint = 0;
                    }
                    _hexController.text = _colorToHex(_activeColor());
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_mode == AssColorMode.gradient)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildEndpointTab(
                        title: context.l10n.gradientTop,
                        color: _color0,
                        isActive: _activeEndpoint == 0,
                        onTap: () {
                          setState(() {
                            _activeEndpoint = 0;
                            _hexController.text = _colorToHex(_color0);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildEndpointTab(
                        title: context.l10n.gradientBottom,
                        color: _color100,
                        isActive: _activeEndpoint == 1,
                        onTap: () {
                          setState(() {
                            _activeEndpoint = 1;
                            _hexController.text = _colorToHex(_color100);
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (_mode == AssColorMode.gradient) const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.hexColorCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _hexController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9a-fA-F]'),
                        ),
                        LengthLimitingTextInputFormatter(6),
                      ],
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.tag),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: IconButton(
                            onPressed: _showVisualColorPicker,
                            icon: const Icon(Icons.palette_outlined),
                            tooltip: context.l10n.chooseColor,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                      ),
                      onChanged: _onHexChanged,
                    ),
                    const SizedBox(height: 24),
                    if (widget.suggestedPresets.isNotEmpty) ...[
                      Text(
                        context.l10n.preset,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: widget.suggestedPresets
                            .map(
                              (preset) => _buildColorCircle(
                                preset,
                                activeColor == preset,
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _mode == AssColorMode.solid
                            ? AssColorValue.solid(_color0)
                            : AssColorValue.gradient(
                                color0: _color0,
                                color100: _color100,
                              ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: Text(context.l10n.apply),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointTab({
    required String title,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  if (isActive)
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? theme.colorScheme.onPrimaryContainer : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorCircle(Color color, bool isActive) {
    return GestureDetector(
      onTap: () => _onColorChanged(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? Colors.white : Colors.white24,
            width: isActive ? 3 : 1,
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
          ],
        ),
        child: isActive
            ? Icon(
                Icons.check,
                color: color.computeLuminance() > 0.5
                    ? Colors.black87
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}

class _VisualColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _VisualColorPickerDialog({required this.initialColor});

  @override
  State<_VisualColorPickerDialog> createState() =>
      _VisualColorPickerDialogState();
}

class _VisualColorPickerDialogState extends State<_VisualColorPickerDialog> {
  late HSVColor _hsvColor;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.initialColor);
  }

  void _updateHueSaturation(Offset position, double size) {
    setState(() {
      _hsvColor = _hsvColor.withHue(
        (position.dx / size * 360).clamp(0.0, 360.0),
      );
      _hsvColor = _hsvColor.withSaturation(
        (1 - position.dy / size).clamp(0.0, 1.0),
      );
    });
  }

  void _updateValue(Offset position, double width) {
    setState(() {
      _hsvColor = _hsvColor.withValue((position.dx / width).clamp(0.0, 1.0));
    });
  }

  String _hexValue(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = min(360.0, MediaQuery.sizeOf(context).width - 48);
    final pickerSize = dialogWidth - 48;
    final color = _hsvColor.toColor();

    return Dialog(
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.chooseColor,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTapDown: (details) =>
                    _updateHueSaturation(details.localPosition, pickerSize),
                onPanStart: (details) =>
                    _updateHueSaturation(details.localPosition, pickerSize),
                onPanUpdate: (details) =>
                    _updateHueSaturation(details.localPosition, pickerSize),
                child: CustomPaint(
                  size: Size.square(pickerSize),
                  painter: _HueSaturationPainter(_hsvColor),
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTapDown: (details) =>
                    _updateValue(details.localPosition, pickerSize),
                onPanStart: (details) =>
                    _updateValue(details.localPosition, pickerSize),
                onPanUpdate: (details) =>
                    _updateValue(details.localPosition, pickerSize),
                child: CustomPaint(
                  size: Size(pickerSize, 28),
                  painter: _ValuePainter(_hsvColor),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '#${_hexValue(color)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(color),
                    child: Text(context.l10n.apply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HueSaturationPainter extends CustomPainter {
  final HSVColor color;

  const _HueSaturationPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white],
        ).createShader(rect),
    );

    final marker = Offset(
      color.hue / 360 * size.width,
      (1 - color.saturation) * size.height,
    );
    canvas.drawCircle(marker, 8, Paint()..color = Colors.black54);
    canvas.drawCircle(
      marker,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HueSaturationPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ValuePainter extends CustomPainter {
  final HSVColor color;

  const _ValuePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fullValueColor = color.withValue(1).toColor();
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.black, fullValueColor],
        ).createShader(rect),
    );

    final markerX = color.value * size.width;
    final markerRect = Rect.fromCenter(
      center: Offset(markerX, size.height / 2),
      width: 6,
      height: size.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(markerRect, const Radius.circular(3)),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(markerRect.deflate(1), const Radius.circular(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ValuePainter oldDelegate) => oldDelegate.color != color;
}
