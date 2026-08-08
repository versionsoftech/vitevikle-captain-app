import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';

class VehicleRegistrationScreen extends StatefulWidget {
  const VehicleRegistrationScreen({super.key});

  @override
  State<VehicleRegistrationScreen> createState() => _VehicleRegistrationScreenState();
}

class _VehicleRegistrationScreenState extends State<VehicleRegistrationScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _bg = Color(0xFFF6F7F9);

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _vehicleNumberController = TextEditingController();
  int? _selectedSeatCapacity;
  File? _rcImage;
  File? _vehicleFrontImage;
  File? _vehicleBackImage;
  File? _vehicleSideImage;
  File? _driverVehicleJointImage;

  bool isVehicleExists = false;
  Map<String, dynamic>? _vehicleData;
  String _vehicleStatus = 'not_submitted';
  bool _hydratingStatus = false;

  String? _serverVehicleTypeId;
  String? _serverBrandId;
  String? _serverModelId;
  String? _serverModelYear;
  String? _serverColorId;
  String? _serverFuelType;

  static const SessionService _sessionService = SessionService();

  final Set<String> _selectedServices = <String>{};

  bool _loadingVehicleTypes = false;
  bool _loadingBrands = false;
  bool _loadingModels = false;
  bool _loadingModelYears = false;
  bool _loadingColors = false;
  bool _loadingFuelTypes = false;
  bool _submitting = false;

  List<Map<String, String>> _vehicleTypes = <Map<String, String>>[];
  List<Map<String, String>> _brands = <Map<String, String>>[];
  List<Map<String, String>> _models = <Map<String, String>>[];
  List<Map<String, String>> _modelYears = <Map<String, String>>[];
  List<Map<String, String>> _colors = <Map<String, String>>[];

  Map<String, String>? _selectedVehicleType;
  Map<String, String>? _selectedBrand;
  Map<String, String>? _selectedModel;
  Map<String, String>? _selectedModelYear;
  Map<String, String>? _selectedColor;
  String? _selectedFuelType;

  String? _serviceError;

  List<Map<String, String>> _fuelTypes = <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    _fetchVehicleInfo();
    _loadVehicleTypes();
    _loadModelYears();
    _loadColors();
    _loadFuelTypes();
  }

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<ImageSource?> _askImageSource() async {
    if (!mounted) return null;
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<File?> _pickImageAnySource() async {
    final source = await _askImageSource();
    if (source == null) return null;
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: source, imageQuality: 75);
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<void> _pickVehicleImage(String key) async {
    if (isVehicleExists) return;
    final file = await _pickImageAnySource();
    if (file == null) return;
    if (!mounted) return;

    setState(() {
      switch (key) {
        case 'vehicle_front_image':
          _vehicleFrontImage = file;
          break;
        case 'vehicle_back_image':
          _vehicleBackImage = file;
          break;
        case 'vehicle_side_image':
          _vehicleSideImage = file;
          break;
        case 'driver_vehicle_joint_image':
          _driverVehicleJointImage = file;
          break;
      }
    });
  }

  Widget _vehicleImagePicker({
    required String title,
    required String keyName,
    required File? pickedFile,
    required String serverField,
  }) {
    final String serverUrl = (isVehicleExists ? (_vehicleData?[serverField] ?? '').toString().trim() : '');
    final bool hasServer = serverUrl.isNotEmpty;
    final bool hasPicked = pickedFile != null;

    Widget body;
    if (isVehicleExists) {
      if (hasServer) {
        body = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(serverUrl, fit: BoxFit.cover),
        );
      } else {
        body = const Center(child: Icon(Icons.image_not_supported_outlined));
      }
    } else if (hasPicked) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(pickedFile!, fit: BoxFit.cover),
      );
    } else {
      body = const Center(child: Icon(Icons.add_a_photo));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: isVehicleExists ? null : () => _pickVehicleImage(keyName),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(10),
            ),
            child: body,
          ),
        ),
      ],
    );
  }

  Future<void> _fetchVehicleInfo() async {
    setState(() {
      _hydratingStatus = true;
    });
    try {
      final token = await _sessionService.getToken();
      final t = (token ?? '').trim();
      if (t.isEmpty) {
        if (!mounted) return;
        setState(() {
          isVehicleExists = false;
          _vehicleData = null;
          _vehicleStatus = 'not_submitted';
        });
        return;
      }

      final uri = Uri.parse('$baseUrl/driver/vehicle-info');
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer $t',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      Map<String, dynamic>? decoded;
      try {
        dynamic raw = res.data;
        if (raw is String) raw = jsonDecode(raw);
        if (raw is Map<String, dynamic>) decoded = raw;
      } catch (_) {
        decoded = null;
      }

      final data = decoded is Map<String, dynamic> ? decoded!['data'] : null;
      final bool exists = data != null;
      final status = exists && data is Map ? (data['status'] ?? '').toString() : 'not_submitted';

      if (!mounted) return;
      setState(() {
        isVehicleExists = exists;
        _vehicleData = exists && data is Map ? Map<String, dynamic>.from(data) : null;
        _vehicleStatus = (status.trim().isEmpty ? 'pending' : status.trim());

        if (isVehicleExists && _vehicleData != null) {
          _selectedVehicleType = null;
          _selectedBrand = null;
          _selectedModel = null;
          _selectedModelYear = null;
          _selectedColor = null;
          _selectedFuelType = null;

          _vehicleNumberController.text = (_vehicleData?['plate_no'] ?? '').toString();

          _selectedServices
            ..clear()
            ..addAll(((_vehicleData?['services'] ?? []) as List)
                .map((x) => x.toString().toLowerCase().trim())
                .where((x) => x.isNotEmpty));

          _serverVehicleTypeId = (_vehicleData?['vehicle_type_id'] ?? '').toString();
          _serverBrandId = (_vehicleData?['brand_id'] ?? '').toString();
          _serverModelId = (_vehicleData?['model_id'] ?? '').toString();
          _serverModelYear = (_vehicleData?['model_year'] ?? '').toString();
          _serverColorId = (_vehicleData?['color_id'] ?? '').toString();
          _serverFuelType = (_vehicleData?['fuel_type'] ?? '').toString();
        }
      });

      if (exists) {
        final vtId = (_serverVehicleTypeId ?? '').trim();
        if (vtId.isNotEmpty) {
          await _loadBrands();
        }
        final bId = (_serverBrandId ?? '').trim();
        if (bId.isNotEmpty) {
          await _loadModelsByBrand(bId);
        }
        _syncSelectionsFromServer();
      }
    } finally {
      if (mounted) {
        setState(() {
          _hydratingStatus = false;
        });
      }
    }
  }

  Future<void> _pickRcImage() async {
    if (isVehicleExists) return;
    final file = await _pickImageAnySource();
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _rcImage = file;
    });
  }

  Future<String?> _buildRcDataUri() async {
    final f = _rcImage;
    if (f == null) return null;
    if (!f.existsSync()) return null;
    final bytes = await f.readAsBytes();
    final b64 = base64Encode(bytes);
    return 'data:image/jpeg;base64,$b64';
  }

  Future<Map<String, dynamic>> _postDriverVehicleInfo({
    required String plateNo,
    required String vehicleType,
    String? vehicleImage,
  }) async {
    final token = await _sessionService.getToken();
    final t = (token ?? '').trim();
    if (t.isEmpty) {
      return {'success': false, 'message': 'Unauthorized'};
    }

    final uri = Uri.parse('$baseUrl/driver/vehicle-info');
    final res = await DioClient.dio.post(
      uri.toString(),
      data: {
        'services': _selectedServices.toList(growable: false),
        'vehicle_type_id': (_selectedVehicleType?['id'] ?? '').toString(),
        'brand_id': (_selectedBrand?['id'] ?? '').toString(),
        'model_id': (_selectedModel?['id'] ?? '').toString(),
        'model_year': (_selectedModelYear?['name'] ?? '').toString(),
        'color_id': (_selectedColor?['id'] ?? '').toString(),
        'fuel_type': (_selectedFuelType ?? '').toString(),
        'plate_no': plateNo,
        'vehicle_type': vehicleType,
        'vehicle_image': vehicleImage,
      },
      options: Options(
        validateStatus: (_) => true,
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
        },
      ),
    );

    dynamic decoded;
    try {
      decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    final statusCode = res.statusCode ?? 0;
    if (statusCode >= 200 && statusCode < 300) {
      return {'success': true};
    }
    return {'success': false, 'message': 'Request failed'};
  }

  Future<Map<String, dynamic>> _postDriverVehicleMultipart({
    required String plateNo,
    required String vehicleType,
    required File rcImage,
    required File vehicleFront,
    required File vehicleBack,
    required File vehicleSide,
    required File driverVehicleJoint,
  }) async {
    final token = await _sessionService.getToken();
    final t = (token ?? '').trim();
    if (t.isEmpty) {
      return {'success': false, 'message': 'Unauthorized'};
    }

    final uri = Uri.parse('$baseUrl/driver/vehicle');
    final formData = FormData.fromMap({
      'vehicle_number': plateNo,
      'plate_no': plateNo,
      'service_type': _selectedServices.join(','),
      'services': _selectedServices.join(','),
      'vehicle_type_id': (_selectedVehicleType?['id'] ?? '').toString(),
      'brand_id': (_selectedBrand?['id'] ?? '').toString(),
      'model_id': (_selectedModel?['id'] ?? '').toString(),
      'model_year': (_selectedModelYear?['id'] ?? _selectedModelYear?['name'] ?? '').toString(),
      'color_id': (_selectedColor?['id'] ?? '').toString(),
      'fuel_type': (_selectedFuelType ?? '').toString(),
      'vehicle_type': (_selectedVehicleType?['id'] ?? '').toString(),
      'brand': (_selectedBrand?['id'] ?? '').toString(),
      'model': (_selectedModel?['id'] ?? '').toString(),
      'vehicle_color': (_selectedColor?['id'] ?? '').toString(),
      'rc_image': await MultipartFile.fromFile(rcImage.path),
      'vehicle_front_image': await MultipartFile.fromFile(vehicleFront.path),
      'vehicle_back_image': await MultipartFile.fromFile(vehicleBack.path),
      'vehicle_side_image': await MultipartFile.fromFile(vehicleSide.path),
      'driver_vehicle_joint_image': await MultipartFile.fromFile(driverVehicleJoint.path),
    });

    final res = await DioClient.dio.post(
      uri.toString(),
      data: formData,
      options: Options(
        validateStatus: (_) => true,
        contentType: Headers.multipartFormDataContentType,
        headers: {
          'Authorization': 'Bearer $t',
        },
      ),
    );

    dynamic decoded;
    try {
      decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    final statusCode = res.statusCode ?? 0;
    if (statusCode >= 200 && statusCode < 300) {
      return {'success': true};
    }

    return {'success': false, 'message': 'Request failed'};
  }

  Color _statusDotColor(String s) {
    switch (s) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _statusBanner() {
    if (!isVehicleExists) return const SizedBox.shrink();
    if (_vehicleStatus == 'not_submitted') return const SizedBox.shrink();

    final colors = _vehicleStatus == 'approved'
        ? const [Color(0xFFd4edda), Color(0xFFc3e6cb)]
        : _vehicleStatus == 'rejected'
            ? const [Color(0xFFf8d7da), Color(0xFFf5c6cb)]
            : const [Color(0xFFfff3cd), Color(0xFFffeeba)];

    final icon = _vehicleStatus == 'approved'
        ? Icons.verified
        : _vehicleStatus == 'rejected'
            ? Icons.cancel
            : Icons.hourglass_bottom;

    final iconColor = _statusDotColor(_vehicleStatus);

    final text = _vehicleStatus == 'approved'
        ? 'Vehicle Approved'
        : _vehicleStatus == 'rejected'
            ? 'Vehicle Rejected'
            : 'Vehicle Under Review';

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadVehicleTypes() async {
    setState(() {
      _loadingVehicleTypes = true;
    });
    try {
      final types = await _getSimpleListFromApi('/vehicle-master/options/vehicle-types');
      setState(() {
        _vehicleTypes = types;
      });
      _syncSelectionsFromServer();
    } finally {
      setState(() {
        _loadingVehicleTypes = false;
      });
    }
  }

  Future<List<Map<String, String>>> _getSimpleListFromApi(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await DioClient.dio.get(
      uri.toString(),
      options: Options(
        validateStatus: (_) => true,
      ),
    );
    final statusCode = res.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) return <Map<String, String>>[];

    dynamic decoded = res.data;
    if (decoded is String) decoded = jsonDecode(decoded);
    if (decoded is! Map<String, dynamic>) return <Map<String, String>>[];
    if (decoded['success'] != true) return <Map<String, String>>[];

    final data = decoded['data'];
    if (data is! List) return <Map<String, String>>[];

    return data.whereType<Map>().map((raw) {
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      return <String, String>{
        'id': (map['_id'] ?? map['id'] ?? '').toString(),
        'name': (map['name'] ?? '').toString(),
      };
    }).where((x) => x['id']!.trim().isNotEmpty).toList(growable: false);
  }

  String _currentVehicleMasterQueryString({
    bool includeVehicleType = true,
    bool includeBrand = true,
    bool includeModel = true,
    bool includeModelYear = false,
    bool includeColor = false,
    bool includeFuelType = false,
  }) {
    final params = <String, String>{};
    if (includeVehicleType) {
      final v = (_selectedVehicleType?['id'] ?? '').trim();
      if (v.isNotEmpty) params['vehicle_type_id'] = v;
    }
    if (includeBrand) {
      final v = (_selectedBrand?['id'] ?? '').trim();
      if (v.isNotEmpty) params['brand_id'] = v;
    }
    if (includeModel) {
      final v = (_selectedModel?['id'] ?? '').trim();
      if (v.isNotEmpty) params['model_id'] = v;
    }
    if (includeModelYear) {
      final v = (_selectedModelYear?['id'] ?? '').trim();
      if (v.isNotEmpty) params['model_year_id'] = v;
    }
    if (includeColor) {
      final v = (_selectedColor?['id'] ?? '').trim();
      if (v.isNotEmpty) params['color_id'] = v;
    }
    if (includeFuelType) {
      final v = (_selectedFuelType ?? '').trim();
      if (v.isNotEmpty) params['fuel_type'] = v;
    }

    if (params.isEmpty) return '';
    return '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
  }

  Future<void> _loadBrands() async {
    setState(() {
      _loadingBrands = true;
    });
    try {
      final vehicleTypeId = (_selectedVehicleType?['id'] ?? '').trim();
      final qp = vehicleTypeId.isEmpty ? '' : '?vehicle_type_id=$vehicleTypeId';
      final brands = await _getSimpleListFromApi('/vehicle-master/options/brands$qp');
      setState(() {
        _brands = brands;
      });
      _syncSelectionsFromServer();
    } finally {
      setState(() {
        _loadingBrands = false;
      });
    }
  }

  Future<void> _loadModelsByBrand(String brandId) async {
    setState(() {
      _loadingModels = true;
    });
    try {
      final vehicleTypeId = (_selectedVehicleType?['id'] ?? '').trim();
      final params = <String, String>{};
      if (vehicleTypeId.isNotEmpty) params['vehicle_type_id'] = vehicleTypeId;
      params['brand_id'] = brandId;

      final qp = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      final models = await _getSimpleListFromApi('/vehicle-master/options/models?$qp');
      setState(() {
        _models = models;
      });
      _syncSelectionsFromServer();
    } finally {
      setState(() {
        _loadingModels = false;
      });
    }
  }

  Future<void> _loadModelYears() async {
    setState(() {
      _loadingModelYears = true;
    });
    try {
      final qp = _currentVehicleMasterQueryString(includeModelYear: false, includeColor: false);
      final years = await _getSimpleListFromApi('/vehicle-master/options/model-years$qp');
      setState(() {
        _modelYears = years;
      });
      _syncSelectionsFromServer();
    } finally {
      setState(() {
        _loadingModelYears = false;
      });
    }
  }

  Future<void> _loadColors() async {
    setState(() {
      _loadingColors = true;
    });
    try {
      final qp = _currentVehicleMasterQueryString(includeModelYear: true, includeColor: false);
      final colors = await _getSimpleListFromApi('/vehicle-master/options/colors$qp');
      setState(() {
        _colors = colors;
      });
      _syncSelectionsFromServer();
    } finally {
      setState(() {
        _loadingColors = false;
      });
    }
  }

  Future<void> _loadFuelTypes() async {
    setState(() {
      _loadingFuelTypes = true;
    });
    try {
      final qp = _currentVehicleMasterQueryString(includeModelYear: true, includeColor: true);
      final uri = Uri.parse('$baseUrl/vehicle-master/options/fuel-types$qp');
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        setState(() {
          _fuelTypes = <Map<String, String>>[];
        });
        return;
      }

      dynamic decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        setState(() {
          _fuelTypes = <Map<String, String>>[];
        });
        return;
      }

      final data = decoded['data'];
      if (data is! List) {
        setState(() {
          _fuelTypes = <Map<String, String>>[];
        });
        return;
      }

      final parsed = data.whereType<Map>().map((raw) {
        final map = raw.map((k, v) => MapEntry(k.toString(), v));
        return <String, String>{
          'value': (map['value'] ?? '').toString(),
          'label': (map['label'] ?? map['value'] ?? '').toString(),
        };
      }).where((x) => x['value']!.trim().isNotEmpty).toList(growable: false);

      setState(() {
        _fuelTypes = parsed;
      });
      _syncSelectionsFromServer();
    } finally {
      setState(() {
        _loadingFuelTypes = false;
      });
    }
  }

  void _syncSelectionsFromServer() {
    if (!isVehicleExists) return;
    if (_vehicleData == null) return;

    Map<String, String>? findById(List<Map<String, String>> list, String? id) {
      final key = (id ?? '').trim();
      if (key.isEmpty) return null;
      for (final x in list) {
        if ((x['id'] ?? '').toString().trim() == key) return x;
      }
      return null;
    }

    Map<String, String>? findByName(List<Map<String, String>> list, String? name) {
      final key = (name ?? '').trim().toLowerCase();
      if (key.isEmpty) return null;
      for (final x in list) {
        final n = (x['name'] ?? '').toString().trim().toLowerCase();
        if (n == key) return x;
      }
      return null;
    }

    setState(() {
      _selectedVehicleType = findById(_vehicleTypes, _serverVehicleTypeId);
      _selectedBrand = findById(_brands, _serverBrandId);
      _selectedModel = findById(_models, _serverModelId);
      _selectedModelYear = findById(_modelYears, _serverModelYear) ?? findByName(_modelYears, _serverModelYear);
      _selectedColor = findById(_colors, _serverColorId);

      final sf = (_serverFuelType ?? '').trim();
      _selectedFuelType = sf.isEmpty ? null : sf;
    });
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 1.3),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _serviceCard(String title, IconData icon) {
    final bool selected = _selectedServices.contains(title.toLowerCase());

    return GestureDetector(
      onTap: isVehicleExists
          ? null
          : () {
        setState(() {
          _serviceError = null;
          final key = title.toLowerCase();
          if (_selectedServices.contains(key)) {
            _selectedServices.remove(key);
          } else {
            _selectedServices.add(key);
          }
        });
      },
      child: Container(
        width: 104,
        height: 92,
        decoration: BoxDecoration(
          color: selected ? _primary.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _primary : const Color(0xFFE5E7EB),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? _primary : Colors.black54, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? Colors.black87 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black87),
      ),
    );
  }

  Widget _prefTile({required String title, required bool value, required ValueChanged<bool?> onChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        activeColor: _primary,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        dense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Vehicle Registration',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vehicle Registration',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Explore Your Life By Joining With Ride',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 18),
                _label('Select Service'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _serviceCard('Cab', Icons.alt_route_rounded),
                    _serviceCard('Parcel', Icons.inventory_2_outlined),
                    _serviceCard('Intercity', Icons.location_city_outlined),
                  ],
                ),
                if ((_serviceError ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _serviceError!,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(height: 18),

                _label('Vehicle Type'),
                DropdownButtonFormField<Map<String, String>>(
                  value: _selectedVehicleType,
                  decoration: _inputDecoration('Select Vehicle Type'),
                  icon: _loadingVehicleTypes
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.keyboard_arrow_down_rounded),
                  items: _vehicleTypes
                      .map((t) => DropdownMenuItem<Map<String, String>>(
                            value: t,
                            child: Text(t['name'] ?? ''),
                          ))
                      .toList(growable: false),
                  onChanged: (_loadingVehicleTypes || isVehicleExists)
                      ? null
                      : (v) async {
                          if (v == null) return;
                          setState(() {
                            _selectedVehicleType = v;
                            _selectedBrand = null;
                            _selectedModel = null;
                            _selectedModelYear = null;
                            _selectedColor = null;
                            _selectedFuelType = null;
                            _brands = <Map<String, String>>[];
                            _models = <Map<String, String>>[];
                            _modelYears = <Map<String, String>>[];
                            _colors = <Map<String, String>>[];
                            _fuelTypes = <Map<String, String>>[];
                          });
                          await _loadBrands();
                          await _loadModelYears();
                          await _loadColors();
                          await _loadFuelTypes();
                        },
                  validator: (v) => v == null ? 'Vehicle type is required' : null,
                ),

                const SizedBox(height: 16),
                _label('Company Brand'),
                DropdownButtonFormField<Map<String, String>>(
                  value: _selectedBrand,
                  decoration: _inputDecoration('Select Brand'),
                  icon: _loadingBrands
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.keyboard_arrow_down_rounded),
                  items: _brands
                      .map((b) => DropdownMenuItem<Map<String, String>>(
                            value: b,
                            child: Text(b['name'] ?? ''),
                          ))
                      .toList(growable: false),
                  onChanged: (_selectedVehicleType == null || _loadingBrands || isVehicleExists)
                      ? null
                      : (v) async {
                          if (v == null) return;
                          setState(() {
                            _selectedBrand = v;
                            _selectedModel = null;
                            _selectedModelYear = null;
                            _selectedColor = null;
                            _selectedFuelType = null;
                            _models = <Map<String, String>>[];
                            _modelYears = <Map<String, String>>[];
                            _colors = <Map<String, String>>[];
                            _fuelTypes = <Map<String, String>>[];
                          });
                          final brandId = (v['id'] ?? '').trim();
                          if (brandId.isNotEmpty) {
                            await _loadModelsByBrand(brandId);
                          }
                          await _loadModelYears();
                          await _loadColors();
                          await _loadFuelTypes();
                        },
                  validator: (v) => v == null ? 'Brand is required' : null,
                ),

                const SizedBox(height: 16),
                _label('Vehicle Model'),
                DropdownButtonFormField<Map<String, String>>(
                  value: _selectedModel,
                  decoration: _inputDecoration('Select Model'),
                  icon: _loadingModels
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.keyboard_arrow_down_rounded),
                  items: _models
                      .map((m) => DropdownMenuItem<Map<String, String>>(
                            value: m,
                            child: Text(m['name'] ?? ''),
                          ))
                      .toList(growable: false),
                  onChanged: (_selectedBrand == null || _loadingModels || isVehicleExists)
                      ? null
                      : (v) async {
                          setState(() {
                            _selectedModel = v;
                            _selectedModelYear = null;
                            _selectedColor = null;
                            _selectedFuelType = null;
                            _modelYears = <Map<String, String>>[];
                            _colors = <Map<String, String>>[];
                            _fuelTypes = <Map<String, String>>[];
                          });
                          await _loadModelYears();
                          await _loadColors();
                          await _loadFuelTypes();
                        },
                  validator: (v) => v == null ? 'Model is required' : null,
                ),

                const SizedBox(height: 16),
                _label('Model Year'),
                DropdownButtonFormField<Map<String, String>>(
                  value: _selectedModelYear,
                  decoration: _inputDecoration('Select Model Year'),
                  icon: _loadingModelYears
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.keyboard_arrow_down_rounded),
                  items: _modelYears
                      .map((y) => DropdownMenuItem<Map<String, String>>(
                            value: y,
                            child: Text(y['name'] ?? ''),
                          ))
                      .toList(growable: false),
                  onChanged: (_loadingModelYears || isVehicleExists)
                      ? null
                      : (v) async {
                          setState(() {
                            _selectedModelYear = v;
                            _selectedColor = null;
                            _selectedFuelType = null;
                            _colors = <Map<String, String>>[];
                            _fuelTypes = <Map<String, String>>[];
                          });
                          await _loadColors();
                          await _loadFuelTypes();
                        },
                  validator: (v) => v == null ? 'Model year is required' : null,
                ),

                const SizedBox(height: 16),
                _label('Vehicle Color'),
                DropdownButtonFormField<Map<String, String>>(
                  value: _selectedColor,
                  decoration: _inputDecoration('Select Color'),
                  icon: _loadingColors
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.keyboard_arrow_down_rounded),
                  items: _colors
                      .map((c) => DropdownMenuItem<Map<String, String>>(
                            value: c,
                            child: Text(c['name'] ?? ''),
                          ))
                      .toList(growable: false),
                  onChanged: (_loadingColors || isVehicleExists)
                      ? null
                      : (v) async {
                          setState(() {
                            _selectedColor = v;
                            _selectedFuelType = null;
                            _fuelTypes = <Map<String, String>>[];
                          });
                          await _loadFuelTypes();
                        },
                  validator: (v) => v == null ? 'Vehicle color is required' : null,
                ),

                const SizedBox(height: 16),
                _label('Fuel Type'),
                DropdownButtonFormField<String>(
                  value: _selectedFuelType,
                  decoration: _inputDecoration('Select Fuel Type'),
                  icon: _loadingFuelTypes
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.keyboard_arrow_down_rounded),
                  items: _fuelTypes
                      .map((f) => DropdownMenuItem<String>(
                            value: f['value'],
                            child: Text(f['label'] ?? ''),
                          ))
                      .toList(growable: false),
                  onChanged: (_loadingFuelTypes || isVehicleExists) ? null : (v) => setState(() => _selectedFuelType = v),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Fuel type is required' : null,
                ),

                const SizedBox(height: 16),
                TextFormField(
                  controller: _vehicleNumberController,
                  enabled: !isVehicleExists,
                  decoration: _inputDecoration('Enter vehicle number').copyWith(
                    hintText: 'Enter vehicle number',
                    labelText: 'Vehicle Number',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Vehicle number is required' : null,
                ),

                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: _inputDecoration('Select seat capacity').copyWith(
                    labelText: 'Seat Capacity',
                  ),
                  value: _selectedSeatCapacity,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: const [1, 2, 3, 4, 5]
                      .map(
                        (v) => DropdownMenuItem<int>(
                          value: v,
                          child: Text(v.toString()),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: isVehicleExists ? null : (v) => setState(() => _selectedSeatCapacity = v),
                ),

                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RC Image', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: isVehicleExists ? null : _pickRcImage,
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: isVehicleExists
                            ? (() {
                                final imageUrl = (_vehicleData?['rc_image'] ?? _vehicleData?['vehicle_image'] ?? '')
                                    .toString()
                                    .trim();
                                if (imageUrl.isNotEmpty) {
                                  if (imageUrl.startsWith('data:image') && imageUrl.contains('base64,')) {
                                    try {
                                      final b64 = imageUrl.split('base64,').last;
                                      final bytes = base64Decode(b64);
                                      return ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.memory(bytes, fit: BoxFit.cover),
                                      );
                                    } catch (_) {
                                      return const Center(child: Icon(Icons.broken_image_outlined));
                                    }
                                  }
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(imageUrl, fit: BoxFit.cover),
                                  );
                                }
                                return const Center(child: Icon(Icons.image_not_supported_outlined));
                              })()
                            : (_rcImage != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(_rcImage!, fit: BoxFit.cover),
                                  )
                                : const Center(child: Icon(Icons.add_a_photo))),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                _vehicleImagePicker(
                  title: 'Vehicle Front Photo',
                  keyName: 'vehicle_front_image',
                  pickedFile: _vehicleFrontImage,
                  serverField: 'vehicle_front_image',
                ),

                const SizedBox(height: 16),
                _vehicleImagePicker(
                  title: 'Vehicle Back Photo',
                  keyName: 'vehicle_back_image',
                  pickedFile: _vehicleBackImage,
                  serverField: 'vehicle_back_image',
                ),

                const SizedBox(height: 16),
                _vehicleImagePicker(
                  title: 'Vehicle Side Photo',
                  keyName: 'vehicle_side_image',
                  pickedFile: _vehicleSideImage,
                  serverField: 'vehicle_side_image',
                ),

                const SizedBox(height: 16),
                _vehicleImagePicker(
                  title: 'Driver with Vehicle Photo',
                  keyName: 'driver_vehicle_joint_image',
                  pickedFile: _driverVehicleJointImage,
                  serverField: 'driver_vehicle_joint_image',
                ),

                const SizedBox(height: 18),
                if (!isVehicleExists)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: (_submitting || _hydratingStatus)
                          ? null
                          : () async {
                              if (_selectedServices.isEmpty) {
                                setState(() {
                                  _serviceError = 'Please select at least one service';
                                });
                              }
                              final ok = _formKey.currentState?.validate() ?? false;
                              if (!ok || _selectedServices.isEmpty) return;

                              if (_rcImage == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please upload RC photo')),
                                );
                                return;
                              }

                              if (_vehicleFrontImage == null ||
                                  _vehicleBackImage == null ||
                                  _vehicleSideImage == null ||
                                  _driverVehicleJointImage == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please upload all 4 vehicle photos')),
                                );
                                return;
                              }

                              final payload = {
                                'services': _selectedServices.toList(growable: false),
                                'vehicle_type_id': (_selectedVehicleType?['id'] ?? '').toString(),
                                'brand_id': (_selectedBrand?['id'] ?? '').toString(),
                                'model_id': (_selectedModel?['id'] ?? '').toString(),
                                'model_year': (_selectedModelYear?['name'] ?? '').toString(),
                                'color_id': (_selectedColor?['id'] ?? '').toString(),
                                'fuel_type': (_selectedFuelType ?? '').toString(),
                                'vehicle_number': _vehicleNumberController.text.trim(),
                              };

                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Confirm'),
                                  content: const Text(
                                    'Are you sure you want to submit vehicle details?\nYou cannot edit after submission.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () async {
                                        Navigator.pop(context);
                                        setState(() {
                                          _submitting = true;
                                        });
                                        try {
                                          final plateNo = _vehicleNumberController.text.trim();
                                          final vehicleType = (_selectedVehicleType?['name'] ?? '').toString().trim();
                                          final result = await _postDriverVehicleMultipart(
                                            plateNo: plateNo,
                                            vehicleType: vehicleType,
                                            rcImage: _rcImage!,
                                            vehicleFront: _vehicleFrontImage!,
                                            vehicleBack: _vehicleBackImage!,
                                            vehicleSide: _vehicleSideImage!,
                                            driverVehicleJoint: _driverVehicleJointImage!,
                                          );

                                          final ok = result['success'] == true;
                                          if (!mounted) return;
                                          if (!ok) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text((result['message'] ?? 'Submit failed').toString())),
                                            );
                                            return;
                                          }

                                          await _fetchVehicleInfo();
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Vehicle details submitted')),
                                          );
                                          debugPrint('Vehicle registration payload: $payload');
                                        } finally {
                                          if (mounted) {
                                            setState(() {
                                              _submitting = false;
                                            });
                                          }
                                        }
                                      },
                                      child: const Text('Confirm'),
                                    ),
                                  ],
                                ),
                              );
                            },
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Register',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                _statusBanner(),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

