import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/models/intercity_request.dart';

/// Live ride and intercity offers the Trips tab can accept or ignore.
class OfferInbox {
  static final city = ValueNotifier<List<Map<String, dynamic>>>(const []);
  static final intercity = ValueNotifier<List<IntercityRequestModel>>(const []);
  static final ignoredIds = <String>{};

  static void setCity(List<Map<String, dynamic>> items) {
    city.value = List<Map<String, dynamic>>.unmodifiable(
      items.where((item) {
        final id = (item['_id'] ?? item['id'] ?? '').toString().trim();
        return id.isNotEmpty && !ignoredIds.contains(id);
      }),
    );
  }

  static void setIntercity(List<IntercityRequestModel> items) {
    intercity.value = List<IntercityRequestModel>.unmodifiable(
      items.where((item) => item.id.trim().isNotEmpty && !ignoredIds.contains(item.id.trim())),
    );
  }

  static void hide(String id) {
    final key = id.trim();
    if (key.isEmpty) return;
    city.value = List<Map<String, dynamic>>.unmodifiable(
      city.value.where((item) {
        final itemId = (item['_id'] ?? item['id'] ?? item['ride_id'] ?? '').toString().trim();
        return itemId != key;
      }),
    );
    intercity.value = List<IntercityRequestModel>.unmodifiable(
      intercity.value.where((item) => item.id.trim() != key),
    );
  }

  static Future<void> _saveChain = Future<void>.value();

  static void _saveIgnored() {
    _saveChain = _saveChain.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('offer_ignored_ids', ignoredIds.toList());
    });
  }

  static void release(String id) {
    final key = id.trim();
    if (key.isEmpty) return;
    ignoredIds.remove(key);
    _saveIgnored();
  }

  static void ignore(String id) {
    final key = id.trim();
    if (key.isEmpty) return;
    ignoredIds.add(key);
    setCity(List<Map<String, dynamic>>.from(city.value));
    setIntercity(List<IntercityRequestModel>.from(intercity.value));
    _saveIgnored();
  }

  static Future<void> loadIgnored() async {
    final prefs = await SharedPreferences.getInstance();
    ignoredIds.addAll(prefs.getStringList('offer_ignored_ids') ?? const <String>[]);
    setCity(List<Map<String, dynamic>>.from(city.value));
    setIntercity(List<IntercityRequestModel>.from(intercity.value));
  }
}
