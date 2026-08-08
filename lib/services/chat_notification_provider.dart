import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/chat_notification_api.dart';
import 'package:vite_captain/services/global_payment_popup.dart';

class ChatNotificationProvider extends ChangeNotifier {
  final ChatNotificationApi _api = const ChatNotificationApi();
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  io.Socket? _socket;
  String _receiverId = '';
  String _receiverRole = '';
  bool _initialized = false;

  int unreadCount = 0;

  bool get isReady => _receiverId.isNotEmpty && _receiverRole.isNotEmpty;

  Future<void> init({required String receiverId, required String receiverRole}) async {
    final nextId = receiverId.trim();
    final nextRole = receiverRole.trim().toLowerCase();
    if (_initialized && nextId == _receiverId && nextRole == _receiverRole) {
      return;
    }

    _receiverId = nextId;
    _receiverRole = nextRole;
    _initialized = true;

    await _initLocalNotifications();
    await refreshUnreadCount();
    _connectSocket();
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _local.initialize(initSettings);
  }

  void _connectSocket() {
    try {
      _socket?.dispose();
    } catch (_) {}

    try {
      final socket = io.io(
        baseUrl.replaceAll('/api', ''),
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': false,
        },
      );

      socket.onConnect((_) {
        if (_receiverRole == 'user') {
          socket.emit('join_user', {'user_id': _receiverId});
        } else {
          socket.emit('join_driver', {'driver_id': _receiverId});
        }
      });

      socket.on('newMessageNotification', (dynamic data) async {
        try {
          unreadCount = unreadCount + 1;
          notifyListeners();

          if (data is Map) {
            final m = Map<String, dynamic>.from(data);
            final title = (m['sender_name'] ?? 'New message').toString().trim();
            final body = (m['message'] ?? '').toString();
            if (body.trim().isNotEmpty) {
              await _showLocal(title: title, body: body);
            }
          }
        } catch (_) {}
      });

      socket.on('wallet_payment_received', (dynamic data) async {
        try {
          if (data is! Map) return;
          final m = Map<String, dynamic>.from(data);
          final amountRaw = m['amount'] ?? m['paid_amount'] ?? m['fare'] ?? 0;
          final commissionRaw = m['commission_amount'] ?? m['commission'] ?? 0;
          final amount = amountRaw is num ? amountRaw.toDouble() : double.tryParse(amountRaw.toString()) ?? 0.0;
          final commissionAmount = commissionRaw is num ? commissionRaw.toDouble() : double.tryParse(commissionRaw.toString()) ?? 0.0;
          await showGlobalPaymentPopup(
            amount: amount,
            commissionAmount: commissionAmount,
            commissionDeducted: commissionAmount > 0,
          );
        } catch (_) {}
      });

      socket.on('review_submitted', (dynamic data) async {
        try {
          await refreshUnreadCount();
          notifyListeners();
        } catch (_) {}
        try {
          await _showLocal(title: 'New Review', body: 'You received a new review');
        } catch (_) {}
      });

      socket.connect();
      _socket = socket;
    } catch (_) {
      _socket = null;
    }
  }

  Future<void> _showLocal({required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Chat Messages',
      channelDescription: 'Chat message notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _local.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
  }

  Future<void> refreshUnreadCount() async {
    if (!isReady) return;
    try {
      unreadCount = await _api.getUnreadCount(receiverId: _receiverId, receiverRole: _receiverRole);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAllRead({String? rideId}) async {
    if (!isReady) return;
    try {
      unreadCount = await _api.markRead(receiverId: _receiverId, receiverRole: _receiverRole, rideId: rideId);
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    super.dispose();
  }
}

