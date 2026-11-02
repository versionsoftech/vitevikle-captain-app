import 'package:flutter/material.dart';
import 'package:vite_captain/models/intercity_request.dart';
import 'package:vite_captain/screens/home/intercity_ride_map_screen.dart';
import 'package:vite_captain/screens/intercity/intercity_payment_screen.dart';
import 'package:vite_captain/services/session_service.dart';

class IntercityPaymentMethodScreen extends StatefulWidget {
  final IntercityRequestModel ride;

  const IntercityPaymentMethodScreen({
    super.key,
    required this.ride,
  });

  @override
  State<IntercityPaymentMethodScreen> createState() => _IntercityPaymentMethodScreenState();
}

class _IntercityPaymentMethodScreenState extends State<IntercityPaymentMethodScreen> {
  String _selectedMethod = '';

  @override
  void initState() {
    super.initState();
    _selectedMethod = 'wallet'; // default to wallet for this flow
  }

  void _selectMethod(String method) {
    setState(() {
      _selectedMethod = method;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose how you will receive payment for this intercity ride:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              _buildMethodCard(
                icon: Icons.account_balance_wallet,
                label: 'Wallet',
                isSelected: _selectedMethod == 'wallet',
                onTap: () => _selectMethod('wallet'),
              ),
              const SizedBox(height: 12),
              _buildMethodCard(
                icon: Icons.money,
                label: 'Cash',
                isSelected: _selectedMethod == 'cash',
                onTap: () => _selectMethod('cash'),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF009640),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _selectedMethod.isEmpty
                      ? null
                      : () {
                          final updatedRide = widget.ride.copyWith(paymentMethod: _selectedMethod);
                          if (_selectedMethod == 'wallet') {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => IntercityPaymentScreen(ride: updatedRide),
                              ),
                            );
                          } else {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => IntercityRideMapScreen(ride: updatedRide),
                              ),
                            );
                          }
                        },
                  child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF009640).withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF009640) : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF009640) : Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? const Color(0xFF009640) : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

