# YuukiLyrics

YuukiLyrics is a cross-platform karaoke lyric editor for creating timed lyrics, previewing them with media, and exporting polished subtitles or videos. It is designed for creators who want RhythmicaLyrics-style timing work, rich Japanese lyric notation, and flexible ASS subtitle output in one focused desktop/mobile tool.

## What It Does

YuukiLyrics helps you prepare karaoke-ready lyrics from draft text and media files. You can load audio or video, align lyrics to playback, refine readings and timing, preview the result, and export files that are ready for subtitle rendering or video production.

The app is especially suited for Japanese karaoke workflows, multi-singer lyrics, ruby/furigana notation, styled subtitle exports, and projects that need careful control over how lyrics appear on screen.

## Highlights

- Visual lyric timing with media playback, waveform guidance, and quick timestamp entry.
- A comfortable editor for both structured lyric work and direct LRC text editing.
- Support for extended LRC workflows, including ruby text and RhythmicaLyrics-friendly timing notation.
- Rich ASS subtitle output with karaoke-style progression, color styling, typography controls, and preview support.
- Multi-singer presentation options, including singer-specific colors and small avatar-style lyric accents.
- Flexible font handling for Japanese and English text, including custom fonts and serif-oriented subtitle layouts.
- Video export that can burn the generated subtitles directly into the source media.
- A dark, compact interface built for repeated editing rather than a one-off export wizard.

## Platforms

| Platform | Status | Distribution |
|----------|--------|--------------|
| Windows  | Supported | Manual build |
| Android  | Supported | APK via GitHub Actions |
| iOS      | Supported | Unsigned IPA via GitHub Actions |
| macOS    | Supported | Manual build |
| Linux    | Supported | Manual build |

## Installation

Pre-built binaries for Android and iOS are available through GitHub Actions:

1. Go to the [Actions](https://github.com/asuharayuuki/yuukilyrics/actions) page.
2. Select the latest successful workflow run for your platform.
3. Download the artifact from the Artifacts section at the bottom of the run page.

> Note: The iOS IPA is unsigned. You will need to sign it yourself or use a sideloading tool such as [AltStore](https://altstore.io/) or [SideStore](https://sidestore.io/).

### Prerequisites

- Windows: YuukiLyrics can use a bundled `ffmpeg.exe` when included with the app, or a system FFmpeg installation from `PATH`.
- Linux: [FFmpeg](https://ffmpeg.org/) must be installed and available on your `PATH`.
- Android, iOS, and macOS: FFmpeg support is provided through the bundled mobile/macOS runtime package.

## Building from Source

```bash
git clone https://github.com/asuharayuuki/yuukilyrics.git
cd yuukilyrics
flutter pub get
flutter run
```

Release builds can be created with the usual Flutter targets:

```bash
flutter build windows
flutter build apk --target-platform android-arm64
flutter build ios
flutter build macos
flutter build linux
```

Requires Flutter SDK on the stable channel with Dart SDK 3.11.5 or newer.

## Tech Stack

- [Flutter](https://flutter.dev/) for the cross-platform application.
- [media_kit](https://pub.dev/packages/media_kit) for media playback.
- [FFmpeg](https://ffmpeg.org/) and [ffmpeg_kit_flutter_new](https://pub.dev/packages/ffmpeg_kit_flutter_new) for waveform, subtitle, and video processing.
- [Google Fonts](https://pub.dev/packages/google_fonts) for the application UI typography.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
