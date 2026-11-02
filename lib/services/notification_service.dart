import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/services/alert_service.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/offer_inbox.dart';
import 'package:vite_captain/services/session_service.dart';

typedef NotificationTapHandler = void Function(Map<String, dynamic> data);

const _iosNotifications = DarwinInitializationSettings(
  requestAlertPermission: true,
  requestBadgePermission: true,
  requestSoundPermission: true,
);

const String rideRequestChannelId = 'vitevikle_ride_requests_compact';
const String rideRequestChannelName = 'Ride requests';
const String rideOfferAccept = 'accept_ride';
const String rideOfferIgnore = 'ignore_ride';
const int rideOfferNotificationId = 2403;
String _lastOfferKey = '';

String _field(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = (data[key] ?? '').toString().trim();
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

String rideMessageBody(Map<String, dynamic> data, String fallback) {
  final pickup = _field(data, const ['pickup_location', 'pickup', 'pickup_address']);
  final drop = _field(data, const ['drop_location', 'drop', 'drop_address']);
  final fare = _field(data, const ['fare', 'amount']);
  final distance = _field(data, const ['distance']);
  final lines = <String>[
    if (pickup.isNotEmpty) 'Pickup: $pickup',
    if (drop.isNotEmpty) 'Drop: $drop',
    if (fare.isNotEmpty) 'Fare: ₹$fare',
    if (distance.isNotEmpty) distance,
  ];
  final generic = fallback.trim().isEmpty ||
      fallback.toLowerCase().contains('you have a new ride request') ||
      fallback.toLowerCase().contains('open the app') ||
      fallback.toLowerCase().contains('open vite captain');
  if (lines.isNotEmpty && generic) return lines.join('\n');
  if (fallback.trim().isNotEmpty) return fallback.trim();
  if (lines.isNotEmpty) return lines.join('\n');
  return 'A new ride is waiting for you.';
}

bool _isRideRequest(RemoteMessage message) {
  final data = message.data;
  final event = (data['event'] ?? data['type'] ?? data['action'] ?? '')
      .toString()
      .toLowerCase();
  final title = (message.notification?.title ?? data['title'] ?? '').toString().toLowerCase();
  return event.contains('ride_request') ||
      event == 'new_ride' ||
      event == 'ride_requested' ||
      title.contains('ride request') ||
      title.contains('new ride');
}

@pragma('vm:entry-point')
void rideOfferBackgroundTap(NotificationResponse response) {
  handleRideOfferResponse(response);
}

Future<void> handleRideOfferResponse(NotificationResponse response) async {
  final action = (response.actionId ?? '').trim();
  if (action != rideOfferAccept && action != rideOfferIgnore) return;
  Map<String, dynamic> data = <String, dynamic>{};
  try {
    final raw = response.payload;
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  final id = (data['id'] ?? '').toString().trim();
  final kind = (data['kind'] ?? 'city').toString().trim();
  final fare = double.tryParse('${data['fare'] ?? 0}') ?? 0;
  if (id.isEmpty) {
    await AlertService.stopAlert();
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final doneKey = 'offer_action_$id';
  if ((prefs.getString(doneKey) ?? '') == action) return;
  await prefs.setString(doneKey, action);
  OfferInbox.ignore(id);
  await AlertService.stopAlert();
  await FlutterLocalNotificationsPlugin().cancel(rideOfferNotificationId);
  _lastOfferKey = '';
  if (action == rideOfferIgnore) {
    if (kind == 'intercity') {
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isNotEmpty) {
        await const ApiService().rejectIntercityRequest(token: token, requestId: id, reason: 'Ignored');
      }
    }
    return;
  }
  if (kind == 'intercity') {
    final token = (await const SessionService().getToken() ?? '').trim();
    if (token.isEmpty) return;
    await const ApiService().sendIntercityBid(token: token, rideId: id, price: fare <= 0 ? 1 : fare);
    return;
  }
  final driverId = (await const SessionService().getDriverId() ?? '').trim();
  if (driverId.isEmpty) return;
  final res = await const ApiService().placeRideBid(
    rideRequestId: id,
    driverId: driverId,
    price: fare <= 0 ? 1 : fare.round(),
  );
  if (res['success'] != true) {
    OfferInbox.release(id);
  }
}

Future<void> showRideOfferNotification({
  required String id,
  required String kind,
  required String title,
  required String body,
  required double fare,
}) async {
  final key = '$kind|$id|${fare.toStringAsFixed(0)}';
  if (id.trim().isEmpty || _lastOfferKey == key) return;
  _lastOfferKey = key;
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    const InitializationSettings(android: androidInit, iOS: _iosNotifications),
    onDidReceiveNotificationResponse: handleRideOfferResponse,
    onDidReceiveBackgroundNotificationResponse: rideOfferBackgroundTap,
  );
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      rideRequestChannelId,
      rideRequestChannelName,
      description: 'New ride requests with accept and ignore',
      importance: Importance.high,
      playSound: false,
    ),
  );
  final shortBody = body.split('\n').first.trim();
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      rideRequestChannelId,
      rideRequestChannelName,
      channelDescription: 'New ride requests with accept and ignore',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
      playSound: false,
      enableVibration: true,
      ticker: 'New ride request',
      styleInformation: BigTextStyleInformation(shortBody.isEmpty ? 'New ride' : shortBody),
      autoCancel: false,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          rideOfferIgnore,
          'Ignore',
          cancelNotification: true,
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          rideOfferAccept,
          'Accept',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    ),
  );
  await plugin.show(
    rideOfferNotificationId,
    title,
    body,
    details,
    payload: jsonEncode(<String, dynamic>{
      'id': id,
      'kind': kind,
      'fare': fare,
    }),
  );
}

Future<void> cancelRideOfferNotification() async {
  _lastOfferKey = '';
  await FlutterLocalNotificationsPlugin().cancel(rideOfferNotificationId);
}

const String captainInboxKey = 'captain_push_inbox';

Future<void> rememberCaptainNotification({
  required String title,
  required String body,
  String event = '',
}) async {
  final cleanTitle = title.trim();
  final cleanBody = body.trim();
  if (cleanTitle.isEmpty && cleanBody.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  final current = await loadCaptainNotifications();
  current.insert(0, <String, dynamic>{
    'title': cleanTitle.isEmpty ? 'Notification' : cleanTitle,
    'body': cleanBody,
    'event': event,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'kind': 'push',
  });
  final kept = current.length > 40 ? current.sublist(0, 40) : current;
  await prefs.setString(captainInboxKey, jsonEncode(kept));
}

Future<List<Map<String, dynamic>>> loadCaptainNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  try {
    final decoded = jsonDecode(prefs.getString(captainInboxKey) ?? '[]');
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

Future<void> showRideRequestNotification({
  required String title,
  required String body,
  Map<String, dynamic>? data,
}) async {
  final payload = data ?? <String, dynamic>{};
  final id = _field(payload, const ['ride_id', 'rideId', 'id', '_id', 'request_id', 'requestId']);
  final kindRaw = _field(payload, const ['ride_type', 'rideType', 'kind', 'type']).toLowerCase();
  final fare = double.tryParse(_field(payload, const ['fare', 'amount', 'price', 'bid_price'])) ?? 0;
  await showRideOfferNotification(
    id: id.isEmpty ? 'push' : id,
    kind: kindRaw.contains('inter') ? 'intercity' : 'city',
    title: title,
    body: body,
    fare: fare,
  );
}

Future<void> showAppNotification({
  required String title,
  required String body,
  Map<String, dynamic>? data,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit, iOS: _iosNotifications));
  final androidPlugin =
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  const channelId = 'vitevikle_channel';
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      channelId,
      'ViteVikle Notifications',
      description: 'Ride and app notifications',
      importance: Importance.max,
    ),
  );
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      'ViteVikle Notifications',
      channelDescription: 'Ride and app notifications',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );
  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    details,
    payload: data == null ? null : jsonEncode(data),
  );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  final data = Map<String, dynamic>.from(message.data);
  if (_isRideRequest(message)) {
    final title = (message.notification?.title ?? data['title'] ?? '').toString().trim();
    final body = (message.notification?.body ?? data['body'] ?? '').toString().trim();
    await showRideRequestNotification(
      title: title.isEmpty ? 'New ride request' : title,
      body: rideMessageBody(data, body),
      data: data,
    );
    return;
  }
  final title = (message.notification?.title ?? data['title'] ?? '').toString().trim();
  final body = (message.notification?.body ?? data['body'] ?? '').toString().trim();
  if (title.isEmpty && body.isEmpty) return;
  await showAppNotification(
    title: title.isEmpty ? 'Vite Captain' : title,
    body: body,
    data: data,
  );
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
    const initSettings = InitializationSettings(android: android, iOS: _iosNotifications);
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final action = (response.actionId ?? '').trim();
        if (action == rideOfferAccept || action == rideOfferIgnore) {
          handleRideOfferResponse(response);
          return;
        }
        final raw = response.payload;
        if (raw == null || raw.trim().isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            onNotificationTap?.call(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      },
      onDidReceiveBackgroundNotificationResponse: rideOfferBackgroundTap,
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

        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
          final title = message.notification?.title;
          final body = message.notification?.body;
          final data = message.data;
          final event = _t(data['event']).toLowerCase();
          final t = _t(title);
          final b = _t(body);

          if (event == 'ride_requested' ||
              event.contains('ride_request') ||
              event == 'new_ride') {
            final rideTitle = t.isNotEmpty ? t : _t(data['title']).isNotEmpty ? _t(data['title']) : 'New ride request';
            final rideBody = rideMessageBody(Map<String, dynamic>.from(data), b.isNotEmpty ? b : _t(data['body']));
            AlertService.startAlert();
            await rememberCaptainNotification(title: rideTitle, body: rideBody, event: event);
            showRideRequestNotification(
              title: rideTitle,
              body: rideBody,
              data: data,
            );
            return;
          }

          final shownTitle = t.isNotEmpty ? t : _t(data['title']);
          final shownBody = b.isNotEmpty ? b : _t(data['body']);
          if (shownTitle.isNotEmpty || shownBody.isNotEmpty) {
            await rememberCaptainNotification(title: shownTitle.isEmpty ? 'Notification' : shownTitle, body: shownBody, event: event);
            _showLocal(
              title: shownTitle.isNotEmpty ? shownTitle : 'Notification',
              body: shownBody,
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
