import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/services/typography_settings_service.dart';

void main() {
  const fallback = TypographySettingsData(
    fontName: 'Bundled Font',
    customFontPath: null,
    fontFaceIndex: 0,
    fontDisplayName: 'Bundled Font',
    fontStyleName: 'Regular',
    fontSize: 85,
    letterSpacingStep: 0,
    decorationWidth: 10,
    fontOutlineWidth: null,
    rubyFontSize: null,
    rubyOutlineWidth: null,
    rubyBaseGap: null,
    lineSpacing: null,
    lyricsBottomMargin: 50,
    singerAvatarSize: null,
    singerAvatarGap: 0,
  );

  test('selected font survives a JSON round trip', () {
    const settings = TypographySettingsData(
      fontName: 'Example Sans Bold',
      customFontPath: r'C:\fonts\example.ttc',
      fontFaceIndex: 2,
      fontDisplayName: 'Example Sans',
      fontStyleName: 'Bold',
      fontSize: 85,
      letterSpacingStep: 0,
      decorationWidth: 10,
      fontOutlineWidth: null,
      rubyFontSize: null,
      rubyOutlineWidth: null,
      rubyBaseGap: null,
      lineSpacing: null,
      lyricsBottomMargin: 50,
      singerAvatarSize: null,
      singerAvatarGap: 0,
    );

    final restored = TypographySettingsData.fromJson(
      settings.toJson(),
      fallback: fallback,
    );

    expect(restored.fontName, settings.fontName);
    expect(restored.customFontPath, settings.customFontPath);
    expect(restored.fontFaceIndex, settings.fontFaceIndex);
    expect(restored.fontDisplayName, settings.fontDisplayName);
    expect(restored.fontStyleName, settings.fontStyleName);
  });

  test(
    'legacy settings without font fields keep the current fallback font',
    () {
      final restored = TypographySettingsData.fromJson(const {
        'version': 1,
        'fontSize': 96,
      }, fallback: fallback);

      expect(restored.fontName, fallback.fontName);
      expect(restored.customFontPath, fallback.customFontPath);
      expect(restored.fontFaceIndex, fallback.fontFaceIndex);
      expect(restored.fontDisplayName, fallback.fontDisplayName);
      expect(restored.fontStyleName, fallback.fontStyleName);
      expect(restored.fontSize, 96);
    },
  );
}
