import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/services/lyrics_state_service.dart';

void main() {
  test('tokenization keeps extended characters and graphemes intact', () {
    final service = LyricsStateService();
    addTearDown(service.dispose);

    final tokens = service.tokenizeTextAdvanced('𠮷野👩‍🎤A');

    expect(tokens.map((token) => token.text).join(), '𠮷野👩‍🎤A');
    expect(tokens.first.text, startsWith('𠮷'));
    expect(tokens.any((token) => token.text.contains('�')), isFalse);
  });

  test('invalid selection indices are rejected without throwing', () {
    final service = LyricsStateService()..loadLrcText('歌詞');
    addTearDown(service.dispose);

    service.setSelection(0, 0);
    expect(service.getSelectedNode(), isNotNull);

    service.setSelection(-1, 0);
    expect(service.selectionPath, isNull);
    expect(service.getSelectedNode(), isNull);
  });

  test('timestamp shifting crosses one hour without wrapping minutes', () {
    final service = LyricsStateService()..loadLrcText('[59:59:90]歌詞');
    addTearDown(service.dispose);

    service.shiftAllTimestamps(200);

    expect(service.rawText, '[60:00:10]歌詞');
  });
}
