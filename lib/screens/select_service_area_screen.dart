import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/zone_service.dart';

class SelectServiceAreaScreen extends StatefulWidget {
  const SelectServiceAreaScreen({
    super.key,
    this.next,
    this.initialState = '',
  });

  final Widget? next;
  final String initialState;

  @override
  State<SelectServiceAreaScreen> createState() => _SelectServiceAreaScreenState();
}

class _SelectServiceAreaScreenState extends State<SelectServiceAreaScreen> {
  static const Color _green = Color(0xFF009640);

  final TextEditingController _search = TextEditingController();
  List<ServiceZone> _zones = const [];
  String _selected = '';
  bool _loading = true;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.initialState.trim();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final zones = await ZoneService.instance.zones(force: true);
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _loading = false;
        if (_selected.isNotEmpty && !zones.any((zone) => zone.name == _selected)) {
          _selected = '';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load states. Check the connection and try again.';
      });
    }
  }

  List<ServiceZone> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _zones;
    return _zones.where((zone) => zone.name.toLowerCase().contains(query)).toList();
  }

  Future<void> _next() async {
    final stateName = _selected.trim();
    if (stateName.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login again.')),
        );
        return;
      }
      final res = await const ApiService().updateDriverProfile(
        token: token,
        country: 'India',
        state: stateName,
      );
      if (!mounted) return;
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((res['message'] ?? 'Could not save the state').toString())),
        );
        return;
      }
      final next = widget.next;
      if (next != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => next),
          (route) => false,
        );
      } else {
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = _visible;
    final chosen = _selected.trim();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF007A34), Color(0xFF009640)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 28),
                child: Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: widget.next == null
                                ? IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
                                      child: Icon(Icons.arrow_back_ios_new_rounded, color: Theme.of(context).colorScheme.onSurface, size: 16),
                                    ),
                                  )
                                : null,
                          ),
                          const Expanded(
                            child: Text(
                              'Select location',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'India is your country. Choose the state you drive in.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFE8F6EE), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Material(
                elevation: 8,
                shadowColor: const Color(0x1A000000),
                borderRadius: BorderRadius.circular(18),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Find your state',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600),
                    prefixIcon: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                            icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: ViteLoader(color: _green))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    children: [
                      const _SectionLabel('Country'),
                      _ChoiceTile(
                        title: 'India',
                        subtitle: 'Service country',
                        leading: Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: const Text('🇮🇳', style: TextStyle(fontSize: 26)),
                        ),
                        selected: true,
                        locked: true,
                      ),
                      const SizedBox(height: 18),
                      _SectionLabel('States${states.isEmpty ? '' : '  ·  ${states.length}'}'),
                      if (_error.isNotEmpty) _MessageCard(text: _error, action: 'Try again', onTap: _load),
                      if (!_loading && states.isEmpty && _error.isEmpty)
                        const _MessageCard(
                          text: 'No states are set yet. Add a zone in admin, then come back to this screen.',
                        ),
                      ...states.map((zone) {
                        final selected = chosen == zone.name;
                        final letter = zone.name.isEmpty ? '?' : zone.name.substring(0, 1).toUpperCase();
                        return _ChoiceTile(
                          title: zone.name,
                          subtitle: 'India',
                          leading: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? _green : const Color(0xFFE8F6EE),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              letter,
                              style: TextStyle(
                                color: selected ? Colors.white : _green,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          selected: selected,
                          onTap: () => setState(() => _selected = zone.name),
                        );
                      }),
                    ],
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Column(
                  children: [
                    Text(
                      chosen.isEmpty ? 'India' : 'India  ·  $chosen',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: chosen.isEmpty || _saving ? null : _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          disabledBackgroundColor: const Color(0xFFB7D7C4),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: ViteLoader(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text('Next'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.leading,
    required this.selected,
    this.subtitle = '',
    this.onTap,
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xFFF3FBF6) : Colors.white,
        elevation: selected ? 0 : 1,
        shadowColor: const Color(0x14000000),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? const Color(0xFF009640) : const Color(0xFFE6E8EA),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? const Color(0xFF009640) : const Color(0xFFD1D5DB),
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text, this.action, this.onTap});

  final String text;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6E8EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.35)),
          if (action != null && onTap != null)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF009640), padding: const EdgeInsets.only(top: 8)),
              child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}
