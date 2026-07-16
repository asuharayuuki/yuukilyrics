import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CancelledException implements Exception {
  @override
  String toString() => 'Export cancelled by user';
}

class FfmpegService {
  bool get isWindows => Platform.isWindows;
  bool get isMobile => Platform.isAndroid || Platform.isIOS;
  Process? _activeProcess;
  Completer<void>? _mobileCompleter;

  Future<String> get windowsFfmpegPath async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final ffmpegExe = p.join(exeDir, 'data', 'flutter_assets', 'windows_assets', 'ffmpeg.exe');
    
    if (await File(ffmpegExe).exists()) {
      return ffmpegExe;
    }

    // Fallback to system PATH
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        return 'ffmpeg';
      }
    } catch (e) {
      // Ignored
    }

    throw Exception('FFmpeg が見つかりません！ ffmpeg.exe をシステム環境変数 PATH に追加するか、アプリに同梱してください。');
  }

  Future<int> getVideoDurationSec(String videoPath) async {
    if (isWindows) {
      final ffmpeg = await windowsFfmpegPath;
      
      final result = await Process.run(ffmpeg, ['-i', videoPath]);
      // ffprobe is better, but we only have ffmpeg.exe bundled for now.
      // FFmpeg prints info to stderr.
      final output = result.stderr.toString();
      final regex = RegExp(r"Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})");
      final match = regex.firstMatch(output);
      if (match != null) {
        int h = int.parse(match.group(1)!);
        int m = int.parse(match.group(2)!);
        int s = int.parse(match.group(3)!);
        return h * 3600 + m * 60 + s;
      }
      return 1;
    } else {
      final session = await FFprobeKit.getMediaInformation(videoPath);
      final mediaInfo = session.getMediaInformation();
      if (mediaInfo != null) {
        return double.parse(mediaInfo.getDuration() ?? "1").toInt();
      }
      return 1;
    }
  }

  Future<bool> checkHardwareAcceleration(String encoder) async {
    // 1-frame micro-test
    final args = [
      '-f', 'lavfi',
      '-i', 'color=c=black:s=256x256:d=0.1',
      '-pix_fmt', 'yuv420p', // Hardware encoders require specific pixel formats
      '-c:v', encoder,
      '-f', 'null',
      '-'
    ];

    if (isWindows) {
      final ffmpeg = await windowsFfmpegPath;
      final result = await Process.run(ffmpeg, args);
      return result.exitCode == 0;
    } else {
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();
      return returnCode?.isValueSuccess() ?? false;
    }
  }

  /// Detects the best available encoder for the current platform.
  /// Returns the encoder name and whether it's hardware-accelerated.
  Future<({String encoder, bool isHardware})> detectBestEncoder({
    required bool preferHwAccel,
  }) async {
    if (isWindows) {
      if (preferHwAccel) {
        // Windows: try NVIDIA > Intel QSV > AMD AMF > software
        for (final enc in ['h264_nvenc', 'h264_qsv', 'h264_amf']) {
          if (await checkHardwareAcceleration(enc)) {
            return (encoder: enc, isHardware: true);
          }
        }
      }
      return (encoder: 'libx264', isHardware: false);
    }

    if (Platform.isAndroid) {
      if (preferHwAccel) {
        // Android MediaCodec H.264 — universally supported on Android 5.0+
        // Works on Qualcomm (Adreno), MediaTek (Dimensity), Samsung (Exynos), Google (Tensor)
        if (await checkHardwareAcceleration('h264_mediacodec')) {
          return (encoder: 'h264_mediacodec', isHardware: true);
        }
      }
      // FFmpegKit Full+GPL includes libx264
      if (await checkHardwareAcceleration('libx264')) {
        return (encoder: 'libx264', isHardware: false);
      }
      return (encoder: 'mpeg4', isHardware: false);
    }

    if (Platform.isIOS || Platform.isMacOS) {
      if (preferHwAccel) {
        // Apple VideoToolbox — available on all iOS/macOS devices
        if (await checkHardwareAcceleration('h264_videotoolbox')) {
          return (encoder: 'h264_videotoolbox', isHardware: true);
        }
      }
      if (await checkHardwareAcceleration('libx264')) {
        return (encoder: 'libx264', isHardware: false);
      }
      return (encoder: 'mpeg4', isHardware: false);
    }

    // Linux and other desktop platforms
    return (encoder: 'libx264', isHardware: false);
  }

  /// Builds encoder-specific quality arguments.
  /// Hardware encoders use bitrate mode (CBR/VBR); software encoders use CRF.
  List<String> _buildQualityArgs(String encoder) {
    switch (encoder) {
      case 'h264_mediacodec':
        // Android MediaCodec: bitrate mode (CRF not supported)
        // 8Mbps for 1080p karaoke content (text + gradients need high bitrate)
        return ['-b:v', '8M', '-profile:v', 'high', '-level', '4.1'];

      case 'h264_videotoolbox':
        // Apple VideoToolbox: supports bitrate and quality modes
        // ABR at 8Mbps, high profile for quality
        return ['-b:v', '8M', '-profile:v', 'high', '-level:v', '4.1'];

      case 'h264_nvenc':
        // NVIDIA: CQ mode (like CRF) with quality preset
        return ['-cq', '20', '-preset', 'p4', '-profile:v', 'high'];

      case 'h264_qsv':
        // Intel QuickSync: global_quality (like CRF)
        return ['-global_quality', '22', '-preset', 'medium', '-profile:v', 'high'];

      case 'h264_amf':
        // AMD AMF: quality_level + bitrate
        return ['-b:v', '8M', '-quality', 'balanced', '-profile:v', 'high'];

      case 'libx264':
        // Software x264: CRF mode, best quality per bitrate
        return ['-crf', '20', '-preset', 'medium', '-profile:v', 'high', '-level', '4.1'];

      case 'mpeg4':
        // MPEG-4 Part 2 fallback: needs high bitrate to compensate for poor efficiency
        return ['-b:v', '10M', '-q:v', '2'];

      default:
        return ['-b:v', '8M'];
    }
  }

  /// Returns the path to the modified ASS file
  Future<String> modifyAssFont(String assPath, String fontName) async {
    final file = File(assPath);
    String content = await file.readAsString();
    
    // Simplistic modification: replace Fontname in styles with the English font name.
    // Standard ASS Style format: Style: Name,Fontname,Fontsize,...
    final lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('Style:')) {
        final parts = lines[i].split(',');
        if (parts.length > 1) {
          parts[1] = fontName;
          lines[i] = parts.join(',');
        }
      }
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempAss = File(p.join(tempDir.path, 'temp_modified_$timestamp.ass'));
    await tempAss.writeAsString(lines.join('\n'));
    return tempAss.path;
  }

  String _escapeFilterPath(String path) {
    // FFmpeg requires double escaping for filter_complex when not using single quotes:
    // Level 1: filter parser, Level 2: option parser.
    return path.replaceAll(r'\', r'\\\\')
               .replaceAll(':', r'\\:')
               .replaceAll('[', r'\\[')
               .replaceAll(']', r'\\]')
               .replaceAll(' ', r'\\ ')
               .replaceAll(',', r'\\,')
               .replaceAll(';', r'\\;')
               .replaceAll('=', r'\\=')
               .replaceAll("'", r"\\'");
  }

  Future<void> exportVideo({
    required String videoPath,
    required String assPath,
    required String fontName,
    required String fontSandboxDir,
    required String outputPath,
    required bool useHwAccel,
    required bool padVideo,
    required Function(double) onProgress,
    Function(String)? onEncoderDetected,
  }) async {
    final totalDuration = await getVideoDurationSec(videoPath);
    final modifiedAss = await modifyAssFont(assPath, fontName);
    
    // Detect the best available encoder for this device
    final detected = await detectBestEncoder(preferHwAccel: useHwAccel);
    final encoder = detected.encoder;
    debugPrint('Selected encoder: $encoder (hardware: ${detected.isHardware})');
    if (onEncoderDetected != null) {
      onEncoderDetected('$encoder (${detected.isHardware ? "Hardware" : "Software"})');
    }

    String finalAssPath = _escapeFilterPath(modifiedAss);
    String finalFontsDir = _escapeFilterPath(fontSandboxDir);
    String filterGraph = '';
    
    if (padVideo) {
      // Dynamic padding to 16:9, preserving original resolution and ensuring even dimensions
      filterGraph = '[0:v]pad=width=\'ceil(max(iw\\,ih*16/9)/2)*2\':height=\'ceil(max(ih\\,iw*9/16)/2)*2\':x=-1:y=-1[padded];[padded]ass=f=$finalAssPath:fontsdir=$finalFontsDir,format=yuv420p[out]';
    } else {
      filterGraph = '[0:v]ass=f=$finalAssPath:fontsdir=$finalFontsDir,format=yuv420p[out]';
    }

    // Build the full argument list
    final qualityArgs = _buildQualityArgs(encoder);
    final args = [
      '-y',
      '-threads', '0',            // Auto-select optimal thread count
      '-i', videoPath,
      '-filter_complex', filterGraph,
      '-map', '[out]',
      '-map', '0:a?',
      '-c:v', encoder,
      ...qualityArgs,
      '-c:a', 'copy',
      '-movflags', '+faststart',  // Enable streaming-compatible layout
      outputPath
    ];

    try {
      if (isWindows) {
        final ffmpeg = await windowsFfmpegPath;

        _activeProcess = await Process.start(ffmpeg, args, environment: {
          'FONTCONFIG_PATH': fontSandboxDir,
          'GDFONTPATH': fontSandboxDir,
          'FFREPORT': 'level=32', // prevent quiet stderr starvation
        });

        final stderrBuffer = StringBuffer();
        _activeProcess!.stderr.transform(SystemEncoding().decoder).listen((output) {
          debugPrint('FFMPEG LOG: $output');
          stderrBuffer.write(output);
          final regex = RegExp(r"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})");
          final match = regex.firstMatch(output);
          if (match != null) {
            int h = int.parse(match.group(1)!);
            int m = int.parse(match.group(2)!);
            int s = int.parse(match.group(3)!);
            int currentSec = h * 3600 + m * 60 + s;
            double progress = (currentSec / totalDuration);
            onProgress(progress.clamp(0.0, 1.0));
          }
        });

        final exitCode = await _activeProcess!.exitCode;
        _activeProcess = null;
        if (exitCode != 0) {
          throw Exception("FFmpeg encoding failed on Windows (exit code $exitCode).\nLog:\n$stderrBuffer");
        }
      } else {
        // Mobile - execute with environment variables for libass
        FFmpegKitConfig.setEnvironmentVariable('FONTCONFIG_PATH', fontSandboxDir);
        FFmpegKitConfig.setEnvironmentVariable('GDFONTPATH', fontSandboxDir);
        
        // We use FFmpegKit's async execution
        _mobileCompleter = Completer<void>();
        await FFmpegKit.executeWithArgumentsAsync(
          args, 
          (session) async {
            if (_mobileCompleter?.isCompleted == true) return;
            final returnCode = await session.getReturnCode();
            if (returnCode?.isValueSuccess() == true) {
              _mobileCompleter?.complete();
            } else {
              final failLog = await session.getOutput();
              _mobileCompleter?.completeError(Exception("FFmpeg encoding failed (code $returnCode).\nLog:\n$failLog"));
            }
          }, 
          (log) {}, 
          (statistics) {
            double currentSec = statistics.getTime() / 1000.0;
            double progress = (currentSec / totalDuration);
            onProgress(progress.clamp(0.0, 1.0));
          }
        );
        try {
          await _mobileCompleter!.future;
        } finally {
          _mobileCompleter = null;
        }
      }
    } finally {
      // Clean up the temporary modified ASS file
      try {
        await File(modifiedAss).delete();
      } catch (_) {}
    }
  }

  void cancelExport() {
    if (isWindows && _activeProcess != null) {
      _activeProcess!.kill();
    } else if (!isWindows) {
      FFmpegKit.cancel();
      if (_mobileCompleter != null && !_mobileCompleter!.isCompleted) {
        _mobileCompleter!.completeError(CancelledException());
      }
    }
  }

  // ─── Temp File Cleanup ──────────────────────────────────────────

  /// Cleans up orphaned temporary files from previous sessions.
  /// Call this on app startup.
  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      if (!await dir.exists()) return;

      final patterns = [
        RegExp(r'^temp_modified_\d+\.ass$'),
        RegExp(r'^temp_export\.ass$'),
        RegExp(r'^preview_temp\.ass$'),
        RegExp(r'_hardsub\.mp4$'),
      ];

      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          for (final pattern in patterns) {
            if (pattern.hasMatch(name)) {
              try {
                await entity.delete();
                debugPrint('Cleaned up temp file: $name');
              } catch (_) {}
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Temp cleanup error: $e');
    }
  }
}
