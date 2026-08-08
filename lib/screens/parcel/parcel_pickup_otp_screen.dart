import 'package:flutter/material.dart';

class ParcelPickupOtpScreen extends StatefulWidget {
  final Map<String, dynamic> parcel;

  const ParcelPickupOtpScreen({
    super.key,
    required this.parcel,
  });

  @override
  State<ParcelPickupOtpScreen> createState() => _ParcelPickupOtpScreenState();
}

class _ParcelPickupOtpScreenState extends State<ParcelPickupOtpScreen> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
