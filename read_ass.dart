import 'dart:io';
void main() {
  final dir = Directory(r'C:\Users\Sekai\Desktop');
  for (var entity in dir.listSync()) {
    if (entity.path.endsWith('.ass')) {
      final bytes = File(entity.path).readAsBytesSync();
      print('Length: ${bytes.length}');
      if (bytes.length > 10) print(bytes.sublist(0, 10));
      break;
    }
  }
}
