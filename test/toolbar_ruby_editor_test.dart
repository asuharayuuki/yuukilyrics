import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:yuukilyrics/l10n/generated/app_localizations.dart';
import 'package:yuukilyrics/services/color_preset_library_service.dart';
import 'package:yuukilyrics/services/lyrics_state_service.dart';
import 'package:yuukilyrics/services/media_player_service.dart';
import 'package:yuukilyrics/widgets/toolbar_area.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ruby edits are applied while an IME composition is active', (
    tester,
  ) async {
    final lyricsState = LyricsStateService()..loadLrcText('{漢|かん}');
    final mediaPlayer = _FakeMediaPlayer();
    final colorPresets = ColorPresetLibraryService();
    addTearDown(lyricsState.dispose);
    addTearDown(mediaPlayer.dispose);
    addTearDown(colorPresets.dispose);
    lyricsState.setSelection(0, 0);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ToolbarArea(
            mediaPlayer: mediaPlayer,
            lyricsState: lyricsState,
            colorPresetLibrary: colorPresets,
            pageState: ToolbarAreaPageState(),
          ),
        ),
      ),
    );

    final rubyField = find.byType(TextField);
    expect(rubyField, findsOneWidget);
    await tester.tap(rubyField);
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ふり',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();

    expect(lyricsState.rawText, '{漢|ふり}');
    expect(
      tester.widget<TextField>(rubyField).controller!.value.composing,
      const TextRange(start: 0, end: 2),
    );

    // Many IMEs finish by clearing only the composing range. EditableText does
    // not call onChanged again because the text is unchanged at this point.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ふり',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    expect(lyricsState.rawText, '{漢|ふり}');
  });
}

class _FakeMediaPlayer extends ChangeNotifier implements MediaPlayerService {
  @override
  bool get isPlaying => false;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  double get pitch => 1;

  @override
  double get rate => 1;

  @override
  Player get player => throw UnsupportedError('Not used by ToolbarArea');

  @override
  Future<void> openMedia(String filePath) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> togglePlayPause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}
}
