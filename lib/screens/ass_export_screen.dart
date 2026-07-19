import '../utils/constants.dart';
import 'package:flutter/material.dart';

import '../models/lyric_ast.dart';
import '../services/ass_exporter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'ass_preview_screen.dart';

import '../services/font_service.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ffmpeg_service.dart';
import 'dart:math';

enum AssPagingMode { auto2Lines, emptyLineDelimited }

class SingerColorInfo {
  String prefix;
  Color primaryColor;
  Color edgeColor;
  SingerColorInfo(this.prefix, this.primaryColor, this.edgeColor);
}

class AssExportSettings {
  final String fontName;
  final String? customFontPath;
  final List<SingerColorInfo> singerColors;
  final Color primaryColor;
  final int fontSize;
  final AssPagingMode pagingMode;
  final int interludeThresholdSeconds;
  final int horizontalMargin;
  final Color edgeColor;
  final int outlineWidth;
  final int blurLevel;
  final int resolutionHeight;

  AssExportSettings({
    required this.fontName,
    this.customFontPath,
    required this.singerColors,
    required this.primaryColor,
    required this.fontSize,
    required this.pagingMode,
    required this.interludeThresholdSeconds,
    required this.horizontalMargin,
    required this.edgeColor,
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
  String? _customFontPath;
  final List<SingerColorInfo> _singerColors = [];
  final List<TextEditingController> _singerControllers = [];
  Color _selectedColor = const Color(0xFF0000AF);
  Color _edgeColor = const Color(0xFF96BFFF); // default: 150, 191, 255
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

  @override
  void initState() {
    super.initState();
    _fontController = TextEditingController(text: 'Kosugi Maru');
    _resolutionController = TextEditingController(text: _resolutionHeight.toString());
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
      final res = await FfmpegService().getVideoResolution(widget.mediaFilePath!);
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
        title: const Text('ASS を出力'),
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
              'ハイライト色:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var color in _presetColors)
                  GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor == color
                              ? Colors.white
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: _selectedColor == color
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                if (!_presetColors.contains(_selectedColor))
                  GestureDetector(
                    onTap: () => _showCustomColorDialog(true),
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: _selectedColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _showCustomColorDialog(true),
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.transparent, width: 3),
                      ),
                      child: const Icon(
                        Icons.palette_outlined,
                        size: 24,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              '発光色 (未歌唱部分の縁取り色):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var color in _presetEdgeColors)
                  GestureDetector(
                    onTap: () => setState(() => _edgeColor = color),
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _edgeColor == color
                              ? Colors.white
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: _edgeColor == color
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                if (!_presetEdgeColors.contains(_edgeColor))
                  GestureDetector(
                    onTap: () => _showCustomColorDialog(false),
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _edgeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: _edgeColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _showCustomColorDialog(false),
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.transparent, width: 3),
                      ),
                      child: const Icon(
                        Icons.palette_outlined,
                        size: 24,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              '歌手ごとの色分け',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'プレフィックスの異なる歌手行に専用のハイライト色と発光色を設定します。一致する際は、より長いプレフィックスを優先します。プレフィックスが含まれていない、または一致しなかった行にはデフォルトのテーマ色が使用されます。',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _singerColors.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: 'プレフィックス (例: ●)',
                        ),
                        controller: _singerControllers[i],
                        onChanged: (val) {
                          _singerColors[i].prefix = val;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            Color? newColor = await _showColorPickerForSinger(
                              _singerColors[i].primaryColor,
                              true,
                            );
                            if (newColor != null) {
                              setState(() {
                                _singerColors[i].primaryColor = newColor;
                              });
                            }
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _singerColors[i].primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            Color? newColor = await _showColorPickerForSinger(
                              _singerColors[i].edgeColor,
                              false,
                            );
                            if (newColor != null) {
                              setState(() {
                                _singerColors[i].edgeColor = newColor;
                              });
                            }
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _singerColors[i].edgeColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          _singerColors.removeAt(i);
                          _singerControllers[i].dispose();
                          _singerControllers.removeAt(i);
                        });
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _singerColors.add(
                    SingerColorInfo(
                      '●',
                      const Color(0xFF0000AF),
                      const Color(0xFF96BFFF),
                    ),
                  );
                  _singerControllers.add(TextEditingController(text: '●'));
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('歌手の色を追加'),
            ),
            const SizedBox(height: 32),
            const Text(
              '字幕字体:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fontController,
              readOnly: _customFontPath != null,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: '字体名',
                filled: _customFontPath != null,
                fillColor: _customFontPath != null
                    ? Colors.grey.withValues(alpha: 0.2)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
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
                        ? 'ローカルフォントを選択'
                        : '選択済み: ${_customFontPath!.split(RegExp(r'[/\\]')).last}',
                  ),
                  onPressed: _pickCustomFont,
                ),
                if (_customFontPath != null)
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 16),
                    label: const Text('清除'),
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
              '基準フォントサイズ: ${_fontSize.toInt()}',
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
              '文字飾りのサイズ: ${_outlineWidth.toInt()} px',
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
              'ブラーの濃さ (Blur Level): $_blurLevel',
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
              '出力解像度 (Target Resolution):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownMenu<int>(
                    controller: _resolutionController,
                    label: const Text('高さ (Height) px'),
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
                      labelText: '幅 (Width) px',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                if (_baselineResolutionHeight != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '動画のデフォルト解像度に戻す',
                    child: IconButton(
                      icon: const Icon(Icons.restore),
                      onPressed: () {
                        _resolutionController.text = _baselineResolutionHeight!.toString();
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              '改ページ設定:',
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
                  child: Text('自動 2 行交差 (左上/右下)'),
                ),
                DropdownMenuItem(
                  value: AssPagingMode.emptyLineDelimited,
                  child: Text('空行を区切りとして段落ごとに配置'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _pagingMode = val);
              },
            ),
            const SizedBox(height: 32),
            Text(
              '間奏の表示閾値: ${_interludeThreshold.toInt()} 秒',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const Text(
              '前後のフレーズの間隔がこの時間を超える場合、間奏のカウントダウンを表示します',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Slider(
              value: _interludeThreshold,
              min: 5,
              max: 60,
              divisions: 55,
              label: '${_interludeThreshold.toInt()}s',
              onChanged: (val) => setState(() => _interludeThreshold = val),
            ),
            const SizedBox(height: 24),
            Text(
              '左右余白 (Horizontal Margin): $_horizontalMargin px',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const Text(
              '左右の歌詞を画面の中央に寄せるための余白を設定します (スマート水平配置)',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Slider(
              value: _horizontalMargin.toDouble(),
              min: 0,
              max: 300,
              divisions: 60,
              label: '$_horizontalMargin px',
              onChanged: (val) => setState(() => _horizontalMargin = val.toInt()),
            ),
            const SizedBox(height: 80), // Padding for scrolling
          ],
        ),
      ),
    );
  }

  AssExportSettings _getCurrentSettings() {
    return AssExportSettings(
      fontName: _fontController.text.trim().isEmpty
          ? 'Kosugi Maru'
          : _fontController.text.trim(),
      customFontPath: _customFontPath,
      singerColors: _singerColors,
      primaryColor: _selectedColor,
      fontSize: _fontSize.toInt(),
      pagingMode: _pagingMode,
      interludeThresholdSeconds: _interludeThreshold.toInt(),
      horizontalMargin: _horizontalMargin,
      edgeColor: _edgeColor,
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
                title: const Text('ASS 字幕ファイルのみ出力'),
                subtitle: const Text('プレーヤーや動画編集ソフト用の .ass ファイルを生成します'),
                onTap: () {
                  Navigator.pop(ctx);
                  _executeExport(widget.onExport);
                },
              ),
              ListTile(
                leading: const Icon(Icons.movie_creation),
                title: const Text('動画をエンコードして出力'),
                subtitle: Text(
                  isVideo
                      ? 'FFmpeg を使用して字幕を動画にハードサブとしてエンコードします'
                      : '動画をインポートした場合のみ使用可能',
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

  Future<void> _showCustomColorDialog(bool isPrimary) async {
    String hexInput = '#';
    Color previewColor = isPrimary ? _selectedColor : _edgeColor;

    final result = await showDialog<Color>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isPrimary ? 'カスタムハイライト色' : 'カスタム発光色'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      color: previewColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'HEX カラーコード',
                      hintText: '例: #FF0000 または FFAA00',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      hexInput = val.trim();
                      if (hexInput.startsWith('#')) {
                        hexInput = hexInput.substring(1);
                      }
                      if (hexInput.length == 6 || hexInput.length == 8) {
                        try {
                          final hex = hexInput.length == 6
                              ? 'FF$hexInput'
                              : hexInput;
                          final color = Color(int.parse(hex, radix: 16));
                          setDialogState(() {
                            previewColor = color;
                          });
                        } catch (_) {}
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(previewColor),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        if (isPrimary) {
          _selectedColor = result;
        } else {
          _edgeColor = result;
        }
      });
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
        setState(() {
          _customFontPath = result.files.single.path;
          _fontController.text = internalName;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('フォントの解析に失敗しました: $e')));
        }
      }
    }
  }

  Future<Color?> _showColorPickerForSinger(
    Color initialColor,
    bool isPrimary,
  ) async {
    String hexInput = '#';
    Color previewColor = initialColor;
    final presets = isPrimary ? _presetColors : _presetEdgeColors;

    return await showDialog<Color>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('カスタム色'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: previewColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: previewColor.withValues(alpha: 0.5),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var color in presets)
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              previewColor = color;
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'HEX カラー値',
                      hintText: '例: #FF0000',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      hexInput = val.trim();
                      if (hexInput.startsWith('#')) {
                        hexInput = hexInput.substring(1);
                      }
                      if (hexInput.length == 6 || hexInput.length == 8) {
                        try {
                          final hex = hexInput.length == 6
                              ? 'FF$hexInput'
                              : hexInput;
                          final color = Color(int.parse(hex, radix: 16));
                          setDialogState(() {
                            previewColor = color;
                          });
                        } catch (e) {
                          // ignore
                        }
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(previewColor);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
