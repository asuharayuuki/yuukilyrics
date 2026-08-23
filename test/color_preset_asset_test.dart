import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/color_preset_asset.dart';

void main() {
  group('ColorPresetValue markdown', () {
    test('keeps legacy formats', () {
      expect(ColorPresetValue.tryParse('#123ABC')!.toMarkdown(), '#123ABC');
      expect(
        ColorPresetValue.tryParse('#123ABC/#456DEF')!.toMarkdown(),
        '#123ABC/#456DEF',
      );
    });

    test('round-trips custom gradient stops', () {
      const source = 'g(0:#3DACCC,45:#0E8ACD,55:#FCDC59,100:#A77C0B)';
      final value = ColorPresetValue.tryParse(source)!;
      expect(value.mode, ColorFillMode.gradient);
      expect(value.stops.map((stop) => stop.position), [0, 0.45, 0.55, 1]);
      expect(value.toMarkdown(), source);
    });

    test('accepts spaces emitted by editable import text', () {
      const source = 'g(0:#3DACCC, 33.2:#3DACCC, 100:#0E8ACD)';
      final value = ColorPresetValue.tryParse(source);
      expect(value, isNotNull);
      expect(value!.stops.map((stop) => stop.position), [0, 0.332, 1]);
      expect(value.toMarkdown(), 'g(0:#3DACCC,33.2:#3DACCC,100:#0E8ACD)');
    });

    test('round-trips a 50 percent hard split', () {
      const source = 'm(0:#FF0000,50:#0000FF)';
      final value = ColorPresetValue.tryParse(source)!;
      expect(value.mode, ColorFillMode.millefeuille);
      expect(value.toMarkdown(), source);
    });

    test('preserves duplicate marker order', () {
      const source = 'g(0:#FFFFFF,50:#FFFFFF,50:#000000,100:#000000)';
      final value = ColorPresetValue.tryParse(source)!;
      expect(value.stops[1].color, 0xFFFFFFFF);
      expect(value.stops[2].color, 0xFF000000);
      expect(value.toMarkdown(), source);
    });

    test('rejects malformed markers', () {
      expect(ColorPresetValue.tryParse('m()'), isNull);
      expect(ColorPresetValue.tryParse('g(101:#FFFFFF)'), isNull);
      expect(ColorPresetValue.tryParse('m(50:FFFFFF)'), isNull);
    });
  });
}
