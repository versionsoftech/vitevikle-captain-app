import 'dart:async';

import 'package:flutter/material.dart';

/// Incoming ride card, laid out like the ZipGo driver request sheet.
class RideRequestCard extends StatefulWidget {
  const RideRequestCard({
    super.key,
    required this.customerName,
    required this.pickup,
    required this.drop,
    required this.fare,
    required this.seconds,
    required this.onAccept,
    required this.onReject,
    this.onWaitFinished,
    this.customerImage = '',
    this.pickupDistance = '',
    this.dropDistance = '',
    this.duration = '',
    this.rating = 0,
    this.reviews = 0,
  });

  final String customerName;
  final String customerImage;
  final String pickup;
  final String drop;
  final int fare;
  final int seconds;
  final String pickupDistance;
  final String dropDistance;
  final String duration;
  final double rating;
  final int reviews;
  final Future<bool> Function(int bid) onAccept;
  final Future<void> Function() onReject;
  final Future<void> Function()? onWaitFinished;

  @override
  State<RideRequestCard> createState() => _RideRequestCardState();
}

class _RideRequestCardState extends State<RideRequestCard> {
  static const Color _green = Color(0xFF4CAF50);
  static const Color _accent = Color(0xFF009640);

  Timer? _timer;
  late int _left;
  late int _total;
  bool _busy = false;
  bool _closed = false;
  bool _waiting = false;
  int _offered = 0;
  int _waitLeft = 30;
  double _knob = 0;
  int _swipePhase = 0;
  final TextEditingController _customFare = TextEditingController();

  @override
  void initState() {
    super.initState();
    _total = widget.seconds <= 0 ? 60 : widget.seconds;
    _left = _total;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _customFare.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _closed) return;
    if (_waiting) {
      if (_waitLeft <= 1) {
        _finish(widget.onWaitFinished ?? widget.onReject);
        return;
      }
      setState(() => _waitLeft -= 1);
      return;
    }
    if (_left <= 1) {
      _finish(widget.onReject);
      return;
    }
    setState(() => _left -= 1);
  }

  Future<void> _finish(Future<void> Function() action) async {
    if (_busy || _closed) return;
    _closed = true;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(int price) async {
    if (_busy || _closed) return;
    setState(() => _busy = true);
    final ok = await widget.onAccept(price <= 0 ? widget.fare : price);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _knob = 0;
        _swipePhase = 0;
      });
      return;
    }
    setState(() {
      _busy = false;
      _waiting = true;
      _offered = price <= 0 ? widget.fare : price;
      _waitLeft = 30;
    });
  }

  Future<void> _editFare() async {
    _customFare.text = '${widget.fare + 1}';
    final amount = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Offer your fare'),
          content: TextField(
            controller: _customFare,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(prefixText: '₹ '),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, int.tryParse(_customFare.text.trim())),
              child: const Text('Offer'),
            ),
          ],
        );
      },
    );
    if (amount != null && amount > 0) _send(amount);
  }

  Future<void> _swipeAccept(double max) async {
    if (_busy || _closed || _swipePhase != 0) return;
    setState(() {
      _knob = max;
      _swipePhase = 1;
      _busy = true;
    });
    final ok = await widget.onAccept(widget.fare);
    if (!mounted || _closed) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _knob = 0;
        _swipePhase = 0;
      });
      return;
    }
    setState(() => _swipePhase = 2);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || _closed) return;
    setState(() {
      _busy = false;
      _waiting = true;
      _offered = widget.fare;
      _waitLeft = 30;
    });
  }

  Widget _acceptSlider(String label) {
    const track = Color(0xFF4CAF50);
    return LayoutBuilder(
      builder: (context, constraints) {
        const knob = 58.0;
        final max = (constraints.maxWidth - knob - 6).clamp(1.0, constraints.maxWidth);
        final x = _swipePhase == 0 ? _knob.clamp(0.0, max) : max;
        return GestureDetector(
          onHorizontalDragUpdate: _busy || _swipePhase != 0
              ? null
              : (details) {
                  setState(() => _knob = (_knob + details.delta.dx).clamp(0.0, max));
                },
          onHorizontalDragEnd: _busy || _swipePhase != 0
              ? null
              : (_) {
                  if (_knob > max * 0.72) {
                    _swipeAccept(max);
                  } else {
                    setState(() => _knob = 0);
                  }
                },
          child: Container(
            height: 49,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.4),
                    ),
                  ),
                ),
                Positioned(
                  left: 3 + x,
                  top: 3,
                  bottom: 3,
                  child: Container(
                    width: knob,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _swipePhase == 1
                        ? const SizedBox(
                            width: 25,
                            height: 25,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF4CAF50)),
                          )
                        : Icon(
                            _swipePhase == 2 ? Icons.check_rounded : Icons.directions_bike,
                            color: const Color(0xFF4CAF50),
                            size: _swipePhase == 2 ? 30 : 25,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _money(num value) {
    final text = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
    return '₹$text';
  }

  String _kmLabel() {
    final raw = widget.dropDistance.trim();
    if (raw.isEmpty) return '';
    return raw.toLowerCase().contains('km') ? raw : '$raw Km';
  }

  String _perKm() {
    final km = double.tryParse(widget.dropDistance.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (km == null || km <= 0 || widget.fare <= 0) return '';
    return '${(widget.fare / km).toStringAsFixed(2)}₹/Km';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.customerName.trim().isEmpty ? 'Customer' : widget.customerName.trim();
    final initial = name[0].toUpperCase();
    final rejectFill = _total <= 0 ? 0.0 : (1 - (_left / _total)).clamp(0.0, 1.0);
    final waitFill = (1 - (_waitLeft / 30)).clamp(0.0, 1.0);

    return Material(
      color: _waiting ? const Color(0xCC000000) : Colors.transparent,
      child: SizedBox.expand(
        child: Stack(
        children: [
          if (!_waiting)
            Positioned(
              top: 36,
              right: 16,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: _busy ? null : () => _finish(widget.onReject),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _waiting
                ? _waitingSheet(name, initial, waitFill)
                : _requestSheet(name, initial, rejectFill),
          ),
        ],
      ),
      ),
    );
  }

  String _photoUrl() {
    final raw = widget.customerImage.trim();
    if (raw.isEmpty) return '';
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return 'https://adm.vitevikle.com$raw';
    return 'https://adm.vitevikle.com/$raw';
  }

  Widget _avatar(String initial) {
    final url = _photoUrl();
    final letter = Text(initial, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800));
    return Container(
      height: 70,
      width: 70,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
      child: url.isEmpty
          ? letter
          : Image.network(
              url,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => letter,
            ),
    );
  }

  Widget _requestSheet(String name, String initial, double rejectFill) {
    final km = _kmLabel();
    final perKm = _perKm();
    final offerA = widget.fare + 1;
    final offerB = widget.fare + 2;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Column(
                      children: [
                        _avatar(initial),
                        const SizedBox(height: 6),
                        Text(name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star, size: 14, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                '${widget.rating.toStringAsFixed(1)}(${widget.reviews})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _addressRow(Icons.navigation, _accent, widget.pickup, bold: true),
                        const SizedBox(height: 12),
                        _addressRow(Icons.circle, const Color(0xFF22C55E), widget.drop, bold: false),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(left: 26),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(_money(widget.fare), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                              if (perKm.isNotEmpty) Text(perKm, style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600)),
                              if (km.isNotEmpty) Text(km, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _acceptSlider('Accept For ${_money(widget.fare)}'),
              const SizedBox(height: 12),
              SizedBox(
                height: 49,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.redAccent.withValues(alpha: 0.8)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: rejectFill.clamp(0.001, 1),
                          child: const ColoredBox(color: Colors.red),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _finish(widget.onReject),
                        child: const Text('Reject', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Offer your fare:', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _offerChip(offerA)),
                  const SizedBox(width: 10),
                  Expanded(child: _offerChip(offerB)),
                  const SizedBox(width: 10),
                  Material(
                    color: _accent,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _busy ? null : _editFare,
                      child: const SizedBox(width: 60, height: 60, child: Icon(Icons.edit, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waitingSheet(String name, String initial, double waitFill) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Offering your fare', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
        Text(_money(_offered), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Wait for the reply', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Column(
                          children: [
                            _avatar(initial),
                            const SizedBox(height: 6),
                            Text(name, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _addressRow(Icons.navigation, _accent, widget.pickup, bold: true),
                            const SizedBox(height: 12),
                            _addressRow(Icons.circle, const Color(0xFF22C55E), widget.drop, bold: false),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.only(left: 26),
                              child: Text(_money(_offered), style: const TextStyle(color: _green, fontSize: 20, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 49,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0xFFD1FAE5)),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: waitFill.clamp(0.001, 1),
                              child: const ColoredBox(color: _green),
                            ),
                          ),
                          Center(
                            child: Text(
                              '0:${_waitLeft.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _offerChip(int amount) {
    return OutlinedButton(
      onPressed: _busy ? null : () => _send(amount),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 60),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        foregroundColor: Colors.black87,
      ),
      child: Text(_money(amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }

  Widget _addressRow(IconData icon, Color color, String text, {required bool bold}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text.trim().isEmpty ? 'Location' : text.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: 13, height: 1.2, color: bold ? Colors.black87 : const Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }
}
