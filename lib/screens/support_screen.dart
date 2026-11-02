import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vite_captain/screens/chat/ride_chat_screen.dart';
import 'package:vite_captain/services/session_service.dart';

const Color _green = Color(0xFF009640);
const String _supportEmail = 'vitevikle@gmail.com';
const String _supportPhone = '9646006716';

class _HelpTopic {
  const _HelpTopic(this.title, this.body);
  final String title;
  final String body;
}

const List<_HelpTopic> _topics = <_HelpTopic>[
  _HelpTopic('Going online', 'Tap Go Online on the home screen. The same button switches you back to off duty.'),
  _HelpTopic('Payout', 'Open Payouts for today\'s earnings and withdrawals. Wallet shows your balance.'),
  _HelpTopic('Login', 'Use the mobile number registered on your captain account.'),
  _HelpTopic('Trip', 'A new ride stays on the screen until you accept or reject it. It does not cancel by itself.'),
  _HelpTopic('Documents', 'Open Profile to check documents, vehicle details, and bank details.'),
];

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String title, String body) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) || body.toLowerCase().contains(q);
  }

  Future<void> _openChat() async {
    final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
    if (!mounted) return;
    if (driverId.isEmpty) {
      _note('Sign in again to use live chat.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RideChatScreen(
          rideId: 'support_$driverId',
          senderId: driverId,
          receiverId: 'vite-support',
          senderRole: 'driver',
          title: 'Support',
        ),
      ),
    );
  }

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: _supportPhone);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _note('Could not open the phone dialer.');
  }

  Future<void> _mail(String subject) async {
    final uri = Uri(scheme: 'mailto', path: _supportEmail, queryParameters: {'subject': subject});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _note('Could not open email.');
  }

  void _note(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openTopic(String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Text(body, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.4)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final topics = _topics.where((topic) => _matches(topic.title, topic.body)).toList();
    final rows = <_RowData>[
      if (_matches('Chat with Support', 'Get instant help from our team'))
        _RowData(Icons.chat_bubble_rounded, const Color(0xFFEAF8F0), _green, 'Chat with Support', 'Get instant help from our team', _openChat),
      if (_matches('Call Support', 'Talk to our support executive'))
        _RowData(Icons.phone_rounded, const Color(0xFFE8F1FF), const Color(0xFF3B82F6), 'Call Support', 'Talk to our support executive', _call),
      if (_matches('Help Center', 'Find answers to common questions'))
        _RowData(Icons.help_rounded, const Color(0xFFE8F1FF), const Color(0xFF3B82F6), 'Help Center', 'Find answers to common questions', () {
          if (topics.isEmpty) {
            _note('No help topics match that search.');
            return;
          }
          _openTopic(topics.first.title, topics.first.body);
        }),
      if (_matches('Report an Issue', 'Facing a problem? Let us know'))
        _RowData(Icons.verified_user_rounded, const Color(0xFFEAF8F0), _green, 'Report an Issue', 'Facing a problem? Let us know', () => _mail('Vite Captain issue')),
      if (_matches('App Guide', 'Learn how to use the app'))
        _RowData(Icons.menu_book_rounded, const Color(0xFFE8F1FF), const Color(0xFF3B82F6), 'App Guide', 'Learn how to use the app', () {
          if (topics.isEmpty) {
            _note('No guide topics match that search.');
            return;
          }
          _openTopic('App Guide', topics.map((topic) => '${topic.title}: ${topic.body}').join('\n\n'));
        }),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        title: const Text('Support', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How can we\nhelp you?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, height: 1.05, color: Theme.of(context).colorScheme.onSurface)),
                    SizedBox(height: 8),
                    Text(
                      'Get quick support and find answers to common questions.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'assets/images/support_agent.png',
                  width: 132,
                  height: 132,
                  fit: BoxFit.cover,
                  semanticLabel: 'Vite support',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search for help (e.g. payout, login, trip)',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _green, width: 1.4)),
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty && q.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('No matches.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ),
          for (final row in rows) ...[
            _SupportRow(data: row),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Text('Support email', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => _mail('Vite Captain support'),
            child: Text(_supportEmail, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          const SizedBox(height: 10),
          Text('Mobile no.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: _call,
            child: Text(_supportPhone, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _RowData {
  const _RowData(this.icon, this.background, this.tint, this.title, this.body, this.onTap);
  final IconData icon;
  final Color background;
  final Color tint;
  final String title;
  final String body;
  final VoidCallback onTap;
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({required this.data});
  final _RowData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: data.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: data.background, shape: BoxShape.circle),
                child: Icon(data.icon, color: data.tint, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.title, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(data.body, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
