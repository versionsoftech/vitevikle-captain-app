import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/ride_booking_state.dart';

class ApplyCouponBottomSheet extends StatefulWidget {
  const ApplyCouponBottomSheet({
    super.key,
    required this.audience,
    required this.orderAmount,
    this.currentCode = '',
  });

  final String audience;
  final int orderAmount;
  final String currentCode;

  @override
  State<ApplyCouponBottomSheet> createState() => _ApplyCouponBottomSheetState();
}

class _ApplyCouponBottomSheetState extends State<ApplyCouponBottomSheet> {
  static const _green = Color(0xFF009640);

  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _coupons = const [];
  bool _loading = true;
  bool _applying = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _controller.text = widget.currentCode;
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.dio.get(
        '$baseUrl/coupons/public',
        queryParameters: {'audience': widget.audience},
        options: Options(validateStatus: (_) => true),
      );
      dynamic data = res.data;
      if (data is String) data = jsonDecode(data);
      final rows = data is Map && data['data'] is List
          ? (data['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _coupons = rows;
        _loading = false;
        _error = data is Map && data['success'] == true
            ? ''
            : (data is Map ? (data['message'] ?? '').toString() : '');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load coupons';
      });
    }
  }

  Future<void> _applyCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty || _applying) return;
    setState(() {
      _applying = true;
      _error = '';
    });
    try {
      final res = await DioClient.dio.get(
        '$baseUrl/coupons/validate/${Uri.encodeComponent(code)}',
        queryParameters: {
          'audience': widget.audience,
          'amount': widget.orderAmount,
        },
        options: Options(validateStatus: (_) => true),
      );
      dynamic data = res.data;
      if (data is String) data = jsonDecode(data);
      final ok = data is Map && data['success'] == true && data['data'] is Map;
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _applying = false;
          _error = data is Map
              ? (data['message'] ?? 'Coupon is invalid or expired').toString()
              : 'Coupon is invalid or expired';
        });
        return;
      }
      Navigator.pop(context, Map<String, dynamic>.from(data['data'] as Map));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = 'Could not apply this coupon';
      });
    }
  }

  String _valueLabel(Map<String, dynamic> coupon) {
    final type = (coupon['type'] ?? '').toString();
    final amount = coupon['amount'];
    if (type == 'percentage') return '${amount ?? 0}% off';
    return '₹${amount ?? 0} off';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  'Apply coupon',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'Enter coupon code',
                          filled: true,
                          fillColor: const Color(0xFFF3F6F4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _applying ? null : () => _applyCode(_controller.text),
                        child: _applying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Apply', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_error, style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                  ),
                ),
              if (widget.currentCode.trim().isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, {'remove': true}),
                    child: Text(
                      'Remove ${widget.currentCode.trim()}',
                      style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: CircularProgressIndicator(color: _green)),
                      )
                    : _coupons.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No active coupons right now. If you have a code, enter it above.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _coupons.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final coupon = _coupons[index];
                              final code = (coupon['code'] ?? '').toString();
                              final title = (coupon['title'] ?? code).toString();
                              final description = (coupon['description'] ?? '').toString().trim();
                              final off = RideBookingState.couponOff(coupon, widget.orderAmount);
                              final minAmount = coupon['min_order_amount'];
                              final minLabel = minAmount == null || '$minAmount' == '0' || '$minAmount' == '0.0'
                                  ? ''
                                  : 'Min ride ₹$minAmount';
                              final blocked = widget.orderAmount > 0 && off == 0 && minLabel.isNotEmpty;
                              return Material(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: blocked || _applying ? null : () => _applyCode(code),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                              const SizedBox(height: 2),
                                              Text(
                                                _valueLabel(coupon),
                                                style: const TextStyle(color: _green, fontWeight: FontWeight.w700),
                                              ),
                                              if (description.isNotEmpty)
                                                Text(description, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                                              if (minLabel.isNotEmpty)
                                                Text(
                                                  blocked ? '$minLabel · fare is lower' : minLabel,
                                                  style: TextStyle(
                                                    color: blocked ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(20)),
                                          child: Text(code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
