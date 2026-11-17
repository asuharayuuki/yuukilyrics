import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../services/update_check_service.dart';

class UpdateCheckDialog extends StatefulWidget {
  final String installedVersion;
  final Future<AppRelease?> releaseCheck;

  const UpdateCheckDialog({
    super.key,
    required this.installedVersion,
    required this.releaseCheck,
  });

  @override
  State<UpdateCheckDialog> createState() => _UpdateCheckDialogState();
}

class _UpdateCheckDialogState extends State<UpdateCheckDialog> {
  bool _openFailed = false;

  Future<void> _openPage(Uri page) async {
    try {
      if (await launchUrl(page, mode: LaunchMode.externalApplication)) {
        if (mounted && _openFailed) setState(() => _openFailed = false);
        return;
      }
    } catch (_) {
      // Report platform launch failures in the dialog.
    }
    if (mounted) setState(() => _openFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<AppRelease?>(
      future: widget.releaseCheck,
      builder: (context, snapshot) {
        final checking = snapshot.connectionState != ConnectionState.done;
        final release = snapshot.data;
        final status = checking
            ? l10n.checkingForUpdates
            : snapshot.hasError
            ? l10n.updateCheckFailed
            : release == null
            ? l10n.noPublishedRelease
            : release.isUpdate
            ? l10n.updateAvailable
            : l10n.noUpdateAvailable;

        return AlertDialog(
          scrollable: true,
          title: Text(l10n.checkForUpdates),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status),
                if (checking) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (release != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.updateVersions(widget.installedVersion, release.tag),
                  ),
                  const Divider(height: 24),
                  if (release.notes.isEmpty)
                    Text(l10n.noReleaseNotes)
                  else
                    MarkdownBody(
                      data: release.notes,
                      selectable: true,
                      imageBuilder: (_, _, _) => const SizedBox.shrink(),
                      onTapLink: (_, href, _) {
                        final reference = href == null
                            ? null
                            : Uri.tryParse(href);
                        if (reference == null) return;
                        final link = release.page.resolveUri(reference);
                        if (link.scheme == 'https' && link.host.isNotEmpty) {
                          _openPage(link);
                        }
                      },
                    ),
                ],
                if (_openFailed) ...[
                  const SizedBox(height: 12),
                  Text(l10n.releasePageOpenFailed),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
            if (!checking)
              FilledButton.icon(
                onPressed: () =>
                    _openPage(release?.page ?? UpdateCheckService.releasesPage),
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.openReleasePage),
              ),
          ],
        );
      },
    );
  }
}
