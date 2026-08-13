import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/font_library_asset.dart';
import 'font_service.dart';

class FontLibraryService extends ChangeNotifier {
  static const supportedExtensions = <String>{'.ttf', '.otf', '.ttc'};

  final Map<String, FontLibraryAsset> _assetsByFileName = {};
  final Map<String, String> _invalidFiles = {};
  final Map<String, Future<String>> _previewFontLoads = {};
  Future<void>? _refreshFuture;
  String? _libraryDirectory;
  bool _isLoading = false;
  bool _isDisposed = false;

  bool get isLoading => _isLoading;
  String? get libraryDirectory => _libraryDirectory;

  List<FontLibraryAsset> get assets {
    final result = _assetsByFileName.values.toList();
    result.sort((a, b) {
      final byName = a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
      return byName != 0 ? byName : a.fileName.compareTo(b.fileName);
    });
    return result;
  }

  Map<String, String> get invalidFiles => Map.unmodifiable(_invalidFiles);

  Future<String> getLibraryDirectory() async {
    if (_libraryDirectory != null) return _libraryDirectory!;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'yuukilyrics', 'fonts'));
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
      final assets = <String, FontLibraryAsset>{};
      final invalidFiles = <String, String>{};
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final extension = p.extension(entity.path).toLowerCase();
        if (!supportedExtensions.contains(extension)) continue;
        final fileName = p.basename(entity.path);
        try {
          final font = await FontService().inspectFontFile(entity.path);
          final stat = await entity.stat();
          assets[_fileNameKey(fileName)] = FontLibraryAsset(
            fileName: fileName,
            path: entity.path,
            extension: extension,
            lastModified: stat.modified,
            fileSize: stat.size,
            faces: List.unmodifiable(font.faces.map((face) => face.info)),
          );
        } catch (error) {
          invalidFiles[fileName] = error.toString();
        }
      }
      _assetsByFileName
        ..clear()
        ..addAll(assets);
      _invalidFiles
        ..clear()
        ..addAll(invalidFiles);
    } finally {
      _isLoading = false;
      _notifyChanged();
    }
  }

  bool containsFileName(String fileName) =>
      _assetsByFileName.containsKey(_fileNameKey(fileName));

  bool containsPath(String path) => _assetsByFileName.values.any(
    (asset) => p.equals(p.absolute(asset.path), p.absolute(path)),
  );

  Future<FontLibraryAsset> importFont({
    required String sourcePath,
    bool replaceExisting = false,
  }) async {
    final extension = p.extension(sourcePath).toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw const FormatException('対応していないフォント形式です。');
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('フォントファイルが見つかりません。');
    }
    final parsed = await FontService().inspectFontFile(sourcePath);
    if (parsed.faces.isEmpty) {
      throw const FormatException('フォントフェイスが見つかりません。');
    }

    final directory = await getLibraryDirectory();
    final fileName = p.basename(sourcePath);
    final existing = _findFileByName(fileName);
    if (existing != null && !replaceExisting) {
      throw FileSystemException('同名のフォントは既に登録されています。', fileName);
    }

    final destinationPath = p.join(directory, fileName);
    if (!p.equals(p.absolute(sourcePath), p.absolute(destinationPath))) {
      final temporaryPath = '$destinationPath.importing';
      final temporary = File(temporaryPath);
      if (await temporary.exists()) await temporary.delete();
      await source.copy(temporaryPath);
      final destination = File(destinationPath);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destinationPath);
      if (existing != null && !p.equals(existing.path, destinationPath)) {
        final oldFile = File(existing.path);
        if (await oldFile.exists()) await oldFile.delete();
      }
    }

    await refresh();
    final imported = _assetsByFileName[_fileNameKey(fileName)];
    if (imported == null) {
      throw const FileSystemException('インポートしたフォントを読み込めませんでした。');
    }
    return imported;
  }

  Future<void> deleteAsset(FontLibraryAsset asset) async {
    final file = File(asset.path);
    if (await file.exists()) await file.delete();
    await refresh();
  }

  Future<String> loadPreviewFontFamily({
    required FontLibraryAsset asset,
    required int faceIndex,
  }) {
    final key =
        '${asset.path}|${asset.fileSize}|'
        '${asset.lastModified.microsecondsSinceEpoch}|$faceIndex';
    return _previewFontLoads.putIfAbsent(
      key,
      () => _loadPreviewFontFamily(asset.path, faceIndex, key),
    );
  }

  Future<String> _loadPreviewFontFamily(
    String path,
    int faceIndex,
    String key,
  ) async {
    final family =
        'YuukiFontPreview_'
        '${key.hashCode.toUnsigned(32).toRadixString(16)}';
    final bytes = await FontService().loadStandaloneFaceBytes(
      fontFilePath: path,
      faceIndex: faceIndex,
    );
    final data = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final loader = FontLoader(family)..addFont(Future.value(data));
    await loader.load();
    return family;
  }

  FontLibraryAsset? _findFileByName(String fileName) =>
      _assetsByFileName[_fileNameKey(fileName)];

  String _fileNameKey(String fileName) => fileName.toLowerCase();

  void _notifyChanged() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
