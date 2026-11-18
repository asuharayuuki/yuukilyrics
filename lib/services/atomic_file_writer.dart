import 'dart:io';

/// Replaces files so that a crash or failed write never leaves the
/// destination truncated or missing.
///
/// New contents are written to a sibling staging file and then swapped in.
/// The existing file is set aside first (Windows cannot rename over a file)
/// and restored if the swap fails. Writes to the same path are serialized.
class AtomicFileWriter {
  AtomicFileWriter._();

  static final Map<String, Future<void>> _writeTails = {};

  /// Writes [contents] to [destination].
  ///
  /// Set [allowDirectFallback] for paths the user picked in a save dialog:
  /// a sandboxed app (e.g. on macOS) may only write that exact file and
  /// cannot create the staging file next to it. The write then goes straight
  /// to the destination instead of failing.
  static Future<void> writeString(
    File destination,
    String contents, {
    bool allowDirectFallback = false,
  }) => _serialized(
    destination,
    () => _writeNow(
      destination,
      (file) => file.writeAsString(contents, flush: true),
      allowDirectFallback: allowDirectFallback,
    ),
  );

  /// Byte counterpart of [writeString].
  static Future<void> writeBytes(
    File destination,
    List<int> bytes, {
    bool allowDirectFallback = false,
  }) => _serialized(
    destination,
    () => _writeNow(
      destination,
      (file) => file.writeAsBytes(bytes, flush: true),
      allowDirectFallback: allowDirectFallback,
    ),
  );

  /// Moves an already-written [staged] file onto [destination]. On failure
  /// the previous destination is kept and [staged] is removed.
  static Future<void> install(File staged, File destination) =>
      _serialized(destination, () async {
        try {
          await _swapIn(staged, destination);
        } finally {
          await _deleteQuietly(staged);
        }
      });

  static Future<void> _serialized(
    File destination,
    Future<void> Function() write,
  ) {
    final path = destination.absolute.path;
    final previous = _writeTails[path] ?? Future<void>.value();
    late final Future<void> operation;
    operation = () async {
      try {
        await previous;
      } catch (_) {
        // A failed write must not permanently block later saves.
      }
      await write();
    }();
    _writeTails[path] = operation;
    return operation.whenComplete(() {
      if (identical(_writeTails[path], operation)) {
        _writeTails.remove(path);
      }
    });
  }

  static Future<void> _writeNow(
    File destination,
    Future<void> Function(File file) writeContents, {
    required bool allowDirectFallback,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('${destination.path}.tmp.$stamp');
    try {
      await writeContents(temporary);
    } on FileSystemException {
      await _deleteQuietly(temporary);
      if (!allowDirectFallback) rethrow;
      await writeContents(destination);
      return;
    }
    try {
      await _swapIn(temporary, destination);
    } finally {
      await _deleteQuietly(temporary);
    }
  }

  static Future<void> _swapIn(File replacement, File destination) async {
    if (!await destination.exists()) {
      await replacement.rename(destination.path);
      return;
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final backup = File('${destination.path}.bak.$stamp');
    await destination.rename(backup.path);
    try {
      await replacement.rename(destination.path);
    } catch (_) {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
    // A leftover backup is harmless; the new contents are already in place.
    await _deleteQuietly(backup);
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
