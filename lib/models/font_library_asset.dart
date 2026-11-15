import '../services/open_type_font.dart';

class FontFaceSelection {
  final String? path;
  final int faceIndex;
  final String displayName;
  final String styleName;

  const FontFaceSelection({
    required this.path,
    required this.faceIndex,
    required this.displayName,
    required this.styleName,
  });
}

class FontLibraryAsset {
  final String fileName;
  final String path;
  final String extension;
  final DateTime lastModified;
  final int fileSize;
  final List<OpenTypeFontFaceInfo> faces;

  const FontLibraryAsset({
    required this.fileName,
    required this.path,
    required this.extension,
    required this.lastModified,
    required this.fileSize,
    required this.faces,
  });

  String get displayName => faces.isEmpty ? fileName : faces.first.displayName;
}
