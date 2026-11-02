import 'package:flutter/material.dart';
import 'package:vite_captain/services/payment_gateway_api.dart';
import 'package:vite_captain/services/ride_booking_state.dart';
import 'package:vite_captain/widgets/vite_loader.dart';

class SetPriceBottomSheet extends StatefulWidget {
  final int initialPrice;
  final int baseFare;
  final String initialPayment;
  final Map<String, dynamic>? coupon;
  final ValueChanged<int>? onDraftFare;
  final ValueChanged<String>? onPaymentChanged;

  const SetPriceBottomSheet({
    super.key,
    this.initialPrice = 10,
    this.baseFare = 0,
    this.initialPayment = 'cash',
    this.coupon,
    this.onDraftFare,
    this.onPaymentChanged,
  });

  @override
  State<SetPriceBottomSheet> createState() => _SetPriceBottomSheetState();
}

class _SetPriceBottomSheetState extends State<SetPriceBottomSheet> {
  late int _price;
  bool _autoBook = false;

  static const int _actionOpenCoupon = -2;

  late String _selectedPayment;
  String _selectedPaymentLabel = 'Cash';
  IconData _selectedPaymentIcon = Icons.money;

  int get _save => RideBookingState.couponOff(widget.coupon, _price);
  int get _payable => (_price - _save).clamp(0, _price);
  String get _couponTitle {
    final code = (widget.coupon?['code'] ?? '').toString().trim();
    return code.isEmpty ? 'Coupon' : code;
  }

  final PaymentGatewayApi _paymentGatewayApi = const PaymentGatewayApi();
  Future<List<PaymentGatewayModel>>? _paymentGatewaysFuture;

  @override
  void initState() {
    super.initState();
    final base = widget.baseFare;
    final start = widget.initialPrice;
    _price = start < base ? base : start;

    _selectedPayment = widget.initialPayment;
    _applyPaymentDisplay(value: _selectedPayment);
  }

  void _applyPaymentDisplay({
    required String value,
    String? label,
    IconData? icon,
  }) {
    setState(() {
      _selectedPayment = value;

      if (label != null && label.trim().isNotEmpty) {
        _selectedPaymentLabel = label.trim();
      } else {
        if (value == 'wallet') {
          _selectedPaymentLabel = 'Wallet';
        } else if (value == 'cash') {
          _selectedPaymentLabel = 'Cash';
        } else {
          _selectedPaymentLabel = value;
        }
      }

      _selectedPaymentIcon = icon ?? _selectedPaymentIcon;
      if (icon == null) {
        if (value == 'wallet') {
          _selectedPaymentIcon = Icons.account_balance_wallet;
        } else if (value == 'cash') {
          _selectedPaymentIcon = Icons.money;
        } else {
          _selectedPaymentIcon = Icons.payments;
        }
      }
    });
  }

  Future<void> _openPaymentMethodSheet() async {
    _paymentGatewaysFuture ??= _paymentGatewayApi.getPaymentGateways();

    final result = await showModalBottomSheet<_PaymentSelectionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _PaymentMethodBottomSheet(
          initialValue: _selectedPayment,
          gatewaysFuture: _paymentGatewaysFuture!,
        );
      },
    );

    if (!mounted || result == null) return;

    _applyPaymentDisplay(
      value: result.value,
      label: result.label,
      icon: result.icon,
    );
    widget.onPaymentChanged?.call(result.value);
  }

  void _inc() {
    setState(() {
      _price += 5;
    });
  }

  void _dec() {
    setState(() {
      final next = _price - 5;
      _price = next < widget.baseFare ? widget.baseFare : next;
    });
  }

  Widget _iconPill(IconData icon, {Color? color}) {
    return Container(
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Icon(icon, color: color ?? Colors.black87),
    );
  }

  Widget _rowTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF009640),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Set your price',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Raise the fare, increase your chances.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                InkWell(onTap: _dec, child: _iconPill(Icons.remove)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$_price',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Container(
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                InkWell(onTap: _inc, child: _iconPill(Icons.add)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.flash_on, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Automatically book the nearest\ndriver for (\u20B9$_price)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: _autoBook,
                    onChanged: (v) => setState(() => _autoBook = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _rowTile(
                      icon: _selectedPaymentIcon,
                      title: _selectedPaymentLabel,
                      onTap: _openPaymentMethodSheet,
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _rowTile(
                      icon: Icons.local_offer,
                      title: _couponTitle,
                      subtitle: _save > 0 ? 'You save ₹$_save' : null,
                      onTap: () {
                        widget.onDraftFare?.call(_price);
                        Navigator.pop(context, _actionOpenCoupon);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF37AF00),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () => Navigator.pop(context, _price),
                child: Text('Book for \u20B9$_payable'),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel Request'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentSelectionResult {
  final String value;
  final String label;
  final IconData icon;

  const _PaymentSelectionResult({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class _PaymentMethodBottomSheet extends StatefulWidget {
  final String initialValue;
  final Future<List<PaymentGatewayModel>> gatewaysFuture;

  const _PaymentMethodBottomSheet({
    required this.initialValue,
    required this.gatewaysFuture,
  });

  @override
  State<_PaymentMethodBottomSheet> createState() => _PaymentMethodBottomSheetState();
}

class _PaymentMethodBottomSheetState extends State<_PaymentMethodBottomSheet> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
  }

  IconData _fallbackIcon(String serial) {
    final s = serial.toLowerCase();
    if (s.contains('wallet')) return Icons.account_balance_wallet;
    if (s.contains('card')) return Icons.credit_card;
    if (s.contains('cash')) return Icons.money;
    return Icons.payments;
  }

  _PaymentSelectionResult _toResult({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return _PaymentSelectionResult(value: value, label: label, icon: icon);
  }

  Widget _paymentTile({
    required String label,
    required String value,
    required Widget leading,
  }) {
    final isSelected = _selected == value;

    return GestureDetector(
      onTap: () => setState(() => _selected = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF37AF00) : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              height: 45,
              width: 55,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: leading),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Container(
              height: 22,
              width: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF37AF00) : Colors.grey,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        height: 10,
                        width: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF37AF00),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.62,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              height: 5,
              width: 50,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Select Payment Method',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            Flexible(
              fit: FlexFit.loose,
              child: ListView(
                shrinkWrap: true,
                primary: false,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _paymentTile(
                    label: 'Cash',
                    value: 'cash',
                    leading: Icon(Icons.money, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  _paymentTile(
                    label: 'Wallet',
                    value: 'wallet',
                    leading: Icon(Icons.account_balance_wallet, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  FutureBuilder<List<PaymentGatewayModel>>(
                    future: widget.gatewaysFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Center(
                            child: SizedBox(
                              height: 22,
                              width: 22,
                              child: ViteLoader(strokeWidth: 2),
                            ),
                          ),
                        );
                      }

                      final items = snapshot.data ?? const <PaymentGatewayModel>[];
                      if (items.isEmpty) return const SizedBox.shrink();

                      return Column(
                        children: items.map((item) {
                          final serial = item.serial;
                          final iconUrl = item.iconUrl.trim();

                          Widget leading;
                          if (iconUrl.isNotEmpty) {
                            final primary = iconUrl;
                            final fallback = primary.replaceFirst('://adm.', '://admin.');
                            leading = Image.network(
                              primary,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) {
                                if (fallback != primary) {
                                  return Image.network(
                                    fallback,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Icon(_fallbackIcon(serial), size: 24),
                                  );
                                }
                                return Icon(_fallbackIcon(serial), size: 24);
                              },
                            );
                          } else {
                            leading = Icon(_fallbackIcon(serial), size: 24, color: Theme.of(context).colorScheme.onSurface);
                          }

                          return _paymentTile(
                            label: item.name,
                            value: serial,
                            leading: leading,
                          );
                        }).toList(growable: false),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF37AF00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () {
                    if (_selected == 'cash') {
                      Navigator.pop(context, _toResult(value: 'cash', label: 'Cash', icon: Icons.money));
                      return;
                    }
                    if (_selected == 'wallet') {
                      Navigator.pop(
                        context,
                        _toResult(
                          value: 'wallet',
                          label: 'Wallet',
                          icon: Icons.account_balance_wallet,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(
                      context,
                      _toResult(
                        value: _selected,
                        label: _selected,
                        icon: Icons.payments,
                      ),
                    );
                  },
                  child: const Text('Confirm'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

