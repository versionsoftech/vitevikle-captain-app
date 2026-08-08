import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vite_captain/services/api_service.dart';

typedef NotificationTapHandler = void Function(Map<String, dynamic> data);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep lightweight — OS shows the notification tray when payload has notification.
  debugPrint('DRIVER BACKGROUND MESSAGE: ${message.notification?.title} ${message.data}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;
  bool _handlersBound = false;
  String _driverId = '';

  NotificationTapHandler? onNotificationTap;

  static const String androidChannelId = 'vitevikle_channel';
  static const String androidChannelName = 'ViteVikle Notifications';

  Future<void> _initLocalNotifications() async {
    if (_localReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.trim().isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            onNotificationTap?.call(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      },
    );

    final androidPlugin =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description: 'Ride and app notifications',
        importance: Importance.max,
      ),
    );
    _localReady = true;
  }

  String _t(dynamic v) => (v ?? '').toString().trim();

  Future<void> _showLocal({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await _initLocalNotifications();
    const androidDetails = AndroidNotificationDetails(
      androidChannelId,
      androidChannelName,
      channelDescription: 'Ride and app notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: data == null ? null : jsonEncode(data),
    );
  }

  Future<void> init({required String driverId}) async {
    try {
      _driverId = driverId.trim();
      if (_driverId.isEmpty) return;

      await _initLocalNotifications();

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('FCM permission status: ${settings.authorizationStatus}');

      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) {
        debugPrint('DRIVER FCM TOKEN: <empty>');
        return;
      }
      debugPrint('DRIVER FCM TOKEN: $token');
      await _saveTokenToBackend(driverId: _driverId, token: token.trim());

      if (!_handlersBound) {
        _handlersBound = true;

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final title = message.notification?.title;
          final body = message.notification?.body;
          final data = message.data;
          final event = _t(data['event']).toLowerCase();
          final t = _t(title);
          final b = _t(body);

          if (event == 'ride_requested') {
            _showLocal(
              title: t.isNotEmpty ? t : 'New Ride Request',
              body: b.isNotEmpty ? b : 'You have a new ride request.',
              data: data,
            );
            return;
          }

          if (t.isNotEmpty || b.isNotEmpty) {
            _showLocal(
              title: t.isNotEmpty ? t : 'Notification',
              body: b,
              data: data,
            );
          }
        });

        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          onNotificationTap?.call(Map<String, dynamic>.from(message.data));
        });

        _messaging.onTokenRefresh.listen((String refreshed) async {
          final id = _driverId.trim();
          if (id.isEmpty) return;
          await _saveTokenToBackend(driverId: id, token: refreshed.trim());
        });
      }

      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        onNotificationTap?.call(Map<String, dynamic>.from(initial.data));
      }
    } catch (e) {
      debugPrint('NotificationService.init error: $e');
    }
  }

  Future<void> _saveTokenToBackend({required String driverId, required String token}) async {
    final id = driverId.trim();
    if (id.isEmpty) return;

    final url = '$baseUrl/notification/save-token';

    try {
      final resp = await Dio().post(
        url,
        data: jsonEncode({
          'userId': id,
          'role': 'driver',
          'token': token,
        }),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );
      debugPrint('DRIVER TOKEN SAVE RESP: ${resp.statusCode} ${resp.data}');
    } catch (e) {
      debugPrint('DRIVER TOKEN SAVE ERROR: $e');
    }
  }
}
