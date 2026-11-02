import 'package:flutter/material.dart';
import 'package:vite_captain/screens/home/driver_give_review_screen.dart';

class DriverPaymentSuccessScreen extends StatelessWidget {
  static const Color primaryColor = Color(0xFF009640);

  final double paidAmount;
  final String rideId;
  final String userId;
  final String userName;
  final String userImageUrl;

  const DriverPaymentSuccessScreen({
    super.key,
    required this.paidAmount,
    required this.rideId,
    required this.userId,
    required this.userName,
    required this.userImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.check_circle, color: primaryColor, size: 64),
              const SizedBox(height: 14),
              Text(
                'Paid ₹${paidAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              const Text(
                'Payment successful',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54),
              ),
              const Spacer(),
              if (userId.trim().isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DriverGiveReviewScreen(
                            rideId: rideId,
                            userId: userId,
                            userName: userName,
                            userImageUrl: userImageUrl,
                            paidAmount: paidAmount,
                          ),
                        ),
                      );
                    },
                    child: const Text('Rate User', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900)),
                  ),
                ),
              if (userId.trim().isNotEmpty) const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

