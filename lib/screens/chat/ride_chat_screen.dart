import 'dart:async';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/chat_notification_provider.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/widgets/curved_green_app_bar.dart';

class RideChatScreen extends StatefulWidget {
  final String rideId;
  final String senderId;
  final String receiverId;
  final String senderRole;
  final String title;

  const RideChatScreen({
    super.key,
    required this.rideId,
    required this.senderId,
    required this.receiverId,
    required this.senderRole,
    required this.title,
  });

  @override
  State<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends State<RideChatScreen> {
  static const Color _green = Color(0xFF009640);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  Timer? _timer;
  io.Socket? _socket;
  bool _loading = false;
  bool _sending = false;

  List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];

  String _text(dynamic v) => (v ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<ChatNotificationProvider>().markAllRead(rideId: widget.rideId);
      } catch (_) {}
    });
    _ensureSocketConnected();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _ensureSocketConnected() {
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
        socket.emit('join_ride', {'ride_id': widget.rideId});
      });

      socket.on('ride_message', (_) {
        _load(silent: true);
      });

      socket.connect();
      _socket = socket;
    } catch (_) {
      _socket = null;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_loading) return;
    if (!silent) setState(() => _loading = true);

    try {
      final uri = Uri.parse('$baseUrl/chat/messages/${widget.rideId}');
      final Response resp = await DioClient.dio.get(uri.toString(), options: Options(validateStatus: (_) => true));
      if (resp.data is! Map) return;

      final decoded = Map<String, dynamic>.from(resp.data as Map);
      if (decoded['success'] != true) return;

      final raw = decoded['data'];
      if (raw is! List) return;

      final next = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;

      setState(() => _messages = next);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (_) {
      return;
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_sending) return;

    final msg = _controller.text.trim();
    if (msg.isEmpty) return;

    setState(() => _sending = true);

    try {
      final uri = Uri.parse('$baseUrl/chat/send-message');
      final Response resp = await DioClient.dio.post(
        uri.toString(),
        data: {
          'ride_id': widget.rideId,
          'sender_id': widget.senderId,
          'receiver_id': widget.receiverId,
          'sender_role': widget.senderRole,
          'message': msg,
        },
        options: Options(validateStatus: (_) => true),
      );

      if (resp.data is! Map) return;
      final decoded = Map<String, dynamic>.from(resp.data as Map);
      if (decoded['success'] != true) return;

      _controller.clear();
      await _load(silent: true);
    } catch (_) {
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: curvedGreenAppBar(title: widget.title.isEmpty ? 'Chat' : widget.title),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: ViteLoader(color: _green))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final senderId = _text(m['sender_id']);
                      final mine = senderId == widget.senderId;
                      final text = _text(m['message']);

                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 280),
                          decoration: BoxDecoration(
                            color: mine ? _green : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            text,
                            style: TextStyle(
                              color: mine ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    width: 52,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _sending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: ViteLoader(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

