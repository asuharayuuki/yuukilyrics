import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'dart:io' show Platform;
import 'screens/main_screen.dart';
import 'services/ffmpeg_service.dart';

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
      title: 'yuukilyrics',
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
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(fontFamily: 'KosugiMaru'),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
