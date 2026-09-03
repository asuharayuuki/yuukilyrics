import 'dart:io';

// Usage: dart run tool/bump_date_version.dart [--date=YYYY-MM-DD] [--build=N]
void main(List<String> arguments) {
  var date = DateTime.now();
  int? requestedBuild;

  for (final argument in arguments) {
    if (argument.startsWith('--date=')) {
      date = _parseDate(argument.substring('--date='.length));
    } else if (argument.startsWith('--build=')) {
      requestedBuild = int.tryParse(argument.substring('--build='.length));
      if (requestedBuild == null || requestedBuild <= 0) {
        _fail('Build number must be a positive integer.');
      }
    } else {
      _fail('Unknown argument: $argument');
    }
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    _fail('Run this script from the repository root.');
  }

  final pubspecContent = pubspec.readAsStringSync();
  final currentVersionPattern = RegExp(
    r'^version:[ \t]*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)[ \t]*$',
    multiLine: true,
  );
  final currentVersionMatch = currentVersionPattern.firstMatch(
    pubspecContent.replaceAll('\r\n', '\n'),
  );
  if (currentVersionMatch == null) {
    _fail('Could not read the current version from pubspec.yaml.');
  }

  final currentBuild = int.parse(currentVersionMatch.group(1)!);
  final build = requestedBuild ?? currentBuild + 1;
  if (build > 2100000000) {
    _fail('Build number exceeds the Android versionCode limit.');
  }

  final version = '${date.year}.${date.month}.${date.day}';
  final tag = 'v$version';

  final edits = <_FileEdit>[
    _FileEdit('pubspec.yaml', [
      _Replacement(currentVersionPattern, 'version: $version+$build'),
    ]),
    _FileEdit('android/app/build.gradle.kts', [
      _Replacement(
        RegExp(r'^[ \t]*versionCode = [0-9]+[ \t]*$', multiLine: true),
        '        versionCode = $build',
      ),
      _Replacement(
        RegExp(
          r'^[ \t]*versionName = "[0-9]+\.[0-9]+\.[0-9]+"[ \t]*$',
          multiLine: true,
        ),
        '        versionName = "$version"',
      ),
    ]),
    for (final path in [
      'ios/Flutter/Debug.xcconfig',
      'ios/Flutter/Release.xcconfig',
      'macos/Flutter/Flutter-Debug.xcconfig',
      'macos/Flutter/Flutter-Release.xcconfig',
    ])
      _FileEdit(path, [
        _Replacement(
          RegExp(r'^FLUTTER_BUILD_NAME=.*$', multiLine: true),
          'FLUTTER_BUILD_NAME=$version',
        ),
        _Replacement(
          RegExp(r'^FLUTTER_BUILD_NUMBER=.*$', multiLine: true),
          'FLUTTER_BUILD_NUMBER=$build',
        ),
      ]),
    _FileEdit('windows/runner/Runner.rc', [
      _Replacement(
        RegExp(
          r'^#define VERSION_AS_NUMBER [0-9]+,[0-9]+,[0-9]+,[0-9]+[ \t]*$',
          multiLine: true,
        ),
        '#define VERSION_AS_NUMBER ${date.year},${date.month},${date.day},$build',
      ),
      _Replacement(
        RegExp(
          r'^#define VERSION_AS_STRING "[0-9]+\.[0-9]+\.[0-9]+"[ \t]*$',
          multiLine: true,
        ),
        '#define VERSION_AS_STRING "$version"',
      ),
    ]),
  ];

  final updatedFiles = <String, String>{};
  for (final edit in edits) {
    final file = File(edit.path);
    if (!file.existsSync()) {
      _fail('Required version file does not exist: ${edit.path}');
    }

    final originalContent = file.readAsStringSync();
    final usesCrLf = originalContent.contains('\r\n');
    var content = originalContent.replaceAll('\r\n', '\n');
    for (final replacement in edit.replacements) {
      final matches = replacement.pattern.allMatches(content).length;
      if (matches != 1) {
        _fail('Expected one version field in ${edit.path}, found $matches.');
      }
      content = content.replaceFirst(replacement.pattern, replacement.value);
    }
    updatedFiles[edit.path] = usesCrLf
        ? content.replaceAll('\n', '\r\n')
        : content;
  }

  for (final entry in updatedFiles.entries) {
    File(entry.key).writeAsStringSync(entry.value);
  }

  stdout.writeln('Version: $version+$build');
  stdout.writeln('Tag: $tag');
}

DateTime _parseDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    _fail('Date must use YYYY-MM-DD.');
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    _fail('Date is not valid: $value');
  }
  return date;
}

Never _fail(String message) {
  stderr.writeln('ERROR: $message');
  exit(1);
}

class _FileEdit {
  const _FileEdit(this.path, this.replacements);

  final String path;
  final List<_Replacement> replacements;
}

class _Replacement {
  const _Replacement(this.pattern, this.value);

  final RegExp pattern;
  final String value;
}
