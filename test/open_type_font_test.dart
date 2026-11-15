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
    expect(face.assFaceName, 'NotoSerifCJKjp-Bold');
  });

  test('a face without a PostScript name uses its existing family lookup', () {
    const face = OpenTypeFontFaceInfo(
      index: 0,
      familyName: 'Example Serif',
      subfamilyName: 'Regular',
      fullName: 'Example Serif Regular',
      postScriptName: '',
    );

    expect(face.assFaceName, 'Example Serif');
  });
}
