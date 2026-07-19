import '../utils/constants.dart';
import 'package:flutter/material.dart';

import '../models/lyric_ast.dart';
import '../services/ass_exporter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'ass_preview_screen.dart';

import '../services/font_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show FontLoader;
import '../services/ffmpeg_service.dart';
import 'dart:math';

enum AssPagingMode { auto2Lines, emptyLineDelimited }

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

  const AssColorValue.gradient({
    required this.color0,
    required this.color100,
  }) : mode = AssColorMode.gradient;

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
  final List<SingerColorInfo> singerColors;
  final bool showSingerPrefixesInAss;
  final AssColorValue sungTextColor;
  final AssColorValue sungOutlineColor;
  final AssColorValue sungDecorationColor;
  final AssColorValue unsungTextColor;
  final AssColorValue unsungOutlineColor;
  final AssColorValue unsungDecorationColor;
  final int fontSize;
  final AssPagingMode pagingMode;
  final int interludeThresholdSeconds;
  final int horizontalMargin;
  final int outlineWidth;
  final int blurLevel;
  final int resolutionHeight;

  AssExportSettings({
    required this.fontName,
    this.customFontPath,
    required this.singerColors,
    required this.showSingerPrefixesInAss,
    required this.sungTextColor,
    required this.sungOutlineColor,
    required this.sungDecorationColor,
    required this.unsungTextColor,
    required this.unsungOutlineColor,
    required this.unsungDecorationColor,
    required this.fontSize,
    required this.pagingMode,
    required this.interludeThresholdSeconds,
    required this.horizontalMargin,
    required this.outlineWidth,
    required this.blurLevel,
    required this.resolutionHeight,
  });
}

class AssExportScreen extends StatefulWidget {
  final Widget? drawer;
  final Future<void> Function(AssExportSettings settings) onExport;
  final Future<void> Function(AssExportSettings settings)? onExportVideo;
  final String? mediaFilePath;
  final LyricDocument? document;

  const AssExportScreen({
    super.key,
    this.drawer,
    required this.onExport,
    this.onExportVideo,
    this.mediaFilePath,
    this.document,
  });

  @override
  State<AssExportScreen> createState() => _AssExportScreenState();
}

class _AssExportScreenState extends State<AssExportScreen> {
  static const Map<SingerColorPreset, _SingerColorPalette>
  _singerColorPresets = {
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
  };

  String? _customFontPath;
  final List<SingerColorInfo> _singerColors = [];
  final List<TextEditingController> _singerControllers = [];
  bool _showSingerPrefixesInAss = false;
  AssColorValue _sungTextColor = const AssColorValue.solid(
    Color(0xFF0000AF),
  );
  AssColorValue _sungOutlineColor = const AssColorValue.solid(
    Color(0xFFFFFFFF),
  );
  AssColorValue _sungDecorationColor = const AssColorValue.solid(
    Color(0xFFFFE196),
  );
  AssColorValue _unsungTextColor = const AssColorValue.solid(
    Color(0xFFFFFFFF),
  );
  AssColorValue _unsungOutlineColor = const AssColorValue.solid(
    Color(0xFF000000),
  );
  AssColorValue _unsungDecorationColor = const AssColorValue.solid(
    Color(0xFF96BFFF),
  );
  SingerColorPreset _defaultColorPreset = SingerColorPreset.none;
  double _fontSize = 85.0;
  double _outlineWidth = 10.0;
  int _blurLevel = 0;
  int _resolutionHeight = 1080;
  AssPagingMode _pagingMode = AssPagingMode.auto2Lines;
  double _interludeThreshold = 10.0;
  int _horizontalMargin = 100;
  late TextEditingController _fontController;
  late TextEditingController _resolutionController;
  bool _isExporting = false;
  int? _baselineResolutionHeight;
  final Set<String> _loadedPreviewFonts = {};

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

  final List<Color> _presetSungOutlineColors = [
    const Color(0xFFFFFFFF),
  ];

  final List<Color> _presetUnsungOutlineColors = [
    const Color(0xFF000000),
  ];

  final List<Color> _presetSungDecorationColors = [
    const Color(0xFFFFE196),
  ];

  final List<Color> _presetUnsungTextColors = [
    const Color(0xFFE1E1FF),
    const Color(0xFFFFEBEB),
    const Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    _fontController = TextEditingController(text: 'Kosugi Maru');
    _resolutionController = TextEditingController(
      text: _resolutionHeight.toString(),
    );
    _resolutionController.addListener(_onResolutionTextChanged);
    _initVideoResolution();
  }

  @override
  void didUpdateWidget(AssExportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mediaFilePath != oldWidget.mediaFilePath) {
      _initVideoResolution();
    }
  }

  void _onResolutionTextChanged() {
    final h = int.tryParse(_resolutionController.text);
    if (h != null && h != _resolutionHeight) {
      setState(() => _resolutionHeight = h);
    }
  }

  Future<void> _initVideoResolution() async {
    if (widget.mediaFilePath != null) {
      final res = await FfmpegService().getVideoResolution(
        widget.mediaFilePath!,
      );
      if (res != null && mounted) {
        int w = res.width;
        int h = res.height;
        int paddedHeight = (max(h.toDouble(), w * 9.0 / 16.0) / 2.0).ceil() * 2;
        setState(() {
          _baselineResolutionHeight = paddedHeight;
          _resolutionHeight = paddedHeight;
          _resolutionController.text = paddedHeight.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _resolutionController.removeListener(_onResolutionTextChanged);
    _fontController.dispose();
    _resolutionController.dispose();
    for (var c in _singerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        title: const Text('ASS 出力'),
        actions: [
          IconButton(
            onPressed: (widget.mediaFilePath == null || widget.document == null)
                ? null
                : _previewAss,
            icon: const Icon(Icons.play_circle_outline),
            tooltip: 'プレビュー',
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
            tooltip: '出力',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '配色スタイル',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              '行頭文字が一致した行から、次の指定が見つかるまで専用の配色を適用します。複数一致する場合は長い行頭文字を優先します。',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 16),
            _buildSingerColorCard(
              isDefault: true,
              title: 'デフォルト配色',
              colorValue: _sungTextColor,
              onTap: _showDefaultColorSettings,
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _singerColors.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildSingerColorCard(
                  isDefault: false,
                  controller: _singerControllers[i],
                  colorValue: _singerColors[i].sungTextColor,
                  onTap: () => _showSingerColorSettings(i),
                  onDelete: () {
                    setState(() {
                      _singerColors.removeAt(i);
                      _singerControllers[i].dispose();
                      _singerControllers.removeAt(i);
                    });
                  },
                  onPrefixChanged: (val) {
                    _singerColors[i].prefix = val;
                  },
                ),
              ),
            const SizedBox(height: 8),
            ActionChip(
              onPressed: () {
                setState(() {
                  _singerColors.add(
                    SingerColorInfo(
                      prefix: '●',
                      sungTextColor: _sungTextColor,
                      sungOutlineColor: _sungOutlineColor,
                      sungDecorationColor: _sungDecorationColor,
                      unsungTextColor: _unsungTextColor,
                      unsungOutlineColor: _unsungOutlineColor,
                      unsungDecorationColor: _unsungDecorationColor,
                    ),
                  );
                  _singerControllers.add(TextEditingController(text: '●'));
                });
              },
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('配色スタイルを追加'),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: SwitchListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: const Text(
                  '行頭文字を字幕に表示',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  '出力する字幕に行頭文字（●など）を含めます',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                value: _showSingerPrefixesInAss,
                onChanged: (value) {
                  setState(() => _showSingerPrefixesInAss = value);
                },
                activeColor: Theme.of(context).colorScheme.primary,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              '字幕フォント',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fontController,
              readOnly: _customFontPath != null,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: 'フォント名',
                filled: _customFontPath != null,
                fillColor: _customFontPath != null
                    ? Colors.grey.withValues(alpha: 0.2)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  label: const Text('Kosugi Maru'),
                  onPressed: () {
                    setState(() {
                      _fontController.text = 'Kosugi Maru';
                    });
                  },
                ),
                ActionChip(
                  label: const Text('BIZ UDPGothic'),
                  onPressed: () {
                    setState(() {
                      _fontController.text = 'BIZ UDPGothic';
                    });
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.file_open, size: 16),
                  label: Text(
                    _customFontPath == null
                        ? 'フォントファイルを選択'
                        : '選択済み：${_customFontPath!.split(RegExp(r'[/\\]')).last}',
                  ),
                  onPressed: _pickCustomFont,
                ),
                if (_customFontPath != null)
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 16),
                    label: const Text('選択解除'),
                    onPressed: () {
                      setState(() {
                        _customFontPath = null;
                        _fontController.text = 'Kosugi Maru';
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'フォントサイズ：${_fontSize.toInt()} px',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            Slider(
              value: _fontSize,
              min: 20,
              max: 200,
              divisions: 180,
              label: _fontSize.toInt().toString(),
              onChanged: (val) => setState(() => _fontSize = val),
            ),
            const SizedBox(height: 24),
            Text(
              '縁の幅：${_outlineWidth.toInt()} px',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            Slider(
              value: _outlineWidth,
              min: 0,
              max: 30,
              divisions: 30,
              label: _outlineWidth.toInt().toString(),
              onChanged: (val) => setState(() => _outlineWidth = val),
            ),
            const SizedBox(height: 24),
            Text(
              'ブラー：$_blurLevel',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            Slider(
              value: _blurLevel.toDouble(),
              min: 0,
              max: 2,
              divisions: 2,
              label: _blurLevel.toString(),
              onChanged: (val) => setState(() => _blurLevel = val.toInt()),
            ),
            const SizedBox(height: 24),
            const Text(
              '出力解像度',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownMenu<int>(
                    controller: _resolutionController,
                    label: const Text('高さ（px）'),
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 720, label: '720'),
                      DropdownMenuEntry(value: 1080, label: '1080'),
                      DropdownMenuEntry(value: 1440, label: '1440'),
                      DropdownMenuEntry(value: 2160, label: '2160'),
                    ],
                    onSelected: (val) {
                      if (val != null) {
                        _resolutionController.text = val.toString();
                      }
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Icon(Icons.close),
                ),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(
                      text: '${(_resolutionHeight * 16 / 9).round()}',
                    ),
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: '幅（px）',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                if (_baselineResolutionHeight != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '元動画の解像度に戻す',
                    child: IconButton(
                      icon: const Icon(Icons.restore),
                      onPressed: () {
                        _resolutionController.text = _baselineResolutionHeight!
                            .toString();
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              '字幕配置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AssPagingMode>(
              initialValue: _pagingMode,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                  value: AssPagingMode.auto2Lines,
                  child: Text('2 行交互表示（左上／右下）'),
                ),
                DropdownMenuItem(
                  value: AssPagingMode.emptyLineDelimited,
                  child: Text('空行ごとに段落分け'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _pagingMode = val);
              },
            ),
            const SizedBox(height: 32),
            Text(
              '間奏判定時間：${_interludeThreshold.toInt()} 秒',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const Text(
              'フレーズ間がこの時間を超えると、間奏カウントダウンを表示します。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Slider(
              value: _interludeThreshold,
              min: 5,
              max: 60,
              divisions: 55,
              label: '${_interludeThreshold.toInt()} 秒',
              onChanged: (val) => setState(() => _interludeThreshold = val),
            ),
            const SizedBox(height: 24),
            Text(
              '水平余白：$_horizontalMargin px',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const Text(
              '短い歌詞を中央寄りに配置するための余白です（スマート水平配置）。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Slider(
              value: _horizontalMargin.toDouble(),
              min: 0,
              max: 300,
              divisions: 60,
              label: '$_horizontalMargin px',
              onChanged: (val) =>
                  setState(() => _horizontalMargin = val.toInt()),
            ),
            const SizedBox(height: 80), // Padding for scrolling
          ],
        ),
      ),
    );
  }

  String _singerPresetLabel(SingerColorPreset preset) {
    return switch (preset) {
      SingerColorPreset.none => 'プリセットなし',
      SingerColorPreset.blue => '青配色',
      SingerColorPreset.standard => '標準配色',
      SingerColorPreset.chorus => 'コーラス配色',
      SingerColorPreset.blue2 => '青配色2',
      SingerColorPreset.purple => '紫',
      SingerColorPreset.bluePurple => '青紫混',
      SingerColorPreset.ciel => 'CIEL',
      SingerColorPreset.sooda => 'Sooda',
      SingerColorPreset.kusou => '空爽',
    };
  }

  void _applySingerPreset(
    SingerColorInfo singer,
    SingerColorPreset preset,
  ) {
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
      title: 'デフォルト配色',
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
      title: '${_singerColors[index].prefix}の配色',
    );
    if (result != null && mounted) {
      setState(() => _singerColors[index] = result);
    }
  }

  Future<SingerColorInfo?> _showColorSettingsDialog({
    required SingerColorInfo edited,
    required String title,
  }) {
    return showDialog<SingerColorInfo>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 440,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '配色プリセット',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<SingerColorPreset>(
                          key: ValueKey(edited.preset),
                          initialValue: edited.preset,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          items: [
                            for (final preset in SingerColorPreset.values)
                              DropdownMenuItem(
                                value: preset,
                                child: Text(_singerPresetLabel(preset)),
                              ),
                          ],
                          onChanged: (preset) {
                            if (preset != null) {
                              setDialogState(
                                () => _applySingerPreset(edited, preset),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'サンプル',
                          style: TextStyle(
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
                              assFontSize: _fontSize,
                              decorationWidth: _outlineWidth,
                              blurLevel: _blurLevel,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          '歌唱済みの配色',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildSingerDialogColorSetting(
                          label: '文字色',
                          value: edited.sungTextColor,
                          presets: _presetColors,
                          setDialogState: setDialogState,
                          onChanged: (value) {
                            edited.sungTextColor = value;
                            edited.preset = SingerColorPreset.none;
                          },
                        ),
                        _buildSingerDialogColorSetting(
                          label: '縁取り色',
                          value: edited.sungOutlineColor,
                          presets: _presetSungOutlineColors,
                          setDialogState: setDialogState,
                          onChanged: (value) {
                            edited.sungOutlineColor = value;
                            edited.preset = SingerColorPreset.none;
                          },
                        ),
                        _buildSingerDialogColorSetting(
                          label: '飾り色',
                          value: edited.sungDecorationColor,
                          presets: _presetSungDecorationColors,
                          setDialogState: setDialogState,
                          onChanged: (value) {
                            edited.sungDecorationColor = value;
                            edited.preset = SingerColorPreset.none;
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '未歌唱の配色',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildSingerDialogColorSetting(
                          label: '文字色',
                          value: edited.unsungTextColor,
                          presets: _presetUnsungTextColors,
                          setDialogState: setDialogState,
                          onChanged: (value) {
                            edited.unsungTextColor = value;
                            edited.preset = SingerColorPreset.none;
                          },
                        ),
                        _buildSingerDialogColorSetting(
                          label: '縁取り色',
                          value: edited.unsungOutlineColor,
                          presets: _presetUnsungOutlineColors,
                          setDialogState: setDialogState,
                          onChanged: (value) {
                            edited.unsungOutlineColor = value;
                            edited.preset = SingerColorPreset.none;
                          },
                        ),
                        _buildSingerDialogColorSetting(
                          label: '飾り色',
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(edited),
                  child: const Text('適用'),
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
            title: '$labelを選択',
          );
          if (selected != null) {
            setDialogState(() => onChanged(selected));
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
        BoxShadow(
          color: representative.withValues(alpha: 0.5),
          blurRadius: 8,
        ),
      ],
    );
  }

  AssExportSettings _getCurrentSettings() {
    return AssExportSettings(
      fontName: _fontController.text.trim().isEmpty
          ? 'Kosugi Maru'
          : _fontController.text.trim(),
      customFontPath: _customFontPath,
      singerColors: _singerColors,
      showSingerPrefixesInAss: _showSingerPrefixesInAss,
      sungTextColor: _sungTextColor,
      sungOutlineColor: _sungOutlineColor,
      sungDecorationColor: _sungDecorationColor,
      unsungTextColor: _unsungTextColor,
      unsungOutlineColor: _unsungOutlineColor,
      unsungDecorationColor: _unsungDecorationColor,
      fontSize: _fontSize.toInt(),
      pagingMode: _pagingMode,
      interludeThresholdSeconds: _interludeThreshold.toInt(),
      horizontalMargin: _horizontalMargin,
      outlineWidth: _outlineWidth.toInt(),
      blurLevel: _blurLevel,
      resolutionHeight: _resolutionHeight,
    );
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
                title: const Text('ASS 字幕を出力'),
                subtitle: const Text('ASS 字幕ファイル（.ass）を保存します'),
                onTap: () {
                  Navigator.pop(ctx);
                  _executeExport(widget.onExport);
                },
              ),
              ListTile(
                leading: const Icon(Icons.movie_creation),
                title: const Text('字幕付き動画を出力'),
                subtitle: Text(
                  isVideo
                      ? '字幕を動画に焼き付けて保存します'
                      : '動画を読み込んだ場合のみ利用できます',
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

    final settings = _getCurrentSettings();

    // We no longer require the user to manually pick a font.
    // The embedded font will be extracted during export.

    try {
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
    if (settings.customFontPath != null) {
      await fontService.processAndSandboxFont(settings.customFontPath!);
    } else {
      await fontService.extractBundledFont();
    }
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

  Future<void> _pickCustomFont() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
    );
    if (result != null && result.files.single.path != null) {
      try {
        final fontService = FontService();
        final internalName = await fontService.processAndSandboxFont(
          result.files.single.path!,
        );
        await _loadPreviewFont(result.files.single.path!, internalName);
        setState(() {
          _customFontPath = result.files.single.path;
          _fontController.text = internalName;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('フォントの解析に失敗しました：$e')));
        }
      }
    }
  }

  String get _previewFontFamily {
    final fontName = _fontController.text.trim();
    if (_customFontPath == null && fontName == 'Kosugi Maru') {
      return 'KosugiMaru';
    }
    return fontName.isEmpty ? 'KosugiMaru' : fontName;
  }

  Future<void> _loadPreviewFont(String path, String family) async {
    final fontKey = '$family|$path';
    if (_loadedPreviewFonts.contains(fontKey)) return;

    final bytes = await File(path).readAsBytes();
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
    required AssColorValue colorValue,
    required VoidCallback onTap,
    VoidCallback? onDelete,
    ValueChanged<String>? onPrefixChanged,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (isDefault)
            Expanded(
              child: Text(
                title ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '行頭文字（例：●）',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                onChanged: onPrefixChanged,
              ),
            ),
          const SizedBox(width: 16),
          Tooltip(
            message: isDefault ? 'デフォルト配色を編集' : 'この配色を編集',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: _colorValueDecoration(
                    colorValue,
                    borderWidth: 1.5,
                  ),
                ),
              ),
            ),
          ),
          if (!isDefault) ...[
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 24,
              color: Colors.white24,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.redAccent,
              onPressed: onDelete,
              tooltip: '削除',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }

  Future<AssColorValue?> _showColorPicker(
    AssColorValue initialValue,
    List<Color> presets, {
    String title = '色を選択',
  }) async {
    return await showDialog<AssColorValue>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(
        initialValue: initialValue,
        suggestedPresets: presets,
        title: title,
      ),
    );
  }
}

class _AssStyleSamplePainter extends CustomPainter {
  final SingerColorInfo colors;
  final String fontFamily;
  final double assFontSize;
  final double decorationWidth;
  final int blurLevel;

  const _AssStyleSamplePainter({
    required this.colors,
    required this.fontFamily,
    required this.assFontSize,
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
    final baseOutlineWidth = previewFontSize * 7 / 85;
    final previewDecorationWidth = max(0.0, decorationWidth * scale);

    if (previewDecorationWidth > 0) {
      final layers = blurLevel + 1;
      for (int index = 0; index < layers; index++) {
        final layerWidth =
            previewDecorationWidth -
            index * previewDecorationWidth / layers;
        final glowPaint = _colorPaint(
          decorationColor,
          bounds,
          opacity: 0.72,
        )
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = (baseOutlineWidth + layerWidth) * 2
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
      ..strokeWidth = baseOutlineWidth * 2;
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
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  Paint _colorPaint(
    AssColorValue value,
    Rect bounds, {
    double opacity = 1,
  }) {
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
          fontWeight: FontWeight.bold,
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
    _hexController = TextEditingController(
      text: _colorToHex(_activeColor()),
    );
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
    return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
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
                segments: const [
                  ButtonSegment(
                    value: AssColorMode.solid,
                    label: Text('単色'),
                  ),
                  ButtonSegment(
                    value: AssColorMode.gradient,
                    label: Text('グラデーション'),
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
                        title: '上（0%）',
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
                        title: '下（100%）',
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
                    const Text(
                      '16 進カラーコード',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _hexController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.tag),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                      ),
                      onChanged: _onHexChanged,
                    ),
                    const SizedBox(height: 24),
                    if (widget.suggestedPresets.isNotEmpty) ...[
                      const Text(
                        'プリセット',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: widget.suggestedPresets
                            .map((preset) =>
                                _buildColorCircle(preset, activeColor == preset))
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
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('キャンセル'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _mode == AssColorMode.solid
                            ? AssColorValue.solid(_color0)
                            : AssColorValue.gradient(
                                color0: _color0, color100: _color100),
                      );
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                    ),
                    child: const Text('適用'),
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
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
