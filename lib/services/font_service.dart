import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;

class FontService {
  String? sandboxFontPath;
  String? extractedFontName;

  /// Returns the absolute path of the sandbox fonts directory.
  Future<String> getSandboxFontsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final fontsDir = Directory(p.join(dir.path, 'yuuki_fonts_sandbox'));
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }
    return fontsDir.path;
  }

  /// Extracts the bundled default font to the sandbox.
  /// Returns the internal English Font Family name.
  Future<String> extractBundledFont() async {
    final sandboxDir = await getSandboxFontsDir();
    final newPath = p.join(sandboxDir, 'KosugiMaru-Regular.ttf');
    final file = File(newPath);

    if (!await file.exists()) {
      final ByteData data = await rootBundle.load('assets/fonts/KosugiMaru-Regular.ttf');
      final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await file.writeAsBytes(bytes);
    }

    sandboxFontPath = newPath;
    
    // We already know its internal English name
    extractedFontName = 'Kosugi Maru';
    return extractedFontName!;
  }

  /// Copies the TTF file to the sandbox and renames it to its English internal name.
  /// Returns the internal English Font Family name.
  Future<String> processAndSandboxFont(String ttfFilePath) async {
    final file = File(ttfFilePath);
    if (!await file.exists()) {
      throw Exception("Font file does not exist: $ttfFilePath");
    }

    final bytes = await file.readAsBytes();
    final fontName = _extractEnglishFontFamilyName(bytes);
    extractedFontName = fontName;

    final sandboxDir = await getSandboxFontsDir();
    // Clear sandbox directory first to avoid old fonts piling up
    final dir = Directory(sandboxDir);
    if (await dir.exists()) {
      await for (var f in dir.list()) {
        if (f is File) {
          await f.delete();
        }
      }
    }

    // Rename file to <English_Font_Name>.ttf
    final newPath = p.join(sandboxDir, '$fontName.ttf');
    await file.copy(newPath);
    sandboxFontPath = newPath;

    return fontName;
  }

  String _extractEnglishFontFamilyName(Uint8List bytes) {
    final byteData = ByteData.view(bytes.buffer);
    
    // sfntVersion
    // final sfntVersion = byteData.getUint32(0, Endian.big);
    final numTables = byteData.getUint16(4, Endian.big);

    int nameTableOffset = -1;
    for (int i = 0; i < numTables; i++) {
      int offset = 12 + i * 16;
      int tag = byteData.getUint32(offset, Endian.big);
      // 'name' in ASCII is 0x6E616D65
      if (tag == 0x6E616D65) {
        nameTableOffset = byteData.getUint32(offset + 8, Endian.big);
        break;
      }
    }

    if (nameTableOffset == -1) {
      throw Exception("Invalid TTF: 'name' table not found.");
    }

    final numNameRecords = byteData.getUint16(nameTableOffset + 2, Endian.big);
    final stringStorageOffset = nameTableOffset + byteData.getUint16(nameTableOffset + 4, Endian.big);

    String? fallbackName;

    for (int i = 0; i < numNameRecords; i++) {
      int recordOffset = nameTableOffset + 6 + i * 12;
      int platformID = byteData.getUint16(recordOffset, Endian.big);
      // int encodingID = byteData.getUint16(recordOffset + 2, Endian.big);
      int languageID = byteData.getUint16(recordOffset + 4, Endian.big);
      int nameID = byteData.getUint16(recordOffset + 6, Endian.big);
      int stringLength = byteData.getUint16(recordOffset + 8, Endian.big);
      int stringOffset = byteData.getUint16(recordOffset + 10, Endian.big);

      // nameID 1 is Font Family
      // nameID 16 is Typographic Family (preferred if exists)
      if (nameID == 1 || nameID == 16) {
        final strBytes = bytes.sublist(
          stringStorageOffset + stringOffset, 
          stringStorageOffset + stringOffset + stringLength
        );
        
        // platformID 3 = Windows (UTF-16BE)
        // platformID 1 = Mac (MacRoman/ASCII)
        String decoded = "";
        if (platformID == 3) {
          // Decode UTF-16BE
          List<int> chars = [];
          for (int j = 0; j < strBytes.length; j += 2) {
            chars.add((strBytes[j] << 8) | strBytes[j+1]);
          }
          decoded = String.fromCharCodes(chars);
        } else if (platformID == 1) {
          decoded = String.fromCharCodes(strBytes);
        } else {
          continue;
        }

        // We want the English name (Mac LangID 0, Windows LangID 1033/0x0409)
        if ((platformID == 1 && languageID == 0) || (platformID == 3 && languageID == 1033)) {
          return decoded.trim();
        } else {
          fallbackName ??= decoded.trim();
        }
      }
    }

    if (fallbackName != null) return fallbackName;
    throw Exception("Could not extract Font Family name from TTF.");
  }
}
