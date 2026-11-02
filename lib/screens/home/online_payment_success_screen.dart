import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OnlinePaymentSuccessScreen extends StatefulWidget {
  final double amount;
  final String riderName;
  final String pickup;
  final String drop;
  final String paymentId;

  const OnlinePaymentSuccessScreen({
    super.key,
    required this.amount,
    required this.riderName,
    required this.pickup,
    required this.drop,
    this.paymentId = '',
  });

  @override
  State<OnlinePaymentSuccessScreen> createState() => _OnlinePaymentSuccessScreenState();
}

class _OnlinePaymentSuccessScreenState extends State<OnlinePaymentSuccessScreen> with TickerProviderStateMixin {
  static const Color _green = Color(0xFF009640);

  late final AnimationController _intro;
  late final AnimationController _ring;
  late final DateTime _paidAt;

  @override
  void initState() {
    super.initState();
    _paidAt = DateTime.now();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
    _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _intro.dispose();
    _ring.dispose();
    super.dispose();
  }

  void _done() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final amountText = widget.amount > 0 ? '₹${widget.amount.toStringAsFixed(widget.amount % 1 == 0 ? 0 : 2)}' : 'Paid';
    final when = DateFormat('d MMM yyyy, h:mm a').format(_paidAt);
    final rider = widget.riderName.trim().isEmpty ? 'Rider' : widget.riderName.trim();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7F5),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  children: [
                    _badge(),
                    const SizedBox(height: 22),
                    _fade(0.42, const Text(
                      'Payment successful',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF111827), letterSpacing: -0.4),
                    )),
                    const SizedBox(height: 6),
                    _fade(0.5, Text(
                      'Received from $rider',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                    )),
                    const SizedBox(height: 18),
                    _fade(0.55, Text(
                      amountText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Color(0xFF111827), letterSpacing: -1.2),
                    )),
                    const SizedBox(height: 22),
                    _fade(0.68, _detailsCard(rider, when)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _done,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Done', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge() {
    final scale = CurvedAnimation(parent: _intro, curve: const Interval(0.0, 0.55, curve: Curves.elasticOut));
    final check = CurvedAnimation(parent: _intro, curve: const Interval(0.28, 0.72, curve: Curves.easeOut));
    return SizedBox(
      height: 148,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _ring]),
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _pulse(118, 0.0),
              _pulse(118, 0.45),
              ScaleTransition(
                scale: Tween<double>(begin: 0.2, end: 1).animate(scale),
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green,
                    boxShadow: [
                      BoxShadow(color: _green.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _CheckPainter(progress: check.value),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pulse(double size, double phase) {
    final t = (_ring.value + phase) % 1.0;
    return Container(
      width: size + (t * 70),
      height: size + (t * 70),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _green.withOpacity((1 - t) * 0.28), width: 2),
      ),
    );
  }

  Widget _fade(double start, Widget child) {
    final anim = CurvedAnimation(parent: _intro, curve: Interval(start, (start + 0.28).clamp(0, 1), curve: Curves.easeOut));
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  Widget _detailsCard(String rider, String when) {
    final rows = <Widget>[
      _row(Icons.person_outline, 'Paid by', rider),
      _row(Icons.account_balance_wallet_outlined, 'Method', 'Razorpay'),
      _row(Icons.schedule, 'Time', when),
      if (widget.pickup.trim().isNotEmpty) _row(Icons.trip_origin, 'Pickup', widget.pickup.trim()),
      if (widget.drop.trim().isNotEmpty) _row(Icons.location_on_outlined, 'Drop', widget.drop.trim()),
      if (widget.paymentId.trim().isNotEmpty) _row(Icons.tag, 'Reference', widget.paymentId.trim()),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1) const Divider(height: 1, color: Color(0xFFF0F2F1)),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: const Color(0xFFE8F6EE), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: _green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 15, color: Color(0xFF111827), fontWeight: FontWeight.w600, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  _CheckPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.68)
      ..lineTo(size.width * 0.74, size.height * 0.36);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    canvas.drawPath(metric.extractPath(0, metric.length * progress.clamp(0, 1)), paint);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) => oldDelegate.progress != progress;
}
