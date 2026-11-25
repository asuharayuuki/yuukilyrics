import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/l10n/generated/app_localizations.dart';
import 'package:yuukilyrics/screens/ass_export_screen.dart';
import 'package:yuukilyrics/services/color_preset_library_service.dart';
import 'package:yuukilyrics/services/font_library_service.dart';
import 'package:yuukilyrics/services/singer_avatar_library_service.dart';
import 'package:yuukilyrics/widgets/saved_color_presets_dialog.dart';

void main() {
  testWidgets('default color editor copies exactly one Markdown row', (
    tester,
  ) async {
    final fonts = _NoopFontLibrary();
    final avatars = SingerAvatarLibraryService();
    final colors = ColorPresetLibraryService();
    addTearDown(fonts.dispose);
    addTearDown(avatars.dispose);
    addTearDown(colors.dispose);
    String? clipboard;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AssExportScreen(
          onExport: (_) async {},
          avatarLibrary: avatars,
          fontLibrary: fonts,
          colorPresetLibrary: colors,
          pageState: AssExportPageState(),
        ),
      ),
    );
    // The default row's name is an editable field; its colors open from the
    // preview, as for every other row.
    await tester.tap(find.byTooltip('配色を編集').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('配色コードをコピー'));
    await tester.pump();

    expect(
      clipboard,
      '| デフォルト配色 | #0000AF | #FFFFFF | #FFE196 | #FFFFFF | #000000 | #96BFFF |',
    );
  });

  testWidgets('import actions use compact buttons', (tester) async {
    final library = ColorPresetLibraryService();
    addTearDown(library.dispose);
    var textImportCount = 0;
    var n3ImportCount = 0;

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
        home: SavedColorPresetsScreen(
          library: library,
          onAdd: (_) async {},
          onEdit: (_) async {},
          onRename: (_, _) async => true,
          onDelete: (_) async {},
          onImport: () async => textImportCount++,
          onImportN3: () async => n3ImportCount++,
        ),
      ),
    );

    final textImport = find.byKey(const ValueKey('import-color-presets'));
    final n3Import = find.byKey(const ValueKey('import-n3-project'));
    expect(tester.getSize(textImport).height, lessThanOrEqualTo(48));
    expect(tester.getSize(n3Import).height, lessThanOrEqualTo(48));
    expect(tester.getSize(textImport).width, lessThan(220));
    expect(tester.getSize(n3Import).width, lessThan(220));

    final importCard = tester.widget<Card>(
      find.ancestor(of: textImport, matching: find.byType(Card)),
    );
    final context = tester.element(textImport);
    expect(importCard.elevation, 0);
    expect(importCard.color, Theme.of(context).colorScheme.surfaceContainerLow);
    expect(
      (importCard.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(24),
    );

    await tester.tap(textImport);
    await tester.tap(n3Import);
    expect(textImportCount, 1);
    expect(n3ImportCount, 1);
  });
}

class _NoopFontLibrary extends FontLibraryService {
  @override
  Future<void> refresh() async {}
}
