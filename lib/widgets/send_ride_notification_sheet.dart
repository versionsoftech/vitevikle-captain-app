import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';

const Color _accent = Color(0xFF009640);

const List<String> _presetMessages = [
  'On my way to your location. 🛵 Get ready to ride!',
  "Approaching your pickup point 🏁 – I'll be there soon!",
  'Pickup and Drop-off Request Updated',
  "En route! 🚙 I'll be at your location in a few minutes.",
  "Your ride is on the way! 🚕 I'll be there in just a few.",
  "I'll be arriving at your location shortly. 👀 See you soon!",
  'Almost there! 🚗 Please be ready as I approach your location',
];

String _text(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s == 'null' ? '' : s;
}

String _first(Map source, List<String> keys) {
  for (final key in keys) {
    final value = _text(source[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _rideIdOf(Map<String, dynamic> ride) {
  return _first(ride, ['_id', 'id', 'ride_id', 'rideId']);
}

String _userIdOf(Map<String, dynamic> ride) {
  final user = ride['user'] ?? ride['customer'] ?? ride['rider'];
  if (user is Map) {
    return _first(Map<String, dynamic>.from(user), ['_id', 'id', 'user_id', 'userId']);
  }
  return _first(ride, ['userId', 'user_id', 'customer_id', 'customerId']);
}

Future<void> showSendRideNotificationSheet(
  BuildContext context,
  Map<String, dynamic> ride,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SendNotificationSheet(ride: ride),
  );
}

class _SendNotificationSheet extends StatefulWidget {
  final Map<String, dynamic> ride;

  const _SendNotificationSheet({required this.ride});

  @override
  State<_SendNotificationSheet> createState() => _SendNotificationSheetState();
}

class _SendNotificationSheetState extends State<_SendNotificationSheet> {
  int _selected = 0;
  bool _sending = false;

  Future<void> _send() async {
    if (_sending) return;
    final message = _presetMessages[_selected];
    final rideId = _rideIdOf(widget.ride);
    final receiverId = _userIdOf(widget.ride);
    final senderId = (await const SessionService().getDriverId() ?? '').trim();

    if (rideId.isEmpty || senderId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride details are missing')),
      );
      return;
    }

    setState(() => _sending = true);
    var sent = false;
    try {
      final resp = await DioClient.dio.post(
        '$baseUrl/chat/send-message',
        data: {
          'ride_id': rideId,
          'sender_id': senderId,
          'receiver_id': receiverId,
          'sender_role': 'driver',
          'message': message,
        },
        options: Options(validateStatus: (_) => true),
      );
      final data = resp.data;
      sent = data is Map && data['success'] == true;
    } catch (_) {
      sent = false;
    }

    if (!mounted) return;
    setState(() => _sending = false);
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the notification')),
      );
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification sent')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Send Notification',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _presetMessages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final selected = index == _selected;
                return Material(
                  color: selected ? _accent : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => setState(() => _selected = index),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: selected ? _accent : const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        _presetMessages[index],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : const Color(0xFF111827),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: Material(
                color: _accent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _sending ? null : _send,
                  child: Center(
                    child: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text(
                            'SEND',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
