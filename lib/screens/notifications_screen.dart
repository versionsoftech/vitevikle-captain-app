import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/screens/chat/ride_chat_screen.dart';
import 'package:vite_captain/screens/intercity/intercity_chat_screen.dart';
import 'package:vite_captain/services/chat_notification_api.dart';
import 'package:vite_captain/services/chat_notification_provider.dart';
import 'package:vite_captain/services/session_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ChatNotificationApi _api = const ChatNotificationApi();
  bool _loading = true;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _formatTime(dynamic raw) {
    try {
      final d = DateTime.tryParse(_text(raw));
      if (d == null) return '';
      final local = d.toLocal();
      return DateFormat('hh:mm a').format(local);
    } catch (_) {
      return '';
    }
  }

  Future<String> _resolveDriverId() async {
    return (await const SessionService().getDriverId())?.trim() ?? '';
  }

  Future<void> _load({bool markRead = false}) async {
    setState(() => _loading = true);
    try {
      final driverId = await _resolveDriverId();
      if (driverId.isEmpty) return;

      if (markRead && mounted) {
        await context.read<ChatNotificationProvider>().markAllRead();
      }

      final rows = await _api.list(receiverId: driverId, receiverRole: 'driver');
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load(markRead: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/notifications/empty_notifications.png',
                        height: 150,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.notifications_none,
                            size: 120,
                            color: Colors.grey.shade300,
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'You have no new notifications',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final n = _rows[index];
                      final name = _text(n['sender_name']);
                      final msg = _text(n['message']);
                      final time = _formatTime(n['created_at']);
                      final img = _text(n['sender_image']);
                      final rideId = _text(n['ride_id']);
                      final senderId = _text(n['sender_id']);
                      final rideType = _text(n['ride_type']).toLowerCase();
                      final hasImg = img.startsWith('http://') || img.startsWith('https://');

                      return ListTile(
                        onTap: () async {
                          final driverId = await _resolveDriverId();
                          if (!context.mounted) return;
                          if (rideId.isEmpty || driverId.isEmpty || senderId.isEmpty) return;

                          await context.read<ChatNotificationProvider>().markAllRead(rideId: rideId);
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => rideType == 'normal'
                                  ? RideChatScreen(
                                      rideId: rideId,
                                      senderId: driverId,
                                      receiverId: senderId,
                                      senderRole: 'driver',
                                      title: name.isEmpty ? 'Chat' : name,
                                    )
                                  : IntercityChatScreen(
                                      rideId: rideId,
                                      senderId: driverId,
                                      receiverId: senderId,
                                      title: name.isEmpty ? 'Chat' : name,
                                    ),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: hasImg ? NetworkImage(img) : null,
                          child: !hasImg ? const Icon(Icons.person, color: Colors.grey) : null,
                        ),
                        title: Text(
                          name.isEmpty ? 'Message' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          msg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          time,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

