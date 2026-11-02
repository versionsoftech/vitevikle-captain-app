import 'package:flutter/services.dart';

class AlertService {
  static bool _isPlaying = false;
  static const MethodChannel _channel = MethodChannel('com.vitecaptain.driver/ride_bubble');

  static Future<void> _boost() async {
    try {
      await _channel.invokeMethod('boostAlert');
    } catch (_) {}
  }

  static Future<void> _restore() async {
    try {
      await _channel.invokeMethod('restoreAlert');
    } catch (_) {}
  }

  static Future<void> startAlert() async {
    if (_isPlaying) return;
    _isPlaying = true;
    await _boost();
    try {
      await _channel.invokeMethod('startOrderRing');
    } catch (_) {}
  }

  static Future<void> stopAlert() async {
    _isPlaying = false;
    try {
      await _channel.invokeMethod('stopOrderRing');
    } catch (_) {}
    await _restore();
  }

  static Future<void> startDutyWatch() async {
    try {
      await _channel.invokeMethod('startDuty');
    } catch (_) {}
  }

  static Future<void> stopDutyWatch() async {
    try {
      await _channel.invokeMethod('stopDuty');
    } catch (_) {}
  }
}
