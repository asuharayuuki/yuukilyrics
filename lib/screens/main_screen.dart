import '../utils/constants.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/atomic_file_writer.dart';
import '../services/ffmpeg_service.dart';
import '../services/font_service.dart';
import '../services/text_file_decoder.dart';
import '../widgets/timeline_waveform.dart';
import '../widgets/lyrics_editor.dart';
import '../widgets/toolbar_area.dart';
import '../widgets/tagging_button.dart';
import '../widgets/exported_video_dialog.dart';
import '../widgets/update_check_dialog.dart';
import '../services/media_player_service.dart';
import '../services/waveform_extractor.dart';
import '../services/waveform_extractor_router.dart';
import '../services/lyrics_state_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'ass_export_screen.dart';
import 'font_library_screen.dart';
import 'singer_avatar_library_screen.dart';
import '../services/ass_exporter.dart';
import '../services/font_library_service.dart';
import '../services/singer_avatar_library_service.dart';
import '../services/color_preset_library_service.dart';
import '../services/escape_pod_service.dart';
import '../services/update_check_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isTextMode = false;
  late final MediaPlayerService _mediaPlayer;
  late final LyricsStateService _lyricsState;
  late final SingerAvatarLibraryService _avatarLibrary;
  late final FontLibraryService _fontLibrary;
  late final ColorPresetLibraryService _colorPresetLibrary;
  final AssExportPageState _assExportPageState = AssExportPageState();
  final TimelineWaveformPageState _timelinePageState =
      TimelineWaveformPageState();
  final LyricsEditorPageState _lyricsEditorPageState = LyricsEditorPageState();
  final ToolbarAreaPageState _toolbarPageState = ToolbarAreaPageState();
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  WaveformData? _waveformData;
  bool _isLoadingMedia = false;
  bool _isDraggingFiles = false;
  String? _mediaFilePath;
  Uint8List? _mediaSecurityScopedBookmark;
  int _mediaLoadGeneration = 0;

  int _selectedPageIndex = 0;
  Future<AppRelease?>? _pendingUpdateCheck;
  bool _updateDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _mediaPlayer = MediaPlayerService();
    _lyricsState = LyricsStateService();
    _avatarLibrary = SingerAvatarLibraryService();
    _fontLibrary = FontLibraryService();
    _colorPresetLibrary = ColorPresetLibraryService();
    _avatarLibrary.refresh();
    _fontLibrary.refresh();
    _colorPresetLibrary.load();
    _loadTypographySettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkForUpdatesOnStartup());
    });
  }

  Future<void> _loadTypographySettings() async {
    final changed = await _assExportPageState.loadTypographySettings();
    if (changed && mounted) setState(() {});
  }

  @override
  void dispose() {
    final bookmark = _mediaSecurityScopedBookmark;
    if (bookmark != null) {
      unawaited(
        DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        ),
      );
    }
    _mediaPlayer.dispose();
    _lyricsState.dispose();
    _avatarLibrary.dispose();
    _fontLibrary.dispose();
    _colorPresetLibrary.dispose();
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

    if (result == null || result.files.single.path == null || !mounted) return;
    await _loadMediaPath(result.files.single.path!);
  }

  Future<void> _loadMediaPath(
    String path, {
    Uint8List? securityScopedBookmark,
  }) async {
    var scopedAccessStarted = false;
    final generation = ++_mediaLoadGeneration;
    setState(() => _isLoadingMedia = true);

    try {
      if (Platform.isMacOS && securityScopedBookmark != null) {
        scopedAccessStarted = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(
              bookmark: securityScopedBookmark,
            );
      }
      if (!mounted || generation != _mediaLoadGeneration) return;

      await _mediaPlayer.openMedia(path);
      if (!mounted || generation != _mediaLoadGeneration) return;

      final previousBookmark = _mediaSecurityScopedBookmark;

      setState(() {
        _mediaFilePath = path;
        _waveformData = null;
        _mediaSecurityScopedBookmark = scopedAccessStarted
            ? securityScopedBookmark
            : null;
      });

      if (previousBookmark != null) {
        unawaited(
          DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: previousBookmark,
          ),
        );
      }
      scopedAccessStarted = false;

      WaveformData? waveData;
      try {
        waveData = await WaveformExtractorRouter.extractWaveform(path);
      } catch (error) {
        if (mounted && generation == _mediaLoadGeneration) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.waveformAnalysisFailed(error)),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }

      if (!mounted || generation != _mediaLoadGeneration) return;
      setState(() => _waveformData = waveData);
    } catch (error) {
      if (mounted && generation == _mediaLoadGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.mediaOpenFailed(error)),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (scopedAccessStarted && securityScopedBookmark != null) {
        unawaited(
          DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: securityScopedBookmark,
          ),
        );
      }
      if (mounted && generation == _mediaLoadGeneration) {
        setState(() => _isLoadingMedia = false);
      }
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
          : kSupportedLyricsExtensions,
    );

    if (result != null && result.files.single.path != null) {
      await _loadLyricsPath(result.files.single.path!);
    }
  }

  Future<void> _loadLyricsPath(
    String path, {
    Uint8List? securityScopedBookmark,
  }) async {
    var scopedAccessStarted = false;
    try {
      if (Platform.isMacOS && securityScopedBookmark != null) {
        scopedAccessStarted = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(
              bookmark: securityScopedBookmark,
            );
      }
      final text = TextFileDecoder.decode(await File(path).readAsBytes()).text;
      if (!mounted) return;
      _lyricsState.loadLrcText(text);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.lyricsOpenFailed(error)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (scopedAccessStarted && securityScopedBookmark != null) {
        unawaited(
          DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: securityScopedBookmark,
          ),
        );
      }
    }
  }

  Future<void> _handleDroppedFiles(DropDoneDetails details) async {
    if (_isDraggingFiles && mounted) {
      setState(() => _isDraggingFiles = false);
    }

    DropItem? mediaFile;
    DropItem? lyricsFile;
    for (final item in details.files) {
      if (item is DropItemDirectory) continue;
      final extension = p
          .extension(item.path)
          .toLowerCase()
          .replaceFirst('.', '');
      if (mediaFile == null && kSupportedMediaExtensions.contains(extension)) {
        mediaFile = item;
      } else if (lyricsFile == null &&
          kSupportedLyricsExtensions.contains(extension)) {
        lyricsFile = item;
      }
    }

    if (mediaFile == null && lyricsFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.unsupportedDroppedFiles)),
        );
      }
      return;
    }

    if (lyricsFile != null) {
      await _loadLyricsPath(
        lyricsFile.path,
        securityScopedBookmark: lyricsFile.extraAppleBookmark,
      );
    }
    if (mediaFile != null && mounted) {
      await _loadMediaPath(
        mediaFile.path,
        securityScopedBookmark: mediaFile.extraAppleBookmark,
      );
    }
  }

  Future<Map<String, String>?> _showMobileExportDialog(
    String defaultFilename,
    String extension,
  ) async {
    final TextEditingController filenameController = TextEditingController(
      text: defaultFilename,
    );
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.exportFile),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: filenameController,
                decoration: InputDecoration(labelText: context.l10n.fileName),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {
                'action': 'share',
                'filename': filenameController.text,
              }),
              child: Text(context.l10n.share),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {
                'action': 'export',
                'filename': filenameController.text,
              }),
              child: Text(context.l10n.saveToDevice),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportLrc() async {
    final l10n = context.l10n;
    final lrcText = _lyricsState.rawText;
    if (lrcText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.emptyLyricsCannotExport)),
      );
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
              subject: l10n.timedLyricsShareSubject('$filename.txt'),
            ),
          );
          // Delay clean up temp file after share to prevent race conditions on mobile
          Future.delayed(const Duration(minutes: 1), () {
            try {
              tempFile.deleteSync();
            } catch (_) {}
          });
          return;
        }
      }

      Uint8List? fileBytes;
      if (Platform.isAndroid || Platform.isIOS) {
        fileBytes = Uint8List.fromList(utf8.encode(lrcText));
      }

      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: l10n.chooseLyricsSaveLocation,
        fileName: '$filename.txt',
        bytes: fileBytes,
      );

      if (outputPath != null) {
        if (!Platform.isAndroid && !Platform.isIOS) {
          await AtomicFileWriter.writeString(
            File(outputPath),
            lrcText,
            allowDirectFallback: true,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.lyricsFileSaved(outputPath))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.lyricsExportFailed(e))),
        );
      }
    }
  }

  Future<void> _onExport(AssExportSettings settings) async {
    final l10n = context.l10n;
    String filename = 'karaoke';
    if (_mediaFilePath != null) {
      filename = _mediaFilePath!.split(RegExp(r'[/\\]')).last;
      final lastDotIdx = filename.lastIndexOf('.');
      if (lastDotIdx != -1) {
        filename = filename.substring(0, lastDotIdx);
      }
    }

    try {
      final assContent = await AssExporter.generateAss(
        _lyricsState.document!,
        settings,
      );

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
              subject: l10n.assShareSubject('$filename.ass'),
            ),
          );
          // Delay clean up temp file after share to prevent race conditions on mobile
          Future.delayed(const Duration(minutes: 1), () {
            try {
              tempFile.deleteSync();
            } catch (_) {}
          });
          return;
        }
      }

      Uint8List? fileBytes;
      if (Platform.isAndroid || Platform.isIOS) {
        fileBytes = Uint8List.fromList(utf8.encode(assContent));
      }

      final String? outputPath = await FilePicker.saveFile(
        dialogTitle: l10n.chooseAssSaveLocation,
        fileName: '$filename.ass',
        bytes: fileBytes,
      );

      if (outputPath != null) {
        if (!Platform.isAndroid && !Platform.isIOS) {
          await AtomicFileWriter.writeString(
            File(outputPath),
            assContent,
            allowDirectFallback: true,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.assSaved(outputPath))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.assExportFailed(e))),
        );
      }
    }
  }

  Future<void> _onExportVideo(AssExportSettings settings) async {
    if (_mediaFilePath == null) return;
    final l10n = context.l10n;

    String filename = 'karaoke';
    filename = _mediaFilePath!.split(RegExp(r'[/\\]')).last;
    final lastDotIdx = filename.lastIndexOf('.');
    if (lastDotIdx != -1) {
      filename = filename.substring(0, lastDotIdx);
    }
    filename += '_hardsub';

    String? outputPath;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Encode inside the app sandbox first. Android then copies the result
        // into the shared gallery; both platforms offer sharing afterwards.
        final tempDir = await getTemporaryDirectory();
        outputPath = '${tempDir.path}/$filename.mp4';
      } else {
        outputPath = await FilePicker.saveFile(
          dialogTitle: l10n.chooseVideoSaveLocation,
          fileName: '$filename.mp4',
          type: FileType.video,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.outputPreparationFailed(e))),
        );
      }
      return;
    }

    if (outputPath == null || !mounted) return;
    // Only remove a partial output on cancel/failure if this export created
    // it; never delete a file the user already had at that path.
    final outputFile = File(outputPath);
    final outputExistedBefore = await outputFile.exists();
    if (!mounted) return;

    ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    ValueNotifier<String> codecNotifier = ValueNotifier(l10n.detectingEncoder);
    bool isCancelled = false;
    final ffmpegService = FfmpegService();
    final fontService = FontService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.encodingVideo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.burningSubtitles),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: codecNotifier,
              builder: (context, codec, child) {
                return Text(
                  l10n.encoderName(codec),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                );
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
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );

    File? tempAssFile;
    try {
      // Generate ASS
      final assContent = await AssExporter.generateAss(
        _lyricsState.document!,
        settings,
      );
      final tempDir = await getTemporaryDirectory();
      tempAssFile = File('${tempDir.path}/temp_export.ass');
      await tempAssFile.writeAsString(assContent);

      // Sandbox Font
      try {
        await fontService.prepareFontForRendering(
          fontFilePath: settings.customFontPath,
          faceIndex: settings.fontFaceIndex,
          latinFont: settings.latinFont,
        );
      } catch (e) {
        debugPrint('Failed to prepare selected font: $e');
        rethrow;
      }
      final sandboxDir = await fontService.getSandboxFontsDir();

      // The user may have cancelled while the ASS file and fonts were being
      // prepared, before FFmpeg had anything to stop.
      if (isCancelled) throw CancelledException();

      await ffmpegService.exportVideo(
        videoPath: _mediaFilePath!,
        assPath: tempAssFile.path,
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
          await showExportedVideoDialog(
            context,
            videoPath: outputPath,
            shareFileName: '$filename.mp4',
            saveToGallery: Platform.isAndroid,
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.videoSaved(outputPath))));
        }
      }
    } catch (e) {
      if (!outputExistedBefore) {
        try {
          if (await outputFile.exists()) await outputFile.delete();
        } catch (_) {}
      }
      // The cancel button already closed the progress dialog, and a
      // user-requested stop is not an encoding failure.
      if (isCancelled || e is CancelledException) return;
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.encodingFailed),
            content: SingleChildScrollView(child: SelectableText(e.toString())),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.close),
              ),
            ],
          ),
        );
      }
    } finally {
      // Clean up temporary ASS file
      try {
        await tempAssFile?.delete();
      } catch (_) {}
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
                title: Text(ctx.l10n.openMediaFile),
                subtitle: Text(ctx.l10n.openMediaFileDescription),
                enabled: !_isLoadingMedia,
                onTap: () {
                  Navigator.pop(ctx);
                  if (!_isLoadingMedia) _openMedia();
                },
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: Text(ctx.l10n.openLyricsFile),
                subtitle: Text(ctx.l10n.openLyricsFileDescription),
                onTap: () {
                  Navigator.pop(ctx);
                  _openLrc();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.note),
                title: Text(ctx.l10n.exportTimedLyrics),
                subtitle: Text(ctx.l10n.exportTimedLyricsDescription),
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

  Future<AppRelease?> _checkForUpdates(String version) {
    return _pendingUpdateCheck ??= UpdateCheckService.check(version)
        .whenComplete(() {
          _pendingUpdateCheck = null;
        });
  }

  Future<void> _checkForUpdatesOnStartup() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final check = _checkForUpdates(packageInfo.version);
      final release = await check;
      if (mounted && release?.isUpdate == true) {
        await _showUpdateCheckDialog(packageInfo.version, () => check);
      }
    } catch (_) {
      // Startup checks should not interrupt editing on network errors.
    }
  }

  Future<void> _showUpdateCheckDialog(
    String version,
    Future<AppRelease?> Function() check,
  ) async {
    if (_updateDialogOpen) return;
    _updateDialogOpen = true;
    try {
      late final releaseCheck = check();
      await showDialog<void>(
        context: context,
        builder: (_) => UpdateCheckDialog(
          installedVersion: version,
          releaseCheck: releaseCheck,
        ),
      );
    } finally {
      _updateDialogOpen = false;
    }
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text(
                'yuukilyrics',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.versionAndBuild(
                  packageInfo.version,
                  packageInfo.buildNumber,
                ),
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '© 2026 asuharayuuki\nLicensed under the GNU General Public License v3.0',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => _showUpdateCheckDialog(
                  packageInfo.version,
                  () => _checkForUpdates(packageInfo.version),
                ),
                icon: const Icon(Icons.system_update_alt),
                label: Text(context.l10n.checkForUpdates),
              ),
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
                label: Text(context.l10n.license),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showEscapePodDialog();
                },
                icon: const Icon(Icons.rocket_launch_outlined),
                label: Text(context.l10n.escapePod),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.close),
            ),
          ],
        );
      },
    );
  }

  EscapePodService get _escapePodService => EscapePodService(
    fontLibrary: _fontLibrary,
    avatarLibrary: _avatarLibrary,
    colorPresetLibrary: _colorPresetLibrary,
  );

  void _showEscapePodDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.rocket_launch_outlined),
            const SizedBox(width: 12),
            Text(dialogContext.l10n.escapePod),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dialogContext.l10n.escapePodDescription),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(dialogContext.l10n.exportEscapePod),
                subtitle: Text(dialogContext.l10n.exportEscapePodDescription),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _exportEscapePod();
                },
              ),
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: Text(dialogContext.l10n.importEscapePod),
                subtitle: Text(dialogContext.l10n.importEscapePodDescription),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _importEscapePod();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _exportEscapePod() async {
    final l10n = context.l10n;
    _showEscapePodProgress(l10n.preparingEscapePod);
    EscapePodExportResult result;
    try {
      result = await _escapePodService.exportArchive();
    } catch (error) {
      _closeEscapePodProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.escapePodExportFailed(error))),
      );
      return;
    }
    _closeEscapePodProgress();
    if (!mounted) return;

    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    try {
      final outputPath = await FilePicker.saveFile(
        dialogTitle: l10n.chooseEscapePodSaveLocation,
        fileName: 'yuukilyrics_escape_pod_$date.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: Platform.isAndroid || Platform.isIOS ? result.bytes : null,
      );
      if (outputPath == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await AtomicFileWriter.writeBytes(
          File(outputPath),
          result.bytes,
          allowDirectFallback: true,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.escapePodExported(
              result.fontCount,
              result.avatarCount,
              result.colorPresetCount,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.escapePodExportFailed(error))),
      );
    }
  }

  Future<void> _importEscapePod() async {
    final l10n = context.l10n;
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: l10n.chooseEscapePodFile,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: Platform.isAndroid || Platform.isIOS,
      );
      if (picked == null || picked.files.isEmpty) return;
      final pickedFile = picked.files.single;
      final bytes =
          pickedFile.bytes ??
          (pickedFile.path == null
              ? null
              : await File(pickedFile.path!).readAsBytes());
      if (bytes == null) {
        throw const FileSystemException('Unable to read the selected ZIP.');
      }

      if (!mounted) return;
      _showEscapePodProgress(l10n.importingEscapePod);
      EscapePodImportResult result;
      try {
        result = await _escapePodService.importArchive(bytes);
      } finally {
        _closeEscapePodProgress();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.escapePodImported(
              result.fontCount,
              result.avatarCount,
              result.colorPresetCount,
              result.skippedEntries.length,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.escapePodImportFailed(error))),
      );
    }
  }

  void _showEscapePodProgress(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  void _closeEscapePodProgress() {
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  Widget _buildDrawer(BuildContext context) {
    return NavigationDrawer(
      selectedIndex: _selectedPageIndex,
      onDestinationSelected: (int index) async {
        if (index == 3) {
          Navigator.pop(context); // close drawer
          _showAboutDialog(context);
        } else {
          if (_selectedPageIndex == 0 && index != 0 && _mediaPlayer.isPlaying) {
            await _mediaPlayer.pause();
            if (!mounted || !context.mounted) return;
          }
          setState(() {
            _selectedPageIndex = index;
          });
          Navigator.pop(context); // close drawer
        }
      },
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 24, 28, 16),
          child: Text(
            'yuukilyrics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.timer),
          label: Text(context.l10n.timingEditor),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.movie_creation),
          label: Text(context.l10n.assExport),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(context.l10n.assetLibrary),
        ),
        const Divider(),
        NavigationDrawerDestination(
          icon: const Icon(Icons.info_outline),
          label: Text(context.l10n.aboutApp),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep inactive pages out of the Windows accessibility tree. Retaining
    // them in an IndexedStack can produce invalid AXTree reparent updates.
    final content = PageStorage(
      bucket: _pageStorageBucket,
      child: switch (_selectedPageIndex) {
        0 => _buildTimingScreen(context),
        1 => AssExportScreen(
          drawer: _buildDrawer(context),
          mediaFilePath: _mediaFilePath,
          document: _lyricsState.document,
          avatarLibrary: _avatarLibrary,
          fontLibrary: _fontLibrary,
          colorPresetLibrary: _colorPresetLibrary,
          pageState: _assExportPageState,
          onManageFonts: _openFontLibrary,
          onExport: _onExport,
          onExportVideo: _onExportVideo,
        ),
        2 => SingerAvatarLibraryScreen(
          drawer: _buildDrawer(context),
          library: _avatarLibrary,
        ),
        _ => _buildTimingScreen(context),
      },
    );

    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return content;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return DropTarget(
      enable: ModalRoute.of(context)?.isCurrent ?? true,
      onDragEntered: (_) {
        if (!_isDraggingFiles) setState(() => _isDraggingFiles = true);
      },
      onDragExited: (_) {
        if (_isDraggingFiles) setState(() => _isDraggingFiles = false);
      },
      onDragDone: _handleDroppedFiles,
      child: Stack(
        children: [
          content,
          if (_isDraggingFiles)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: colorScheme.scrim.withValues(alpha: 0.58),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colorScheme.primary),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.file_download_outlined,
                            size: 48,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.dropMediaOrLyricsHere,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openFontLibrary() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => FontLibraryScreen(library: _fontLibrary),
      ),
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
            tooltip: context.l10n.file,
            icon: const Icon(Icons.file_open),
            onPressed: _showFilesBottomSheet,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: context.l10n.toggleTextEditMode,
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
                pageState: _timelinePageState,
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
                colorPresetLibrary: _colorPresetLibrary,
                pageState: _lyricsEditorPageState,
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
              colorPresetLibrary: _colorPresetLibrary,
              pageState: _toolbarPageState,
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
