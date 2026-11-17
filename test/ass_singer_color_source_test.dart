import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/l10n/generated/app_localizations.dart';
import 'package:yuukilyrics/parser/lrc_parser.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/ass_exporter.dart';
import 'package:yuukilyrics/services/color_preset_library_service.dart';
import 'package:yuukilyrics/services/font_library_service.dart';
import 'package:yuukilyrics/services/singer_avatar_library_service.dart';

class _TestAvatarLibrary extends SingerAvatarLibraryService {
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'current color source applies default edits and reflects first-row promotion',
    (tester) async {
      final avatars = _TestAvatarLibrary();
      final fonts = FontLibraryService();
      final presets = ColorPresetLibraryService();
      AssExportSettings? exportedSettings;
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
            onExport: (settings) async {
              exportedSettings = settings;
            },
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

      const firstPalette =
          '#111111 | #222222 | #333333 | #444444 | #555555 | #666666';
      const secondPalette =
          '#777777 | #888888 | #999999 | #AAAAAA | #BBBBBB | #CCCCCC';
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(
        dialogField,
        '$reappliedSource\n| Alice/Carol | $firstPalette |'
        '\n| Singer B | $secondPalette |',
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();

      final delete = find.byTooltip('删除');
      expect(delete, findsNWidgets(3));
      await tester.tap(delete.first);
      await tester.pumpAndSettle();
      expect(delete, findsNWidgets(2));
      expect(find.text('Alice/Carol'), findsOneWidget);
      expect(find.text('默认配色'), findsNothing);
      expect(find.text('Singer B'), findsOneWidget);
      expect(presets.activePresets.map((preset) => preset.name), [
        'Alice/Carol',
        'Singer B',
      ]);

      await tester.tap(find.text('源代码'));
      await tester.pumpAndSettle();
      final promotedSource = tester
          .widget<TextField>(dialogField)
          .controller!
          .text;
      expect(promotedSource, contains('| Alice/Carol | $firstPalette |'));
      expect(promotedSource, contains('| Singer B | $secondPalette |'));
      expect(promotedSource, isNot(contains('#123456')));
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('导出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 ASS 字幕'));
      await tester.pumpAndSettle();
      final settings = exportedSettings!;
      expect(settings.showSingerPrefixesInAss, isFalse);
      expect(settings.singerColors.map((singer) => singer.prefix), [
        'Alice/Carol',
        'Singer B',
      ]);
      await tester.runAsync(() async {
        final ass = await AssExporter.generateAss(
          LrcParser.parseDocument(
            'Singer B[00:05:00]歌[00:06:00]\n'
            'Alice/Carol[00:07:00]音[00:08:00]',
          ),
          settings,
        );
        final dialogue = ass
            .split('\n')
            .where((line) => line.startsWith('Dialogue:'));
        expect(dialogue.where((line) => line.endsWith('/')), isEmpty);
        expect(
          dialogue.where((line) => line.endsWith('音')),
          contains(contains('&H00111111&')),
        );
      });

      await tester.tap(delete.first);
      await tester.pumpAndSettle();
      expect(delete, findsNothing);
      expect(find.text('Singer B'), findsOneWidget);
      expect(find.text('默认配色'), findsNothing);
      expect(presets.activePresets.map((preset) => preset.name), ['Singer B']);
    },
  );
}
