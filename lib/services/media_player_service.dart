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

    _subscriptions.add(_player.stream.playing.listen((playing) {
      _isPlaying = playing;
      if (playing) {
        _interpolationStopwatch.start();
        _ticker?.cancel();
        _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
          notifyListeners();
        });
      } else {
        _interpolationStopwatch.stop();
        _ticker?.cancel();
        notifyListeners();
      }
    }));

    _subscriptions.add(_player.stream.position.listen((pos) {
      // Sync the base position and reset the stopwatch
      _basePosition = pos;
      if (_isPlaying) {
        _interpolationStopwatch.reset();
        _interpolationStopwatch.start();
      }
      notifyListeners();
    }));

    _subscriptions.add(_player.stream.duration.listen((dur) {
      _duration = dur;
      notifyListeners();
    }));
  }

  Future<void> openMedia(String filePath) async {
    String uriPath = filePath;
    if (!filePath.startsWith('http') && !filePath.startsWith('file://')) {
      uriPath = Uri.file(filePath).toString();
    }
    await _player.open(Media(uriPath), play: false);
  }

  Future<void> play() async {
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }
  
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
      _basePosition = position;
      _interpolationStopwatch.reset();
      await _player.seek(position);
      notifyListeners();
  }

  Future<void> setRate(double rate) async {
    _rate = rate;
    await _player.setRate(rate);
    notifyListeners();
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
    await _player.setPitch(pitch);
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

