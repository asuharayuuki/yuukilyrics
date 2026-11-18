part of '../ass_export_screen.dart';

// Per-line alignment settings for 2-, 3- and 4-line pages.

class _LineAlignmentSettingsValue {
  final List<AssLineAlignment> twoLines;
  final List<AssLineAlignment> threeLines;
  final List<AssLineAlignment> fourLines;

  _LineAlignmentSettingsValue({
    required Iterable<AssLineAlignment> twoLines,
    required Iterable<AssLineAlignment> threeLines,
    required Iterable<AssLineAlignment> fourLines,
  }) : twoLines = List.unmodifiable(twoLines),
       threeLines = List.unmodifiable(threeLines),
       fourLines = List.unmodifiable(fourLines);
}

class _LineAlignmentSettingsDialog extends StatefulWidget {
  final _LineAlignmentSettingsValue initialValue;

  const _LineAlignmentSettingsDialog({required this.initialValue});

  @override
  State<_LineAlignmentSettingsDialog> createState() =>
      _LineAlignmentSettingsDialogState();
}

class _LineAlignmentSettingsDialogState
    extends State<_LineAlignmentSettingsDialog> {
  late List<AssLineAlignment> _twoLines;
  late List<AssLineAlignment> _threeLines;
  late List<AssLineAlignment> _fourLines;

  @override
  void initState() {
    super.initState();
    _twoLines = List.of(widget.initialValue.twoLines);
    _threeLines = List.of(widget.initialValue.threeLines);
    _fourLines = List.of(widget.initialValue.fourLines);
  }

  void _reset() {
    setState(() {
      _twoLines = List.of(kDefaultTwoLineAlignments);
      _threeLines = List.of(kDefaultThreeLineAlignments);
      _fourLines = List.of(kDefaultFourLineAlignments);
    });
  }

  Widget _buildGroup(String title, List<AssLineAlignment> alignments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var index = 0; index < alignments.length; index++) ...[
          Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(context.l10n.lineNumber(index + 1)),
              ),
              Expanded(
                child: SegmentedButton<AssLineAlignment>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: AssLineAlignment.left,
                      icon: const Icon(Icons.format_align_left),
                      tooltip: context.l10n.alignLeft,
                    ),
                    ButtonSegment(
                      value: AssLineAlignment.center,
                      icon: const Icon(Icons.format_align_center),
                      tooltip: context.l10n.alignCenter,
                    ),
                    ButtonSegment(
                      value: AssLineAlignment.right,
                      icon: const Icon(Icons.format_align_right),
                      tooltip: context.l10n.alignRight,
                    ),
                  ],
                  selected: {alignments[index]},
                  onSelectionChanged: (selection) {
                    setState(() => alignments[index] = selection.single);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          if (index != alignments.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.lineAlignmentSettings),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.lineAlignmentSettingsHelp),
              const SizedBox(height: 20),
              _buildGroup(context.l10n.bottomAlignedTwoLines, _twoLines),
              const SizedBox(height: 20),
              _buildGroup(context.l10n.bottomAlignedThreeLines, _threeLines),
              const SizedBox(height: 20),
              _buildGroup(context.l10n.bottomAlignedFourLines, _fourLines),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: Text(context.l10n.resetDefaults)),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _LineAlignmentSettingsValue(
              twoLines: _twoLines,
              threeLines: _threeLines,
              fourLines: _fourLines,
            ),
          ),
          child: Text(context.l10n.confirm),
        ),
      ],
    );
  }
}
