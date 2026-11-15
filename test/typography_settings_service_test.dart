import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/font_library_asset.dart';
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
      latinFont: FontFaceSelection(
        path: 'latin.ttc',
        faceIndex: 1,
        displayName: 'Latin Serif',
        styleName: 'Italic',
      ),
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
    expect(restored.latinFont?.path, settings.latinFont!.path);
    expect(restored.latinFont?.faceIndex, 1);
    expect(restored.latinFont?.displayName, 'Latin Serif');
    expect(restored.latinFont?.styleName, 'Italic');
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
      expect(restored.latinFont, isNull);
    },
  );
}
