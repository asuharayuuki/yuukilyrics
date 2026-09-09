import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/services/open_type_font.dart';

void main() {
  test('ASS font name uses the family instead of a styled full name', () {
    const face = OpenTypeFontFaceInfo(
      index: 0,
      familyName: 'Noto Serif CJK JP',
      subfamilyName: 'Bold',
      fullName: 'Noto Serif CJK JP Bold',
      postScriptName: 'NotoSerifCJKjp-Bold',
    );

    expect(face.assFontName, 'Noto Serif CJK JP');
  });
}
