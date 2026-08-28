import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class MediaPlayerService extends ChangeNotifier {
  final Player _player = Player();

  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  double _pitch = 1.0;
  double _rate = 1.0;

  // Interpolation for smooth 60fps UI despite slow native updates
  final Stopwatch _interpolationStopwatch = Stopwatch();
  Duration _basePosition = Duration.zero;
  Timer? _ticker;
  int _seekGeneration = 0;
  Duration? _pendingNativeSeekPosition;
  bool _latestSeekCommandCompleted = false;
  bool _holdPositionAfterPause = false;
  Future<void> _openTail = Future<void>.value();

  final List<StreamSubscription> _subscriptions = [];

  bool get isPlaying => _isPlaying;

  Duration get position {
    if (_isPlaying) {
      return _basePosition + (_interpolationStopwatch.elapsed * _rate);
    }
    return _basePosition;
  }

  Duration get duration => _duration;
  double get pitch => _pitch;
  double get rate => _rate;
  Player get player => _player;

  MediaPlayerService() {
    if (_player.platform is NativePlayer) {
      final np = _player.platform as NativePlayer;
      np.setProperty('hr-seek', 'yes');
      np.setProperty('hr-seek-framedrop', 'no');
      np.setProperty('hwdec', 'auto-safe'); // Enable hardware decoding
    }

    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (playing) {
          _holdPositionAfterPause = false;
        }
        if (playing == _isPlaying) return;

        // Preserve the interpolated position before switching to the paused
        // getter, then discard elapsed time before starting a new play period.
        // Otherwise pausing falls back to the last native position update and
        // resuming counts the previous play period's elapsed time again.
        final currentPosition = position;
        _interpolationStopwatch
          ..stop()
          ..reset();
        _isPlaying = playing;
        if (playing) {
          _interpolationStopwatch.start();
          _ticker?.cancel();
          _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
            notifyListeners();
          });
        } else {
          _basePosition = currentPosition;
          _ticker?.cancel();
          notifyListeners();
        }
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen((pos) {
        // media_kit emits playing=false before the native pause command has
        // fully settled, so a trailing position event can otherwise move the
        // paused timeline once more after it has visually stopped.
        if (!_isPlaying && _holdPositionAfterPause) return;

        final pendingSeekPosition = _pendingNativeSeekPosition;
        if (pendingSeekPosition != null) {
          final expectedPosition = _isPlaying ? position : pendingSeekPosition;
          final distanceFromExpected = (pos - expectedPosition).inMilliseconds
              .abs();

          // Native position events do not identify which seek produced them.
          // While dragging, reject events from older queued seeks until the
          // latest command has completed and playback reaches its new target.
          if (!_latestSeekCommandCompleted || distanceFromExpected > 250) {
            return;
          }
          _pendingNativeSeekPosition = null;
        }

        // Sync the base position and reset the stopwatch
        _basePosition = pos;
        if (_isPlaying) {
          _interpolationStopwatch.reset();
          _interpolationStopwatch.start();
        }
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        _duration = dur;
        notifyListeners();
      }),
    );
  }

  Future<void> openMedia(String filePath) async {
    final previousOpen = _openTail;
    final currentOpen = () async {
      try {
        await previousOpen;
      } catch (_) {
        // A failed open must not prevent the next selected file from loading.
      }

      _seekGeneration++;
      _pendingNativeSeekPosition = null;
      _latestSeekCommandCompleted = false;
      _holdPositionAfterPause = false;
      String uriPath = filePath;
      if (!filePath.startsWith('http') && !filePath.startsWith('file://')) {
        uriPath = Uri.file(filePath).toString();
      }
      await _player.open(Media(uriPath), play: false);
    }();
    _openTail = currentOpen;
    await currentOpen;
  }

  Future<void> play() async {
    await _player.play();
  }

  Future<void> pause() async {
    _holdPositionAfterPause = true;
    try {
      await _player.pause();
    } catch (_) {
      _holdPositionAfterPause = false;
      rethrow;
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    final seekGeneration = ++_seekGeneration;
    _holdPositionAfterPause = false;
    _pendingNativeSeekPosition = position;
    _latestSeekCommandCompleted = false;
    _basePosition = position;
    _interpolationStopwatch.reset();
    notifyListeners();

    try {
      await _player.seek(position);
    } catch (_) {
      if (seekGeneration == _seekGeneration) {
        _pendingNativeSeekPosition = null;
        _latestSeekCommandCompleted = false;
      }
      rethrow;
    }

    // Dragging can enqueue many seeks. An older completion must not overwrite
    // the final drag position, while the latest completion reasserts the exact
    // target before playback is resumed.
    if (seekGeneration != _seekGeneration) return;
    _latestSeekCommandCompleted = true;
    _basePosition = position;
    _interpolationStopwatch.reset();
    notifyListeners();
  }

  Future<void> setRate(double rate) async {
    await _player.setRate(rate);
    final currentPosition = position;
    _basePosition = currentPosition;
    _interpolationStopwatch.reset();
    if (_isPlaying) _interpolationStopwatch.start();
    _rate = rate;
    notifyListeners();
  }

  Future<void> setPitch(double pitch) async {
    await _player.setPitch(pitch);
    _pitch = pitch;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
