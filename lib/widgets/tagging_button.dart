import 'package:flutter/material.dart';
import '../services/lyrics_state_service.dart';
import '../services/media_player_service.dart';

class TaggingButton extends StatefulWidget {
  final LyricsStateService lyricsState;
  final MediaPlayerService mediaPlayer;

  const TaggingButton({
    super.key,
    required this.lyricsState,
    required this.mediaPlayer,
  });

  @override
  State<TaggingButton> createState() => _TaggingButtonState();
}

class _TaggingButtonState extends State<TaggingButton> {
  Duration? _tapDownTime; // Cache the press-down moment's playback position

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return ListenableBuilder(
      listenable: widget.lyricsState,
      builder: (context, child) {
        final active = widget.lyricsState.activeCursor != null;
        return Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: active
                  ? [color, Color.lerp(color, Colors.black, 0.2)!]
                  : [Colors.grey.shade700, Colors.grey.shade800],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withAlpha(100),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTapDown: (_) {
                if (widget.lyricsState.activeCursor == null) return;
                // Immediate playback position capture and timestamp recording
                _tapDownTime = widget.mediaPlayer.position;
                widget.lyricsState.recordTimestamp(_tapDownTime!, advance: false);
              },
              onTapUp: (_) {
                if (_tapDownTime != null) {
                  // Release records End Tag (if applicable) and ALWAYS advances the cursor
                  widget.lyricsState.recordEndTag(
                    widget.mediaPlayer.position,
                    forceInsert: false,
                  );
                }
                _tapDownTime = null;
              },
              onTapCancel: () {
                if (_tapDownTime != null) {
                  widget.lyricsState.recordEndTag(
                    widget.mediaPlayer.position,
                    forceInsert: false,
                  );
                }
                _tapDownTime = null;
              },
              onTap: () {}, // Required to trigger material splash
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      active ? 'Ciallo～(∠・ω< )⌒☆' : 'Ciallo～(∠・ω< )⌒☆',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                        color: Colors.white,
                      ),
                    ),
                    if (active)
                      const Padding(
                        padding: EdgeInsets.only(top: 2.0),
                        child: Text(
                          'Ciallo～(∠・ω< )⌒☆',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
