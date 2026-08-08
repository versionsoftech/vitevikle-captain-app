import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class AlertService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _isPlaying = false;
  static Future<void>? _loopFuture;

  static Future<void> startAlert() async {
    if (_isPlaying) return;
    _isPlaying = true;

    _loopFuture = () async {
      while (_isPlaying) {
        try {
          await _player.stop();
        } catch (_) {}

        try {
          await _player.play(AssetSource('sounds/beep.mp3'));
        } catch (_) {}

        try {
          // vibration removed
        } catch (_) {}

        await Future.delayed(const Duration(seconds: 2));
      }
    }();

    await _loopFuture;
  }

  static Future<void> stopAlert() async {
    _isPlaying = false;
    try {
      await _player.stop();
    } catch (_) {}
  }
}
