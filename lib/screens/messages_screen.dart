import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/screens/chat/ride_chat_screen.dart';
import 'package:vite_captain/screens/intercity/intercity_chat_screen.dart';
import 'package:vite_captain/services/chat_notification_api.dart';
import 'package:vite_captain/services/chat_notification_provider.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/widgets/vite_loader.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final ChatNotificationApi _api = const ChatNotificationApi();
  bool _loading = true;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _time(dynamic raw) {
    final parsed = DateTime.tryParse(_text(raw));
    if (parsed == null) return '';
    return DateFormat('dd MMM, hh:mm a').format(parsed.toLocal());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (driverId.isEmpty) return;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(8, top + 8, 16, 18),
            decoration: const BoxDecoration(
              color: Color(0xFF009640),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
                const Expanded(
                  child: Text('Chats', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: ViteLoader())
                : _rows.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Color(0xFFCBD5E1)),
                            SizedBox(height: 12),
                            Text('No chats yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: const Color(0xFF009640),
                        onRefresh: _load,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            final name = _text(row['sender_name']);
                            final message = _text(row['message']);
                            final image = _text(row['sender_image']);
                            final rideId = _text(row['ride_id']);
                            final senderId = _text(row['sender_id']);
                            final rideType = _text(row['ride_type']).toLowerCase();
                            final hasImage = image.startsWith('http://') || image.startsWith('https://');
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
                                  if (!context.mounted || rideId.isEmpty || driverId.isEmpty || senderId.isEmpty) return;
                                  await context.read<ChatNotificationProvider>().markAllRead(rideId: rideId);
                                  if (!context.mounted) return;
                                  await Navigator.push(
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
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: const Color(0xFFE8F7EE),
                                        backgroundImage: hasImage ? NetworkImage(image) : null,
                                        child: hasImage ? null : const Icon(Icons.person_rounded, color: Color(0xFF009640)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name.isEmpty ? 'Rider' : name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w800),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              message.isEmpty ? 'New message' : message,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 12.5),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_time(row['created_at']), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
