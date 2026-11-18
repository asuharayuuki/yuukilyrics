import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';

/// Gallery album that exported videos are saved into on Android.
const exportedVideoAlbum = 'YuukiLyrics';

/// Shows the result of a mobile video export with share (and, on Android,
/// gallery) actions that stay available until the user closes the dialog.
///
/// With [saveToGallery], the video at [videoPath] is first copied into the
/// device gallery under [exportedVideoAlbum], where it stays visible to
/// other apps and survives uninstalling this one. The sandbox copy is then
/// removed once the dialog closes. If the gallery save fails (for example,
/// permission denied), the sandbox copy is kept so it can still be shared.
Future<void> showExportedVideoDialog(
  BuildContext context, {
  required String videoPath,
  required String shareFileName,
  required bool saveToGallery,
}) async {
  final l10n = context.l10n;
  var savedToGallery = false;
  String message;

  if (saveToGallery) {
    try {
      final hasAccess =
          await Gal.hasAccess(toAlbum: true) ||
          await Gal.requestAccess(toAlbum: true);
      if (!hasAccess) throw const _GalleryAccessDenied();
      await Gal.putVideo(videoPath, album: exportedVideoAlbum);
      savedToGallery = true;
      message = l10n.videoSavedToGallery(exportedVideoAlbum);
    } on GalException catch (error) {
      debugPrint('Saving video to gallery failed: $error');
      message = l10n.videoGallerySaveFailed(error.type.message);
    } catch (error) {
      debugPrint('Saving video to gallery failed: $error');
      message = l10n.videoGallerySaveFailed(error);
    }
  } else {
    message = l10n.videoSaved(videoPath);
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.videoExportComplete),
      content: Text(message),
      actions: [
        if (savedToGallery)
          TextButton.icon(
            onPressed: () => Gal.open(),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(l10n.openGallery),
          ),
        TextButton.icon(
          onPressed: () => SharePlus.instance.share(
            ShareParams(
              files: [XFile(videoPath)],
              subject: l10n.hardsubVideoShareSubject(shareFileName),
            ),
          ),
          icon: const Icon(Icons.share),
          label: Text(l10n.share),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.close),
        ),
      ],
    ),
  );

  if (savedToGallery) {
    try {
      await File(videoPath).delete();
    } catch (_) {
      // Leftover exports are removed by the startup temp cleanup.
    }
  }
}

class _GalleryAccessDenied implements Exception {
  const _GalleryAccessDenied();

  @override
  String toString() => GalExceptionType.accessDenied.message;
}
