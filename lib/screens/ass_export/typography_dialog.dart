part of '../ass_export_screen.dart';

// Typography settings dialog and its live style sample.

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
      latinFont: base.latinFont,
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
      final sourceStops = value.effectiveStops;
      final colors = <Color>[];
      final positions = <double>[];
      if (value.isMillefeuille && sourceStops.length > 1) {
        // N3 makes a hard band by repeating each colour at the following
        // stop. The final stop is the lower boundary, not another visible
        // band of its own.
        for (var index = 0; index < sourceStops.length - 1; index++) {
          final current = sourceStops[index];
          final next = sourceStops[index + 1];
          colors
            ..add(current.color.withValues(alpha: opacity))
            ..add(current.color.withValues(alpha: opacity));
          positions
            ..add(current.position)
            ..add(next.position);
        }
      } else {
        for (final stop in sourceStops) {
          colors.add(stop.color.withValues(alpha: opacity));
          positions.add(stop.position);
        }
      }
      if (colors.length == 1) {
        colors.add(colors.first);
        positions
          ..clear()
          ..addAll(const [0, 1]);
      }
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: positions,
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
