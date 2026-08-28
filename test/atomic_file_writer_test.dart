import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/services/atomic_file_writer.dart';

void main() {
  test('serializes replacement writes and leaves no staging files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yuukilyrics_atomic_writer_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/settings.json');
    await destination.writeAsString('original');

    await Future.wait([
      AtomicFileWriter.writeString(destination, 'first'),
      AtomicFileWriter.writeString(destination, 'second'),
      AtomicFileWriter.writeString(destination, 'third'),
    ]);

    expect(await destination.readAsString(), 'third');
    expect(
      await directory
          .list()
          .where(
            (entry) =>
                entry.path.contains('.tmp.') || entry.path.contains('.bak.'),
          )
          .toList(),
      isEmpty,
    );
  });
}
