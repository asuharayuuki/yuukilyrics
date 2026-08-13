import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'dart:io' show Platform;
import 'screens/main_screen.dart';
import 'services/ffmpeg_service.dart';
import 'l10n/generated/app_localizations.dart';

Locale? debugAppLocaleOverride({bool? debugMode, String? localeName}) {
  if (!(debugMode ?? kDebugMode)) return null;

  final value = localeName ?? const String.fromEnvironment('APP_LOCALE');
  final languageCode = value.trim().toLowerCase().split(RegExp(r'[-_]')).first;
  return switch (languageCode) {
    'ja' => const Locale('ja'),
    'zh' => const Locale('zh'),
    _ => null,
  };
}

Locale resolveAppLocale(Locale? locale, Iterable<Locale> supportedLocales) {
  if (locale != null) {
    for (final supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return supportedLocale;
      }
    }
  }
  return const Locale('ja');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      debugPrint('Failed to set high refresh rate: $e');
    }
  }

  // Clean up orphaned temporary files from previous sessions
  await FfmpegService.cleanupTempFiles();

  runApp(const YuukiLyricsApp());
}

class YuukiLyricsApp extends StatelessWidget {
  const YuukiLyricsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: debugAppLocaleOverride(),
      localeResolutionCallback: resolveAppLocale,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF1E1E2C),
          surfaceContainerHighest: const Color(0xFF2D2D3A),
        ),
        scaffoldBackgroundColor: const Color(0xFF12121A),
        fontFamily: 'KosugiMaru',
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ).apply(fontFamily: 'KosugiMaru'),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
