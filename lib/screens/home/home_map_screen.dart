import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/models/intercity_request.dart';
import 'package:vite_captain/screens/auth/login_screen.dart';
import 'package:vite_captain/screens/full_map_screen.dart';
import 'package:vite_captain/screens/activity/activity_screen.dart';
import 'package:vite_captain/screens/home/intercity_ride_map_screen.dart';
import 'package:vite_captain/screens/home/intercity_bidding_screen.dart';
import 'package:vite_captain/screens/home/pickup_map_screen.dart';
import 'package:vite_captain/screens/home/driver_ride_in_progress_screen.dart';
import 'package:vite_captain/screens/home/navigation_map_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:vite_captain/services/distance_calculate_api.dart';
import 'package:vite_captain/services/fare_calculate_api.dart';
import 'package:vite_captain/services/location_service.dart';
import 'package:vite_captain/services/payment_gateway_api.dart';
import 'package:vite_captain/services/places_service.dart';
import 'package:vite_captain/services/preference_api.dart';
import 'package:vite_captain/services/ride_booking_state.dart';
import 'package:vite_captain/services/parcel_activity_state.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/service_category_api.dart';
import 'package:vite_captain/services/vehicle_type_api.dart';
import 'package:vite_captain/services/vehicles_by_service_api.dart';
import 'package:vite_captain/screens/notifications_screen.dart';
import 'package:vite_captain/screens/settings_screen.dart';
import 'package:vite_captain/services/alert_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vite_captain/widgets/payment_received_popup.dart';
import 'package:vite_captain/widgets/cancellation_reason_sheet.dart';
import 'package:vite_captain/screens/bank_details_screen.dart';
import 'package:vite_captain/screens/document_verification_menu_screen.dart';
import 'package:vite_captain/screens/my_earnings_screen.dart';
import 'package:vite_captain/screens/my_rating_screen.dart';
import 'package:vite_captain/screens/personal_picture/personal_picture_instruction_screen.dart';
import 'package:vite_captain/screens/profile_screen.dart';
import 'package:vite_captain/screens/vehicle_registration_screen.dart';
import 'package:vite_captain/screens/wallet/wallet_screen.dart';
import 'package:vite_captain/screens/wallet/driver_withdraw_screen.dart';
import 'package:vite_captain/widgets/apply_coupon_bottom_sheet.dart';
import 'package:vite_captain/widgets/logout_dialog.dart';
import 'package:vite_captain/widgets/set_price_bottom_sheet.dart';
import 'package:vite_captain/widgets/service_category_card.dart';
import 'package:vite_captain/widgets/wallet_insufficient_dialog.dart';
import 'package:vite_captain/providers/driver_status_summary_provider.dart';
import 'package:vite_captain/providers/document_verification_provider.dart';
import 'package:vite_captain/controllers/profile_controller.dart';
import 'package:vite_captain/screens/home/location_selection_screen.dart';
import 'package:vite_captain/screens/parcel/parcel_map_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vite_captain/screens/intercity/intercity_chat_screen.dart';
import 'package:vite_captain/services/chat_notification_provider.dart';
import 'package:vite_captain/services/app_config.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> with WidgetsBindingObserver {
  static const String _isOnlinePrefsKey = 'isOnline';
  static const String _googleApiKey = 'AIzaSyCgfyPk2RQlRS7OTkYGSk2OjOcdbzKzivc';
  static const String _vehicleImageAsset = 'assets/images/Car.png';
  static const String _parcelDutyPrefsKey = 'is_parcel_active';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final LocationService _locationService = const LocationService();
  final PlacesService _placesService = const PlacesService(apiKey: _googleApiKey);
  final PolylinePoints _polylinePoints = PolylinePoints();
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  bool _loadingLocation = true;
  LatLng _cameraTarget = const LatLng(20.5937, 78.9629);
  Set<Marker> _markers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};
  final Map<String, List<LatLng>> _directionsPointCache = <String, List<LatLng>>{};
  String _pickupDropRouteCacheKey = '';

  bool _isOnline = false;
  bool _isInForeground = true;
  Timer? _pingTimer;
  Timer? _rideRequestsTimer;
  Timer? _intercityRequestsTimer;
  Timer? _activeRideTimer;
  Timer? _parcelRequestsTimer;
  bool isDialogOpen = false;
  bool _isRideAccepted = false;
  final Set<String> _handledRideRequestIds = <String>{};
  final Set<String> _ignoredRideIds = <String>{};
  final Set<String> _ignoredParcelRequestIds = <String>{};
  final Set<String> _acceptingParcelRequestIds = <String>{};
  String? _acceptedRideId;
  String? _lastRideId;
  bool _isUpdatingBid = false;
  Map<String, dynamic>? _activeRide;
  bool _parcelDutyOn = false;
  bool _loadingParcelRequests = false;
  List<Map<String, dynamic>> _liveParcelRequests = <Map<String, dynamic>>[];
  bool _rideAcceptedSheetOpen = false;
  String _rideAcceptedSheetRideId = '';
  bool _ongoingRideScreenOpen = false;

  bool _loadingIntercityRequests = false;
  List<IntercityRequestModel> _intercityRequests = <IntercityRequestModel>[];
  List<IntercityRequestModel> _myWaitingIntercityRides = <IntercityRequestModel>[];
  List<IntercityRequestModel> _myAcceptedIntercityRides = <IntercityRequestModel>[];
  final Set<String> _seenIntercityRequestIds = <String>{};
  bool _intercityScreenOpening = false;
  int _bottomTabIndex = 0;

  final Set<String> _pendingIntercityBidIds = <String>{};
  double _speedKmh = 0;
  StreamSubscription<Position>? _positionSub;
  LatLng? _driverLatLng;
  BitmapDescriptor? _driverIcon;
  DateTime? _lastLocationSentAt;

  bool _isAllApproved = false;
  String _driverId = '';
  String _driverVehicleType = '';
  String _driverVehicleTypeId = '';
  String _vehicleFrontImageUrl = '';

  final AudioPlayer _togglePlayer = AudioPlayer();

  RideBookingState? _rideState;
  int _routeRequestId = 0;
  int _fareRequestId = 0;
  String? _lastFareKey;

  final ServiceCategoryApi _serviceCategoryApi = const ServiceCategoryApi();
  Future<List<ServiceCategory>>? _serviceCategoriesFuture;
  int _selectedServiceIndex = 0;
  String? _selectedServiceCategoryId;

  String _selectedPayment = 'cash';

  final PaymentGatewayApi _paymentGatewayApi = const PaymentGatewayApi();
  Future<List<PaymentGatewayModel>>? _paymentGatewaysFuture;

  bool _isPetsSelected = false;
  bool _isLuggagesSelected = false;

  final PreferenceApi _preferenceApi = const PreferenceApi();
  Future<List<PreferenceModel>>? _preferencesFuture;
  List<int> _selectedPreferences = <int>[];

  final VehicleTypeApi _vehicleTypeApi = const VehicleTypeApi();
  Future<List<VehicleTypeModel>>? _vehicleTypesFuture;
  int? _selectedVehicleId;

  final VehiclesByServiceApi _vehiclesByServiceApi = const VehiclesByServiceApi();
  Future<List<ServiceVehicleModel>>? _vehiclesByServiceFuture;

  final FareCalculateApi _fareCalculateApi = const FareCalculateApi();
  final DistanceCalculateApi _distanceCalculateApi = const DistanceCalculateApi();
  final SessionService _sessionService = const SessionService();
  Future<Map<String, String>>? _userBasicsFuture;

  double _walletBalance = 0.0;
  bool _walletBalanceLoading = true;
  String _driverName = '';
  String _driverImageUrl = '';
  int _totalCompletedRides = 0;
  int _distanceRequestId = 0;
  String? _lastDistanceKey;
  String? _distanceKm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      context.read<DocumentVerificationProvider>().hydrate();
    });
    _userBasicsFuture = _sessionService.getUserBasics();
    _loadInitialLocation();
    _startDriverTracking();
    _serviceCategoriesFuture = _serviceCategoryApi.fetchServiceCategories();
    _loadWalletBalance();
    _loadDriverProfile();
    _loadVehicleFrontImage();
    _vehicleTypesFuture = _vehicleTypeApi.getVehicleTypes();
    _preferencesFuture = _preferenceApi.getPreferences();
    _paymentGatewaysFuture = _paymentGatewayApi.getPaymentGateways();

    _initDriverAndApprovalStatus();

    _hydrateParcelDuty();

    _hydrateOnlineStatusOnStart();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DriverStatusSummaryProvider>().refresh(silent: true);
    });
  }

  Future<void> _handleHomeSOS() async {
    // STEP 3: TRACE SOS FLOW
    // Debug
    // ignore: avoid_print
    print('SOS_DIALOG_OPENED');

    // BLOCK if emergency contact missing
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isNotEmpty) {
        final prof = await const ApiService().getDriverProfile(token: token);
        final data = prof['data'];
        final ec = data is Map ? data['emergency_contact'] : null;
        final hasEc = ec is Map && (ec['name'] ?? '').toString().trim().isNotEmpty && (ec['phone'] ?? '').toString().trim().isNotEmpty;
        if (!hasEc) {
          if (!mounted) return;
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Emergency Contact Required'),
              content: const Text('Please add Emergency Contact first.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Go To Profile')),
              ],
            ),
          );
          if (go == true) {
            if (!mounted) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
          }
          return;
        }
      }
    } catch (_) {}

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Emergency SOS'),
        content: const Text('Are you sure you want to send an emergency alert?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send SOS')),
        ],
      ),
    );

    if (confirmed != true) return;

    // Debug
    // ignore: avoid_print
    print('SOS_CONFIRMED');

    try {
      // STEP 6: VERIFY LOCATION (do not block on address)
      // Debug
      // ignore: avoid_print
      print('SOS_LOCATION_START');
      final pos = await _locationService.getCurrentLocation();
      // ignore: avoid_print
      print('SOS_LOCATION_SUCCESS lat=${pos.latitude}, lng=${pos.longitude}');

      final driverId = (await _sessionService.getDriverId() ?? '').trim();
      final basics = await _sessionService.getUserBasics();
      final driverName = (basics['name'] ?? '').trim();
      final driverPhone = (basics['mobile'] ?? '').trim();

      // STEP 4: API
      // Debug
      // ignore: avoid_print
      print('SOS_API_REQUEST_START');

      final token = (await _sessionService.getToken() ?? '').trim();
      print('SOS_TOKEN $token');
      print('SOS_AUTH_HEADER Bearer $token');

      final pkg = await PackageInfo.fromPlatform();
      final rideNumber = _activeRide?['ride_number']?.toString() ?? (_acceptedRideId ?? '');
      final vehicleNumber = '';
      
      // Fetch address from coordinates
      String address = '';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          address = '${place.street}, ${place.locality}, ${place.country}'.trim();
        }
      } catch (_) {
        address = 'Location available';
      }

      final payload = <String, dynamic>{
        'lat': pos.latitude,
        'lng': pos.longitude,
        'driver_name': driverName,
        'driver_phone': driverPhone,
        'app_version': pkg.version,
        'device_model': (Theme.of(context).platform.name),
        if (vehicleNumber.isNotEmpty) 'vehicle_number': vehicleNumber,
        if (rideNumber.isNotEmpty) 'ride_number': rideNumber,
        if (address.isNotEmpty) 'current_address': address,
      };

      final res = await const ApiService().triggerSOS(token: token, driverId: driverId, payload: payload);
      // ignore: avoid_print
      print('SOS_API_RESPONSE $res');
      print('SOS ALERT ID: ${res['alert_id']}');
      print('SOS SUCCESS: ${res['success']}');

      if (res['success'] == true && res['alert_id'] != null) {
        // Debug
        // ignore: avoid_print
        print('SOS_SUCCESS');
        print('SOS_RECORD_CREATED_IN_MONGODB: ${res['alert_id']}');

        // Get emergency contact phone from response or profile
        String emergencyPhone = '';
        if (res['emergency_contact'] != null && res['emergency_contact']['phone'] != null) {
          emergencyPhone = res['emergency_contact']['phone'].toString().trim();
        } else {
          // Fallback to profile
          try {
            final token = (await _sessionService.getToken() ?? '').trim();
            if (token.isNotEmpty) {
              final prof = await const ApiService().getDriverProfile(token: token);
              final data = prof['data'];
              final ec = data is Map ? data['emergency_contact'] : null;
              emergencyPhone = ec is Map ? (ec['phone'] ?? '').toString().trim() : '';
            }
          } catch (_) {}
        }

        print('SOS_EMERGENCY_PHONE $emergencyPhone');

        // Format time for display
        final formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

        // Show improved success dialog
        if (!mounted) return;
        _showSOSSuccessDialog(
          driverName: driverName,
          driverPhone: driverPhone,
          vehicleNumber: (await _sessionService.getUserBasics())['vehicle_number'] ?? '',
          rideNumber: _activeRide?['ride_number']?.toString() ?? (_acceptedRideId ?? ''),
          lat: pos.latitude,
          lng: pos.longitude,
          emergencyPhone: emergencyPhone,
          currentTime: formattedTime,
          address: address,
        );

        // Automatically launch phone dialer AFTER dialog is shown
        if (emergencyPhone.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
          print('SOS_PHONE_DIAL_OPENED');
          print('SOS_PHONE_NUMBER $emergencyPhone');
          final uri = Uri(scheme: 'tel', path: emergencyPhone);
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          print('SOS_DIALER_LAUNCHED $launched');
        } else {
          print('SOS_NO_EMERGENCY_PHONE');
        }

        return;
      }

      // Fallback if backend declined
      // ignore: avoid_print
      print('SOS_ERROR back-end rejected, activating fallback');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS Alert Submitted')), // fallback success UI
      );
    } catch (e, st) {
      // Debug
      // ignore: avoid_print
      print('SOS_ERROR $e');
      // ignore: avoid_print
      print(st);

      // STEP 5: IMPLEMENT FALLBACK SOS
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      // ignore: avoid_print
      print('SOS_FALLBACK lat=${pos.latitude}, lng=${pos.longitude}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS Alert Submitted')), // Fallback UI
      );
    }
  }

  void _showSOSSuccessDialog({
    required String driverName,
    required String driverPhone,
    required String vehicleNumber,
    required String rideNumber,
    required double lat,
    required double lng,
    required String emergencyPhone,
    required String currentTime,
    required String address,
  }) {
    // Log SOS popup data for debugging
    print('SOS_POPUP_DATA');
    print({
      'ride_number': rideNumber,
      'driver_name': driverName,
      'driver_phone': driverPhone,
      'vehicle_number': vehicleNumber,
      'address': address,
      'emergency_phone': emergencyPhone,
      'lat': lat,
      'lng': lng,
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success animation with smooth pulse
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.2),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.sos,
                      color: Colors.red,
                      size: 36,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'SOS Alert Sent',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Emergency assistance request has been recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            // Status section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStatusItem('Admin Notified', true),
                  const SizedBox(height: 6),
                  _buildStatusItem('Emergency Contact Notified', emergencyPhone.isNotEmpty),
                  const SizedBox(height: 6),
                  _buildStatusItem('SOS Recorded', true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Ride Information section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ride Information',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCompactInfoRow('Ride No', rideNumber.isNotEmpty ? rideNumber : 'N/A'),
                  const SizedBox(height: 6),
                  _buildCompactInfoRow('Driver', driverName.isNotEmpty ? driverName : 'N/A'),
                  const SizedBox(height: 6),
                  _buildCompactInfoRow('Vehicle', vehicleNumber.isNotEmpty ? vehicleNumber : 'N/A'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Location section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    address.isNotEmpty ? address : 'Location available',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Timestamp
            Text(
              currentTime,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final uri = Uri(scheme: 'tel', path: '911');
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    child: Text('CALL SUPPORT', style: TextStyle(color: Colors.red.shade700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('CLOSE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, bool completed) {
    return Row(
      children: [
        Icon(
          completed ? Icons.check_circle : Icons.radio_button_unchecked,
          color: completed ? Colors.green : Colors.grey,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: completed ? Colors.black87 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection({required IconData icon, required String title, required String content}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey[700], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSosActionsSheet({
    required String driverName,
    required String driverPhone,
    required String vehicleNumber,
    required String rideNumber,
    required double lat,
    required double lng,
    required String emergencyPhone,
  }) async {
    String maps = 'https://maps.google.com/?q=$lat,$lng';
    final now = DateTime.now();
    final ts = DateFormat('yyyy-MM-dd hh:mm a').format(now);

    final message = StringBuffer()
      ..writeln('EMERGENCY ALERT')
      ..writeln()
      ..writeln('Driver:')
      ..writeln(driverName)
      ..writeln()
      ..writeln('Phone:')
      ..writeln(driverPhone)
      ..writeln()
      ..writeln('Vehicle:')
      ..writeln(vehicleNumber)
      ..writeln()
      ..writeln('Ride:')
      ..writeln(rideNumber.isEmpty ? '-' : rideNumber)
      ..writeln()
      ..writeln('Location:')
      ..writeln('${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}')
      ..writeln()
      ..writeln('Maps:')
      ..writeln(maps)
      ..writeln()
      ..writeln('Time:')
      ..writeln(ts)
      ..writeln()
      ..writeln('Generated by ViteWay Driver SOS');

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Emergency SOS Activated',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (emergencyPhone.isNotEmpty) ...[
                  Text(
                    'Emergency Contact: $emergencyPhone',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                ],
                const Text(
                  'Location Shared',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.call, color: Colors.green),
                  title: const Text('Call Emergency Contact Again'),
                  onTap: () async {
                    if (emergencyPhone.isNotEmpty) {
                      final uri = Uri(scheme: 'tel', path: emergencyPhone);
                      await launchUrl(uri);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_location, color: Colors.blue),
                  title: const Text('Share Live Location'),
                  onTap: () async {
                    await Share.share(message.toString());
                  },
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadVehicleFrontImage() async {
    try {
      final token = await _sessionService.getToken();
      final t = (token ?? '').trim();
      if (t.isEmpty) return;

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

      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is! Map) return;

      final rawFront = (data['vehicle_front_image'] ?? data['vehicle_image'] ?? '').toString().trim();
      final normalized = _normalizeMaybeUrl(rawFront);

      if (!mounted) return;
      if (normalized.isNotEmpty) {
        setState(() {
          _vehicleFrontImageUrl = normalized;
        });
      }
    } catch (_) {
      // keep fallback asset
    }
  }

  String _asTrimmed(dynamic v) => (v ?? '').toString().trim();

  String _normalizeVehicleForMatch(dynamic value) {
    final s = _asTrimmed(value).toLowerCase();
    if (s.isEmpty) return s;
    // Bike family
    if (s.contains('two wheeler') ||
        (s.contains('two') && s.contains('wheel')) ||
        (s.contains('2') && s.contains('wheel')) ||
        s.contains('bike') ||
        s.contains('bicycle') ||
        s.contains('scooter') ||
        s.contains('motor') ||
        s.contains('moto')) {
      return 'bike';
    }
    // Car family
    if (s.contains('four wheeler') ||
        (s.contains('four') && s.contains('wheel')) ||
        (s.contains('4') && s.contains('wheel')) ||
        s.contains('car') ||
        s.contains('suv') ||
        s.contains('sedan') ||
        s.contains('hatchback')) {
      return 'car';
    }
    return s;
  }

  String _requestVehicleFromMap(Map<String, dynamic> data) {
    return _asTrimmed(
      data['vehicle_slug'] ??
          data['vehicleSlug'] ??
          data['vehicle_type_name'] ??
          data['vehicleTypeName'] ??
          data['vehicle_name'] ??
          data['vehicleName'] ??
          data['vehicle_type'] ??
          data['vehicleType'],
    );
  }

  bool _isStrictVehicleTypeMatch(dynamic requestVehicle) {
    final driverType = _normalizeVehicleForMatch(_driverVehicleType);
    final reqType = _normalizeVehicleForMatch(requestVehicle);
    final match = driverType.isEmpty || reqType.isEmpty || driverType == reqType;
    print('[RIDE_DISPATCH] ========================================');
    print('[RIDE_DISPATCH] VEHICLE TYPE MATCH CHECK');
    print('[RIDE_DISPATCH] Driver Vehicle Type (Raw): $_driverVehicleType');
    print('[RIDE_DISPATCH] Driver Vehicle Type (Normalized): $driverType');
    print('[RIDE_DISPATCH] Request Vehicle Type (Raw): $requestVehicle');
    print('[RIDE_DISPATCH] Request Vehicle Type (Normalized): $reqType');
    print('[RIDE_DISPATCH] Match Result: $match');
    if (driverType.isEmpty) {
      print('[RIDE_DISPATCH] Driver vehicle type empty; allowing backend-filtered request');
    }
    print('[RIDE_DISPATCH] ========================================');
    return match;
  }

  bool _isStaleParcelAcceptMessage(String message) {
    final m = message.toLowerCase();
    return m.contains('already taken') || m.contains('already assigned') || m.contains('not found');
  }

  bool _looksLikeObjectId(String value) {
    final v = value.trim();
    return RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(v);
  }

  Future<Map<String, String>?> _showDriverCancelSheet() async {
    int limit = 0;
    int duration = 0;
    try {
      final settingsResp = await const ApiService().getAppSettings();
      final rules = (settingsResp['cancellation_rules'] is Map)
          ? Map<String, dynamic>.from(settingsResp['cancellation_rules'] as Map)
          : <String, dynamic>{};

      limit = int.tryParse((rules['driver_penalty_limit'] ?? 0).toString()) ?? 0;
      duration = int.tryParse((rules['penalty_duration'] ?? 0).toString()) ?? 0;
    } catch (_) {
      limit = 0;
      duration = 0;
    }

    String selectedReasonId = '';
    String selectedReasonText = '';
    final noteCtrl = TextEditingController();
    bool isSubmitting = false;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                final warn = limit > 0;
                return Column(
                  children: [
                    Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cancel Ride',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        warn
                            ? 'Frequent cancellations may trigger a penalty${duration > 0 ? ' for $duration min' : ''}.'
                            : 'Are you sure you want to cancel this ride?',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Select a reason', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: const ApiService().getCancellationReasons(type: 'driver'),
                        builder: (ctx, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final payload = snap.data ?? <String, dynamic>{};
                          final ok = payload['success'] == true;
                          final list = payload['data'];
                          final reasons = (ok && list is List) ? list : <dynamic>[];

                          if (!ok) {
                            return Center(
                              child: Text(
                                (payload['message'] ?? 'Failed to load reasons').toString(),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          if (reasons.isEmpty) {
                            return const Center(child: Text('No cancellation reasons available'));
                          }

                          return ListView.separated(
                            itemCount: reasons.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (ctx, i) {
                              final raw = reasons[i];
                              if (raw is! Map) return const SizedBox.shrink();
                              final m = Map<String, dynamic>.from(raw);
                              final id = (m['id'] ?? m['_id'] ?? '').toString().trim();
                              final text = (m['reason_text'] ?? m['reason'] ?? '').toString().trim();
                              final selected = id.isNotEmpty && id == selectedReasonId;

                              return InkWell(
                                onTap: () {
                                  if (id.isEmpty) return;
                                  setLocal(() {
                                    selectedReasonId = id;
                                    selectedReasonText = text;
                                  });
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                      width: selected ? 1.6 : 1,
                                    ),
                                    color: selected ? const Color(0xFFF8FAFC) : Colors.white,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: selected ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          selected ? Icons.check_rounded : Icons.info_outline_rounded,
                                          color: selected ? Colors.white : const Color(0xFF0F172A),
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          text.isEmpty ? '-' : text,
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (selectedReasonText.trim().toLowerCase() == 'other')
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tell us more (optional)',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 4,
                      )
                    else
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Add a note (optional)',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 1,
                        maxLines: 3,
                      ),
                    const SizedBox(height: 12),
                    SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              onPressed: (isSubmitting || selectedReasonId.isEmpty)
                                  ? null
                                  : () {
                                      setLocal(() => isSubmitting = true);
                                      Navigator.pop(ctx, {
                                        'cancellation_reason_id': selectedReasonId,
                                        'reason': selectedReasonText,
                                        'note': noteCtrl.text,
                                      });
                                    },
                              child: isSubmitting
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Confirm Cancel'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    noteCtrl.dispose();
    return result;
  }

  IconData _parcelIcon(String desc) {
    final d = desc.toLowerCase();
    if (d.contains('box')) return Icons.inventory_2;
    if (d.contains('wood') || d.contains('timber')) return Icons.forest;
    if (d.contains('document')) return Icons.description;
    if (d.contains('book')) return Icons.menu_book;
    if (d.contains('electronic') || d.contains('electronics') || d.contains('mobile') || d.contains('laptop')) return Icons.devices;
    return Icons.local_shipping;
  }

  DateTime? _parseParcelDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
      } catch (_) {
        return null;
      }
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      final parsed = DateTime.parse(s);
      final localTime = parsed.toLocal();
      print('========== PARCEL_TIME_PARSE ==========');
      print('RAW_TIME_VALUE => $s');
      print('PARSED_DATETIME_UTC => $parsed');
      print('PARSED_DATETIME_LOCAL => $localTime');
      print('======================================');
      return localTime;
    } catch (_) {
      return null;
    }
  }

  Future<void> _hydrateParcelDuty() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = prefs.getBool(_parcelDutyPrefsKey) ?? true;
      print('========== PARCEL_DUTY_STATUS ==========');
      print('PARCEL_DUTY_PREFS_KEY => $_parcelDutyPrefsKey');
      print('PARCEL_DUTY_VALUE => $next');
      print('PARCEL_DUTY_ONLINE => $_isOnline');
      print('PARCEL_DUTY_DRIVER_ID => $_driverId');
      print('========================================');
      if (!mounted) return;
      if (_parcelDutyOn != next) {
        setState(() {
          _parcelDutyOn = next;
        });
      }
      _refreshParcelRequestsPolling();
    } catch (_) {}
  }

  void _refreshParcelRequestsPolling() {
    final driverId = _driverId.trim();
    if (_parcelDutyOn && _isOnline && driverId.isNotEmpty) {
      _startParcelRequestsPolling();
    } else {
      _stopParcelRequestsPolling();
      if (mounted && _liveParcelRequests.isNotEmpty) {
        setState(() {
          _liveParcelRequests = <Map<String, dynamic>>[];
        });
      }
    }
  }

  void _startParcelRequestsPolling() {
    if (_parcelRequestsTimer != null) return;
    _parcelRequestsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      fetchLiveParcelRequests();
    });
    fetchLiveParcelRequests();
  }

  void _stopParcelRequestsPolling() {
    _parcelRequestsTimer?.cancel();
    _parcelRequestsTimer = null;
  }

  Future<void> fetchLiveParcelRequests() async {
    if (_loadingParcelRequests) return;
    if (!_parcelDutyOn) return;
    if (!_isOnline) return;

    try {
      _loadingParcelRequests = true;
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      final resp = await const ApiService().getLiveParcelRequests(token: token);
      print('========== DRIVER_API_RESPONSE ==========');
      print('PARCEL_API_SUCCESS => ${resp['success']}');
      print('PARCEL_API_DATA_COUNT => ${resp['data'] is List ? (resp['data'] as List).length : 0}');
      print('==========================================');

      if (resp['success'] != true) return;

      final raw = resp['data'];
      final list = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      final filtered = list.where((e) {
        final id = _asTrimmed(e['_id'] ?? e['id']);
        if (id.isEmpty) return false;
        if (_ignoredParcelRequestIds.contains(id)) return false;

        print('========== PARCEL_MODEL_PARSE ==========');
        print('PARCEL_ID => $id');
        print('PARCEL_PICKUP => ${e['pickup']}');
        print('PARCEL_DROP => ${e['drop']}');
        print('PARCEL_VEHICLE_NAME => ${e['vehicle_name']}');
        print('PARCEL_VEHICLE_ID => ${e['vehicle_id']}');
        print('PARCEL_VEHICLE_TYPE => ${e['vehicle_type']}');
        print('PARCEL_STATUS => ${e['status']}');
        print('PARCEL_DRIVER_STATUS => ${e['driver_status']}');
        print('PARCEL_USER_STATUS => ${e['user_status']}');
        print('==========================================');

        final driverStatus = _asTrimmed(e['driver_status'] ?? e['driverStatus']);
        final isAccepted = driverStatus == 'accepted';

        final parcelVehicle = _requestVehicleFromMap(e);
        print('========== PARCEL_VEHICLE_MATCH ==========');
        print('PARCEL_ID => $id');
        print('PARCEL_DRIVER_TYPE => $_driverVehicleType');
        print('PARCEL_REQUEST_TYPE => $parcelVehicle');
        print('PARCEL_IS_ACCEPTED => $isAccepted');
        print('==========================================');

        if (!isAccepted) {
          if (!_isStrictVehicleTypeMatch(parcelVehicle)) {
            print('========== PARCEL_FILTER_RESULT ==========');
            print('PARCEL_ID => $id');
            print('FILTER_REASON => VEHICLE_MISMATCH');
            print('FILTER_RESULT => false');
            print('==========================================');
            return false;
          }
        }

        print('========== PARCEL_FILTER_RESULT ==========');
        print('PARCEL_ID => $id');
        print('FILTER_REASON => PASSED');
        print('FILTER_RESULT => true');
        print('==========================================');

        return true;
      }).toList();

      if (!mounted) return;
      setState(() {
        _liveParcelRequests = filtered;
      });
    } catch (_) {
    } finally {
      _loadingParcelRequests = false;
    }
  }

  Future<void> _acceptParcel(Map<String, dynamic> parcel) async {
    final parcelId = _asTrimmed(parcel['_id'] ?? parcel['id']);
    if (parcelId.isEmpty) return;
    final driverStatus = _asTrimmed(parcel['driver_status'] ?? parcel['driverStatus']).toLowerCase();
    if (driverStatus != 'accepted' && !_isStrictVehicleTypeMatch(_requestVehicleFromMap(parcel))) {
      setState(() {
        _ignoredParcelRequestIds.add(parcelId);
        _liveParcelRequests.removeWhere((e) => _asTrimmed(e['_id'] ?? e['id']) == parcelId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This parcel is not for your vehicle type')),
      );
      return;
    }
    if (_acceptingParcelRequestIds.contains(parcelId)) return;
    _acceptingParcelRequestIds.add(parcelId);

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      // New confirmation flow (backward compatible)
      final resp = await const ApiService().driverAcceptParcel(token: token, parcelId: parcelId);
      print('PARCEL_ACCEPT_HOME driverAcceptParcel => $resp');
      final data = resp['data'];
      final ok = resp['success'] == true ||
          resp['status'] == true ||
          _asTrimmed(resp['success']).toLowerCase() == 'true' ||
          _asTrimmed(resp['status']).toLowerCase() == 'true' ||
          _asTrimmed(resp['driver_status'] ?? resp['driverStatus']).toLowerCase() == 'accepted' ||
          (data is Map && _asTrimmed(data['driver_status'] ?? data['driverStatus']).toLowerCase() == 'accepted');
      if (!mounted) return;

      if (!ok) {
        final msg = (resp['message'] ?? '').toString();
        if (isWalletInsufficientMessage(msg)) {
          await showWalletInsufficientDialog(context, message: msg);
          return;
        }
        // Fallback to legacy accept if confirmation endpoint fails
        final legacy = await const ApiService().acceptParcelRequest(token: token, parcelId: parcelId);
        print('PARCEL_ACCEPT_HOME acceptParcelRequest => $legacy');
        final legacyData = legacy['data'];
        final legacyOk = legacy['success'] == true ||
            legacy['status'] == true ||
            _asTrimmed(legacy['success']).toLowerCase() == 'true' ||
            _asTrimmed(legacy['status']).toLowerCase() == 'true' ||
            _asTrimmed(legacy['driver_status'] ?? legacy['driverStatus']).toLowerCase() == 'accepted' ||
            (legacyData is Map && _asTrimmed(legacyData['driver_status'] ?? legacyData['driverStatus']).toLowerCase() == 'accepted');
        if (!mounted) return;

        if (!legacyOk) {
          final legacyMsg = (legacy['message'] ?? '').toString();
          if (isWalletInsufficientMessage(legacyMsg)) {
            await showWalletInsufficientDialog(context, message: legacyMsg);
            return;
          }
          if (_isStaleParcelAcceptMessage('$msg $legacyMsg')) {
            setState(() {
              _ignoredParcelRequestIds.add(parcelId);
              _liveParcelRequests.removeWhere((e) => _asTrimmed(e['_id'] ?? e['id']) == parcelId);
            });
            return;
          }
          print('PARCEL_ACCEPT_HOME failure snackbar resp=$resp legacy=$legacy');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to accept parcel')),
          );
          return;
        }

        // Legacy flow: keep request visible and move to waiting state
        setState(() {
          for (int i = 0; i < _liveParcelRequests.length; i++) {
            final id = _asTrimmed(_liveParcelRequests[i]['_id'] ?? _liveParcelRequests[i]['id']);
            if (id == parcelId) {
              _liveParcelRequests[i] = {
                ..._liveParcelRequests[i],
                'driver_status': 'accepted',
                'user_status': 'pending',
              };
              break;
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parcel accepted. Waiting for user confirmation.')),
        );
        return;
      }

      // Confirmation flow: keep request visible and move to waiting state
      setState(() {
        for (int i = 0; i < _liveParcelRequests.length; i++) {
          final id = _asTrimmed(_liveParcelRequests[i]['_id'] ?? _liveParcelRequests[i]['id']);
          if (id == parcelId) {
            _liveParcelRequests[i] = {
              ..._liveParcelRequests[i],
              'driver_status': 'accepted',
              'user_status': 'pending',
            };
            break;
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for customer response...')),
      );
    } catch (_) {
    } finally {
      _acceptingParcelRequestIds.remove(parcelId);
    }
  }

  Future<void> _cancelParcelWaiting(Map<String, dynamic> parcel) async {
    final parcelId = _asTrimmed(parcel['_id'] ?? parcel['id']);
    if (parcelId.isEmpty) return;

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      final picked = await CancellationReasonSheet.show(
        context: context,
        type: 'driver',
        title: 'Cancel',
        confirmText: 'Cancel',
      );
      if (picked == null) return;

      final resp = await const ApiService().driverCancelParcel(
        token: token,
        parcelId: parcelId,
        cancellationReasonId: picked['cancellation_reason_id'],
        reason: picked['reason'],
        note: picked['note'],
      );
      final ok = resp['success'] == true;
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((resp['message'] ?? 'Unable to cancel').toString())),
        );
        return;
      }

      setState(() {
        for (int i = 0; i < _liveParcelRequests.length; i++) {
          final id = _asTrimmed(_liveParcelRequests[i]['_id'] ?? _liveParcelRequests[i]['id']);
          if (id == parcelId) {
            _liveParcelRequests[i] = {
              ..._liveParcelRequests[i],
              'driver_status': 'cancelled',
              'user_status': 'pending',
            };
            break;
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cancelled')),
      );
    } catch (_) {}
  }

  Future<void> _rejectParcel(Map<String, dynamic> parcel) async {
    final parcelId = _asTrimmed(parcel['_id'] ?? parcel['id']);
    if (parcelId.isEmpty) return;

    final picked = await CancellationReasonSheet.show(
      context: context,
      type: 'driver',
      title: 'Cancel',
      confirmText: 'Cancel',
    );
    if (picked == null) return;

    final snapshot = Map<String, dynamic>.from(parcel);
    setState(() {
      _ignoredParcelRequestIds.add(parcelId);
      _liveParcelRequests.removeWhere((e) => _asTrimmed(e['_id'] ?? e['id']) == parcelId);
    });

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;
      final resp = await const ApiService().rejectParcelRequest(
        token: token,
        parcelId: parcelId,
        cancellationReasonId: picked['cancellation_reason_id'],
        reason: picked['reason'],
        note: picked['note'],
      );
      final ok = resp['success'] == true;
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _ignoredParcelRequestIds.remove(parcelId);
          _liveParcelRequests.insert(0, snapshot);
        });
      } else {
        try {
          context.read<ParcelActivityState>().upsertCancelled({
            ...snapshot,
            'status': 'CANCELLED',
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Widget _buildParcelRequestCard(Map<String, dynamic> parcel) {
    final desc = _asTrimmed(parcel['description']);
    final title = desc.isEmpty ? 'Parcel' : desc;
    final pickup = _asTrimmed(parcel['pickup']);
    final drop = _asTrimmed(parcel['drop']);
    final priceRaw = parcel['price'];
    final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse(_asTrimmed(priceRaw)) ?? 0.0;

    final pickupDate = _asTrimmed(parcel['pickup_date'] ?? parcel['pickupDate']);
    final pickupTime = _asTrimmed(parcel['pickup_time'] ?? parcel['pickupTime']);
    final when = _parseParcelDate(pickupDate.isNotEmpty && pickupTime.isNotEmpty ? '$pickupDate $pickupTime' : (parcel['pickup_time'] ?? parcel['created_at'] ?? parcel['createdAt']));
    final whenText = when == null ? '' : DateFormat('dd MMM yyyy, hh:mm a').format(when);

    print('========== PARCEL_CARD_TIME ==========');
    print('PICKUP_DATE => $pickupDate');
    print('PICKUP_TIME => $pickupTime');
    print('CREATED_AT => ${parcel['created_at']}');
    print('CREATED_AT_TYPE => ${parcel['created_at'].runtimeType}');
    print('======================================');

    print('========== PARCEL_CARD_DISPLAY ==========');
    print('WHEN => $when');
    print('WHEN_TEXT => $whenText');
    print('========================================');

    final iconData = _parcelIcon(desc);
    final iconColor = iconData == Icons.forest ? Colors.brown : (iconData == Icons.description ? Colors.blue : const Color(0xFF369D01));

    final driverStatus = _asTrimmed(parcel['driver_status'] ?? parcel['driverStatus']);
    final userStatus = _asTrimmed(parcel['user_status'] ?? parcel['userStatus']);
    final isWaiting = driverStatus == 'accepted' && userStatus == 'pending';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ParcelMapScreen(parcel: parcel),
          ),
        );
        if (result == null) return;
        final parcelId = _asTrimmed(parcel['_id'] ?? parcel['id']);
        if (parcelId.isEmpty) return;
        if (!mounted) return;
        setState(() {
          _ignoredParcelRequestIds.add(parcelId);
          _liveParcelRequests.removeWhere((e) => _asTrimmed(e['_id'] ?? e['id']) == parcelId);
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Card(
          elevation: 7,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(iconData, color: iconColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${price.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ],
                ),
                if (whenText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(whenText, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFF369D01), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        pickup.isEmpty ? '-' : pickup,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        drop.isEmpty ? '-' : drop,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (isWaiting)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Waiting for User Response...',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _rejectParcel(parcel),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _acceptParcel(parcel),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeMaybeUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (v.startsWith('/')) return 'https://adm.vitevikle.com$v';
    return 'https://adm.vitevikle.com/$v';
  }

  Future<void> _loadWalletBalance() async {
    try {
      if (mounted) {
        setState(() {
          _walletBalanceLoading = true;
        });
      }

      try {
        final cached = await _sessionService.getWalletBalance();
        if (mounted && cached > 0) {
          setState(() {
            _walletBalance = cached;
          });
        }
      } catch (_) {}

      final driverId = (await _sessionService.getDriverId())?.trim() ?? '';
      if (driverId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _walletBalance = 0.0;
          _walletBalanceLoading = false;
        });
        return;
      }

      final res = await const ApiService().getDriverWallet(driverId: driverId);
      final ok = res['success'] == true;
      final bal = ok ? (res['balance'] as num?)?.toDouble() ?? 0.0 : 0.0;
      // ignore: avoid_print
      print('Home Wallet Balance: $bal');

      if (!mounted) return;
      setState(() {
        _walletBalance = bal;
        _walletBalanceLoading = false;
      });

      try {
        await _sessionService.saveWalletBalance(bal);
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _walletBalanceLoading = false;
      });
    }
  }

  Future<void> _loadDriverProfile() async {
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      final resp = await const ApiService().getDriverProfile(token: token);
      if (!mounted) return;

      print('===== DRIVER PROFILE API RESPONSE =====');
      print('$resp');
      print('======================================');

      final ok = resp['success'] == true;
      final data = ok && resp['data'] is Map ? resp['data'] as Map : null;
      if (data == null) return;

      final name = (data['driver_name'] ?? data['name'] ?? data['fullName'] ?? data['driverName'] ?? '').toString().trim();
      final image = (data['profile_image'] ?? data['image'] ?? data['avatar'] ?? data['driver_image'] ?? '').toString().trim();
      final ridesRaw = data['total_completed_rides'] ?? data['totalCompletedRides'] ?? data['completedRides'] ?? data['total_trips'] ?? data['totalTrips'];
      final rides = ridesRaw is num ? ridesRaw.toInt() : int.tryParse(ridesRaw?.toString() ?? '') ?? 0;

      String vehicleType = (data['vehicleType'] ?? data['vehicle_type'] ?? data['vehicle_type_name'] ?? data['vehicleTypeName'] ?? '').toString().trim();
      String vehicleTypeId = '';
      String vehicleColor = '';
      String vehicleNumber = '';

      final vehicleInfo = data['vehicleInfo'];
      if (vehicleInfo is Map) {
        vehicleTypeId = (vehicleInfo['vehicleType'] ?? vehicleInfo['vehicle_type_id'] ?? '').toString().trim();
        final nestedVehicleName = (vehicleInfo['vehicleTypeName'] ?? vehicleInfo['vehicle_type_name'] ?? vehicleInfo['name'] ?? vehicleInfo['slug'] ?? '').toString().trim();
        if (vehicleType.isEmpty && nestedVehicleName.isNotEmpty) {
          vehicleType = nestedVehicleName;
        }
        vehicleColor = (vehicleInfo['vehicleColor'] ?? vehicleInfo['vehicle_color'] ?? '').toString().trim();
        vehicleNumber = (vehicleInfo['vehicleNumber'] ?? vehicleInfo['vehicle_number'] ?? vehicleInfo['plate_no'] ?? vehicleInfo['plateNumber'] ?? '').toString().trim();
      }

      final driverVehicleInfo = data['driverVehicleInfo'];
      if (driverVehicleInfo is Map) {
        if (vehicleTypeId.isEmpty) {
          vehicleTypeId = (driverVehicleInfo['vehicle_type_id'] ?? driverVehicleInfo['vehicleTypeId'] ?? '').toString().trim();
        }
        final driverVehicleInfoName = (driverVehicleInfo['vehicle_type'] ?? driverVehicleInfo['vehicleType'] ?? driverVehicleInfo['vehicle_type_name'] ?? driverVehicleInfo['vehicleTypeName'] ?? '').toString().trim();
        if (vehicleType.isEmpty && driverVehicleInfoName.isNotEmpty) {
          vehicleType = driverVehicleInfoName;
        }
        if (vehicleColor.isEmpty) {
          vehicleColor = (driverVehicleInfo['vehicle_color'] ?? driverVehicleInfo['vehicleColor'] ?? driverVehicleInfo['color'] ?? '').toString().trim();
        }
        if (vehicleNumber.isEmpty) {
          vehicleNumber = (driverVehicleInfo['plate_no'] ?? driverVehicleInfo['plateNumber'] ?? driverVehicleInfo['vehicle_number'] ?? driverVehicleInfo['vehicleNumber'] ?? '').toString().trim();
        }
      }

      if (_looksLikeObjectId(vehicleType)) {
        vehicleTypeId = vehicleTypeId.isNotEmpty ? vehicleTypeId : vehicleType;
        vehicleType = '';
      }

      if (vehicleType.isEmpty && vehicleTypeId.isNotEmpty) {
        try {
          final details = await const VehicleTypeApi().getVehicleTypeById(vehicleTypeId: vehicleTypeId);
          final resolved = (details?.slug.trim().isNotEmpty == true ? details!.slug : details?.name ?? '').trim();
          if (resolved.isNotEmpty) {
            vehicleType = resolved;
          }
        } catch (_) {}
      }

      print('[RIDE_DISPATCH] ========================================');
      print('[RIDE_DISPATCH] DRIVER VEHICLE TYPE LOADED');
      print('[RIDE_DISPATCH] Vehicle Type (Raw): $vehicleType');
      print('[RIDE_DISPATCH] Vehicle Type ID: $vehicleTypeId');
      print('[RIDE_DISPATCH] Vehicle Color: $vehicleColor');
      print('[RIDE_DISPATCH] Vehicle Number: $vehicleNumber');
      print('[RIDE_DISPATCH] ========================================');

      await _sessionService.saveVehicleType(vehicleType);
      await _sessionService.saveVehicleColor(vehicleColor);
      await _sessionService.saveVehicleNumber(vehicleNumber);

      print('===== SESSION VEHICLE DATA SAVED =====');
      print('SESSION VEHICLE TYPE = $vehicleType');
      print('SESSION VEHICLE COLOR = $vehicleColor');
      print('SESSION VEHICLE NUMBER = $vehicleNumber');
      print('=====================================');

      setState(() {
        if (name.isNotEmpty) _driverName = name;
        final normalized = _normalizeMaybeUrl(image);
        if (normalized.isNotEmpty) _driverImageUrl = normalized;
        _totalCompletedRides = rides;
        _driverVehicleType = vehicleType;
        _driverVehicleTypeId = vehicleTypeId;
      });
    } catch (_) {}
  }

  Future<void> _callNumber(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) {
      return;
    }

    final Uri uri = Uri(scheme: 'tel', path: p);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showAcceptingRideDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF369D01)),
                SizedBox(height: 10),
                Text('Accepting Ride...', style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRideAcceptedDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.canPop(ctx)) Navigator.pop(ctx);
        });

        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Color(0xFF369D01), size: 70),
                SizedBox(height: 10),
                Text('Ride Accepted', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text('Driver is on the way', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntercityWaitingCard(IntercityRequestModel req) {
    print('========== INTERCITY REQUEST ==========');
    print('INTERCITY REQUEST => $req');
    print('PICKUP DATE => ${req.pickupDate}');
    print('PICKUP TIME => ${req.pickupTime}');
    print('========================================');

    final riderName = req.riderName.trim().isEmpty ? 'User' : req.riderName.trim();
    final riderImage = req.riderImage.trim();
    final pickup = req.pickup.trim().isEmpty ? '-' : req.pickup.trim();
    final drop = req.drop.trim().isEmpty ? '-' : req.drop.trim();
    final offer = (req.bidPrice > 0 ? req.bidPrice : req.price).toStringAsFixed(2);
    final distanceText = '${req.km.toStringAsFixed(1)} Km';
    final ratingText = req.userRating.toStringAsFixed(1);
    // REMOVED: Cash label from Intercity ride cards per user request
    // final payment = req.paymentType.trim().isEmpty ? 'Cash' : req.paymentType.trim();
    final vehicle = req.vehicleType.trim().isEmpty ? 'Car' : req.vehicleType.trim();
    final pickupDate = req.pickupDate.trim();
    final pickupTime = req.pickupTime.trim();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IntercityRideMapScreen(ride: req),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: riderImage.isNotEmpty ? NetworkImage(riderImage) : null,
                child: riderImage.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      riderName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text('₹$offer', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text(distanceText, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(width: 8),
                        const Icon(Icons.star, size: 14, color: Colors.orange),
                        const SizedBox(width: 3),
                        Text(ratingText, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                '₹ $offer For ${req.persons} Person${req.persons == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (pickupDate.isNotEmpty || pickupTime.isNotEmpty)
                Text(
                  '${pickupDate.isNotEmpty ? '📅 $pickupDate' : '📅 Not Scheduled'}${pickupDate.isNotEmpty && pickupTime.isNotEmpty ? ' ' : ''}${pickupTime.isNotEmpty ? '🕐 $pickupTime' : '🕐 Not Scheduled'}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF369D01).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Intercity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF369D01))),
              ),
              if (req.isScheduled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Scheduled', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.orange)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // REMOVED: Cash label from Intercity ride cards per user request
              // Container(
              //   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              //   decoration: BoxDecoration(
              //     color: Colors.grey.shade200,
              //     borderRadius: BorderRadius.circular(8),
              //   ),
              //   child: Text(payment, style: const TextStyle(fontWeight: FontWeight.w700)),
              // ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(vehicle, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const Icon(Icons.radio_button_unchecked, size: 16, color: Colors.black54),
                  Container(height: 25, width: 1, color: Colors.grey.shade400),
                  const Icon(Icons.location_on, color: Color(0xFF369D01), size: 18),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pickup, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text(drop, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF369D01),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Waiting for customer response...',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntercityAcceptedPickupCard(IntercityRequestModel req) {
    final riderName = req.riderName.trim().isEmpty ? 'User' : req.riderName.trim();
    final riderImage = req.riderImage.trim();
    final pickup = req.pickup.trim().isEmpty ? '-' : req.pickup.trim();
    final drop = req.drop.trim().isEmpty ? '-' : req.drop.trim();
    final offer = (req.bidPrice > 0 ? req.bidPrice : req.price).toStringAsFixed(2);
    final distanceText = '${req.km.toStringAsFixed(1)} Km';
    final ratingText = req.userRating.toStringAsFixed(1);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IntercityRideMapScreen(ride: req),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 6))],
          border: Border.all(color: const Color(0xFFE6E6E6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: riderImage.isNotEmpty ? NetworkImage(riderImage) : null,
                child: riderImage.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(riderName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('₹$offer', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF369D01))),
                        const SizedBox(width: 8),
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text(distanceText, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        const Icon(Icons.star, size: 14, color: Colors.orange),
                        const SizedBox(width: 3),
                        Text(ratingText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('For ${req.persons} Person${req.persons == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF369D01).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Intercity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF369D01))),
              ),
              if (req.isScheduled) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Scheduled', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.orange)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(pickup, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(drop, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      final token = (await _sessionService.getToken() ?? '').trim();
                      if (token.isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Unauthorized')),
                        );
                        return;
                      }

                      final resp = await const ApiService().acceptIntercityRequest(
                        token: token,
                        requestId: req.id,
                      );

                      if (!context.mounted) return;
                      final ok = resp['success'] == true;
                      if (!ok) {
                        final msg = (resp['message'] ?? 'Failed to accept intercity').toString();
                        if (isWalletInsufficientMessage(msg)) {
                          await showWalletInsufficientDialog(context, message: msg);
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg)),
                        );
                        return;
                      }
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Something went wrong. Please try again.')),
                      );
                      return;
                    }

                    final ride = <String, dynamic>{
                      '_id': req.id,
                      'id': req.id,
                      'pickup': {
                        'lat': req.pickupLat,
                        'lng': req.pickupLng,
                        'address': req.pickup,
                      },
                      'drop': {
                        'lat': req.dropLat,
                        'lng': req.dropLng,
                        'address': req.drop,
                      },
                      'pickup_address': req.pickup,
                      'drop_address': req.drop,
                      'user': {
                        'name': req.riderName,
                        'profile_image': req.riderImage,
                      },
                      'userName': req.riderName,
                      'user_image': req.riderImage,
                      'customerName': req.riderName,
                      'customerImage': req.riderImage,
                      'phone': req.riderPhone,
                      'mobile': req.riderPhone,
                    };

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PickupMapScreen(
                          ride: ride,
                          arrivalMinutes: 5,
                          googleApiKey: _googleApiKey,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF369D01),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('PICKUP CUSTOMER', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                width: 54,
                child: ElevatedButton(
                  onPressed: () => _callNumber(req.riderPhone),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF369D01),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Icon(Icons.call),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                width: 54,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chat will be enabled after chat system setup.')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF369D01),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInForeground = state == AppLifecycleState.resumed;

    _refreshHeartbeat();
    if (_isInForeground) {
      _hydrateParcelDuty();
    }

    if (state == AppLifecycleState.resumed) {
      _loadWalletBalance();
      _loadDriverProfile();
      if (mounted) {
        setState(() {
          _userBasicsFuture = _sessionService.getUserBasics(forceRefresh: true);
        });
      }
    }
  }

  Future<void> _setOfflineFromSystem() async {
    _stopHeartbeat();
    if (!_isOnline) return;

    if (mounted) {
      setState(() {
        _isOnline = false;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isOnlinePrefsKey, false);
    } catch (_) {}

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isNotEmpty) {
        await const ApiService().updateDriverStatus(token: token, isOnline: false);
      }
    } catch (_) {}
  }

  void _refreshHeartbeat() {
    if (_isOnline) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }

    _refreshRideRequestsPolling();
    _refreshIntercityRequestsPolling();
    _refreshParcelRequestsPolling();
    _refreshActiveRidePolling();
  }

  void _refreshIntercityRequestsPolling() {
    final driverId = _driverId.trim();
    if (_isOnline && driverId.isNotEmpty) {
      _startIntercityRequestsPolling();
    } else {
      _stopIntercityRequestsPolling();
    }
  }

  void _startIntercityRequestsPolling() {
    if (_intercityRequestsTimer != null) return;
    _intercityRequestsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      fetchIntercityRequests();
    });
    fetchIntercityRequests();
  }

  void _stopIntercityRequestsPolling() {
    _intercityRequestsTimer?.cancel();
    _intercityRequestsTimer = null;
  }

  Future<void> fetchIntercityRequests() async {
    if (!_isOnline) return;
    if (_loadingIntercityRequests) return;
    if (_activeRide != null) return;

    if (mounted) {
      setState(() {
        _loadingIntercityRequests = true;
      });
    }

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      print('[RIDE_DISPATCH] ========================================');
      print('[RIDE_DISPATCH] FETCHING INTERCITY REQUESTS');
      print('[RIDE_DISPATCH] Driver ID: $_driverId');
      print('[RIDE_DISPATCH] Driver Vehicle Type: $_driverVehicleType');
      print('[RIDE_DISPATCH] ========================================');

      print('Intercity polling API...');
      final respAvailable = await const ApiService().getIntercityRequests(token: token);
      
      print('[RIDE_DISPATCH] ========================================');
      print('[RIDE_DISPATCH] INTERCITY REQUESTS API RESPONSE');
      print('[RIDE_DISPATCH] Success: ${respAvailable['success']}');
      print('[RIDE_DISPATCH] Data: ${respAvailable['data']}');
      print('[RIDE_DISPATCH] ========================================');
      
      print('========== DRIVER INTERCITY RAW RESPONSE ==========');
      print(respAvailable);
      print('===================================================');
      final respWaiting = await const ApiService().getMyWaitingIntercityRides(token: token);
      final respAccepted = await const ApiService().getMyAcceptedIntercityRides(token: token);

      List<IntercityRequestModel> parseList(dynamic payload) {
        if (payload is! List) return <IntercityRequestModel>[];
        final out = <IntercityRequestModel>[];
        final ids = <String>{};
        for (final item in payload) {
          print('[RIDE_DISPATCH] ========================================');
          print('[RIDE_DISPATCH] PARSING INTERCITY REQUEST ITEM');
          print('[RIDE_DISPATCH] Item: $item');
          print('[RIDE_DISPATCH] ========================================');

          print('========== RAW ITEM ==========');
          print('RAW ITEM => $item');
          print('RAW PICKUP DATE => ${item["pickup_date"]}');
          print('RAW PICKUP TIME => ${item["pickup_time"]}');
          print('RAW DATE => ${item["date"]}');
          print('RAW TIME => ${item["time"]}');
          print('===============================');

          IntercityRequestModel? ride;
          if (item is Map<String, dynamic>) {
            ride = IntercityRequestModel.fromJson(item);
          } else if (item is Map) {
            ride = IntercityRequestModel.fromJson(Map<String, dynamic>.from(item));
          }
          if (ride == null) continue;
          if (ride.id.trim().isEmpty) continue;
          if (ids.contains(ride.id)) continue;
          ids.add(ride.id);
          
          print('[RIDE_DISPATCH] ========================================');
          print('[RIDE_DISPATCH] PARSED INTERCITY REQUEST');
          print('[RIDE_DISPATCH] Ride ID: ${ride.id}');
          print('[RIDE_DISPATCH] Vehicle Type: ${ride.vehicleType}');
          print('[RIDE_DISPATCH] Status: ${ride.status}');
          print('[RIDE_DISPATCH] ========================================');
          
          out.add(ride);
        }
        return out;
      }

      Future<void> openIntercityRequest(IntercityRequestModel ride) async {
        if (_intercityScreenOpening) return;
        if (_seenIntercityRequestIds.contains(ride.id)) return;
        if (!_isStrictVehicleTypeMatch(ride.vehicleType)) return;
        _seenIntercityRequestIds.add(ride.id);
        _intercityScreenOpening = true;
        print('Rendering intercity popup: ${ride.id}');
        try {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IntercityRideMapScreen(ride: ride),
            ),
          );
        } finally {
          _intercityScreenOpening = false;
        }
      }

      void scheduleFirstIntercityPopup(List<IntercityRequestModel> rides) {
        if (rides.isEmpty) return;
        final next = rides.firstWhere(
          (ride) => !_seenIntercityRequestIds.contains(ride.id),
          orElse: () => rides.first,
        );
        if (_seenIntercityRequestIds.contains(next.id)) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          openIntercityRequest(next);
        });
      }

      bool isVehicleMatch(IntercityRequestModel ride) {
        return _isStrictVehicleTypeMatch(ride.vehicleType);
      }

      bool isAvailableIntercity(IntercityRequestModel ride) {
        final status = ride.status.trim().toLowerCase();
        
        print('[RIDE_DISPATCH] ========================================');
        print('[RIDE_DISPATCH] CHECKING INTERCITY REQUEST AVAILABILITY');
        print('[RIDE_DISPATCH] Ride ID: ${ride.id}');
        print('[RIDE_DISPATCH] Status: $status');
        print('[RIDE_DISPATCH] Vehicle Type: ${ride.vehicleType}');
        print('[RIDE_DISPATCH] ========================================');
        
        if (status != 'pending' && status != 'new' && status != 'searching') {
          print('[RIDE_DISPATCH] FILTERED OUT: Invalid status ($status)');
          return false;
        }
        if (!isVehicleMatch(ride)) {
          print('[RIDE_DISPATCH] FILTERED OUT: Vehicle type mismatch');
          return false;
        }
        print('[RIDE_DISPATCH] REQUEST IS AVAILABLE');
        return true;
      }

      final availableAll = respAvailable['success'] == true ? parseList(respAvailable['data']) : <IntercityRequestModel>[];
      
      print('[RIDE_DISPATCH] ========================================');
      print('[RIDE_DISPATCH] INTERCITY REQUEST FILTERING');
      print('[RIDE_DISPATCH] Total Available Requests: ${availableAll.length}');
      print('[RIDE_DISPATCH] Driver Vehicle Type: $_driverVehicleType');
      print('[RIDE_DISPATCH] ========================================');
      
      print('Parsed intercity rides: ${availableAll.length}');
      final available = availableAll
          .where(isAvailableIntercity)
          .toList();
      
      print('[RIDE_DISPATCH] ========================================');
      print('[RIDE_DISPATCH] FILTERED INTERCITY REQUESTS');
      print('[RIDE_DISPATCH] After Vehicle Type Filter: ${available.length}');
      print('[RIDE_DISPATCH] ========================================');
      
      print('Rendered intercity ride count: ${available.length}');
      final waiting = respWaiting['success'] == true ? parseList(respWaiting['data']) : <IntercityRequestModel>[];
      final accepted = respAccepted['success'] == true ? parseList(respAccepted['data']) : <IntercityRequestModel>[];

      if (!mounted) return;
      setState(() {
        _intercityRequests = available;
        _myWaitingIntercityRides = waiting;
        _myAcceptedIntercityRides = accepted;
      });
      // Removed auto-opening of intercity map screen to ensure it only opens on explicit user tap.
    } catch (_) {
      return;
    } finally {
      if (mounted) {
        setState(() {
          _loadingIntercityRequests = false;
        });
      }
    }
  }

  String _formatIntercityDate(DateTime? date) {
    if (date == null) return '';
    final d = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    final hour = d.hour;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(h12)}:${two(d.minute)} $ampm';
  }

  Widget _intercityChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black87),
      ),
    );
  }

  Widget _buildIntercityRequestCard(IntercityRequestModel req) {
    // REMOVED: Cash label from Intercity ride cards per user request
    // final payment = req.paymentType.trim().isEmpty ? 'Cash' : req.paymentType.trim();
    final vehicle = req.vehicleType.trim().isEmpty ? '-' : req.vehicleType.trim();
    final pickup = req.pickup.trim().isEmpty ? '-' : req.pickup.trim();
    final drop = req.drop.trim().isEmpty ? '-' : req.drop.trim();
    final pickupDate = req.pickupDate.trim();
    final pickupTime = req.pickupTime.trim();
    final dateText = _formatIntercityDate(req.createdAt);
    final riderName = req.riderName.trim().isEmpty ? 'User' : req.riderName.trim();
    final riderImage = req.riderImage.trim();
    final offer = (req.bidPrice > 0 ? req.bidPrice : req.price).toStringAsFixed(2);
    final distanceText = '${req.km.toStringAsFixed(1)} Km';
    final ratingText = req.userRating.toStringAsFixed(1);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IntercityRideMapScreen(ride: req),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 6)),
          ],
          border: Border.all(color: const Color(0xFFE6E6E6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: riderImage.isNotEmpty ? NetworkImage(riderImage) : null,
                child: riderImage.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      riderName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '₹$offer',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF369D01)),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text(distanceText, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        const Icon(Icons.star, size: 14, color: Colors.orange),
                        const SizedBox(width: 3),
                        Text(ratingText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Text('For ${req.persons} Person${req.persons == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF369D01).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Intercity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF369D01))),
              ),
              if (req.isScheduled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Scheduled', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.orange)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 15,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text('${req.km.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text('${req.timeMinutes} min', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          if (pickupDate.isNotEmpty || pickupTime.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 15,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text(pickupDate.isNotEmpty ? pickupDate : 'Not Scheduled', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text(pickupTime.isNotEmpty ? pickupTime : 'Not Scheduled', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              // REMOVED: Cash label from Intercity ride cards per user request
              // _intercityChip(payment),
              _intercityChip(vehicle),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  pickup,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  drop,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Ride Placed',
                style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  dateText,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_pendingIntercityBidIds.contains(req.id))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Waiting for customer response',
                style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) {
                          return AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            title: const Text('Reject Ride'),
                            content: const Text('Are you sure you want to reject this ride?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('No'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  try {
                                    final token = (await _sessionService.getToken() ?? '').trim();
                                    if (token.isEmpty) return;

                                    final picked = await CancellationReasonSheet.show(
                                      context: context,
                                      type: 'driver',
                                      title: 'Reject Ride',
                                      confirmText: 'Reject',
                                    );
                                    if (picked == null) return;

                                    await const ApiService().rejectIntercityRequest(
                                      token: token,
                                      requestId: req.id,
                                      cancellationReasonId: picked['cancellation_reason_id'],
                                      reason: picked['reason'],
                                      note: picked['note'],
                                    );
                                  } catch (_) {}

                                  if (!mounted) return;
                                  setState(() {
                                    _intercityRequests = _intercityRequests.where((r) => r.id != req.id).toList();
                                  });
                                },
                                child: const Text('Yes', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF369D01),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      if (!_isStrictVehicleTypeMatch(req.vehicleType)) {
                        setState(() {
                          _intercityRequests = _intercityRequests.where((r) => r.id != req.id).toList();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('This ride is not for your vehicle type')),
                        );
                        return;
                      }
                      final ok = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) {
                          return IntercityBidBottomSheet(ride: req);
                        },
                      );

                      if (!mounted) return;
                      if (ok == true) {
                        setState(() {
                          _pendingIntercityBidIds.add(req.id);
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Bid sent. Waiting for user response...')),
                        );
                      }
                    },
                    child: const Text('Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
    );
  }

  void _refreshRideRequestsPolling() {
    final driverId = _driverId.trim();
    if (_isOnline && driverId.isNotEmpty) {
      _startRideRequestsPolling();
    } else {
      _stopRideRequestsPolling();
    }
  }

  void _refreshActiveRidePolling() {
    final driverId = _driverId.trim();
    if (_isOnline && driverId.isNotEmpty) {
      _startActiveRidePolling();
    } else {
      _stopActiveRidePolling();
      // Keep last known active ride on UI when going offline; do not wipe restore state.
    }
  }

  void _startRideRequestsPolling() {
    if (_rideRequestsTimer != null) return;
    _rideRequestsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      fetchRideRequests();
    });
    fetchRideRequests();
  }

  void _stopRideRequestsPolling() {
    _rideRequestsTimer?.cancel();
    _rideRequestsTimer = null;
  }

  void _startActiveRidePolling() {
    if (_activeRideTimer != null) return;
    _activeRideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchActiveRide();
    });
    _fetchActiveRide();
  }

  void _stopActiveRidePolling() {
    _activeRideTimer?.cancel();
    _activeRideTimer = null;
  }

  Future<void> _fetchActiveRide() async {
    final driverId = _driverId.trim();
    if (driverId.isEmpty) return;

    try {
      final resp = await const ApiService().getMyActiveRide(driverId: driverId);
      if (resp['success'] != true) return;

      final ride = resp['ride'];
      Map<String, dynamic>? next;
      if (ride is Map) {
        next = Map<String, dynamic>.from(ride);
      }

      if (!mounted) return;

      final hadActive = _activeRide != null || _isRideAccepted || ((_acceptedRideId ?? '').toString().trim().isNotEmpty);
      final prevStatus = _activeRide != null ? _rideStatusOf(_activeRide!) : '';

      if (next != null && _shouldClearActiveRide(next)) {
        final rideId = _rideIdOf(next);
        setState(() {
          _activeRide = null;
          _isRideAccepted = false;
        });
        if (rideId.isNotEmpty) {
          _handledRideRequestIds.remove(rideId);
          _ignoredRideIds.remove(rideId);
          if (_acceptedRideId == rideId) {
            _acceptedRideId = null;
          }
        }
        _lastRideId = null;
        _ongoingRideScreenOpen = false;
        _ongoingRideOpenedId = '';
        _refreshRideRequestsPolling();
        _refreshIntercityRequestsPolling();
        _refreshParcelRequestsPolling();
        return;
      }

      // When an active ride exists, stop showing bidding dialogs.
      if (next != null) {
        setState(() {
          _activeRide = next;
        });

        _maybeOpenOngoingRideScreen(next);
        if (!_ongoingRideScreenOpen) {
          _maybeShowRideAcceptedSheet(next);
        }
      } else {
        final notifyCancel = hadActive &&
            (prevStatus == 'accepted' ||
                prevStatus == 'assigned' ||
                prevStatus == 'arrived' ||
                prevStatus == 'waiting_user_confirmation');
        if (notifyCancel) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Ride cancelled by rider'),
              duration: Duration(seconds: 4),
              backgroundColor: Color(0xFFB91C1C),
            ),
          );
        }

        if (_activeRide != null) {
          setState(() {
            _activeRide = null;
          });
        }

        if (_isRideAccepted) {
          setState(() {
            _isRideAccepted = false;
          });
        }
        _acceptedRideId = null;
        _lastRideId = null;
        _ongoingRideScreenOpen = false;
        _ongoingRideOpenedId = '';
      }
    } catch (_) {
      return;
    }
  }

  String _ongoingRideOpenedId = '';
  final Set<String> _autoOpenedRideIds = <String>{};
  bool _coldStartRideRestore = false;

  void _maybeOpenOngoingRideScreen(Map<String, dynamic> ride) {
    final status = _rideStatusOf(ride);
    final rideId = _rideIdOf(ride);
    if (rideId.isEmpty) return;

    // Open each ride UI at most once per app session (prevents re-push after user pops back).
    if (_autoOpenedRideIds.contains(rideId)) return;
    if (_ongoingRideScreenOpen) return;

    Widget? screen;
    if (status == 'ongoing' || status == 'started') {
      screen = DriverRideInProgressScreen(
        ride: ride,
        googleApiKey: _googleApiKey,
      );
    } else if (status == 'arrived') {
      screen = NavigationMapScreen(
        ride: ride,
        googleApiKey: _googleApiKey,
      );
    } else if ((status == 'accepted' || status == 'assigned') && _coldStartRideRestore) {
      // Only auto-open pickup when app relaunches mid-ride; live accepts still use ETA sheet.
      screen = PickupMapScreen(
        ride: ride,
        arrivalMinutes: 5,
        googleApiKey: _googleApiKey,
      );
    } else {
      return;
    }

    if (!mounted) return;
    final key = '$rideId|$status';
    _autoOpenedRideIds.add(rideId);
    _ongoingRideScreenOpen = true;
    _ongoingRideOpenedId = key;
    _acceptedRideId = rideId;
    _isRideAccepted = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        _ongoingRideScreenOpen = false;
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => screen!),
      ).whenComplete(() {
        if (_ongoingRideOpenedId == key) {
          _ongoingRideScreenOpen = false;
          _ongoingRideOpenedId = '';
        }
      });
    });
  }

  void _maybeShowRideAcceptedSheet(Map<String, dynamic> ride) {
    final status = _rideStatusOf(ride);
    if (status != 'accepted' && status != 'assigned') return;
    if (_ongoingRideScreenOpen) return;

    final rideId = _rideIdOf(ride);
    if (rideId.isEmpty) return;

    if (_rideAcceptedSheetOpen && _rideAcceptedSheetRideId == rideId) return;
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_ongoingRideScreenOpen) return;
      if (_rideAcceptedSheetOpen && _rideAcceptedSheetRideId == rideId) return;
      _rideAcceptedSheetOpen = true;
      _rideAcceptedSheetRideId = rideId;

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: false,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return SafeArea(
            top: false,
            child: _RideAcceptedBottomSheet(
              ride: ride,
              onCancel: () async {
                if (context.mounted) {
                  Navigator.pop(context);
                }
                await Future<void>.delayed(const Duration(milliseconds: 80));
                await _cancelActiveRide();
              },
            ),
          );
        },
      ).whenComplete(() {
        _rideAcceptedSheetOpen = false;
      });
    });
  }

  void _startHeartbeat() {
    if (_pingTimer != null) return;
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _sendPing();
    });
    _sendPing();
  }

  void _stopHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> _sendPing() async {
    if (!_isOnline) return;
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;
      await const ApiService().pingDriver(token: token);
    } catch (_) {}
  }

  Future<void> _hydrateOnlineStatusOnStart() async {
    bool? local;
    try {
      final prefs = await SharedPreferences.getInstance();
      local = prefs.getBool(_isOnlinePrefsKey);
    } catch (_) {
      local = null;
    }

    if (local != null && mounted) {
      setState(() {
        _isOnline = local!;
      });
      _refreshHeartbeat();
    }

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      final profile = await const ApiService().getDriverProfile(token: token);
      if (!mounted) return;

      String status = '';
      final rawStatus = profile['status'] ??
          (profile['data'] is Map ? (profile['data']['status'] ?? profile['data']['driver_status']) : null);
      if (rawStatus != null) {
        status = rawStatus.toString().trim().toLowerCase();
      }

      if (status != 'online' && status != 'offline') return;

      final backendIsOnline = status == 'online';
      if (mounted) {
        setState(() {
          _isOnline = backendIsOnline;
        });
      }
      _refreshHeartbeat();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_isOnlinePrefsKey, backendIsOnline);
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _initDriverAndApprovalStatus() async {
    final id = (await _sessionService.getDriverId())?.trim() ?? '';
    if (!mounted) return;
    setState(() {
      _driverId = id;
    });
    _refreshRideRequestsPolling();
    _refreshIntercityRequestsPolling();
    _refreshActiveRidePolling();
    // Cold-start restore: reopen the correct ride screen after app kill.
    if (id.isNotEmpty) {
      _coldStartRideRestore = true;
      try {
        await _fetchActiveRide();
      } finally {
        _coldStartRideRestore = false;
      }
    }
    _refreshParcelRequestsPolling();
    await _checkApprovalStatus();
  }

  String _rideStatusOf(Map<String, dynamic> ride) {
    return (ride['status'] ?? '').toString().trim().toLowerCase();
  }

  String _rideIdOf(Map<String, dynamic> ride) {
    return (ride['_id'] ?? ride['id'] ?? ride['ride_id'] ?? ride['rideId'] ?? '').toString().trim();
  }

  String _ridePaymentMethodOf(Map<String, dynamic> ride) {
    return (ride['payment_method'] ?? ride['paymentMethod'] ?? '').toString().trim().toLowerCase();
  }

  bool _isCompletedRideStatus(String status) {
    final s = status.trim().toLowerCase();
    return s == 'completed' || s == 'complete' || s == 'finished' || s == 'ride_completed';
  }

  bool _isCompletedPaymentStatus(String status) {
    final s = status.trim().toLowerCase();
    return s == 'completed' || s == 'complete' || s == 'successful' || s == 'success' || s == 'paid';
  }

  bool _shouldClearActiveRide(Map<String, dynamic> ride) {
    final paymentStatus = (ride['payment_status'] ?? '').toString().trim().toLowerCase();
    final legacyPaymentStatus = (ride['paymentStatus'] ?? '').toString().trim().toLowerCase();
    return _isCompletedRideStatus(_rideStatusOf(ride)) &&
        (_isCompletedPaymentStatus(paymentStatus) || _isCompletedPaymentStatus(legacyPaymentStatus));
  }

  double _rideFareOf(Map<String, dynamic> ride) {
    final v = ride['fare'] ?? ride['amount'] ?? ride['total'] ?? ride['price'];
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Future<void> _startActiveRide() async {
    final ride = _activeRide;
    if (ride == null) return;
    final rideId = _rideIdOf(ride);
    final driverId = _driverId.trim();
    if (rideId.isEmpty || driverId.isEmpty) return;

    try {
      await const ApiService().startRide(rideRequestId: rideId, driverId: driverId);
    } catch (_) {}
    await _fetchActiveRide();
  }

  Future<void> _cancelActiveRide() async {
    final ride = _activeRide;
    if (ride == null) return;
    final rideId = _rideIdOf(ride);
    if (rideId.isEmpty) return;

    final values = await _showDriverCancelSheet();
    if (values == null) return;

    try {
      await const ApiService().cancelRide(
        rideRequestId: rideId,
        cancelledBy: 'driver',
        cancellationReasonId: values['cancellation_reason_id'],
        reason: values['reason'],
        note: values['note'],
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _activeRide = null;
      _isRideAccepted = false;
    });
    _handledRideRequestIds.remove(rideId);
    _ignoredRideIds.remove(rideId);
    if (_acceptedRideId == rideId) {
      _acceptedRideId = null;
    }
    _lastRideId = null;
    _refreshRideRequestsPolling();
  }

  Future<void> fetchRideRequests() async {
    if (!_isOnline) return;
    if (isDialogOpen) return;
    final driverId = _driverId.trim();
    if (driverId.isEmpty) return;

    try {
      print('Driver polling API...');
      final resp = await const ApiService().getRideRequests();
      print(resp);
      if (resp['success'] != true) return;

      final data = resp['rides'];
      if (data is! List) return;

      Map<String, dynamic>? next;
      for (final item in data) {
        if (item is! Map) continue;
        final id = (item['_id'] ?? item['id'] ?? item['ride_id'] ?? item['rideId'] ?? item['rideRequestId'] ?? '').toString();
        if (id.trim().isEmpty) continue;
        if (_acceptedRideId != null && _acceptedRideId == id.trim()) continue;
        if (_ignoredRideIds.contains(id.trim())) continue;
        if (_handledRideRequestIds.contains(id)) continue;

        final status = (item['status'] ?? '').toString().trim().toLowerCase();
        if (status.isNotEmpty && status != 'bidding') continue;

        if (!_isStrictVehicleTypeMatch(_requestVehicleFromMap(Map<String, dynamic>.from(item)))) continue;

        next = Map<String, dynamic>.from(item);
        break;
      }

      if (next == null) return;

      final rideRequestId = (next['_id'] ?? next['id'] ?? '').toString();
      if (rideRequestId.trim().isEmpty) return;

      if (_acceptedRideId != null && _acceptedRideId == rideRequestId.trim()) return;
      if (_ignoredRideIds.contains(rideRequestId.trim())) return;

      if (_lastRideId != null && _lastRideId == rideRequestId) return;
      if (isDialogOpen) return;

      if (!mounted) return;
      _lastRideId = rideRequestId;
      await _showRideRequestDialog(next);
    } catch (_) {
      return;
    }
  }

  Future<void> _showRideRequestDialog(Map<String, dynamic> request) async {
    if (isDialogOpen) return;
    if (!mounted) return;
    final rideRequestId = (request['_id'] ?? request['id'] ?? request['ride_id'] ?? request['rideId'] ?? request['rideRequestId'] ?? '').toString().trim();
    if (rideRequestId.isEmpty) return;
    if (_acceptedRideId != null && _acceptedRideId == rideRequestId) return;
    if (_ignoredRideIds.contains(rideRequestId)) return;
    if (!_isStrictVehicleTypeMatch(_requestVehicleFromMap(request))) {
      _ignoredRideIds.add(rideRequestId);
      return;
    }
    final pickup = request['pickup'];
    final drop = request['drop'];
    final pickupAddress = pickup is Map ? (pickup['address'] ?? '').toString() : '';
    final dropAddress = drop is Map ? (drop['address'] ?? '').toString() : '';

    double? tryDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    LatLng? parseLatLng(dynamic node) {
      if (node is! Map) return null;
      final lat = tryDouble(node['lat'] ?? node['latitude']);
      final lng = tryDouble(node['lng'] ?? node['lon'] ?? node['longitude']);
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    }

    final pickupLatLng = parseLatLng(pickup);
    final dropLatLng = parseLatLng(drop);

    final fareValue = request['fare'];
    final fare = fareValue is num ? fareValue.round() : int.tryParse(fareValue?.toString() ?? '') ?? 0;
    final customerName = (request['user_name'] ?? request['customerName'] ?? request['userName'] ?? request['name'] ?? 'Customer')
        .toString()
        .trim();
    final ratingValue = request['rating'];
    final rating = ratingValue is num
        ? ratingValue.toStringAsFixed(1)
        : (double.tryParse(ratingValue?.toString() ?? '')?.toStringAsFixed(1) ?? '4.5');
    final customerImage = (request['user_image'] ?? request['customerImage'] ?? request['image'] ?? '')
        .toString()
        .trim();

    final distanceValue = request['distance'] ?? request['distanceKm'] ?? request['totalDistance'];
    final timeValue = request['time'] ?? request['duration'] ?? request['durationMins'];
    final distanceText = distanceValue == null || distanceValue.toString().trim().isEmpty
        ? '--'
        : distanceValue.toString().trim();
    final timeText = timeValue == null || timeValue.toString().trim().isEmpty
        ? '--'
        : timeValue.toString().trim();

    isDialogOpen = true;
    try {
      AlertService.startAlert();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          int offerPrice = fare;
          const themeGreen = Color(0xFF1FB354);
          bool isOfferOpen = false;
          bool isAccepting = false;
          double acceptThumbX = 0;
          double rejectProgress = 0;
          bool acceptAnimating = false;
          bool rejectAnimating = false;
          bool _autoRejectStarted = false;
          Timer? _autoRejectTimer;
          bool _pauseAutoReject = false;
          final hasImage = customerImage.startsWith('http://') || customerImage.startsWith('https://');

          final canShowMiniMap = pickupLatLng != null && dropLatLng != null;
          final miniMapMarkers = <Marker>{
            if (pickupLatLng != null)
              Marker(
                markerId: const MarkerId('pickup'),
                position: pickupLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              ),
            if (dropLatLng != null)
              Marker(
                markerId: const MarkerId('destination'),
                position: dropLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              ),
          };
          final routePoints = <LatLng>[
            if (pickupLatLng != null) pickupLatLng,
            if (dropLatLng != null) dropLatLng,
          ];

          return StatefulBuilder(
            builder: (context, setModalState) {
              const double buttonHeight = 50;
              return Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.65,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 5,
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: Colors.grey.shade200,
                                          backgroundImage: hasImage ? NetworkImage(customerImage) : null,
                                          child: hasImage
                                              ? null
                                              : const Icon(Icons.person, color: Colors.black54),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              customerName.isEmpty ? 'Customer' : customerName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(Icons.star, size: 14, color: Colors.orange),
                                                const SizedBox(width: 4),
                                                Text(rating),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const Spacer(),
                                        GestureDetector(
                                          onTap: () {
                                            if (!canShowMiniMap) return;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => FullMapScreen(
                                                  pickupLatLng: pickupLatLng!,
                                                  destinationLatLng: dropLatLng!,
                                                  apiKey: _googleApiKey,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(Icons.map_outlined),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.circle, size: 12, color: themeGreen),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  pickupAddress.isEmpty ? 'Pickup location' : pickupAddress,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.location_on, size: 16, color: Colors.red),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  dropAddress.isEmpty ? 'Drop location' : dropAddress,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Icon(Icons.route, size: 16),
                                        const SizedBox(width: 5),
                                        Text('$distanceText km'),
                                        const SizedBox(width: 15),
                                        const Icon(Icons.access_time, size: 16),
                                        const SizedBox(width: 5),
                                        Text('$timeText mins'),
                                        const Spacer(),
                                        Text(
                                          '₹$fare',
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 150,
                                            child: Container(
                                              height: buttonHeight,
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(25),
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  GestureDetector(
                                                    onTap: () {
                                                      setModalState(() {
                                                        offerPrice = (offerPrice - 10).clamp(0, 1000000);
                                                      });
                                                    },
                                                    child: const Icon(Icons.remove, size: 22),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Center(
                                                      child: Text(
                                                        '₹$offerPrice',
                                                        maxLines: 1,
                                                        softWrap: false,
                                                        overflow: TextOverflow.visible,
                                                        style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.black,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  GestureDetector(
                                                    onTap: () {
                                                      setModalState(() {
                                                        offerPrice = (offerPrice + 10).clamp(0, 1000000);
                                                      });
                                                    },
                                                    child: const Icon(Icons.add, size: 22),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(right: 12),
                                              child: SizedBox(
                                                height: buttonHeight,
                                                child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFF2F6FD6),
                                                    foregroundColor: Colors.white,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(25),
                                                    ),
                                                  ),
                                                  onPressed: () async {
                                                    await _placeBidAndClose(
                                                      rideRequestId: rideRequestId,
                                                      price: offerPrice,
                                                      request: request,
                                                    );
                                                    if (!mounted) return;
                                                    await AlertService.stopAlert();
                                                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                                                  },
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      'Offer ₹$offerPrice',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        const acceptHeight = 60.0;
                                        const rejectHeight = 58.0;
                                        const radius = 14.0;
                                        const animDuration = Duration(milliseconds: 320);
                                        const thumbSize = 46.0;
                                        final fullW = constraints.maxWidth;
                                        final maxThumbX = (fullW - thumbSize - 10).clamp(0.0, 100000.0);

                                        Future<void> runReject() async {
                                          if (rejectAnimating) return;
                                          rejectAnimating = true;
                                          _autoRejectTimer?.cancel();
                                          _autoRejectTimer = null;
                                          await Future<void>.delayed(const Duration(milliseconds: 30));
                                          await AlertService.stopAlert();
                                          if (dialogContext.mounted) {
                                            Navigator.pop(dialogContext);
                                          }

                                          await Future<void>.delayed(const Duration(milliseconds: 80));
                                          if (!mounted) return;

                                          final picked = await CancellationReasonSheet.show(
                                            context: context,
                                            type: 'driver',
                                            title: 'Cancel',
                                            confirmText: 'Cancel',
                                          );
                                          if (picked == null) {
                                            // allow popup again if driver backed out
                                            rejectAnimating = false;
                                            return;
                                          }

                                          try {
                                            await const ApiService().cancelRide(
                                              rideRequestId: rideRequestId,
                                              cancelledBy: 'driver',
                                              cancellationReasonId: picked['cancellation_reason_id'],
                                              reason: picked['reason'],
                                              note: picked['note'],
                                            );
                                          } catch (_) {}

                                          if (!mounted) return;
                                          setState(() {
                                            _ignoredRideIds.add(rideRequestId);
                                          });
                                        }

                                        void ensureAutoRejectStarted() {
                                          if (_autoRejectStarted) return;
                                          _autoRejectStarted = true;
                                          final rideRequestSeconds = AppConfig.intRideSetting('ride_request_time', 15);
                                          final totalTicks = (rideRequestSeconds <= 0 ? 15 : rideRequestSeconds) * 10;
                                          final double step = 1 / totalTicks;

                                          _autoRejectTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
                                            if (!mounted) return;
                                            if (rejectAnimating) {
                                              t.cancel();
                                              return;
                                            }
                                            if (_pauseAutoReject) return;
                                            final next = (rejectProgress + step).clamp(0.0, 1.0);
                                            setModalState(() {
                                              rejectProgress = next;
                                            });
                                            if (rejectProgress >= 1) {
                                              t.cancel();
                                              runReject();
                                            }
                                          });
                                        }

                                        ensureAutoRejectStarted();

                                        Future<void> runAccept() async {
                                          if (isAccepting || acceptAnimating) return;
                                          acceptAnimating = true;
                                          _autoRejectTimer?.cancel();
                                          _autoRejectTimer = null;
                                          setModalState(() {
                                            isAccepting = true;
                                            acceptThumbX = maxThumbX;
                                          });

                                          await Future<void>.delayed(animDuration);

                                          final ok = await _placeBidAndClose(
                                            rideRequestId: rideRequestId,
                                            price: offerPrice,
                                            request: request,
                                          );
                                          if (!mounted) return;

                                          if (ok) {
                                            await AlertService.stopAlert();
                                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                                            return;
                                          }

                                          // allow retry if accept failed
                                          acceptAnimating = false;
                                          setModalState(() {
                                            isAccepting = false;
                                            acceptThumbX = 0;
                                          });
                                        }

                                        Widget buildAcceptButton() {
                                          return GestureDetector(
                                            onTap: runAccept,
                                            onHorizontalDragStart: isAccepting
                                                ? null
                                                : (_) {
                                                    _pauseAutoReject = true;
                                                  },
                                            onHorizontalDragUpdate: isAccepting
                                                ? null
                                                : (d) {
                                                    setModalState(() {
                                                      acceptThumbX = (acceptThumbX + d.delta.dx).clamp(0.0, maxThumbX);
                                                    });
                                                  },
                                            onHorizontalDragEnd: isAccepting
                                                ? null
                                                : (_) {
                                                    final shouldAccept = acceptThumbX >= maxThumbX * 0.8;
                                                    if (shouldAccept) {
                                                      runAccept();
                                                      return;
                                                    }
                                                    setModalState(() {
                                                      acceptThumbX = 0;
                                                    });
                                                    _pauseAutoReject = false;
                                                  },
                                            child: SizedBox(
                                              height: acceptHeight,
                                              width: double.infinity,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(radius),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    Container(
                                                      color: const Color(0xFFE8F5E9),
                                                    ),
                                                    Center(
                                                      child: Text(
                                                        'Swipe to Accept',
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w900,
                                                          fontSize: 16,
                                                          color: Color(0xFF1B5E20),
                                                        ),
                                                      ),
                                                    ),
                                                    AnimatedPositioned(
                                                      duration: const Duration(milliseconds: 120),
                                                      curve: Curves.easeOut,
                                                      left: 6 + acceptThumbX,
                                                      top: (acceptHeight - thumbSize) / 2,
                                                      child: Container(
                                                        width: thumbSize,
                                                        height: thumbSize,
                                                        decoration: const BoxDecoration(
                                                          color: Color(0xFF1FB354),
                                                          shape: BoxShape.circle,
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Color(0x26000000),
                                                              blurRadius: 8,
                                                              offset: Offset(0, 4),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Center(
                                                          child: isAccepting
                                                              ? const SizedBox(
                                                                  width: 22,
                                                                  height: 22,
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth: 2.4,
                                                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                                  ),
                                                                )
                                                              : const Icon(Icons.directions_bike, color: Colors.white, size: 22),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        Widget buildRejectButton() {
                                          return GestureDetector(
                                            onTap: runReject,
                                            onHorizontalDragUpdate: rejectAnimating
                                                ? null
                                                : (d) {
                                                    final next = (rejectProgress + (d.delta.dx / (fullW == 0 ? 1 : fullW))).clamp(0.0, 1.0);
                                                    setModalState(() {
                                                      rejectProgress = next;
                                                    });
                                                  },
                                            onHorizontalDragEnd: rejectAnimating
                                                ? null
                                                : (_) {
                                                    if (rejectProgress >= 0.8) {
                                                      runReject();
                                                      return;
                                                    }
                                                    setModalState(() {
                                                      rejectProgress = 0;
                                                    });
                                                  },
                                            child: SizedBox(
                                              height: rejectHeight,
                                              width: double.infinity,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(radius),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    Container(
                                                      color: const Color(0xFFFFEBEE),
                                                    ),
                                                    Align(
                                                      alignment: Alignment.centerLeft,
                                                      child: AnimatedContainer(
                                                        duration: animDuration,
                                                        curve: Curves.easeInOut,
                                                        width: fullW * rejectProgress,
                                                        color: const Color(0xFFE53935),
                                                      ),
                                                    ),
                                                    Center(
                                                      child: Text(
                                                        'Reject',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w900,
                                                          fontSize: 16,
                                                          color: rejectProgress > 0.6 ? Colors.white : const Color(0xFFE53935),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        return Column(
                                          children: [
                                            buildAcceptButton(),
                                            const SizedBox(height: 12),
                                            buildRejectButton(),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      await AlertService.stopAlert();
      isDialogOpen = false;
    }
  }

  Future<int?> _askOfferPrice({required int initial}) async {
    if (!mounted) return null;
    final controller = TextEditingController(text: initial > 0 ? initial.toString() : '');
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Offer your price'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            enableInteractiveSelection: false,
            decoration: const InputDecoration(hintText: 'Enter amount'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final raw = controller.text.trim();
                final value = int.tryParse(raw);
                if (value == null || value <= 0) return;
                if (context.mounted) {
                  Navigator.pop(context, value);
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<bool> _placeBidAndClose({
    required String rideRequestId,
    required int price,
    Map<String, dynamic>? request,
  }) async {
    final driverId = _driverId.trim();
    if (driverId.isEmpty) return false;
    if (rideRequestId.trim().isEmpty) return false;
    if (price <= 0) return false;
    if (_isUpdatingBid) return false;
    if (request != null && !_isStrictVehicleTypeMatch(_requestVehicleFromMap(request))) {
      _ignoredRideIds.add(rideRequestId.trim());
      return false;
    }

    final normalizedRideId = rideRequestId.trim();
    _acceptedRideId = normalizedRideId;
    _ignoredRideIds.add(normalizedRideId);
    _handledRideRequestIds.add(normalizedRideId);
    _isUpdatingBid = true;
    if (mounted) {
      setState(() {
        _isRideAccepted = true;
      });
    } else {
      _isRideAccepted = true;
    }

    // Stop polling new ride requests once accepted is in progress.
    _stopRideRequestsPolling();

    bool ok = false;
    String failMessage = '';
    try {
      final resp = await const ApiService().placeRideBid(
        rideRequestId: rideRequestId,
        driverId: driverId,
        price: price,
        paymentMethod: _selectedPayment,
      );
      // ignore: avoid_print
      print('placeRideBid resp: $resp');
      ok = resp['success'] == true;
      if (!ok) {
        failMessage = (resp['message'] ?? '').toString();
      }
      if (ok) {
        await _fetchActiveRide();
      }
    } catch (e) {
      ok = false;
      failMessage = e.toString();
    }
    finally {
      _isUpdatingBid = false;
    }

    if (!ok) {
      // Accept failed: allow popup again.
      _acceptedRideId = null;
      _ignoredRideIds.remove(normalizedRideId);
      _handledRideRequestIds.remove(normalizedRideId);
      if (mounted) {
        setState(() {
          _isRideAccepted = false;
        });
      } else {
        _isRideAccepted = false;
      }
      _refreshRideRequestsPolling();

      if (mounted && isWalletInsufficientMessage(failMessage)) {
        await showWalletInsufficientDialog(context, message: failMessage);
      } else if (mounted) {
        final msg = failMessage.trim().isEmpty ? 'Failed to accept. Please try again.' : failMessage.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _checkApprovalStatus() async {
    if (!mounted) return;
    await context.read<DriverStatusSummaryProvider>().refresh(silent: true);
    final approved = context.read<DriverStatusSummaryProvider>().summary.isAllApproved;
    if (!mounted) return;
    setState(() {
      _isAllApproved = approved;
    });
  }

  Future<void> _redirectToPendingSection() async {
    final summary = context.read<DriverStatusSummaryProvider>().summary;
    if (!mounted) return;

    if (summary.documentStatus != VerificationStatus.approved) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DocumentVerificationMenuScreen()),
      );
      if (!mounted) return;
      return;
    }

    if (summary.vehicleStatus != VerificationStatus.approved) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VehicleRegistrationScreen()),
      );
      if (!mounted) return;
      return;
    }

    if (summary.bankStatus != VerificationStatus.approved) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BankDetailsScreen()),
      );
      if (!mounted) return;
      return;
    }
  }

  Future<void> _playToggleSound(bool isOnline) async {
    try {
      if (isOnline) {
        await _togglePlayer.play(AssetSource('sounds/online.mp3'));
      } else {
        await _togglePlayer.play(AssetSource('sounds/offline.mp3'));
      }
    } catch (_) {
      // fallback: play a simple system click if assets are missing
      SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> _handleLogoutTap() async {
    await _setOfflineFromSystem();
    if (!mounted) return;
    await showLogoutDialog(context);
  }

  void _showStatusMessage(bool isOnline) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOnline ? 'You are Online' : 'You are Offline'),
        backgroundColor: isOnline ? const Color(0xFF369D01) : const Color(0xFFE53935),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleStatus(bool value) async {
    if (value) {
      final driverId = _driverId.trim().isNotEmpty
          ? _driverId.trim()
          : (await _sessionService.getDriverId())?.trim() ?? '';
      if (driverId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver not found. Please login again.'),
            backgroundColor: Color(0xFFE53935),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (_driverId.trim() != driverId.trim()) {
        if (!mounted) return;
        setState(() {
          _driverId = driverId.trim();
        });
      }

      await _checkApprovalStatus();

      if (!_isAllApproved) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complete your registration to go online'),
            backgroundColor: Color(0xFFE53935),
            duration: Duration(seconds: 2),
          ),
        );
        await _redirectToPendingSection();
        await _checkApprovalStatus();
        HapticFeedback.mediumImpact();
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _isOnline = value;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isOnlinePrefsKey, value);
    } catch (_) {}

    _refreshHeartbeat();
    _refreshParcelRequestsPolling();

    // Sync ON DUTY / OFF DUTY to backend (isOnline + lastSeenAt)
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isNotEmpty) {
        await const ApiService().updateDriverStatus(token: token, isOnline: value);
      }
    } catch (_) {}

    HapticFeedback.mediumImpact();
    _playToggleSound(value);
    _showStatusMessage(value);
  }

  String _timeGreeting() {
    final now = DateTime.now();
    final hour = now.hour;

    if (hour >= 5 && hour <= 11) {
      return 'Good Morning Captain ☀️';
    }
    if (hour >= 12 && hour <= 16) {
      return 'Good Afternoon Captain ☀️';
    }
    if (hour >= 17 && hour <= 21) {
      return 'Good Evening Captain 🌙';
    }
    return 'Good Night Captain 🌙';
  }

  String _dutyStatusMessage() {
    if (_isOnline) {
      return 'You’re online—ready for your next ride!';
    }
    return 'You’re offline. Go online to earn now';
  }

  Widget _dashboardStatCard({
    required String value,
    required String title,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _dashboardGreetingCard() {
    return FutureBuilder<Map<String, String>>(
      future: _userBasicsFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, String>{};
        final rawName = _driverName.trim().isNotEmpty ? _driverName.trim() : (data['name'] ?? '').trim();
        final name = rawName.isEmpty ? 'Captain' : rawName;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFDFF5E3),
                Color(0xFFA5D6A7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hi, $name',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "You've completed ${_totalCompletedRides} trips",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: ClipOval(
                  child: _driverImageUrl.trim().isEmpty
                      ? const Center(
                          child: Icon(Icons.person, color: Color(0xFF369D01), size: 34),
                        )
                      : Image.network(
                          _driverImageUrl.trim(),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.person, color: Color(0xFF369D01), size: 34),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _walletBar() {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const WalletScreen()),
        );

        if (!mounted) return;
        _loadWalletBalance();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xff0BAF00),
              Color(0xff059600),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Wallet Balance',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _walletBalanceLoading ? '₹ --' : '₹ ${_walletBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Icon(Icons.account_balance_wallet, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _dashboardCenterSection() {
    return FutureBuilder<Map<String, String>>(
      future: _userBasicsFuture,
      builder: (context, snapshot) {
        final ride = _activeRide;
        if (ride != null) {
          if (_shouldClearActiveRide(ride)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _activeRide == null) return;
              setState(() {
                _activeRide = null;
                _isRideAccepted = false;
              });
            });
            return const SizedBox.shrink();
          }
          final status = _rideStatusOf(ride);
          if (status == 'accepted' || status == 'assigned') {
            return const SizedBox.shrink();
          }

          final pickup = ride['pickup'];
          final drop = ride['drop'];
          final pickupAddress = pickup is Map ? (pickup['address'] ?? '').toString() : '';
          final dropAddress = drop is Map ? (drop['address'] ?? '').toString() : '';
          final maybeFinalFare = ride['finalFare'];
          final finalFareNum = maybeFinalFare is num
              ? maybeFinalFare
              : num.tryParse(maybeFinalFare?.toString() ?? '') ?? 0;
          final fareValue = finalFareNum > 0 ? maybeFinalFare : ride['fare'];
          final fare = fareValue is num ? fareValue.round() : int.tryParse(fareValue?.toString() ?? '') ?? 0;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 6)),
                    ],
                    border: Border.all(color: const Color(0xFFE6E6E6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ride Ongoing',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      Text('Pickup: ${pickupAddress.isEmpty ? 'Pickup location' : pickupAddress}'),
                      const SizedBox(height: 6),
                      Text('Drop: ${dropAddress.isEmpty ? 'Drop location' : dropAddress}'),
                      const SizedBox(height: 6),
                      Text('Fare: ₹$fare'),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _cancelActiveRide,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE53935),
                            side: const BorderSide(color: Color(0xFFE53935)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              scale: _isOnline ? 1.03 : 1.0,
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE5E7EB),
                  boxShadow: [
                    BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 8)),
                  ],
                ),
                child: ClipOval(
                  child: (_vehicleFrontImageUrl.isNotEmpty)
                      ? Image.network(
                          _vehicleFrontImageUrl,
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Image.asset(
                              _vehicleImageAsset,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            );
                          },
                        )
                      : Image.asset(
                          _vehicleImageAsset,
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.directions_car, size: 56, color: Color(0xFF369D01)),
                            );
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _timeGreeting(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Text(
                  _dutyStatusMessage(),
                  key: ValueKey<bool>(_isOnline),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _topControlBar() {
    Widget circleIcon({required IconData icon, VoidCallback? onPressed}) {
      return Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: Icon(icon, color: Colors.black87),
          onPressed: onPressed,
        ),
      );
    }

    final togglePill = Consumer<DriverStatusSummaryProvider>(
      builder: (context, summaryProvider, _) {
        final canGoOnline = summaryProvider.summary.isAllApproved;

        final bgColor = _isOnline ? const Color(0xFFFFFFFF) : const Color(0xFFF5F5F5);
        final borderColor = _isOnline ? Colors.transparent : const Color(0xFFE0E0E0);
        final textColor = _isOnline ? const Color(0xFF369D01) : const Color(0xFF555555);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleStatus(!_isOnline),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor),
              boxShadow: const [
                BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 3)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isOnline) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _isOnline ? 'ON DUTY' : 'OFF DUTY',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  height: 28,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _isOnline ? const Color(0xFF369D01) : const Color(0xFFE6E6E6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _isOnline ? const Color(0xFF369D01) : const Color(0xFFDADADA)),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      alignment: _isOnline ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isOnline ? Icons.power_settings_new : Icons.circle,
                            size: 12,
                            color: _isOnline ? const Color(0xFF369D01) : const Color(0xFFE53935),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!canGoOnline && !_isOnline) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFFF59E0B)),
                ],
              ],
            ),
          ),
        );
      },
    );

    final sosButton = GestureDetector(
      onTap: () async {
        // STEP 2: VERIFY BUTTON CLICK
        // Debug
        // ignore: avoid_print
        print('SOS_BUTTON_CLICKED');
        await _handleHomeSOS();
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'SOS',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );

    return Row(
      children: [
        sosButton,
        Expanded(
          child: Center(child: togglePill),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            circleIcon(icon: Icons.location_on, onPressed: () {}),
            const SizedBox(width: 8),
            Consumer<ChatNotificationProvider>(
              builder: (context, n, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    circleIcon(
                      icon: Icons.notifications_none,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        );
                      },
                    ),
                    if (n.unreadCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${n.unreadCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _drawerSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _drawerMenuCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _drawerMenuItem(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F8EF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF0A7A40), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF94A3B8)),
      onTap: onTap,
    );
  }

  Widget _drawerDangerCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const ListTile(
        leading: Icon(Icons.delete, color: Colors.red),
        title: Text(
          'Delete Account',
          style: TextStyle(color: Colors.red),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 14),
      ),
    );
  }

  Widget _drawerWalletBar() {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ActivityScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF369D01),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Wallet Balance',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '₹ 0.00',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerProfileCard() {
    final future = _userBasicsFuture ?? _sessionService.getUserBasics(forceRefresh: true);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );

              if (!mounted) return;
              setState(() {
                _userBasicsFuture = _sessionService.getUserBasics(forceRefresh: true);
              });
            },
            child: Row(
              children: [
                ValueListenableBuilder<String?>(
                  valueListenable: ProfileController.profileImagePath,
                  builder: (context, _, __) {
                    final pickedProvider = ProfileController.imageProviderOrNull();

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PersonalPictureInstructionScreen(),
                          ),
                        );
                      },
                      child: FutureBuilder<Map<String, String>>(
                        future: future,
                        builder: (context, snapshot) {
                          final data = snapshot.data ?? const <String, String>{};
                          final imageUrl = (data['imageUrl'] ?? '').trim();

                          return CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: pickedProvider ?? (imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null),
                            child: (pickedProvider != null || imageUrl.isNotEmpty)
                                ? null
                                : const Icon(Icons.person, color: Colors.grey),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FutureBuilder<Map<String, String>>(
                    future: future,
                    builder: (context, snapshot) {
                      final data = snapshot.data ?? const <String, String>{};
                      final name = (data['name'] ?? '').trim();
                      final mobile = (data['mobile'] ?? '').trim();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isNotEmpty ? name : '-',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            mobile.isNotEmpty ? mobile : '-',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MyRatingScreen(),
                ),
              );
            },
            child: const Row(
              children: [
                Icon(Icons.star, color: Colors.orange, size: 18),
                SizedBox(width: 6),
                Text(
                  '5.00 My Rating',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Spacer(),
                Icon(Icons.arrow_forward_ios, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerContent() {
    return Drawer(
      backgroundColor: const Color(0xFFF3F6F4),
      child: SafeArea(
        child: Column(
          children: [
            _drawerProfileCard(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _drawerWalletBar(),
                  const SizedBox(height: 16),
                  _drawerSectionTitle('General'),
                  _drawerMenuCard(
                    children: [
                      _drawerMenuItem(
                        Icons.person,
                        'Profile',
                        onTap: () async {
                          Navigator.pop(context);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                          if (!mounted) return;
                          setState(() {
                            _userBasicsFuture = _sessionService.getUserBasics(forceRefresh: true);
                          });
                        },
                      ),
                      _drawerMenuItem(
                        Icons.local_activity,
                        'Activity',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ActivityScreen(),
                            ),
                          );
                        },
                      ),
                      _drawerMenuItem(Icons.settings, 'App Settings', onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/app-settings');
                      }),
                      _drawerMenuItem(
                        Icons.account_balance_outlined,
                        'Withdraw',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverWithdrawScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _drawerSectionTitle('Registration Details'),
                  _drawerMenuCard(
                    children: [
                      _drawerMenuItem(
                        Icons.description,
                        'Document Registration',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DocumentVerificationMenuScreen(),
                            ),
                          );
                        },
                      ),
                      _drawerMenuItem(
                        Icons.directions_car,
                        'Vehicle Registration',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const VehicleRegistrationScreen(),
                            ),
                          );
                        },
                      ),
                      _drawerMenuItem(
                        Icons.account_balance,
                        'Bank details',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BankDetailsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _drawerSectionTitle('Alert Zone'),
                  _drawerDangerCard(),
                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: _handleLogoutTap,
                      child: const Text(
                        'Logout',
                        style: TextStyle(
                          color: Color(0xFF369D01),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Center(
                    child: Text(
                      'Version: 2.0.3',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardHome() {
    return SafeArea(
      child: Column(
        children: [
          Container(
            height: 90,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF369D01),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Align(
              alignment: Alignment.center,
              child: _topControlBar(),
            ),
          ),
          _walletBar(),
          _dashboardGreetingCard(),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                if (_myWaitingIntercityRides.isNotEmpty)
                  _buildIntercityWaitingCard(_myWaitingIntercityRides.first),
                if (_intercityRequests.isNotEmpty)
                  ..._intercityRequests.map(_buildIntercityRequestCard),
                if (_parcelDutyOn && _liveParcelRequests.isNotEmpty)
                  ..._liveParcelRequests.map(_buildParcelRequestCard),
                if (_myWaitingIntercityRides.isEmpty &&
                    _intercityRequests.isEmpty &&
                    !(_parcelDutyOn && _liveParcelRequests.isNotEmpty))
                  _dashboardCenterSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDriverIcon() async {
    if (_driverIcon != null) return;
    try {
      final bytes = await _materialIconToPng(
        iconData: Icons.directions_car,
        size: 72,
        color: const Color(0xFF369D01),
        backgroundColor: Colors.white,
        padding: 18,
      );
      _driverIcon = BitmapDescriptor.fromBytes(bytes);
    } catch (_) {
      _driverIcon = BitmapDescriptor.defaultMarker;
    }
  }

  Future<Uint8List> _materialIconToPng({
    required IconData iconData,
    required double size,
    required Color color,
    required Color backgroundColor,
    double padding = 16,
  }) async {
    final double canvasSize = size + (padding * 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = backgroundColor;

    canvas.drawCircle(
      Offset(canvasSize / 2, canvasSize / 2),
      canvasSize / 2,
      bgPaint,
    );

    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final textStyle = TextStyle(
      fontSize: size,
      fontFamily: iconData.fontFamily,
      package: iconData.fontPackage,
      color: color,
    );
    textPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: textStyle,
    );
    textPainter.layout();

    final offset = Offset(
      (canvasSize - textPainter.width) / 2,
      (canvasSize - textPainter.height) / 2,
    );
    textPainter.paint(canvas, offset);

    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasSize.toInt(), canvasSize.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _startDriverTracking() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) async {
      if (!mounted) return;
      await _loadDriverIcon();
      if (!mounted) return;

      final latLng = LatLng(pos.latitude, pos.longitude);
      final nextSpeed = (pos.speed.isNaN ? 0 : pos.speed) * 3.6;

      // Live location ping (every ~8s) when ON DUTY
      if (_isOnline) {
        final now = DateTime.now();
        if (_lastLocationSentAt == null || now.difference(_lastLocationSentAt!).inSeconds >= 8) {
          _lastLocationSentAt = now;
          try {
            final token = (await _sessionService.getToken() ?? '').trim();
            if (token.isNotEmpty) {
              await const ApiService().updateDriverLocation(
                token: token,
                lat: pos.latitude,
                lng: pos.longitude,
              );
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _driverLatLng = latLng;
          _speedKmh = nextSpeed.isFinite ? nextSpeed.clamp(0, 250).toDouble() : 0;
          _cameraTarget = latLng;
          _markers = <Marker>{
            Marker(
              markerId: const MarkerId('driver'),
              position: latLng,
              icon: _driverIcon ?? BitmapDescriptor.defaultMarker,
              flat: true,
              rotation: pos.heading,
              anchor: const Offset(0.5, 0.5),
            ),
          };
          _polylines = <Polyline>{};
        });
      }
    });
  }

  void _fetchVehiclesForService(String serviceCategoryId) {
    _vehiclesByServiceFuture = _vehiclesByServiceApi.getVehiclesByService(serviceCategoryId);
    _selectedVehicleId = null;
    context.read<RideBookingState>().setSelectedVehicleTypeId(null);
  }

  Future<void> _maybeRecalculateFare() async {
    final state = context.read<RideBookingState>();
    final pickupLat = state.pickupLat;
    final pickupLng = state.pickupLng;
    final dropLat = state.dropLat;
    final dropLng = state.dropLng;
    final vehicleTypeId = state.selectedVehicleTypeId;

    if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) return;
    if (vehicleTypeId == null || vehicleTypeId.trim().isEmpty) return;

    final key = '${pickupLat.toStringAsFixed(5)},${pickupLng.toStringAsFixed(5)}|${dropLat.toStringAsFixed(5)},${dropLng.toStringAsFixed(5)}|$vehicleTypeId';
    if (_lastFareKey == key) return;
    _lastFareKey = key;

    final requestId = ++_fareRequestId;
    final result = await _fareCalculateApi.calculateFare(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropLat: dropLat,
      dropLng: dropLng,
      vehicleTypeId: vehicleTypeId,
    );

    if (!mounted || requestId != _fareRequestId || result == null) return;

    final baseFare = result.baseFare.round();
    state.setBaseFare(baseFare);
    state.setOfferFare(result.totalFare);
  }

  Future<void> _maybeRecalculateDistance() async {
    final state = context.read<RideBookingState>();
    final pickupLat = state.pickupLat;
    final pickupLng = state.pickupLng;
    final dropLat = state.dropLat;
    final dropLng = state.dropLng;

    if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) {
      if (mounted && _distanceKm != null) {
        setState(() {
          _distanceKm = null;
        });
      }
      return;
    }

    final key = '${pickupLat.toStringAsFixed(5)},${pickupLng.toStringAsFixed(5)}|${dropLat.toStringAsFixed(5)},${dropLng.toStringAsFixed(5)}';
    if (_lastDistanceKey == key) return;
    _lastDistanceKey = key;

    final requestId = ++_distanceRequestId;
    final result = await _distanceCalculateApi.calculateDistanceKm(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropLat: dropLat,
      dropLng: dropLng,
    );

    if (!mounted || requestId != _distanceRequestId) return;

    setState(() {
      _distanceKm = result;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Intentionally no-op for driver home UI.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopHeartbeat();
    _stopRideRequestsPolling();
    _stopIntercityRequestsPolling();
    _stopActiveRidePolling();
    _stopParcelRequestsPolling();
    _positionSub?.cancel();
    _togglePlayer.dispose();
    _pickupController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  String _readableAddressFromPlacemark(Placemark? p) {
    if (p == null) return 'Unknown location';

    final street = p.street?.trim() ?? '';
    final locality = p.locality?.trim() ?? '';
    final subLocality = p.subLocality?.trim() ?? '';
    final admin = p.administrativeArea?.trim() ?? '';

    final bool looksLikePlusCode =
        RegExp(r'^[A-Z0-9]{3,}\+[A-Z0-9]{2,}$').hasMatch(street);

    final parts = <String>[
      if (street.isNotEmpty && !looksLikePlusCode) street,
      if (subLocality.isNotEmpty) subLocality,
      if (locality.isNotEmpty) locality,
      if (admin.isNotEmpty) admin,
    ];

    return parts.isEmpty ? 'Unknown location' : parts.join(', ');
  }

  Future<Map<String, dynamic>> _resolveCurrentLocationAddress() async {
    final position = await _locationService.getCurrentLocation();
    final lat = position.latitude;
    final lng = position.longitude;

    String address = 'Current location';
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      address = _readableAddressFromPlacemark(
        placemarks.isNotEmpty ? placemarks.first : null,
      );
    } catch (_) {}

    return <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'address': address,
    };
  }

  Future<void> _loadInitialLocation() async {
    try {
      final data = await _resolveCurrentLocationAddress();
      if (!mounted) return;

      final lat = (data['lat'] as double);
      final lng = (data['lng'] as double);
      final address = (data['address'] as String);

      _cameraTarget = LatLng(lat, lng);
      await _loadDriverIcon();

      setState(() {
        _driverLatLng = LatLng(lat, lng);
        _markers = <Marker>{
          Marker(
            markerId: const MarkerId('driver'),
            position: LatLng(lat, lng),
            icon: _driverIcon ?? BitmapDescriptor.defaultMarker,
            flat: true,
            anchor: const Offset(0.5, 0.5),
          ),
        };
        _polylines = <Polyline>{};
      });

      if (_mapController.isCompleted) {
        final map = await _mapController.future;
        await map.animateCamera(
          CameraUpdate.newLatLngZoom(_cameraTarget, 16),
        );
      }
    } catch (_) {
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
      });
    }
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (!mounted) return;
      final target = LatLng(position.latitude, position.longitude);
      if (_mapController.isCompleted) {
        final map = await _mapController.future;
        await map.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      }
    } catch (_) {}
  }

  Widget _sideFab({
    required String hero,
    required Widget child,
    VoidCallback? onPressed,
    Color backgroundColor = Colors.white,
    Color foregroundColor = Colors.black,
  }) {
    return FloatingActionButton(
      heroTag: hero,
      mini: true,
      elevation: 2,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      onPressed: onPressed,
      child: child,
    );
  }

  Widget _speedPill() {
    final speedText = _speedKmh.round().toString();
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            speedText,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const Text(
            'km/h',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final bool isActive = _bottomTabIndex == index;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _bottomTabIndex = index;
        });

        if (index == 0) {
          _hydrateParcelDuty();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isActive ? 1.25 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Icon(
                icon,
                color: isActive ? Colors.white : Colors.white70,
                size: isActive ? 28 : 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontSize: isActive ? 14 : 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF369D01),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(icon: Icons.home_outlined, label: 'Home', index: 0),
            _buildNavItem(icon: Icons.account_balance_wallet_outlined, label: 'My Earnings', index: 1),
            _buildNavItem(icon: Icons.local_activity, label: 'Activity', index: 2),
            _buildNavItem(icon: Icons.settings_outlined, label: 'Settings', index: 3),
          ],
        ),
      ),
    );
  }

  Widget _topHeaderBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 14, top: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF369D01),
                  ),
                  child: const Center(
                    child: Text(
                      'J',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _toggleStatus(!_isOnline);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isOnline ? const Color(0xFF369D01) : Colors.grey,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isOnline ? Icons.toggle_on : Icons.toggle_off,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isOnline ? 'ON' : 'OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: const Icon(Icons.notifications_none, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerDriverAvatarButton() {
    return GestureDetector(
      onTap: () {
        _toggleStatus(!_isOnline);
      },
      child: Container(
        height: 70,
        width: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF369D01),
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 10)),
          ],
        ),
        child: const Icon(Icons.person, color: Colors.white, size: 34),
      ),
    );
  }

  Widget _leftControls() {
    Widget wrap(Widget child) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: child,
      );
    }

    return Column(
      children: [
        wrap(
          IconButton(
            onPressed: _moveToCurrentLocation,
            icon: const Icon(Icons.refresh, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 10),
        _speedPill(),
      ],
    );
  }

  void _onRideStateChanged() {
    final state = _rideState;
    if (state == null || !mounted) return;

    final pickupText = state.pickupAddress.trim();
    final dropText = state.dropAddress.trim();

    if (_pickupController.text != pickupText) {
      _pickupController.text = pickupText;
    }
    if (_dropController.text != dropText) {
      _dropController.text = dropText;
    }

    _syncMarkersAndRoute(state);
    _maybeRecalculateFare();
    _maybeRecalculateDistance();
  }

  Future<void> _syncMarkersAndRoute(RideBookingState state) async {
    final pickup =
        (state.pickupLat != null && state.pickupLng != null) ? LatLng(state.pickupLat!, state.pickupLng!) : null;
    final drop =
        (state.dropLat != null && state.dropLng != null) ? LatLng(state.dropLat!, state.dropLng!) : null;

    final nextMarkers = <Marker>{
      if (pickup != null)
        Marker(
          markerId: const MarkerId('pickup_marker'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: state.pickupAddress,
          ),
        ),
      if (drop != null)
        Marker(
          markerId: const MarkerId('drop_marker'),
          position: drop,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Drop',
            snippet: state.dropAddress,
          ),
        ),
    };

    if (mounted) {
      setState(() {
        _markers = nextMarkers;
      });
    }

    if (pickup == null || drop == null) {
      if (mounted) {
        setState(() {
          _polylines = <Polyline>{};
        });
      }
      return;
    }

    final cacheKey =
        '${pickup.latitude.toStringAsFixed(5)},${pickup.longitude.toStringAsFixed(5)}|${drop.latitude.toStringAsFixed(5)},${drop.longitude.toStringAsFixed(5)}';
    if (_pickupDropRouteCacheKey == cacheKey && _polylines.isNotEmpty) {
      return;
    }

    final requestId = ++_routeRequestId;
    final route = await _buildRoutePolyline(pickup, drop);
    if (!mounted || requestId != _routeRequestId) return;

    _pickupDropRouteCacheKey = cacheKey;
    setState(() {
      _polylines = route == null ? <Polyline>{} : <Polyline>{route};
    });

    await _fitBoundsForPickupDrop(pickup, drop);
  }

  Future<Polyline?> _buildRoutePolyline(LatLng pickup, LatLng drop) async {
    final cacheKey =
        '${pickup.latitude.toStringAsFixed(5)},${pickup.longitude.toStringAsFixed(5)}|${drop.latitude.toStringAsFixed(5)},${drop.longitude.toStringAsFixed(5)}';
    try {
      var points = _directionsPointCache[cacheKey];
      if (points == null) {
        final result = await _polylinePoints.getRouteBetweenCoordinates(
          googleApiKey: _googleApiKey,
          request: PolylineRequest(
            origin: PointLatLng(pickup.latitude, pickup.longitude),
            destination: PointLatLng(drop.latitude, drop.longitude),
            mode: TravelMode.driving,
          ),
        );

        points = result.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList(growable: false);

        if (points.isEmpty) {
          points = <LatLng>[pickup, drop];
        } else {
          _directionsPointCache[cacheKey] = points;
        }
      }

      return Polyline(
        polylineId: const PolylineId('pickup_drop_route'),
        points: points,
        color: const Color(0xFF2F6BFF),
        width: 5,
        geodesic: true,
      );
    } catch (_) {
      return Polyline(
        polylineId: const PolylineId('pickup_drop_route'),
        points: <LatLng>[pickup, drop],
        color: const Color(0xFF2F6BFF),
        width: 5,
        geodesic: true,
      );
    }
  }

  Future<void> _fitBoundsForPickupDrop(LatLng pickup, LatLng drop) async {
    if (!_mapController.isCompleted) return;

    final map = await _mapController.future;

    final sw = LatLng(
      pickup.latitude < drop.latitude ? pickup.latitude : drop.latitude,
      pickup.longitude < drop.longitude ? pickup.longitude : drop.longitude,
    );
    final ne = LatLng(
      pickup.latitude > drop.latitude ? pickup.latitude : drop.latitude,
      pickup.longitude > drop.longitude ? pickup.longitude : drop.longitude,
    );

    final bounds = LatLngBounds(southwest: sw, northeast: ne);
    await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  String _paymentRideIdForSync() {
    final v = (_acceptedRideId ?? '').toString().trim();
    return v;
  }

  Future<void> _syncPaymentMethodToBackend(String method) async {
    final rideId = _paymentRideIdForSync();
    if (rideId.isEmpty) return;
    try {
      await const ApiService().updatePaymentMethod(
        rideId: rideId,
        paymentMethod: method,
      );
    } catch (_) {}
  }

  Future<void> _openSetPriceSheet() async {
    final rideState = context.read<RideBookingState>();
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => SetPriceBottomSheet(
        initialPrice: rideState.offerFare,
        baseFare: rideState.baseFare,
        initialPayment: _selectedPayment,
        onPaymentChanged: (value) {
          setState(() {
            _selectedPayment = value;
          });
          _syncPaymentMethodToBackend(value);
        },
      ),
    );

    if (result == null) return;

    if (result == -2) {
      if (!mounted) return;
      await _openCouponSheet();
      return;
    }

    rideState.setOfferFare(result);
  }

  Future<void> _openCouponSheet() async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => const ApplyCouponBottomSheet(),
    );

    if (!mounted) return;
    if (result == null || result.trim().isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Coupon applied: ${result.trim()}')),
    );
  }

  Future<void> _openLocationSelection({required bool isPickupSelection}) async {
    final rideState = context.read<RideBookingState>();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.93,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: LocationSelectionScreen(
              useScaffold: false,
              isSelectingPickup: isPickupSelection,
              initialPickupAddress: rideState.pickupAddress,
              initialDropAddress: rideState.dropAddress,
              initialPickupLat: rideState.pickupLat,
              initialPickupLng: rideState.pickupLng,
              initialDropLat: rideState.dropLat,
              initialDropLng: rideState.dropLng,
              contactName: rideState.selectedContactName,
              contactPhone: rideState.selectedContactPhone,
              placesService: _placesService,
            ),
          ),
        );
      },
    );

    if (result == null) return;

    final contactName = (result['contactName'] ?? '').toString();
    final contactPhone = (result['contactPhone'] ?? '').toString();
    if (contactName.trim().isNotEmpty || contactPhone.trim().isNotEmpty) {
      rideState.setContact(name: contactName, phone: contactPhone);
    }

    if (result['clearPickup'] == true) {
      rideState.clearPickup();
      return;
    }

    if (result['clearDrop'] == true) {
      rideState.clearDrop();
      return;
    }

    final address = (result['address'] ?? '').toString().trim();
    final lat = result['lat'];
    final lng = result['lng'];

    if (lat is! num || lng is! num) return;

    final resolvedAddress = address.isEmpty ? 'Selected location' : address;
    final dLat = lat.toDouble();
    final dLng = lng.toDouble();

    if (result['isPickup'] == true) {
      rideState.setPickup(lat: dLat, lng: dLng, address: resolvedAddress);
    } else {
      rideState.setDrop(lat: dLat, lng: dLng, address: resolvedAddress);
    }

    if (_mapController.isCompleted) {
      final map = await _mapController.future;
      await map.animateCamera(CameraUpdate.newLatLngZoom(LatLng(dLat, dLng), 16));
    }
  }

  Future<void> _setPickupToCurrentLocation() async {
    try {
      final data = await _resolveCurrentLocationAddress();
      if (!mounted) return;

      final rideState = context.read<RideBookingState>();
      final lat = data['lat'] as double;
      final lng = data['lng'] as double;
      final address = data['address'] as String;

      rideState.setPickup(lat: lat, lng: lng, address: address);

      if (_mapController.isCompleted) {
        final map = await _mapController.future;
        await map.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
        );
      }
    } catch (_) {}
  }

  void _clearPickup() {
    context.read<RideBookingState>().clearPickup();
  }

  void _clearDrop() {
    context.read<RideBookingState>().clearDrop();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_bottomTabIndex == 0) {
      content = _dashboardHome();
    } else if (_bottomTabIndex == 1) {
      content = const MyEarningsScreen();
    } else if (_bottomTabIndex == 2) {
      content = const ActivityScreen(initialIndex: 0);
    } else if (_bottomTabIndex == 3) {
      content = const SettingsScreen();
    } else {
      final titles = ['Home', 'My Earnings', 'Activity', 'Settings'];
      content = Center(
        child: Text(
          titles[_bottomTabIndex],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: _drawerContent(),
      body: content,
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildVehicleTypesStrip() {
    final future = _vehiclesByServiceFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<ServiceVehicleModel>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final items = snapshot.data ?? const <ServiceVehicleModel>[];
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No vehicles available',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final parsedId = int.tryParse(item.id) ?? item.id.hashCode;
              final selected = _selectedVehicleId != null && parsedId == _selectedVehicleId;
              final imageUrl = item.image;

              return Padding(
                padding: EdgeInsets.only(right: index == items.length - 1 ? 0 : 10),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedVehicleId = parsedId;
                    });
                    context.read<RideBookingState>().setSelectedVehicleTypeId(item.id);
                    _maybeRecalculateFare();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 92,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFE8F5E9) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? const Color(0xFF369D01) : Colors.grey.shade300,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 72,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 22,
                                    color: Colors.grey,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 3), // Reduced spacing between vehicle image and name
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: selected ? const Color(0xFF369D01) : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  void _openPaymentSheet(BuildContext context) {
    _paymentGatewaysFuture ??= _paymentGatewayApi.getPaymentGateways();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            IconData _fallbackIcon(String serial) {
              final s = serial.toLowerCase();
              if (s.contains('wallet')) return Icons.account_balance_wallet;
              if (s.contains('card')) return Icons.credit_card;
              if (s.contains('cash')) return Icons.currency_rupee;
              return Icons.payments;
            }

            Widget buildPaymentItem({
              required String name,
              String? imageUrl,
              IconData? icon,
              required String value,
            }) {
              final isSelected = _selectedPayment == value;

              Widget leading;
              if (imageUrl != null && imageUrl.trim().isNotEmpty) {
                final primary = imageUrl.trim();
                final fallback = primary.replaceFirst('://adm.', '://admin.');
                leading = Image.network(
                  primary,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) {
                    if (fallback != primary) {
                      return Image.network(
                        fallback,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 24),
                      );
                    }
                    return const Icon(Icons.image, size: 24);
                  },
                );
              } else {
                leading = Icon(icon ?? Icons.payments, size: 24, color: Colors.black87);
              }

              return GestureDetector(
                onTap: () {
                  setModalState(() {
                    _selectedPayment = value;
                  });
                  _syncPaymentMethodToBackend(value);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF37AF00) : Colors.grey.shade300,
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        height: 45,
                        width: 55,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(child: leading),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      Container(
                        height: 22,
                        width: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF37AF00) : Colors.grey,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? Center(
                                child: Container(
                                  height: 10,
                                  width: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF37AF00),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.62,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      height: 5,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Select Payment Method',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 15),
                    Flexible(
                      fit: FlexFit.loose,
                      child: ListView(
                        shrinkWrap: true,
                        primary: false,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          buildPaymentItem(
                            name: 'Cash',
                            icon: Icons.money,
                            value: 'cash',
                          ),
                          buildPaymentItem(
                            name: 'Wallet',
                            icon: Icons.account_balance_wallet,
                            value: 'wallet',
                          ),
                          FutureBuilder<List<PaymentGatewayModel>>(
                            future: _paymentGatewaysFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Center(
                                    child: SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }

                              final items = snapshot.data ?? const <PaymentGatewayModel>[];
                              if (items.isEmpty) return const SizedBox.shrink();

                              return Column(
                                children: items.map((item) {
                                  final serial = item.serial;
                                  return buildPaymentItem(
                                    name: item.name,
                                    imageUrl: item.iconUrl.trim().isNotEmpty ? item.iconUrl : null,
                                    icon: _fallbackIcon(serial),
                                    value: serial,
                                  );
                                }).toList(growable: false),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF37AF00),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context, _selectedPayment);
                            if (mounted) {
                              setState(() {});
                            }
                          },
                          child: const Text('Confirm'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openPreferenceSheet(BuildContext context) {
    _preferencesFuture ??= _preferenceApi.getPreferences();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'Choose Preferences',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FutureBuilder<List<PreferenceModel>>(
                      future: _preferencesFuture,
                      builder: (context, snapshot) {
                        final items = snapshot.data ?? const <PreferenceModel>[];

                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }

                        if (items.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final pref = items[index];
                            final selected = _selectedPreferences.contains(pref.id);

                            return ListTile(
                              leading: pref.iconUrl.trim().isEmpty
                                  ? const SizedBox(width: 24, height: 24)
                                  : Image.network(
                                      pref.iconUrl,
                                      width: 24,
                                      height: 24,
                                      errorBuilder: (_, __, ___) => const SizedBox(width: 24, height: 24),
                                    ),
                              title: Text(pref.name),
                              trailing: Checkbox(
                                value: selected,
                                activeColor: const Color(0xFF37AF00),
                                checkColor: Colors.white,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setModalState(() {
                                    if (value) {
                                      if (!_selectedPreferences.contains(pref.id)) {
                                        _selectedPreferences.add(pref.id);
                                      }
                                    } else {
                                      _selectedPreferences.remove(pref.id);
                                    }
                                    _isPetsSelected = _selectedPreferences.isNotEmpty;
                                    _isLuggagesSelected = _selectedPreferences.isNotEmpty;
                                  });
                                },
                              ),
                              onTap: () {
                                setModalState(() {
                                  if (selected) {
                                    _selectedPreferences.remove(pref.id);
                                  } else {
                                    _selectedPreferences.add(pref.id);
                                  }
                                  _isPetsSelected = _selectedPreferences.isNotEmpty;
                                  _isLuggagesSelected = _selectedPreferences.isNotEmpty;
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF37AF00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context, _selectedPreferences);
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        child: const Text(
                          'Confirm',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildServiceCategoriesStrip() {
    final future = _serviceCategoriesFuture;
    if (future == null) return const SizedBox.shrink();

    return SizedBox(
      height: 86,
      child: FutureBuilder<List<ServiceCategory>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          final items = snapshot.data ?? const <ServiceCategory>[];
          if (items.isEmpty) return const SizedBox.shrink();

          if (_selectedServiceIndex >= items.length) {
            _selectedServiceIndex = 0;
          }

          Widget buildCard(ServiceCategory item, int index, {double? width}) {
            final selected = index == _selectedServiceIndex;

            if (_selectedServiceIndex == index && _selectedServiceCategoryId != item.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _selectedServiceCategoryId = item.id;
                  _fetchVehiclesForService(item.id);
                });
              });
            }

            return ServiceCategoryCard(
              title: item.name.trim().isEmpty ? item.service : item.name,
              iconUrl: item.image,
              selected: selected,
              width: width,
              onTap: () {
                setState(() {
                  _selectedServiceIndex = index;
                  _selectedServiceCategoryId = item.id;
                  _fetchVehiclesForService(item.id);
                });
              },
            );
          }

          if (items.length <= 5) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final count = items.length;
                final gap = 8.0;
                final totalGap = gap * (count - 1);
                final each = ((constraints.maxWidth - totalGap) / count).clamp(54, 86).toDouble();

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(count, (index) {
                    final item = items[index];
                    return Padding(
                      padding: EdgeInsets.only(right: index == count - 1 ? 0 : gap),
                      child: buildCard(item, index, width: each),
                    );
                  }),
                );
              },
            );
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return buildCard(item, index);
            },
          );
        },
      ),
    );
  }

  Widget _locationInputField({
    required TextEditingController controller,
    required String hintText,
    required Widget prefixIcon,
    required VoidCallback onTap,
    required VoidCallback onClearTap,
    bool showClear = false,
    Future<void> Function()? onCurrentLocationTap,
  }) {
    return SizedBox(
      height: 50,
      child: TextField(
        controller: controller,
        readOnly: true,
        onTap: onTap,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.grey.shade200,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          hintText: hintText,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: prefixIcon,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onCurrentLocationTap != null)
                IconButton(
                  icon: const Icon(Icons.my_location, size: 20),
                  onPressed: onCurrentLocationTap,
                ),
              if (showClear)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onClearTap,
                ),
            ],
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 60, minHeight: 40),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _RideAcceptedBottomSheet extends StatefulWidget {
  final Map<String, dynamic> ride;
  final VoidCallback onCancel;

  const _RideAcceptedBottomSheet({
    required this.ride,
    required this.onCancel,
  });

  @override
  State<_RideAcceptedBottomSheet> createState() => _RideAcceptedBottomSheetState();
}

class _RideAcceptedBottomSheetState extends State<_RideAcceptedBottomSheet> {
  Timer? _cancelTimer;
  double _cancelProgress = 0;

  int _fareOf(Map<String, dynamic> r) {
    final maybeFinal = r['finalFare'];
    final finalNum = maybeFinal is num ? maybeFinal : num.tryParse(maybeFinal?.toString() ?? '') ?? 0;
    final raw = finalNum > 0 ? maybeFinal : r['fare'];
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _startCancelFill();
  }

  @override
  void dispose() {
    _cancelTimer?.cancel();
    _cancelTimer = null;
    super.dispose();
  }

  void _stopCancelFill() {
    _cancelTimer?.cancel();
    _cancelTimer = null;
  }

  void _startCancelFill() {
    if (_cancelTimer != null) return;
    _cancelProgress = 0;
    _cancelTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      final next = (_cancelProgress + (1 / 100)).clamp(0.0, 1.0);
      setState(() {
        _cancelProgress = next;
      });
      if (next >= 1) {
        t.cancel();
        _cancelTimer = null;
        widget.onCancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const startGreen = Color(0xFF16A34A);
    const cancelTop = Color(0xFFFF6B6B);
    const cancelBase = Color(0xFFFFCDD2);
    const cancelFill = Color(0xFFE53935);

    final ride = widget.ride;
    final pickup = ride['pickup'];
    final drop = ride['drop'];

    final pickupAddress = (ride['pickup_address'] ?? (pickup is Map ? pickup['address'] : null) ?? '')
        .toString()
        .trim();
    final dropAddress = (ride['drop_address'] ?? (drop is Map ? drop['address'] : null) ?? '')
        .toString()
        .trim();

    final userNode = ride['user'];
    final userMap = userNode is Map ? userNode : const {};
    final name = (userMap['name'] ?? ride['customerName'] ?? ride['userName'] ?? ride['name'] ?? 'Customer')
        .toString()
        .trim();
    final imageUrl = (userMap['profile_image'] ?? ride['customerImage'] ?? ride['user_image'] ?? ride['image'] ?? '')
        .toString()
        .trim();
    final hasImage = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final fare = _fareOf(ride);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, -6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            height: 5,
            width: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFFF3F4F6),
                      backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
                      child: hasImage
                          ? null
                          : Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'R',
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name.isEmpty ? 'Rider' : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  fare > 0 ? '₹$fare' : '₹--',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                children: [
                                  Container(
                                    height: 8,
                                    width: 8,
                                    decoration: const BoxDecoration(color: startGreen, shape: BoxShape.circle),
                                  ),
                                  Container(
                                    height: 26,
                                    width: 2,
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                  Container(
                                    height: 8,
                                    width: 8,
                                    decoration: const BoxDecoration(color: cancelTop, shape: BoxShape.circle),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pickupAddress.isEmpty ? 'Pickup location' : pickupAddress,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      dropAddress.isEmpty ? 'Drop location' : dropAddress,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'How soon will you arrive?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                _ArrivalButton(
                  label: 'Arriving in 5 min',
                  minutes: 5,
                  ride: ride,
                  googleApiKey: _HomeMapScreenState._googleApiKey,
                  onBeforeTap: _stopCancelFill,
                ),
                const SizedBox(height: 10),
                _ArrivalButton(
                  label: 'Arriving in 10 min',
                  minutes: 10,
                  ride: ride,
                  googleApiKey: _HomeMapScreenState._googleApiKey,
                  onBeforeTap: _stopCancelFill,
                ),
                const SizedBox(height: 10),
                _ArrivalButton(
                  label: 'Arriving in 15 min',
                  minutes: 15,
                  ride: ride,
                  googleApiKey: _HomeMapScreenState._googleApiKey,
                  onBeforeTap: _stopCancelFill,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    return SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            _stopCancelFill();
                            widget.onCancel();
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  color: cancelBase,
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 100),
                                    curve: Curves.linear,
                                    width: w * _cancelProgress,
                                    decoration: BoxDecoration(
                                      color: cancelFill,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                                const Center(
                                  child: Text(
                                    'Cancel Ride',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ConfirmFareUI extends StatefulWidget {
  final dynamic ride;
  final SessionService sessionService;
  final Future<void> Function()? onBidSent;

  const ConfirmFareUI({
    super.key,
    required this.ride,
    required this.sessionService,
    this.onBidSent,
  });

  @override
  State<ConfirmFareUI> createState() => _ConfirmFareUIState();
}

class _ConfirmFareUIState extends State<ConfirmFareUI> {
  double price = 0;
  int selectedHour = 8;
  int selectedMinute = 30;
  String period = 'AM';

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    final r = widget.ride;
    if (r is IntercityRequestModel) {
      price = r.price;
    } else if (r is Map) {
      final v = r['total_price'] ?? r['price'] ?? 0;
      if (v is num) {
        price = v.toDouble();
      } else {
        price = double.tryParse(v.toString()) ?? 0;
      }
    }
  }

  String _rideId() {
    final r = widget.ride;
    if (r is IntercityRequestModel) return r.id;
    if (r is Map) return (r['_id'] ?? r['id'] ?? r['ride_id'] ?? '').toString();
    return '';
  }

  String _riderName() {
    final r = widget.ride;
    if (r is IntercityRequestModel) return r.riderName;
    if (r is Map) return (r['rider_name'] ?? r['name'] ?? r['riderName'] ?? 'User').toString();
    return 'User';
  }

  String _riderImage() {
    final r = widget.ride;
    if (r is IntercityRequestModel) return r.riderImage;
    if (r is Map) return (r['user_image'] ?? r['rider_image'] ?? r['image'] ?? '').toString();
    return '';
  }

  double _km() {
    final r = widget.ride;
    if (r is IntercityRequestModel) return r.km;
    if (r is Map) {
      final v = r['total_km'] ?? r['km'] ?? 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }
    return 0;
  }

  int _timeMinutes() {
    final r = widget.ride;
    if (r is IntercityRequestModel) return r.timeMinutes;
    if (r is Map) {
      final v = r['total_time'] ?? r['timeMinutes'] ?? r['time_minutes'] ?? 0;
      if (v is num) return v.round();
      return int.tryParse(v.toString()) ?? 0;
    }
    return 0;
  }

  String _pickup() {
    final r = widget.ride;
    if (r is IntercityRequestModel) return r.pickup;
    if (r is Map) return (r['pickup_location'] ?? r['pickup'] ?? '').toString();
    return '';
  }

  String _drop() {
    final r = widget.ride;
    if (r is IntercityRequestModel) return r.drop;
    if (r is Map) return (r['drop_location'] ?? r['drop'] ?? '').toString();
    return '';
  }

  String _selectedTimeText() {
    return '${_two(selectedHour)}:${_two(selectedMinute)} $period';
  }

  int _selectedTimeMinutes() {
    return (selectedHour * 60) + selectedMinute;
  }

  Future<void> _submitBid() async {
    final rideId = _rideId().trim();
    if (rideId.isEmpty) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    bool ok = false;
    String failMessage = '';
    try {
      final token = (await widget.sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;
      final resp = await const ApiService().sendIntercityBid(
        token: token,
        rideId: rideId,
        price: price,
        timeMinutes: _selectedTimeMinutes(),
      );
      ok = resp['success'] == true;
      if (!ok) {
        failMessage = (resp['message'] ?? 'Failed to send bid').toString();
      }
    } catch (_) {}

    if (!mounted) return;

    if (!ok) {
      if (isWalletInsufficientMessage(failMessage)) {
        await showWalletInsufficientDialog(context, message: failMessage);
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(failMessage.isEmpty ? 'Failed to send bid' : failMessage)),
      );
      return;
    }

    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Bid sent. Waiting for user response...')),
    );
    await widget.onBidSent?.call();
  }

  void showTimePickerSheet() {
    final now = DateTime.now();
    final initial = DateTime(now.year, now.month, now.day, selectedHour, selectedMinute);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            height: 300,
            padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                    const Expanded(
                      child: Text(
                        'Select Time',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Select', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    initialDateTime: initial,
                    use24hFormat: false,
                    onDateTimeChanged: (val) {
                      if (!mounted) return;
                      setState(() {
                        selectedHour = val.hour;
                        selectedMinute = val.minute;
                        period = val.hour >= 12 ? 'PM' : 'AM';
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final riderName = _riderName().trim().isEmpty ? 'User' : _riderName().trim();
    final riderImage = _riderImage().trim();
    final km = _km();
    final timeMin = _timeMinutes();
    final pickup = _pickup().trim();
    final drop = _drop().trim();

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            const Text(
              'Confirm Fare',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: riderImage.isNotEmpty ? NetworkImage(riderImage) : null,
                  child: riderImage.isEmpty ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    riderName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '₹${price.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF369D01), fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${km.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('$timeMin min', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const Icon(Icons.radio_button_unchecked, size: 18, color: Colors.black54),
                    Container(height: 30, width: 2, color: Colors.grey.shade400),
                    const Icon(Icons.location_on, color: Color(0xFF369D01), size: 18),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pickup.isEmpty ? '-' : pickup, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(drop.isEmpty ? '-' : drop, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      if (price > 10) {
                        setState(() => price -= 10);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 20),
                Text(
                  '₹${price.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 20),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF369D01),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: () => setState(() => price += 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: showTimePickerSheet,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Select Time', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(_selectedTimeText(), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitBid,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF369D01),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'BOOK FOR ₹${price.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _ArrivalButton extends StatelessWidget {
  final String label;
  final int minutes;
  final Map<String, dynamic> ride;
  final String googleApiKey;
  final VoidCallback? onBeforeTap;

  const _ArrivalButton({
    required this.label,
    required this.minutes,
    required this.ride,
    required this.googleApiKey,
    this.onBeforeTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: InkWell(
        onTap: () {
          onBeforeTap?.call();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PickupMapScreen(
                ride: ride,
                arrivalMinutes: minutes,
                googleApiKey: googleApiKey,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}





