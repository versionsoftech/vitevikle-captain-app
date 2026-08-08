import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/screens/home/map_picker_screen.dart';
import 'package:vite_captain/services/contact_service.dart';
import 'package:vite_captain/services/places_service.dart';

enum LocationFieldType { pickup, drop }

class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({
    super.key,
    required this.isSelectingPickup,
    required this.initialPickupAddress,
    required this.initialDropAddress,
    required this.placesService,
    this.initialPickupLat,
    this.initialPickupLng,
    this.initialDropLat,
    this.initialDropLng,
    this.contactName = 'For me',
    this.contactPhone = '',
    this.useScaffold = true,
  });

  final bool isSelectingPickup;
  final String initialPickupAddress;
  final String initialDropAddress;
  final double? initialPickupLat;
  final double? initialPickupLng;
  final double? initialDropLat;
  final double? initialDropLng;
  final PlacesService placesService;
  final String contactName;
  final String contactPhone;
  final bool useScaffold;

  @override
  State<LocationSelectionScreen> createState() => _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> {
  final ContactService _contactService = const ContactService();

  late final TextEditingController _pickupController;
  late final TextEditingController _dropController;

  late final FocusNode _pickupFocusNode;
  late final FocusNode _dropFocusNode;

  final List<TextEditingController> _stopControllers = <TextEditingController>[];

  LocationFieldType _activeField = LocationFieldType.drop;
  final List<PlaceSuggestion> _suggestions = <PlaceSuggestion>[];
  final List<Map<String, dynamic>> _recentLocations = <Map<String, dynamic>>[];
  Map<String, dynamic>? _nearMeLocation;

  bool _loading = false;
  bool _hadSearchError = false;
  Timer? _debounce;
  late final String _sessionToken;

  bool _clearedPickup = false;
  bool _clearedDrop = false;

  String _contactName = 'For me';
  String _contactPhone = '';

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController(text: widget.initialPickupAddress);
    _dropController = TextEditingController(text: widget.initialDropAddress);

    _pickupFocusNode = FocusNode();
    _dropFocusNode = FocusNode();

    _activeField =
        widget.isSelectingPickup ? LocationFieldType.pickup : LocationFieldType.drop;

    _contactName = widget.contactName.trim().isEmpty ? 'For me' : widget.contactName;
    _contactPhone = widget.contactPhone;

    _sessionToken = _randomToken();
    _pickupController.addListener(_onTextChanged);
    _dropController.addListener(_onTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isSelectingPickup) {
        _pickupFocusNode.requestFocus();
      } else {
        _dropFocusNode.requestFocus();
      }
    });

    unawaited(_loadRecentLocations());
    unawaited(_loadNearMeLocation());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupController.removeListener(_onTextChanged);
    _dropController.removeListener(_onTextChanged);
    _pickupController.dispose();
    _dropController.dispose();
    _pickupFocusNode.dispose();
    _dropFocusNode.dispose();
    for (final c in _stopControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRecentLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('recent_locations') ?? <String>[];

    final parsed = <Map<String, dynamic>>[];
    for (final item in raw) {
      final parts = item.split('|');
      if (parts.length < 3) continue;
      final lat = double.tryParse(parts[1]);
      final lng = double.tryParse(parts[2]);
      if (lat == null || lng == null) continue;
      parsed.add(<String, dynamic>{
        'address': parts[0],
        'lat': lat,
        'lng': lng,
      });
    }

    if (!mounted) return;
    setState(() {
      _recentLocations
        ..clear()
        ..addAll(parsed);
    });
  }

  Future<void> _saveRecentLocation({
    required String address,
    required double lat,
    required double lng,
  }) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('recent_locations') ?? <String>[];
    final newItem = '$trimmed|$lat|$lng';

    final next = <String>[newItem, ...existing.where((e) => e != newItem)];
    if (next.length > 10) {
      next.removeRange(10, next.length);
    }

    await prefs.setStringList('recent_locations', next);
    if (!mounted) return;
    await _loadRecentLocations();
  }

  Future<void> _loadNearMeLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      String address = 'Current location';
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        final p = placemarks.isNotEmpty ? placemarks.first : null;
        final parts = <String>[
          if ((p?.subLocality ?? '').trim().isNotEmpty) p!.subLocality!.trim(),
          if ((p?.locality ?? '').trim().isNotEmpty) p!.locality!.trim(),
          if ((p?.administrativeArea ?? '').trim().isNotEmpty)
            p!.administrativeArea!.trim(),
        ];
        if (parts.isNotEmpty) address = parts.join(', ');
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _nearMeLocation = <String, dynamic>{
          'address': address,
          'lat': pos.latitude,
          'lng': pos.longitude,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nearMeLocation = null;
      });
    }
  }

  String _randomToken() {
    final r = Random();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  String get _activeQuery {
    return _activeField == LocationFieldType.pickup
        ? _pickupController.text
        : _dropController.text;
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), () {
      _search(_activeQuery);
    });
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _suggestions.clear();
        _loading = false;
        _hadSearchError = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _hadSearchError = false;
    });

    try {
      final nearLat = (_nearMeLocation?['lat'] is num)
          ? (_nearMeLocation?['lat'] as num).toDouble()
          : null;
      final nearLng = (_nearMeLocation?['lng'] is num)
          ? (_nearMeLocation?['lng'] as num).toDouble()
          : null;

      final results = await widget.placesService.autocomplete(
        trimmed,
        sessionToken: _sessionToken,
        language: 'en',
        components: 'country:in',
        locationLat: nearLat,
        locationLng: nearLng,
        radiusMeters: (nearLat != null && nearLng != null) ? 50000 : null,
      );
      if (!mounted) return;
      setState(() {
        _suggestions
          ..clear()
          ..addAll(results);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hadSearchError = true;
        _suggestions.clear();
      });
    }
  }

  Future<void> _selectRecentOrNearMe(Map<String, dynamic> item) async {
    final address = (item['address'] ?? '').toString().trim();
    final lat = item['lat'];
    final lng = item['lng'];

    if (lat is! num || lng is! num) return;
    Navigator.pop(
      context,
      <String, dynamic>{
        'address': address.isEmpty ? 'Selected location' : address,
        'lat': lat.toDouble(),
        'lng': lng.toDouble(),
        'isPickup': _activeField == LocationFieldType.pickup,
        'contactName': _contactName,
        'contactPhone': _contactPhone,
      },
    );
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _loading = true;
      _hadSearchError = false;
    });

    try {
      final details = await widget.placesService.getPlaceDetails(
        suggestion.placeId,
        sessionToken: _sessionToken,
        language: 'en',
      );

      if (!mounted) return;

      if (_activeField == LocationFieldType.pickup) {
        _pickupController.text = details.address;
      } else {
        _dropController.text = details.address;
      }

      await _saveRecentLocation(
        address: details.address,
        lat: details.lat,
        lng: details.lng,
      );

      Navigator.pop(
        context,
        <String, dynamic>{
          'address': details.address,
          'lat': details.lat,
          'lng': details.lng,
          'isPickup': _activeField == LocationFieldType.pickup,
          'contactName': _contactName,
          'contactPhone': _contactPhone,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hadSearchError = true;
        _suggestions.clear();
      });
    }
  }

  Future<void> _openMapPicker() async {
    final initialLat = _activeField == LocationFieldType.pickup
        ? widget.initialPickupLat
        : widget.initialDropLat;
    final initialLng = _activeField == LocationFieldType.pickup
        ? widget.initialPickupLng
        : widget.initialDropLng;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MapPickerScreen(
          title: _activeField == LocationFieldType.pickup
              ? 'Select pickup location'
              : 'Select drop location',
          initialLat: initialLat,
          initialLng: initialLng,
        ),
      ),
    );

    if (result == null) return;

    if (!mounted) return;
    Navigator.pop(
      context,
      <String, dynamic>{
        ...result,
        'isPickup': _activeField == LocationFieldType.pickup,
        'contactName': _contactName,
        'contactPhone': _contactPhone,
      },
    );
  }

  Future<void> _setPickupToCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String address = 'Current location';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        final p = placemarks.isNotEmpty ? placemarks.first : null;
        final parts = <String>[
          if ((p?.street ?? '').trim().isNotEmpty) p!.street!.trim(),
          if ((p?.subLocality ?? '').trim().isNotEmpty) p!.subLocality!.trim(),
          if ((p?.locality ?? '').trim().isNotEmpty) p!.locality!.trim(),
        ];
        if (parts.isNotEmpty) {
          address = parts.join(', ');
        }
      } catch (_) {}

      if (!mounted) return;
      _pickupController.text = address;

      Navigator.pop(
        context,
        <String, dynamic>{
          'address': address,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'isPickup': true,
          'contactName': _contactName,
          'contactPhone': _contactPhone,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hadSearchError = true;
      });
    }
  }

  void _handleBack() {
    if (_clearedPickup || _clearedDrop) {
      Navigator.pop(
        context,
        <String, dynamic>{
          if (_clearedPickup) 'clearPickup': true,
          if (_clearedDrop) 'clearDrop': true,
          'contactName': _contactName,
          'contactPhone': _contactPhone,
        },
      );
      return;
    }

    Navigator.pop(context);
  }

  void _clearField({required bool isPickup}) {
    if (isPickup) {
      _pickupController.clear();
      _clearedPickup = true;
    } else {
      _dropController.clear();
      _clearedDrop = true;
    }

    setState(() {
      _hadSearchError = false;
      _suggestions.clear();
    });
  }

  Future<void> _openBookingRideForSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final isMyself = _contactName.trim().isEmpty || _contactName == 'For me';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Booking ride for',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Myself'),
                  trailing: Icon(
                    isMyself ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isMyself ? const Color(0xFF16A34A) : Colors.grey,
                  ),
                  onTap: () {
                    setState(() {
                      _contactName = 'For me';
                      _contactPhone = '';
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Add new rider'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _chooseContactFromList();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _chooseContactFromList() async {
    final allowed = await _contactService.requestPermission();
    if (!allowed) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Contacts permission required'),
          content: const Text('Allow contacts access to book for someone else.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final contacts = await _contactService.getContacts();
    if (!mounted) return;

    final selected = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text(
                  'Select contact',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: contacts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = contacts[index];
                      final subtitle = c.phones.isEmpty ? '' : c.phones.first.number;
                      return ListTile(
                        title: Text(c.displayName),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    final mapped = _contactService.mapContact(selected);
    if (mapped == null) return;

    setState(() {
      _contactName = mapped.name;
      _contactPhone = mapped.phone;
    });
  }

  void _addStop() {
    setState(() {
      _stopControllers.add(TextEditingController());
    });
  }

  void _removeStop(int index) {
    setState(() {
      final c = _stopControllers.removeAt(index);
      c.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildTopBar(),
        Expanded(child: _buildBody()),
      ],
    );

    if (widget.useScaffold) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFF2F3F5),
        body: SafeArea(child: content),
      );
    }

    return Material(
      color: const Color(0xFFF2F3F5),
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: content,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          Text(
            widget.isSelectingPickup ? 'Pickup' : 'Drop',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          InkWell(
            onTap: _openBookingRideForSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(_contactName),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final queryEmpty = _activeQuery.trim().isEmpty;

    return Column(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _locationField(
                        isPickup: true,
                        controller: _pickupController,
                        focusNode: _pickupFocusNode,
                        hint: 'Pickup location',
                      ),
                      const Divider(height: 1),
                      ...List.generate(_stopControllers.length, (i) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _stopControllers[i],
                                    decoration: const InputDecoration(
                                      hintText: 'Add Stop',
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _removeStop(i),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            const Divider(height: 1),
                          ],
                        );
                      }),
                      _locationField(
                        isPickup: false,
                        controller: _dropController,
                        focusNode: _dropFocusNode,
                        hint: 'Drop location',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openMapPicker,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        icon: const Icon(
                          Icons.location_on_outlined,
                          color: Colors.black,
                        ),
                        label: const Text(
                          'Select on map',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addStop,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.add, color: Colors.black),
                        label: const Text(
                          'Add stops',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: queryEmpty
              ? ListView(
                  children: [
                    if (_recentLocations.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          'Recent locations',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      ..._recentLocations.map((item) {
                        final address = (item['address'] ?? '').toString();
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Recent',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectRecentOrNearMe(item),
                        );
                      }),
                      const Divider(height: 1),
                    ],
                    if (_nearMeLocation != null) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          'Near me',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.my_location),
                        title: const Text(
                          'Current location',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          (_nearMeLocation?['address'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectRecentOrNearMe(_nearMeLocation!),
                      ),
                    ],
                    if (_recentLocations.isEmpty && _nearMeLocation == null)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Text(
                            'Start typing to search locations',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              : (_suggestions.isEmpty
                  ? Center(
                      child: Text(
                        _hadSearchError ? 'No results found' : 'No results found',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final s = _suggestions[index];
                        return ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            s.primaryText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: s.secondaryText.trim().isEmpty
                              ? null
                              : Text(
                                  s.secondaryText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => _selectSuggestion(s),
                        );
                      },
                    )),
        ),
      ],
    );
  }

  Widget _locationField({
    required bool isPickup,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
  }) {
    final active = _activeField == (isPickup ? LocationFieldType.pickup : LocationFieldType.drop);
    final showClear = controller.text.trim().isNotEmpty;

    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 12,
          color: isPickup ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onTap: () {
              setState(() {
                _activeField = isPickup ? LocationFieldType.pickup : LocationFieldType.drop;
              });
              _search(controller.text);
            },
            onChanged: (_) {
              if (_activeField !=
                  (isPickup ? LocationFieldType.pickup : LocationFieldType.drop)) {
                setState(() {
                  _activeField = isPickup ? LocationFieldType.pickup : LocationFieldType.drop;
                });
              } else {
                setState(() {});
              }
            },
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              hintStyle: TextStyle(
                color: active ? const Color(0xFF64748B) : const Color(0xFF9CA3AF),
                fontWeight: FontWeight.w600,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPickup)
                    IconButton(
                      icon: const Icon(Icons.my_location, size: 20),
                      onPressed: _setPickupToCurrentLocation,
                    ),
                  if (showClear)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => _clearField(isPickup: isPickup),
                    ),
                ],
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 40),
            ),
          ),
        ),
      ],
    );
  }
}

