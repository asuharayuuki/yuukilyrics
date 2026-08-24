import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/color_preset_asset.dart';
import '../services/color_preset_library_service.dart';
import 'dual_color_preview.dart';

class SavedColorPresetsScreen extends StatelessWidget {
  const SavedColorPresetsScreen({
    super.key,
    required this.library,
    required this.onAdd,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
    required this.onImport,
    required this.onImportN3,
  });

  final ColorPresetLibraryService library;
  final Future<void> Function(ColorPresetAsset preset) onAdd;
  final Future<void> Function(ColorPresetAsset preset) onEdit;
  final Future<bool> Function(ColorPresetAsset preset, String newName) onRename;
  final Future<void> Function(ColorPresetAsset preset) onDelete;
  final Future<void> Function() onImport;
  final Future<void> Function() onImportN3;

  PreviewColorValue _preview(ColorPresetValue value) => PreviewColorValue(
    color0: Color(value.color0),
    color100: Color(value.color100),
    isGradient: value.isGradient,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.savedColorPresets),
        centerTitle: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 32.0;
          return SingleChildScrollView(
            key: const PageStorageKey<String>('saved-color-presets-scroll'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              40,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        bottom: 8,
                        top: 8,
                      ),
                      child: Text(
                        context.l10n.importAction,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildImportAction(
                              context,
                              title: context.l10n.importSavedColorPresets,
                              description: context
                                  .l10n
                                  .importSavedColorPresetsDescription,
                              onTap: onImport,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Divider(
                                height: 1,
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            _buildImportAction(
                              context,
                              title: context.l10n.importN3Project,
                              description:
                                  context.l10n.importN3ProjectDescription,
                              onTap: onImportN3,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        bottom: 8,
                        top: 8,
                      ),
                      child: Text(
                        context.l10n.savedColorPresets,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AnimatedBuilder(
                          animation: library,
                          builder: (context, _) {
                            final presets = library.presets.toList()
                              ..sort(
                                (left, right) => left.name
                                    .toLowerCase()
                                    .compareTo(right.name.toLowerCase()),
                              );
                            if (presets.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 56,
                                  horizontal: 16,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.palette_outlined,
                                      size: 44,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      context.l10n.noSavedColorPresetLibrary,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < presets.length;
                                  index++
                                ) ...[
                                  if (index > 0) const SizedBox(height: 6),
                                  _buildPresetRow(context, presets[index]),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImportAction(
    BuildContext context, {
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetRow(BuildContext context, ColorPresetAsset preset) {
    final theme = Theme.of(context);
    return Material(
      key: ValueKey('saved-color-preset-${preset.name}'),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: _EditablePresetName(preset: preset, onRename: onRename),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: context.l10n.editColors,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onEdit(preset),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: DualColorPreview(
                      sung: _preview(preset.sungTextColor),
                      unsung: _preview(preset.unsungTextColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => onAdd(preset),
                tooltip: context.l10n.addToCurrentSingerColors,
                color: theme.colorScheme.primary,
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                onPressed: () => onDelete(preset),
                tooltip: context.l10n.deleteColorPreset,
                color: theme.colorScheme.error,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditablePresetName extends StatefulWidget {
  const _EditablePresetName({required this.preset, required this.onRename});

  final ColorPresetAsset preset;
  final Future<bool> Function(ColorPresetAsset preset, String newName) onRename;

  @override
  State<_EditablePresetName> createState() => _EditablePresetNameState();
}

class _EditablePresetNameState extends State<_EditablePresetName> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.preset.name);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _EditablePresetName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.preset.name) {
      _controller.text = widget.preset.name;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  Future<void> _commit() async {
    if (_saving) return;
    final name = _controller.text.trim();
    if (name == widget.preset.name) return;
    _saving = true;
    final saved = await widget.onRename(widget.preset, name);
    _saving = false;
    if (!saved && mounted) {
      _controller.text = widget.preset.name;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLength: 80,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        counterText: '',
        hintText: context.l10n.colorPresetName,
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        _commit();
        _focusNode.unfocus();
      },
    );
  }
}
