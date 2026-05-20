import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
      type: FileType.custom,
      allowedExtensions: ['mp3', 'mp4', 'wav', 'flac', 'mkv', 'avi', 'aac'],
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
      final waveData = await WaveformExtractorRouter.extractWaveform(path);

      setState(() {
        _waveformData = waveData;
        _isLoadingMedia = false;
      });
    }
  }

  Future<void> _openLrc() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final text = await File(path).readAsString();
      _lyricsState.loadLrcText(text);
    }
  }

  Future<void> _exportLrc() async {
    final lrcText = _lyricsState.rawText;
    if (lrcText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('歌词内容为空，无法导出。')),
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
        // Mobile: Write to a temp file and call system sharing
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$filename.txt');
        await tempFile.writeAsString(lrcText);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tempFile.path)],
            subject: '导出歌词: $filename.txt',
          ),
        );
      } else {
        // PC / Desktop: Save As Dialog
        final String? outputPath = await FilePicker.saveFile(
          dialogTitle: '选择保存歌词文件的路径',
          fileName: '$filename.txt',
        );

        if (outputPath != null) {
          final file = File(outputPath);
          await file.writeAsString(lrcText);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已成功导出至：$outputPath')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('yuukilyrics', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          if (_isLoadingMedia)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: 16, height: 16, 
                child: CircularProgressIndicator(strokeWidth: 2)
              ),
            )
          else
            IconButton(
              tooltip: 'Open Media',
              onPressed: _openMedia,
              icon: const Icon(Icons.music_note),
            ),
          IconButton(
            tooltip: 'Open LRC',
            onPressed: _openLrc,
            icon: const Icon(Icons.description),
          ),
          IconButton(
            tooltip: 'Export LRC',
            onPressed: _exportLrc,
            icon: Icon(Platform.isAndroid || Platform.isIOS ? Icons.share : Icons.save_alt),
          ),
          const SizedBox(width: 16),
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
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
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
