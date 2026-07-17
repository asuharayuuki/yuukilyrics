import 'package:flutter/material.dart';

import '../services/waveform_extractor.dart';
import '../services/media_player_service.dart';
import '../services/lyrics_state_service.dart';

class TimelineWaveform extends StatefulWidget {
  final WaveformData? waveformData;
  final MediaPlayerService mediaPlayer;
  final LyricsStateService lyricsState;

  const TimelineWaveform({
    super.key,
    required this.waveformData,
    required this.mediaPlayer,
    required this.lyricsState,
  });

  @override
  State<TimelineWaveform> createState() => _TimelineWaveformState();
}

class _TimelineWaveformState extends State<TimelineWaveform> {
  // Base scale: how many pixels per second
  double _pixelsPerSecond = 100.0;
  double _basePixelsPerSecond = 100.0;

  // Dragging state
  bool _isDragging = false;
  double _dragPositionMillis = 0;
  bool _wasPlayingBeforeDrag = false;
  bool _wasShiftMode = false;

  @override
  Widget build(BuildContext context) {
    if (widget.waveformData == null) {
      return Center(
        child: Text(
          'Ciallo～(∠・ω< )⌒☆',
          style: TextStyle(
            color: Colors.white.withAlpha(76),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: widget.lyricsState,
          builder: (context, _) {
            final isShiftMode = widget.lyricsState.isGlobalTimeShiftMode;
            final screenWidth = constraints.maxWidth;
            final centerOffset = screenWidth / 2;
            final waveColor = isShiftMode 
                ? Colors.orange.withAlpha(200) 
                : Theme.of(context).colorScheme.primary.withAlpha(150);
            final primaryColor = isShiftMode 
                ? Colors.orange 
                : Theme.of(context).colorScheme.primary;

            if (isShiftMode && !_wasShiftMode) {
              // Just entered shift mode
              _dragPositionMillis = widget.mediaPlayer.position.inMilliseconds.toDouble();
              // Start playback automatically
              widget.mediaPlayer.play();
            }
            _wasShiftMode = isShiftMode;

        return GestureDetector(
          onScaleStart: (details) {
            _basePixelsPerSecond = _pixelsPerSecond;
            _isDragging = true;
            if (!isShiftMode) {
              _dragPositionMillis = widget.mediaPlayer.position.inMilliseconds.toDouble();
            }
            _wasPlayingBeforeDrag = widget.mediaPlayer.isPlaying;
            if (_wasPlayingBeforeDrag) {
              widget.mediaPlayer.pause();
            }
          },
          onScaleUpdate: (details) {
            setState(() {
              // Handle zoom
              if (details.scale != 1.0) {
                _pixelsPerSecond = (_basePixelsPerSecond * details.scale).clamp(
                  10.0,
                  1000.0,
                );
              }

              // Handle pan (drag)
              if (details.focalPointDelta.dx != 0) {
                // Drag left (negative delta) means moving forward in time
                final deltaMillis =
                    -(details.focalPointDelta.dx / _pixelsPerSecond) * 1000;
                _dragPositionMillis += deltaMillis;
                _dragPositionMillis = _dragPositionMillis.clamp(
                  0.0,
                  widget.mediaPlayer.duration.inMilliseconds.toDouble(),
                );

                // Throttle seeking slightly or seek directly (media_kit handles frequent seeks ok when paused)
                widget.mediaPlayer.seek(
                  Duration(milliseconds: _dragPositionMillis.toInt()),
                );
              }
            });
          },
          onScaleEnd: (details) {
            setState(() {
              _isDragging = false;
            });
            widget.mediaPlayer.seek(
              Duration(milliseconds: _dragPositionMillis.toInt()),
            );
            if (isShiftMode) {
              widget.lyricsState.setGlobalTimeShiftTargetTime(
                  Duration(milliseconds: _dragPositionMillis.toInt()));
            }
            if (_wasPlayingBeforeDrag || isShiftMode) {
              widget.mediaPlayer.play();
            }
          },
          child: Container(
            color: Colors.transparent, // Capture gestures
            child: Stack(
              children: [
                // Waveform CustomPaint — repaints directly via Listenable,
                // bypassing widget rebuild entirely
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ClipRect(
                      child: CustomPaint(
                        painter: WaveformPainter(
                          waveformData: widget.waveformData!,
                          pixelsPerSecond: _pixelsPerSecond,
                          centerOffset: centerOffset,
                          waveColor: waveColor,
                          mediaPlayer: widget.mediaPlayer,
                          isDragging: _isDragging,
                          dragPositionMillis: _dragPositionMillis,
                          isShiftMode: isShiftMode,
                        ),
                      ),
                    ),
                  ),
                ),

                // Center Playhead
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 2,
                    color: primaryColor,
                    height: double.infinity,
                  ),
                ),

                // Time text — lightweight AnimatedBuilder, only rebuilds a Text widget
                Positioned(
                  top: 8,
                  left: 16,
                  child: AnimatedBuilder(
                    animation: widget.mediaPlayer,
                    builder: (context, child) {
                      final currentPosition = (_isDragging || isShiftMode)
                          ? Duration(milliseconds: _dragPositionMillis.toInt())
                          : widget.mediaPlayer.position;
                      return Text(
                        _formatDuration(currentPosition),
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      });
      },
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String threeDigits(int n) => n.toString().padLeft(3, "0");
    String mm = twoDigits(d.inMinutes.remainder(60));
    String ss = twoDigits(d.inSeconds.remainder(60));
    String xx = threeDigits(
      d.inMilliseconds.remainder(1000),
    ).substring(0, 2); // hundredths
    return "$mm:$ss:$xx";
  }
}

class WaveformPainter extends CustomPainter {
  final WaveformData waveformData;
  final double pixelsPerSecond;
  final double centerOffset;
  final Color waveColor;
  final MediaPlayerService mediaPlayer;
  final bool isDragging;
  final double dragPositionMillis;
  final bool isShiftMode;


  WaveformPainter({
    required this.waveformData,
    required this.pixelsPerSecond,
    required this.centerOffset,
    required this.waveColor,
    required this.mediaPlayer,
    required this.isDragging,
    required this.dragPositionMillis,
    required this.isShiftMode,
  }) : super(repaint: mediaPlayer); // Repaint directly when mediaPlayer notifies

  @override
  void paint(Canvas canvas, Size size) {
    // Read position directly — no widget rebuild needed
    final currentPosition = (isDragging || isShiftMode)
        ? Duration(milliseconds: dragPositionMillis.toInt())
        : mediaPlayer.position;
    final double positionPixels =
        (currentPosition.inMilliseconds / 1000.0) * pixelsPerSecond;

    // Draw samples
    final samples = waveformData.samples;
    final totalDurationSecs = waveformData.duration.inMilliseconds / 1000.0;

    // Each sample represents a chunk of time.
    final samplesPerSec = samples.length / totalDurationSecs;

    final paint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = false;

    // We want the current position to be at 'centerOffset'
    // startX is where time = 0 is located on screen
    final startX = centerOffset - positionPixels;
    final double centerY = size.height / 2;

    // Iterate pixel by pixel on the screen width
    for (double x = 0; x < size.width; x++) {
      // time relative to start of audio
      final double timeAtX = (x - startX) / pixelsPerSecond;
      if (timeAtX < 0 || timeAtX >= totalDurationSecs) continue;
      
      final int startSample = (timeAtX * samplesPerSec).floor().clamp(0, samples.length - 1);
      final int endSample = ((timeAtX + 1.0 / pixelsPerSecond) * samplesPerSec).ceil().clamp(startSample, samples.length);
      
      double maxAmp = 0;
      for (int i = startSample; i < endSample; i++) {
        if (samples[i] > maxAmp) maxAmp = samples[i];
      }
      
      if (maxAmp > 0) {
        double h = maxAmp * centerY;
        canvas.drawLine(Offset(x, centerY - h), Offset(x, centerY + h), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.centerOffset != centerOffset ||
        oldDelegate.waveformData != waveformData ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.dragPositionMillis != dragPositionMillis ||
        oldDelegate.waveColor != waveColor ||
        oldDelegate.isShiftMode != isShiftMode;
  }
}
