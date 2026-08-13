import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/singer_avatar_asset.dart';
import '../services/singer_avatar_library_service.dart';
import '../l10n/l10n.dart';

class SingerAvatarLibraryScreen extends StatefulWidget {
  final Widget? drawer;
  final SingerAvatarLibraryService library;

  const SingerAvatarLibraryScreen({
    super.key,
    this.drawer,
    required this.library,
  });

  @override
  State<SingerAvatarLibraryScreen> createState() =>
      _SingerAvatarLibraryScreenState();
}

class _SingerAvatarLibraryScreenState extends State<SingerAvatarLibraryScreen> {
  @override
  void initState() {
    super.initState();
    widget.library.refresh();
  }

  Future<String?> _askSingerName({
    required String title,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.singerName,
              errorText: errorText,
            ),
            onSubmitted: (_) {
              final error = widget.library.validateSingerName(controller.text);
              if (error != null) {
                setDialogState(() => errorText = error);
              } else {
                Navigator.pop(context, controller.text.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final error = widget.library.validateSingerName(
                  controller.text,
                );
                if (error != null) {
                  setDialogState(() => errorText = error);
                } else {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: Text(context.l10n.confirm),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _uploadImage() async {
    final l10n = context.l10n;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    final name = await _askSingerName(
      title: context.l10n.addSingerIcon,
      initialValue: p.basenameWithoutExtension(path),
    );
    if (name == null || !mounted) return;

    var replace = false;
    if (widget.library.containsSinger(name)) {
      replace =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(context.l10n.replaceExistingIcon),
              content: Text(context.l10n.replaceSingerIconQuestion(name)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.replace),
                ),
              ],
            ),
          ) ??
          false;
      if (!replace) return;
    }

    await _runOperation(
      () => widget.library.importImage(
        sourcePath: path,
        singerName: name,
        replaceExisting: replace,
      ),
      l10n.singerIconSaved,
    );
  }

  Future<void> _renameAsset(SingerAvatarAsset asset) async {
    final l10n = context.l10n;
    final name = await _askSingerName(
      title: context.l10n.renameSinger,
      initialValue: asset.singerName,
    );
    if (name == null || name == asset.singerName) return;
    await _runOperation(
      () => widget.library.renameSinger(asset: asset, newSingerName: name),
      l10n.singerRenamed,
    );
  }

  Future<void> _deleteAsset(SingerAvatarAsset asset) async {
    final l10n = context.l10n;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.deleteSingerIcon),
            content: Text(
              context.l10n.deleteSingerIconQuestion(asset.singerName),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.delete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _runOperation(
      () => widget.library.deleteAsset(asset),
      l10n.singerIconDeleted,
    );
  }

  Future<void> _runOperation(
    Future<void> Function() operation,
    String successMessage,
  ) async {
    try {
      await operation();
      if (mounted) {
        PaintingBinding.instance.imageCache.clear();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.operationFailed(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        leading: widget.drawer == null
            ? null
            : Builder(
                builder: (context) => IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                  tooltip: context.l10n.openNavigationMenu,
                ),
              ),
        title: Text(context.l10n.assetLibrary),
        actions: [
          IconButton(
            onPressed: widget.library.refresh,
            icon: const Icon(Icons.refresh),
            tooltip: context.l10n.refresh,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _uploadImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: context.l10n.addSingerIcon,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.library,
        builder: (context, _) {
          if (widget.library.isLoading && widget.library.assets.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final assets = widget.library.assets;
          return CustomScrollView(
            key: const PageStorageKey<String>('avatar-library-scroll'),
            slivers: [
              if (widget.library.conflicts.isNotEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      context.l10n.singerIconConflicts(
                        widget.library.conflicts.length,
                      ),
                    ),
                  ),
                ),
              if (assets.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text(context.l10n.noSingerIcons)),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent: 242,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final asset = assets[index];
                      return _AvatarTile(
                        asset: asset,
                        onRename: () => _renameAsset(asset),
                        onDelete: () => _deleteAsset(asset),
                      );
                    }, childCount: assets.length),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadImage,
        icon: const Icon(Icons.upload),
        label: Text(context.l10n.addImage),
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  final SingerAvatarAsset asset;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _AvatarTile({
    required this.asset,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: Image.file(
                File(asset.path),
                key: ValueKey('${asset.path}:${asset.lastModified}'),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 40),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.singerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        asset.extension.substring(1).toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRename,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: context.l10n.renameSingerTooltip,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: context.l10n.delete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
