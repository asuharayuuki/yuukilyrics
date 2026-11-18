import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/services/atomic_file_writer.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('atomic'));
  tearDown(() => dir.delete(recursive: true));

  List<String> names() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('install replaces an existing file and leaves nothing behind', () async {
    final destination = File('${dir.path}/a.ttf')..writeAsStringSync('old');
    final staged = File('${dir.path}/a.ttf.importing')
      ..writeAsStringSync('new');

    await AtomicFileWriter.install(staged, destination);

    expect(destination.readAsStringSync(), 'new');
    expect(names(), ['a.ttf']);
  });

  test('install keeps the existing file when the swap fails', () async {
    final destination = File('${dir.path}/a.ttf')..writeAsStringSync('old');
    final missing = File('${dir.path}/missing.importing');

    await expectLater(
      AtomicFileWriter.install(missing, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(destination.readAsStringSync(), 'old');
    expect(names(), ['a.ttf']);
  });

  test('writeBytes replaces contents atomically', () async {
    final destination = File('${dir.path}/pod.zip')..writeAsBytesSync([1]);
    await AtomicFileWriter.writeBytes(destination, [2, 3]);
    expect(destination.readAsBytesSync(), [2, 3]);
    expect(names(), ['pod.zip']);
  });
}
