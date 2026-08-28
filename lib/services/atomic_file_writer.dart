import 'dart:io';

class AtomicFileWriter {
  AtomicFileWriter._();

  static final Map<String, Future<void>> _writeTails = {};

  static Future<void> writeString(File destination, String contents) {
    final path = destination.absolute.path;
    final previous = _writeTails[path] ?? Future<void>.value();
    late final Future<void> operation;
    operation = () async {
      try {
        await previous;
      } catch (_) {
        // A failed write must not permanently block later saves.
      }
      await _writeStringNow(destination, contents);
    }();
    _writeTails[path] = operation;
    return operation.whenComplete(() {
      if (identical(_writeTails[path], operation)) {
        _writeTails.remove(path);
      }
    });
  }

  static Future<void> _writeStringNow(File destination, String contents) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('${destination.path}.tmp.$stamp');
    final backup = File('${destination.path}.bak.$stamp');
    var movedOriginal = false;
    var installedReplacement = false;

    try {
      await temporary.writeAsString(contents, flush: true);
      if (await destination.exists()) {
        await destination.rename(backup.path);
        movedOriginal = true;
      }
      await temporary.rename(destination.path);
      installedReplacement = true;
    } catch (_) {
      if (movedOriginal &&
          !await destination.exists() &&
          await backup.exists()) {
        await backup.rename(destination.path);
        movedOriginal = false;
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
      if (installedReplacement && await backup.exists()) {
        try {
          await backup.delete();
        } catch (_) {}
      }
    }
  }
}
