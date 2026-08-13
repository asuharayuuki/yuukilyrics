import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/l10n.dart';
import '../models/font_library_asset.dart';
import '../services/font_library_service.dart';
import '../widgets/font_face_preview_text.dart';

class FontLibraryScreen extends StatefulWidget {
  final Widget? drawer;
  final FontLibraryService library;

  const FontLibraryScreen({super.key, this.drawer, required this.library});

  @override
  State<FontLibraryScreen> createState() => _FontLibraryScreenState();
}

class _FontLibraryScreenState extends State<FontLibraryScreen> {
  @override
  void initState() {
    super.initState();
    widget.library.refresh();
  }

  Future<void> _importFont() async {
    final l10n = context.l10n;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf', 'ttc'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    final fileName = p.basename(path);
    var replaceExisting = false;
    if (widget.library.containsFileName(fileName)) {
      replaceExisting =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.replaceExistingFont),
              content: Text(l10n.replaceFontQuestion(fileName)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.replace),
                ),
              ],
            ),
          ) ??
          false;
      if (!replaceExisting) return;
    }
    if (!mounted) return;

    await _runOperation(
      () => widget.library.importFont(
        sourcePath: path,
        replaceExisting: replaceExisting,
      ),
      l10n.fontImported,
    );
  }

  Future<void> _deleteFont(FontLibraryAsset asset) async {
    final l10n = context.l10n;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.deleteFont),
            content: Text(l10n.deleteFontQuestion(asset.displayName)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    if (!mounted) return;
    await _runOperation(
      () => widget.library.deleteAsset(asset),
      l10n.fontDeleted,
    );
  }

  Future<void> _showFontDetails(FontLibraryAsset asset) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: FontFacePreviewText(
          library: widget.library,
          asset: asset,
          face: asset.faces.first,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(asset.fileName),
                const SizedBox(height: 16),
                Text(
                  context.l10n.fontFaces,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final face in asset.faces)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.text_fields),
                    title: FontFacePreviewText(
                      library: widget.library,
                      asset: asset,
                      face: face,
                    ),
                    subtitle: Text(face.assFontName),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _runOperation(
    Future<void> Function() operation,
    String successMessage,
  ) async {
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed(error))),
      );
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
        title: Text(context.l10n.fontLibrary),
        actions: [
          IconButton(
            onPressed: widget.library.refresh,
            icon: const Icon(Icons.refresh),
            tooltip: context.l10n.refresh,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _importFont,
            icon: const Icon(Icons.font_download_outlined),
            tooltip: context.l10n.importFont,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.library,
        builder: (context, _) {
          final assets = widget.library.assets;
          if (widget.library.isLoading && assets.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return CustomScrollView(
            key: const PageStorageKey<String>('font-library-scroll'),
            slivers: [
              if (widget.library.invalidFiles.isNotEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      context.l10n.invalidFontFiles(
                        widget.library.invalidFiles.length,
                      ),
                    ),
                  ),
                ),
              if (assets.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text(context.l10n.noImportedFonts)),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  sliver: SliverList.separated(
                    itemCount: assets.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      return ListTile(
                        leading: const Icon(Icons.font_download_outlined),
                        title: FontFacePreviewText(
                          library: widget.library,
                          asset: asset,
                          face: asset.faces.first,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          context.l10n.fontFileSummary(
                            asset.fileName,
                            asset.faces.length,
                            _formatFileSize(asset.fileSize),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _showFontDetails(asset),
                        trailing: IconButton(
                          onPressed: () => _deleteFont(asset),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: context.l10n.deleteFont,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importFont,
        icon: const Icon(Icons.upload),
        label: Text(context.l10n.importFont),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
    return '${(kib / 1024).toStringAsFixed(1)} MB';
  }
}
