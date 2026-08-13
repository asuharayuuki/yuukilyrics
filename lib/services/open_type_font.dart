import 'dart:math' as math;
import 'dart:typed_data';

class OpenTypeFontException implements Exception {
  final String message;

  const OpenTypeFontException(this.message);

  @override
  String toString() => message;
}

class OpenTypeFontFaceInfo {
  final int index;
  final String familyName;
  final String subfamilyName;
  final String fullName;
  final String postScriptName;

  const OpenTypeFontFaceInfo({
    required this.index,
    required this.familyName,
    required this.subfamilyName,
    required this.fullName,
    required this.postScriptName,
  });

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    if (subfamilyName.isEmpty || subfamilyName == 'Regular') return familyName;
    return '$familyName $subfamilyName';
  }

  String get assFontName {
    final normalized = subfamilyName.toLowerCase();
    if (normalized == 'regular' ||
        normalized == 'normal' ||
        normalized == 'roman') {
      return familyName;
    }
    return fullName.isNotEmpty ? fullName : familyName;
  }
}

class OpenTypeGlyphMetrics {
  final int glyphId;
  final double xMin;
  final double xMax;
  final double advanceWidth;
  final double leftSideBearing;
  final double rightSideBearing;
  final bool hasOutline;

  const OpenTypeGlyphMetrics({
    required this.glyphId,
    required this.xMin,
    required this.xMax,
    required this.advanceWidth,
    required this.leftSideBearing,
    required this.rightSideBearing,
    required this.hasOutline,
  });

  double get outlineWidth => math.max(0, xMax - xMin);
}

class OpenTypeFontFile {
  final Uint8List bytes;
  final List<OpenTypeFontFace> faces;

  OpenTypeFontFile._(this.bytes, this.faces);

  factory OpenTypeFontFile.parse(Uint8List source) {
    if (source.length < 12) {
      throw const OpenTypeFontException('フォントファイルが破損しています。');
    }
    final bytes = Uint8List.fromList(source);
    final data = ByteData.sublistView(bytes);
    final offsets = <int>[];
    if (_tag(data, 0) == 'ttcf') {
      _requireRange(bytes, 0, 12, 'TTC ヘッダーが不正です。');
      final count = data.getUint32(8, Endian.big);
      if (count == 0 || count > 4096) {
        throw const OpenTypeFontException('TTC に有効なフォントフェイスがありません。');
      }
      _requireRange(bytes, 12, count * 4, 'TTC のフォントフェイス一覧が不正です。');
      for (var i = 0; i < count; i++) {
        offsets.add(data.getUint32(12 + i * 4, Endian.big));
      }
    } else {
      offsets.add(0);
    }

    final faces = <OpenTypeFontFace>[];
    for (var i = 0; i < offsets.length; i++) {
      faces.add(OpenTypeFontFace._parse(bytes, data, i, offsets[i]));
    }
    return OpenTypeFontFile._(bytes, List.unmodifiable(faces));
  }

  OpenTypeFontFace faceAt(int index) {
    if (index < 0 || index >= faces.length) {
      throw OpenTypeFontException('フォントフェイス番号が不正です：$index');
    }
    return faces[index];
  }
}

class OpenTypeFontFace {
  final Uint8List _bytes;
  final ByteData _data;
  final int sfntOffset;
  final String sfntVersion;
  final Map<String, _TableRecord> _tables;
  final OpenTypeFontFaceInfo info;
  final int unitsPerEm;
  final int ascent;
  final int descent;
  final int numGlyphs;
  final int numberOfHMetrics;
  final int _indexToLocFormat;

  _Cmap? _cmap;
  _CffFont? _cff;
  final Map<int, OpenTypeGlyphMetrics> _glyphCache = {};

  String get standaloneExtension => sfntVersion == 'OTTO' ? '.otf' : '.ttf';

  OpenTypeFontFace._({
    required Uint8List bytes,
    required ByteData data,
    required this.sfntOffset,
    required this.sfntVersion,
    required Map<String, _TableRecord> tables,
    required this.info,
    required this.unitsPerEm,
    required this.ascent,
    required this.descent,
    required this.numGlyphs,
    required this.numberOfHMetrics,
    required int indexToLocFormat,
  }) : _bytes = bytes,
       _data = data,
       _tables = tables,
       _indexToLocFormat = indexToLocFormat;

  factory OpenTypeFontFace._parse(
    Uint8List bytes,
    ByteData data,
    int faceIndex,
    int sfntOffset,
  ) {
    _requireRange(bytes, sfntOffset, 12, 'フォントフェイスのテーブル一覧が不正です。');
    final version = _tag(data, sfntOffset);
    if (version != 'OTTO' &&
        version != 'true' &&
        version != 'typ1' &&
        data.getUint32(sfntOffset, Endian.big) != 0x00010000) {
      throw OpenTypeFontException('対応していないフォント形式です：$version');
    }
    final numTables = data.getUint16(sfntOffset + 4, Endian.big);
    _requireRange(bytes, sfntOffset + 12, numTables * 16, 'フォントテーブル一覧が不正です。');
    final tables = <String, _TableRecord>{};
    for (var i = 0; i < numTables; i++) {
      final recordOffset = sfntOffset + 12 + i * 16;
      final tag = _tag(data, recordOffset);
      final checksum = data.getUint32(recordOffset + 4, Endian.big);
      final offset = data.getUint32(recordOffset + 8, Endian.big);
      final length = data.getUint32(recordOffset + 12, Endian.big);
      _requireRange(bytes, offset, length, 'フォントテーブル $tag がファイル範囲外です。');
      tables[tag] = _TableRecord(tag, checksum, offset, length);
    }

    final head = _requiredTable(tables, 'head');
    final hhea = _requiredTable(tables, 'hhea');
    final maxp = _requiredTable(tables, 'maxp');
    _requireRange(bytes, head.offset, 54, 'head テーブルが不正です。');
    _requireRange(bytes, hhea.offset, 36, 'hhea テーブルが不正です。');
    _requireRange(bytes, maxp.offset, 6, 'maxp テーブルが不正です。');
    final unitsPerEm = data.getUint16(head.offset + 18, Endian.big);
    final ascent = data.getInt16(hhea.offset + 4, Endian.big);
    final descent = -data.getInt16(hhea.offset + 6, Endian.big);
    final numGlyphs = data.getUint16(maxp.offset + 4, Endian.big);
    final numberOfHMetrics = data.getUint16(hhea.offset + 34, Endian.big);
    if (unitsPerEm == 0 ||
        ascent <= 0 ||
        descent < 0 ||
        numGlyphs == 0 ||
        numberOfHMetrics == 0) {
      throw const OpenTypeFontException('フォントのメトリクスが不正です。');
    }
    final names = _readNames(bytes, data, tables['name']);
    final family = _pickName(names, 16) ?? _pickName(names, 1) ?? 'Font';
    final subfamily = _pickName(names, 17) ?? _pickName(names, 2) ?? 'Regular';
    final fullName =
        _pickName(names, 4) ??
        (subfamily == 'Regular' ? family : '$family $subfamily');
    final postScript = _pickName(names, 6) ?? fullName.replaceAll(' ', '');

    return OpenTypeFontFace._(
      bytes: bytes,
      data: data,
      sfntOffset: sfntOffset,
      sfntVersion: version,
      tables: Map.unmodifiable(tables),
      info: OpenTypeFontFaceInfo(
        index: faceIndex,
        familyName: family,
        subfamilyName: subfamily,
        fullName: fullName,
        postScriptName: postScript,
      ),
      unitsPerEm: unitsPerEm,
      ascent: ascent,
      descent: descent,
      numGlyphs: numGlyphs,
      numberOfHMetrics: numberOfHMetrics,
      indexToLocFormat: data.getInt16(head.offset + 50, Endian.big),
    );
  }

  OpenTypeGlyphMetrics metricsForCodePoint(int codePoint) {
    final glyphId = (_cmap ??= _Cmap.parse(
      _bytes,
      _data,
      _tables['cmap'],
    )).glyphFor(codePoint);
    return metricsForGlyph(glyphId >= 0 && glyphId < numGlyphs ? glyphId : 0);
  }

  OpenTypeGlyphMetrics metricsForGlyph(int glyphId) {
    if (glyphId < 0 || glyphId >= numGlyphs) glyphId = 0;
    return _glyphCache.putIfAbsent(glyphId, () {
      final hMetric = _horizontalMetric(glyphId);
      final bounds = _glyphBounds(glyphId);
      final outlineWidth = bounds == null
          ? 0.0
          : math.max(0.0, bounds.$2 - bounds.$1);
      final rightSideBearing = hMetric.$1 - hMetric.$2 - outlineWidth;
      return OpenTypeGlyphMetrics(
        glyphId: glyphId,
        xMin: bounds?.$1 ?? hMetric.$2,
        xMax: bounds?.$2 ?? hMetric.$2,
        advanceWidth: hMetric.$1,
        leftSideBearing: hMetric.$2,
        rightSideBearing: rightSideBearing,
        hasOutline: bounds != null && outlineWidth > 0,
      );
    });
  }

  (double, double) _horizontalMetric(int glyphId) {
    final hmtx = _requiredTable(_tables, 'hmtx');
    final metricIndex = math.min(glyphId, numberOfHMetrics - 1);
    final metricOffset = hmtx.offset + metricIndex * 4;
    _requireRange(_bytes, metricOffset, 4, 'hmtx テーブルが不正です。');
    final advance = _data.getUint16(metricOffset, Endian.big).toDouble();
    if (glyphId < numberOfHMetrics) {
      return (advance, _data.getInt16(metricOffset + 2, Endian.big).toDouble());
    }
    final lsbOffset =
        hmtx.offset + numberOfHMetrics * 4 + (glyphId - numberOfHMetrics) * 2;
    _requireRange(_bytes, lsbOffset, 2, 'hmtx の左サイドベアリングが不正です。');
    return (advance, _data.getInt16(lsbOffset, Endian.big).toDouble());
  }

  (double, double)? _glyphBounds(int glyphId) {
    if (_tables.containsKey('glyf')) return _trueTypeBounds(glyphId);
    if (_tables.containsKey('CFF ') || _tables.containsKey('CFF2')) {
      _cff ??= _CffFont.parse(
        _bytes,
        _data,
        _tables['CFF '] ?? _tables['CFF2']!,
        unitsPerEm,
      );
      return _cff!.boundsForGlyph(glyphId);
    }
    throw const OpenTypeFontException('対応する glyf、CFF、CFF2 アウトラインがありません。');
  }

  (double, double)? _trueTypeBounds(int glyphId) {
    final loca = _requiredTable(_tables, 'loca');
    final glyf = _requiredTable(_tables, 'glyf');
    int glyphOffset(int index) {
      if (_indexToLocFormat == 0) {
        final offset = loca.offset + index * 2;
        _requireRange(_bytes, offset, 2, 'loca テーブルが不正です。');
        return _data.getUint16(offset, Endian.big) * 2;
      }
      final offset = loca.offset + index * 4;
      _requireRange(_bytes, offset, 4, 'loca テーブルが不正です。');
      return _data.getUint32(offset, Endian.big);
    }

    final start = glyphOffset(glyphId);
    final end = glyphOffset(glyphId + 1);
    if (end <= start) return null;
    final offset = glyf.offset + start;
    _requireRange(_bytes, offset, 10, 'glyf のグリフデータが不正です。');
    return (
      _data.getInt16(offset + 2, Endian.big).toDouble(),
      _data.getInt16(offset + 6, Endian.big).toDouble(),
    );
  }

  Uint8List buildStandaloneFont() {
    final records = _tables.values.toList()
      ..sort((a, b) => a.tag.compareTo(b.tag));
    final numTables = records.length;
    final headerLength = 12 + numTables * 16;
    var totalLength = headerLength;
    final outputOffsets = <String, int>{};
    for (final record in records) {
      totalLength = (totalLength + 3) & ~3;
      outputOffsets[record.tag] = totalLength;
      totalLength += record.length;
    }
    totalLength = (totalLength + 3) & ~3;
    final output = Uint8List(totalLength);
    final out = ByteData.sublistView(output);
    output.setRange(0, 4, _bytes, sfntOffset);
    out.setUint16(4, numTables, Endian.big);
    final highestPower = 1 << (math.log(numTables) / math.ln2).floor();
    out.setUint16(6, highestPower * 16, Endian.big);
    out.setUint16(8, (math.log(highestPower) / math.ln2).round(), Endian.big);
    out.setUint16(10, numTables * 16 - highestPower * 16, Endian.big);

    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final directoryOffset = 12 + i * 16;
      _writeTag(output, directoryOffset, record.tag);
      out.setUint32(directoryOffset + 4, record.checksum, Endian.big);
      out.setUint32(
        directoryOffset + 8,
        outputOffsets[record.tag]!,
        Endian.big,
      );
      out.setUint32(directoryOffset + 12, record.length, Endian.big);
      final destination = outputOffsets[record.tag]!;
      output.setRange(
        destination,
        destination + record.length,
        _bytes,
        record.offset,
      );
    }

    final headOffset = outputOffsets['head'];
    if (headOffset != null) {
      out.setUint32(headOffset + 8, 0, Endian.big);
      final checksum = _fontChecksum(output);
      out.setUint32(
        headOffset + 8,
        (0xB1B0AFBA - checksum) & 0xFFFFFFFF,
        Endian.big,
      );
    }
    return output;
  }
}

class _TableRecord {
  final String tag;
  final int checksum;
  final int offset;
  final int length;

  const _TableRecord(this.tag, this.checksum, this.offset, this.length);
}

class _NameRecord {
  final int platform;
  final int encoding;
  final int language;
  final int nameId;
  final String value;

  const _NameRecord(
    this.platform,
    this.encoding,
    this.language,
    this.nameId,
    this.value,
  );
}

List<_NameRecord> _readNames(
  Uint8List bytes,
  ByteData data,
  _TableRecord? table,
) {
  if (table == null || table.length < 6) return const [];
  final count = data.getUint16(table.offset + 2, Endian.big);
  final storage = table.offset + data.getUint16(table.offset + 4, Endian.big);
  _requireRange(bytes, table.offset + 6, count * 12, 'name テーブルのレコードが不正です。');
  final result = <_NameRecord>[];
  for (var i = 0; i < count; i++) {
    final offset = table.offset + 6 + i * 12;
    final platform = data.getUint16(offset, Endian.big);
    final encoding = data.getUint16(offset + 2, Endian.big);
    final language = data.getUint16(offset + 4, Endian.big);
    final nameId = data.getUint16(offset + 6, Endian.big);
    final length = data.getUint16(offset + 8, Endian.big);
    final relative = data.getUint16(offset + 10, Endian.big);
    final start = storage + relative;
    if (start < 0 || start + length > bytes.length) continue;
    final raw = bytes.sublist(start, start + length);
    String value;
    if (platform == 0 || platform == 3) {
      if (raw.length.isOdd) continue;
      final codes = <int>[];
      for (var j = 0; j < raw.length; j += 2) {
        codes.add((raw[j] << 8) | raw[j + 1]);
      }
      value = String.fromCharCodes(codes);
    } else if (platform == 1) {
      value = String.fromCharCodes(raw);
    } else {
      continue;
    }
    value = value.replaceAll('\u0000', '').trim();
    if (value.isNotEmpty) {
      result.add(_NameRecord(platform, encoding, language, nameId, value));
    }
  }
  return result;
}

String? _pickName(List<_NameRecord> names, int nameId) {
  final candidates = names.where((record) => record.nameId == nameId).toList();
  if (candidates.isEmpty) return null;
  int score(_NameRecord record) {
    if (record.platform == 3 && record.language == 0x0409) return 0;
    if (record.platform == 0) return 1;
    if (record.platform == 3) return 2;
    if (record.platform == 1 && record.language == 0) return 3;
    return 4;
  }

  candidates.sort((a, b) => score(a).compareTo(score(b)));
  return candidates.first.value;
}

abstract class _Cmap {
  int glyphFor(int codePoint);

  static _Cmap parse(Uint8List bytes, ByteData data, _TableRecord? table) {
    if (table == null || table.length < 4) {
      throw const OpenTypeFontException('フォントに cmap テーブルがありません。');
    }
    final count = data.getUint16(table.offset + 2, Endian.big);
    _requireRange(bytes, table.offset + 4, count * 8, 'cmap の一覧が不正です。');
    final candidates = <(int, int, int, int)>[];
    for (var i = 0; i < count; i++) {
      final record = table.offset + 4 + i * 8;
      final platform = data.getUint16(record, Endian.big);
      final encoding = data.getUint16(record + 2, Endian.big);
      final subtable = table.offset + data.getUint32(record + 4, Endian.big);
      if (subtable < 0 || subtable + 2 > bytes.length) continue;
      final format = data.getUint16(subtable, Endian.big);
      var priority = 100;
      if (format == 12 && platform == 3 && encoding == 10) priority = 0;
      if (format == 12 && platform == 0) priority = math.min(priority, 1);
      if (format == 4 && platform == 3 && encoding == 1) priority = 2;
      if (format == 4 && platform == 0) priority = math.min(priority, 3);
      if (format == 13) priority = math.min(priority, 4);
      if (format == 6 || format == 0) priority = math.min(priority, 5);
      if (priority < 100) {
        candidates.add((priority, format, subtable, table.offset));
      }
    }
    if (candidates.isEmpty) {
      throw const OpenTypeFontException('対応する Unicode cmap がありません。');
    }
    candidates.sort((a, b) => a.$1.compareTo(b.$1));
    final selected = candidates.first;
    switch (selected.$2) {
      case 12:
      case 13:
        return _CmapGroups.parse(bytes, data, selected.$3, selected.$2 == 13);
      case 4:
        return _CmapFormat4.parse(bytes, data, selected.$3);
      case 6:
        return _CmapFormat6.parse(bytes, data, selected.$3);
      default:
        return _CmapFormat0.parse(bytes, data, selected.$3);
    }
  }
}

class _CmapGroups implements _Cmap {
  final List<(int, int, int)> groups;
  final bool constantGlyph;

  const _CmapGroups(this.groups, this.constantGlyph);

  factory _CmapGroups.parse(
    Uint8List bytes,
    ByteData data,
    int offset,
    bool constantGlyph,
  ) {
    _requireRange(bytes, offset, 16, 'cmap format 12/13 が不正です。');
    final count = data.getUint32(offset + 12, Endian.big);
    _requireRange(bytes, offset + 16, count * 12, 'cmap のグループが範囲外です。');
    final groups = <(int, int, int)>[];
    for (var i = 0; i < count; i++) {
      final p = offset + 16 + i * 12;
      groups.add((
        data.getUint32(p, Endian.big),
        data.getUint32(p + 4, Endian.big),
        data.getUint32(p + 8, Endian.big),
      ));
    }
    return _CmapGroups(groups, constantGlyph);
  }

  @override
  int glyphFor(int codePoint) {
    var low = 0;
    var high = groups.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final group = groups[middle];
      if (codePoint < group.$1) {
        high = middle - 1;
      } else if (codePoint > group.$2) {
        low = middle + 1;
      } else {
        return constantGlyph ? group.$3 : group.$3 + codePoint - group.$1;
      }
    }
    return 0;
  }
}

class _CmapFormat4 implements _Cmap {
  final ByteData data;
  final int offset;
  final int segmentCount;
  final int endCodes;
  final int startCodes;
  final int idDeltas;
  final int idRangeOffsets;

  const _CmapFormat4(
    this.data,
    this.offset,
    this.segmentCount,
    this.endCodes,
    this.startCodes,
    this.idDeltas,
    this.idRangeOffsets,
  );

  factory _CmapFormat4.parse(Uint8List bytes, ByteData data, int offset) {
    _requireRange(bytes, offset, 16, 'cmap format 4 が不正です。');
    final length = data.getUint16(offset + 2, Endian.big);
    _requireRange(bytes, offset, length, 'cmap format 4 が範囲外です。');
    final segmentCount = data.getUint16(offset + 6, Endian.big) ~/ 2;
    final endCodes = offset + 14;
    final startCodes = endCodes + segmentCount * 2 + 2;
    final idDeltas = startCodes + segmentCount * 2;
    final idRangeOffsets = idDeltas + segmentCount * 2;
    return _CmapFormat4(
      data,
      offset,
      segmentCount,
      endCodes,
      startCodes,
      idDeltas,
      idRangeOffsets,
    );
  }

  @override
  int glyphFor(int codePoint) {
    if (codePoint < 0 || codePoint > 0xFFFF) return 0;
    var low = 0;
    var high = segmentCount - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final end = data.getUint16(endCodes + middle * 2, Endian.big);
      if (codePoint > end) {
        low = middle + 1;
        continue;
      }
      final start = data.getUint16(startCodes + middle * 2, Endian.big);
      if (codePoint < start) {
        high = middle - 1;
        continue;
      }
      final delta = data.getInt16(idDeltas + middle * 2, Endian.big);
      final rangeOffset = data.getUint16(
        idRangeOffsets + middle * 2,
        Endian.big,
      );
      if (rangeOffset == 0) return (codePoint + delta) & 0xFFFF;
      final glyphOffset =
          idRangeOffsets + middle * 2 + rangeOffset + (codePoint - start) * 2;
      if (glyphOffset < 0 || glyphOffset + 2 > data.lengthInBytes) return 0;
      final glyph = data.getUint16(glyphOffset, Endian.big);
      return glyph == 0 ? 0 : (glyph + delta) & 0xFFFF;
    }
    return 0;
  }
}

class _CmapFormat6 implements _Cmap {
  final ByteData data;
  final int firstCode;
  final int count;
  final int glyphOffset;

  const _CmapFormat6(this.data, this.firstCode, this.count, this.glyphOffset);

  factory _CmapFormat6.parse(Uint8List bytes, ByteData data, int offset) {
    _requireRange(bytes, offset, 10, 'cmap format 6 が不正です。');
    final count = data.getUint16(offset + 8, Endian.big);
    _requireRange(bytes, offset + 10, count * 2, 'cmap format 6 が範囲外です。');
    return _CmapFormat6(
      data,
      data.getUint16(offset + 6, Endian.big),
      count,
      offset + 10,
    );
  }

  @override
  int glyphFor(int codePoint) {
    final index = codePoint - firstCode;
    if (index < 0 || index >= count) return 0;
    return data.getUint16(glyphOffset + index * 2, Endian.big);
  }
}

class _CmapFormat0 implements _Cmap {
  final Uint8List glyphs;

  const _CmapFormat0(this.glyphs);

  factory _CmapFormat0.parse(Uint8List bytes, ByteData data, int offset) {
    _requireRange(bytes, offset, 262, 'cmap format 0 が不正です。');
    return _CmapFormat0(Uint8List.sublistView(bytes, offset + 6, offset + 262));
  }

  @override
  int glyphFor(int codePoint) =>
      codePoint >= 0 && codePoint < glyphs.length ? glyphs[codePoint] : 0;
}

_TableRecord _requiredTable(Map<String, _TableRecord> tables, String tag) {
  final table = tables[tag];
  if (table == null) {
    throw OpenTypeFontException('フォントに $tag テーブルがありません。');
  }
  return table;
}

String _tag(ByteData data, int offset) {
  if (offset < 0 || offset + 4 > data.lengthInBytes) return '';
  return String.fromCharCodes([
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
    data.getUint8(offset + 3),
  ]);
}

void _writeTag(Uint8List bytes, int offset, String tag) {
  for (var i = 0; i < 4; i++) {
    bytes[offset + i] = tag.codeUnitAt(i);
  }
}

void _requireRange(Uint8List bytes, int offset, int length, String message) {
  if (offset < 0 || length < 0 || offset > bytes.length - length) {
    throw OpenTypeFontException(message);
  }
}

int _fontChecksum(Uint8List bytes) {
  final padded = (bytes.length + 3) & ~3;
  var sum = 0;
  for (var offset = 0; offset < padded; offset += 4) {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final index = offset + i;
      value = (value << 8) | (index < bytes.length ? bytes[index] : 0);
    }
    sum = (sum + value) & 0xFFFFFFFF;
  }
  return sum;
}

class _CffFont {
  final Uint8List bytes;
  final ByteData data;
  final int baseOffset;
  final bool isCff2;
  final int unitsPerEm;
  final _CffIndex charStrings;
  final _CffIndex globalSubrs;
  final _CffPrivateData topPrivate;
  final List<_CffPrivateData> fontDicts;
  final List<int>? glyphFontDicts;
  final List<double> topMatrix;
  final List<List<double>> fontMatrices;
  final Map<int, (double, double)?> _boundsCache = {};

  _CffFont._({
    required this.bytes,
    required this.data,
    required this.baseOffset,
    required this.isCff2,
    required this.unitsPerEm,
    required this.charStrings,
    required this.globalSubrs,
    required this.topPrivate,
    required this.fontDicts,
    required this.glyphFontDicts,
    required this.topMatrix,
    required this.fontMatrices,
  });

  factory _CffFont.parse(
    Uint8List bytes,
    ByteData data,
    _TableRecord table,
    int unitsPerEm,
  ) {
    final isCff2 = table.tag == 'CFF2';
    final base = table.offset;
    _requireRange(bytes, base, isCff2 ? 5 : 4, '${table.tag} テーブルが不正です。');
    Map<int, List<double>> topDict;
    late _CffIndex globalSubrs;
    if (isCff2) {
      final headerSize = data.getUint8(base + 2);
      final topDictLength = data.getUint16(base + 3, Endian.big);
      _requireRange(
        bytes,
        base + headerSize,
        topDictLength,
        'CFF2 Top DICT が不正です。',
      );
      topDict = _parseCffDict(bytes, data, base + headerSize, topDictLength);
      globalSubrs = _CffIndex.parse(
        bytes,
        data,
        base + headerSize + topDictLength,
        isCff2: true,
      );
    } else {
      final headerSize = data.getUint8(base + 2);
      var cursor = base + headerSize;
      final names = _CffIndex.parse(bytes, data, cursor);
      cursor = names.nextOffset;
      final topDictIndex = _CffIndex.parse(bytes, data, cursor);
      cursor = topDictIndex.nextOffset;
      if (topDictIndex.count == 0) {
        throw const OpenTypeFontException('CFF Top DICT が空です。');
      }
      final top = topDictIndex.objectRange(0);
      topDict = _parseCffDict(bytes, data, top.$1, top.$2 - top.$1);
      final strings = _CffIndex.parse(bytes, data, cursor);
      cursor = strings.nextOffset;
      globalSubrs = _CffIndex.parse(bytes, data, cursor);
    }

    final charStringsOffset = _dictInt(topDict, 17);
    if (charStringsOffset == null) {
      throw const OpenTypeFontException('CFF に CharStrings がありません。');
    }
    final charStrings = _CffIndex.parse(
      bytes,
      data,
      base + charStringsOffset,
      isCff2: isCff2,
    );
    final topPrivate = _readCffPrivate(bytes, data, base, topDict[18], isCff2);
    final topMatrix = _dictMatrix(topDict) ?? const [0.001, 0, 0, 0.001, 0, 0];

    final fontDicts = <_CffPrivateData>[];
    final fontMatrices = <List<double>>[];
    List<int>? glyphFontDicts;
    final fdArrayOffset = _dictInt(topDict, 0x0C24);
    final fdSelectOffset = _dictInt(topDict, 0x0C25);
    if (fdArrayOffset != null && fdSelectOffset != null) {
      final fdArray = _CffIndex.parse(
        bytes,
        data,
        base + fdArrayOffset,
        isCff2: isCff2,
      );
      for (var i = 0; i < fdArray.count; i++) {
        final range = fdArray.objectRange(i);
        final dict = _parseCffDict(bytes, data, range.$1, range.$2 - range.$1);
        fontDicts.add(_readCffPrivate(bytes, data, base, dict[18], isCff2));
        fontMatrices.add(_dictMatrix(dict) ?? topMatrix);
      }
      glyphFontDicts = _readFdSelect(
        bytes,
        data,
        base + fdSelectOffset,
        charStrings.count,
        fontDicts.length,
      );
    }

    return _CffFont._(
      bytes: bytes,
      data: data,
      baseOffset: base,
      isCff2: isCff2,
      unitsPerEm: unitsPerEm,
      charStrings: charStrings,
      globalSubrs: globalSubrs,
      topPrivate: topPrivate,
      fontDicts: fontDicts,
      glyphFontDicts: glyphFontDicts,
      topMatrix: topMatrix,
      fontMatrices: fontMatrices,
    );
  }

  (double, double)? boundsForGlyph(int glyphId) {
    if (glyphId < 0 || glyphId >= charStrings.count) return null;
    return _boundsCache.putIfAbsent(glyphId, () {
      var privateData = topPrivate;
      var matrix = topMatrix;
      if (glyphFontDicts != null && glyphId < glyphFontDicts!.length) {
        final fd = glyphFontDicts![glyphId];
        if (fd >= 0 && fd < fontDicts.length) {
          privateData = fontDicts[fd];
          matrix = fontMatrices[fd];
        }
      }
      final builder = _CffBoundsBuilder(matrix, unitsPerEm);
      final interpreter = _Type2Interpreter(
        bytes: bytes,
        data: data,
        globalSubrs: globalSubrs,
        localSubrs: privateData.localSubrs,
        isCff2: isCff2,
        bounds: builder,
      );
      final range = charStrings.objectRange(glyphId);
      interpreter.run(range.$1, range.$2);
      return builder.horizontalBounds;
    });
  }
}

class _CffPrivateData {
  final _CffIndex? localSubrs;

  const _CffPrivateData(this.localSubrs);
}

_CffPrivateData _readCffPrivate(
  Uint8List bytes,
  ByteData data,
  int cffBase,
  List<double>? privateValues,
  bool isCff2,
) {
  if (privateValues == null || privateValues.length < 2) {
    return const _CffPrivateData(null);
  }
  final size = privateValues[0].round();
  final offset = cffBase + privateValues[1].round();
  if (size <= 0) return const _CffPrivateData(null);
  _requireRange(bytes, offset, size, 'CFF Private DICT が不正です。');
  final dict = _parseCffDict(bytes, data, offset, size);
  final subrsOffset = _dictInt(dict, 19);
  if (subrsOffset == null) return const _CffPrivateData(null);
  return _CffPrivateData(
    _CffIndex.parse(bytes, data, offset + subrsOffset, isCff2: isCff2),
  );
}

class _CffIndex {
  final Uint8List bytes;
  final int count;
  final int dataStart;
  final List<int> offsets;
  final int nextOffset;

  const _CffIndex._(
    this.bytes,
    this.count,
    this.dataStart,
    this.offsets,
    this.nextOffset,
  );

  factory _CffIndex.parse(
    Uint8List bytes,
    ByteData data,
    int offset, {
    bool isCff2 = false,
  }) {
    final countSize = isCff2 ? 4 : 2;
    _requireRange(bytes, offset, countSize, 'CFF INDEX が不正です。');
    final count = isCff2
        ? data.getUint32(offset, Endian.big)
        : data.getUint16(offset, Endian.big);
    if (count == 0) {
      return _CffIndex._(bytes, 0, offset + countSize, const [
        1,
      ], offset + countSize);
    }
    if (count > 0x100000) {
      throw const OpenTypeFontException('CFF INDEX の項目数が不正です。');
    }
    _requireRange(
      bytes,
      offset + countSize,
      1,
      'CFF INDEX の offsetSize が不正です。',
    );
    final offsetSize = data.getUint8(offset + countSize);
    if (offsetSize < 1 || offsetSize > 4) {
      throw const OpenTypeFontException('CFF INDEX の offsetSize が不正です。');
    }
    final offsetsStart = offset + countSize + 1;
    _requireRange(
      bytes,
      offsetsStart,
      (count + 1) * offsetSize,
      'CFF INDEX のオフセット一覧が不正です。',
    );
    int readOffset(int index) {
      var value = 0;
      final start = offsetsStart + index * offsetSize;
      for (var i = 0; i < offsetSize; i++) {
        value = (value << 8) | data.getUint8(start + i);
      }
      return value;
    }

    final offsets = List<int>.generate(count + 1, readOffset, growable: false);
    final dataStart = offsetsStart + (count + 1) * offsetSize;
    final dataLength = offsets.last - 1;
    if (offsets.first != 1 || dataLength < 0) {
      throw const OpenTypeFontException('CFF INDEX のオフセットが不正です。');
    }
    _requireRange(bytes, dataStart, dataLength, 'CFF INDEX のデータが範囲外です。');
    return _CffIndex._(
      bytes,
      count,
      dataStart,
      offsets,
      dataStart + dataLength,
    );
  }

  (int, int) objectRange(int index) {
    if (index < 0 || index >= count) {
      throw OpenTypeFontException('CFF INDEX の番号が不正です：$index');
    }
    return (dataStart + offsets[index] - 1, dataStart + offsets[index + 1] - 1);
  }
}

Map<int, List<double>> _parseCffDict(
  Uint8List bytes,
  ByteData data,
  int offset,
  int length,
) {
  _requireRange(bytes, offset, length, 'CFF DICT が範囲外です。');
  final result = <int, List<double>>{};
  final operands = <double>[];
  var cursor = offset;
  final end = offset + length;
  while (cursor < end) {
    final byte = data.getUint8(cursor);
    if (byte <= 21) {
      cursor++;
      var operator = byte;
      if (byte == 12) {
        if (cursor >= end) break;
        operator = 0x0C00 | data.getUint8(cursor++);
      }
      result[operator] = List<double>.from(operands);
      operands.clear();
      continue;
    }
    final number = _readCffNumber(bytes, data, cursor, end, dictMode: true);
    operands.add(number.$1);
    cursor = number.$2;
  }
  return result;
}

(double, int) _readCffNumber(
  Uint8List bytes,
  ByteData data,
  int offset,
  int end, {
  bool dictMode = false,
}) {
  final byte = data.getUint8(offset);
  if (byte >= 32 && byte <= 246) return (byte - 139.0, offset + 1);
  if (byte >= 247 && byte <= 250) {
    _requireRange(bytes, offset, 2, 'CFF の数値が不正です。');
    return ((byte - 247) * 256 + data.getUint8(offset + 1) + 108.0, offset + 2);
  }
  if (byte >= 251 && byte <= 254) {
    _requireRange(bytes, offset, 2, 'CFF の数値が不正です。');
    return (
      -(byte - 251) * 256 - data.getUint8(offset + 1) - 108.0,
      offset + 2,
    );
  }
  if (byte == 28) {
    _requireRange(bytes, offset, 3, 'CFF shortint が不正です。');
    return (data.getInt16(offset + 1, Endian.big).toDouble(), offset + 3);
  }
  if (byte == 29 && dictMode) {
    _requireRange(bytes, offset, 5, 'CFF longint が不正です。');
    return (data.getInt32(offset + 1, Endian.big).toDouble(), offset + 5);
  }
  if (byte == 30 && dictMode) {
    final buffer = StringBuffer();
    var cursor = offset + 1;
    var done = false;
    while (cursor < end && !done) {
      final value = data.getUint8(cursor++);
      for (final nibble in [value >> 4, value & 0x0F]) {
        switch (nibble) {
          case <= 9:
            buffer.write(nibble);
          case 0xA:
            buffer.write('.');
          case 0xB:
            buffer.write('E');
          case 0xC:
            buffer.write('E-');
          case 0xE:
            buffer.write('-');
          case 0xF:
            done = true;
        }
        if (done) break;
      }
    }
    return (double.tryParse(buffer.toString()) ?? 0, cursor);
  }
  if (byte == 255) {
    _requireRange(bytes, offset, 5, 'CFF fixed の数値が不正です。');
    return (data.getInt32(offset + 1, Endian.big) / 65536.0, offset + 5);
  }
  throw OpenTypeFontException('対応していない CFF 数値形式です：$byte');
}

int? _dictInt(Map<int, List<double>> dict, int operator) {
  final values = dict[operator];
  return values == null || values.isEmpty ? null : values.first.round();
}

List<double>? _dictMatrix(Map<int, List<double>> dict) {
  final values = dict[0x0C07];
  return values != null && values.length >= 6
      ? List<double>.from(values.take(6))
      : null;
}

List<int> _readFdSelect(
  Uint8List bytes,
  ByteData data,
  int offset,
  int glyphCount,
  int fontDictCount,
) {
  _requireRange(bytes, offset, 1, 'CFF FDSelect が不正です。');
  final format = data.getUint8(offset);
  final result = List<int>.filled(glyphCount, 0);
  if (format == 0) {
    _requireRange(
      bytes,
      offset + 1,
      glyphCount,
      'CFF FDSelect format 0 が不正です。',
    );
    for (var i = 0; i < glyphCount; i++) {
      result[i] = math.min(
        data.getUint8(offset + 1 + i),
        math.max(0, fontDictCount - 1),
      );
    }
    return result;
  }
  if (format == 3) {
    _requireRange(bytes, offset + 1, 2, 'CFF FDSelect format 3 が不正です。');
    final ranges = data.getUint16(offset + 1, Endian.big);
    _requireRange(bytes, offset + 3, ranges * 3 + 2, 'CFF FDSelect が範囲外です。');
    for (var i = 0; i < ranges; i++) {
      final p = offset + 3 + i * 3;
      final first = data.getUint16(p, Endian.big);
      final fd = data.getUint8(p + 2);
      final next = i + 1 < ranges
          ? data.getUint16(p + 3, Endian.big)
          : data.getUint16(offset + 3 + ranges * 3, Endian.big);
      for (var glyph = first; glyph < math.min(next, glyphCount); glyph++) {
        result[glyph] = math.min(fd, math.max(0, fontDictCount - 1));
      }
    }
    return result;
  }
  if (format == 4) {
    _requireRange(bytes, offset + 1, 4, 'CFF2 FDSelect format 4 が不正です。');
    final ranges = data.getUint32(offset + 1, Endian.big);
    _requireRange(bytes, offset + 5, ranges * 6 + 4, 'CFF2 FDSelect が範囲外です。');
    for (var i = 0; i < ranges; i++) {
      final p = offset + 5 + i * 6;
      final first = data.getUint32(p, Endian.big);
      final fd = data.getUint16(p + 4, Endian.big);
      final next = i + 1 < ranges
          ? data.getUint32(p + 6, Endian.big)
          : data.getUint32(offset + 5 + ranges * 6, Endian.big);
      for (var glyph = first; glyph < math.min(next, glyphCount); glyph++) {
        result[glyph] = math.min(fd, math.max(0, fontDictCount - 1));
      }
    }
    return result;
  }
  throw OpenTypeFontException('対応していない CFF FDSelect 形式です：$format');
}

class _Type2Interpreter {
  final Uint8List bytes;
  final ByteData data;
  final _CffIndex globalSubrs;
  final _CffIndex? localSubrs;
  final bool isCff2;
  final _CffBoundsBuilder bounds;
  final List<double> stack = [];
  final List<double> transient = List<double>.filled(32, 0);
  double x = 0;
  double y = 0;
  int hintCount = 0;

  _Type2Interpreter({
    required this.bytes,
    required this.data,
    required this.globalSubrs,
    required this.localSubrs,
    required this.isCff2,
    required this.bounds,
  });

  void run(int start, int end) => _execute(start, end, 0);

  bool _execute(int start, int end, int depth) {
    if (depth > 32) {
      throw const OpenTypeFontException('CFF サブルーチンの再帰が深すぎます。');
    }
    var cursor = start;
    while (cursor < end) {
      final byte = data.getUint8(cursor);
      if (byte == 28 || byte == 255 || byte >= 32) {
        final number = _readCffNumber(bytes, data, cursor, end);
        stack.add(number.$1);
        cursor = number.$2;
        continue;
      }
      cursor++;
      if (byte == 12) {
        if (cursor >= end) break;
        _escape(data.getUint8(cursor++));
        continue;
      }
      switch (byte) {
        case 1:
        case 3:
        case 18:
        case 23:
          _consumeStemHints();
        case 4:
          if (stack.length > 1) stack.removeAt(0);
          if (stack.isNotEmpty) y += stack.last;
          stack.clear();
        case 5:
          for (var i = 0; i + 1 < stack.length; i += 2) {
            _lineTo(x + stack[i], y + stack[i + 1]);
          }
          stack.clear();
        case 6:
          var horizontal = true;
          for (final value in stack) {
            if (horizontal) {
              _lineTo(x + value, y);
            } else {
              _lineTo(x, y + value);
            }
            horizontal = !horizontal;
          }
          stack.clear();
        case 7:
          var vertical = true;
          for (final value in stack) {
            if (vertical) {
              _lineTo(x, y + value);
            } else {
              _lineTo(x + value, y);
            }
            vertical = !vertical;
          }
          stack.clear();
        case 8:
          _consumeCurves();
        case 10:
          if (stack.isNotEmpty && localSubrs != null) {
            final index =
                stack.removeLast().round() + _subrBias(localSubrs!.count);
            if (index >= 0 && index < localSubrs!.count) {
              final range = localSubrs!.objectRange(index);
              _execute(range.$1, range.$2, depth + 1);
            }
          }
        case 11:
          return true;
        case 14:
          stack.clear();
          return false;
        case 15:
          if (stack.isNotEmpty) stack.removeLast();
        case 16:
          _blend();
        case 19:
        case 20:
          _consumeStemHints();
          cursor += (hintCount + 7) ~/ 8;
          if (cursor > end) cursor = end;
        case 21:
          if (stack.length > 2) stack.removeAt(0);
          if (stack.length >= 2) {
            x += stack[stack.length - 2];
            y += stack.last;
          }
          stack.clear();
        case 22:
          if (stack.length > 1) stack.removeAt(0);
          if (stack.isNotEmpty) x += stack.last;
          stack.clear();
        case 24:
          while (stack.length > 2) {
            final values = stack.take(6).toList();
            stack.removeRange(0, 6);
            _curveBy(values);
          }
          if (stack.length >= 2) _lineTo(x + stack[0], y + stack[1]);
          stack.clear();
        case 25:
          while (stack.length > 6) {
            _lineTo(x + stack[0], y + stack[1]);
            stack.removeRange(0, 2);
          }
          if (stack.length >= 6) _curveBy(stack.take(6).toList());
          stack.clear();
        case 26:
          _vvCurves();
        case 27:
          _hhCurves();
        case 29:
          if (stack.isNotEmpty) {
            final index =
                stack.removeLast().round() + _subrBias(globalSubrs.count);
            if (index >= 0 && index < globalSubrs.count) {
              final range = globalSubrs.objectRange(index);
              _execute(range.$1, range.$2, depth + 1);
            }
          }
        case 30:
          _alternatingCurves(verticalFirst: true);
        case 31:
          _alternatingCurves(verticalFirst: false);
        default:
          stack.clear();
      }
    }
    return false;
  }

  void _consumeStemHints() {
    if (stack.length.isOdd) stack.removeAt(0);
    hintCount += stack.length ~/ 2;
    stack.clear();
  }

  void _lineTo(double nextX, double nextY) {
    bounds.line(x, y, nextX, nextY);
    x = nextX;
    y = nextY;
  }

  void _curveBy(List<double> values) {
    if (values.length < 6) return;
    final x1 = x + values[0];
    final y1 = y + values[1];
    final x2 = x1 + values[2];
    final y2 = y1 + values[3];
    final x3 = x2 + values[4];
    final y3 = y2 + values[5];
    bounds.curve(x, y, x1, y1, x2, y2, x3, y3);
    x = x3;
    y = y3;
  }

  void _consumeCurves() {
    while (stack.length >= 6) {
      _curveBy(stack.take(6).toList());
      stack.removeRange(0, 6);
    }
    stack.clear();
  }

  void _vvCurves() {
    var index = 0;
    var dx1 = 0.0;
    if (stack.length.isOdd) dx1 = stack[index++];
    while (index + 3 < stack.length) {
      final dy1 = stack[index++];
      final dx2 = stack[index++];
      final dy2 = stack[index++];
      final dy3 = stack[index++];
      _curveBy([dx1, dy1, dx2, dy2, 0, dy3]);
      dx1 = 0;
    }
    stack.clear();
  }

  void _hhCurves() {
    var index = 0;
    var dy1 = 0.0;
    if (stack.length.isOdd) dy1 = stack[index++];
    while (index + 3 < stack.length) {
      final dx1 = stack[index++];
      final dx2 = stack[index++];
      final dy2 = stack[index++];
      final dx3 = stack[index++];
      _curveBy([dx1, dy1, dx2, dy2, dx3, 0]);
      dy1 = 0;
    }
    stack.clear();
  }

  void _alternatingCurves({required bool verticalFirst}) {
    var index = 0;
    var vertical = verticalFirst;
    while (index + 3 < stack.length) {
      final remaining = stack.length - index;
      final a = stack[index++];
      final b = stack[index++];
      final c = stack[index++];
      final d = stack[index++];
      var finalDelta = 0.0;
      if (remaining == 5) finalDelta = stack[index++];
      if (vertical) {
        _curveBy([0, a, b, c, d, finalDelta]);
      } else {
        _curveBy([a, 0, b, c, finalDelta, d]);
      }
      vertical = !vertical;
    }
    stack.clear();
  }

  void _escape(int operator) {
    double pop() => stack.isEmpty ? 0 : stack.removeLast();
    switch (operator) {
      case 3:
        final b = pop();
        final a = pop();
        stack.add(a != 0 && b != 0 ? 1 : 0);
      case 4:
        final b = pop();
        final a = pop();
        stack.add(a != 0 || b != 0 ? 1 : 0);
      case 5:
        stack.add(pop() == 0 ? 1 : 0);
      case 9:
        stack.add(pop().abs());
      case 10:
        final b = pop();
        final a = pop();
        stack.add(a + b);
      case 11:
        final b = pop();
        final a = pop();
        stack.add(a - b);
      case 12:
        final b = pop();
        final a = pop();
        stack.add(b == 0 ? 0 : a / b);
      case 14:
        stack.add(-pop());
      case 15:
        final b = pop();
        final a = pop();
        stack.add(a == b ? 1 : 0);
      case 18:
        pop();
      case 20:
        final index = pop().round();
        final value = pop();
        if (index >= 0 && index < transient.length) transient[index] = value;
      case 21:
        final index = pop().round();
        stack.add(
          index >= 0 && index < transient.length ? transient[index] : 0,
        );
      case 22:
        final s2 = pop();
        final s1 = pop();
        final v2 = pop();
        final v1 = pop();
        stack.add(s1 <= s2 ? v1 : v2);
      case 23:
        stack.add(0.5);
      case 24:
        final b = pop();
        final a = pop();
        stack.add(a * b);
      case 26:
        stack.add(math.sqrt(math.max(0, pop())));
      case 27:
        if (stack.isNotEmpty) stack.add(stack.last);
      case 28:
        if (stack.length >= 2) {
          final last = stack.removeLast();
          final previous = stack.removeLast();
          stack.add(last);
          stack.add(previous);
        }
      case 29:
        final index = pop().round();
        if (stack.isEmpty) {
          stack.add(0);
        } else {
          stack.add(stack[math.max(0, stack.length - 1 - index)]);
        }
      case 30:
        final amount = pop().round();
        final count = pop().round();
        if (count > 0 && count <= stack.length) {
          final start = stack.length - count;
          final values = stack.sublist(start);
          stack.removeRange(start, stack.length);
          final shift = ((amount % count) + count) % count;
          stack.addAll(values.sublist(count - shift));
          stack.addAll(values.sublist(0, count - shift));
        }
      case 34:
        if (stack.length >= 7) {
          final v = List<double>.from(stack);
          _curveBy([v[0], 0, v[1], v[2], v[3], 0]);
          _curveBy([v[4], 0, v[5], -v[2], v[6], 0]);
        }
        stack.clear();
      case 35:
        if (stack.length >= 13) {
          final v = List<double>.from(stack);
          _curveBy(v.sublist(0, 6));
          _curveBy(v.sublist(6, 12));
        }
        stack.clear();
      case 36:
        if (stack.length >= 9) {
          final v = List<double>.from(stack);
          _curveBy([v[0], v[1], v[2], v[3], v[4], 0]);
          _curveBy([v[5], 0, v[6], v[7], v[8], -(v[1] + v[3] + v[7])]);
        }
        stack.clear();
      case 37:
        if (stack.length >= 11) {
          final v = List<double>.from(stack);
          final dx = v[0] + v[2] + v[4] + v[6] + v[8];
          final dy = v[1] + v[3] + v[5] + v[7] + v[9];
          final lastDx = dx.abs() > dy.abs() ? -dx : v[10];
          final lastDy = dx.abs() > dy.abs() ? v[10] : -dy;
          _curveBy(v.sublist(0, 6));
          _curveBy([v[6], v[7], v[8], v[9], lastDx, lastDy]);
        }
        stack.clear();
      default:
        stack.clear();
    }
  }

  void _blend() {
    if (!isCff2 || stack.isEmpty) return;
    final count = stack.removeLast().round();
    if (count <= 0 || stack.length < count) return;
    final baseValues = stack.take(count).toList();
    stack
      ..clear()
      ..addAll(baseValues);
  }

  static int _subrBias(int count) {
    if (count < 1240) return 107;
    if (count < 33900) return 1131;
    return 32768;
  }
}

class _CffBoundsBuilder {
  final List<double> matrix;
  final int unitsPerEm;
  double? _minX;
  double? _maxX;

  _CffBoundsBuilder(this.matrix, this.unitsPerEm);

  (double, double)? get horizontalBounds =>
      _minX == null || _maxX == null ? null : (_minX!, _maxX!);

  double _transformX(double x, double y) =>
      (matrix[0] * x + matrix[2] * y + matrix[4]) * unitsPerEm;

  void _include(double x, double y) {
    final transformed = _transformX(x, y);
    _minX = _minX == null ? transformed : math.min(_minX!, transformed);
    _maxX = _maxX == null ? transformed : math.max(_maxX!, transformed);
  }

  void line(double x0, double y0, double x1, double y1) {
    _include(x0, y0);
    _include(x1, y1);
  }

  void curve(
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    final p0 = _transformX(x0, y0);
    final p1 = _transformX(x1, y1);
    final p2 = _transformX(x2, y2);
    final p3 = _transformX(x3, y3);
    _includeTransformed(p0);
    _includeTransformed(p3);
    final a = -p0 + 3 * p1 - 3 * p2 + p3;
    final b = 2 * (p0 - 2 * p1 + p2);
    final c = p1 - p0;
    if (a.abs() < 1e-12) {
      if (b.abs() > 1e-12) _includeCurveAt(-c / b, p0, p1, p2, p3);
      return;
    }
    final discriminant = b * b - 4 * a * c;
    if (discriminant < 0) return;
    final root = math.sqrt(discriminant);
    _includeCurveAt((-b + root) / (2 * a), p0, p1, p2, p3);
    _includeCurveAt((-b - root) / (2 * a), p0, p1, p2, p3);
  }

  void _includeCurveAt(double t, double p0, double p1, double p2, double p3) {
    if (t <= 0 || t >= 1) return;
    final mt = 1 - t;
    _includeTransformed(
      mt * mt * mt * p0 +
          3 * mt * mt * t * p1 +
          3 * mt * t * t * p2 +
          t * t * t * p3,
    );
  }

  void _includeTransformed(double value) {
    _minX = _minX == null ? value : math.min(_minX!, value);
    _maxX = _maxX == null ? value : math.max(_maxX!, value);
  }
}
