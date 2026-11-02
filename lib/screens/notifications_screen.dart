import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/services/chat_notification_api.dart';
import 'package:vite_captain/services/notification_service.dart';
import 'package:vite_captain/services/session_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ChatNotificationApi _api = const ChatNotificationApi();
  bool _loading = true;
  int _tab = 0;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _chats = <Map<String, dynamic>>[];

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _formatTime(dynamic raw) {
    try {
      final d = DateTime.tryParse(_text(raw));
      if (d == null) return '';
      return DateFormat('dd MMM, hh:mm a').format(d.toLocal());
    } catch (_) {
      return '';
    }
  }

  ({IconData icon, Color color}) _style(String event, String title) {
    final text = '$event $title'.toLowerCase();
    if (text.contains('wallet') || text.contains('payment') || text.contains('earning') || text.contains('cash')) {
      return (icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF0284C7));
    }
    if (text.contains('document') || text.contains('kyc') || text.contains('licence') || text.contains('license')) {
      return (icon: Icons.badge_rounded, color: const Color(0xFFD97706));
    }
    if (text.contains('cancel')) {
      return (icon: Icons.cancel_rounded, color: const Color(0xFFE11D48));
    }
    if (text.contains('complete') || text.contains('arrived') || text.contains('start')) {
      return (icon: Icons.check_circle_rounded, color: const Color(0xFF009640));
    }
    if (text.contains('bid') || text.contains('offer')) {
      return (icon: Icons.local_offer_rounded, color: const Color(0xFF7C3AED));
    }
    if (text.contains('ride') || text.contains('trip') || text.contains('parcel') || text.contains('order')) {
      return (icon: Icons.local_taxi_rounded, color: const Color(0xFF009640));
    }
    if (text.contains('account') || text.contains('suspend') || text.contains('review')) {
      return (icon: Icons.verified_user_rounded, color: const Color(0xFF0F766E));
    }
    return (icon: Icons.notifications_rounded, color: const Color(0xFF009640));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (driverId.isEmpty) return;
      final appRows = await _api.listApp(receiverId: driverId);
      final chatRows = await _api.list(receiverId: driverId, receiverRole: 'driver');
      await _api.markAppRead(receiverId: driverId);
      await _api.markRead(receiverId: driverId, receiverRole: 'driver');
      final localRows = await loadCaptainNotifications();
      final merged = <Map<String, dynamic>>[
        ...appRows.map((row) => <String, dynamic>{
              'title': row['title'],
              'body': row['body'],
              'event': row['event'],
              'created_at': row['created_at'],
            }),
        ...localRows,
      ];
      merged.sort((a, b) {
        final left = DateTime.tryParse(_text(a['created_at'])) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = DateTime.tryParse(_text(b['created_at'])) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final row in merged) {
        final stamp = _text(row['created_at']);
        final shortStamp = stamp.length > 16 ? stamp.substring(0, 16) : stamp;
        final key = '${_text(row['title'])}|${_text(row['body'])}|$shortStamp';
        if (seen.contains(key)) continue;
        seen.add(key);
        unique.add(row);
      }
      if (!mounted) return;
      setState(() {
        _rows = unique;
        _chats = chatRows;
      });
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

  Widget _captainTab(String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF009640) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? const Color(0xFF009640) : const Color(0xFFE5E7EB)),
          ),
          child: Text(
            label,
            style: TextStyle(color: selected ? Colors.white : const Color(0xFF111827), fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
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
                  child: Text(
                    'Notifications',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                _captainTab('Alerts', 0),
                const SizedBox(width: 8),
                _captainTab('Chats', 1),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: ViteLoader())
                : (_tab == 0 ? _rows : _chats).isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none_rounded, size: 64, color: Color(0xFFCBD5E1)),
                            SizedBox(height: 12),
                            Text('No notifications yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: const Color(0xFF009640),
                        onRefresh: _load,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                          itemCount: (_tab == 0 ? _rows : _chats).length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final row = (_tab == 0 ? _rows : _chats)[index];
                            if (_tab == 1 && _text(row['title']).isEmpty) {
                              row['title'] = _text(row['sender_name']).isEmpty ? 'Chat' : _text(row['sender_name']);
                            }
                            final title = _text(row['title']);
                            final body = _text(row['body']).isEmpty ? _text(row['message']) : _text(row['body']);
                            final style = _style(_text(row['event']), title);
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4)),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: style.color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(style.icon, color: style.color, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title.isEmpty ? 'Notification' : title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                        ),
                                        if (body.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            body,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.3),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatTime(row['created_at']),
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
