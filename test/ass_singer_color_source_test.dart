import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/l10n/generated/app_localizations.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/color_preset_library_service.dart';
import 'package:yuukilyrics/services/font_library_service.dart';
import 'package:yuukilyrics/services/singer_avatar_library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'current singer color source includes and applies default colors',
    (tester) async {
      final avatars = SingerAvatarLibraryService();
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

      await tester.tap(find.text('源代码'));
      await tester.pumpAndSettle();

      var sourceField = tester.widget<TextField>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
      );
      final initialSource = sourceField.controller!.text;
      expect(
        RegExp(r'^\| 默认配色 \|', multiLine: true).allMatches(initialSource),
        hasLength(1),
      );
      expect(initialSource, contains('#0000AF'));

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        initialSource.replaceFirst('#0000AF', '#123456'),
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('源代码'));
      await tester.pumpAndSettle();
      sourceField = tester.widget<TextField>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
      );
      final reappliedSource = sourceField.controller!.text;
      expect(
        RegExp(r'^\| 默认配色 \|', multiLine: true).allMatches(reappliedSource),
        hasLength(1),
      );
      expect(reappliedSource, contains('#123456'));
    },
  );
}
