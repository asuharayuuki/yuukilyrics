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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A typical phone: 390x844 logical pixels with a 336px software keyboard.
  const phoneSize = Size(390, 844);
  const keyboardHeight = 336.0;

  Future<void> openSourceDialog(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phoneSize;
    addTearDown(tester.view.reset);

    final avatars = _TestAvatarLibrary();
    final fonts = FontLibraryService();
    final presets = ColorPresetLibraryService();
    addTearDown(avatars.dispose);
    addTearDown(fonts.dispose);
    addTearDown(presets.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
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

    final sourceButton = find.text('ソース');
    await tester.ensureVisible(sourceButton);
    await tester.pumpAndSettle();
    await tester.tap(sourceButton);
    await tester.pumpAndSettle();
  }

  Finder sourceField() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  testWidgets('source field keeps most of the space above the keyboard', (
    tester,
  ) async {
    await openSourceDialog(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
    await tester.pumpAndSettle();

    final visibleHeight = phoneSize.height - keyboardHeight;
    final fieldHeight = tester.getSize(sourceField()).height;
    expect(tester.takeException(), isNull);
    expect(fieldHeight, greaterThan(visibleHeight * 0.55));
    // Copy/paste stay reachable as compact icon buttons.
    expect(find.byTooltip('コピー'), findsOneWidget);
    expect(find.byTooltip('貼り付け'), findsOneWidget);
  });

  testWidgets('dialog keeps its toolbar and normal size without keyboard', (
    tester,
  ) async {
    await openSourceDialog(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('コピー'), findsOneWidget);
    expect(tester.getSize(sourceField()).height, greaterThan(300));
  });
}
