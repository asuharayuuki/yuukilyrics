import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import '../services/waveform_extractor.dart';
import '../services/media_player_service.dart';

class TimelineWaveform extends StatefulWidget {
  final WaveformData? waveformData;
  final MediaPlayerService mediaPlayer;

  const TimelineWaveform({
    super.key,
    required this.waveformData,
    required this.mediaPlayer,
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
        final screenWidth = constraints.maxWidth;
        final centerOffset = screenWidth / 2;

        return GestureDetector(
          onScaleStart: (details) {
            _basePixelsPerSecond = _pixelsPerSecond;
            _isDragging = true;
            _dragPositionMillis = widget.mediaPlayer.position.inMilliseconds
                .toDouble();
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
            if (_wasPlayingBeforeDrag) {
              widget.mediaPlayer.play();
            }
          },
          child: AnimatedBuilder(
            animation: widget.mediaPlayer,
            builder: (context, child) {
              final currentPosition = _isDragging
                  ? Duration(milliseconds: _dragPositionMillis.toInt())
                  : widget.mediaPlayer.position;

              // Calculate horizontal offset
              final double positionPixels =
                  (currentPosition.inMilliseconds / 1000.0) * _pixelsPerSecond;

              return Container(
                color: Colors.transparent, // Capture gestures
                child: Stack(
                  children: [
                    // Waveform CustomPaint
                    Positioned.fill(
                      child: ClipRect(
                        child: CustomPaint(
                          painter: WaveformPainter(
                            waveformData: widget.waveformData!,
                            pixelsPerSecond: _pixelsPerSecond,
                            positionPixels: positionPixels,
                            centerOffset: centerOffset,
                            waveColor: Theme.of(
                              context,
                            ).colorScheme.primary.withAlpha(150),
                          ),
                        ),
                      ),
                    ),

                    // Center Playhead
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 2,
                        color: Theme.of(context).colorScheme.primary,
                        height: double.infinity,
                      ),
                    ),

                    // Time text
                    Positioned(
                      top: 8,
                      left: 16,
                      child: Text(
                        _formatDuration(currentPosition),
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
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
  final double positionPixels;
  final double centerOffset;
  final Color waveColor;

  WaveformPainter({
    required this.waveformData,
    required this.pixelsPerSecond,
    required this.positionPixels,
    required this.centerOffset,
    required this.waveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw samples
    final samples = waveformData.samples;
    final totalDurationSecs = waveformData.duration.inMilliseconds / 1000.0;

    // Each sample represents a chunk of time.
    final samplesPerSec = samples.length / totalDurationSecs;
    final pixelPerSample = pixelsPerSecond / samplesPerSec;

    final paint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = pixelPerSample
      ..strokeCap = StrokeCap.butt;

    // We want the current position to be at 'centerOffset'
    // So the starting x coordinate for sample 0 is:
    final startX = centerOffset - positionPixels;

    // Only draw visible samples
    final firstVisibleSample = ((-startX) / pixelPerSample).floor().clamp(
      0,
      samples.length,
    );
    final lastVisibleSample = ((size.width - startX) / pixelPerSample)
        .ceil()
        .clamp(0, samples.length);

    final int visibleCount = lastVisibleSample - firstVisibleSample;
    if (visibleCount <= 0) return;

    // Use highly optimized Float32List and drawRawPoints (Single GPU Draw Call)
    // Avoids incredibly expensive CPU Path tessellation on mid-range Androids.
    final points = Float32List(visibleCount * 4);
    int pIdx = 0;
    final double centerY = size.height / 2;

    for (int i = firstVisibleSample; i < lastVisibleSample; i++) {
      double x = startX + i * pixelPerSample + (pixelPerSample / 2);
      double amp = samples[i]; // 0.0 to 1.0
      double h = amp * centerY;

      points[pIdx++] = x;
      points[pIdx++] = centerY - h;
      points[pIdx++] = x;
      points[pIdx++] = centerY + h;
    }

    canvas.drawRawPoints(ui.PointMode.lines, points, paint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.positionPixels != positionPixels ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.centerOffset != centerOffset ||
        oldDelegate.waveformData != waveformData;
  }
}
