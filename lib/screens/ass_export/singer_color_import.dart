part of '../ass_export_screen.dart';

// Markdown singer-color source: parsing and the import/edit dialog.

class _SingerColorImportParseResult {
  final List<SingerColorInfo> singers;
  final SingerColorInfo? defaultColors;
  final int validLineCount;
  final List<String> errors;

  const _SingerColorImportParseResult({
    required this.singers,
    this.defaultColors,
    required this.validLineCount,
    required this.errors,
  });

  int get duplicateCount =>
      validLineCount - singers.length - (defaultColors == null ? 0 : 1);
}

_SingerColorImportParseResult _parseSingerColorText(
  String source,
  AppLocalizations l10n,
  String? defaultColorsName,
) {
  final singersByName = <String, SingerColorInfo>{};
  final errors = <String>[];
  SingerColorInfo? defaultColors;
  var validLineCount = 0;
  final lines = source.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'));

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty) continue;

    final fields = _splitSingerColorImportLine(line);
    if (fields == null) {
      errors.add(l10n.singerColorImportSplitError(index + 1));
      continue;
    }
    if (_isSingerColorImportHeader(fields) || _isMarkdownSeparatorRow(fields)) {
      continue;
    }
    if (fields.length != 7) {
      errors.add(
        l10n.singerColorImportColumnCountError(index + 1, fields.length),
      );
      continue;
    }

    final singerName = fields.first.trim();
    final isDefault = defaultColors == null && singerName == defaultColorsName;
    if (singerName.isEmpty && !isDefault) {
      errors.add(l10n.singerColorImportSingerRequired(index + 1));
      continue;
    }

    final colors = <AssColorValue>[];
    var invalidColorIndex = -1;
    for (var colorIndex = 1; colorIndex < fields.length; colorIndex++) {
      final color = _tryParseSingerColorValue(fields[colorIndex]);
      if (color == null) {
        invalidColorIndex = colorIndex;
        break;
      }
      colors.add(color);
    }
    if (invalidColorIndex >= 0) {
      final colorNames = [
        '',
        l10n.sungTextColor,
        l10n.sungOutlineColor,
        l10n.sungDecorationColor,
        l10n.unsungTextColor,
        l10n.unsungOutlineColor,
        l10n.unsungDecorationColor,
      ];
      errors.add(
        l10n.singerColorImportInvalidColor(
          index + 1,
          colorNames[invalidColorIndex],
          fields[invalidColorIndex],
        ),
      );
      continue;
    }

    validLineCount++;
    final singer = SingerColorInfo(
      prefix: singerName,
      preset: SingerColorPreset.none,
      sungTextColor: colors[0],
      sungOutlineColor: colors[1],
      sungDecorationColor: colors[2],
      unsungTextColor: colors[3],
      unsungOutlineColor: colors[4],
      unsungDecorationColor: colors[5],
    );
    if (isDefault) {
      defaultColors = singer;
    } else {
      singersByName[singerName] = singer;
    }
  }

  return _SingerColorImportParseResult(
    singers: singersByName.values.toList(),
    defaultColors: defaultColors,
    validLineCount: validLineCount,
    errors: errors,
  );
}

List<String>? _splitSingerColorImportLine(String line) {
  if (line.contains('\t')) {
    return line.split('\t').map((field) => field.trim()).toList();
  }
  if (!line.contains('|')) return null;

  var content = line;
  if (content.startsWith('|')) content = content.substring(1);
  if (content.endsWith('|')) content = content.substring(0, content.length - 1);
  return content.split('|').map((field) => field.trim()).toList();
}

bool _isSingerColorImportHeader(List<String> fields) {
  if (fields.length != 7) return false;
  final first = fields.first
      .replaceAll('*', '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();
  return first == '歌手' ||
      first == '歌手名称' ||
      first == '歌手名' ||
      first == 'プリセット名' ||
      first == '预设名称' ||
      first == '預設名稱' ||
      first == 'singer';
}

bool _isMarkdownSeparatorRow(List<String> fields) {
  if (fields.length != 7) return false;
  return fields.every((field) {
    final separator = field.replaceAll(':', '').trim();
    return RegExp(r'^-{3,}$').hasMatch(separator);
  });
}

AssColorValue? _tryParseSingerColorValue(String source) {
  final parsed = ColorPresetValue.tryParse(source);
  if (parsed == null) return null;
  if (!parsed.isGradient) return AssColorValue.solid(Color(parsed.color0));
  return AssColorValue.withStops(
    mode: parsed.isMillefeuille
        ? AssColorMode.millefeuille
        : AssColorMode.gradient,
    stops: parsed.stops
        .map(
          (stop) =>
              AssColorStop(position: stop.position, color: Color(stop.color)),
        )
        .toList(growable: false),
  );
}

@immutable
class _SingerColorPalette {
  final AssColorValue sungTextColor;
  final AssColorValue sungOutlineColor;
  final AssColorValue sungDecorationColor;
  final AssColorValue unsungTextColor;
  final AssColorValue unsungOutlineColor;
  final AssColorValue unsungDecorationColor;

  const _SingerColorPalette({
    required this.sungTextColor,
    required this.sungOutlineColor,
    required this.sungDecorationColor,
    required this.unsungTextColor,
    required this.unsungOutlineColor,
    required this.unsungDecorationColor,
  });
}

class _SingerColorImportDialog extends StatefulWidget {
  final String initialText;
  final String? title;
  final IconData titleIcon;
  final String? confirmLabel;
  final bool requireAllRowsValid;
  final String? defaultColorsName;

  const _SingerColorImportDialog({
    required this.initialText,
    this.title,
    this.titleIcon = Icons.upload_file,
    this.confirmLabel,
    this.requireAllRowsValid = false,
    this.defaultColorsName,
  });

  @override
  State<_SingerColorImportDialog> createState() =>
      _SingerColorImportDialogState();
}

class _SingerColorImportDialogState extends State<_SingerColorImportDialog> {
  static final Uri _onlineColorEditorUri = Uri.parse(
    'https://scheme.suisei.eu.org/',
  );

  late final TextEditingController _textController;
  late _SingerColorImportParseResult _parseResult;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _parseResult = const _SingerColorImportParseResult(
      singers: [],
      validLineCount: 0,
      errors: [],
    );
    _textController.addListener(_parseInput);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parseResult = _parseSingerColorText(
      _textController.text,
      context.l10n,
      widget.defaultColorsName,
    );
  }

  @override
  void dispose() {
    _textController.removeListener(_parseInput);
    _textController.dispose();
    super.dispose();
  }

  void _parseInput() {
    setState(() {
      _parseResult = _parseSingerColorText(
        _textController.text,
        context.l10n,
        widget.defaultColorsName,
      );
    });
  }

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    _textController.text = data!.text!;
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
  }

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: _textController.text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.copiedToClipboard)));
  }

  Future<void> _openOnlineColorEditor() async {
    try {
      final opened = await launchUrl(
        _onlineColorEditorUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('Unable to open $_onlineColorEditorUri');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasInput = _textController.text.trim().isNotEmpty;
    final statusColor = _parseResult.errors.isEmpty
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    final canSubmit =
        (_parseResult.singers.isNotEmpty ||
            _parseResult.defaultColors != null) &&
        (!widget.requireAllRowsValid || _parseResult.errors.isEmpty);

    // While the software keyboard is up, only the space above it is usable.
    // Shrink the dialog chrome so the source field keeps most of that space
    // instead of being squeezed by the title, toolbar and status rows.
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.viewInsets.bottom - media.padding.vertical;
    final compact = media.viewInsets.bottom > 0 || availableHeight < 560;

    final toolbarActions = [
      (Icons.content_copy, context.l10n.copy, _copyText),
      (Icons.content_paste, context.l10n.paste, _pasteText),
      (
        Icons.open_in_new,
        context.l10n.onlineColorEditor,
        _openOnlineColorEditor,
      ),
    ];

    return AlertDialog(
      insetPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      titlePadding: compact ? const EdgeInsets.fromLTRB(20, 12, 20, 0) : null,
      contentPadding: compact ? const EdgeInsets.fromLTRB(16, 8, 16, 0) : null,
      actionsPadding: compact ? const EdgeInsets.fromLTRB(16, 4, 16, 8) : null,
      title: Row(
        children: [
          Icon(widget.titleIcon, size: compact ? 20 : null),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title ?? context.l10n.singerColorImport,
              maxLines: compact ? 1 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: compact ? theme.textTheme.titleMedium : null,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SizedBox(
          width: double.maxFinite,
          // AlertDialog shrinks its content to fit, so in compact mode ask for
          // everything and let the field take whatever is left.
          height: compact
              ? max(0.0, availableHeight)
              : min(620.0, media.size.height * 0.72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (icon, label, onPressed) in toolbarActions)
                        IconButton(
                          onPressed: onPressed,
                          tooltip: label,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(icon, size: 20),
                        ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (icon, label, onPressed) in toolbarActions)
                      OutlinedButton.icon(
                        onPressed: onPressed,
                        icon: Icon(icon, size: 18),
                        label: Text(label),
                      ),
                  ],
                ),
              SizedBox(height: compact ? 4 : 10),
              Expanded(
                child: TextField(
                  controller: _textController,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: context.l10n.singerColorInputHint,
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              SizedBox(height: compact ? 6 : 12),
              Text(
                hasInput
                    ? context.l10n.singerColorImportSummary(
                        _parseResult.validLineCount,
                        _parseResult.singers.length,
                        _parseResult.duplicateCount,
                        _parseResult.errors.length,
                      )
                    : context.l10n.singerColorInputEmpty,
                maxLines: compact ? 1 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  color: hasInput
                      ? statusColor
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_parseResult.errors.isNotEmpty) ...[
                SizedBox(height: compact ? 4 : 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: compact ? 44 : 92),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          _parseResult.errors.join('\n'),
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: canSubmit
              ? () => Navigator.pop(context, _parseResult)
              : null,
          icon: const Icon(Icons.download_done, size: 18),
          label: Text(widget.confirmLabel ?? context.l10n.importValidRows),
        ),
      ],
    );
  }
}
