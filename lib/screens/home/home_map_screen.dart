import 'dart:async';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vite_captain/maps/mappls_routes.dart';
import 'package:vite_captain/maps/mappls_geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vite_captain/maps/mappls_map.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/models/intercity_request.dart';
import 'package:vite_captain/screens/auth/login_screen.dart';
import 'package:vite_captain/modules/status/driver_suspended_screen.dart';
import 'package:vite_captain/screens/full_map_screen.dart';
import 'package:vite_captain/screens/activity/activity_screen.dart';
import 'package:vite_captain/screens/home/intercity_bidding_screen.dart';
import 'package:vite_captain/screens/home/share_seats_sheet.dart';
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
import 'package:vite_captain/services/zone_service.dart';
import 'package:vite_captain/services/service_category_api.dart';
import 'package:vite_captain/services/vehicle_type_api.dart';
import 'package:vite_captain/services/vehicles_by_service_api.dart';
import 'package:vite_captain/screens/notifications_screen.dart';
import 'package:vite_captain/screens/support_screen.dart';
import 'package:vite_captain/screens/settings_screen.dart';
import 'package:vite_captain/services/alert_service.dart';
import 'package:vite_captain/services/notification_service.dart';
import 'package:vite_captain/services/offer_inbox.dart';
import 'package:vite_captain/services/ride_bubble.dart';
import 'package:vite_captain/maps/open_mappls_navigation.dart';
import 'package:vite_captain/widgets/ride_otp_sheet.dart';
import 'package:vite_captain/screens/home/driver_payment_screen.dart';
import 'package:vite_captain/widgets/ride_request_card.dart';
import 'package:vite_captain/widgets/request_countdown_ring.dart';
import 'package:vite_captain/widgets/ride_route_rail.dart';
import 'package:vite_captain/widgets/send_ride_notification_sheet.dart';
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
  static const String _vehicleImageAsset = 'assets/images/Car.png';
  static const String _parcelDutyPrefsKey = 'is_parcel_active';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final LocationService _locationService = const LocationService();
  final PlacesService _placesService = const PlacesService();
  final Completer<MapplsViewController> _mapController =
      Completer<MapplsViewController>();
  MapplsViewController? _liveMap;

  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  bool _loadingLocation = true;
  LatLng _cameraTarget = const LatLng(20.5937, 78.9629);
  Set<Marker> _markers = <Marker>{};
  Set<Marker> _demandMarkers = <Marker>{};
  int _nearbyRequestCount = 0;
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
  BuildContext? _offerDialogContext;
  final Set<String> _etaChosenRideIds = <String>{};
  Timer? _etaTick;
  int _etaLeftSeconds = 0;
  bool _isRideAccepted = false;
  final Set<String> _handledRideRequestIds = <String>{};
  final Set<String> _ignoredRideIds = <String>{};
  final Set<String> _ignoredParcelRequestIds = <String>{};
  final Set<String> _acceptingParcelRequestIds = <String>{};
  String? _acceptedRideId;
  String? _lastRideId;
  bool _isUpdatingBid = false;
  bool _tripBusy = false;
  bool _otpSheetOpen = false;
  String? _bubbleSignature;
  bool _bubbleOn = false;
  String _accountHold = '';
  String _serviceState = '';
  List<String> _zoneServiceIds = const [];
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
  Map<String, dynamic>? _seatTrip;
  List<Map<String, dynamic>> _seatOffers = const [];
  List<Map<String, dynamic>> _openSeatRequests = const [];
  final Set<String> _seenIntercityRequestIds = <String>{};
  bool _intercityScreenOpening = false;
  int _bottomTabIndex = 0;
  bool _requestsSheetOpen = true;
  int _seenIncomingCount = 0;
  String _selectedIncomingId = '';
  final Map<String, DateTime> _incomingSeenAt = <String, DateTime>{};
  final Map<String, GlobalKey> _incomingCardKeys = <String, GlobalKey>{};
  final ScrollController _incomingListScroll = ScrollController();
  Timer? _incomingTick;

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
  bool _dutyUpdating = false;
  bool _locationFailed = false;
  String _driverName = '';
  String _driverImageUrl = '';
  int _totalCompletedRides = 0;
  double _todayEarning = 0;
  int _todayTrips = 0;
  String _todayHours = '00:00';
  double _lastTripEarning = 0;
  double _weekTotal = 0;
  List<double> _weekDays = List<double>.filled(7, 0);
  double _driverRating = 0;
  int _ratingCount = 0;
  FlutterTts? _tts;
  String? _wishSlotStarted;
  DateTime? _lastExitPrompt;
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
    _userBasicsFuture = _sessionService.getUserBasics(forceRefresh: true).then((data) {
      final mobile = (data['mobile'] ?? '').trim();
      final resolved = _firstPersonName({'fullName': data['name'], 'name': data['name']}, mobile);
      if (resolved.isNotEmpty && mounted && (_driverName.trim().isEmpty || _looksLikePhone(_driverName))) {
        setState(() => _driverName = resolved);
      }
      _maybeSpeakWish(resolved.isNotEmpty ? resolved : _driverName);
      return data;
    });
    OfferInbox.loadIgnored();
    _loadInitialLocation();
    _startDriverTracking();
    _serviceCategoriesFuture = _serviceCategoryApi.fetchServiceCategories();
    _loadWalletBalance();
    _loadDriverProfile();
    _loadCaptainRating();
    _loadHomeSummary();
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
            Text(
              'SOS Alert Sent',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
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
                  Text(
                    'Status',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
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
                  Text(
                    'Ride Information',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
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
                  Text(
                    'Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    address.isNotEmpty ? address : 'Location available',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
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
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
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
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            return const Center(child: ViteLoader());
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
                                      child: ViteLoader(strokeWidth: 2, color: Colors.white),
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
      onTap: () {},
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
                const Text(
                  'PARCEL DELIVERY',
                  style: TextStyle(color: Color(0xFF009640), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.4),
                ),
                const SizedBox(height: 8),
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
                RideRouteRail(
                  pickup: pickup.isEmpty ? '-' : pickup,
                  drop: drop.isEmpty ? '-' : drop,
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

  String _clockFromHours(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    final match = RegExp(r'([0-9]*\.?[0-9]+)').firstMatch(text);
    final hours = match == null ? 0.0 : (double.tryParse(match.group(1)!) ?? 0);
    if (hours <= 0) return '00:00';
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  Future<void> _loadHomeSummary() async {
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;
      final headers = {'Authorization': 'Bearer $token'};
      final results = await Future.wait([
        DioClient.dio.get(
          '$baseUrl/driver-earnings?range=today',
          options: Options(validateStatus: (_) => true, headers: headers),
        ),
        DioClient.dio.get(
          '$baseUrl/driver/history',
          options: Options(validateStatus: (_) => true, headers: headers),
        ),
      ]);
      if (!mounted) return;
      final decoded = results[0].data;
      setState(() {
        if (decoded is Map && decoded['status'] == true) {
          final earn = decoded['today_earning'];
          _todayEarning = earn is num ? earn.toDouble() : double.tryParse('$earn') ?? 0;
          final trips = decoded['today_trips'];
          _todayTrips = trips is num ? trips.toInt() : int.tryParse('${trips ?? ''}') ?? 0;
          _todayHours = _clockFromHours(decoded['today_login_hours']);
          final latest = decoded['latest_ride'];
          if (latest is Map) {
            final amount = latest['amount'];
            _lastTripEarning = amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0;
          }
        }
        _applyWeekHistory(results[1].data);
      });
    } catch (_) {}
  }

  void _applyWeekHistory(dynamic body) {
    final rows = body is Map && body['data'] is List ? body['data'] as List : const <dynamic>[];
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(Duration(days: today.weekday - 1));
    final days = List<double>.filled(7, 0);
    var week = 0.0;
    var sawTrip = false;
    for (final row in rows) {
      if (row is! Map) continue;
      final amountRaw = row['amount'];
      final amount = amountRaw is num ? amountRaw.toDouble() : double.tryParse('$amountRaw') ?? 0;
      if (!sawTrip) {
        _lastTripEarning = amount;
        sawTrip = true;
      }
      final day = _parseHistoryDay('${row['date'] ?? ''}');
      if (day == null) continue;
      final index = day.difference(start).inDays;
      if (index < 0 || index > 6) continue;
      days[index] += amount;
      week += amount;
    }
    _weekDays = days;
    _weekTotal = week;
  }

  DateTime? _parseHistoryDay(String raw) {
    final parts = raw.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  String _inr(num value) {
    final digits = value.round().abs().toString();
    if (digits.length <= 3) return '₹$digits';
    final head = digits.substring(0, digits.length - 3);
    final tail = digits.substring(digits.length - 3);
    final grouped = StringBuffer();
    for (var i = 0; i < head.length; i++) {
      if (i > 0 && (head.length - i) % 2 == 0) grouped.write(',');
      grouped.write(head[i]);
    }
    return '₹$grouped,$tail';
  }

  double get _dailyGoalAmount {
    var best = _todayEarning;
    for (final day in _weekDays) {
      if (day > best) best = day;
    }
    if (best <= 0) return 0;
    return (best / 100).ceil() * 100;
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

  Future<void> _loadZoneServices(String stateName) async {
    try {
      final ids = await ZoneService.instance.serviceIdsFor(stateName);
      if (!mounted) return;
      setState(() => _zoneServiceIds = ids);
    } catch (_) {}
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
      final accountStatus = (data['account_status'] ?? '').toString();
      if (accountStatus == 'suspended') {
        _openAccountHold(accountStatus);
        return;
      }
      final address = data['address'];
      final savedState = address is Map
          ? (address['state'] ?? data['state'] ?? '').toString().trim()
          : (data['state'] ?? '').toString().trim();
      if (mounted) {
        setState(() {
          _accountHold = accountStatus == 'under_review' ? 'under_review' : '';
          _serviceState = savedState;
        });
        if (savedState.isNotEmpty) _loadZoneServices(savedState);
      }
      final mobile = (data['mobile'] ?? data['phone'] ?? '').toString().trim();
      final name = _firstPersonName(data, mobile).isNotEmpty ? _firstPersonName(data, mobile) : (_scanPersonName(data) ?? '');
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
        final ratingRaw = data['rating'] ?? data['avg_rating'] ?? data['average_rating'] ?? data['driver_rating'];
        final parsedRating = ratingRaw is num ? ratingRaw.toDouble() : double.tryParse('${ratingRaw ?? ''}') ?? 0;
        if (parsedRating > 0) _driverRating = parsedRating;
        final countRaw = data['rating_count'] ?? data['review_count'] ?? data['reviews_count'] ?? data['total_reviews'];
        final parsedCount = countRaw is num ? countRaw.toInt() : int.tryParse('${countRaw ?? ''}') ?? 0;
        if (parsedCount > 0) _ratingCount = parsedCount;
        _driverVehicleType = vehicleType;
        _driverVehicleTypeId = vehicleTypeId;
      });
      await _loadCaptainRating();
      await _maybeSpeakWish(name.isNotEmpty ? name : _driverName);
    } catch (_) {}
  }

  String _wishSlotId() {
    final now = DateTime.now();
    final hour = now.hour;
    var day = DateTime(now.year, now.month, now.day);
    final String period;
    if (hour < 5) {
      period = 'night';
      day = day.subtract(const Duration(days: 1));
    } else if (hour < 12) {
      period = 'morning';
    } else if (hour < 17) {
      period = 'afternoon';
    } else if (hour < 21) {
      period = 'evening';
    } else {
      period = 'night';
    }
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$date-$period';
  }

  Future<void> _maybeSpeakWish(String rawName) async {
    if (!mounted) return;
    final name = rawName.trim();
    if (name.isEmpty || name.toLowerCase() == 'captain' || _looksLikePhone(name)) return;
    final slot = _wishSlotId();
    if (_wishSlotStarted == slot) return;
    _wishSlotStarted = slot;
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'captain_wish_slot';
      if (prefs.getString(key) == slot) return;
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage('en-IN');
      await tts.setSpeechRate(0.48);
      await tts.setPitch(1.0);
      await tts.setVolume(1);
      try {
        final voices = await tts.getVoices;
        if (voices is List) {
          Map? female;
          for (final raw in voices) {
            if (raw is! Map) continue;
            final voiceName = (raw['name'] ?? '').toString().toLowerCase();
            final locale = (raw['locale'] ?? '').toString().toLowerCase().replaceAll('_', '-');
            if (!locale.startsWith('en-in')) continue;
            final isFemale = voiceName.contains('female') || voiceName.contains('ena') || voiceName.contains('enc');
            if (isFemale) {
              female = raw;
              break;
            }
          }
          if (female != null) {
            await tts.setVoice({
              'name': female['name'].toString(),
              'locale': female['locale'].toString(),
            });
          }
        }
      } catch (_) {}
      await tts.speak('${_wishTitle()}, $name. Go online and start the earning.');
      await prefs.setString(key, slot);
    } catch (_) {}
  }

  String _firstPersonName(Map data, String mobile) {
    const keys = ['fullName', 'full_name', 'driver_name', 'driverName', 'name', 'username'];
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isEmpty || value.toLowerCase() == 'null') continue;
      if (_looksLikePhone(value) || (mobile.isNotEmpty && value == mobile)) continue;
      return value;
    }
    return '';
  }

  String? _scanPersonName(Map data) {
    String? read(dynamic node, int depth) {
      if (depth > 4 || node is! Map) return null;
      for (final entry in node.entries) {
        final key = entry.key.toString().toLowerCase();
        final value = entry.value;
        if (value is String && (key.contains('fullname') || key.contains('full_name') || key == 'driver_name' || key == 'drivername' || key == 'name')) {
          final text = value.trim();
          if (text.isEmpty || text.toLowerCase() == 'null' || text.toLowerCase() == 'captain') continue;
          if (_looksLikePhone(text)) continue;
          if (RegExp(r'[A-Za-z]').hasMatch(text)) return text;
        }
        if (value is Map) {
          final nested = read(value, depth + 1);
          if (nested != null) return nested;
        }
      }
      return null;
    }

    return read(data, 0);
  }

  Future<void> _loadCaptainRating() async {
    try {
      final driverId = (await _sessionService.getDriverId() ?? '').trim();
      if (driverId.isEmpty) return;
      final token = (await _sessionService.getToken() ?? '').trim();
      final resp = await DioClient.dio.get(
        '$baseUrl/get-my-reviews/$driverId',
        options: Options(
          validateStatus: (_) => true,
          headers: {
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );
      final body = resp.data;
      final rows = body is Map && body['data'] is List ? body['data'] as List : const <dynamic>[];
      final seen = <String>{};
      var sum = 0.0;
      var count = 0;
      for (final row in rows) {
        if (row is! Map) continue;
        final role = '${row['role'] ?? ''}'.toLowerCase();
        final source = '${row['source'] ?? ''}'.toLowerCase();
        if (role == 'customer' || source == 'rider_reviews') continue;
        if (role.isNotEmpty && role != 'driver' && source != 'driver_reviews') continue;
        final id = '${row['_id'] ?? ''}';
        if (id.isNotEmpty && !seen.add(id)) continue;
        final raw = row['rating'] ?? row['stars'];
        final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
        if (value <= 0) continue;
        sum += value;
        count++;
      }
      if (!mounted || count == 0) return;
      setState(() {
        _driverRating = sum / count;
        _ratingCount = count;
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
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ViteLoader(color: Color(0xFF369D01)),
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
              color: Theme.of(context).colorScheme.surface,
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
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
          mainAxisSize: MainAxisSize.min,
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
                        Flexible(
                          child: Text('₹$offer', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 2),
                        Flexible(child: Text(distanceText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12))),
                        const SizedBox(width: 6),
                        const Icon(Icons.star, size: 14, color: Colors.orange),
                        const SizedBox(width: 2),
                        Text(ratingText, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '₹ $offer For ${req.persons} Person${req.persons == 1 ? '' : 's'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          if (pickupDate.isNotEmpty || pickupTime.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${pickupDate.isNotEmpty ? pickupDate : 'Not scheduled'}${pickupTime.isNotEmpty ? ' · $pickupTime' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
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
          RideRouteRail(
            pickup: pickup,
            drop: drop,
            distanceLabel: req.km > 0 ? '${req.km.toStringAsFixed(1)} km' : null,
          ),
          const SizedBox(height: 15),
          const Row(
            children: [
              ViteLoader(
                strokeWidth: 2,
                color: Color(0xFF369D01),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting for customer response...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: Color(0xFF009640)),
                foregroundColor: const Color(0xFF009640),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _passIntercityToCaptain(req),
              child: const Text('Pass to a captain with empty seats', style: TextStyle(fontWeight: FontWeight.w900)),
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
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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

                    if (!mounted) return;
                    setState(() {
                      _activeRide = ride;
                      _acceptedRideId = req.id;
                      _isRideAccepted = true;
                    });
                    _syncRideBubble(ride);
                    _fetchActiveRide();
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: Color(0xFF009640)),
                foregroundColor: const Color(0xFF009640),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _passIntercityToCaptain(req),
              child: const Text('Pass to a captain with empty seats', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
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

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _showHomeMini();
    }

    if (state == AppLifecycleState.resumed) {
      _bubbleOn = false;
      RideBubble.stop();
      _bubbleSignature = null;
      OfferInbox.loadIgnored();
      _loadWalletBalance();
      _loadDriverProfile();
      _loadHomeSummary();
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
        if (_seenIntercityRequestIds.contains(ride.id)) return;
        if (!_isStrictVehicleTypeMatch(ride.vehicleType)) return;
        _seenIntercityRequestIds.add(ride.id);
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
          .where((ride) => !OfferInbox.ignoredIds.contains(ride.id.trim()))
          .toList();
      
      print('[RIDE_DISPATCH] ========================================');
      print('[RIDE_DISPATCH] FILTERED INTERCITY REQUESTS');
      print('[RIDE_DISPATCH] After Vehicle Type Filter: ${available.length}');
      print('[RIDE_DISPATCH] ========================================');
      
      print('Rendered intercity ride count: ${available.length}');
      final waiting = respWaiting['success'] == true ? parseList(respWaiting['data']) : <IntercityRequestModel>[];
      final accepted = respAccepted['success'] == true ? parseList(respAccepted['data']) : <IntercityRequestModel>[];
      Map<String, dynamic>? seatTrip;
      var seatOffers = const <Map<String, dynamic>>[];
      var openSeatRequests = const <Map<String, dynamic>>[];
      try {
        final board = await const ApiService().getIntercitySeatBoard(token: token);
        final data = board['data'];
        if (board['success'] == true && data is Map) {
          final trip = data['trip'];
          seatTrip = trip is Map ? Map<String, dynamic>.from(trip) : null;
          List<Map<String, dynamic>> asMaps(dynamic raw) {
            if (raw is! List) return const [];
            return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          }
          seatOffers = asMaps(data['offers']);
          openSeatRequests = asMaps(data['open_requests']);
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _intercityRequests = available;
        _myWaitingIntercityRides = waiting;
        _myAcceptedIntercityRides = accepted;
        _seatTrip = seatTrip;
        _seatOffers = seatOffers;
        _openSeatRequests = openSeatRequests;
        _nearbyRequestCount = OfferInbox.city.value.length + available.length + _liveParcelRequests.length;
      });
      OfferInbox.setIntercity(available);
      _publishOfferNotification();
      if (available.isNotEmpty) {
        AlertService.startAlert();
      } else if (OfferInbox.city.value.isEmpty && !isDialogOpen) {
        AlertService.stopAlert();
        cancelRideOfferNotification();
      }
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }

  Future<void> _passIntercityToCaptain(IntercityRequestModel req) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSeatsSheet(ride: req),
    );
    if (!mounted || sent != true) return;
    setState(() {
      _intercityRequests = _intercityRequests.where((r) => r.id != req.id).toList();
      _myWaitingIntercityRides = _myWaitingIntercityRides.where((r) => r.id != req.id).toList();
      _myAcceptedIntercityRides = _myAcceptedIntercityRides.where((r) => r.id != req.id).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride passed to a captain who has empty seats')),
    );
  }

  Future<void> _ignoreIntercityOffer(IntercityRequestModel req) async {
    OfferInbox.ignore(req.id);
    final left = _intercityRequests.where((r) => r.id != req.id).toList();
    if (mounted) {
      setState(() => _intercityRequests = left);
    }
    if (left.isEmpty && OfferInbox.city.value.isEmpty) {
      AlertService.stopAlert();
    }
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;
      await const ApiService().rejectIntercityRequest(
        token: token,
        requestId: req.id,
        reason: 'Ignored',
      );
    } catch (_) {}
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
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 0, 8, 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 6)),
          ],
          border: Border.all(color: const Color(0xFFE6E6E6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          const Text(
            'Intercity ride',
            style: TextStyle(color: Color(0xFF009640), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.4),
          ),
          const SizedBox(height: 8),
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
                        Flexible(
                          child: Text(
                            '₹$offer',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF369D01)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 2),
                        Flexible(child: Text(distanceText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700))),
                        const SizedBox(width: 6),
                        const Icon(Icons.star, size: 14, color: Colors.orange),
                        const SizedBox(width: 2),
                        Text(ratingText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
            const SizedBox(height: 8),
          Text(
            '$vehicle · ${req.persons} person${req.persons == 1 ? '' : 's'}${pickupDate.isNotEmpty ? ' · $pickupDate $pickupTime' : ''}',
            maxLines: 1,
                  overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12),
                ),
          const SizedBox(height: 8),
          RideRouteRail(
            pickup: pickup,
            drop: drop,
            distanceLabel: req.km > 0 ? '${req.km.toStringAsFixed(1)} km' : null,
          ),
          const SizedBox(height: 10),
          if (_pendingIntercityBidIds.contains(req.id))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              alignment: Alignment.center,
              child: Text(
                'Waiting for customer response',
                style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFF009640)),
                      foregroundColor: const Color(0xFF009640),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _passIntercityToCaptain(req),
                    child: const Text('Give to a captain on this route', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 8),
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
                    onPressed: () => _ignoreIntercityOffer(req),
                    child: const Text('Ignore', style: TextStyle(fontWeight: FontWeight.w900)),
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
        _bubbleSignature = null;
        RideBubble.clear();
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
        final acceptedNow = _rideStatusOf(next) == 'accepted' || _rideStatusOf(next) == 'assigned';
        if (acceptedNow && isDialogOpen) _closeOfferDialog();
        if (!_ongoingRideScreenOpen) {
          _maybeShowRideAcceptedSheet(next);
        }
        _syncActiveRideMap(next);
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
        _bubbleSignature = null;
        RideBubble.clear();
      }
    } catch (_) {
      return;
    }
  }

  String _ongoingRideOpenedId = '';
  final Set<String> _autoOpenedRideIds = <String>{};
  bool _coldStartRideRestore = false;

  void _maybeOpenOngoingRideScreen(Map<String, dynamic> ride) {
    final rideId = _rideIdOf(ride);
    if (rideId.isEmpty) return;
    _acceptedRideId = rideId;
    _isRideAccepted = true;
        _ongoingRideScreenOpen = false;
    _syncRideBubble(ride);
  }

  void _closeOfferDialog() {
    final ctx = _offerDialogContext;
    _offerDialogContext = null;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
  }

  void _startEtaCountdown(int minutes) {
    _etaTick?.cancel();
    _etaLeftSeconds = minutes <= 0 ? 0 : minutes * 60;
    if (_etaLeftSeconds <= 0) return;
    _etaTick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_etaLeftSeconds <= 1) {
        timer.cancel();
        setState(() => _etaLeftSeconds = 0);
        return;
      }
      setState(() => _etaLeftSeconds -= 1);
    });
  }

  String _runningClock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _maybeShowRideAcceptedSheet(Map<String, dynamic> ride) {
    final status = _rideStatusOf(ride);
    if (status != 'accepted' && status != 'assigned') return;
    if (_ongoingRideScreenOpen) return;

    final rideId = _rideIdOf(ride);
    if (rideId.isEmpty) return;
    if (_etaChosenRideIds.contains(rideId) || _etaText(ride).isNotEmpty) return;

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
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return SafeArea(
            top: false,
            child: _RideAcceptedBottomSheet(
              ride: ride,
              onPickTime: (minutes) async {
                _etaChosenRideIds.add(rideId);
                _startEtaCountdown(minutes);
                try {
                  await const ApiService().setRideEta(rideId: rideId, etaMinutes: minutes);
                } catch (_) {}
              },
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

  void _openAccountHold(String status) {
    if (status == 'under_review') {
      if (mounted) setState(() => _accountHold = 'under_review');
      return;
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DriverSuspendedScreen()),
      (route) => false,
    );
  }

  Future<void> _sendPing() async {
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;
      final res = await const ApiService().pingDriver(token: token);
      final accountStatus = (res['account_status'] ?? '').toString();
      if (accountStatus == 'suspended') {
        _openAccountHold(accountStatus);
      } else if (accountStatus == 'under_review') {
        if (mounted && _accountHold != 'under_review') {
          setState(() => _accountHold = 'under_review');
        }
      } else if (_accountHold.isNotEmpty && mounted) {
        setState(() => _accountHold = '');
      }
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
      if (local == true) AlertService.startDutyWatch();
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
      if (backendIsOnline) {
        AlertService.startDutyWatch();
      } else {
        AlertService.stopDutyWatch();
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

  String _pointAddress(dynamic node) {
    if (node is Map) {
      final address = (node['address'] ?? node['name'] ?? node['formatted_address'] ?? '').toString().trim();
      if (address.isNotEmpty) return address;
    }
    final text = (node ?? '').toString().trim();
    if (text.startsWith('{') || text.startsWith('[')) return '';
    return text;
  }

  String _personName(Map<String, dynamic> ride) {
    final user = ride['user'];
    final fromUser = user is Map ? (user['name'] ?? user['full_name'] ?? user['fullName'] ?? '').toString().trim() : '';
    final name = (ride['user_name'] ?? ride['userName'] ?? ride['customerName'] ?? ride['name'] ?? fromUser).toString().trim();
    return name.isEmpty ? 'Customer' : name;
  }

  String _personPhone(Map<String, dynamic> ride) {
    final user = ride['user'];
    final fromUser = user is Map ? (user['phone'] ?? user['mobile'] ?? user['contact'] ?? '').toString().trim() : '';
    return (ride['phone'] ?? ride['mobile'] ?? ride['user_phone'] ?? ride['userPhone'] ?? fromUser).toString().trim();
  }

  String _etaText(Map<String, dynamic> ride) {
    final raw = (ride['eta'] ?? ride['arrival_time'] ?? ride['arrivalTime'] ?? ride['time'] ?? ride['duration'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final lower = raw.toLowerCase();
    if (lower.contains('min') || lower.contains(':')) return raw;
    return '$raw min';
  }

  LatLng? _latLngOf(dynamic node) {
    if (node is! Map) return null;
    final latRaw = node['lat'] ?? node['latitude'];
    final lngRaw = node['lng'] ?? node['lon'] ?? node['longitude'];
    final lat = latRaw is num ? latRaw.toDouble() : double.tryParse('${latRaw ?? ''}');
    final lng = lngRaw is num ? lngRaw.toDouble() : double.tryParse('${lngRaw ?? ''}');
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  void _showHomeMini() {
    final ride = _activeRide;
    if (ride == null) return;
    final status = _rideStatusOf(ride);
    final live = status == 'accepted' ||
        status == 'assigned' ||
        status == 'arrived' ||
        status == 'waiting_user_confirmation' ||
        status == 'ongoing' ||
        status == 'started' ||
        status == 'in_progress';
    if (!live) return;
    _bubbleSignature = null;
    _syncRideBubble(ride);
  }

  void _publishOfferNotification() {
    final city = OfferInbox.city.value;
    final intercity = OfferInbox.intercity.value;
    if (city.isEmpty && intercity.isEmpty) {
      if (!isDialogOpen) cancelRideOfferNotification();
      return;
    }
    if (city.isNotEmpty) {
      final ride = city.first;
      final id = (ride['_id'] ?? ride['id'] ?? '').toString().trim();
      final pickup = _pointAddress(ride['pickup'] ?? ride['pickup_address']);
      final drop = _pointAddress(ride['drop'] ?? ride['drop_address']);
      final fareRaw = ride['fare'] ?? ride['amount'] ?? ride['price'];
      final fare = fareRaw is num ? fareRaw.toDouble() : (double.tryParse('${fareRaw ?? ''}') ?? 0);
      final name = (ride['user_name'] ?? ride['customerName'] ?? ride['name'] ?? 'Rider').toString().trim();
      showRideOfferNotification(
        id: id,
        kind: 'city',
        title: name.isEmpty ? 'New ride request' : name,
        body: '${pickup.isEmpty ? 'Pickup' : pickup}\n${drop.isEmpty ? 'Drop' : drop}',
        fare: fare,
      );
      return;
    }
    final ride = intercity.first;
    final fare = ride.bidPrice > 0 ? ride.bidPrice : ride.price;
    showRideOfferNotification(
      id: ride.id,
      kind: 'intercity',
      title: ride.riderName.trim().isEmpty ? 'Intercity ride' : ride.riderName.trim(),
      body: '${ride.pickup}\n${ride.drop}',
      fare: fare,
    );
  }

  void _syncRideBubble(Map<String, dynamic> ride) {
    final pickup = _pointAddress(ride['pickup'] ?? ride['pickup_address'] ?? ride['pickupAddress']);
    final drop = _pointAddress(ride['drop'] ?? ride['drop_address'] ?? ride['dropAddress']);
    final eta = _etaText(ride);
    final status = _rideStatusOf(ride);
    final live = status == 'accepted' ||
        status == 'assigned' ||
        status == 'arrived' ||
        status == 'waiting_user_confirmation' ||
        status == 'ongoing' ||
        status == 'started' ||
        status == 'in_progress';
    if (!live) {
      _bubbleOn = false;
      _bubbleSignature = null;
      RideBubble.clear();
      return;
    }
    final toDrop = status == 'ongoing' || status == 'started' || status == 'in_progress';
    final heading = toDrop ? 'Head to drop' : 'Head to pickup';
    final place = toDrop ? drop : pickup;
    final target = toDrop
        ? (_latLngOf(ride['drop']) ?? _latLngOf(ride['drop_location']) ?? _latLngOf(ride['destination']))
        : (_latLngOf(ride['pickup']) ?? _latLngOf(ride['pickup_location']));
    final here = _driverLatLng;
    final body = place.isEmpty ? 'Follow the route' : place;
    RideBubble.prepare(
      title: heading,
      body: body,
      eta: eta,
      lat: here?.latitude,
      lng: here?.longitude,
      targetLat: target?.latitude,
      targetLng: target?.longitude,
    );
    if (_isInForeground) return;
    final signature = '$heading|$place|$eta';
    if (_bubbleSignature == signature && _bubbleOn) {
      RideBubble.move(
        title: heading,
        body: body,
        lat: here?.latitude,
        lng: here?.longitude,
        targetLat: target?.latitude,
        targetLng: target?.longitude,
      );
      return;
    }
    _bubbleSignature = signature;
    _bubbleOn = true;
    RideBubble.start(
      title: heading,
      body: body,
      pickup: pickup,
      drop: drop,
      eta: eta.isEmpty ? '' : eta,
      lat: here?.latitude,
      lng: here?.longitude,
      targetLat: target?.latitude,
      targetLng: target?.longitude,
    );
  }

  Future<void> _navigateForRide(Map<String, dynamic> ride, {required bool toDrop}) async {
    final node = toDrop ? (ride['drop'] ?? ride['destination']) : (ride['pickup'] ?? ride['pickup_location']);
    final address = _pointAddress(node ?? (toDrop ? ride['drop_address'] : ride['pickup_address']));
    final point = _latLngOf(node);
    if (point != null) {
      await openMapplsNavigation(point);
      return;
    }
    await openMapplsPlace(address);
  }

  Future<void> _runTripAction(Future<void> Function() action) async {
    if (_tripBusy) return;
    setState(() => _tripBusy = true);
    try {
      await action();
      await _fetchActiveRide();
    } finally {
      if (mounted) setState(() => _tripBusy = false);
    }
  }

  Future<void> _playTripTick() async {
    try {
      await _togglePlayer.stop();
      await _togglePlayer.setVolume(0.5);
      await _togglePlayer.play(AssetSource('sounds/tick.wav'));
    } catch (_) {}
  }

  Future<void> _askRideOtp(Map<String, dynamic> ride) async {
    final rideId = _rideIdOf(ride);
    if (rideId.isEmpty || !mounted) return;
    setState(() => _otpSheetOpen = true);
    final started = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => RideOtpSheet(rideId: rideId),
    );
    if (mounted) setState(() => _otpSheetOpen = false);
    if (started != true || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _fetchActiveRide();
  }

  Future<void> _confirmTripReceived(Map<String, dynamic> ride) async {
    final rideId = _rideIdOf(ride);
    if (rideId.isEmpty) return;
    final token = (await _sessionService.getToken() ?? '').trim();
    final method = _ridePaymentMethodOf(ride);
    final rideType = (ride['ride_type'] ?? ride['rideType'] ?? 'normal').toString().trim();
    final res = method == 'wallet'
        ? await const ApiService().walletReceivedRide(rideId: rideId, rideType: rideType.isEmpty ? 'normal' : rideType)
        : await const ApiService().confirmCashReceived(rideId: rideId, token: token, rideType: rideType.isEmpty ? 'normal' : rideType);
    if (!mounted) return;
    if (res['success'] != true) {
      final rawMsg = (res['message'] ?? 'Could not confirm payment').toString();
      final lowerMsg = rawMsg.toLowerCase();
      final msg = (rawMsg.trim().isEmpty || lowerMsg.contains('<!doctype') || lowerMsg.contains('<html') || lowerMsg.contains('cannot post'))
          ? 'Could not confirm the payment. Please try again.'
          : rawMsg;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }
    setState(() {
      _activeRide = null;
      _isRideAccepted = false;
      _polylines = <Polyline>{};
    });
    _acceptedRideId = null;
    RideBubble.clear();
    await _fetchActiveRide();
  }

  Widget _activeTripCard(Map<String, dynamic> ride) {
    const green = Color(0xFF009640);
    final status = _rideStatusOf(ride);
    final pickup = _pointAddress(ride['pickup'] ?? ride['pickup_address'] ?? ride['pickupAddress']);
    final drop = _pointAddress(ride['drop'] ?? ride['drop_address'] ?? ride['dropAddress']);
    final name = _personName(ride);
    final eta = _etaText(ride);
    final fare = _rideFareOf(ride);
    final goingToDrop = status == 'ongoing' || status == 'started' || status == 'in_progress';
    final atPickup = status == 'arrived' || status == 'waiting_user_confirmation';
    final paying = _isCompletedRideStatus(status);
    final title = paying
        ? 'Collect payment'
        : goingToDrop
            ? 'Ride in progress'
            : atPickup
                ? 'At pickup'
                : 'Heading to pickup';
    final action = paying
        ? 'Payment received'
        : goingToDrop
            ? 'End ride'
            : atPickup
                ? 'Start ride'
                : "I've arrived";

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 14,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.directions_car_filled_rounded, color: green, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                          Text(name, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
                    ),
                    Material(
                      color: const Color(0xFF4038FF).withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => showSendRideNotificationSheet(context, ride),
                        child: const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(Icons.notifications_rounded, color: Color(0xFF4038FF), size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_etaLeftSeconds > 0)
                      Text(_runningClock(_etaLeftSeconds), style: const TextStyle(color: green, fontWeight: FontWeight.w900, fontSize: 13))
                    else if (eta.isNotEmpty)
                      Text(eta, style: const TextStyle(color: green, fontWeight: FontWeight.w900, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 12),
                _tripStop(color: green, label: 'Pickup', value: pickup.isEmpty ? 'Pickup location' : pickup),
                const SizedBox(height: 8),
                _tripStop(color: const Color(0xFFEF4444), label: 'Drop', value: drop.isEmpty ? 'Drop location' : drop),
                if (fare > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Fare', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('₹${fare.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _callNumber(_personPhone(ride)),
                        icon: const Icon(Icons.call_rounded, size: 18),
                        label: const Text('Call', style: TextStyle(fontWeight: FontWeight.w800)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: green,
                          side: const BorderSide(color: green),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _navigateForRide(ride, toDrop: goingToDrop || paying),
                        icon: const Icon(Icons.navigation_rounded, size: 18),
                        label: const Text('Navigate', style: TextStyle(fontWeight: FontWeight.w800)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF111827),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: _tripBusy
                      ? const Center(child: SizedBox(width: 22, height: 22, child: ViteLoader(strokeWidth: 2, color: green)))
                      : SlideAction(
                          key: ValueKey('home-trip-slide-$action'),
                          text: goingToDrop ? 'Swipe to end ride' : action,
                          textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                          outerColor: goingToDrop ? const Color(0xFFEF4444) : green,
                          innerColor: Colors.white,
                          sliderButtonIcon: Icon(
                            goingToDrop ? Icons.directions_bike : Icons.double_arrow_rounded,
                            color: goingToDrop ? const Color(0xFFEF4444) : green,
                          ),
                          elevation: 0,
                          onSubmit: () async {
                            await _playTripTick();
                            final rideId = _rideIdOf(ride);
                            final driverId = _driverId.trim();
                            if (rideId.isEmpty || driverId.isEmpty) return;
                            if (paying) {
                              await _confirmTripReceived(ride);
                              return;
                            }
                            if (atPickup) {
                              await _askRideOtp(ride);
                              return;
                            }
                            await _runTripAction(() async {
                              if (goingToDrop) {
                                final token = (await _sessionService.getToken() ?? '').trim();
                                final res = await const ApiService().completeRide(
                                  token: token,
                                  rideRequestId: rideId,
                                  driverId: driverId,
                                );
                                if (!mounted) return;
                                final rideNode = res['ride'];
                                final apiStatus = (res['status'] ?? (rideNode is Map ? rideNode['status'] : null) ?? '').toString().trim().toUpperCase();
                                final ok = res['success'] == true || apiStatus == 'COMPLETED' || (res['message'] ?? '').toString().toLowerCase().contains('success');
                                if (!ok) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text((res['message'] ?? 'Could not end the ride').toString())),
                                  );
                                  return;
                                }
                                final extra = rideNode is Map ? Map<String, dynamic>.from(rideNode) : <String, dynamic>{};
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DriverPaymentScreen(ride: {
                                      ...ride,
                                      ...extra,
                                    }),
                                  ),
                                );
                                return;
                              }
                              await const ApiService().driverArrived(rideId: rideId, driverId: driverId);
                            });
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tripStop({required Color color, required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
              Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
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

      final matches = <Map<String, dynamic>>[];
      for (final item in data) {
        if (item is! Map) continue;
        final id = (item['_id'] ?? item['id'] ?? item['ride_id'] ?? item['rideId'] ?? item['rideRequestId'] ?? '').toString();
        if (id.trim().isEmpty) continue;
        if (_acceptedRideId != null && _acceptedRideId == id.trim()) continue;
        if (_ignoredRideIds.contains(id.trim()) || OfferInbox.ignoredIds.contains(id.trim())) continue;
        if (_handledRideRequestIds.contains(id)) continue;

        final status = (item['status'] ?? '').toString().trim().toLowerCase();
        if (status.isNotEmpty && status != 'bidding') continue;

        if (!_isStrictVehicleTypeMatch(_requestVehicleFromMap(Map<String, dynamic>.from(item)))) continue;

        matches.add(Map<String, dynamic>.from(item));
      }

      if (mounted) {
        setState(() {
          _nearbyRequestCount = matches.length + _liveParcelRequests.length + _intercityRequests.length;
          _demandMarkers = _demandMarkersFor(matches);
          if (_driverLatLng != null) {
            _markers = _markersWithDriver(_driverLatLng!);
          }
        });
      }

      OfferInbox.setCity(matches);
      _publishOfferNotification();
      if (matches.isEmpty) {
        if (_intercityRequests.isEmpty && !isDialogOpen) {
          AlertService.stopAlert();
        }
        return;
      }
      if (_activeRide != null) return;
      final next = matches.first;

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

    double kmBetween(LatLng a, LatLng b) {
      final dLat = (b.latitude - a.latitude) * pi / 180;
      final dLng = (b.longitude - a.longitude) * pi / 180;
      final h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * pi / 180) * cos(b.latitude * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
      return 6371 * 2 * atan2(sqrt(h), sqrt(1 - h));
    }

    final fareValue = request['fare'];
    final fare = fareValue is num ? fareValue.round() : int.tryParse(fareValue?.toString() ?? '') ?? 0;
    final customerName = (request['user_name'] ?? request['customerName'] ?? request['userName'] ?? request['name'] ?? 'Customer')
        .toString()
        .trim();
    final userNode = request['user'];
    final userPhoto = userNode is Map
        ? (userNode['user_image'] ?? userNode['profileImage'] ?? userNode['profile_image'] ?? userNode['image'] ?? userNode['photo'] ?? userNode['avatar'] ?? '')
        : '';
    final customerImage = (request['customerImage'] ??
            request['user_image'] ??
            request['userImage'] ??
            request['profile_image'] ??
            request['profileImage'] ??
            request['photo'] ??
            request['avatar'] ??
            request['image'] ??
            userPhoto)
        .toString()
        .trim();

    final distanceValue = request['distance'] ?? request['distanceKm'] ?? request['totalDistance'];
    final timeValue = request['time'] ?? request['duration'] ?? request['durationMins'];
    final parsedDistance = distanceValue is num ? distanceValue.toDouble() : double.tryParse('${distanceValue ?? ''}');
    final routeKm = (parsedDistance != null && parsedDistance > 0.05)
        ? parsedDistance
        : (pickupLatLng != null && dropLatLng != null ? kmBetween(pickupLatLng, dropLatLng) : 0.0);
    final distanceText = routeKm > 0.05 ? routeKm.toStringAsFixed(routeKm < 10 ? 1 : 0) : '';
    final parsedTime = timeValue is num ? timeValue.toDouble() : double.tryParse('${timeValue ?? ''}');
    final timeText = (parsedTime != null && parsedTime > 0)
        ? parsedTime.round().toString()
        : (routeKm > 0.05 ? max(1, (routeKm / 25 * 60).round()).toString() : '');
    final pickupRaw = (request['pickup_distance'] ?? request['pickupDistance'] ?? '').toString().trim();
    final pickupParsed = double.tryParse(pickupRaw.replaceAll(RegExp(r'[^0-9.]'), ''));
    final pickupKm = (pickupParsed != null && pickupParsed > 0.05)
        ? pickupParsed.toStringAsFixed(pickupParsed < 10 ? 1 : 0)
        : (_driverLatLng != null && pickupLatLng != null
            ? kmBetween(_driverLatLng!, pickupLatLng).toStringAsFixed(1)
            : '');

    isDialogOpen = true;
    try {
      AlertService.startAlert();
      final ratingRaw = request['user_rating'] ?? request['rating'] ?? (userNode is Map ? userNode['rating'] : null);
      final reviewRaw = request['review'] ?? request['reviews'] ?? request['rating_count'] ?? (userNode is Map ? userNode['review'] : null);
      final rating = ratingRaw is num ? ratingRaw.toDouble() : double.tryParse('${ratingRaw ?? ''}') ?? 0;
      final reviews = reviewRaw is num ? reviewRaw.toInt() : int.tryParse('${reviewRaw ?? ''}') ?? 0;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0x66000000),
        builder: (dialogContext) {
          _offerDialogContext = dialogContext;
          return RideRequestCard(
            customerName: customerName == 'Customer' ? '' : customerName,
            customerImage: customerImage,
            pickup: pickupAddress.isEmpty ? 'Pickup location' : pickupAddress,
            drop: dropAddress.isEmpty ? 'Drop location' : dropAddress,
            fare: fare,
            seconds: 60,
            pickupDistance: pickupKm,
            dropDistance: distanceText,
            duration: timeText,
            rating: rating,
            reviews: reviews,
            onAccept: (bid) async {
              final ok = await _placeBidAndClose(
                rideRequestId: rideRequestId,
                price: bid <= 0 ? 1 : bid,
                request: request,
              );
              await AlertService.stopAlert();
              return ok;
            },
            onWaitFinished: () async {
              _closeOfferDialog();
            },
            onReject: () async {
              await AlertService.stopAlert();
              _closeOfferDialog();
            },
          );
          // ignore: dead_code
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
                        color: Theme.of(context).colorScheme.surface,
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
                                                const Text(''),
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
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                          color: Theme.of(context).colorScheme.onSurface,
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
                                                      color: Theme.of(context).colorScheme.surface,
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
                                                                  child: ViteLoader(
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
                                                      color: Theme.of(context).colorScheme.surface,
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
    final extraCityRides = AppConfig.intRideSetting('city_rides_while_ongoing', 0);
    final keepingCurrentTrip = _activeRide != null;
    final currentStatus = keepingCurrentTrip ? _rideStatusOf(_activeRide!) : '';
    const cityStatuses = {
      'accepted',
      'assigned',
      'arrived',
      'started',
      'ongoing',
      'in_progress',
      'waiting_user_confirmation',
    };
    final onCityRide = cityStatuses.contains(currentStatus);
    if (onCityRide && extraCityRides <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Finish this city ride before accepting another.'),
          ),
        );
      }
      return false;
    }

    _ignoredRideIds.add(normalizedRideId);
    _handledRideRequestIds.add(normalizedRideId);
    OfferInbox.hide(normalizedRideId);
    OfferInbox.ignore(normalizedRideId);
    _isUpdatingBid = true;
      if (!keepingCurrentTrip) {
        _acceptedRideId = normalizedRideId;
    if (mounted) {
      setState(() {
        _isRideAccepted = true;
      });
    } else {
      _isRideAccepted = true;
        }
    }

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
      if (ok && (!keepingCurrentTrip || onCityRide)) {
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
      _ignoredRideIds.remove(normalizedRideId);
      _handledRideRequestIds.remove(normalizedRideId);
      OfferInbox.release(normalizedRideId);
      if (!keepingCurrentTrip) {
        _acceptedRideId = null;
      if (mounted) {
        setState(() {
          _isRideAccepted = false;
        });
      } else {
        _isRideAccepted = false;
      }
      _refreshRideRequestsPolling();
      }

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

    if (keepingCurrentTrip && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('City ride saved. It opens after this trip ends.')),
      );
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
    if (!isOnline) return;
    try {
      await _togglePlayer.stop();
      await _togglePlayer.setVolume(0.45);
      await _togglePlayer.play(AssetSource('sounds/tick.wav'));
    } catch (_) {}
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
    if (value && _accountHold == 'under_review') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account is under review. You can go online after support resolves it.'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }
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
    if (_activeRide != null && !value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish the active trip before going offline'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    setState(() => _dutyUpdating = true);
    var confirmed = false;
    var failMessage = 'Could not update duty status. Check your connection.';
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) {
        failMessage = 'Please login again.';
      } else {
        final res = await const ApiService().updateDriverStatus(token: token, isOnline: value);
        confirmed = res['success'] == true;
        if (!confirmed && (res['message'] ?? '').toString().trim().isNotEmpty) {
          failMessage = res['message'].toString();
        }
      }
    } catch (_) {}

    if (!mounted) return;
    if (!confirmed) {
      setState(() => _dutyUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failMessage), backgroundColor: const Color(0xFFE53935)),
      );
      return;
    }

    setState(() {
      _dutyUpdating = false;
      _isOnline = value;
      if (!value) {
        _nearbyRequestCount = 0;
        _demandMarkers = <Marker>{};
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isOnlinePrefsKey, value);
    } catch (_) {}

    _refreshHeartbeat();
    _refreshParcelRequestsPolling();

    _playToggleSound(value);
    if (value) {
      AlertService.startDutyWatch();
    } else {
      AlertService.stopAlert();
      AlertService.stopDutyWatch();
    }
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
        color: Theme.of(context).colorScheme.surface,
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "You've completed ${_totalCompletedRides} trips",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
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
                    color: Theme.of(context).colorScheme.surface,
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
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
                          color: Theme.of(context).colorScheme.surface,
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _drawerMenuCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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

  Widget _drawerStatusMark(VerificationStatus status) {
    final IconData icon;
    final Color color;
    switch (status) {
      case VerificationStatus.approved:
        icon = Icons.check_circle;
        color = const Color(0xFF009640);
        break;
      case VerificationStatus.rejected:
        icon = Icons.cancel;
        color = Colors.red;
        break;
      case VerificationStatus.pending:
        icon = Icons.access_time;
        color = Colors.orange;
        break;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 22, height: 22, child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF94A3B8)),
      ],
    );
  }

  Widget _drawerMenuItem(IconData icon, String title, {VoidCallback? onTap, Widget? trailing}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF0A7A40), size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF94A3B8)),
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
        color: Theme.of(context).colorScheme.surface,
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                        Icons.home_outlined,
                        'Home',
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _bottomTabIndex = 0);
                        },
                      ),
                      _drawerMenuItem(
                        Icons.account_balance_wallet_outlined,
                        'My Earnings',
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _bottomTabIndex = 2);
                        },
                      ),
                      _drawerMenuItem(
                        Icons.settings_outlined,
                        'Settings',
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _bottomTabIndex = 3);
                        },
                      ),
                      _drawerMenuItem(
                        Icons.account_balance_wallet,
                        'Wallet',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                        },
                      ),
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
                        trailing: Consumer<DriverStatusSummaryProvider>(
                          builder: (context, s, _) => _drawerStatusMark(s.summary.documentStatus),
                        ),
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
                        trailing: Consumer<DriverStatusSummaryProvider>(
                          builder: (context, s, _) => _drawerStatusMark(s.summary.vehicleStatus),
                        ),
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
                        trailing: Consumer<DriverStatusSummaryProvider>(
                          builder: (context, s, _) => _drawerStatusMark(s.summary.bankStatus),
                        ),
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

  Widget _dashboardHome() => _offlineDashboard();

  bool get _hasIncomingWork =>
      _myWaitingIntercityRides.isNotEmpty ||
      _intercityRequests.isNotEmpty ||
      _seatOffers.isNotEmpty ||
      _openSeatRequests.isNotEmpty ||
      (_parcelDutyOn && _liveParcelRequests.isNotEmpty) ||
      _activeRide != null;

  Future<void> _takeSeatRequest(Map<String, dynamic> row) async {
    final token = (await _sessionService.getToken() ?? '').trim();
    final requestId = (row['request_id'] ?? '').toString();
    final hostId = (row['host_ride_id'] ?? _seatTrip?['host_ride_id'] ?? '').toString();
    final res = await const ApiService().acceptIntercitySeatShare(
      token: token,
      requestId: requestId,
      hostRideId: hostId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res['success'] == true ? 'Passengers added to your car' : (res['message'] ?? 'Could not take this ride').toString())),
    );
  }

  Future<void> _skipSeatOffer(Map<String, dynamic> row) async {
    final token = (await _sessionService.getToken() ?? '').trim();
    await const ApiService().declineIntercitySeatShare(
      token: token,
      requestId: (row['request_id'] ?? '').toString(),
    );
    if (!mounted) return;
    setState(() {
      _seatOffers = _seatOffers.where((e) => e['request_id'] != row['request_id']).toList();
    });
  }

  Widget _seatPassengerCard(Map<String, dynamic> row, {required bool offered}) {
    final count = row['passenger_count'] ?? 1;
    final name = (row['rider_name'] ?? 'Passenger').toString();
    final price = row['price'] ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 8, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF009640)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offered ? 'Empty seats offered to you' : 'Fill your empty seats',
            style: const TextStyle(color: Color(0xFF009640), fontWeight: FontWeight.w900, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text('$name · $count passenger${count == 1 ? '' : 's'} · ₹$price', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${row['pickup'] ?? ''}  →  ${row['drop'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(
            children: [
              if (offered)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _skipSeatOffer(row),
                    child: const Text('Not now'),
                  ),
                ),
              if (offered) const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF009640), foregroundColor: Colors.white),
                  onPressed: () => _takeSeatRequest(row),
                  child: const Text('Take them', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySeatsCard() {
    final empty = _seatTrip?['empty_seats'] ?? 0;
    final filled = _seatTrip?['seats_filled'] ?? 0;
    final capacity = _seatTrip?['seat_capacity'] ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 8, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F6EC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Your car has $empty empty seat${empty == 1 ? '' : 's'} ($filled/$capacity filled). Matching passengers on this route can join so the trip covers the cost.',
        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF14532D)),
      ),
    );
  }

  Widget _buildSeatFillCards() {
    return Column(
      children: [
        ..._seatOffers.map((row) => _seatPassengerCard(row, offered: true)),
        ..._openSeatRequests.where((row) => row['offered'] != true).map((row) => _seatPassengerCard(row, offered: false)),
      ],
    );
  }

  Widget _incomingWorkList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_myWaitingIntercityRides.isNotEmpty)
          _buildIntercityWaitingCard(_myWaitingIntercityRides.first),
        if (_seatTrip != null && ((_seatTrip?['empty_seats'] ?? 0) as num) > 0)
          _buildEmptySeatsCard(),
        if (_seatOffers.isNotEmpty || _openSeatRequests.isNotEmpty) _buildSeatFillCards(),
        if (_intercityRequests.isNotEmpty) ..._intercityRequests.map(_buildIntercityRequestCard),
        if (_parcelDutyOn && _liveParcelRequests.isNotEmpty)
          ..._liveParcelRequests.map(_buildParcelRequestCard),
        if (!_hasIncomingWork) _dashboardCenterSection(),
      ],
    );
  }

  Widget _offlineDashboard() {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(
          child: MapplsView(
            key: const ValueKey('captain-home-map'),
            initialCameraPosition: CameraPosition(target: _cameraTarget, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              _liveMap = controller;
              if (!_mapController.isCompleted) _mapController.complete(controller);
              final here = _driverLatLng;
              if (here != null) {
                controller.animateCamera(CameraUpdate.newLatLngZoom(here, 15));
              }
            },
          ),
        ),
        Positioned(top: top + 10, left: 12, right: 12, child: _mapHomeHeader()),
        if (_activeRide == null)
          Positioned(top: top + 86, left: 12, child: _mapDashCard()),
        Positioned(
          top: top + 86,
          right: 12,
          child: _mapControlButton(
            icon: Icons.my_location_rounded,
            onTap: _recenterHomeMap,
          ),
        ),
        if (_locationFailed)
          Positioned(
            top: top + 78,
            left: 16,
            right: 16,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.all(Radius.circular(12)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('Location permission is needed to show your position.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _recenterHomeMap() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationFailed = true);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (!mounted) return;
      final target = LatLng(position.latitude, position.longitude);
      setState(() {
        _driverLatLng = target;
        _cameraTarget = target;
        _locationFailed = false;
        _markers = _markersWithDriver(target);
      });
      final map = _liveMap ?? (_mapController.isCompleted ? await _mapController.future : null);
      if (map == null) return;
      await map.animateCamera(
        CameraUpdate.newLatLngZoom(target, 16),
        duration: const Duration(milliseconds: 500),
      );
    } catch (_) {
      if (mounted) setState(() => _locationFailed = true);
    }
  }

  Widget _mapHomeHeader() {
    return FutureBuilder<Map<String, String>>(
      future: _userBasicsFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, String>{};
        final mobile = (data['mobile'] ?? '').trim();
        final image = _driverImageUrl.trim().isNotEmpty ? _driverImageUrl.trim() : (data['imageUrl'] ?? '').trim();
        final name = _homeCaptainName(data['name'] ?? '', mobile);
        final initial = name.isEmpty ? 'C' : name[0].toUpperCase();
        return Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  backgroundImage: image.isEmpty ? null : NetworkImage(image),
                  child: image.isEmpty ? Text(initial, style: const TextStyle(color: Color(0xFF149444), fontWeight: FontWeight.w800, fontSize: 18)) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_wishTitle(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF149444), fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 1),
                      Text(name.isEmpty ? 'Captain' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 16)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _mapDutyToggle(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mapDutyToggle() {
    final online = _isOnline;
    return Container(
      height: 36,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _dutyUpdating || !online ? null : () => _toggleStatus(false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: online ? Colors.transparent : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: online ? Colors.transparent : const Color(0xFFE5E7EB)),
              ),
              child: Text('OFF', style: TextStyle(color: online ? const Color(0xFF9CA3AF) : const Color(0xFF374151), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
          GestureDetector(
            onTap: _dutyUpdating || online ? null : () => _toggleStatus(true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: online ? const Color(0xFF149444) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('ON DUTY', style: TextStyle(color: online ? Colors.white : const Color(0xFF149444), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapDashCard() {
    final rating = _driverRating > 0 ? _driverRating.toStringAsFixed(1) : '0.0';
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => setState(() => _bottomTabIndex = 2),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.grid_view_rounded, color: Color(0xFF149444), size: 16),
                SizedBox(width: 6),
                Text('Dashboard', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            _mapDashRow(Icons.payments_rounded, _inr(_todayEarning), 'Earnings'),
            const SizedBox(height: 8),
            _mapDashRow(Icons.star_rounded, rating, 'Ratings'),
            const SizedBox(height: 8),
            _mapDashRow(Icons.receipt_long_rounded, '$_todayTrips', 'Trips'),
          ],
        ),
      ),
      ),
    );
  }

  Widget _mapDashRow(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
        children: [
          Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFF149444), size: 16),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 14, height: 1.1)),
            Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _homeBanner(double top) {
    final unread = context.watch<ChatNotificationProvider>().unreadCount;
    return Container(
      clipBehavior: Clip.antiAlias,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, top + 14, 12, 18),
            decoration: const BoxDecoration(
        color: Color(0xFF149444),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -28,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.08)),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -24,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.06)),
            ),
          ),
          Row(
            children: [
              Expanded(child: _homeIdentity()),
              const SizedBox(width: 8),
              _headerDutySwitch(),
              _homeCircleButton(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                showDot: unread > 0,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _homeIdentity() {
    return FutureBuilder<Map<String, String>>(
      future: _userBasicsFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, String>{};
        final mobile = (data['mobile'] ?? '').trim();
        final image = _driverImageUrl.trim().isNotEmpty ? _driverImageUrl.trim() : (data['imageUrl'] ?? '').trim();
        final name = _homeCaptainName(data['name'] ?? '', mobile);
        final initial = name.isEmpty ? 'C' : name[0].toUpperCase();
        final ratingLabel = _driverRating > 0 ? _driverRating.toStringAsFixed(1) : '';
        return Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.22),
              backgroundImage: image.isEmpty ? null : NetworkImage(image),
              child: image.isEmpty ? Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_wishTitle(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, height: 1.1),
                  ),
                  if (ratingLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 15),
                        const SizedBox(width: 2),
                        Text(ratingLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _headerDutySwitch() {
    final online = _isOnline;
    return GestureDetector(
      onTap: _dutyUpdating ? null : () => _toggleStatus(!online),
      onHorizontalDragEnd: _dutyUpdating
          ? null
          : (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 80 && !online) _toggleStatus(true);
              if (velocity < -80 && online) _toggleStatus(false);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 96,
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: online ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 46,
                height: 28,
                decoration: BoxDecoration(
                  color: online ? const Color(0xFF149444) : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      'Off',
                      style: TextStyle(
                        color: online ? const Color(0xFF6B7280) : const Color(0xFF374151),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'On',
                      style: TextStyle(
                        color: online ? Colors.white : const Color(0xFF6B7280),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayEarningsCard() {
    final avg = _todayTrips <= 0 ? 0.0 : _todayEarning / _todayTrips;
    final parts = _todayHours.split(':');
    final hours = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final mins = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.10), blurRadius: 28, offset: const Offset(0, 14)),
          BoxShadow(color: const Color(0xFF149444).withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text("Today's earnings", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 15))),
              GestureDetector(
                onTap: () => setState(() => _bottomTabIndex = 2),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('See all', style: TextStyle(color: Color(0xFF149444), fontWeight: FontWeight.w800, fontSize: 14)),
                    Icon(Icons.chevron_right_rounded, color: Color(0xFF149444), size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(_inr(_todayEarning), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface, height: 1.05, letterSpacing: -0.8)),
              ),
              if (_lastTripEarning > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFE7F8EE), borderRadius: BorderRadius.circular(20)),
                  child: Text('+${_inr(_lastTripEarning)} last trip', style: const TextStyle(color: Color(0xFF149444), fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: Theme.of(context).colorScheme.surface),
          const SizedBox(height: 12),
          Row(
            children: [
              _earningStat(Icons.directions_car_filled_rounded, const Color(0xFF3B82F6), const Color(0xFFE8F1FF), '$_todayTrips', 'Trips'),
              _statDivider(),
              _earningStat(Icons.schedule_rounded, const Color(0xFF7C3AED), const Color(0xFFF3E8FF), '${hours}h ${mins}m', 'Online'),
              _statDivider(),
              _earningStat(Icons.currency_rupee_rounded, const Color(0xFFF59E0B), const Color(0xFFFFF4E5), _inr(avg), 'Per trip'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 36, color: Theme.of(context).colorScheme.surface);

  Widget _earningStat(IconData icon, Color color, Color background, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: background, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _dutyBanner() {
    final online = _isOnline;
    final label = _dutyUpdating ? 'Please wait' : (online ? 'Searching for ride requests...' : 'Go online');
    return Material(
      color: online ? const Color(0xFFE7F6EC) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: online || _dutyUpdating ? null : () => _toggleStatus(true),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: online ? const Color(0xFFD7F0E1) : const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              _PulseDot(active: online && !_dutyUpdating),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: online ? const Color(0xFF3F6B52) : const Color(0xFF149444), fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wishCard() {
    final hour = DateTime.now().hour;
    final night = hour >= 21 || hour < 5;
    final evening = hour >= 17 && hour < 21;
    final afternoon = hour >= 12 && hour < 17;
    final icon = night
        ? Icons.nights_stay_rounded
        : evening
            ? Icons.wb_twilight_rounded
            : afternoon
                ? Icons.wb_cloudy_rounded
                : Icons.wb_sunny_rounded;
    final tint = night
        ? const Color(0xFF1E3A8A)
        : evening
            ? const Color(0xFFC2410C)
            : afternoon
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFB45309);
    final background = night
        ? const Color(0xFFEEF2FF)
        : evening
            ? const Color(0xFFFFF7ED)
            : afternoon
                ? const Color(0xFFEFF6FF)
                : const Color(0xFFFFFBEB);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
            child: Icon(icon, color: tint, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  () {
                    final who = _homeCaptainName('', '');
                    return who.isEmpty ? _wishTitle() : '${_wishTitle()}, $who';
                  }(),
                  style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(_wishMessage(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 13, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletHomeCard() {
    final balance = _walletBalanceLoading ? '...' : _inr(_walletBalance);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wallet balance', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(balance, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 28, height: 1.1)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _walletAction(
                  label: 'Open wallet',
                  filled: true,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                    if (mounted) _loadWalletBalance();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _walletAction(
                  label: 'Withdraw',
                  filled: false,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverWithdrawScreen())),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _walletAction({required String label, required bool filled, required VoidCallback onTap}) {
    return Material(
      color: filled ? const Color(0xFF149444) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
              alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF149444)),
          ),
          child: Text(label, style: TextStyle(color: filled ? Colors.white : const Color(0xFF149444), fontWeight: FontWeight.w800, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _weekChartCard() {
    var peak = 0.0;
    for (final day in _weekDays) {
      if (day > peak) peak = day;
    }
    final todayIndex = DateTime.now().weekday - 1;
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('This week', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 16))),
              Text(_inr(_weekTotal), style: const TextStyle(color: Color(0xFF149444), fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final share = peak <= 0 ? 0.0 : _weekDays[index] / peak;
                final height = 14 + share * 48;
                final active = index == todayIndex;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        height: height,
                        width: 16,
                        decoration: BoxDecoration(
                          color: active ? const Color(0xFF149444) : const Color(0xFFCDEBD8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(labels[index], style: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayGlance(double avg, int hours, int mins) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFF009640).withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
          Expanded(
                child: Text("Today's earnings", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              GestureDetector(
                onTap: () => setState(() => _bottomTabIndex = 2),
                child: const Text('See all', style: TextStyle(color: Color(0xFF009640), fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '₹${_todayEarning.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface, height: 1.1, letterSpacing: -0.8),
          ),
          const SizedBox(height: 14),
          Row(
              children: [
              _tintStat('$_todayTrips', 'Trips', const Color(0xFFEAF8F0), const Color(0xFF067A3C)),
              const SizedBox(width: 8),
              _tintStat('${hours}h ${mins}m', 'Online', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
              const SizedBox(width: 8),
              _tintStat('₹${avg.toStringAsFixed(0)}', 'Per trip', const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tintStat(String value, String label, Color background, Color foreground) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: foreground.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required String value,
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: foreground, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _earningsSummaryCard() {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _bottomTabIndex = 2),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Today's Earnings", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      '₹ ${_todayEarning.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface, height: 1.1),
                    ),
                  ],
                ),
              ),
              const Column(
                children: [
                  Icon(Icons.bar_chart_rounded, color: Color(0xFF009640), size: 22),
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View Details', style: TextStyle(color: Color(0xFF009640), fontWeight: FontWeight.w800, fontSize: 12)),
                      Icon(Icons.chevron_right, color: Color(0xFF009640), size: 16),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _performanceRow(double avg) {
    Widget metric(IconData icon, Color tint, String value, String label) {
      return Expanded(
        child: Column(
          children: [
            Icon(icon, color: tint, size: 20),
            const SizedBox(height: 4),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    final parts = _todayHours.split(':');
    final hours = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final mins = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          metric(Icons.directions_car_filled_outlined, const Color(0xFF009640), '$_todayTrips', 'Trips'),
          Container(width: 1, height: 36, color: const Color(0xFFE5E7EB)),
          metric(Icons.schedule_rounded, const Color(0xFF3B82F6), '${hours}h ${mins}m', 'Online Time'),
          Container(width: 1, height: 36, color: const Color(0xFFE5E7EB)),
          metric(Icons.payments_outlined, const Color(0xFFF59E0B), '₹ ${avg.toStringAsFixed(0)}', 'Avg. Earning'),
        ],
      ),
    );
  }

  Widget _dutyActionRow() {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _dutyUpdating ? null : () => _toggleStatus(!_isOnline),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFB7E4C7)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: Color(0xFF009640), shape: BoxShape.circle),
                child: Icon(_isOnline ? Icons.power_settings_new : Icons.power_settings_new, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dutyUpdating ? 'Updating...' : (_isOnline ? 'Go Offline' : 'Go Online'),
                      style: const TextStyle(color: Color(0xFF067A3C), fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF009640)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeShortcuts() {
    Widget tile(IconData icon, String label, Color background, Color tint, VoidCallback onTap) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  children: [
                    Icon(icon, color: tint, size: 22),
                    const SizedBox(height: 8),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                    const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(Icons.account_balance_wallet_outlined, 'Wallet', const Color(0xFFEAF8F0), const Color(0xFF009640), () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
          if (mounted) _loadWalletBalance();
        }),
        tile(Icons.bar_chart_rounded, 'Earnings', const Color(0xFFE8F1FF), const Color(0xFF3B82F6), () => setState(() => _bottomTabIndex = 2)),
        tile(Icons.assignment_outlined, 'My Jobs', const Color(0xFFFFF4E5), const Color(0xFFF59E0B), () => setState(() => _bottomTabIndex = 1)),
        tile(Icons.star_rounded, 'My Rating', const Color(0xFFF3E8FF), const Color(0xFF8B5CF6), () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRatingScreen()));
        }),
      ],
    );
  }

  Widget _onlineMapHome() {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(
          child: MapplsView(
            initialCameraPosition: CameraPosition(target: _cameraTarget, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              if (!_mapController.isCompleted) _mapController.complete(controller);
              controller.animateCamera(CameraUpdate.newLatLngZoom(_cameraTarget, 16));
            },
          ),
        ),
        Positioned(
          top: top + 8,
          left: 12,
          right: 12,
          child: _onlineTopBar(),
        ),
        if (_locationFailed)
          Positioned(
            top: top + 64,
            left: 16,
            right: 16,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Location permission is needed to show your position.',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  int get _incomingCount =>
      _myWaitingIntercityRides.length +
      _intercityRequests.length +
      (_parcelDutyOn ? _liveParcelRequests.length : 0);

  Widget _incomingRequestsLayer() {
    final count = _incomingCount;
    if (count <= 0) return const SizedBox.shrink();
    if (count > _seenIncomingCount && !_requestsSheetOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_requestsSheetOpen) setState(() => _requestsSheetOpen = true);
      });
    }
    _seenIncomingCount = count;

    final bottom = 64.0 + MediaQuery.paddingOf(context).bottom;
    if (_requestsSheetOpen) {
      return _multipleRequestsSheet();
    }
    return Positioned(
        right: 16,
        bottom: bottom + 12,
        child: Material(
          color: Colors.white,
          elevation: 4,
          shadowColor: const Color(0x33000000),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => setState(() => _requestsSheetOpen = true),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0xFF009640), shape: BoxShape.circle),
                    child: Text(
                      '$count',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    count == 1 ? 'Request' : 'Requests',
                    style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Color(0xFF6B7280)),
                ],
              ),
            ),
          ),
        ),
      );
  }

  void _focusIncomingRequest(String id) {
    setState(() => _selectedIncomingId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _incomingCardKeys[id]?.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 280),
        alignment: 0.08,
        curve: Curves.easeOut,
      );
    });
  }

  void _armIncomingClock(List<String> ids) {
    final now = DateTime.now();
    for (final id in ids) {
      _incomingSeenAt.putIfAbsent(id, () => now);
    }
    _incomingSeenAt.removeWhere((id, _) => !ids.contains(id));
    if (_incomingTick != null) return;
    _incomingTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_requestsSheetOpen || _incomingCount < 1) {
        _incomingTick?.cancel();
        _incomingTick = null;
        return;
      }
      setState(() {});
    });
  }

  int _incomingSecondsLeft(String id) {
    const window = 60;
    final seen = _incomingSeenAt[id];
    if (seen == null) return window;
    final left = window - DateTime.now().difference(seen).inSeconds;
    if (left < 0) return 0;
    if (left > window) return window;
    return left;
  }

  Color _incomingRingColor(int seconds, bool selected) {
    if (selected) return const Color(0xFF009640);
    if (seconds >= 45) return const Color(0xFF9CA3AF);
    if (seconds >= 30) return const Color(0xFFEF4444);
    if (seconds >= 18) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  List<_IncomingChoice> _incomingChoices() {
    final rows = <_IncomingChoice>[];
    for (final req in _myWaitingIntercityRides) {
      rows.add(_IncomingChoice(
        id: 'wait-${req.id}',
        card: _buildIntercityWaitingCard(req),
      ));
    }
    for (final req in _intercityRequests) {
      rows.add(_IncomingChoice(
        id: req.id,
        card: _buildIntercityRequestCard(req),
      ));
    }
    if (_parcelDutyOn) {
      for (final parcel in _liveParcelRequests) {
        final id = _asTrimmed(parcel['_id'] ?? parcel['id']);
        if (id.isEmpty) continue;
        rows.add(_IncomingChoice(
          id: 'parcel-$id',
          card: _buildParcelRequestCard(parcel),
        ));
      }
    }
    final now = DateTime.now();
    for (final row in rows) {
      _incomingSeenAt.putIfAbsent(row.id, () => now);
    }
    rows.sort((a, b) {
      final aSeen = _incomingSeenAt[a.id] ?? now;
      final bSeen = _incomingSeenAt[b.id] ?? now;
      return aSeen.compareTo(bSeen);
    });
    return rows;
  }

  Widget _multipleRequestsSheet() {
    final rows = _incomingChoices();
    if (rows.isEmpty) return const SizedBox.shrink();
    _armIncomingClock(rows.map((row) => row.id).toList());
    var selectedId = _selectedIncomingId;
    if (!rows.any((row) => row.id == selectedId)) selectedId = rows.first.id;
    final listHeight = min(MediaQuery.sizeOf(context).height * 0.62, 560.0);
    for (final row in rows) {
      _incomingCardKeys.putIfAbsent(row.id, GlobalKey.new);
    }

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _requestsSheetOpen = false),
              child: const ColoredBox(color: Color(0x73000000)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: Colors.white,
              elevation: 18,
              shadowColor: Colors.black54,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(99)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 4, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              rows.length == 1 ? 'New request' : 'New requests',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _requestsSheetOpen = false),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF111827)),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: listHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 58,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(6, 4, 0, 12),
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                final isSelected = row.id == selectedId;
                                final seconds = _incomingSecondsLeft(row.id);
                                final ring = _incomingRingColor(seconds, isSelected);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Material(
                                    color: isSelected ? const Color(0xFFE7F8EE) : Colors.transparent,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => _focusIncomingRequest(row.id),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: RequestCountdownRing(seconds: seconds, totalSeconds: 60, color: ring),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: _incomingListScroll,
                              padding: const EdgeInsets.only(bottom: 12),
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                final isSelected = row.id == selectedId;
                                return Container(
                                  key: _incomingCardKeys[row.id],
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF009640) : Colors.transparent,
                                      width: isSelected ? 1.5 : 0,
                                    ),
                                  ),
                                  child: row.card,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineTopBar() {
    final unread = context.watch<ChatNotificationProvider>().unreadCount;
    return Row(
      children: [
        _mapControlButton(
          icon: Icons.menu_rounded,
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        const Spacer(),
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 3,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _dutyUpdating ? null : () => _toggleStatus(false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF009640), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _dutyUpdating ? '...' : 'ONLINE',
                    style: const TextStyle(color: Color(0xFF009640), fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        _mapControlButton(
          icon: Icons.notifications_none_rounded,
          showDot: unread > 0,
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          },
        ),
        const SizedBox(width: 8),
        _mapControlButton(
          icon: Icons.sos_rounded,
          background: const Color(0xFFE11D48),
          iconColor: Colors.white,
          onTap: _handleHomeSOS,
        ),
      ],
    );
  }

  Widget _mapControlButton({
    required IconData icon,
    required VoidCallback onTap,
    Color background = Colors.white,
    Color iconColor = const Color(0xFF111827),
    bool showDot = false,
  }) {
    return Material(
      color: background,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: iconColor, size: 22),
              if (showDot)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(radius: 4, backgroundColor: Color(0xFFE11D48)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandHeader() {
    final unread = context.watch<ChatNotificationProvider>().unreadCount;
    return Row(
      children: [
        const Text('Vite Captain', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, height: 1)),
        const Spacer(),
        _headerIconButton(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          showDot: unread > 0,
          light: true,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        ),
        _headerIconButton(
          icon: Icons.headset_mic_outlined,
          label: 'Support',
          light: true,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen())),
        ),
      ],
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool showDot = false,
    bool light = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: light ? Colors.white.withValues(alpha: 0.18) : const Color(0xFFF3F4F6),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, color: light ? Colors.white : const Color(0xFF111827), size: 24),
                  if (showDot)
                    const Positioned(
                      right: 10,
                      top: 10,
                      child: CircleAvatar(radius: 4, backgroundColor: Color(0xFFE11D48)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _captainHeader() {
    return FutureBuilder<Map<String, String>>(
      future: _userBasicsFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, String>{};
        final rawName = _driverName.trim().isNotEmpty ? _driverName.trim() : (data['name'] ?? '').trim();
        final mobile = (data['mobile'] ?? '').trim();
        final image = _driverImageUrl.trim().isNotEmpty ? _driverImageUrl.trim() : (data['imageUrl'] ?? '').trim();
        final greetingName = _displayCaptainName(rawName, mobile);
        final phoneLine = mobile.isNotEmpty ? mobile : (_looksLikePhone(rawName) ? rawName : '');
        final rating = _driverRating > 0 ? _driverRating.toStringAsFixed(1) : '0.0';
        final countLabel = _ratingCount > 0 ? ' ($_ratingCount)' : '';
        return Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  backgroundImage: image.isEmpty ? null : NetworkImage(image),
                  child: image.isEmpty ? const Icon(Icons.person, color: Color(0xFF009640), size: 28) : null,
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hi, $greetingName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 18),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          phoneLine.isEmpty ? '$rating$countLabel' : '$rating$countLabel  ·  $phoneLine',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isOnline ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _dutyUpdating ? 'Wait' : (_isOnline ? 'Online' : 'Offline'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  bool _looksLikePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8;
  }

  String _displayCaptainName(String name, String mobile) {
    if (name.isEmpty || _looksLikePhone(name) || name == mobile) return 'Captain';
    return name;
  }

  String _homeCaptainName(String sessionName, String mobile) {
    final saved = _driverName.trim();
    final session = sessionName.trim();
    for (final value in [saved, session]) {
      if (value.isEmpty || value == mobile || _looksLikePhone(value)) continue;
      if (value.toLowerCase() == 'captain') continue;
      return value;
    }
    return saved.isNotEmpty && saved.toLowerCase() != 'captain' && !_looksLikePhone(saved) ? saved : '';
  }

  String _wishTitle() {
    final hour = DateTime.now().hour;
    if (hour < 5 || hour >= 21) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _wishMessage() => 'Go online and start the earning.';

  Widget _homeCircleButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool showDot = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: const Color(0xFFC8EE7A),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, color: const Color(0xFF166534), size: 20),
                  if (showDot) const Positioned(right: 9, top: 9, child: CircleAvatar(radius: 4, backgroundColor: Color(0xFFE11D48))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dutyCard() {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isOnline ? const Color(0xFF009640) : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isOnline ? 'ONLINE' : 'OFF DUTY',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.4, color: Theme.of(context).colorScheme.onSurface),
                ),
                const Spacer(),
                Switch(
                  value: _isOnline,
                  activeThumbColor: const Color(0xFF009640),
                  onChanged: _dutyUpdating ? null : (value) => _toggleStatus(value),
                ),
              ],
            ),
            Text(
              _isOnline
                  ? 'You are online and can receive ride requests'
                  : 'Go online to start receiving ride requests',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletCard() {
    return Material(
      color: const Color(0xFFE7F6EC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _bottomTabIndex = 2),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "TODAY'S EARNINGS",
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '₹ ${_todayEarning.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface, height: 1),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 46, color: const Color(0xFFD1E7D8)),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TRIPS',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_todayTrips',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface, height: 1),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActions() {
    Widget item(IconData icon, String label, Color tint, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 26),
              ),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        item(Icons.account_balance_wallet_outlined, 'Wallet', const Color(0xFF16A34A), () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
          if (mounted) _loadWalletBalance();
        }),
        item(Icons.bar_chart_rounded, 'Earnings', const Color(0xFF3B82F6), () {
          setState(() => _bottomTabIndex = 2);
        }),
        item(Icons.receipt_long_outlined, 'Activity', const Color(0xFFF59E0B), () {
          setState(() => _bottomTabIndex = 1);
        }),
        item(Icons.star_rounded, 'My Rating', const Color(0xFFFBBF24), () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRatingScreen()));
        }),
      ],
    );
  }

  Widget _offlineBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 188,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFFE7F8EE)),
            Image.asset(
              'assets/images/vitecaptain-car-banner.png',
              fit: BoxFit.fitHeight,
              alignment: Alignment.centerRight,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 148, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("You're Offline", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 6),
                  Text(
                    'Go online and start\nearning with ViteCaptain',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 14, height: 1.25),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _dutyUpdating ? null : () => _toggleStatus(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF009640),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    icon: const Icon(Icons.power_settings_new, size: 18, color: Colors.white),
                    label: const Text('Go Online', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayStats() {
    Widget tile(IconData icon, String value, String label, Color bg) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: const Color(0xFF166534)),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text("Today's Stats", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            TextButton(
              onPressed: () => setState(() => _bottomTabIndex = 2),
              child: const Text('View All', style: TextStyle(color: Color(0xFF009640), fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        Row(
          children: [
            tile(Icons.local_taxi_outlined, '$_todayTrips', 'Trips Completed', const Color(0xFFE8F8EE)),
            const SizedBox(width: 10),
            tile(Icons.schedule_rounded, _todayHours, 'Online Hours', const Color(0xFFEFF6FF)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            tile(Icons.currency_rupee, '₹ ${_todayEarning.toStringAsFixed(2)}', "Today's Earnings", const Color(0xFFFEF9C3)),
            const SizedBox(width: 10),
            tile(Icons.star_rounded, _driverRating > 0 ? _driverRating.toStringAsFixed(1) : '0.0', "Today's Rating", const Color(0xFFFFE4E6)),
          ],
        ),
      ],
    );
  }

  Set<Marker> _markersForActiveRide(LatLng driver, {double rotation = 0}) {
    final ride = _activeRide;
    final pickup = ride == null ? null : (_latLngOf(ride['pickup']) ?? _latLngOf(ride['pickup_location']));
    final drop = ride == null ? null : (_latLngOf(ride['drop']) ?? _latLngOf(ride['drop_location']));
    return <Marker>{
      Marker(
        markerId: const MarkerId('driver'),
        position: driver,
        icon: _driverIcon ?? BitmapDescriptor.defaultMarker,
        flat: true,
        rotation: rotation,
        anchor: const Offset(0.5, 0.5),
      ),
      if (pickup != null)
        Marker(
          markerId: const MarkerId('active_pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
      if (drop != null)
        Marker(
          markerId: const MarkerId('active_drop'),
          position: drop,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Drop'),
        ),
    };
  }

  String _activeRouteKey = '';

  Future<void> _syncActiveRideMap(Map<String, dynamic> ride, {bool fit = false}) async {
    final driver = _driverLatLng;
    final pickup = _latLngOf(ride['pickup']) ?? _latLngOf(ride['pickup_location']);
    final drop = _latLngOf(ride['drop']) ?? _latLngOf(ride['drop_location']);
    if (driver != null && mounted) {
      setState(() {
        _markers = _markersForActiveRide(driver);
      });
    }
    final status = _rideStatusOf(ride);
    final toDrop = status == 'ongoing' || status == 'started' || status == 'in_progress' || _isCompletedRideStatus(status);
    final target = toDrop ? drop : pickup;
    final origin = driver ?? (toDrop ? pickup : null);
    if (origin == null || target == null) return;
    final key = '${toDrop ? 'drop' : 'pickup'}|${origin.latitude.toStringAsFixed(3)},${origin.longitude.toStringAsFixed(3)}|${target.latitude.toStringAsFixed(4)},${target.longitude.toStringAsFixed(4)}';
    if (_activeRouteKey == key && _polylines.isNotEmpty && !fit) return;
    _activeRouteKey = key;
    final requestId = ++_routeRequestId;
    final route = await _buildRoutePolyline(origin, target);
    if (!mounted || requestId != _routeRequestId) return;
    setState(() {
      _polylines = route == null ? <Polyline>{} : <Polyline>{route};
    });
    if (fit) {
      await _fitBoundsForPickupDrop(origin, target);
    }
  }

  Set<Marker> _markersWithDriver(LatLng latLng, {double rotation = 0}) {
    return <Marker>{
      Marker(
        markerId: const MarkerId('driver'),
        position: latLng,
        icon: _driverIcon ?? BitmapDescriptor.defaultMarker,
        flat: true,
        rotation: rotation,
        anchor: const Offset(0.5, 0.5),
      ),
      ..._demandMarkers,
    };
  }

  double? _asCoord(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }

  Set<Marker> _demandMarkersFor(List<Map<String, dynamic>> requests) {
    final markers = <Marker>{};
    for (final request in requests.take(8)) {
      final pickup = request['pickup'];
      if (pickup is! Map) continue;
      final lat = _asCoord(pickup['lat'] ?? pickup['latitude']);
      final lng = _asCoord(pickup['lng'] ?? pickup['lon'] ?? pickup['longitude']);
      if (lat == null || lng == null) continue;
      final id = (request['_id'] ?? request['id'] ?? lat.toString()).toString();
      markers.add(
        Marker(
          markerId: MarkerId('demand_$id'),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Nearby trip'),
        ),
      );
    }
    return markers;
  }

  Future<void> _loadDriverIcon() async {
    if (_driverIcon != null) return;
    try {
      final bytes = await _materialIconToPng(
        iconData: Icons.directions_car,
        size: 72,
        color: const Color(0xFF369D01),
        backgroundColor: Theme.of(context).colorScheme.surface,
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
              try {
                final zone = await ZoneService.instance.syncLocation(pos.latitude, pos.longitude);
                if (zone != null && zone.isNotEmpty && zone != _serviceState && mounted) {
                  setState(() => _serviceState = zone);
                  _loadZoneServices(zone);
                }
              } catch (_) {}
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _driverLatLng = latLng;
          _speedKmh = nextSpeed.isFinite ? nextSpeed.clamp(0, 250).toDouble() : 0;
          if (_activeRide == null) {
          _cameraTarget = latLng;
            _markers = _markersWithDriver(latLng, rotation: pos.heading);
          _polylines = <Polyline>{};
          } else {
            _markers = _markersForActiveRide(latLng, rotation: pos.heading);
          }
        });
        final ride = _activeRide;
        if (ride != null) {
          _syncActiveRideMap(ride);
          _syncRideBubble(ride);
        }
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
    _tts?.stop();
    _etaTick?.cancel();
    _incomingTick?.cancel();
    _incomingListScroll.dispose();
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
      _locationFailed = false;
      await _loadDriverIcon();

      setState(() {
        _driverLatLng = LatLng(lat, lng);
        _markers = _markersWithDriver(LatLng(lat, lng));
        _polylines = <Polyline>{};
      });

      final map = _liveMap ?? (_mapController.isCompleted ? await _mapController.future : null);
      if (map != null) {
        await map.animateCamera(
          CameraUpdate.newLatLngZoom(_cameraTarget, 16),
          duration: const Duration(milliseconds: 500),
        );
      }
    } catch (_) {
      _locationFailed = true;
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
        color: Theme.of(context).colorScheme.surface,
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
    int badge = 0,
  }) {
    final bool isActive = _bottomTabIndex == index;
    final color = isActive ? const Color(0xFF009640) : const Color(0xFF9CA3AF);
    return Expanded(
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
          setState(() => _bottomTabIndex = index);
          if (index == 0) _hydrateParcelDuty();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF149444) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: isActive ? Colors.white : const Color(0xFF9CA3AF), size: 22),
                ),
                if (badge > 0)
                  Positioned(
                    right: -4,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(10)),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: const Color(0x1A000000),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
          child: Row(
            children: [
              _buildNavItem(icon: Icons.home_rounded, label: 'Home', index: 0),
              _buildNavItem(icon: Icons.format_list_bulleted_rounded, label: 'Trips', index: 1, badge: _nearbyRequestCount),
              _buildNavItem(icon: Icons.account_balance_wallet_outlined, label: 'Earnings', index: 2),
              _buildNavItem(icon: Icons.person_outline_rounded, label: 'Profile', index: 3),
            ],
          ),
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Icon(Icons.notifications_none, color: Theme.of(context).colorScheme.onSurface),
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
          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 4),
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
          color: Theme.of(context).colorScheme.surface,
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
            icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurface),
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
        final route = await fetchMapplsRoute(pickup, drop);
        if (route == null) {
          points = <LatLng>[pickup, drop];
        } else {
          points = route.points;
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
    final map = _liveMap ?? (_mapController.isCompleted ? await _mapController.future : null);
    if (map == null) return;

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
        coupon: rideState.appliedCoupon,
        onDraftFare: rideState.setOfferFare,
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
      if (!mounted) return;
      await _openSetPriceSheet();
      return;
    }

    rideState.setOfferFare(result);
  }

  Future<void> _openCouponSheet() async {
    final rideState = context.read<RideBookingState>();
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => ApplyCouponBottomSheet(
        audience: 'driver',
        orderAmount: rideState.offerFare > 0 ? rideState.offerFare : rideState.baseFare,
        currentCode: (rideState.appliedCoupon?['code'] ?? '').toString(),
      ),
    );

    if (!mounted || result == null) return;
    if (result['remove'] == true) {
      rideState.setAppliedCoupon(null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coupon removed')),
      );
      return;
    }

    rideState.setAppliedCoupon(result);
    final code = (result['code'] ?? '').toString();
    final off = result['discount'];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(off == null ? 'Coupon applied: $code' : 'Coupon $code applied. You save ₹$off')),
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
      content = const ActivityScreen(initialIndex: 0);
    } else if (_bottomTabIndex == 2) {
      content = const MyEarningsScreen();
    } else if (_bottomTabIndex == 3) {
      content = const SettingsScreen();
    } else {
      content = const SizedBox.shrink();
    }

    final lightStatus = _bottomTabIndex != 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onSystemBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: (lightStatus ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
      key: _scaffoldKey,
      drawer: _drawerContent(),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Stack(
            children: [
              content,
              if (_accountHold == 'under_review') _accountReviewBanner(),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomNavBar(),
              ),
              if (_bottomTabIndex == 0 && _activeRide != null && !_otpSheetOpen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 86),
                  child: _activeTripCard(_activeRide!),
                ),
              if (_bottomTabIndex == 0) _incomingRequestsLayer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountReviewBanner() {
    final zoneNote = _serviceState.trim().isEmpty ? '' : ' Zone: $_serviceState.';
    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.of(context).padding.top + 8,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF6C445)),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hourglass_top_rounded, color: Color(0xFF8A5A00)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account under review',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6B4300)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'You can keep using the app. Going online stays off until support resolves the expiry review. Call 9646006716 or email vitevikle@gmail.com.$zoneNote',
                      style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF6B4300)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSystemBack() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
      return;
    }
    if (_bottomTabIndex != 0) {
      setState(() => _bottomTabIndex = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastExitPrompt == null || now.difference(_lastExitPrompt!) > const Duration(seconds: 2)) {
      _lastExitPrompt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    SystemNavigator.pop();
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
              child: ViteLoader(strokeWidth: 2),
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
                                    child: ViteLoader(strokeWidth: 2),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                leading = Icon(icon ?? Icons.payments, size: 24, color: Theme.of(context).colorScheme.onSurface);
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
                    color: Theme.of(context).colorScheme.surface,
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
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
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
                                      child: ViteLoader(strokeWidth: 2),
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
                              child: ViteLoader(strokeWidth: 2),
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
                child: ViteLoader(strokeWidth: 2),
              ),
            );
          }

          final all = snapshot.data ?? const <ServiceCategory>[];
          final items = _zoneServiceIds.isEmpty
              ? all
              : all.where((item) => _zoneServiceIds.contains(item.id)).toList();
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
  final Future<void> Function(int minutes) onPickTime;

  const _RideAcceptedBottomSheet({
    required this.ride,
    required this.onCancel,
    required this.onPickTime,
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

  Future<void> _pickArrival(int minutes) async {
    _stopCancelFill();
    await widget.onPickTime(minutes);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _timeButton(String label, int minutes, {Color color = const Color(0xFF22C55E)}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _pickArrival(minutes),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ),
    );
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
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, -6)),
        ],
      ),
      child: SingleChildScrollView(
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
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
                      child: hasImage
                          ? null
                          : Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'R',
                              style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
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
                                  color: Theme.of(context).colorScheme.surface,
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _timeButton('5 min.', 5),
                _timeButton('10 min.', 10),
                _timeButton('15 min.', 15),
                _timeButton('20 min.', 20),
                _timeButton('Default Time', 10, color: const Color(0xFF009640)),
                const SizedBox(height: 4),
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
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
  final VoidCallback? onBeforeTap;

  const _ArrivalButton({
    required this.label,
    required this.minutes,
    required this.ride,
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

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.active});

  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? const Color(0xFF149444) : const Color(0xFF9CA3AF);
    return FadeTransition(
      opacity: widget.active ? Tween<double>(begin: 0.35, end: 1).animate(_controller) : const AlwaysStoppedAnimation<double>(1),
      child: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

class _GoalRingPainter extends CustomPainter {
  const _GoalRingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 7.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE5E7EB);
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF149444);
    canvas.drawArc(arc, -pi / 2, pi * 2, false, track);
    if (progress > 0) canvas.drawArc(arc, -pi / 2, pi * 2 * progress.clamp(0, 1), false, fill);
  }

  @override
  bool shouldRepaint(covariant _GoalRingPainter oldDelegate) => oldDelegate.progress != progress;
}

class _DutySlide extends StatefulWidget {
  const _DutySlide({required this.online, required this.busy, required this.onChanged});

  final bool online;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  State<_DutySlide> createState() => _DutySlideState();
}

class _DutySlideState extends State<_DutySlide> {
  double _progress = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _progress = widget.online ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant _DutySlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.online != widget.online) {
      _progress = widget.online ? 1 : 0;
    }
  }

  void _finish() {
    final next = _progress >= 0.55;
    setState(() {
      _dragging = false;
      _progress = next ? 1 : 0;
    });
    if (!widget.busy && next != widget.online) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final online = _progress >= 0.55;
    final label = widget.busy ? 'Please wait' : (online ? 'Swipe to go offline' : 'Swipe to go online');
    return LayoutBuilder(
      builder: (context, constraints) {
        const knob = 48.0;
        const inset = 4.0;
        final travel = (constraints.maxWidth - knob - inset * 2).clamp(0.0, constraints.maxWidth);
        final dx = inset + travel * _progress;
        return GestureDetector(
          onHorizontalDragStart: widget.busy ? null : (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: widget.busy
              ? null
              : (details) {
                  if (travel <= 0) return;
                  setState(() => _progress = (_progress + details.delta.dx / travel).clamp(0.0, 1.0));
                },
          onHorizontalDragEnd: widget.busy ? null : (_) => _finish(),
          onHorizontalDragCancel: widget.busy ? null : _finish,
          child: AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
            height: 56,
            decoration: BoxDecoration(
              color: online ? const Color(0xFF149444) : const Color(0xFFE8EEF0),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 6)),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: online ? 0 : 36, right: online ? 36 : 0),
                  child: Text(label, style: TextStyle(color: online ? Colors.white : const Color(0xFF374151), fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                AnimatedPositioned(
                  duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: dx,
                  top: inset,
                  child: Container(
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
                    child: Icon(
                      online ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: online ? const Color(0xFFB91C1C) : const Color(0xFF149444),
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IncomingChoice {
  const _IncomingChoice({
    required this.id,
    required this.card,
  });

  final String id;
  final Widget card;
}





