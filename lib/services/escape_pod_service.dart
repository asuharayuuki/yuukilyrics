import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'color_preset_library_service.dart';
import 'font_library_service.dart';
import 'singer_avatar_library_service.dart';

class EscapePodExportResult {
  final Uint8List bytes;
  final int fontCount;
  final int avatarCount;
  final int colorPresetCount;

  const EscapePodExportResult({
    required this.bytes,
    required this.fontCount,
    required this.avatarCount,
    required this.colorPresetCount,
  });
}

class EscapePodImportResult {
  final int fontCount;
  final int avatarCount;
  final int colorPresetCount;
  final List<String> skippedEntries;

  const EscapePodImportResult({
    required this.fontCount,
    required this.avatarCount,
    required this.colorPresetCount,
    required this.skippedEntries,
  });
}

class EscapePodService {
  static const formatName = 'yuukilyrics.escape-pod';
  static const formatVersion = 1;
  static const _maxEntries = 2000;
  static const _maxExpandedBytes = 1024 * 1024 * 1024;

  final FontLibraryService fontLibrary;
  final SingerAvatarLibraryService avatarLibrary;
  final ColorPresetLibraryService colorPresetLibrary;

  const EscapePodService({
    required this.fontLibrary,
    required this.avatarLibrary,
    required this.colorPresetLibrary,
  });

  Future<EscapePodExportResult> exportArchive() async {
    await Future.wait([
      fontLibrary.refresh(),
      avatarLibrary.refresh(),
      colorPresetLibrary.load(),
    ]);

    final archive = Archive();
    final fontFiles = await _libraryFiles(
      await fontLibrary.getLibraryDirectory(),
      FontLibraryService.supportedExtensions,
    );
    final avatarFiles = await _libraryFiles(
      await avatarLibrary.getLibraryDirectory(),
      SingerAvatarLibraryService.supportedExtensions,
    );

    for (final file in fontFiles) {
      archive.add(
        ArchiveFile.bytes(
          'fonts/${p.basename(file.path)}',
          await file.readAsBytes(),
        ),
      );
    }
    for (final file in avatarFiles) {
      archive.add(
        ArchiveFile.bytes(
          'singer_avatars/${p.basename(file.path)}',
          await file.readAsBytes(),
        ),
      );
    }

    final colorMarkdown = await colorPresetLibrary.exportMarkdown();
    archive.add(ArchiveFile.string('color_presets.md', colorMarkdown));

    final manifest = <String, Object>{
      'format': formatName,
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'contents': <String, Object>{
        'fonts': fontFiles.map((file) => p.basename(file.path)).toList(),
        'singerAvatars': avatarFiles
            .map((file) => p.basename(file.path))
            .toList(),
        'colorPresets': 'color_presets.md',
      },
    };
    archive.add(
      ArchiveFile.string(
        'manifest.json',
        const JsonEncoder.withIndent('  ').convert(manifest),
      ),
    );

    final encoded = ZipEncoder().encode(archive);
    return EscapePodExportResult(
      bytes: Uint8List.fromList(encoded),
      fontCount: fontFiles.length,
      avatarCount: avatarFiles.length,
      colorPresetCount: colorPresetLibrary.exportablePresets.length,
    );
  }

  Future<EscapePodImportResult> importArchive(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > _maxEntries) {
      throw const FormatException('Too many files in the escape pod.');
    }

    var expandedBytes = 0;
    final entries = <String, ArchiveFile>{};
    for (final entry in archive) {
      if (entry.isSymbolicLink) {
        throw const FormatException('Symbolic links are not supported.');
      }
      final name = _validatedEntryName(entry.name);
      if (!entry.isFile) continue;
      expandedBytes += entry.size;
      if (expandedBytes > _maxExpandedBytes) {
        throw const FormatException('The escape pod is too large.');
      }
      entries[name] = entry;
    }

    final manifestEntry = entries['manifest.json'];
    if (manifestEntry == null) {
      throw const FormatException('manifest.json is missing.');
    }
    final manifest = jsonDecode(
      utf8.decode(manifestEntry.content, allowMalformed: false),
    );
    if (manifest is! Map<String, dynamic> ||
        manifest['format'] != formatName ||
        manifest['version'] != formatVersion) {
      throw const FormatException('Unsupported escape pod format.');
    }

    final temporaryRoot = Directory(
      p.join(
        (await getTemporaryDirectory()).path,
        'yuukilyrics_escape_import_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await temporaryRoot.create(recursive: true);

    var fontCount = 0;
    var avatarCount = 0;
    var colorPresetCount = 0;
    final skipped = <String>[];
    try {
      for (final entry in entries.entries) {
        if (!entry.key.startsWith('fonts/')) continue;
        final fileName = entry.key.substring('fonts/'.length);
        if (!_isSingleFileName(fileName) ||
            !FontLibraryService.supportedExtensions.contains(
              p.extension(fileName).toLowerCase(),
            )) {
          skipped.add(entry.key);
          continue;
        }
        try {
          final staged = File(p.join(temporaryRoot.path, fileName));
          await staged.writeAsBytes(entry.value.content, flush: true);
          await fontLibrary.importFont(
            sourcePath: staged.path,
            replaceExisting: true,
          );
          fontCount++;
        } catch (_) {
          skipped.add(entry.key);
        }
      }

      for (final entry in entries.entries) {
        if (!entry.key.startsWith('singer_avatars/')) continue;
        final fileName = entry.key.substring('singer_avatars/'.length);
        final extension = p.extension(fileName).toLowerCase();
        final singerName = p.basenameWithoutExtension(fileName);
        if (!_isSingleFileName(fileName) ||
            !SingerAvatarLibraryService.supportedExtensions.contains(
              extension,
            ) ||
            avatarLibrary.validateSingerName(singerName) != null) {
          skipped.add(entry.key);
          continue;
        }
        try {
          final staged = File(p.join(temporaryRoot.path, fileName));
          await staged.writeAsBytes(entry.value.content, flush: true);
          await avatarLibrary.importImage(
            sourcePath: staged.path,
            singerName: singerName,
            replaceExisting: true,
          );
          avatarCount++;
        } catch (_) {
          skipped.add(entry.key);
        }
      }

      final colors = entries['color_presets.md'];
      if (colors != null) {
        try {
          colorPresetCount = await colorPresetLibrary.importMarkdown(
            utf8.decode(colors.content, allowMalformed: false),
          );
        } catch (_) {
          skipped.add('color_presets.md');
        }
      }
    } finally {
      if (await temporaryRoot.exists()) {
        await temporaryRoot.delete(recursive: true);
      }
      await Future.wait([
        fontLibrary.refresh(),
        avatarLibrary.refresh(),
        colorPresetLibrary.load(),
      ]);
    }

    return EscapePodImportResult(
      fontCount: fontCount,
      avatarCount: avatarCount,
      colorPresetCount: colorPresetCount,
      skippedEntries: List.unmodifiable(skipped),
    );
  }

  Future<List<File>> _libraryFiles(
    String directoryPath,
    Set<String> supportedExtensions,
  ) async {
    final result = <File>[];
    await for (final entity in Directory(
      directoryPath,
    ).list(followLinks: false)) {
      if (entity is! File) continue;
      if (!supportedExtensions.contains(
        p.extension(entity.path).toLowerCase(),
      )) {
        continue;
      }
      result.add(entity);
    }
    result.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return result;
  }

  String _validatedEntryName(String source) {
    final name = source.replaceAll('\\', '/');
    if (name.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        name.split('/').any((part) => part == '..')) {
      throw const FormatException('Unsafe path in escape pod.');
    }
    return name;
  }

  bool _isSingleFileName(String source) =>
      source.isNotEmpty && p.basename(source) == source;
}
