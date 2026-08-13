class SingerAvatarAsset {
  final String singerName;
  final String path;
  final String extension;
  final DateTime lastModified;
  final int fileSize;

  const SingerAvatarAsset({
    required this.singerName,
    required this.path,
    required this.extension,
    required this.lastModified,
    required this.fileSize,
  });
}
