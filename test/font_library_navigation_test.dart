import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/l10n/generated/app_localizations.dart';
import 'package:yuukilyrics/screens/font_library_screen.dart';
import 'package:yuukilyrics/services/font_library_service.dart';

void main() {
  testWidgets('font library is presented as a child page', (tester) async {
    final library = FontLibraryService();
    addTearDown(library.dispose);

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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => FontLibraryScreen(library: library),
                ),
              ),
              child: const Text('open fonts'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open fonts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('字体库'), findsOneWidget);
    expect(find.byType(NavigationDrawer), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('open fonts'), findsOneWidget);
  });
}
