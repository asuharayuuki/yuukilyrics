# YuukiLyrics

YuukiLyrics is a cross-platform karaoke lyric editor built with Flutter, designed for high-precision timing synchronization. It provides advanced authoring capabilities for extended LRC formats with native RhythmicaLyrics compatibility, and can export richly styled ASS subtitle files with dynamic karaoke sweep animations.

## Features

### Lyric Editing

- **Dual editing modes** — switch between a structured visual editor (CharCell grid with per-character timing dots) and a raw LRC text editor with syntax highlighting.
- **AST-based document model** — lyrics are parsed into a structured tree (`LyricDocument` → `LyricLine` → `LyricNode`) supporting time tags, plain text, and ruby annotations, enabling precise programmatic manipulation.
- **Ruby (furigana) annotation** — full support for `{base|ruby}` notation. Inline ruby editor in the toolbar lets you add, modify, or remove readings without touching raw syntax.
- **RhythmicaLyrics compatibility** — supports multi-character connection syntax (`＋`), typed time tags (`[type|time]`), proportional timing expansion, and Tag-10 end markers.

### Timing & Tagging

- **Tap-to-tag workflow** — stamp timestamps at the current playback position with a single tap; the cursor auto-advances to the next tagging slot.
- **Configurable timing offset** — default −230 ms offset to compensate for human reaction latency (matching RhythmicaLyrics' `タイムタグ打ち込み時にずらす時間 = -23 × 10ms`).
- **Audio waveform timeline** — zoomable and pannable waveform visualization extracted via FFmpeg, with a center-line playback indicator for frame-accurate scrubbing.

### ASS Subtitle Export

- **Karaoke sweep animations** — generates `\kf` / `\k` tags with per-character timing for smooth fill-sweep effects.
- **Highly customizable output** — configure font name/size, primary & outline colors, outline width, per-singer color mapping (with prefix-based detection), and paging mode (auto 2-line or empty-line delimited).
- **Custom font embedding** — load any `.ttf` file; the font's internal English family name is automatically extracted from the `name` table and used in ASS styles. Fonts are sandboxed for clean FFmpeg subtitle rendering.
- **Interlude handling** — configurable interlude detection threshold and visual gap multiplier for natural spacing between lyric blocks.
- **Live ASS preview** — preview the generated subtitle overlaid on the source media in a full-screen player with libass rendering, double-tap seeking, and long-press 2× fast-forward.

### Video Export

- **Hardcoded subtitle rendering** — burn ASS subtitles directly into the video via FFmpeg with `ass` filter and custom `fontsdir`.
- **Hardware acceleration** — auto-detects and uses platform-specific hardware encoders (`h264_nvenc`, `h264_qsv`, `h264_amf` on Windows; `h264_videotoolbox`, `h264_mediacodec` on Apple/Android) with transparent fallback to `libx264`.
- **Aspect ratio padding** — optional automatic padding to 16:9 while preserving the original resolution.
- **Real-time progress** — FFmpeg stderr is parsed for `time=` to drive a progress indicator.

### Media Playback

- **Broad format support** — mp3, mp4, wav, flac, mkv, avi, aac, opus, webm, ogg and more, powered by media_kit (libmpv).
- **High refresh rate** — automatically enables high refresh rate display mode on Android.

## Platforms

| Platform | Status | Distribution |
|----------|--------|--------------|
| Windows  | ✅      | Manual build |
| Android  | ✅      | APK via GitHub Actions |
| iOS      | ✅      | Unsigned IPA via GitHub Actions |
| macOS    | ✅      | Manual build |
| Linux    | ✅      | Manual build |

## Installation

Pre-built binaries for **Android** (APK) and **iOS** (unsigned IPA) are available through GitHub Actions:

1. Go to the [Actions](https://github.com/asuharayuuki/yuukilyrics/actions) page.
2. Select the latest successful workflow run for your platform.
3. Download the artifact from the **Artifacts** section at the bottom of the run page.

> [!NOTE]
> The iOS IPA is **unsigned**. You will need to sign it yourself or use a sideloading tool such as [AltStore](https://altstore.io/) or [SideStore](https://sidestore.io/).

### Prerequisites

- **Windows / Linux**: [FFmpeg](https://ffmpeg.org/) must be installed and available on your `PATH` for waveform extraction and video export.
- **Android / iOS / macOS**: FFmpeg is bundled via `ffmpeg_kit_flutter_new`; no additional installation is required.

## Building from Source

```bash
# Clone the repository
git clone https://github.com/asuharayuuki/yuukilyrics.git
cd yuukilyrics

# Install dependencies
flutter pub get

# Run in debug mode
flutter run

# Build a release binary
flutter build windows   # or: apk, ios, macos, linux
```

Requires Flutter SDK (stable channel) with Dart SDK ≥ 3.11.5.

## Project Structure

```
lib/
├── main.dart                        # App entry point & theme
├── models/
│   └── lyric_ast.dart               # AST nodes: LyricDocument, LyricLine, LyricTimeTag, LyricText, LyricRuby
├── parser/
│   └── lrc_parser.dart              # Extended LRC parser with ruby expansion
├── screens/
│   ├── main_screen.dart             # Primary editor screen with media loading, file I/O, navigation
│   ├── ass_export_screen.dart       # ASS export settings UI (font, colors, paging, interlude)
│   └── ass_preview_screen.dart      # Full-screen ASS subtitle preview player
├── services/
│   ├── lyrics_state_service.dart    # Document state, tagging cursor, undo, slot management
│   ├── ass_exporter.dart            # ASS file generation with karaoke timing & sweep animations
│   ├── media_player_service.dart    # media_kit player wrapper
│   ├── ffmpeg_service.dart          # FFmpeg operations (video export, HW accel, duration)
│   ├── font_service.dart            # TTF name-table extraction & font sandboxing
│   └── waveform_extractor*.dart     # Platform-specific audio waveform extraction
└── widgets/
    ├── lyrics_editor.dart           # CharCell-based visual editor & raw text editor
    ├── toolbar_area.dart            # Playback controls, ruby editor, timing tools
    ├── tagging_button.dart          # Tap-to-tag timestamp button
    ├── timeline_waveform.dart       # Zoomable waveform timeline with playback cursor
    └── lrc_syntax_controller.dart   # LRC syntax highlighting for the text editor
```

## Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (Material 3, dark theme)
- **Media**: [media_kit](https://pub.dev/packages/media_kit) (libmpv)
- **FFmpeg**: [ffmpeg_kit_flutter_new](https://pub.dev/packages/ffmpeg_kit_flutter_new) (mobile) / bundled binary (Windows)
- **Typography**: [Google Fonts](https://pub.dev/packages/google_fonts) (Inter)

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).