import 'dart:io';

import 'package:flutter/services.dart';

/// Small on-screen bubble while a ride is in progress, including after the app is left.
class RideBubble {
  static const MethodChannel _channel = MethodChannel('com.vitecaptain.driver/ride_bubble');

  static Future<void> prepare({
    String title = 'Ride in progress',
    String body = 'Tap to return to the ride',
    String eta = '',
    double? lat,
    double? lng,
    double? targetLat,
    double? targetLng,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('prepare', {
        'title': title,
        'body': body,
        'eta': eta,
        'lat': lat,
        'lng': lng,
        'targetLat': targetLat,
        'targetLng': targetLng,
      });
    } catch (_) {}
  }

  static Future<void> start({
    String title = 'Ride in progress',
    String body = 'Tap to return to the ride',
    String pickup = '',
    String drop = '',
    String eta = '',
    String phone = '',
    double? lat,
    double? lng,
    double? targetLat,
    double? targetLng,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('start', {
        'title': title,
        'body': body,
        'pickup': pickup,
        'drop': drop,
        'eta': eta,
        'phone': phone,
        'lat': lat,
        'lng': lng,
        'targetLat': targetLat,
        'targetLng': targetLng,
      });
    } catch (_) {}
  }

  static Future<void> move({
    String title = 'Ride in progress',
    String body = '',
    double? lat,
    double? lng,
    double? targetLat,
    double? targetLng,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('move', {
        'title': title,
        'body': body,
        'lat': lat,
        'lng': lng,
        'targetLat': targetLat,
        'targetLng': targetLng,
      });
    } catch (_) {}
  }

  static Future<void> clear() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('clear');
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
