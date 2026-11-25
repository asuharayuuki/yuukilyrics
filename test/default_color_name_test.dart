import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/l10n/generated/app_localizations.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/color_preset_library_service.dart';
import 'package:yuukilyrics/services/font_library_service.dart';
import 'package:yuukilyrics/services/singer_avatar_library_service.dart';

class _TestAvatarLibrary extends SingerAvatarLibraryService {
  @override
  Future<void> refresh() async {}
}

/// Name fields of the color rows, top (default) first.
Finder _nameFields() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      (widget.decoration?.hintText == '默认配色' ||
          widget.decoration?.hintText == '行首字符'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ColorPresetLibraryService> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final avatars = _TestAvatarLibrary();
    final fonts = FontLibraryService();
    final presets = ColorPresetLibraryService();
    addTearDown(avatars.dispose);
    addTearDown(fonts.dispose);
    addTearDown(presets.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: AssExportScreen(
          onExport: (_) async {},
          avatarLibrary: avatars,
          fontLibrary: fonts,
          colorPresetLibrary: presets,
          pageState: AssExportPageState(),
        ),
      ),
    );
    await tester.pump();
    return presets;
  }

  Future<void> addColorNamed(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(_nameFields().last, name);
    await tester.pump();
  }

  testWidgets('a color promoted by deleting the default stays renamable', (
    tester,
  ) async {
    final presets = await pumpScreen(tester);
    await addColorNamed(tester, 'A');
    expect(_nameFields(), findsNWidgets(2));

    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(_nameFields(), findsOneWidget);
    expect(tester.widget<TextField>(_nameFields()).controller!.text, 'A');

    await tester.enterText(_nameFields(), 'B');
    await tester.pump();
    expect(presets.activePresets.map((preset) => preset.name), ['B']);
  });

  testWidgets('the default color and a color can both be renamed', (
    tester,
  ) async {
    final presets = await pumpScreen(tester);
    await addColorNamed(tester, 'A');

    await tester.enterText(_nameFields().first, 'Main');
    await tester.pump();
    await tester.enterText(_nameFields().last, 'Duet');
    await tester.pump();
    expect(presets.activePresets.map((preset) => preset.name), [
      'Main',
      'Duet',
    ]);

    // Clearing the default name falls back to the label, not a marker.
    await tester.enterText(_nameFields().first, '');
    await tester.pump();
    expect(presets.activePresets.map((preset) => preset.name), ['Duet']);
  });
}
