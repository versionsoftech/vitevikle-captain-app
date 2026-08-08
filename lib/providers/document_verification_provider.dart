import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/services/api_service.dart';

class DriverDocumentConfig {
  final String id;
  final String name;
  final String? key;
  final String type;
  final bool isRequired;
  final bool isFrontImageRequired;
  final bool isBackImageRequired;
  final bool isSelfieRequired;
  final bool isDocumentNumberRequired;
  final bool needExpiredDate;
  final String? validationRegex;
  final String? placeholder;

  DriverDocumentConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.key,
    required this.isRequired,
    required this.isFrontImageRequired,
    required this.isBackImageRequired,
    required this.isSelfieRequired,
    required this.isDocumentNumberRequired,
    required this.needExpiredDate,
    required this.validationRegex,
    required this.placeholder,
  });

  static bool _boolish(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'yes') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return false;
  }

  factory DriverDocumentConfig.fromJson(Map<String, dynamic> json) {
    return DriverDocumentConfig(
      id: (json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      key: json['key']?.toString(),
      isRequired: _boolish(json['is_required']),
      isFrontImageRequired: _boolish(json['is_front_image_required']),
      isBackImageRequired: _boolish(json['is_back_image_required']),
      isSelfieRequired: _boolish(json['is_selfie_required']),
      isDocumentNumberRequired: _boolish(json['is_document_number_required']),
      needExpiredDate: _boolish(json['need_expired_date']),
      validationRegex: json['validation_regex']?.toString(),
      placeholder: json['placeholder']?.toString(),
    );
  }
}

enum DocumentStatus {
  pending,
  approved,
  rejected,
}

class DocumentVerificationProvider extends ChangeNotifier {
  static const String _storageKey = 'driver_document_verification_state_v1';
  static const String _dynamicStorageKey = 'driver_document_verification_dynamic_state_v1';

  bool _hydrated = false;

  bool _loadingConfigs = false;
  String? _configError;
  List<DriverDocumentConfig> _configs = const [];

  bool get loadingConfigs => _loadingConfigs;
  String? get configError => _configError;
  List<DriverDocumentConfig> get configs => _configs;

  String? aadharFront;
  String? aadharBack;
  String? aadharSelfie;
  String aadharNumber = '';

  String? panImage;
  String? panSelfie;
  String panNumber = '';

  String? licenseFront;
  String? licenseBack;
  String? licenseSelfie;
  String licenseNumber = '';
  String licenseExpiry = '';

  String? voterFront;
  String? voterBack;
  String? voterSelfie;
  String voterIdNumber = '';

  DocumentStatus get aadharStatus => _isAadharComplete ? DocumentStatus.approved : DocumentStatus.pending;
  DocumentStatus get panStatus => _isPanComplete ? DocumentStatus.approved : DocumentStatus.pending;
  DocumentStatus get licenseStatus => _isLicenseComplete ? DocumentStatus.approved : DocumentStatus.pending;
  DocumentStatus get voterStatus => _isVoterComplete ? DocumentStatus.approved : DocumentStatus.pending;

  bool get isAllDocumentsApproved =>
      aadharStatus == DocumentStatus.approved &&
      panStatus == DocumentStatus.approved &&
      licenseStatus == DocumentStatus.approved &&
      voterStatus == DocumentStatus.approved;

  bool get hydrated => _hydrated;

  final Map<String, Map<String, dynamic>> _dynamicStates = {};

  bool _loadingServerDocs = false;
  String? _serverDocsError;
  final Map<String, String> _serverStatusByDocumentId = {};

  bool get loadingServerDocs => _loadingServerDocs;
  String? get serverDocsError => _serverDocsError;

  Map<String, dynamic> getDynamicState(String documentKey) {
    final k = documentKey.trim().toLowerCase();
    return _dynamicStates[k] ?? <String, dynamic>{};
  }

  Future<void> updateDynamicState(
    String documentKey, {
    String? frontImagePath,
    String? backImagePath,
    String? selfieImagePath,
    String? documentNumber,
    String? expiryDate,
  }) async {
    final k = documentKey.trim().toLowerCase();
    final current = Map<String, dynamic>.from(_dynamicStates[k] ?? <String, dynamic>{});

    if (frontImagePath != null) current['front_image'] = frontImagePath;
    if (backImagePath != null) current['back_image'] = backImagePath;
    if (selfieImagePath != null) current['selfie_image'] = selfieImagePath;
    if (documentNumber != null) current['document_number'] = documentNumber;
    if (expiryDate != null) current['expiry_date'] = expiryDate;

    _dynamicStates[k] = current;
    await _persistDynamic();
    notifyListeners();
  }

  DocumentStatus getStatusForConfig(DriverDocumentConfig config) {
    return isCompleteForConfig(config) ? DocumentStatus.approved : DocumentStatus.pending;
  }

  DocumentStatus getServerStatusForConfig(DriverDocumentConfig config) {
    final id = config.id.trim();
    final raw = (_serverStatusByDocumentId[id] ?? '').trim().toLowerCase();
    if (raw == 'approved') return DocumentStatus.approved;
    if (raw == 'rejected') return DocumentStatus.rejected;
    return DocumentStatus.pending;
  }

  bool get isAllDocumentsApprovedFromServer {
    if (_configs.isEmpty) return false;
    return _configs.every((c) => getServerStatusForConfig(c) == DocumentStatus.approved);
  }

  Future<void> refreshServerStatuses({required String driverId}) async {
    if (_loadingServerDocs) return;
    _loadingServerDocs = true;
    _serverDocsError = null;
    notifyListeners();

    final result = await const ApiService().getDriverDocumentsTableByDriver(driverId);
    if (result['success'] == true && result['data'] is List) {
      _serverStatusByDocumentId.clear();
      for (final item in (result['data'] as List)) {
        if (item is Map<String, dynamic>) {
          final docId = (item['document_id'] ?? '').toString().trim();
          final st = (item['status'] ?? '').toString().trim().toLowerCase();
          if (docId.isNotEmpty) {
            _serverStatusByDocumentId[docId] = st.isEmpty ? 'pending' : st;
          }
        }
      }
    } else {
      _serverDocsError = (result['message'] ?? 'Failed to load document status').toString();
    }

    _loadingServerDocs = false;
    notifyListeners();
  }

  bool isCompleteForConfig(DriverDocumentConfig config) {
    if (!config.isRequired) return true;

    final docKey = (config.key ?? config.id).toLowerCase().trim();
    final state = getDynamicState(docKey);

    final front = (state['front_image'] ?? '').toString().trim();
    final back = (state['back_image'] ?? '').toString().trim();
    final selfie = (state['selfie_image'] ?? '').toString().trim();
    final number = (state['document_number'] ?? '').toString().trim();
    final expiry = (state['expiry_date'] ?? '').toString().trim();

    if (config.isFrontImageRequired && front.isEmpty) return false;
    if (config.isBackImageRequired && back.isEmpty) return false;
    if (config.isSelfieRequired && selfie.isEmpty) return false;

    if (config.isDocumentNumberRequired) {
      if (number.isEmpty) return false;
      final regex = (config.validationRegex ?? '').trim();
      if (regex.isNotEmpty) {
        try {
          if (!RegExp(regex).hasMatch(number)) return false;
        } catch (_) {
          // ignore invalid regex and fall back to non-empty
        }
      }
    }

    if (config.needExpiredDate && expiry.isEmpty) return false;

    return true;
  }

  bool get _isAadharComplete {
    final digits = aadharNumber.replaceAll(RegExp(r'\D'), '');
    return (aadharFront ?? '').isNotEmpty &&
        (aadharBack ?? '').isNotEmpty &&
        (aadharSelfie ?? '').isNotEmpty &&
        RegExp(r'^\d{12}$').hasMatch(digits);
  }

  bool get _isPanComplete {
    final v = panNumber.trim().toUpperCase();
    return (panImage ?? '').isNotEmpty &&
        (panSelfie ?? '').isNotEmpty &&
        RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(v);
  }

  bool get _isLicenseComplete {
    return (licenseFront ?? '').isNotEmpty &&
        (licenseBack ?? '').isNotEmpty &&
        (licenseSelfie ?? '').isNotEmpty &&
        licenseNumber.trim().isNotEmpty &&
        licenseExpiry.trim().isNotEmpty;
  }

  bool get _isVoterComplete {
    return (voterFront ?? '').isNotEmpty &&
        (voterBack ?? '').isNotEmpty &&
        (voterSelfie ?? '').isNotEmpty &&
        voterIdNumber.trim().isNotEmpty;
  }

  Future<void> hydrate() async {
    if (_hydrated) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final dynamicRaw = prefs.getString(_dynamicStorageKey);
    if (raw == null || raw.trim().isEmpty) {
      // still try dynamic state
    }

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;

        aadharFront = data['aadharFront'] as String?;
        aadharBack = data['aadharBack'] as String?;
        aadharSelfie = data['aadharSelfie'] as String?;
        aadharNumber = (data['aadharNumber'] as String?) ?? '';

        panImage = data['panImage'] as String?;
        panSelfie = data['panSelfie'] as String?;
        panNumber = (data['panNumber'] as String?) ?? '';

        licenseFront = data['licenseFront'] as String?;
        licenseBack = data['licenseBack'] as String?;
        licenseSelfie = data['licenseSelfie'] as String?;
        licenseNumber = (data['licenseNumber'] as String?) ?? '';
        licenseExpiry = (data['licenseExpiry'] as String?) ?? '';

        voterFront = data['voterFront'] as String?;
        voterBack = data['voterBack'] as String?;
        voterSelfie = data['voterSelfie'] as String?;
        voterIdNumber = (data['voterIdNumber'] as String?) ?? '';
      } catch (_) {
        // ignore corrupted state
      }
    }

    if (dynamicRaw != null && dynamicRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(dynamicRaw);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final k = entry.key.toString().trim().toLowerCase();
            final v = entry.value;
            if (v is Map<String, dynamic>) {
              _dynamicStates[k] = Map<String, dynamic>.from(v);
            }
          }
        }
      } catch (_) {
        // ignore corrupted state
      }
    }

    _hydrated = true;
    notifyListeners();
  }

  Future<void> loadConfigs() async {
    if (_loadingConfigs) return;
    _loadingConfigs = true;
    _configError = null;
    notifyListeners();

    final result = await const ApiService().getDriverDocumentConfigs();
    if (result['success'] == true && result['data'] is List) {
      final list = (result['data'] as List)
          .whereType<dynamic>()
          .map((e) => e is Map<String, dynamic> ? DriverDocumentConfig.fromJson(e) : null)
          .whereType<DriverDocumentConfig>()
          .toList();
      _configs = list;
    } else {
      _configs = const [];
      _configError = (result['message'] ?? 'Failed to load documents').toString();
    }

    _loadingConfigs = false;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'aadharFront': aadharFront,
      'aadharBack': aadharBack,
      'aadharSelfie': aadharSelfie,
      'aadharNumber': aadharNumber,
      'panImage': panImage,
      'panSelfie': panSelfie,
      'panNumber': panNumber,
      'licenseFront': licenseFront,
      'licenseBack': licenseBack,
      'licenseSelfie': licenseSelfie,
      'licenseNumber': licenseNumber,
      'licenseExpiry': licenseExpiry,
      'voterFront': voterFront,
      'voterBack': voterBack,
      'voterSelfie': voterSelfie,
      'voterIdNumber': voterIdNumber,
    };
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  Future<void> _persistDynamic() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dynamicStorageKey, jsonEncode(_dynamicStates));
  }

  Future<void> updateAadhar({
    String? front,
    String? back,
    String? selfie,
    String? number,
  }) async {
    aadharFront = front ?? aadharFront;
    aadharBack = back ?? aadharBack;
    aadharSelfie = selfie ?? aadharSelfie;
    aadharNumber = number ?? aadharNumber;
    await _persist();
    notifyListeners();
  }

  Future<void> updatePan({
    String? image,
    String? selfie,
    String? number,
  }) async {
    panImage = image ?? panImage;
    panSelfie = selfie ?? panSelfie;
    panNumber = number ?? panNumber;
    await _persist();
    notifyListeners();
  }

  Future<void> updateLicense({
    String? front,
    String? back,
    String? selfie,
    String? number,
    String? expiry,
  }) async {
    licenseFront = front ?? licenseFront;
    licenseBack = back ?? licenseBack;
    licenseSelfie = selfie ?? licenseSelfie;
    licenseNumber = number ?? licenseNumber;
    licenseExpiry = expiry ?? licenseExpiry;
    await _persist();
    notifyListeners();
  }

  Future<void> updateVoter({
    String? front,
    String? back,
    String? selfie,
    String? voterId,
  }) async {
    voterFront = front ?? voterFront;
    voterBack = back ?? voterBack;
    voterSelfie = selfie ?? voterSelfie;
    voterIdNumber = voterId ?? voterIdNumber;
    await _persist();
    notifyListeners();
  }
}

