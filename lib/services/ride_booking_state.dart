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
