import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/singer_avatar_asset.dart';

class SingerAvatarLibraryService extends ChangeNotifier {
  static const supportedExtensions = {'.png', '.jpg', '.jpeg', '.webp'};

  final Map<String, SingerAvatarAsset> _assetsByKey = {};
  final Map<String, List<String>> _conflictsByName = {};
  String? _libraryDirectory;
  bool _isLoading = false;
  Future<void>? _refreshFuture;
  bool _isDisposed = false;

  bool get isLoading => _isLoading;
  String? get libraryDirectory => _libraryDirectory;
  List<SingerAvatarAsset> get assets {
    final result = _assetsByKey.values.toList();
    result.sort((a, b) => a.singerName.compareTo(b.singerName));
    return result;
  }

  Map<String, List<String>> get conflicts => Map.unmodifiable(
    _conflictsByName.map(
      (name, paths) => MapEntry(name, List.unmodifiable(paths)),
    ),
  );

  Map<String, String> get assetPathsBySinger => Map.unmodifiable({
    for (final asset in _assetsByKey.values) asset.singerName: asset.path,
  });

  Future<String> getLibraryDirectory() async {
    if (_libraryDirectory != null) return _libraryDirectory!;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(documents.path, 'yuukilyrics', 'singer_avatars'),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _libraryDirectory = directory.path;
    return directory.path;
  }

  Future<void> refresh() {
    final activeRefresh = _refreshFuture;
    if (activeRefresh != null) return activeRefresh;
    late final Future<void> refresh;
    refresh = _performRefresh().whenComplete(() {
      if (identical(_refreshFuture, refresh)) _refreshFuture = null;
    });
    _refreshFuture = refresh;
    return refresh;
  }

  Future<void> _performRefresh() async {
    _isLoading = true;
    _notifyChanged();
    try {
      final directory = Directory(await getLibraryDirectory());
      final grouped = <String, List<SingerAvatarAsset>>{};
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final extension = p.extension(entity.path).toLowerCase();
        if (!supportedExtensions.contains(extension)) continue;
        final singerName = p.basenameWithoutExtension(entity.path);
        if (singerName.startsWith('.') || validateSingerName(singerName) != null) {
          continue;
        }
        final stat = await entity.stat();
        final asset = SingerAvatarAsset(
          singerName: singerName,
          path: entity.path,
          extension: extension,
          lastModified: stat.modified,
          fileSize: stat.size,
        );
        grouped.putIfAbsent(_nameKey(singerName), () => []).add(asset);
      }

      _assetsByKey.clear();
      _conflictsByName.clear();
      for (final group in grouped.values) {
        if (group.length == 1) {
          _assetsByKey[_nameKey(group.single.singerName)] = group.single;
        } else {
          group.sort((a, b) => a.path.compareTo(b.path));
          _conflictsByName[group.first.singerName] = [
            for (final asset in group) asset.path,
          ];
        }
      }
    } finally {
      _isLoading = false;
      _notifyChanged();
    }
  }

  SingerAvatarAsset? findBySinger(String singerName) =>
      _assetsByKey[_nameKey(singerName.trim())];

  bool containsSinger(String singerName) =>
      _assetsByKey.containsKey(_nameKey(singerName.trim()));

  String? validateSingerName(String source) {
    final name = source.trim();
    if (name.isEmpty) return '歌手名を入力してください';
    if (name != source) return '歌手名の先頭と末尾に空白は使用できません';
    if (RegExp(r'[<>:"/\\|?*]').hasMatch(name)) {
      return '歌手名に < > : " / \\ | ? * は使用できません';
    }
    if (name.endsWith('.') || name.endsWith(' ')) {
      return '歌手名の末尾にピリオドまたは空白は使用できません';
    }
    final reserved = RegExp(
      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
      caseSensitive: false,
    );
    if (reserved.hasMatch(name)) return 'この名前はファイル名に使用できません';
    return null;
  }

  Future<void> importImage({
    required String sourcePath,
    required String singerName,
    required bool replaceExisting,
  }) async {
    final name = singerName.trim();
    final validationError = validateSingerName(name);
    if (validationError != null) throw ArgumentError(validationError);

    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('画像ファイルが見つかりません');
    final extension = p.extension(source.path).toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw ArgumentError('PNG、JPEG、WebP 形式の画像のみ使用できます');
    }
    await _validateImage(source);
    await refresh();

    final key = _nameKey(name);
    if (_conflictsByName.keys.any((value) => _nameKey(value) == key)) {
      throw StateError('この歌手名には重複ファイルがあります。先に競合を解消してください');
    }
    final existing = _assetsByKey[key];
    if (existing != null && !replaceExisting) {
      throw StateError('この歌手のアイコンは既に登録されています');
    }

    final directory = await getLibraryDirectory();
    final target = File(p.join(directory, '$name$extension'));
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final staged = File(p.join(directory, '.__avatar_import_$stamp$extension'));
    File? backup;
    var installed = false;
    try {
      await source.copy(staged.path);
      if (existing != null) {
        backup = File('${existing.path}.__avatar_backup_$stamp');
        await File(existing.path).rename(backup.path);
      }
      await staged.rename(target.path);
      installed = true;
    } catch (_) {
      if (await staged.exists()) await staged.delete();
      if (!installed && backup != null && await backup.exists()) {
        await backup.rename(existing!.path);
      }
      rethrow;
    }
    if (backup != null && await backup.exists()) {
      try {
        await backup.delete();
      } catch (_) {
        // Backup files are ignored by the library scanner.
      }
    }
    await refresh();
  }

  Future<void> renameSinger({
    required SingerAvatarAsset asset,
    required String newSingerName,
  }) async {
    final name = newSingerName.trim();
    final validationError = validateSingerName(name);
    if (validationError != null) throw ArgumentError(validationError);
    await refresh();

    final oldKey = _nameKey(asset.singerName);
    final newKey = _nameKey(name);
    final current = _assetsByKey[oldKey];
    if (current == null) throw StateError('元のアイコンファイルが見つかりません');
    if (oldKey != newKey &&
        (_assetsByKey.containsKey(newKey) ||
            _conflictsByName.keys.any((value) => _nameKey(value) == newKey))) {
      throw StateError('変更先の歌手名には既にアイコンが登録されています');
    }

    final target = p.join(
      await getLibraryDirectory(),
      '$name${current.extension}',
    );
    if (current.path == target) return;
    if (p.equals(current.path, target)) {
      final temporary = '$target.__avatar_rename_${DateTime.now().microsecondsSinceEpoch}';
      final staged = await File(current.path).rename(temporary);
      await staged.rename(target);
    } else {
      await File(current.path).rename(target);
    }
    await refresh();
  }

  Future<void> deleteAsset(SingerAvatarAsset asset) async {
    final current = findBySinger(asset.singerName);
    if (current != null && await File(current.path).exists()) {
      await File(current.path).delete();
    }
    await refresh();
  }

  Future<void> _validateImage(File file) async {
    final bytes = await file.readAsBytes();
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      if (image.width <= 0 || image.height <= 0) {
        throw const FormatException('画像サイズが正しくありません');
      }
    } catch (_) {
      throw const FormatException('画像を読み込めません');
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  void _notifyChanged() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  String _nameKey(String name) => name.trim().toLowerCase();
}
