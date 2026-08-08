import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParcelActivityState extends ChangeNotifier {
  static const String _prefsKey = 'parcel_cancelled_cache_v1';
  final List<Map<String, dynamic>> _cancelledParcels = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get cancelledParcels => List<Map<String, dynamic>>.unmodifiable(_cancelledParcels);

  String _idOf(Map<String, dynamic> parcel) {
    return (parcel['_id'] ?? parcel['id'] ?? '').toString().trim();
  }

  Future<void> hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey) ?? '';
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final next = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (next.isEmpty) return;
      _cancelledParcels
        ..clear()
        ..addAll(next);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_cancelledParcels));
    } catch (_) {}
  }

  void upsertCancelled(Map<String, dynamic> parcel) {
    final id = _idOf(parcel);
    if (id.isEmpty) return;

    final idx = _cancelledParcels.indexWhere((e) => _idOf(e) == id);
    final normalized = <String, dynamic>{
      ...parcel,
      'status': (parcel['status'] ?? 'CANCELLED').toString(),
    };

    if (idx >= 0) {
      _cancelledParcels[idx] = normalized;
    } else {
      _cancelledParcels.insert(0, normalized);
    }
    notifyListeners();
    _persist();
  }

  void clear() {
    if (_cancelledParcels.isEmpty) return;
    _cancelledParcels.clear();
    notifyListeners();
    _persist();
  }
}
