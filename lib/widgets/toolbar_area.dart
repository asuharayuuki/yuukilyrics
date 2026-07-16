import 'package:flutter/material.dart';
import '../services/media_player_service.dart';
import '../services/lyrics_state_service.dart';
import '../models/lyric_ast.dart';

class ToolbarArea extends StatefulWidget {
  final MediaPlayerService mediaPlayer;
  final LyricsStateService lyricsState;

  const ToolbarArea({
    super.key,
    required this.mediaPlayer,
    required this.lyricsState,
  });

  @override
  State<ToolbarArea> createState() => _ToolbarAreaState();
}

class _ToolbarAreaState extends State<ToolbarArea> {
  // Inline ruby editor state
  final TextEditingController _rubyCtrl = TextEditingController();
  bool _showRubyEditor = false;

  @override
  void initState() {
    super.initState();
    widget.lyricsState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.lyricsState.removeListener(_onStateChanged);
    _rubyCtrl.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    final node = widget.lyricsState.getSelectedNode();
    bool nextShowRubyEditor = false;
    String nextRubyText = '';

    if (node != null) {
      nextShowRubyEditor = true;
      if (node is LyricRuby) {
        nextRubyText = node.rubyNodes
            .whereType<LyricText>()
            .where((n) => n.text != '＋')
            .map((n) => n.text)
            .join();
      }
    }

    bool changed = false;
    if (_showRubyEditor != nextShowRubyEditor) {
      _showRubyEditor = nextShowRubyEditor;
      changed = true;
    }
    
    if (_rubyCtrl.text != nextRubyText) {
      _rubyCtrl.text = nextRubyText;
      changed = true;
    }

    if (changed) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main toolbar row
            SizedBox(
              height: 56,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Play / Pause
                    _buildToolBtn(
                      tooltip: 'Play / Pause',
                      icon: ListenableBuilder(
                        listenable: widget.mediaPlayer,
                        builder: (_, child) => Icon(
                          widget.mediaPlayer.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                      onPressed: widget.mediaPlayer.togglePlayPause,
                    ),

                    const _Divider(),

                    // Start tagging / Stop
                    ListenableBuilder(
                      listenable: widget.lyricsState,
                      builder: (_, child) {
                        final isTagging =
                            widget.lyricsState.activeCursor != null;
                        return _buildToolBtn(
                          tooltip: isTagging ? 'Stop Tagging' : 'Start Tagging',
                          icon: Icon(
                            isTagging
                                ? Icons.stop_circle_outlined
                                : Icons.radio_button_checked,
                          ),
                          onPressed: isTagging
                              ? widget.lyricsState.stopTagging
                              : widget.lyricsState.startTagging,
                          color: isTagging
                              ? Colors.redAccent
                              : colorScheme.primary,
                        );
                      },
                    ),

                    const _Divider(),

                    // Add Cursor
                    _buildToolBtn(
                      tooltip: 'カーソルを追加 (Add Cursor)',
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: widget.lyricsState.addCursorToSelected,
                    ),

                    // Remove Cursor
                    _buildToolBtn(
                      tooltip: 'カーソルを削除 (Remove Cursor)',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: widget.lyricsState.removeCursorFromSelected,
                    ),

                    // Merge with next
                    _buildToolBtn(
                      tooltip: '次の文字と結合 (Merge with Next)',
                      icon: const Icon(Icons.merge_type),
                      onPressed: widget.lyricsState.mergeSelectedWithNext,
                    ),

                    // Link Ruby (Merge Kana)
                    _buildToolBtn(
                      tooltip: 'ルビを結合 (Link Ruby)',
                      icon: const Icon(Icons.link),
                      onPressed: widget.lyricsState.linkRubySegments,
                    ),

                    // Split
                    _buildToolBtn(
                      tooltip: '分割 (Split Node)',
                      icon: const Icon(Icons.call_split),
                      onPressed: widget.lyricsState.splitSelectedNode,
                    ),

                    // Toggle 10 Tag
                    _buildToolBtn(
                      tooltip: '10タグを追加/削除',
                      icon: const Icon(Icons.stop),
                      onPressed: widget.lyricsState.toggleEndTag,
                    ),

                    const _Divider(),

                    // Auto Ruby & Tag (Combined)
                    _buildToolBtn(
                      tooltip: '自動ルビ＆タグ付け (Auto Ruby & Tag)',
                      icon: const Icon(Icons.auto_fix_high),
                      onPressed: () =>
                          widget.lyricsState.autoRubyAndTagDocument(context),
                    ),

                    const _Divider(),

                    // Seek backward 1500ms
                    _buildToolBtn(
                      tooltip: '1.5秒 戻る',
                      icon: const Icon(Icons.fast_rewind),
                      onPressed: () {
                        final pos = widget.mediaPlayer.position;
                        widget.mediaPlayer.seek(
                          Duration(
                            milliseconds: (pos.inMilliseconds - 1500).clamp(
                              0,
                              double.maxFinite.toInt(),
                            ),
                          ),
                        );
                      },
                    ),

                    // Seek forward 1000ms
                    _buildToolBtn(
                      tooltip: '1秒 進む',
                      icon: const Icon(Icons.fast_forward),
                      onPressed: () {
                        final pos = widget.mediaPlayer.position;
                        widget.mediaPlayer.seek(
                          pos + const Duration(milliseconds: 1000),
                        );
                      },
                    ),

                    const _Divider(),

                    // Tagging offset
                    ListenableBuilder(
                      listenable: widget.lyricsState,
                      builder: (_, child) {
                        final isOffsetModified =
                            widget.lyricsState.taggingOffsetMs != -230;
                        return _buildToolBtn(
                          tooltip: 'タグ付けオフセット設定 (Tagging Offset)',
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: _showOffsetDialog,
                          color: isOffsetModified ? colorScheme.primary : null,
                        );
                      },
                    ),

                    // Speed control
                    ListenableBuilder(
                      listenable: widget.mediaPlayer,
                      builder: (_, child) {
                        final isSpeedModified =
                            (widget.mediaPlayer.rate - 1.0).abs() > 0.01;
                        return _buildToolBtn(
                          tooltip: '再生速度 (Playback Speed)',
                          icon: const Icon(Icons.speed),
                          onPressed: _showSpeedDialog,
                          color: isSpeedModified ? colorScheme.primary : null,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Inline Ruby editor row (only visible when a Ruby node is selected)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _showRubyEditor
                  ? _buildRubyEditor(colorScheme)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolBtn({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: color ?? Colors.white70, size: 22),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRubyEditor(ColorScheme cs) {
    final node = widget.lyricsState.getSelectedNode();
    String label = '読み: ';
    if (node is LyricRuby) {
      label = '${node.baseText}: ';
    } else if (node is LyricText) {
      final sel = widget.lyricsState.selectionPath;
      if (sel != null &&
          sel.length > 2 &&
          sel[2] >= 0 &&
          sel[2] < node.text.length) {
        label = '${node.text[sel[2]]}: ';
      }
    }

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: TextField(
              controller: _rubyCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Enter reading (e.g. こう)',
              ),
              onSubmitted: (_) {
                widget.lyricsState.updateRubyText(_rubyCtrl.text);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        double rate = widget.mediaPlayer.rate;
        return AlertDialog(
          title: const Text('再生速度'),
          content: StatefulBuilder(
            builder: (ctx, ss) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '×${rate.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Slider(
                  value: rate,
                  min: 0.2,
                  max: 1.0,
                  divisions: 8,
                  label: '×${rate.toStringAsFixed(2)}',
                  onChanged: (v) => ss(() => rate = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                widget.mediaPlayer.setRate(rate);
                Navigator.pop(ctx);
              },
              child: const Text('確認'),
            ),
          ],
        );
      },
    );
  }

  void _showOffsetDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        int offset = widget.lyricsState.taggingOffsetMs;
        return AlertDialog(
          title: const Text('タグ付けのタイムオフセット'),
          content: StatefulBuilder(
            builder: (ctx, ss) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${offset}ms',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  offset < 0 ? '時間を早める ${-offset}ms' : '時間を遅らせる ${offset}ms',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withAlpha(150),
                  ),
                ),
                Slider(
                  value: offset.toDouble(),
                  min: -500,
                  max: 100,
                  divisions: 60,
                  label: '${offset}ms',
                  onChanged: (v) => ss(() => offset = v.round()),
                ),
                const Text(
                  '人間の反応遅延を補正\nオリジナル版のデフォルト: -230ms',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                widget.lyricsState.taggingOffsetMs = offset;
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('確認'),
            ),
          ],
        );
      },
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: Colors.white12,
      margin: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}
