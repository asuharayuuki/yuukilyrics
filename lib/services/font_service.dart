import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/font_library_asset.dart';
import 'open_type_font.dart';

class FontService {
  static const bundledFontFamily = 'Kosugi Maru';
  static const bundledFontAsset = 'assets/fonts/KosugiMaru-Regular.ttf';

  String? sandboxFontPath;
  String? extractedFontName;

  Future<String> getSandboxFontsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final fontsDir = Directory(p.join(dir.path, 'yuuki_fonts_sandbox'));
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }
    return fontsDir.path;
  }

  Future<OpenTypeFontFile> inspectFontFile(String fontFilePath) async {
    final file = File(fontFilePath);
    if (!await file.exists()) {
      throw Exception('フォントファイルが見つかりません：$fontFilePath');
    }
    return OpenTypeFontFile.parse(await file.readAsBytes());
  }

  Future<OpenTypeFontFace> loadSelectedFace({
    String? fontFilePath,
    int faceIndex = 0,
  }) async {
    final bytes = fontFilePath == null
        ? await _loadBundledFontBytes()
        : await _readFontFile(fontFilePath);
    return OpenTypeFontFile.parse(bytes).faceAt(faceIndex);
  }

  Future<Uint8List> loadStandaloneFaceBytes({
    String? fontFilePath,
    int faceIndex = 0,
  }) async {
    final face = await loadSelectedFace(
      fontFilePath: fontFilePath,
      faceIndex: faceIndex,
    );
    return face.buildStandaloneFont();
  }

  Future<String> prepareFontForRendering({
    String? fontFilePath,
    int faceIndex = 0,
    FontFaceSelection? latinFont,
  }) async {
    final face = await loadSelectedFace(
      fontFilePath: fontFilePath,
      faceIndex: faceIndex,
    );
    final latinFace =
        latinFont != null &&
            (latinFont.path != fontFilePath || latinFont.faceIndex != faceIndex)
        ? await loadSelectedFace(
            fontFilePath: latinFont.path,
            faceIndex: latinFont.faceIndex,
          )
        : null;
    final sandboxDir = await getSandboxFontsDir();
    await _clearSandboxDirectory(sandboxDir);
    sandboxFontPath = await _writeStandaloneFace(sandboxDir, face);
    if (latinFace != null) {
      await _writeStandaloneFace(sandboxDir, latinFace, prefix: 'latin-');
    }
    extractedFontName = face.info.assFontName;
    return extractedFontName!;
  }

  Future<void> clearSandboxFonts() async {
    final sandboxDir = await getSandboxFontsDir();
    await _clearSandboxDirectory(sandboxDir);
    sandboxFontPath = null;
    extractedFontName = null;
  }

  Future<Uint8List> _readFontFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('フォントファイルが見つかりません：$path');
    }
    return file.readAsBytes();
  }

  Future<Uint8List> _loadBundledFontBytes() async {
    final data = await rootBundle.load(bundledFontAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<String> _writeStandaloneFace(
    String directoryPath,
    OpenTypeFontFace face, {
    String prefix = '',
  }) async {
    final safeName = face.info.assFontName.replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '_',
    );
    final path = p.join(
      directoryPath,
      '$prefix$safeName${face.standaloneExtension}',
    );
    await File(path).writeAsBytes(face.buildStandaloneFont(), flush: true);
    return path;
  }

  Future<void> _clearSandboxDirectory(String sandboxDir) async {
    final dir = Directory(sandboxDir);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
  }
}
