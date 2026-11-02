import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/services/api_service.dart';

bool _sessionNameIsPhone(String value) {
  final compact = value.replaceAll(RegExp(r'\s'), '');
  final digits = compact.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 8 && digits.length >= compact.length - 2;
}

String _sessionPersonName(Map data) {
  const keys = ['fullName', 'full_name', 'driver_name', 'driverName', 'name', 'username'];
  for (final key in keys) {
    final value = (data[key] ?? '').toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') continue;
    if (!_sessionNameIsPhone(value)) return value;
  }
  return '';
}

class SessionService {
  static const String _tokenKey = 'user_token';
  static const String _mobileKey = 'user_mobile';
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _onboardingCompletedKey = 'onboarding_completed';
  static const String _disclaimerAcceptedKey = 'disclaimer_accepted';
  static const String _locationGrantedKey = 'location_permission_granted';
  static const String _profileImageUrlKey = 'user_profile_image_url';
  static const String _profileImageLockedKey = 'user_profile_image_locked';
  static const String _driverIdKey = 'driver_id';
  static const String _walletBalanceKey = 'driver_wallet_balance';
  static const String _vehicleStatusKey = 'vehicle_registration_status';
  static const String _vehicleReadOnlyKey = 'vehicle_registration_read_only';
  static const String _vehicleNumberKey = 'vehicle_number';
  static const String _vehicleTypeKey = 'vehicle_type';
  static const String _vehicleColorKey = 'vehicle_color';
  static const String _vehicleSubmittedKey = 'vehicle_submitted';
  static const String _vehicleRcImagePathKey = 'vehicle_rc_image_path';

  static const String _bankAccountKey = 'bank_account';
  static const String _bankNameKey = 'bank_name';
  static const String _bankHolderKey = 'bank_holder';
  static const String _bankIfscKey = 'bank_ifsc';
  static const String _bankEmailKey = 'bank_email';
  static const String _bankPayoutMethodKey = 'payout_method';
  static const String _bankStatusKey = 'bank_status';
  static const String _bankSubmittedKey = 'bank_submitted';

  const SessionService();

  Future<void> saveVehicleRegistrationStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vehicleStatusKey, status.trim());
  }

  Future<String> getVehicleRegistrationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_vehicleStatusKey) ?? 'not_submitted').trim();
  }

  Future<void> saveVehicleRegistrationReadOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vehicleReadOnlyKey, value);
  }

  Future<bool> getVehicleRegistrationReadOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vehicleReadOnlyKey) ?? false;
  }

  Future<void> saveVehicleNumber(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vehicleNumberKey, value.trim());
  }

  Future<String> getVehicleNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_vehicleNumberKey) ?? '').trim();
  }

  Future<void> saveVehicleType(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vehicleTypeKey, value.trim());
  }

  Future<String> getVehicleType() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_vehicleTypeKey) ?? '').trim();
  }

  Future<void> saveVehicleColor(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vehicleColorKey, value.trim());
  }

  Future<String> getVehicleColor() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_vehicleColorKey) ?? '').trim();
  }

  Future<void> saveVehicleSubmitted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vehicleSubmittedKey, value);
  }

  Future<bool> getVehicleSubmitted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vehicleSubmittedKey) ?? false;
  }

  Future<void> saveVehicleRcImagePath(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      await prefs.remove(_vehicleRcImagePathKey);
      return;
    }
    await prefs.setString(_vehicleRcImagePathKey, v);
  }

  Future<String> getVehicleRcImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_vehicleRcImagePathKey) ?? '').trim();
  }

  Future<void> saveBankAccount(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bankAccountKey, value.trim());
  }

  Future<String> getBankAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_bankAccountKey) ?? '').trim();
  }

  Future<void> saveBankName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bankNameKey, value.trim());
  }

  Future<String> getBankName() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_bankNameKey) ?? '').trim();
  }

  Future<void> saveBankHolderName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bankHolderKey, value.trim());
  }

  Future<String> getBankHolderName() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_bankHolderKey) ?? '').trim();
  }

  Future<void> saveBankIfsc(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bankIfscKey, value.trim());
  }

  Future<String> getBankIfsc() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_bankIfscKey) ?? '').trim();
  }

  Future<void> saveBankEmail(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bankEmailKey, value.trim());
  }

  Future<String> getBankEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_bankEmailKey) ?? '').trim();
  }

  Future<void> saveBankPayoutMethod(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bankPayoutMethodKey, value.trim());
  }

  Future<String> getBankPayoutMethod() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_bankPayoutMethodKey) ?? 'bank_transfer').trim();
  }

  Future<void> saveBankStatus(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bankStatusKey, value.trim());
  }

  Future<String> getBankStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_bankStatusKey) ?? 'not_submitted').trim();
  }

  Future<void> saveBankSubmitted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bankSubmittedKey, value);
  }

  Future<bool> getBankSubmitted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_bankSubmittedKey) ?? false;
  }

  Future<void> saveLoginSession({
    required String token,
    required String mobile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_mobileKey, mobile);
    await prefs.setBool(_isLoggedInKey, true);
  }

  Future<void> saveDriverId(String driverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverIdKey, driverId);
  }

  Future<String?> getDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_driverIdKey);
  }

  String _paymentPopupKey(String rideId) => 'payment_popup_shown_${rideId.trim()}';

  Future<bool> getPaymentPopupShown({required String rideId}) async {
    final id = rideId.trim();
    if (id.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_paymentPopupKey(id)) ?? false;
  }

  Future<void> setPaymentPopupShown({required String rideId, required bool value}) async {
    final id = rideId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_paymentPopupKey(id), value);
  }

  Future<void> saveWalletBalance(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_walletBalanceKey, value);
  }

  Future<double> getWalletBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_walletBalanceKey) ?? 0.0;
  }

  Future<bool> getIsLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  Future<String?> getMobile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mobileKey);
  }

  Future<void> setOnboardingCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, value);
  }

  Future<bool> getOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompletedKey) ?? false;
  }

  Future<void> setDisclaimerAccepted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_disclaimerAcceptedKey, value);
  }

  Future<bool> getDisclaimerAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_disclaimerAcceptedKey) ?? false;
  }

  Future<void> setLocationPermissionGranted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationGrantedKey, value);
  }

  Future<bool> getLocationPermissionGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_locationGrantedKey) ?? false;
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> saveProfileImageUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeProfileImageUrl(url);
    await prefs.setString(_profileImageUrlKey, normalized);
    if (normalized.trim().isNotEmpty) {
      await prefs.setBool(_profileImageLockedKey, true);
    }
  }

  Future<void> saveProfileImageLocked(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_profileImageLockedKey, value);
  }

  Future<bool> getProfileImageLocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_profileImageLockedKey) ?? false;
  }

  Future<String?> getProfileImageUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_profileImageUrlKey);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Map<String, dynamic> _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return <String, dynamic>{};
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final dynamic jsonMap = jsonDecode(decoded);
      if (jsonMap is Map<String, dynamic>) return jsonMap;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _normalizeProfileImageUrl(dynamic value) {
    final raw = (value ?? '').toString().trim();
    final lowered = raw.toLowerCase();
    if (raw.isEmpty) return '';
    if (lowered == 'null' || lowered == 'undefined' || lowered == 'none' || lowered == 'na' || lowered == 'n/a') {
      return '';
    }

    final origin = Uri.parse(baseUrl).origin;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw.replaceFirst(RegExp(r'^http://adm\.vitevikle\.com', caseSensitive: false), 'https://adm.vitevikle.com');
    }
    if (raw.startsWith('/')) return '$origin$raw';
    if (raw.contains('/uploads/')) return '$origin/$raw';

    final looksLikeFile = raw.contains('.') && !raw.contains(' ');
    if (looksLikeFile) {
      return '$origin/uploads/profile/$raw';
    }

    return '$origin/uploads/profile/$raw';
  }

  Future<void> updateCachedUserBasics(Map<String, dynamic> data) async {
    final token = await getToken();
    final payload = token == null ? <String, dynamic>{} : _decodeJwtPayload(token);
    final prefs = await SharedPreferences.getInstance();
    final current = <String, dynamic>{};
    final cachedRaw = prefs.getString('driver_cached_user_basics');
    if (cachedRaw != null && cachedRaw.trim().isNotEmpty) {
      try {
        final dynamic cachedDecoded = jsonDecode(cachedRaw);
        if (cachedDecoded is Map) current.addAll(Map<String, dynamic>.from(cachedDecoded));
      } catch (_) {}
    }
    final merged = <String, String>{
      'id': (data['id'] ?? data['_id'] ?? data['driverId'] ?? current['id'] ?? payload['id'] ?? payload['driverId'] ?? '').toString(),
      'name': (data['name'] ?? data['fullName'] ?? data['username'] ?? current['name'] ?? payload['name'] ?? '').toString(),
      'email': (data['email'] ?? current['email'] ?? payload['email'] ?? '').toString(),
      'mobile': (data['mobile'] ?? data['phone'] ?? current['mobile'] ?? payload['mobile'] ?? '').toString(),
      'dateOfBirth': (data['dateOfBirth'] ?? data['dob'] ?? current['dateOfBirth'] ?? payload['dateOfBirth'] ?? '').toString(),
      'imageUrl': _normalizeProfileImageUrl(data['image'] ?? data['image_url'] ?? data['imageUrl'] ?? data['profile_image'] ?? current['imageUrl'] ?? ''),
    };

    await prefs.setString('driver_cached_user_basics', jsonEncode(merged));
    if (merged['imageUrl']!.trim().isNotEmpty) {
      await saveProfileImageUrl(merged['imageUrl']!);
    }
  }

  Future<Map<String, String>> getUserBasics({bool forceRefresh = false}) async {
    String? token = await getToken();
    Map<String, dynamic> payload = token == null ? <String, dynamic>{} : _decodeJwtPayload(token);

    String id = (payload['id'] ?? payload['_id'] ?? payload['user_id'] ?? payload['userId'] ?? payload['driverId'] ?? '').toString();
    String name = (payload['name'] ?? payload['fullName'] ?? payload['username'] ?? '').toString();
    String email = (payload['email'] ?? '').toString();
    String imageUrl = _normalizeProfileImageUrl(await getProfileImageUrl());
    String dateOfBirth = (payload['dateOfBirth'] ?? payload['dob'] ?? '').toString();
    String cachedMobile = '';

    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh) {
      final cachedRaw = prefs.getString('driver_cached_user_basics');
      if (cachedRaw != null && cachedRaw.trim().isNotEmpty) {
        try {
          final dynamic cachedDecoded = jsonDecode(cachedRaw);
          if (cachedDecoded is Map) {
            final cached = Map<String, dynamic>.from(cachedDecoded);
            id = (cached['id'] ?? id).toString();
            name = (cached['name'] ?? name).toString();
            email = (cached['email'] ?? email).toString();
            dateOfBirth = (cached['dateOfBirth'] ?? dateOfBirth).toString();
            cachedMobile = (cached['mobile'] ?? '').toString();
            imageUrl = _normalizeProfileImageUrl(cached['imageUrl'] ?? imageUrl);
          }
        } catch (_) {}
      }
    }

    String mobile = '';
    final rawMobile = payload['mobile'] ?? payload['phone'];
    if (rawMobile != null) mobile = rawMobile.toString();
    if (mobile.trim().isEmpty) {
      mobile = cachedMobile.trim().isNotEmpty ? cachedMobile : ((await getMobile()) ?? '');
    }

    final needsHydration = name.trim().isEmpty || _sessionNameIsPhone(name) || (mobile.trim().isEmpty) || (email.trim().isEmpty) || id.trim().isEmpty;

    if ((forceRefresh || needsHydration) && token != null && token.trim().isNotEmpty) {
      final profile = await const ApiService().getDriverProfile(token: token.trim());
      final driverData = profile['data'];
      if (profile['success'] == true && driverData is Map) {
        final m = Map<String, dynamic>.from(driverData);
        final dynamic maybeId = m['id'] ?? m['_id'] ?? m['driverId'];
        final pickedName = _sessionPersonName(m);
        final dynamic maybeEmail = m['email'];
        final dynamic maybePhone = m['phone'] ?? m['mobile'];
        final dynamic maybeDateOfBirth = m['dateOfBirth'] ?? m['dob'];
        final dynamic maybeImage = m['image'] ?? m['image_url'] ?? m['imageUrl'] ?? m['profile_image'] ?? m['avatar'];

        if (maybeId != null && maybeId.toString().trim().isNotEmpty) id = maybeId.toString();
        if (pickedName.isNotEmpty) name = pickedName;
        if (maybeEmail != null && maybeEmail.toString().trim().isNotEmpty) email = maybeEmail.toString();
        if (maybePhone != null && maybePhone.toString().trim().isNotEmpty) mobile = maybePhone.toString();
        if (maybeDateOfBirth != null && maybeDateOfBirth.toString().trim().isNotEmpty && maybeDateOfBirth.toString() != 'null') dateOfBirth = maybeDateOfBirth.toString();
        imageUrl = _normalizeProfileImageUrl(maybeImage);
        await updateCachedUserBasics({
          'id': id,
          'name': name,
          'email': email,
          'mobile': mobile,
          'dateOfBirth': dateOfBirth,
          'imageUrl': imageUrl,
        });
        return {
          'id': id,
          'name': name,
          'email': email,
          'mobile': mobile,
          'dateOfBirth': dateOfBirth,
          'imageUrl': imageUrl,
        };
      }
    }

    if ((forceRefresh || needsHydration) && mobile.trim().isNotEmpty) {
      final details = await const ApiService().checkUserDetails(mobile.trim(), token: token);

      final newToken = details['token'];
      if (newToken is String && newToken.trim().isNotEmpty) {
        await saveToken(newToken.trim());
        token = newToken.trim();
      }

      final user = details['user'];
      if (user is Map) {
        final m = Map<String, dynamic>.from(user);
        final dynamic maybeId = m['id'] ?? m['_id'] ?? m['user_id'] ?? m['userId'];
        final pickedName = _sessionPersonName(m);
        final dynamic maybeEmail = m['email'];
        final dynamic maybePhone = m['phone'] ?? m['mobile'];
        final dynamic maybeDateOfBirth = m['dateOfBirth'] ?? m['dob'];
        final dynamic maybeImage = m['image'] ?? m['profile_image'] ?? m['avatar'] ?? m['user_image'];

        if (maybeId != null && maybeId.toString().trim().isNotEmpty) id = maybeId.toString();
        if (pickedName.isNotEmpty && (_sessionNameIsPhone(name) || name.trim().isEmpty)) name = pickedName;
        if (maybeEmail != null && maybeEmail.toString().trim().isNotEmpty) email = maybeEmail.toString();
        if (maybePhone != null && maybePhone.toString().trim().isNotEmpty) mobile = maybePhone.toString();
        if (maybeDateOfBirth != null && maybeDateOfBirth.toString().trim().isNotEmpty && maybeDateOfBirth.toString() != 'null') dateOfBirth = maybeDateOfBirth.toString();
        imageUrl = _normalizeProfileImageUrl(maybeImage);
        if (imageUrl.trim().isNotEmpty) {
          await saveProfileImageUrl(imageUrl.trim());
        }
      } else if (token != null && token.trim().isNotEmpty) {
        payload = _decodeJwtPayload(token);
        id = (payload['id'] ?? payload['_id'] ?? payload['user_id'] ?? payload['userId'] ?? payload['driverId'] ?? '').toString();
        name = (payload['name'] ?? payload['fullName'] ?? payload['username'] ?? '').toString();
        email = (payload['email'] ?? '').toString();
        final newMobile = payload['mobile'] ?? payload['phone'];
        if (newMobile != null && newMobile.toString().trim().isNotEmpty) {
          mobile = newMobile.toString();
        }
      }
    }

    return {
      'id': id,
      'name': name,
      'email': email,
      'mobile': mobile,
      'dateOfBirth': dateOfBirth,
      'imageUrl': imageUrl,
    };
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_mobileKey);
    await prefs.remove(_isLoggedInKey);
    await prefs.remove(_profileImageUrlKey);
    await prefs.remove('driver_cached_user_basics');
    await prefs.remove(_profileImageLockedKey);
    await prefs.remove(_driverIdKey);
    await prefs.remove(_walletBalanceKey);
    await prefs.remove(_vehicleStatusKey);
    await prefs.remove(_vehicleReadOnlyKey);
    await prefs.remove(_vehicleNumberKey);
    await prefs.remove(_vehicleTypeKey);
    await prefs.remove(_vehicleColorKey);
    await prefs.remove(_vehicleSubmittedKey);
    await prefs.remove(_vehicleRcImagePathKey);
    await prefs.remove(_bankAccountKey);
    await prefs.remove(_bankNameKey);
    await prefs.remove(_bankHolderKey);
    await prefs.remove(_bankIfscKey);
    await prefs.remove(_bankEmailKey);
    await prefs.remove(_bankPayoutMethodKey);
    await prefs.remove(_bankStatusKey);
    await prefs.remove(_bankSubmittedKey);
  }

  Future<void> logout() async {
    await clearSession();
    await FirebaseAuth.instance.signOut();
  }
}

