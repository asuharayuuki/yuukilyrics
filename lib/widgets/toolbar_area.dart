import 'package:flutter/material.dart';
import '../services/media_player_service.dart';
import '../services/lyrics_state_service.dart';
import '../services/color_preset_library_service.dart';
import '../models/color_preset_asset.dart';
import '../models/lyric_ast.dart';
import '../l10n/l10n.dart';
import 'dual_color_preview.dart';

class ToolbarAreaPageState {
  bool _showColorPalette = false;
}

class ToolbarArea extends StatefulWidget {
  final MediaPlayerService mediaPlayer;
  final LyricsStateService lyricsState;
  final ColorPresetLibraryService colorPresetLibrary;
  final ToolbarAreaPageState pageState;

  const ToolbarArea({
    super.key,
    required this.mediaPlayer,
    required this.lyricsState,
    required this.colorPresetLibrary,
    required this.pageState,
  });

  @override
  State<ToolbarArea> createState() => _ToolbarAreaState();
}

class _ToolbarAreaState extends State<ToolbarArea> {
  // Inline ruby editor state
  final TextEditingController _rubyCtrl = TextEditingController();
  bool _showRubyEditor = false;
  List<ColorPresetAsset> _colorPresets = const [];

  bool get _showColorPalette => widget.pageState._showColorPalette;
  set _showColorPalette(bool value) =>
      widget.pageState._showColorPalette = value;

  @override
  void initState() {
    super.initState();
    widget.lyricsState.addListener(_onStateChanged);
    widget.colorPresetLibrary.addListener(_onColorPresetsChanged);
    _colorPresets = widget.colorPresetLibrary.activePresets;
    _onStateChanged();
  }

  @override
  void dispose() {
    widget.lyricsState.removeListener(_onStateChanged);
    widget.colorPresetLibrary.removeListener(_onColorPresetsChanged);
    _rubyCtrl.dispose();
    super.dispose();
  }

  void _onColorPresetsChanged() {
    if (!mounted) return;
    setState(() {
      _colorPresets = widget.colorPresetLibrary.activePresets;
    });
  }

  void _onRubyChanged(String value) {
    final composing = _rubyCtrl.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    widget.lyricsState.updateRubyText(value);
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
                key: const PageStorageKey<String>('timing-toolbar-scroll'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Play / Pause
                    _buildToolBtn(
                      tooltip: context.l10n.playPause,
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
                          tooltip: isTagging
                              ? context.l10n.stopTagging
                              : context.l10n.startTagging,
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
                      tooltip: context.l10n.addCheck,
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: widget.lyricsState.addCursorToSelected,
                    ),

                    // Remove Cursor
                    _buildToolBtn(
                      tooltip: context.l10n.removeCheck,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: widget.lyricsState.removeCursorFromSelected,
                    ),

                    // Merge with next
                    _buildToolBtn(
                      tooltip: context.l10n.mergeNextCharacter,
                      icon: const Icon(Icons.merge_type),
                      onPressed: widget.lyricsState.mergeSelectedWithNext,
                    ),

                    // Split
                    _buildToolBtn(
                      tooltip: context.l10n.splitCharacter,
                      icon: const Icon(Icons.call_split),
                      onPressed: widget.lyricsState.splitSelectedNode,
                    ),

                    // Toggle 10 Tag
                    _buildToolBtn(
                      tooltip: context.l10n.toggleKeyUpCheck,
                      icon: const Icon(Icons.stop),
                      onPressed: widget.lyricsState.toggleEndTag,
                    ),

                    const _Divider(),

                    // Auto Ruby & Tag (Combined)
                    _buildToolBtn(
                      tooltip: context.l10n.autoRubyAndChecks,
                      icon: const Icon(Icons.auto_fix_high),
                      onPressed: () =>
                          widget.lyricsState.autoRubyAndTagDocument(context),
                    ),

                    const _Divider(),

                    // Tagging offset
                    ListenableBuilder(
                      listenable: widget.lyricsState,
                      builder: (_, child) {
                        final isOffsetModified =
                            widget.lyricsState.taggingOffsetMs != -230;
                        return _buildToolBtn(
                          tooltip: context.l10n.taggingOffset,
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: _showOffsetDialog,
                          color: isOffsetModified ? colorScheme.primary : null,
                        );
                      },
                    ),

                    // Global time shift
                    ListenableBuilder(
                      listenable: widget.lyricsState,
                      builder: (_, child) {
                        final isShiftMode =
                            widget.lyricsState.isGlobalTimeShiftMode;
                        return _buildToolBtn(
                          tooltip: isShiftMode
                              ? context.l10n.confirmBulkAdjustment
                              : context.l10n.bulkAdjustTimeTags,
                          icon: Icon(
                            isShiftMode ? Icons.check : Icons.compare_arrows,
                          ),
                          color: isShiftMode ? Colors.orange : null,
                          onPressed: () {
                            if (!isShiftMode) {
                              // Entering mode: pause playback
                              widget.mediaPlayer.pause();
                            }
                            widget.lyricsState.toggleGlobalTimeShiftMode(
                              widget.mediaPlayer.position,
                            );
                          },
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
                          tooltip: context.l10n.playbackSpeed,
                          icon: const Icon(Icons.speed),
                          onPressed: _showSpeedDialog,
                          color: isSpeedModified ? colorScheme.primary : null,
                        );
                      },
                    ),

                    // Mobile haptic feedback
                    ListenableBuilder(
                      listenable: widget.lyricsState,
                      builder: (_, child) {
                        final isEnabled =
                            widget.lyricsState.hapticFeedbackEnabled;
                        return _buildToolBtn(
                          tooltip: isEnabled
                              ? context.l10n.disableHapticFeedback
                              : context.l10n.enableHapticFeedback,
                          icon: const Icon(Icons.vibration),
                          onPressed: widget.lyricsState.toggleHapticFeedback,
                          color: isEnabled ? colorScheme.primary : null,
                        );
                      },
                    ),

                    const _Divider(),

                    // Apply a saved color preset to the selected lyric line.
                    _buildToolBtn(
                      tooltip: _showColorPalette
                          ? context.l10n.closeLineColoring
                          : context.l10n.lineColoring,
                      icon: const Icon(Icons.palette_outlined),
                      onPressed: _toggleColorPalette,
                      color: _showColorPalette ? colorScheme.primary : null,
                    ),
                  ],
                ),
              ),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _showColorPalette
                  ? _buildColorPalette(colorScheme)
                  : const SizedBox.shrink(),
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

  void _toggleColorPalette() {
    if (_showColorPalette) {
      setState(() => _showColorPalette = false);
      return;
    }
    setState(() {
      _colorPresets = widget.colorPresetLibrary.activePresets;
      _showColorPalette = true;
    });
  }

  Widget _buildColorPalette(ColorScheme colorScheme) {
    if (_colorPresets.isEmpty) {
      return Container(
        width: double.infinity,
        height: 48,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: colorScheme.surface,
        child: Text(
          context.l10n.noSavedColorPresets,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    final prefixes = _colorPresets.map((preset) => preset.name).toList();
    return Container(
      width: double.infinity,
      height: 52,
      color: colorScheme.surface,
      child: ListenableBuilder(
        listenable: widget.lyricsState,
        builder: (context, _) {
          final selectedPrefix = widget.lyricsState.matchingPrefixAtSelection(
            prefixes,
          );
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: _colorPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 2),
            itemBuilder: (context, index) {
              final preset = _colorPresets[index];
              final isSelected = selectedPrefix == preset.name;
              return Tooltip(
                message: context.l10n.applyLineColor(preset.name),
                child: InkWell(
                  onTap: () => _applyColorPreset(preset),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ColorPreviewCircle(
                          value: _previewColor(preset.sungTextColor),
                          size: 28,
                          borderWidth: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  PreviewColorValue _previewColor(ColorPresetValue value) => PreviewColorValue(
    color0: Color(value.color0),
    color100: Color(value.color100),
    isGradient: value.isGradient,
  );

  void _applyColorPreset(ColorPresetAsset preset) {
    if (widget.lyricsState.selectionPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.selectLyricLineFirst)),
      );
      return;
    }
    final applied = widget.lyricsState.togglePrefixBeforeSelection(
      preset.name,
      _colorPresets.map((item) => item.name),
    );
    if (!applied) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.lineColoringFailed)));
    }
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
    String label = context.l10n.rubyLabel;
    if (node is LyricRuby) {
      label = '${node.baseText}：';
    } else if (node is LyricText) {
      final sel = widget.lyricsState.selectionPath;
      if (sel != null &&
          sel.length > 2 &&
          sel[2] >= 0 &&
          sel[2] < node.text.length) {
        final selectedLength = sel.length > 4 ? sel[4] : 1;
        final candidateEnd = sel[2] + (selectedLength < 1 ? 1 : selectedLength);
        final selectedEnd = candidateEnd > node.text.length
            ? node.text.length
            : candidateEnd;
        label = '${node.text.substring(sel[2], selectedEnd)}：';
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
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: context.l10n.rubyInputHint,
              ),
              onChanged: _onRubyChanged,
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
          title: Text(ctx.l10n.playbackSpeed),
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
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                widget.mediaPlayer.setRate(rate);
                Navigator.pop(ctx);
              },
              child: Text(ctx.l10n.apply),
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
          title: Text(ctx.l10n.taggingOffset),
          content: StatefulBuilder(
            builder: (ctx, ss) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$offset ms',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  offset < 0
                      ? ctx.l10n.advanceInputTime(-offset)
                      : ctx.l10n.delayInputTime(offset),
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
                  label: '$offset ms',
                  onChanged: (v) => ss(() => offset = v.round()),
                ),
                Text(
                  ctx.l10n.offsetHelp,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                widget.lyricsState.taggingOffsetMs = offset;
                setState(() {});
                Navigator.pop(ctx);
              },
              child: Text(ctx.l10n.apply),
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
