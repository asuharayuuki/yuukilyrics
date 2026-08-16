import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/color_preset_asset.dart';
import '../services/color_preset_library_service.dart';
import 'dual_color_preview.dart';

enum _SavedColorPresetAction { rename, delete }

class SavedColorPresetsDialog extends StatelessWidget {
  const SavedColorPresetsDialog({
    super.key,
    required this.library,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onImport,
  });

  final ColorPresetLibraryService library;
  final Future<void> Function(ColorPresetAsset preset) onAdd;
  final Future<void> Function(ColorPresetAsset preset) onRename;
  final Future<void> Function(ColorPresetAsset preset) onDelete;
  final Future<void> Function() onImport;

  PreviewColorValue _preview(ColorPresetValue value) => PreviewColorValue(
    color0: Color(value.color0),
    color100: Color(value.color100),
    isGradient: value.isGradient,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogHeight = min(620.0, MediaQuery.sizeOf(context).height * 0.72);
    return AlertDialog(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      title: Text(context.l10n.savedColorPresets),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SizedBox(
          width: double.maxFinite,
          height: dialogHeight,
          child: AnimatedBuilder(
            animation: library,
            builder: (context, _) {
              final presets = library.presets.toList()
                ..sort(
                  (left, right) => left.name.toLowerCase().compareTo(
                    right.name.toLowerCase(),
                  ),
                );
              if (presets.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.noSavedColorPresetLibrary,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 4),
                itemCount: presets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final preset = presets[index];
                  return Material(
                    key: ValueKey('saved-color-preset-${preset.name}'),
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                preset.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            DualColorPreview(
                              sung: _preview(preset.sungTextColor),
                              unsung: _preview(preset.unsungTextColor),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () => onAdd(preset),
                              tooltip: context.l10n.addToCurrentSingerColors,
                              color: theme.colorScheme.primary,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            PopupMenuButton<_SavedColorPresetAction>(
                              tooltip: context.l10n.moreActions,
                              iconColor: theme.colorScheme.onSurfaceVariant,
                              onSelected: (action) {
                                switch (action) {
                                  case _SavedColorPresetAction.rename:
                                    unawaited(onRename(preset));
                                  case _SavedColorPresetAction.delete:
                                    unawaited(onDelete(preset));
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: _SavedColorPresetAction.rename,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.edit_outlined,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    title: Text(context.l10n.renameColorPreset),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: _SavedColorPresetAction.delete,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.delete_outline,
                                      color: theme.colorScheme.error,
                                    ),
                                    title: Text(
                                      context.l10n.deleteColorPreset,
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: onImport, child: Text(context.l10n.importAction)),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
