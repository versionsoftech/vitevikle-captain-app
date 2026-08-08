import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsProvider extends ChangeNotifier {
  static const _keyDarkMode = 'isDarkMode';
  static const _keyLanguage = 'app_language';

  bool _loaded = false;
  bool _isDarkMode = false;
  Locale _locale = const Locale('en');

  bool get loaded => _loaded;
  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => ThemeMode.light;
  Locale get locale => _locale;

  AppSettingsProvider() {
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = false; // force light
      final code = (prefs.getString(_keyLanguage) ?? 'en').trim();
      _locale = Locale(_normalizeLanguageCode(code));
    } catch (_) {
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  String _normalizeLanguageCode(String code) {
    switch (code.toLowerCase()) {
      case 'hi':
      case 'hindi':
        return 'hi';
      case 'pa':
      case 'punjabi':
        return 'pa';
      case 'en':
      case 'english':
      default:
        return 'en';
    }
  }

  String get languageLabel {
    switch (_locale.languageCode) {
      case 'hi':
        return 'Hindi';
      case 'pa':
        return 'Punjabi';
      case 'en':
      default:
        return 'English';
    }
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = false; // ignore and force light
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDarkMode, false);
    } catch (_) {}
  }

  Future<void> setLanguage(String languageCode) async {
    _locale = Locale(_normalizeLanguageCode(languageCode));
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLanguage, _locale.languageCode);
    } catch (_) {}
  }
}
