import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/color_preset_asset.dart';

class ColorPresetLibraryService extends ChangeNotifier {
  static const markdownHeader = <String>[
    'プリセット名',
    '歌唱済み文字色',
    '歌唱済み縁取り色',
    '歌唱済み飾り色',
    '未歌唱文字色',
    '未歌唱縁取り色',
    '未歌唱飾り色',
  ];

  final List<ColorPresetAsset> _presets = [];
  final List<ColorPresetAsset> _activePresets = [];
  String? _filePath;

  List<ColorPresetAsset> get presets => List.unmodifiable(_presets);
  List<ColorPresetAsset> get activePresets => List.unmodifiable(_activePresets);
  List<ColorPresetAsset> get exportablePresets {
    final merged = <String, ColorPresetAsset>{};
    for (final preset in _presets) {
      merged[_nameKey(preset.name)] = preset;
    }
    for (final preset in _activePresets) {
      merged[_nameKey(preset.name)] = preset;
    }
    return List.unmodifiable(merged.values);
  }

  void setActivePresets(Iterable<ColorPresetAsset> presets) {
    final next = presets
        .where((preset) => validateName(preset.name) == null)
        .toList(growable: false);
    if (_samePresets(_activePresets, next)) return;
    _activePresets
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  bool _samePresets(
    List<ColorPresetAsset> current,
    List<ColorPresetAsset> next,
  ) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (current[index].toMarkdownFields().join('\u0000') !=
          next[index].toMarkdownFields().join('\u0000')) {
        return false;
      }
    }
    return true;
  }

  Future<String> getFilePath() async {
    if (_filePath != null) return _filePath!;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'yuukilyrics'));
    if (!await directory.exists()) await directory.create(recursive: true);
    _filePath = p.join(directory.path, 'color_presets.md');
    return _filePath!;
  }

  Future<void> load() async {
    final file = File(await getFilePath());
    if (!await file.exists()) {
      _presets.clear();
      await _write();
      notifyListeners();
      return;
    }

    final parsed = <String, ColorPresetAsset>{};
    final lines = await file.readAsLines();
    for (final rawLine in lines) {
      final fields = _splitRow(rawLine);
      if (fields == null || fields.length != 7) continue;
      if (_isHeader(fields) || _isSeparator(fields)) continue;

      final name = fields.first.trim();
      if (validateName(name) != null) continue;
      final colors = fields
          .skip(1)
          .map(ColorPresetValue.tryParse)
          .toList(growable: false);
      if (colors.any((color) => color == null)) continue;

      parsed[_nameKey(name)] = ColorPresetAsset(
        name: name,
        sungTextColor: colors[0]!,
        sungOutlineColor: colors[1]!,
        sungDecorationColor: colors[2]!,
        unsungTextColor: colors[3]!,
        unsungOutlineColor: colors[4]!,
        unsungDecorationColor: colors[5]!,
      );
    }
    _presets
      ..clear()
      ..addAll(parsed.values);
    notifyListeners();
  }

  Future<String> readMarkdown() async {
    await load();
    if (_presets.isEmpty) return '';
    return File(await getFilePath()).readAsString();
  }

  Future<String> exportMarkdown() async {
    await load();
    return _serialize(exportablePresets);
  }

  Future<int> importMarkdown(String markdown) async {
    await load();
    final parsed = _parseMarkdown(markdown.split(RegExp(r'\r?\n')));
    await saveAll(parsed);
    return parsed.length;
  }

  Future<ColorPresetAsset> save(ColorPresetAsset preset) async {
    final name = preset.name.trim();
    final error = validateName(name);
    if (error != null) throw ArgumentError(error);
    final normalized = preset.renamed(name);
    final index = _indexOfName(name);
    if (index < 0) {
      _presets.add(normalized);
    } else {
      _presets[index] = normalized;
    }
    await _write();
    notifyListeners();
    return normalized;
  }

  Future<void> saveAll(Iterable<ColorPresetAsset> presets) async {
    for (final preset in presets) {
      final name = preset.name.trim();
      final error = validateName(name);
      if (error != null) throw ArgumentError(error);
      final normalized = preset.renamed(name);
      final index = _indexOfName(name);
      if (index < 0) {
        _presets.add(normalized);
      } else {
        _presets[index] = normalized;
      }
    }
    await _write();
    notifyListeners();
  }

  Future<void> rename(ColorPresetAsset preset, String newName) async {
    final name = newName.trim();
    final error = validateName(name);
    if (error != null) throw ArgumentError(error);
    final currentIndex = _indexOfName(preset.name);
    if (currentIndex < 0) throw StateError('Preset not found.');
    final duplicateIndex = _indexOfName(name);
    if (duplicateIndex >= 0 && duplicateIndex != currentIndex) {
      throw StateError('A preset with the same name already exists.');
    }
    _presets[currentIndex] = _presets[currentIndex].renamed(name);
    await _write();
    notifyListeners();
  }

  Future<void> delete(ColorPresetAsset preset) async {
    _presets.removeWhere(
      (item) => _nameKey(item.name) == _nameKey(preset.name),
    );
    await _write();
    notifyListeners();
  }

  String? validateName(String source) {
    final name = source.trim();
    if (name.isEmpty) return 'empty';
    if (name.contains('|') || name.contains('\n') || name.contains('\r')) {
      return 'invalid';
    }
    return null;
  }

  int _indexOfName(String name) {
    final key = _nameKey(name);
    return _presets.indexWhere((preset) => _nameKey(preset.name) == key);
  }

  String _nameKey(String name) => name.trim().toLowerCase();

  Future<void> _write() async {
    final file = File(await getFilePath());
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(_serialize(_presets), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  List<String>? _splitRow(String source) {
    var row = source.trim();
    if (!row.contains('|')) return null;
    if (row.startsWith('|')) row = row.substring(1);
    if (row.endsWith('|')) row = row.substring(0, row.length - 1);
    return row.split('|').map((field) => field.trim()).toList();
  }

  bool _isHeader(List<String> fields) {
    final first = fields.first.replaceAll(RegExp(r'\s+'), '');
    return first == 'プリセット名' || first == '预设名称' || first == '預設名稱';
  }

  bool _isSeparator(List<String> fields) =>
      fields.every((field) => RegExp(r'^:?-{3,}:?$').hasMatch(field.trim()));

  String _serialize(Iterable<ColorPresetAsset> presets) {
    final buffer = StringBuffer()
      ..writeln('| ${markdownHeader.join(' | ')} |')
      ..writeln('| ${List.filled(markdownHeader.length, '---').join(' | ')} |');
    for (final preset in presets) {
      buffer.writeln('| ${preset.toMarkdownFields().join(' | ')} |');
    }
    return buffer.toString();
  }

  List<ColorPresetAsset> _parseMarkdown(Iterable<String> lines) {
    final parsed = <String, ColorPresetAsset>{};
    for (final rawLine in lines) {
      final fields = _splitRow(rawLine);
      if (fields == null || fields.length != 7) continue;
      if (_isHeader(fields) || _isSeparator(fields)) continue;

      final name = fields.first.trim();
      if (validateName(name) != null) continue;
      final colors = fields
          .skip(1)
          .map(ColorPresetValue.tryParse)
          .toList(growable: false);
      if (colors.any((color) => color == null)) continue;
      parsed[_nameKey(name)] = ColorPresetAsset(
        name: name,
        sungTextColor: colors[0]!,
        sungOutlineColor: colors[1]!,
        sungDecorationColor: colors[2]!,
        unsungTextColor: colors[3]!,
        unsungOutlineColor: colors[4]!,
        unsungDecorationColor: colors[5]!,
      );
    }
    return parsed.values.toList(growable: false);
  }
}
