import '../utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ffmpeg_service.dart';
import '../services/font_service.dart';
import '../widgets/timeline_waveform.dart';
import '../widgets/lyrics_editor.dart';
import '../widgets/toolbar_area.dart';
import '../widgets/tagging_button.dart';
import '../services/media_player_service.dart';
import '../services/waveform_extractor.dart';
import '../services/waveform_extractor_router.dart';
import '../services/lyrics_state_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'ass_export_screen.dart';
import '../services/ass_exporter.dart';
import 'package:url_launcher/url_launcher.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isTextMode = false;
  late final MediaPlayerService _mediaPlayer;
  late final LyricsStateService _lyricsState;
  WaveformData? _waveformData;
  bool _isLoadingMedia = false;
  String? _mediaFilePath;

  int _selectedPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _mediaPlayer = MediaPlayerService();
    _lyricsState = LyricsStateService();
  }

  @override
  void dispose() {
    _mediaPlayer.dispose();
    _lyricsState.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isTextMode = !_isTextMode;
    });
  }

  Future<void> _openMedia() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)
          ? FileType.any
          : FileType.custom,
      allowedExtensions:
          (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)
          ? null
          : kSupportedMediaExtensions,
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;

      setState(() {
        _mediaFilePath = path;
        _isLoadingMedia = true;
      });

      // Load into media player
      await _mediaPlayer.openMedia(path);

      // Extract waveform data
      WaveformData? waveData;
      try {
        waveData = await WaveformExtractorRouter.extractWaveform(path);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('波形解析エラー: $e'),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }

      setState(() {
        _waveformData = waveData;
        _isLoadingMedia = false;
      });
    }
  }

  Future<void> _openLrc() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)
          ? FileType.any
          : FileType.custom,
      allowedExtensions:
          (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)
          ? null
          : ['lrc', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final text = await File(path).readAsString();
      _lyricsState.loadLrcText(text);
    }
  }

  Future<Map<String, String>?> _showMobileExportDialog(String defaultFilename, String extension) async {
    final TextEditingController filenameController = TextEditingController(text: defaultFilename);
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('ファイルを出力 ($extension)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: filenameController,
                decoration: const InputDecoration(
                  labelText: 'ファイル名',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {'action': 'share', 'filename': filenameController.text}),
              child: const Text('共有'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {'action': 'export', 'filename': filenameController.text}),
              child: const Text('デバイスに出力'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportLrc() async {
    final lrcText = _lyricsState.rawText;
    if (lrcText.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('歌詞が空のため、出力できません。')));
      return;
    }

    // Extract filename from media path (or fallback to 'lyrics')
    String filename = 'lyrics';
    if (_mediaFilePath != null) {
      filename = _mediaFilePath!.split(RegExp(r'[/\\]')).last;
      // Remove extension
      final lastDotIdx = filename.lastIndexOf('.');
      if (lastDotIdx != -1) {
        filename = filename.substring(0, lastDotIdx);
      }
    }

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await _showMobileExportDialog(filename, '.txt');
        if (result == null) return;
        filename = result['filename'] ?? filename;
        final action = result['action'];

        if (action == 'share') {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$filename.txt');
          await tempFile.writeAsString(lrcText);

          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(tempFile.path)],
              subject: '歌詞を出力: $filename.txt',
            ),
          );
          // Delay clean up temp file after share to prevent race conditions on mobile
          Future.delayed(const Duration(minutes: 1), () {
            try { tempFile.deleteSync(); } catch (_) {}
          });
          return;
        }
      }

      Uint8List? fileBytes;
      if (Platform.isAndroid || Platform.isIOS) {
        fileBytes = Uint8List.fromList(utf8.encode(lrcText));
      }

      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: '歌詞ファイルの保存先を選択',
        fileName: '$filename.txt',
        bytes: fileBytes,
      );

      if (outputPath != null) {
        if (!Platform.isAndroid && !Platform.isIOS) {
          final file = File(outputPath);
          await file.writeAsString(lrcText);
        }

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('への出力が成功しました：$outputPath')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('出力に失敗しました：$e')));
      }
    }
  }

  Future<void> _onExport(AssExportSettings settings) async {
    String filename = 'karaoke';
    if (_mediaFilePath != null) {
      filename = _mediaFilePath!.split(RegExp(r'[/\\]')).last;
      final lastDotIdx = filename.lastIndexOf('.');
      if (lastDotIdx != -1) {
        filename = filename.substring(0, lastDotIdx);
      }
    }

          try {
            final assContent = await AssExporter.generateAss(_lyricsState.document!, settings);

      if (Platform.isAndroid || Platform.isIOS) {
        final result = await _showMobileExportDialog(filename, '.ass');
        if (result == null) return;
        filename = result['filename'] ?? filename;
        final action = result['action'];

        if (action == 'share') {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$filename.ass');
          await tempFile.writeAsString(assContent);

          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(tempFile.path)],
              subject: '字幕を出力: $filename.ass',
            ),
          );
          // Delay clean up temp file after share to prevent race conditions on mobile
          Future.delayed(const Duration(minutes: 1), () {
            try { tempFile.deleteSync(); } catch (_) {}
          });
          return;
        }
      }

      Uint8List? fileBytes;
      if (Platform.isAndroid || Platform.isIOS) {
        fileBytes = Uint8List.fromList(utf8.encode(assContent));
      }

      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: 'ASS 字幕の保存先を選択',
        fileName: '$filename.ass',
        bytes: fileBytes,
      );

      if (outputPath != null) {
        if (!Platform.isAndroid && !Platform.isIOS) {
          final file = File(outputPath);
          await file.writeAsString(assContent);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('高度なASSの出力が成功しました：$outputPath')));
        }
      }
    } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('出力に失敗しました: $e')));
            }
          }
          }

  Future<void> _onExportVideo(AssExportSettings settings) async {
          if (_mediaFilePath == null) return;
          
          String filename = 'karaoke';
          filename = _mediaFilePath!.split(RegExp(r'[/\\]')).last;
          final lastDotIdx = filename.lastIndexOf('.');
          if (lastDotIdx != -1) {
            filename = filename.substring(0, lastDotIdx);
          }
          filename += '_hardsub';

          String? outputPath;
          if (Platform.isAndroid || Platform.isIOS) {
            // Save to external storage so other apps can access the file
            final extDir = await getExternalStorageDirectory();
            if (extDir != null) {
              final exportDir = Directory('${extDir.path}/exports');
              if (!await exportDir.exists()) {
                await exportDir.create(recursive: true);
              }
              outputPath = '${exportDir.path}/$filename.mp4';
            } else {
              // Fallback to temp directory if external storage is unavailable
              final tempDir = await getTemporaryDirectory();
              outputPath = '${tempDir.path}/$filename.mp4';
            }
          } else {
            outputPath = await FilePicker.saveFile(
              dialogTitle: '動画の保存先を選択',
              fileName: '$filename.mp4',
              type: FileType.video,
            );
          }

          if (outputPath == null) return;

          ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
          ValueNotifier<String> codecNotifier = ValueNotifier('最適なエンコーダーを検出中...');
          bool isCancelled = false;
          final ffmpegService = FfmpegService();
          final fontService = FontService();

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('動画をエンコード中...'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('FFmpeg を使用してハードサブをエンコードしています。しばらくお待ちください。'),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: codecNotifier,
                    builder: (context, codec, child) {
                      return Text('エンコーダー: $codec', style: const TextStyle(fontSize: 12, color: Colors.grey));
                    },
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, value, child) {
                      return Column(
                        children: [
                          LinearProgressIndicator(value: value),
                          const SizedBox(height: 8),
                          Text('${(value * 100).toStringAsFixed(1)}%'),
                        ],
                      );
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    isCancelled = true;
                    ffmpegService.cancelExport();
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('キャンセル'),
                ),
              ],
            ),
          );

          File? tempAssFile;
          try {
            // Generate ASS
            final assContent = await AssExporter.generateAss(_lyricsState.document!, settings);
            final tempDir = await getTemporaryDirectory();
            tempAssFile = File('${tempDir.path}/temp_export.ass');
            await tempAssFile.writeAsString(assContent);

            // Sandbox Font
            String exportFontName = settings.fontName;
            if (settings.customFontPath != null) {
              try {
                 exportFontName = await fontService.processAndSandboxFont(settings.customFontPath!);
              } catch (e) {
                 debugPrint('Failed to process custom font: $e');
              }
            } else {
              try {
                 exportFontName = await fontService.extractBundledFont();
              } catch (e) {
                 debugPrint('Failed to extract bundled font: $e');
              }
            }
            final sandboxDir = await fontService.getSandboxFontsDir();

            await ffmpegService.exportVideo(
              videoPath: _mediaFilePath!,
              assPath: tempAssFile.path,
              fontName: exportFontName,
              fontSandboxDir: sandboxDir,
              outputPath: outputPath,
              useHwAccel: true,
              padVideo: false,
              onEncoderDetected: (codec) {
                if (!isCancelled) codecNotifier.value = codec;
              },
              onProgress: (p) {
                if (!isCancelled) progressNotifier.value = p;
              },
            );

            if (!isCancelled && mounted) {
              Navigator.of(context).pop(); // close dialog
              
              if (Platform.isAndroid || Platform.isIOS) {
                // Show location + offer share
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('保存しました：$outputPath'),
                    action: SnackBarAction(
                      label: '共有',
                      onPressed: () async {
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [XFile(outputPath!)],
                            subject: '動画を出力: $filename.mp4',
                          ),
                        );
                      },
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('動画の出力が成功しました：$outputPath')),
                );
              }
            }
          } catch (e) {
            if (mounted) {
              if (Navigator.canPop(context)) Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('エンコードに失敗しました'),
                  content: SingleChildScrollView(child: SelectableText(e.toString())),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
          } finally {
            // Clean up temporary ASS file
            try { await tempAssFile?.delete(); } catch (_) {}
          }
  }

  void _showFilesBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.audio_file),
                title: const Text('メディアを開く (Open Media)'),
                subtitle: const Text('編集する音声または動画ファイルをインポートします'),
                enabled: !_isLoadingMedia,
                onTap: () {
                  Navigator.pop(ctx);
                  if (!_isLoadingMedia) _openMedia();
                },
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('歌詞を開く (Open LRC)'),
                subtitle: const Text('外部の LRC 歌詞ファイルをインポートして編集します'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openLrc();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.note),
                title: const Text('LRC 歌詞を出力'),
                subtitle: const Text('現在のタイムラインを標準の LRC 形式で出力します'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportLrc();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text(
                'yuukilyrics',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '© 2026 asuharayuuki\nLicensed under the GNU General Public License v3.0',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () async {
                  final url = Uri.parse('https://space.bilibili.com/53133362');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.live_tv),
                label: const Text('bilibili'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final url = Uri.parse(
                    'https://github.com/asuharayuuki/yuukilyrics',
                  );
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.code),
                label: const Text('GitHub'),
              ),
              TextButton.icon(
                onPressed: () {
                  showLicensePage(context: context);
                },
                icon: const Icon(Icons.description),
                label: const Text('Licenses'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return NavigationDrawer(
      selectedIndex: _selectedPageIndex,
      onDestinationSelected: (int index) {
        if (index == 2) {
          Navigator.pop(context); // close drawer
          _showAboutDialog(context);
        } else {
          setState(() {
            _selectedPageIndex = index;
          });
          Navigator.pop(context); // close drawer
        }
      },
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(28, 24, 28, 16),
          child: Text(
            'yuukilyrics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.timer),
          label: Text('タイミング'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.movie_creation),
          label: Text('ASS 出力'),
        ),
        Divider(),
        NavigationDrawerDestination(
          icon: Icon(Icons.info_outline),
          label: Text('情報'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _selectedPageIndex,
      children: [
        _buildTimingScreen(context),
        AssExportScreen(
          drawer: _buildDrawer(context),
          mediaFilePath: _mediaFilePath,
          document: _lyricsState.document,
          onExport: _onExport,
          onExportVideo: _onExportVideo,
        ),
      ],
    );
  }

  Widget _buildTimingScreen(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: const Text(
          'yuukilyrics',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: [
          if (_isLoadingMedia)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Files',
            icon: const Icon(Icons.file_open),
            onPressed: _showFilesBottomSheet,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Toggle Edit Mode',
            icon: Icon(_isTextMode ? Icons.code : Icons.edit_note),
            onPressed: _toggleMode,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Timeline & Waveform
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(51),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: TimelineWaveform(
                mediaPlayer: _mediaPlayer,
                waveformData: _waveformData,
                lyricsState: _lyricsState,
              ),
            ),
          ),

          // Lyrics Editor
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              child: LyricsEditor(
                isTextMode: _isTextMode,
                lyricsState: _lyricsState,
                mediaPlayer: _mediaPlayer,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 12.0,
            ),
            child: ToolbarArea(
              mediaPlayer: _mediaPlayer,
              lyricsState: _lyricsState,
            ),
          ),

          // Main Tagging Button
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 16.0),
            child: TaggingButton(
              lyricsState: _lyricsState,
              mediaPlayer: _mediaPlayer,
            ),
          ),
        ],
      ),
    );
  }
}
