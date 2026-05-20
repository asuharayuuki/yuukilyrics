import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class MediaPlayerService extends ChangeNotifier {
  final Player _player = Player();
  
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _pitch = 1.0;
  double _rate = 1.0;

  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get pitch => _pitch;
  double get rate => _rate;
  Player get player => _player;

  MediaPlayerService() {
    _player.stream.playing.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });

    _player.stream.position.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _player.stream.duration.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
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
    await _player.seek(position);
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
    _player.dispose();
    super.dispose();
  }
}
