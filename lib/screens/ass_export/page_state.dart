part of '../ass_export_screen.dart';

// State of the ASS export page that outlives the screen widget.

class AssExportPageState {
  final TypographySettingsService _typographySettingsService =
      TypographySettingsService();
  int _typographyRevision = 0;
  String? _customFontPath;
  String _fontName = FontService.bundledFontFamily;
  String _fontDisplayName = FontService.bundledFontFamily;
  String _fontStyleName = 'Regular';
  int _fontFaceIndex = 0;
  FontFaceSelection? _latinFont;
  bool _fadeLyricLines = false;
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
  String? _defaultColorName;
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
    fontName: _fontName,
    customFontPath: _customFontPath,
    fontFaceIndex: _fontFaceIndex,
    fontDisplayName: _fontDisplayName,
    fontStyleName: _fontStyleName,
    latinFont: _latinFont,
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
    _fontName = settings.fontName;
    _customFontPath = settings.customFontPath;
    _fontFaceIndex = settings.fontFaceIndex;
    _fontDisplayName = settings.fontDisplayName;
    _fontStyleName = settings.fontStyleName;
    _latinFont = settings.latinFont;
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

  void applyFontSelection({
    required String fontName,
    required String? customFontPath,
    required int fontFaceIndex,
    required String fontDisplayName,
    required String fontStyleName,
  }) {
    _typographyRevision++;
    _fontName = fontName;
    _customFontPath = customFontPath;
    _fontFaceIndex = fontFaceIndex;
    _fontDisplayName = fontDisplayName;
    _fontStyleName = fontStyleName;
    unawaited(_saveTypographySettings(_typographySettings));
  }

  void applyLatinFontSelection(FontFaceSelection? font) {
    _typographyRevision++;
    _latinFont = font;
    unawaited(_saveTypographySettings(_typographySettings));
  }

  Future<void> _saveTypographySettings(TypographySettingsData settings) async {
    try {
      await _typographySettingsService.save(settings);
    } catch (error) {
      debugPrint('Failed to save typography settings: $error');
    }
  }
}
