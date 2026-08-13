import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'dart:async';

import '../l10n/l10n.dart';

class AssPreviewScreen extends StatefulWidget {
  final String mediaPath;
  final String assFilePath;
  final String? fontSandboxDir;

  const AssPreviewScreen({
    super.key,
    required this.mediaPath,
    required this.assFilePath,
    this.fontSandboxDir,
  });

  @override
  State<AssPreviewScreen> createState() => _AssPreviewScreenState();
}

class _AssPreviewScreenState extends State<AssPreviewScreen> {
  late final Player player;
  late final VideoController controller;
  late StreamSubscription<PlayerLog> _logSubscription;
  bool _isFastForwarding = false;
  final List<String> _assLogs = [];

  @override
  void initState() {
    super.initState();

    player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
        pitch: false,
        logLevel: MPVLogLevel.warn,
      ),
    );

    _logSubscription = player.stream.log.listen((event) {
      // Catch subtitle and libass related warnings/errors
      if (event.prefix.contains('ass') ||
          event.prefix.contains('sub') ||
          event.prefix.contains('font')) {
        if (!mounted) return;
        setState(() {
          _assLogs.add(
            '[${event.level.toUpperCase()}] [${event.prefix}] ${event.text}',
          );
        });
      }
    });
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: false,
      ),
    );

    if (player.platform is NativePlayer) {
      final np = player.platform as NativePlayer;
      np.setProperty('hr-seek', 'yes');
      np.setProperty('hr-seek-framedrop', 'no');
      np.setProperty('hwdec', 'no'); // Disable hardware decoding
      if (widget.fontSandboxDir != null) {
        np.setProperty('sub-fonts-dir', widget.fontSandboxDir!);
      }
    }

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await player.open(Media(widget.mediaPath), play: false);
      await player.setSubtitleTrack(
        SubtitleTrack.uri(Uri.file(widget.assFilePath).toString()),
      );
      player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.previewLoadFailed(e)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    player.dispose();
    super.dispose();
  }

  void _showLogsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.subtitleRenderWarnings),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _assLogs.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _assLogs[index],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.redAccent,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.close),
          ),
        ],
      ),
    );
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLeft = details.globalPosition.dx < screenWidth / 2;
    final seekAmount = const Duration(seconds: 5);
    final currentPos = player.state.position;

    if (isLeft) {
      player.seek(currentPos - seekAmount);
    } else {
      player.seek(currentPos + seekAmount);
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() => _isFastForwarding = true);
    player.setRate(2.0);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    setState(() => _isFastForwarding = false);
    player.setRate(1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTapDown: _onDoubleTapDown,
              onDoubleTap: () {}, // Required to capture double tap
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              child: Video(
                controller: controller,
                controls: MaterialVideoControls,
              ),
            ),
          ),
          if (_isFastForwarding)
            Positioned(
              top: 48,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.playingAtDoubleSpeed,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.fast_forward,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          if (_assLogs.isNotEmpty)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: FloatingActionButton.extended(
                  onPressed: _showLogsDialog,
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                  icon: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                  ),
                  label: Text(
                    context.l10n.warningErrorCount(_assLogs.length),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
