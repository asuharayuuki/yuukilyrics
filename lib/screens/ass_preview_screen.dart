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
  bool _isClosing = false;
  bool _allowPop = false;
  Future<void>? _playerDisposal;
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
        if (!mounted || _isClosing) return;
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

    unawaited(_initPlayer());
  }

  Future<void> _initPlayer() async {
    try {
      if (player.platform case final NativePlayer nativePlayer) {
        await nativePlayer.setProperty('hr-seek', 'yes');
        if (_isClosing) return;
        await nativePlayer.setProperty('hr-seek-framedrop', 'no');
        if (_isClosing) return;
        await nativePlayer.setProperty('hwdec', 'no');
        if (_isClosing) return;
        if (widget.fontSandboxDir != null) {
          await nativePlayer.setProperty(
            'sub-fonts-dir',
            widget.fontSandboxDir!,
          );
          if (_isClosing) return;
        }
      }

      await player.open(Media(widget.mediaPath), play: false);
      if (_isClosing) return;
      await player.setSubtitleTrack(
        SubtitleTrack.uri(Uri.file(widget.assFilePath).toString()),
      );
      if (_isClosing) return;
      await player.play();
    } catch (e) {
      if (mounted && !_isClosing) {
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
    _isClosing = true;
    unawaited(_disposePlayerOnce());
    super.dispose();
  }

  Future<void> _disposePlayerOnce() {
    return _playerDisposal ??= () async {
      await _logSubscription.cancel();
      try {
        await player.stop();
      } catch (_) {
        // Initialization may not have completed yet.
      }
      try {
        await player.dispose();
      } catch (_) {
        // Closing the route should still succeed if native teardown reports an
        // error after resources have already been released.
      }
    }();
  }

  Future<void> _closePreview() async {
    if (_isClosing) return;
    setState(() => _isClosing = true);
    await _disposePlayerOnce();
    if (!mounted) return;

    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
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
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closePreview());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AbsorbPointer(
          absorbing: _isClosing,
          child: Stack(
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
                    onPressed: _closePreview,
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
        ),
      ),
    );
  }
}
