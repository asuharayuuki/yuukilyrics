import 'dart:convert';

import 'package:http/http.dart' as http;

const _repository = 'asuharayuuki/yuukilyrics';

class AppRelease {
  final String tag;
  final String notes;
  final bool isUpdate;

  const AppRelease({
    required this.tag,
    required this.notes,
    required this.isUpdate,
  });

  Uri get page => Uri.https('github.com', '/$_repository/releases/tag/$tag');
}

class UpdateCheckService {
  static final releasesPage = Uri.https('github.com', '/$_repository/releases');
  static final _latestRelease = Uri.https(
    'api.github.com',
    '/repos/$_repository/releases/latest',
  );
  static final _versionPattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');

  /// Returns null when GitHub has no published stable release.
  static Future<AppRelease?> check(String installedVersion) async {
    final currentVersion = _versionParts(installedVersion);
    final client = http.Client();
    try {
      final response = await client
          .get(
            _latestRelease,
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw http.ClientException(
          'GitHub returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> || data['tag_name'] is! String) {
        throw const FormatException('Invalid GitHub release');
      }
      final tag = data['tag_name'] as String;
      final latestVersion = _versionParts(tag);
      final notes = data['body'];
      return AppRelease(
        tag: tag,
        notes: notes is String ? notes.trim() : '',
        isUpdate: _compare(latestVersion, currentVersion) > 0,
      );
    } finally {
      client.close();
    }
  }

  static List<int> _versionParts(String value) {
    final match = _versionPattern.firstMatch(value);
    if (match == null) throw FormatException('Invalid app version', value);
    return [for (var index = 1; index <= 3; index++) int.parse(match[index]!)];
  }

  static int _compare(List<int> a, List<int> b) {
    for (var index = 0; index < a.length; index++) {
      final result = a[index].compareTo(b[index]);
      if (result != 0) return result;
    }
    return 0;
  }
}
