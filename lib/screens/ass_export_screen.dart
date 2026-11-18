export '../models/ass_export_settings.dart';

import '../utils/constants.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../models/lyric_ast.dart';
import '../models/font_library_asset.dart';
import '../models/ass_export_settings.dart';
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
import '../services/n3_color_import_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter;
import '../services/ffmpeg_service.dart';
import '../services/singer_avatar_library_service.dart';
import '../services/typography_settings_service.dart';
import 'dart:math';
import '../l10n/l10n.dart';
import '../widgets/font_face_preview_text.dart';
import '../widgets/dual_color_preview.dart';
import '../widgets/saved_color_presets_dialog.dart';

part 'ass_export/page_state.dart';
part 'ass_export/singer_color_import.dart';
part 'ass_export/line_alignment_dialog.dart';
part 'ass_export/typography_dialog.dart';
part 'ass_export/color_picker_dialog.dart';

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

  const _FontLibraryChoice.usePrimary()
    : asset = null,
      faceIndex = null,
      useBuiltIn = false,
      openManager = false;
}

String _fontFamilyLabel(OpenTypeFontFaceInfo face) {
  final familyName = face.familyName.trim();
  return familyName.isEmpty ? face.displayName : familyName;
}

String _fontStyleLabel(OpenTypeFontFaceInfo face) {
  final styleName = face.subfamilyName.trim();
  return styleName.isEmpty ? 'Regular' : styleName;
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
  String? _previewFontFamily;

  String? get _customFontPath => _pageState._customFontPath;
  String get _fontName => _pageState._fontName;
  String get _fontDisplayName => _pageState._fontDisplayName;
  String get _fontStyleName => _pageState._fontStyleName;
  int get _fontFaceIndex => _pageState._fontFaceIndex;
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

  Future<void> _loadPersistedPreviewFont() async {
    final path = _customFontPath;
    if (path == null) return;
    final asset = widget.fontLibrary.assets
        .where((asset) => asset.path == path)
        .firstOrNull;
    if (asset == null) return;
    final faceIndex = _fontFaceIndex;
    try {
      final family = await widget.fontLibrary.loadPreviewFontFamily(
        asset: asset,
        faceIndex: faceIndex,
      );
      if (mounted &&
          _customFontPath == path &&
          _fontFaceIndex == faceIndex &&
          _previewFontFamily != family) {
        setState(() => _previewFontFamily = family);
      }
    } catch (error) {
      debugPrint('Failed to load persisted preview font: $error');
    }
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
    final latinPath = _pageState._latinFont?.path;
    if (latinPath != null && !widget.fontLibrary.containsPath(latinPath)) {
      _pageState.applyLatinFontSelection(null);
    }
    final selectedPath = _customFontPath;
    if (selectedPath != null &&
        !widget.fontLibrary.containsPath(selectedPath)) {
      _selectBundledFont();
      return;
    }
    unawaited(_loadPersistedPreviewFont());
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
          title: _defaultColorName,
          sungColor: _sungTextColor,
          unsungColor: _unsungTextColor,
          onTap: _showDefaultColorSettings,
          onDelete: _singerColors.isEmpty ? null : _deleteDefaultColor,
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
              child: OutlinedButton.icon(
                onPressed: _showCurrentSingerColorMarkdownDialog,
                icon: const Icon(Icons.code),
                label: Text(context.l10n.sourceCode),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _addSingerColor,
              icon: const Icon(Icons.add),
              tooltip: context.l10n.addSinger,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(32),
                minimumSize: const Size.square(32),
                maximumSize: const Size.square(32),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTypographySection() {
    final latinFont = _pageState._latinFont;
    return _buildSection(
      title: context.l10n.textSettings,
      children: [
        _buildFontControl(),
        _buildDivider(),
        _buildActionSetting(
          title: context.l10n.latinLyricsFont,
          value: latinFont == null
              ? context.l10n.useJapaneseLyricsFont
              : '${latinFont.displayName} · ${latinFont.styleName}',
          onTap: () => _showFontLibraryPicker(latin: true),
        ),
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
        _buildSwitchSetting(
          title: context.l10n.fadeLyricLines,
          value: _pageState._fadeLyricLines,
          onChanged: (value) =>
              setState(() => _pageState._fadeLyricLines = value),
        ),
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
                  context.l10n.japaneseLyricsFont,
                  style: theme.textTheme.bodySmall,
                ),
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

  void _deleteDefaultColor() {
    if (_singerColors.isEmpty) return;
    setState(() {
      final promoted = _singerColors.removeAt(0);
      _pageState._defaultColorName = promoted.prefix;
      _setDefaultColors(promoted);
      _singerControllers.removeAt(0).dispose();
    });
    _publishActiveColorPresets();
  }

  String get _defaultColorName =>
      _pageState._defaultColorName ?? context.l10n.defaultColors;

  void _setDefaultColors(SingerColorInfo colors) {
    _defaultColorPreset = colors.preset;
    _sungTextColor = colors.sungTextColor;
    _sungOutlineColor = colors.sungOutlineColor;
    _sungDecorationColor = colors.sungDecorationColor;
    _unsungTextColor = colors.unsungTextColor;
    _unsungOutlineColor = colors.unsungOutlineColor;
    _unsungDecorationColor = colors.unsungDecorationColor;
  }

  SingerColorInfo _currentDefaultColors(String name) => SingerColorInfo(
    prefix: name,
    preset: _defaultColorPreset,
    sungTextColor: _sungTextColor,
    sungOutlineColor: _sungOutlineColor,
    sungDecorationColor: _sungDecorationColor,
    unsungTextColor: _unsungTextColor,
    unsungOutlineColor: _unsungOutlineColor,
    unsungDecorationColor: _unsungDecorationColor,
  );

  List<SingerColorInfo> _singerColorsForMatching() {
    final promotedName = _pageState._defaultColorName?.trim();
    if (promotedName == null ||
        promotedName.isEmpty ||
        _singerColors.any((singer) => singer.prefix.trim() == promotedName)) {
      return List.of(_singerColors);
    }
    return [_currentDefaultColors(promotedName), ..._singerColors];
  }

  String _serializeCurrentSingerColors() {
    final header = <String>[
      context.l10n.singerName,
      context.l10n.sungTextColor,
      context.l10n.sungOutlineColor,
      context.l10n.sungDecorationColor,
      context.l10n.unsungTextColor,
      context.l10n.unsungOutlineColor,
      context.l10n.unsungDecorationColor,
    ];
    final rows = [
      _currentDefaultColors(_defaultColorName),
      ..._singerColors,
    ].map((singer) => _colorMarkdownRow(singer, singer.prefix.trim()));
    return [
      '| ${header.join(' | ')} |',
      '| ${List.filled(header.length, '---').join(' | ')} |',
      ...rows,
    ].join('\n');
  }

  String _colorMarkdownName(String name) =>
      name.replaceAll('|', '｜').replaceAll(RegExp(r'[\r\n]+'), ' ');

  String _colorMarkdownRow(SingerColorInfo singer, String name) {
    final safeName = _colorMarkdownName(name);
    final fields = _colorPresetFromSinger(safeName, singer).toMarkdownFields();
    return '| ${fields.join(' | ')} |';
  }

  Future<void> _showCurrentSingerColorMarkdownDialog() async {
    final result = await showDialog<_SingerColorImportParseResult>(
      context: context,
      builder: (context) => _SingerColorImportDialog(
        initialText: _serializeCurrentSingerColors(),
        title: context.l10n.currentSingerColorMarkdown,
        titleIcon: Icons.code,
        confirmLabel: context.l10n.apply,
        requireAllRowsValid: true,
        defaultColorsName: _colorMarkdownName(_defaultColorName.trim()).trim(),
      ),
    );
    if (result == null || !mounted) return;

    for (final controller in _singerControllers) {
      controller.dispose();
    }
    setState(() {
      final defaultColors = result.defaultColors;
      if (defaultColors != null) {
        _setDefaultColors(defaultColors);
      }
      _singerColors
        ..clear()
        ..addAll(result.singers);
      _singerControllers
        ..clear()
        ..addAll(
          result.singers.map(
            (singer) => TextEditingController(text: singer.prefix),
          ),
        );
    });
    _publishActiveColorPresets();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.currentSingerColorMarkdownApplied(result.singers.length),
        ),
      ),
    );
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

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => SavedColorPresetsScreen(
          library: widget.colorPresetLibrary,
          onAdd: _addSavedColorPresetToCurrent,
          onEdit: _editSavedColorPreset,
          onRename: _renameSavedColorPreset,
          onDelete: _deleteSavedColorPreset,
          onImport: _showSavedColorPresetImportDialog,
          onImportN3: _showSavedColorPresetN3ImportDialog,
        ),
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

  Future<bool> _renameSavedColorPreset(
    ColorPresetAsset preset,
    String newName,
  ) async {
    final name = newName.trim();
    if (name == preset.name) return true;
    final validation = widget.colorPresetLibrary.validateName(name);
    if (validation != null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            validation == 'empty'
                ? context.l10n.colorPresetNameRequired
                : context.l10n.colorPresetNameInvalid,
          ),
        ),
      );
      return false;
    }
    try {
      await widget.colorPresetLibrary.rename(preset, name);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.colorPresetRenamed(name))),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed(error))),
      );
      return false;
    }
  }

  Future<void> _editSavedColorPreset(ColorPresetAsset preset) async {
    final result = await _showColorSettingsDialog(
      edited: _singerFromColorPreset(preset),
      title: context.l10n.singerColorsTitle(preset.name),
      fillPrefixFromPreset: false,
      allowSavePreset: false,
    );
    if (result == null || !mounted) return;
    try {
      final saved = await widget.colorPresetLibrary.save(
        _colorPresetFromSinger(preset.name, result),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.colorPresetSaved(saved.name))),
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

  Future<void> _showSavedColorPresetN3ImportDialog() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['n3proj'],
        withData: true,
      );
      if (picked == null || !mounted) return;
      final file = picked.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const FileSystemException('Unable to read the selected file.');
      }
      final presets = N3ColorImportService().importBytes(bytes);
      if (!mounted) return;
      const header = ColorPresetLibraryService.markdownHeader;
      final rows = presets.map((preset) {
        final fields = preset.toMarkdownFields();
        fields[0] = fields[0]
            .replaceAll('|', '｜')
            .replaceAll(RegExp(r'[\r\n]+'), ' ');
        return '| ${fields.join(' | ')} |';
      });
      final markdown = [
        '| ${header.join(' | ')} |',
        '| ${List.filled(header.length, '---').join(' | ')} |',
        ...rows,
      ].join('\n');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.n3ColorImportLoaded(presets.length)),
        ),
      );
      await _showSavedColorPresetImportDialog(initialText: markdown);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.n3ColorImportFailed(error))),
      );
    }
  }

  Future<void> _showSavedColorPresetImportDialog({String? initialText}) async {
    final savedMarkdown =
        initialText ?? await widget.colorPresetLibrary.readMarkdown();
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

    final existingNames = widget.colorPresetLibrary.presets
        .map((preset) => preset.name.trim().toLowerCase())
        .toSet();
    var updatedCount = 0;
    var addedCount = 0;
    final presets = result.singers
        .map((singer) {
          final name = singer.prefix.trim();
          if (existingNames.contains(name.toLowerCase())) {
            updatedCount++;
          } else {
            addedCount++;
            existingNames.add(name.toLowerCase());
          }
          return _colorPresetFromSinger(name, singer);
        })
        .toList(growable: false);

    try {
      await widget.colorPresetLibrary.saveAll(presets);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed(error))),
      );
      return;
    }
    if (!mounted) return;

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
    if (!value.isGradient) {
      return ColorPresetValue.solid(value.color0.toARGB32());
    }
    return ColorPresetValue.withStops(
      mode: value.isMillefeuille
          ? ColorFillMode.millefeuille
          : ColorFillMode.gradient,
      stops: value.effectiveStops.map(
        (stop) => ColorPresetStop(
          position: stop.position,
          color: stop.color.toARGB32(),
        ),
      ),
    );
  }

  AssColorValue _fromPresetValue(ColorPresetValue value) {
    if (!value.isGradient) return AssColorValue.solid(Color(value.color0));
    return AssColorValue.withStops(
      mode: value.isMillefeuille
          ? AssColorMode.millefeuille
          : AssColorMode.gradient,
      stops: value.stops
          .map(
            (stop) =>
                AssColorStop(position: stop.position, color: Color(stop.color)),
          )
          .toList(growable: false),
    );
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
      _singerColorsForMatching()
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
    final result = await _showColorSettingsDialog(
      edited: _currentDefaultColors(_defaultColorName),
      title: _defaultColorName,
      fillPrefixFromPreset: false,
    );
    if (result != null && mounted) {
      setState(() => _setDefaultColors(result));
      _publishActiveColorPresets();
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
    bool allowSavePreset = true,
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
                                fontFamily: _previewFontFamily ?? 'KosugiMaru',
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
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.sungTextColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.outlineColor,
                            value: edited.sungOutlineColor,
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.sungOutlineColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.decorationColor,
                            value: edited.sungDecorationColor,
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
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.unsungTextColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.outlineColor,
                            value: edited.unsungOutlineColor,
                            setDialogState: setDialogState,
                            onChanged: (value) {
                              edited.unsungOutlineColor = value;
                              edited.preset = SingerColorPreset.none;
                            },
                          ),
                          _buildSingerDialogColorSetting(
                            label: context.l10n.decorationColor,
                            value: edited.unsungDecorationColor,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: context.l10n.copyColorCode,
                      onPressed: () async {
                        final prefix = edited.prefix.trim();
                        final row = _colorMarkdownRow(
                          edited,
                          prefix.isEmpty ? context.l10n.defaultColors : prefix,
                        );
                        await Clipboard.setData(ClipboardData(text: row));
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(ctx.l10n.copiedToClipboard)),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    if (allowSavePreset)
                      IconButton(
                        tooltip: context.l10n.saveColorPreset,
                        onPressed: () async {
                          final preset = await _saveCurrentColorPreset(edited);
                          if (preset == null || !ctx.mounted) return;
                          if (fillPrefixFromPreset &&
                              edited.prefix.trim().isEmpty) {
                            setDialogState(() => edited.prefix = preset.name);
                          }
                        },
                        icon: const Icon(Icons.save_outlined),
                      ),
                  ],
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
        latinFont: _pageState._latinFont,
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
        fontName: _fontName,
        customFontPath: _customFontPath,
        fontFaceIndex: _fontFaceIndex,
        fontDisplayName: _fontDisplayName,
        fontStyleName: _fontStyleName,
        latinFont: _pageState._latinFont,
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
      latinFont: _pageState._latinFont,
      fadeLyricLines: _pageState._fadeLyricLines,
      isBold: _isBold,
      singerColors: _singerColorsForMatching(),
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
      latinFont: settings.latinFont,
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

  Future<void> _showFontLibraryPicker({bool latin = false}) async {
    await widget.fontLibrary.refresh();
    if (!mounted) return;
    final latinFont = _pageState._latinFont;
    final selectedPath = latin ? latinFont?.path : _customFontPath;
    final selectedFaceIndex = latin ? latinFont?.faceIndex : _fontFaceIndex;
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
                        latin
                            ? context.l10n.latinLyricsFont
                            : context.l10n.chooseFont,
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
                      (latin ? 2 : 1) +
                      fontChoices.length +
                      (fontChoices.isEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (latin && index == 0) {
                      return ListTile(
                        leading: const Icon(Icons.text_fields),
                        title: Text(context.l10n.useJapaneseLyricsFont),
                        trailing: latinFont == null
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(
                          context,
                          const _FontLibraryChoice.usePrimary(),
                        ),
                      );
                    }
                    if (latin) index--;
                    if (index == 0) {
                      return ListTile(
                        leading: const Icon(Icons.text_fields),
                        title: Text(
                          FontService.bundledFontFamily,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontFamily: 'KosugiMaru'),
                        ),
                        subtitle: const Text('Regular'),
                        trailing: selectedPath == null && selectedFaceIndex == 0
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
                        selectedPath == asset.path &&
                        selectedFaceIndex == face.index;
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
    } else if (latin) {
      final asset = selected.asset;
      final face = asset?.faces.firstWhere(
        (item) => item.index == selected.faceIndex,
      );
      final selection = switch (face) {
        final chosen? => FontFaceSelection(
          path: asset!.path,
          faceIndex: chosen.index,
          displayName: _fontFamilyLabel(chosen),
          styleName: _fontStyleLabel(chosen),
        ),
        null when selected.useBuiltIn => const FontFaceSelection(
          path: null,
          faceIndex: 0,
          displayName: FontService.bundledFontFamily,
          styleName: 'Regular',
        ),
        null => null,
      };
      setState(() => _pageState.applyLatinFontSelection(selection));
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
      final family = await widget.fontLibrary.loadPreviewFontFamily(
        asset: asset,
        faceIndex: face.index,
      );
      if (!mounted) return;
      setState(() {
        _previewFontFamily = family;
        _pageState.applyFontSelection(
          customFontPath: asset.path,
          fontFaceIndex: face.index,
          fontName: face.assFontName,
          fontDisplayName: _fontFamilyLabel(face),
          fontStyleName: _fontStyleLabel(face),
        );
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
      _previewFontFamily = null;
      _pageState.applyFontSelection(
        customFontPath: null,
        fontFaceIndex: 0,
        fontName: FontService.bundledFontFamily,
        fontDisplayName: FontService.bundledFontFamily,
        fontStyleName: 'Regular',
      );
    });
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
        right: onDelete == null ? 16 : 8,
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
            if (onDelete != null) ...[
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

  List<Color> _currentSingerPresetColors() {
    final colors = <Color>[];
    final seen = <int>{};

    void addValue(AssColorValue value) {
      for (final stop in value.effectiveStops) {
        if (seen.add(stop.color.toARGB32())) colors.add(stop.color);
      }
    }

    for (final singer in _singerColors) {
      addValue(singer.sungTextColor);
      addValue(singer.sungOutlineColor);
      addValue(singer.sungDecorationColor);
      addValue(singer.unsungTextColor);
      addValue(singer.unsungOutlineColor);
      addValue(singer.unsungDecorationColor);
    }
    return colors;
  }

  Future<AssColorValue?> _showColorPicker(
    AssColorValue initialValue, {
    String? title,
  }) async {
    return showAssColorPickerDialog(
      context,
      initialValue: initialValue,
      suggestedPresets: _currentSingerPresetColors(),
      title: title ?? context.l10n.chooseColor,
    );
  }
}
