import 'package:flutter/material.dart';

class RideBookingState extends ChangeNotifier {
  double? pickupLat;
  double? pickupLng;
  String pickupAddress = '';

  double? dropLat;
  double? dropLng;
  String dropAddress = '';

  String selectedContactName = 'For me';
  String selectedContactPhone = '';

  final List<String> stops = <String>[];

  int offerFare = 0;
  int baseFare = 0;
  String? selectedVehicleTypeId;
  Map<String, dynamic>? appliedCoupon;

  static int couponOff(Map<String, dynamic>? coupon, int fare) {
    if (coupon == null || fare <= 0) return 0;
    final minRaw = coupon['min_order_amount'];
    final min = minRaw is num ? minRaw.round() : int.tryParse('$minRaw') ?? 0;
    if (min > 0 && fare < min) return 0;
    final amountRaw = coupon['amount'];
    final amount = amountRaw is num ? amountRaw.toDouble() : double.tryParse('$amountRaw') ?? 0;
    if (amount <= 0) return 0;
    final type = (coupon['type'] ?? '').toString();
    if (type == 'percentage') {
      final pct = amount > 100 ? 100.0 : amount;
      return (fare * pct / 100).round().clamp(0, fare);
    }
    return amount.round().clamp(0, fare);
  }

  void setAppliedCoupon(Map<String, dynamic>? coupon) {
    final code = (coupon?['code'] ?? '').toString().trim();
    appliedCoupon = code.isEmpty ? null : Map<String, dynamic>.from(coupon!);
    notifyListeners();
  }

  void setPickup({
    required double lat,
    required double lng,
    required String address,
  }) {
    pickupLat = lat;
    pickupLng = lng;
    pickupAddress = address;
    notifyListeners();
  }

  void clearPickup() {
    pickupLat = null;
    pickupLng = null;
    pickupAddress = '';
    notifyListeners();
  }

  void setDrop({
    required double lat,
    required double lng,
    required String address,
  }) {
    dropLat = lat;
    dropLng = lng;
    dropAddress = address;
    notifyListeners();
  }

  void clearDrop() {
    dropLat = null;
    dropLng = null;
    dropAddress = '';
    notifyListeners();
  }

  void setContact({required String name, required String phone}) {
    selectedContactName = name.trim().isEmpty ? 'For me' : name.trim();
    selectedContactPhone = phone.trim();
    notifyListeners();
  }

  void setOfferFare(int fare) {
    offerFare = fare;
    notifyListeners();
  }

  void setBaseFare(int fare) {
    baseFare = fare;
    if (offerFare < baseFare) {
      offerFare = baseFare;
    }
    notifyListeners();
  }

  void setSelectedVehicleTypeId(String? id) {
    selectedVehicleTypeId = (id ?? '').trim().isEmpty ? null : id;
    notifyListeners();
  }

  void addStop() {
    stops.add('');
    notifyListeners();
  }

  void updateStop(int index, String value) {
    if (index < 0 || index >= stops.length) return;
    stops[index] = value;
    notifyListeners();
  }

  void removeStop(int index) {
    if (index < 0 || index >= stops.length) return;
    stops.removeAt(index);
    notifyListeners();
  }
}
