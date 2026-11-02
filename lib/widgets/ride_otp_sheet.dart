import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/widgets/vite_loader.dart';

/// One field so a fast 4-digit entry is not dropped between boxes.
class RideOtpSheet extends StatefulWidget {
  final String rideId;

  const RideOtpSheet({super.key, required this.rideId});

  @override
  State<RideOtpSheet> createState() => _RideOtpSheetState();
}

class _RideOtpSheetState extends State<RideOtpSheet> {
  static const Color _green = Color(0xFF009640);

  final TextEditingController _codeController = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final next = digits.length > 4 ? digits.substring(0, 4) : digits;
    if (next != value) {
      _codeController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
    if (_error.isNotEmpty) setState(() => _error = '');
    setState(() {});
    if (next.length == 4) _submit();
  }

  Future<void> _submit() async {
    final otp = _codeController.text.trim();
    if (_busy) return;
    if (otp.length < 4) {
      setState(() => _error = 'Enter the 4-digit OTP from the rider');
      return;
    }
    _busy = true;
    setState(() => _error = '');
    final res = await const ApiService().verifyRideOtp(rideId: widget.rideId, otp: otp);
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = (res['message'] ?? 'Wrong OTP. Ask the rider again.').toString();
    });
    _codeController.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.viewPaddingOf(context).bottom;
    final code = _codeController.text;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 16),
            Text('Enter rider OTP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 6),
            Text(
              'Type the 4-digit code. It fills as fast as you type.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.3),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => _focus.requestFocus(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final digit = index < code.length ? code[index] : '';
                      final active = index == code.length || (code.length == 4 && index == 3);
                      return Container(
                        width: 58,
                        height: 64,
                        margin: EdgeInsets.only(left: index == 0 ? 0 : 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAF9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: active ? _green : const Color(0xFFE5E7EB), width: active ? 1.6 : 1),
                        ),
                        child: Text(digit, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                      );
                    }),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextField(
                        controller: _codeController,
                        focusNode: _focus,
                        enabled: !_busy,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        showCursor: false,
                        enableSuggestions: false,
                        autocorrect: false,
                        style: const TextStyle(color: Colors.transparent, fontSize: 24),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                        decoration: const InputDecoration(
                          counterText: '',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isCollapsed: true,
                        ),
                        onChanged: _onChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: ViteLoader(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify and start', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
