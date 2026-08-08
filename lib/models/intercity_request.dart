class IntercityRequestModel {
  final String id;
  final String userId;
  final String riderName;
  final String riderImage;
  final String riderPhone;
  final double userRating;
  final int persons;
  final String rideType;
  final bool isScheduled;
  final DateTime? scheduledTime;
  final String pickup;
  final String drop;
  final double pickupLat;
  final double pickupLng;
  final double dropLat;
  final double dropLng;
  final String pickupDate;
  final String pickupTime;
  final String arrivalTime;
  final String vehicleType;
  final double price;
  final double bidPrice;
  final double km;
  final int timeMinutes;
  final DateTime? createdAt;
  final String paymentType;
  final String status;

  IntercityRequestModel({
    required this.id,
    required this.userId,
    required this.riderName,
    required this.riderImage,
    required this.riderPhone,
    required this.userRating,
    required this.persons,
    required this.rideType,
    required this.isScheduled,
    required this.scheduledTime,
    required this.pickup,
    required this.drop,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropLat,
    required this.dropLng,
    required this.pickupDate,
    required this.pickupTime,
    required this.arrivalTime,
    required this.vehicleType,
    required this.price,
    required this.bidPrice,
    required this.km,
    required this.timeMinutes,
    required this.createdAt,
    required this.paymentType,
    required this.status,
  });

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final raw = v.toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static int _toInt(dynamic v) {
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory IntercityRequestModel.fromJson(Map<String, dynamic> json) {
    print('========== FROM JSON ==========');
    print('FROM JSON => $json');
    print('ROOT PICKUP TIME = ${json["pickup_time"]}');
    print('ACCEPTED BID = ${json["accepted_bid"]}');
    
    // Parse accepted_bid.arrival_time if available
    String parsedArrivalTime = '';
    if (json['accepted_bid'] is Map) {
      final acceptedBid = json['accepted_bid'] as Map;
      parsedArrivalTime = (acceptedBid['arrival_time'] ?? acceptedBid['arrivalTime'] ?? '').toString();
      print('ACCEPTED BID ARRIVAL TIME = $parsedArrivalTime');
    } else if (json['selected_bid'] is Map) {
      final selectedBid = json['selected_bid'] as Map;
      parsedArrivalTime = (selectedBid['arrival_time'] ?? selectedBid['arrivalTime'] ?? '').toString();
      print('SELECTED BID ARRIVAL TIME = $parsedArrivalTime');
    }
    
    print('JSON pickup_date => ${json["pickup_date"]}');
    print('JSON pickup_time => ${json["pickup_time"]}');
    print('JSON arrival_time => ${json["arrival_time"]}');
    print('JSON arrivalTime => ${json["arrivalTime"]}');
    print('PARSED ARRIVAL TIME = $parsedArrivalTime');
    print('===============================');

    final userNode = json['user'] is Map ? Map<String, dynamic>.from(json['user'] as Map) : <String, dynamic>{};
    final riderName = (json['rider_name'] ?? userNode['name'] ?? json['name'] ?? 'User').toString();
    final riderImage = (json['rider_image'] ?? userNode['profile_image'] ?? userNode['image'] ?? json['image'] ?? '').toString();
    final userRatingRaw = userNode['rating'] ?? json['user_rating'] ?? json['rider_rating'] ?? json['rating'];
    final userRating = _toDouble(userRatingRaw);
    final personsRaw = json['persons'] ?? json['passengers'] ?? json['passenger_count'] ?? 1;
    final persons = _toInt(personsRaw);

    final rideType = (json['ride_type'] ?? json['rideType'] ?? 'intercity').toString();
    final isScheduledRaw = json['is_scheduled'] ?? json['isScheduled'] ?? false;
    final isScheduled = isScheduledRaw == true || isScheduledRaw.toString().toLowerCase() == 'true';
    final scheduledTime = _toDate(json['scheduled_time'] ?? json['scheduledTime']);

    final result = IntercityRequestModel(
      id: (json['_id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      riderName: riderName,
      riderImage: riderImage,
      riderPhone: (json['rider_phone'] ?? json['phone'] ?? json['mobile'] ?? '').toString(),
      userRating: userRating,
      persons: persons <= 0 ? 1 : persons,
      rideType: rideType.trim().isEmpty ? 'intercity' : rideType,
      isScheduled: isScheduled,
      scheduledTime: scheduledTime,
      pickup: (json['pickup_location'] ?? '').toString(),
      drop: (json['drop_location'] ?? '').toString(),
      pickupLat: _toDouble(json['pickup_lat'] ?? json['pickupLat']),
      pickupLng: _toDouble(json['pickup_lng'] ?? json['pickupLng']),
      dropLat: _toDouble(json['drop_lat'] ?? json['dropLat']),
      dropLng: _toDouble(json['drop_lng'] ?? json['dropLng']),
      pickupDate: (json['pickup_date'] ?? json['pickupDate'] ?? '').toString(),
      pickupTime: (json['pickup_time'] ?? json['pickupTime'] ?? '').toString(),
      arrivalTime: parsedArrivalTime.isNotEmpty ? parsedArrivalTime : (json['arrival_time'] ?? json['arrivalTime'] ?? '').toString(),
      vehicleType: (json['vehicle_type'] ?? '').toString(),
      price: _toDouble(json['total_price']),
      bidPrice: _toDouble(json['bid_price'] ?? json['bidPrice'] ?? json['price']),
      km: _toDouble(json['total_km'] ?? json['totalKm'] ?? json['km']),
      timeMinutes: (() {
        final v = json['total_time'] ?? json['totalTime'] ?? json['time_minutes'] ?? json['timeMinutes'];
        return _toInt(v);
      })(),
      createdAt: _toDate(json['created_at']),
      paymentType: ((json['payment_method'] ?? json['paymentType'] ?? 'Cash').toString()).trim().isEmpty
          ? 'Cash'
          : (json['payment_method'] ?? json['paymentType'] ?? 'Cash').toString(),
      status: (json['status'] ?? '').toString(),
    );

    print('========== MODEL PICKUP DATE/TIME ==========');
    print('MODEL PICKUP DATE => ${result.pickupDate}');
    print('MODEL PICKUP TIME => ${result.pickupTime}');
    print('MODEL ARRIVAL TIME => ${result.arrivalTime}');
    print('============================================');
    return result;
  }

  IntercityRequestModel copyWith({
    String? paymentMethod,
  }) {
    return IntercityRequestModel(
      id: id,
      userId: userId,
      riderName: riderName,
      riderImage: riderImage,
      riderPhone: riderPhone,
      userRating: userRating,
      persons: persons,
      rideType: rideType,
      isScheduled: isScheduled,
      scheduledTime: scheduledTime,
      pickup: pickup,
      drop: drop,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropLat: dropLat,
      dropLng: dropLng,
      pickupDate: pickupDate,
      pickupTime: pickupTime,
      arrivalTime: arrivalTime,
      vehicleType: vehicleType,
      price: price,
      bidPrice: bidPrice,
      km: km,
      timeMinutes: timeMinutes,
      createdAt: createdAt,
      paymentType: paymentMethod ?? paymentType,
      status: status,
    );
  }
}
