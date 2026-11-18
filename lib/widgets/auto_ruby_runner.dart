import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/lyrics_state_service.dart';
import '../services/yahoo_furigana_client.dart';

/// Runs [LyricsStateService.autoRubyAndTagDocument] behind a modal progress
/// dialog with a stop button, then reports the outcome in a snack bar.
Future<void> runAutoRubyWithProgress(
  BuildContext context,
  LyricsStateService lyrics, {
  YahooFuriganaClient client = const YahooFuriganaClient(),
}) async {
  if (lyrics.document == null) return;
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  final result = await showDialog<_AutoRubyResult>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => _AutoRubyProgressDialog(lyrics: lyrics, client: client),
  );
  if (result == null) return;

  final message = switch (result) {
    _AutoRubyResult(error: final Object error) => error.toString(),
    _AutoRubyResult(outcome: AutoRubyOutcome.completed) =>
      l10n.autoRubyCompleted,
    _ => l10n.autoRubyCancelled,
  };
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

class _AutoRubyResult {
  final AutoRubyOutcome? outcome;
  final Object? error;
  const _AutoRubyResult({this.outcome, this.error});
}

class _AutoRubyProgressDialog extends StatefulWidget {
  final LyricsStateService lyrics;
  final YahooFuriganaClient client;

  const _AutoRubyProgressDialog({required this.lyrics, required this.client});

  @override
  State<_AutoRubyProgressDialog> createState() =>
      _AutoRubyProgressDialogState();
}

class _AutoRubyProgressDialogState extends State<_AutoRubyProgressDialog> {
  bool _stopRequested = false;
  AutoRubyProgress? _progress;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    _AutoRubyResult result;
    try {
      final outcome = await widget.lyrics.autoRubyAndTagDocument(
        client: widget.client,
        isCancelled: () => _stopRequested,
        onProgress: (update) {
          if (mounted) setState(() => _progress = update);
        },
      );
      result = _AutoRubyResult(outcome: outcome);
    } catch (error) {
      debugPrint('Auto ruby failed: $error');
      result = _AutoRubyResult(error: error);
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final progress = _progress;
    final status = progress == null
        ? l10n.preparing
        : progress.applying
        ? l10n.updatingLyrics
        : l10n.fetchingRubyProgress(
            progress.completedBatches + 1,
            progress.totalBatches,
          );

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.autoRubyAndChecks),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress?.fraction ?? 0),
            const SizedBox(height: 12),
            Text(status, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _stopRequested
                ? null
                : () => setState(() => _stopRequested = true),
            child: Text(l10n.stop),
          ),
        ],
      ),
    );
  }
}
